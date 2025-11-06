package mobile

import (
	"os"
	"path/filepath"
	"testing"
	"time"
)

func TestParseDddBasic(t *testing.T) {
	parser := NewParser()
	payload := []byte("test payload")

	result, err := parser.ParseDdd(payload, &ParseOptions{Source: "vu"})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if result.Status != statusOk {
		t.Fatalf("expected status ok, got %s", result.Status)
	}
	if result.Json == "" {
		t.Fatalf("expected JSON payload")
	}
}

func TestParseDddVerifyMissingDirectory(t *testing.T) {
	parser := NewParser()
	payload := []byte("test payload")

	_, err := parser.ParseDdd(payload, &ParseOptions{Source: "card", Verify: true, PKSPath: ""})
	if err == nil {
		t.Fatalf("expected error for missing PKS path")
	}
}

func TestParseDddVerificationDirectory(t *testing.T) {
	parser := NewParser()
	payload := []byte("test payload")

	dir := t.TempDir()
	if err := os.WriteFile(filepath.Join(dir, "cert1.pem"), []byte("cert"), 0o600); err != nil {
		t.Fatalf("write file: %v", err)
	}

	result, err := parser.ParseDdd(payload, &ParseOptions{Source: "card", Verify: true, PKSPath: dir})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if result.VerificationLog == "" {
		t.Fatalf("expected verification log")
	}
}

func TestParseDddTimeout(t *testing.T) {
	parser := NewParser()
	payload := make([]byte, 1024)

	_, err := parser.ParseDdd(payload, &ParseOptions{Source: "vu", TimeoutMs: 1})
	if err == nil {
		t.Fatalf("expected timeout error")
	}
	if nativeErr, ok := err.(*NativeError); ok {
		if nativeErr.Code != ErrTimeout {
			t.Fatalf("expected timeout error code, got %s", nativeErr.Code)
		}
	} else {
		t.Fatalf("unexpected error type %T", err)
	}
}

func TestCancelActiveParse(t *testing.T) {
	parser := NewParser()
	payload := make([]byte, 1<<20)

	done := make(chan struct{})
	go func() {
		defer close(done)
		parser.ParseDdd(payload, &ParseOptions{Source: "vu", TimeoutMs: 5000})
	}()

	time.Sleep(10 * time.Millisecond)
	parser.CancelActiveParse()

	select {
	case <-done:
	case <-time.After(2 * time.Second):
		t.Fatalf("parse did not finish after cancel")
	}
}
