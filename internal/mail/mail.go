// Package mail sends transactional email via SMTP, or logs in development.
package mail

import (
	"context"
	"fmt"
	"log/slog"
	"net/smtp"
	"strings"
	"time"

	"petora/internal/config"
)

type Mailer interface {
	Send(ctx context.Context, to, subject, body string) error
}

func New(cfg config.Config) Mailer {
	if cfg.SMTPHost == "" {
		return logMailer{prod: cfg.IsProduction()}
	}
	return &smtpMailer{cfg: cfg}
}

// logMailer is the development fallback. Bodies (which may contain OTPs) are logged ONLY outside production.
type logMailer struct{ prod bool }

func (l logMailer) Send(ctx context.Context, to, subject, body string) error {
	if l.prod {
		slog.WarnContext(ctx, "SMTP not configured; email not sent", "to", to, "subject", subject)
		return fmt.Errorf("smtp not configured")
	}
	slog.InfoContext(ctx, "DEV EMAIL (not sent)", "to", to, "subject", subject, "body", body)
	return nil
}

type smtpMailer struct{ cfg config.Config }

func (m *smtpMailer) Send(ctx context.Context, to, subject, body string) error {
	for _, s := range []string{to, subject} {
		if strings.ContainsAny(s, "\r\n") {
			return fmt.Errorf("header injection attempt")
		}
	}
	msg := fmt.Sprintf("From: %s\r\nTo: %s\r\nSubject: %s\r\nDate: %s\r\nMIME-Version: 1.0\r\nContent-Type: text/plain; charset=UTF-8\r\n\r\n%s",
		m.cfg.SMTPFrom, to, subject, time.Now().UTC().Format(time.RFC1123Z), body)
	addr := fmt.Sprintf("%s:%d", m.cfg.SMTPHost, m.cfg.SMTPPort)
	var auth smtp.Auth
	if m.cfg.SMTPUser != "" {
		auth = smtp.PlainAuth("", m.cfg.SMTPUser, m.cfg.SMTPPass, m.cfg.SMTPHost)
	}
	done := make(chan error, 1)
	go func() { done <- smtp.SendMail(addr, auth, extractAddr(m.cfg.SMTPFrom), []string{to}, []byte(msg)) }()
	select {
	case err := <-done:
		return err
	case <-ctx.Done():
		return ctx.Err()
	case <-time.After(20 * time.Second):
		return fmt.Errorf("smtp timeout")
	}
}

func extractAddr(from string) string {
	if i := strings.Index(from, "<"); i >= 0 {
		return strings.TrimRight(from[i+1:], ">")
	}
	return from
}
