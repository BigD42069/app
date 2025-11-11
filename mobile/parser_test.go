package mobile

import "testing"

func TestParseDddRequiresOptions(t *testing.T) {
	parser := NewParser()
	_, err := parser.ParseDdd([]byte("abc"), nil)
	if err == nil {
		t.Fatalf("expected error for nil options")
	}
	if nativeErr, ok := err.(*NativeError); !ok || nativeErr.Code != ErrInvalidArguments {
		t.Fatalf("expected invalid-arguments error, got %v", err)
	}
}

func TestParseDddRequiresPayload(t *testing.T) {
	parser := NewParser()
	_, err := parser.ParseDdd(nil, &ParseOptions{Source: "card"})
	if err == nil {
		t.Fatalf("expected error for empty payload")
	}
	if nativeErr, ok := err.(*NativeError); !ok || nativeErr.Code != ErrInvalidArguments {
		t.Fatalf("expected invalid-arguments error, got %v", err)
	}
}

func TestParseDddRequiresValidSource(t *testing.T) {
	parser := NewParser()
	_, err := parser.ParseDdd([]byte("abc"), &ParseOptions{Source: "invalid"})
	if err == nil {
		t.Fatalf("expected error for invalid source")
	}
	if nativeErr, ok := err.(*NativeError); !ok || nativeErr.Code != ErrInvalidArguments {
		t.Fatalf("expected invalid-arguments error, got %v", err)
	}
}

func TestCancelWithoutActiveService(t *testing.T) {
	parser := NewParser()
	parser.CancelActiveParse()
}
