package media

import (
	"bytes"
	"image"
	"image/png"
	"testing"
)

func TestProcessImage(t *testing.T) {
	var buf bytes.Buffer
	_ = png.Encode(&buf, image.NewRGBA(image.Rect(0, 0, 2000, 1500)))
	vs, err := ProcessImage(buf.Bytes())
	if err != nil {
		t.Fatal(err)
	}
	if len(vs) != 3 || vs[0].Width != 360 || vs[2].Width != 1600 {
		t.Fatalf("variants: %+v", []int{vs[0].Width, vs[1].Width, vs[2].Width})
	}
	if SniffType(vs[0].Data) != "image/jpeg" {
		t.Fatal("variants must be re-encoded JPEG")
	}
	if _, err := ProcessImage([]byte("<svg onload=alert(1)>")); err != ErrBadType {
		t.Fatal("SVG/HTML must be rejected")
	}
	small := bytes.Buffer{}
	_ = png.Encode(&small, image.NewRGBA(image.Rect(0, 0, 50, 50)))
	if _, err := ProcessImage(small.Bytes()); err == nil {
		t.Fatal("tiny images must be rejected")
	}
	mid := bytes.Buffer{}
	_ = png.Encode(&mid, image.NewRGBA(image.Rect(0, 0, 160, 140)))
	if _, err := ProcessImage(mid.Bytes()); err != nil {
		t.Fatalf("160x140 image should be accepted, got: %v", err)
	}
}

func TestSafeFilename(t *testing.T) {
	for in, want := range map[string]string{"../../etc/passwd": "passwd", "C:\\x\\évil name.pdf": "vil_name.pdf", "": "file"} {
		if got := SafeFilename(in); got != want {
			t.Errorf("SafeFilename(%q)=%q want %q", in, got, want)
		}
	}
}
