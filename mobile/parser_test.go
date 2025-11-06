package mobile

import (
	"encoding/binary"
	"encoding/json"
	"os"
	"path/filepath"
	"testing"
	"time"
)

type decodeResult struct {
	Days []struct {
		Date       string `json:"date"`
		DistanceKm int    `json:"distanceKm"`
		StartOdo   int    `json:"startOdometer"`
		EndOdo     int    `json:"endOdometer"`
	} `json:"days"`
	TotalDays int `json:"totalDays"`
}

func TestParseDddExtractsDaysFromTlv(t *testing.T) {
	parser := NewParser()
	payload := buildTlvPayload([]dayFixture{
		{date: time.Date(2024, 3, 4, 0, 0, 0, 0, time.UTC), start: 1000, end: 1750},
		{date: time.Date(2024, 3, 3, 0, 0, 0, 0, time.UTC), start: 500, end: 650},
	})

	result, err := parser.ParseDdd(payload, &ParseOptions{Source: "vu"})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if result.Status != statusOk {
		t.Fatalf("expected status ok, got %s", result.Status)
	}

	var decoded decodeResult
	if err := json.Unmarshal([]byte(result.Json), &decoded); err != nil {
		t.Fatalf("failed to decode json: %v", err)
	}

	if decoded.TotalDays != 2 {
		t.Fatalf("expected 2 days, got %d", decoded.TotalDays)
	}

	if decoded.Days[0].Date != "2024-03-04" {
		t.Fatalf("expected most recent day first, got %s", decoded.Days[0].Date)
	}
	if decoded.Days[0].DistanceKm != 750 {
		t.Fatalf("unexpected distance for latest day: %d", decoded.Days[0].DistanceKm)
	}
}

func TestParseDddFallbackWithoutTlv(t *testing.T) {
	parser := NewParser()
	payload := buildRawPayload([]dayFixture{
		{date: time.Date(2023, 12, 24, 0, 0, 0, 0, time.UTC), start: 123, end: 456},
	})

	result, err := parser.ParseDdd(payload, &ParseOptions{Source: "card"})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	var decoded decodeResult
	if err := json.Unmarshal([]byte(result.Json), &decoded); err != nil {
		t.Fatalf("failed to decode json: %v", err)
	}

	if decoded.TotalDays != 1 {
		t.Fatalf("expected 1 day, got %d", decoded.TotalDays)
	}
	if decoded.Days[0].DistanceKm != 333 {
		t.Fatalf("unexpected distance: %d", decoded.Days[0].DistanceKm)
	}
}

func TestParseDddVerifyMissingDirectory(t *testing.T) {
	parser := NewParser()
	payload := buildRawPayload([]dayFixture{
		{date: time.Date(2023, 1, 1, 0, 0, 0, 0, time.UTC), start: 0, end: 1},
	})

	_, err := parser.ParseDdd(payload, &ParseOptions{Source: "card", Verify: true, PKSPath: ""})
	if err == nil {
		t.Fatalf("expected error for missing PKS path")
	}
}

func TestParseDddVerificationDirectory(t *testing.T) {
	parser := NewParser()
	payload := buildRawPayload([]dayFixture{
		{date: time.Date(2023, 1, 2, 0, 0, 0, 0, time.UTC), start: 10, end: 20},
	})

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
	payload := make([]byte, 16<<20) // 16 MiB to ensure noticeable work

	_, err := parser.ParseDdd(payload, &ParseOptions{Source: "vu", TimeoutMs: 1})
	if err == nil {
		t.Fatalf("expected timeout error")
	}
	nativeErr, ok := err.(*NativeError)
	if !ok {
		t.Fatalf("unexpected error type %T", err)
	}
	if nativeErr.Code != ErrTimeout {
		t.Fatalf("expected timeout error code, got %s", nativeErr.Code)
	}
}

func TestCancelActiveParse(t *testing.T) {
	parser := NewParser()
	payload := make([]byte, 16<<20)

	done := make(chan *ParseResult, 1)
	errCh := make(chan error, 1)

	go func() {
		res, err := parser.ParseDdd(payload, &ParseOptions{Source: "vu", TimeoutMs: 5000})
		if err != nil {
			errCh <- err
			return
		}
		done <- res
	}()

	time.Sleep(10 * time.Millisecond)
	parser.CancelActiveParse()

	select {
	case res := <-done:
		if res.Status != statusCancelled {
			t.Fatalf("expected cancelled status, got %s", res.Status)
		}
	case err := <-errCh:
		if nativeErr, ok := err.(*NativeError); !ok || nativeErr.Code != ErrCancelled {
			t.Fatalf("unexpected error after cancel: %v", err)
		}
	case <-time.After(2 * time.Second):
		t.Fatalf("parse did not finish after cancel")
	}
}

type dayFixture struct {
	date  time.Time
	start int
	end   int
}

func buildTlvPayload(days []dayFixture) []byte {
	raw := buildRawPayload(days)
	block := append([]byte{0xC3}, make([]byte, 2)...)
	binary.BigEndian.PutUint16(block[1:], uint16(len(raw)))
	block = append(block, raw...)
	return block
}

func buildRawPayload(days []dayFixture) []byte {
	var payload []byte
	for _, day := range days {
		payload = append(payload, encodeDate(day.date)...)    // 2 bytes
		payload = append(payload, encodeUint24(day.start)...) // 3 bytes
		payload = append(payload, encodeUint24(day.end)...)   // 3 bytes
	}
	return payload
}

func encodeDate(date time.Time) []byte {
	year := uint16(date.Year()-tachographEpochYearOffset) << tachographYearBitShift
	month := uint16(date.Month()) << tachographMonthBitShift
	day := uint16(date.Day())
	raw := year | month | day
	buf := make([]byte, 2)
	binary.BigEndian.PutUint16(buf, raw)
	return buf
}

func encodeUint24(value int) []byte {
	v := uint32(value & 0xFFFFFF)
	return []byte{byte(v >> 16), byte(v >> 8), byte(v)}
}
