// Package media validates and transforms uploads: content sniffing, decompression-bomb limits,
// EXIF-stripping re-encode and variant generation.
package media

import (
	"bytes"
	"errors"
	"fmt"
	"image"
	"image/jpeg"
	_ "image/png" // register decoders
	"io"
	"mime/multipart"
	"net/http"
	"path/filepath"
	"regexp"
	"strings"

	"github.com/disintegration/imaging"
	_ "golang.org/x/image/webp"
)

var (
	ErrTooLarge = errors.New("file too large")
	ErrBadType  = errors.New("unsupported file type")
	ErrBadImage = errors.New("image could not be read")
	maxPixels   = 40_000_000 // 40 MP: blocks decompression bombs
	maxSide     = 8000
)

// ReadUpload reads at most limit bytes from a multipart file; larger uploads are rejected, not truncated.
func ReadUpload(f multipart.File, limit int64) ([]byte, error) {
	b, err := io.ReadAll(io.LimitReader(f, limit+1))
	if err != nil {
		return nil, err
	}
	if int64(len(b)) > limit {
		return nil, ErrTooLarge
	}
	if len(b) == 0 {
		return nil, ErrBadImage
	}
	return b, nil
}

// SniffType returns the detected MIME type (never trusts the client-supplied header or file extension).
func SniffType(b []byte) string {
	if len(b) >= 4 && string(b[:4]) == "%PDF" {
		return "application/pdf"
	}
	if len(b) >= 12 && string(b[:4]) == "RIFF" && string(b[8:12]) == "WEBP" {
		return "image/webp"
	}
	return http.DetectContentType(b)
}

type Variant struct {
	Name          string
	Data          []byte
	Width, Height int
}

var variantWidths = []struct {
	name string
	w    int
}{{"thumb", 360}, {"medium", 900}, {"large", 1600}}

// ProcessImage decodes (validating dimensions first), auto-orients, and re-encodes as JPEG at several sizes.
// Re-encoding strips EXIF/GPS metadata and neutralises polyglot payloads.
func ProcessImage(data []byte) ([]Variant, error) {
	switch SniffType(data) {
	case "image/jpeg", "image/png", "image/webp":
	default:
		return nil, ErrBadType
	}
	cfg, _, err := image.DecodeConfig(bytes.NewReader(data))
	if err != nil {
		return nil, ErrBadImage
	}
	if cfg.Width <= 0 || cfg.Height <= 0 || cfg.Width > maxSide || cfg.Height > maxSide || cfg.Width*cfg.Height > maxPixels {
		return nil, fmt.Errorf("%w: dimensions too large", ErrBadImage)
	}
	if cfg.Width < 100 || cfg.Height < 100 {
		return nil, fmt.Errorf("%w: image must be at least 100x100 pixels", ErrBadImage)
	}
	src, err := imaging.Decode(bytes.NewReader(data), imaging.AutoOrientation(true))
	if err != nil {
		return nil, ErrBadImage
	}
	var out []Variant
	for _, v := range variantWidths {
		img := src
		if src.Bounds().Dx() > v.w {
			img = imaging.Resize(src, v.w, 0, imaging.Lanczos)
		}
		var buf bytes.Buffer
		if err := jpeg.Encode(&buf, img, &jpeg.Options{Quality: 82}); err != nil {
			return nil, err
		}
		out = append(out, Variant{Name: v.name, Data: buf.Bytes(), Width: img.Bounds().Dx(), Height: img.Bounds().Dy()})
	}
	return out, nil
}

// Square returns a centre-cropped square JPEG (used for seller logos).
func Square(data []byte, size int) ([]byte, error) {
	switch SniffType(data) {
	case "image/jpeg", "image/png", "image/webp":
	default:
		return nil, ErrBadType
	}
	cfg, _, err := image.DecodeConfig(bytes.NewReader(data))
	if err != nil || cfg.Width*cfg.Height > maxPixels {
		return nil, ErrBadImage
	}
	src, err := imaging.Decode(bytes.NewReader(data), imaging.AutoOrientation(true))
	if err != nil {
		return nil, ErrBadImage
	}
	var buf bytes.Buffer
	if err := jpeg.Encode(&buf, imaging.Fill(src, size, size, imaging.Center, imaging.Lanczos), &jpeg.Options{Quality: 85}); err != nil {
		return nil, err
	}
	return buf.Bytes(), nil
}

var unsafeName = regexp.MustCompile(`[^A-Za-z0-9._-]+`)

// SafeFilename keeps only a display-safe base name (never used as a storage path).
func SafeFilename(name string) string {
	name = filepath.Base(strings.ReplaceAll(name, "\\", "/"))
	name = unsafeName.ReplaceAllString(name, "_")
	name = strings.Trim(name, "._")
	if name == "" {
		return "file"
	}
	if len(name) > 100 {
		name = name[:100]
	}
	return name
}
