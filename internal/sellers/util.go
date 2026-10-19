package sellers

import (
	"bytes"
	"crypto/sha256"
	"encoding/hex"
	"io"
)

func bytesReader(b []byte) io.Reader { return bytes.NewReader(b) }
func sha256Hex(b []byte) string      { h := sha256.Sum256(b); return hex.EncodeToString(h[:]) }
