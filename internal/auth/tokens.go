package auth

import (
	"errors"
	"time"

	"github.com/golang-jwt/jwt/v5"

	"petora/internal/security"
)

type claims struct {
	SessionID string `json:"sid"`
	jwt.RegisteredClaims
}

func (s *Service) signAccess(userID, sessionID string) (string, time.Time, error) {
	exp := time.Now().Add(s.cfg.AccessTTL)
	c := claims{SessionID: sessionID, RegisteredClaims: jwt.RegisteredClaims{
		Subject: userID, ExpiresAt: jwt.NewNumericDate(exp), IssuedAt: jwt.NewNumericDate(time.Now()), Issuer: "petora"}}
	tok, err := jwt.NewWithClaims(jwt.SigningMethodHS256, c).SignedString([]byte(s.cfg.JWTSecret))
	return tok, exp, err
}

// parseAccess verifies signature, algorithm, issuer and expiry.
func (s *Service) parseAccess(raw string) (userID, sessionID string, err error) {
	var c claims
	tok, err := jwt.ParseWithClaims(raw, &c, func(t *jwt.Token) (any, error) { return []byte(s.cfg.JWTSecret), nil },
		jwt.WithValidMethods([]string{"HS256"}), jwt.WithIssuer("petora"), jwt.WithExpirationRequired())
	if err != nil || !tok.Valid || c.Subject == "" || c.SessionID == "" {
		return "", "", errors.New("invalid token")
	}
	return c.Subject, c.SessionID, nil
}

func randomCSRF() string { return security.RandomToken(24) }
