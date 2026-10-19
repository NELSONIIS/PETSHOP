package payments

import (
	"context"
	"encoding/json"
	"time"

	"petora/internal/database"
	"petora/internal/httpx"
)

type Invoice struct {
	ID            string          `json:"id"`
	Number        string          `json:"number"`
	PaymentID     string          `json:"payment_id"`
	BillToName    string          `json:"bill_to_name"`
	BillToEmail   string          `json:"bill_to_email"`
	Lines         json.RawMessage `json:"lines"`
	SubtotalMinor int64           `json:"subtotal_minor"`
	TaxMinor      int64           `json:"tax_minor"`
	TotalMinor    int64           `json:"total_minor"`
	Currency      string          `json:"currency"`
	IssuedAt      time.Time       `json:"issued_at"`
}

const invCols = `id, number, payment_id, bill_to_name, bill_to_email, lines, subtotal_minor, tax_minor, total_minor, currency, issued_at`

func (s *Service) ListInvoices(ctx context.Context, userID string, pg httpx.Page) ([]Invoice, int, error) {
	var total int
	if err := s.db.QueryRow(ctx, `SELECT count(*) FROM invoices WHERE user_id=$1`, userID).Scan(&total); err != nil {
		return nil, 0, err
	}
	rows, err := s.db.Query(ctx, `SELECT `+invCols+` FROM invoices WHERE user_id=$1 ORDER BY issued_at DESC LIMIT $2 OFFSET $3`, userID, pg.PerPage, pg.Offset)
	if err != nil {
		return nil, 0, err
	}
	defer rows.Close()
	out := []Invoice{}
	for rows.Next() {
		var i Invoice
		if err := rows.Scan(&i.ID, &i.Number, &i.PaymentID, &i.BillToName, &i.BillToEmail, &i.Lines, &i.SubtotalMinor, &i.TaxMinor, &i.TotalMinor, &i.Currency, &i.IssuedAt); err != nil {
			return nil, 0, err
		}
		out = append(out, i)
	}
	return out, total, rows.Err()
}

func (s *Service) GetInvoice(ctx context.Context, userID, id string) (*Invoice, error) {
	var i Invoice
	err := s.db.QueryRow(ctx, `SELECT `+invCols+` FROM invoices WHERE id::text=$1 AND user_id=$2`, id, userID).
		Scan(&i.ID, &i.Number, &i.PaymentID, &i.BillToName, &i.BillToEmail, &i.Lines, &i.SubtotalMinor, &i.TaxMinor, &i.TotalMinor, &i.Currency, &i.IssuedAt)
	if database.IsNoRows(err) {
		return nil, httpx.NotFound("Invoice")
	}
	return &i, err
}
