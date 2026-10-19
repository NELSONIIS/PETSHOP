package httpx

import (
	"net/mail"
	"regexp"
	"strings"
	"unicode/utf8"
)

// V accumulates field errors; call Err() at the end.
type V struct{ errs []FieldError }

func (v *V) Add(field, msg string) { v.errs = append(v.errs, FieldError{field, msg}) }
func (v *V) Err() error {
	if len(v.errs) == 0 {
		return nil
	}
	return Invalid(v.errs...)
}
func (v *V) Required(field, val string) bool {
	if strings.TrimSpace(val) == "" {
		v.Add(field, "is required")
		return false
	}
	return true
}
func (v *V) Length(field, val string, min, max int) {
	n := utf8.RuneCountInString(strings.TrimSpace(val))
	if n < min || n > max {
		v.Add(field, "must be between "+itoa(min)+" and "+itoa(max)+" characters")
	}
}
func (v *V) Email(field, val string) {
	a, err := mail.ParseAddress(val)
	if err != nil || a.Address != val || len(val) > 254 {
		v.Add(field, "must be a valid email address")
	}
}

var phoneRe = regexp.MustCompile(`^\+?[0-9]{10,15}$`)

func (v *V) Phone(field, val string) {
	if !phoneRe.MatchString(val) {
		v.Add(field, "must be a valid phone number (10-15 digits)")
	}
}
func (v *V) OneOf(field, val string, allowed ...string) {
	for _, a := range allowed {
		if a == val {
			return
		}
	}
	v.Add(field, "must be one of: "+strings.Join(allowed, ", "))
}
func (v *V) Password(field, val string) {
	if utf8.RuneCountInString(val) < 10 || len(val) > 128 {
		v.Add(field, "must be 10-128 characters")
		return
	}
	var letter, digit bool
	for _, r := range val {
		switch {
		case r >= '0' && r <= '9':
			digit = true
		case (r >= 'a' && r <= 'z') || (r >= 'A' && r <= 'Z') || r > 127:
			letter = true
		}
	}
	if !letter || !digit {
		v.Add(field, "must contain at least one letter and one number")
	}
}
func (v *V) Range(field string, val, min, max int64) {
	if val < min || val > max {
		v.Add(field, "must be between "+itoa64(min)+" and "+itoa64(max))
	}
}

func itoa(i int) string { return itoa64(int64(i)) }
func itoa64(i int64) string {
	if i == 0 {
		return "0"
	}
	neg := i < 0
	if neg {
		i = -i
	}
	var b [20]byte
	p := len(b)
	for i > 0 {
		p--
		b[p] = byte('0' + i%10)
		i /= 10
	}
	if neg {
		p--
		b[p] = '-'
	}
	return string(b[p:])
}
