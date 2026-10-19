// Package cache wraps Redis for caching, rate limiting and job wake-ups.
// Redis is an optimisation only: every method degrades to a no-op/allow when Redis is unavailable
// so that outages never block the primary Postgres-backed business logic.
package cache

import (
	"context"
	"encoding/json"
	"errors"
	"time"

	"github.com/redis/go-redis/v9"
)

type Cache struct{ rdb *redis.Client }

// New returns a Cache; an empty url yields a disabled (no-op) cache for dev/test.
func New(url string) (*Cache, error) {
	if url == "" {
		return &Cache{}, nil
	}
	opt, err := redis.ParseURL(url)
	if err != nil {
		return nil, err
	}
	opt.DialTimeout, opt.ReadTimeout, opt.WriteTimeout = 2*time.Second, 500*time.Millisecond, 500*time.Millisecond
	return &Cache{rdb: redis.NewClient(opt)}, nil
}

func (c *Cache) Enabled() bool { return c != nil && c.rdb != nil }
func (c *Cache) Close() {
	if c.Enabled() {
		_ = c.rdb.Close()
	}
}
func (c *Cache) Ping(ctx context.Context) error {
	if !c.Enabled() {
		return nil
	}
	return c.rdb.Ping(ctx).Err()
}

// GetJSON loads key into dst; returns false on miss or any Redis error.
func (c *Cache) GetJSON(ctx context.Context, key string, dst any) bool {
	if !c.Enabled() {
		return false
	}
	b, err := c.rdb.Get(ctx, key).Bytes()
	if err != nil {
		return false
	}
	return json.Unmarshal(b, dst) == nil
}

func (c *Cache) SetJSON(ctx context.Context, key string, v any, ttl time.Duration) {
	if !c.Enabled() {
		return
	}
	if b, err := json.Marshal(v); err == nil {
		_ = c.rdb.Set(ctx, key, b, ttl).Err()
	}
}

func (c *Cache) Del(ctx context.Context, keys ...string) {
	if c.Enabled() && len(keys) > 0 {
		_ = c.rdb.Del(ctx, keys...).Err()
	}
}

// DelPrefix removes every key with the prefix (SCAN based; used for listing-cache invalidation).
func (c *Cache) DelPrefix(ctx context.Context, prefix string) {
	if !c.Enabled() {
		return
	}
	iter := c.rdb.Scan(ctx, 0, prefix+"*", 200).Iterator()
	var keys []string
	for iter.Next(ctx) {
		keys = append(keys, iter.Val())
		if len(keys) >= 200 {
			_ = c.rdb.Del(ctx, keys...).Err()
			keys = keys[:0]
		}
	}
	if len(keys) > 0 {
		_ = c.rdb.Del(ctx, keys...).Err()
	}
}

var rateScript = redis.NewScript(`
local c = redis.call('INCR', KEYS[1])
if c == 1 then redis.call('PEXPIRE', KEYS[1], ARGV[1]) end
local ttl = redis.call('PTTL', KEYS[1])
return {c, ttl}`)

// Allow implements a fixed-window counter. Fails open if Redis is down.
func (c *Cache) Allow(ctx context.Context, key string, limit int, window time.Duration) (allowed bool, retryAfter time.Duration) {
	if !c.Enabled() {
		return true, 0
	}
	res, err := rateScript.Run(ctx, c.rdb, []string{"rl:" + key}, window.Milliseconds()).Int64Slice()
	if err != nil || len(res) != 2 {
		return true, 0
	}
	if res[0] > int64(limit) {
		return false, time.Duration(res[1]) * time.Millisecond
	}
	return true, 0
}

// TryLock acquires a short-lived lock; returns a release func. Used only for coordination (never as truth).
func (c *Cache) TryLock(ctx context.Context, key string, ttl time.Duration) (release func(), ok bool) {
	if !c.Enabled() {
		return func() {}, true
	}
	ok, err := c.rdb.SetNX(ctx, "lock:"+key, "1", ttl).Result()
	if err != nil {
		return func() {}, true
	}
	if !ok {
		return nil, false
	}
	return func() { _ = c.rdb.Del(context.Background(), "lock:"+key).Err() }, true
}

// Notify/Wait provide a wake-up hint for workers; the jobs table remains authoritative.
func (c *Cache) Notify(ctx context.Context, channel string) {
	if c.Enabled() {
		_ = c.rdb.Publish(ctx, channel, "1").Err()
	}
}

func (c *Cache) Subscribe(ctx context.Context, channel string) (<-chan struct{}, error) {
	if !c.Enabled() {
		return nil, errors.New("cache disabled")
	}
	sub := c.rdb.Subscribe(ctx, channel)
	out := make(chan struct{}, 1)
	go func() {
		defer sub.Close()
		defer close(out)
		for {
			select {
			case <-ctx.Done():
				return
			case _, ok := <-sub.Channel():
				if !ok {
					return
				}
				select {
				case out <- struct{}{}:
				default:
				}
			}
		}
	}()
	return out, nil
}
