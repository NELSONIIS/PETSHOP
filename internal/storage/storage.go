// Package storage abstracts object storage. Public media (pet photos) and private files
// (seller verification documents) live in separate buckets/directories with different access paths.
package storage

import (
	"context"
	"errors"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"strings"

	"github.com/minio/minio-go/v7"
	"github.com/minio/minio-go/v7/pkg/credentials"

	"petora/internal/config"
)

type Bucket string

const (
	Public  Bucket = "public"
	Private Bucket = "private"
)

var ErrNotFound = errors.New("storage: object not found")

type Store interface {
	Put(ctx context.Context, b Bucket, key string, r io.Reader, size int64, contentType string) error
	Get(ctx context.Context, b Bucket, key string) (io.ReadCloser, error)
	Delete(ctx context.Context, b Bucket, key string) error
	// PublicURL returns the URL for a key in the Public bucket.
	PublicURL(key string) string
	// PublicHandler serves public media when the driver is local (nil for S3/CDN).
	PublicHandler() http.Handler
}

func New(cfg config.Config) (Store, error) {
	switch cfg.StorageDriver {
	case "local":
		return NewLocal(cfg.StorageLocalPath, cfg.PublicMediaURL)
	case "s3":
		return NewS3(cfg)
	}
	return nil, fmt.Errorf("unknown STORAGE_DRIVER %q", cfg.StorageDriver)
}

// ---- local filesystem ----

type Local struct {
	root      string
	publicURL string
}

func NewLocal(root, publicURL string) (*Local, error) {
	abs, err := filepath.Abs(root)
	if err != nil {
		return nil, err
	}
	for _, b := range []Bucket{Public, Private} {
		if err := os.MkdirAll(filepath.Join(abs, string(b)), 0o750); err != nil {
			return nil, err
		}
	}
	return &Local{root: abs, publicURL: publicURL}, nil
}

// path resolves a key safely: keys are generated server-side, but we still refuse traversal.
func (l *Local) path(b Bucket, key string) (string, error) {
	if key == "" || strings.Contains(key, "..") || strings.HasPrefix(key, "/") || strings.ContainsRune(key, 0) {
		return "", errors.New("invalid storage key")
	}
	p := filepath.Join(l.root, string(b), filepath.FromSlash(key))
	if !strings.HasPrefix(p, filepath.Join(l.root, string(b))+string(os.PathSeparator)) {
		return "", errors.New("invalid storage key")
	}
	return p, nil
}

func (l *Local) Put(_ context.Context, b Bucket, key string, r io.Reader, _ int64, _ string) error {
	p, err := l.path(b, key)
	if err != nil {
		return err
	}
	if err := os.MkdirAll(filepath.Dir(p), 0o750); err != nil {
		return err
	}
	tmp := p + ".tmp"
	f, err := os.OpenFile(tmp, os.O_CREATE|os.O_WRONLY|os.O_TRUNC, 0o640)
	if err != nil {
		return err
	}
	if _, err := io.Copy(f, r); err != nil {
		f.Close()
		os.Remove(tmp)
		return err
	}
	if err := f.Close(); err != nil {
		return err
	}
	return os.Rename(tmp, p)
}

func (l *Local) Get(_ context.Context, b Bucket, key string) (io.ReadCloser, error) {
	p, err := l.path(b, key)
	if err != nil {
		return nil, err
	}
	f, err := os.Open(p)
	if errors.Is(err, os.ErrNotExist) {
		return nil, ErrNotFound
	}
	return f, err
}

func (l *Local) Delete(_ context.Context, b Bucket, key string) error {
	p, err := l.path(b, key)
	if err != nil {
		return err
	}
	if err := os.Remove(p); err != nil && !errors.Is(err, os.ErrNotExist) {
		return err
	}
	return nil
}

func (l *Local) PublicURL(key string) string { return l.publicURL + "/" + key }

// PublicHandler serves ONLY the public bucket, never directory listings, immutable cache headers.
func (l *Local) PublicHandler() http.Handler {
	root := filepath.Join(l.root, string(Public))
	fs := http.FileServer(noListFS{http.Dir(root)})
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Access-Control-Allow-Origin", "*")
		w.Header().Set("Cache-Control", "public, max-age=31536000, immutable")
		w.Header().Set("X-Content-Type-Options", "nosniff")
		w.Header().Set("Content-Security-Policy", "default-src 'none'; img-src 'self'")
		fs.ServeHTTP(w, r)
	})
}

type noListFS struct{ fs http.FileSystem }

func (n noListFS) Open(name string) (http.File, error) {
	f, err := n.fs.Open(name)
	if err != nil {
		return nil, err
	}
	if st, err := f.Stat(); err != nil || st.IsDir() {
		f.Close()
		return nil, os.ErrNotExist
	}
	return f, nil
}

// ---- S3-compatible (AWS S3, Cloudflare R2, MinIO, DigitalOcean Spaces…) ----

type S3 struct {
	c         *minio.Client
	pub, priv string
	publicURL string
}

func NewS3(cfg config.Config) (*S3, error) {
	c, err := minio.New(cfg.S3Endpoint, &minio.Options{
		Creds: credentials.NewStaticV4(cfg.S3AccessKey, cfg.S3SecretKey, ""), Secure: cfg.S3UseSSL, Region: cfg.S3Region})
	if err != nil {
		return nil, err
	}
	return &S3{c: c, pub: cfg.S3PublicBucket, priv: cfg.S3PrivateBucket, publicURL: cfg.PublicMediaURL}, nil
}

func (s *S3) bucket(b Bucket) string {
	if b == Private {
		return s.priv
	}
	return s.pub
}

func (s *S3) Put(ctx context.Context, b Bucket, key string, r io.Reader, size int64, ct string) error {
	_, err := s.c.PutObject(ctx, s.bucket(b), key, r, size, minio.PutObjectOptions{ContentType: ct})
	return err
}

func (s *S3) Get(ctx context.Context, b Bucket, key string) (io.ReadCloser, error) {
	o, err := s.c.GetObject(ctx, s.bucket(b), key, minio.GetObjectOptions{})
	if err != nil {
		return nil, err
	}
	if _, err := o.Stat(); err != nil {
		o.Close()
		if minio.ToErrorResponse(err).Code == "NoSuchKey" {
			return nil, ErrNotFound
		}
		return nil, err
	}
	return o, nil
}

func (s *S3) Delete(ctx context.Context, b Bucket, key string) error {
	return s.c.RemoveObject(ctx, s.bucket(b), key, minio.RemoveObjectOptions{})
}
func (s *S3) PublicURL(key string) string { return s.publicURL + "/" + key }
func (s *S3) PublicHandler() http.Handler { return nil }
