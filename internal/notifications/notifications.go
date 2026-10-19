// Package notifications creates in-app notifications and enqueues email via the durable job queue.
package notifications

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"sort"
	"text/template"

	"petora/internal/database"
	"petora/internal/jobs"
	"petora/internal/mail"
)

type Service struct{ db *database.DB }

func New(db *database.DB) *Service { return &Service{db: db} }

// Create inserts an in-app notification using q (pass the surrounding tx when there is one).
func Create(ctx context.Context, q database.Querier, userID, kind, title, body string, data map[string]any) error {
	b, _ := json.Marshal(data)
	if data == nil {
		b = []byte("{}")
	}
	_, err := q.Exec(ctx, `INSERT INTO notifications (user_id, kind, title, body, data) VALUES ($1,$2,$3,$4,$5)`,
		userID, kind, title, body, b)
	return err
}

type EmailJob struct {
	To       string            `json:"to"`
	Template string            `json:"template"`
	Vars     map[string]string `json:"vars"`
}

// EnqueueEmail records an email in the outbox (atomic with the caller's transaction when q is a Tx).
func EnqueueEmail(ctx context.Context, q database.Querier, to, template string, vars map[string]string, opts ...jobs.Option) error {
	return jobs.Enqueue(ctx, q, "email.send", EmailJob{To: to, Template: template, Vars: vars}, opts...)
}

type tpl struct{ subject, body string }

// Built-in defaults; admins may override any of them in notification_templates (channel = 'email').
var defaults = map[string]tpl{
	"email_verify":           {"Verify your PETORA email", "Hi {{.name}},\n\nYour PETORA verification code is {{.code}}. It expires in 15 minutes.\n\nIf you did not create an account, ignore this email."},
	"password_reset":         {"Reset your PETORA password", "Hi {{.name}},\n\nUse this code to reset your password: {{.code}}\nIt expires in 15 minutes. If you did not request this, you can ignore this email."},
	"enquiry_received":       {"New enquiry on {{.listing}}", "Hi {{.name}},\n\nYou have a new enquiry about \"{{.listing}}\".\nOpen your PETORA seller inbox to respond: {{.url}}"},
	"enquiry_reply":          {"{{.seller}} replied to your enquiry", "Hi {{.name}},\n\nYou have a new reply about \"{{.listing}}\": {{.url}}"},
	"subscription_activated": {"Your PETORA {{.plan}} plan is active", "Hi {{.name}},\n\nYour {{.plan}} plan is active until {{.until}}.\nInvoice: {{.invoice}}"},
	"subscription_expiring":  {"Your PETORA plan expires {{.when}}", "Hi {{.name}},\n\nYour {{.plan}} plan ends on {{.until}}. Renew to keep your benefits: {{.url}}"},
	"subscription_expired":   {"Your PETORA plan has expired", "Hi {{.name}},\n\nYour {{.plan}} plan has expired. {{.detail}}\nRenew: {{.url}}"},
	"payment_failed":         {"Your PETORA payment did not go through", "Hi {{.name}},\n\nYour payment for the {{.plan}} plan failed. You have not been charged for an active plan. Try again: {{.url}}"},
	"listing_approved":       {"Your listing is live", "Hi {{.name}},\n\n\"{{.listing}}\" has been approved and is now visible on PETORA."},
	"listing_rejected":       {"Your listing needs changes", "Hi {{.name}},\n\n\"{{.listing}}\" was not approved.\nReason: {{.reason}}\nYou can edit and resubmit it."},
	"seller_verified":        {"Your seller account is verified", "Hi {{.name}},\n\nYour seller verification was approved. You can now subscribe and publish listings."},
	"seller_rejected":        {"Your seller verification needs attention", "Hi {{.name}},\n\nWe could not approve your verification.\nReason: {{.reason}}"},
	"refund_processed":       {"Your PETORA refund", "Hi {{.name}},\n\nA refund of {{.amount}} for invoice {{.invoice}} has been issued."},
	"support_contact":        {"[PETORA support] {{.subject}}", "{{.body}}"},
	"account_deleted":        {"Your PETORA account was deleted", "Hi {{.name}},\n\nYour account and personal data have been deleted as requested."},
}

// Render picks the admin-edited template if present, else the built-in default.
func Render(ctx context.Context, db *database.DB, key string, vars map[string]string) (subject, body string, err error) {
	t, ok := defaults[key]
	var subj, bd string
	if e := db.QueryRow(ctx, `SELECT subject, body FROM notification_templates WHERE key=$1 AND channel='email' AND is_active`, key).Scan(&subj, &bd); e == nil {
		t = tpl{subj, bd}
	} else if !ok {
		return "", "", errors.New("unknown email template: " + key)
	}
	render := func(s string) (string, error) {
		tt, err := template.New("m").Option("missingkey=zero").Parse(s)
		if err != nil {
			return "", err
		}
		var buf bytes.Buffer
		if err := tt.Execute(&buf, vars); err != nil {
			return "", err
		}
		return buf.String(), nil
	}
	if subject, err = render(t.subject); err != nil {
		return
	}
	body, err = render(t.body)
	return
}

// EmailHandler is the job handler for kind "email.send".
func EmailHandler(db *database.DB, m mail.Mailer) jobs.Handler {
	return func(ctx context.Context, payload json.RawMessage) error {
		var j EmailJob
		if err := json.Unmarshal(payload, &j); err != nil {
			return err
		}
		subject, body, err := Render(ctx, db, j.Template, j.Vars)
		if err != nil {
			return err
		}
		return m.Send(ctx, j.To, subject, body)
	}
}

func TemplateKeys() []string {
	out := make([]string, 0, len(defaults))
	for k := range defaults {
		out = append(out, k)
	}
	sort.Strings(out)
	return out
}

func IsTemplateKey(k string) bool { _, ok := defaults[k]; return ok }

// ValidateTemplate parses subject and body so admins cannot save a template that would fail at send time.
func ValidateTemplate(subject, body string) error {
	for _, s := range []string{subject, body} {
		if _, err := template.New("v").Parse(s); err != nil {
			return err
		}
	}
	return nil
}
