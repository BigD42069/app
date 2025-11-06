package mobile

import (
	"context"
	"crypto/sha256"
	"encoding/binary"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"sync"
	"time"
)

const (
	statusOk        = "ok"
	statusError     = "error"
	statusCancelled = "cancelled"

	tachographTagMin                 = 0xC0
	tachographTagMax                 = 0xEF
	tachographRecordLength           = 8
	tachographRecordAdvance          = 6
	maxReasonableDistanceKm          = 2000
	tachographEpochYearOffset        = 1985
	tachographYearBitShift           = 9
	tachographMonthBitShift          = 5
	tachographYearMask        uint16 = 0xFE00
	tachographMonthMask       uint16 = 0x01E0
	tachographDayMask         uint16 = 0x001F
)

// Parser kapselt die Analyse einer DDD-Datei und verwaltet einen optionalen
// Cancel-/Timeout-Kontext, damit gomobile-Bindings Cancel-Requests sauber
// durchreichen können.
type Parser struct {
	mu     sync.Mutex
	cancel context.CancelFunc
}

// NewParser erzeugt eine neue Parser-Instanz.
func NewParser() *Parser {
	return &Parser{}
}

// ParseResult beschreibt die Ergebnisse des nativen Parse-Laufs.
type ParseResult struct {
	Status          string
	Json            string
	VerificationLog string
	ErrorDetails    string
}

// ParseOptions enthält optionale Parameter für die Analyse.
type ParseOptions struct {
	Source    string
	Verify    bool
	PKSPath   string
	TimeoutMs int
}

type tachographDayPayload struct {
	Date          string `json:"date"`
	StartOdometer int    `json:"startOdometer"`
	EndOdometer   int    `json:"endOdometer"`
	DistanceKm    int    `json:"distanceKm"`
}

type dayAccumulator struct {
	days map[time.Time]tachographDayPayload
}

func newDayAccumulator() *dayAccumulator {
	return &dayAccumulator{days: make(map[time.Time]tachographDayPayload)}
}

func (a *dayAccumulator) add(day time.Time, start, end int) {
	distance := distanceKm(start, end)
	if distance <= 0 || distance > maxReasonableDistanceKm {
		return
	}

	payload := tachographDayPayload{
		Date:          day.Format("2006-01-02"),
		StartOdometer: start,
		EndOdometer:   end,
		DistanceKm:    distance,
	}

	existing, ok := a.days[day]
	if !ok || payload.DistanceKm > existing.DistanceKm {
		a.days[day] = payload
	}
}

func (a *dayAccumulator) toSlice() []tachographDayPayload {
	result := make([]tachographDayPayload, 0, len(a.days))
	for _, day := range a.days {
		result = append(result, day)
	}
	sort.Slice(result, func(i, j int) bool {
		// Sortiere absteigend nach Datum, damit der aktuellste Tag zuerst kommt.
		return result[i].Date > result[j].Date
	})
	return result
}

// ParseDdd führt eine Analyse der DDD-Datei durch und liefert strukturierte
// Tagesinformationen zurück. Die Implementierung spiegelt den bestehenden
// Dart-Parser wider, sodass die Flutter-App dieselbe Logik erhält.
func (p *Parser) ParseDdd(payload []byte, opts *ParseOptions) (*ParseResult, error) {
	if len(payload) == 0 {
		return nil, &NativeError{Code: ErrInvalidArguments, Message: "payload must not be empty"}
	}

	if opts == nil {
		return nil, &NativeError{Code: ErrInvalidArguments, Message: "options must be provided"}
	}

	if opts.Source != "vu" && opts.Source != "card" {
		return nil, &NativeError{Code: ErrInvalidArguments, Message: "source must be either 'vu' or 'card'"}
	}

	if opts.Verify && opts.PKSPath == "" {
		return nil, &NativeError{Code: ErrInvalidArguments, Message: "pksPath is required when verify is true"}
	}

	ctx, cancel := context.WithCancel(context.Background())
	if opts.TimeoutMs > 0 {
		ctx, cancel = context.WithTimeout(ctx, time.Duration(opts.TimeoutMs)*time.Millisecond)
	}

	p.mu.Lock()
	if p.cancel != nil {
		p.cancel()
	}
	p.cancel = cancel
	p.mu.Unlock()

	defer func() {
		cancel()
		p.mu.Lock()
		p.cancel = nil
		p.mu.Unlock()
	}()

	if err := ctx.Err(); err != nil {
		return nil, translateContextError(err)
	}

	days, err := decodeTachographDays(ctx, payload)
	if err != nil {
		if errors.Is(err, context.Canceled) {
			return &ParseResult{Status: statusCancelled}, nil
		}
		if errors.Is(err, context.DeadlineExceeded) {
			return nil, &NativeError{Code: ErrTimeout, Message: "parse operation timed out"}
		}
		return nil, &NativeError{Code: ErrParser, Message: err.Error()}
	}

	result := map[string]any{
		"bytes":       len(payload),
		"source":      opts.Source,
		"sha256":      sha256Digest(payload),
		"generatedAt": time.Now().UTC().Format(time.RFC3339Nano),
		"days":        days,
		"totalDays":   len(days),
	}

	if opts.Verify {
		log, err := generateVerificationLog(ctx, opts.PKSPath)
		if err != nil {
			if errors.Is(err, context.Canceled) {
				return &ParseResult{Status: statusCancelled}, nil
			}
			if errors.Is(err, os.ErrNotExist) {
				return nil, &NativeError{Code: ErrInvalidArguments, Message: fmt.Sprintf("PKS path %q does not exist", opts.PKSPath)}
			}
			return &ParseResult{
				Status:       statusError,
				ErrorDetails: fmt.Sprintf("verification failed: %v", err),
			}, nil
		}
		result["verified"] = true
		result["pksPath"] = opts.PKSPath
		result["verification"] = log
		return marshalResult(statusOk, result, log)
	}

	return marshalResult(statusOk, result, "")
}

// CancelActiveParse stoppt laufende Parse-Operationen.
func (p *Parser) CancelActiveParse() {
	p.mu.Lock()
	defer p.mu.Unlock()
	if p.cancel != nil {
		p.cancel()
		p.cancel = nil
	}
}

func decodeTachographDays(ctx context.Context, payload []byte) ([]tachographDayPayload, error) {
	if err := ctx.Err(); err != nil {
		return nil, err
	}

	accumulator := newDayAccumulator()

	blocks, ok, err := parseTLVBlocks(ctx, payload)
	if err != nil {
		return nil, err
	}

	if ok && len(blocks) > 0 {
		for _, block := range blocks {
			if err := extractDays(ctx, block, accumulator); err != nil {
				return nil, err
			}
		}
	} else {
		if err := extractDays(ctx, payload, accumulator); err != nil {
			return nil, err
		}
	}

	return accumulator.toSlice(), nil
}

func parseTLVBlocks(ctx context.Context, data []byte) ([][]byte, bool, error) {
	var blocks [][]byte
	index := 0

	for index+3 <= len(data) {
		if err := ctx.Err(); err != nil {
			return nil, false, err
		}

		tag := data[index]
		length := int(binary.BigEndian.Uint16(data[index+1 : index+3]))
		index += 3

		if length <= 0 || index+length > len(data) {
			return nil, false, nil
		}

		if tag >= tachographTagMin && tag <= tachographTagMax {
			block := append([]byte(nil), data[index:index+length]...)
			blocks = append(blocks, block)
		}

		index += length
	}

	if index != len(data) {
		return nil, false, nil
	}

	return blocks, true, nil
}

func extractDays(ctx context.Context, data []byte, accumulator *dayAccumulator) error {
	if len(data) < tachographRecordLength {
		return nil
	}

	for i := 0; i <= len(data)-tachographRecordLength; {
		if err := ctx.Err(); err != nil {
			return err
		}

		rawDate := binary.BigEndian.Uint16(data[i : i+2])
		date, ok := decodeDate(rawDate)
		if !ok {
			i++
			continue
		}

		start, ok := readUint24(data, i+2)
		if !ok {
			i++
			continue
		}
		end, ok := readUint24(data, i+5)
		if !ok {
			i++
			continue
		}

		accumulator.add(date, int(start), int(end))
		i += tachographRecordLength
	}

	return nil
}

func decodeDate(raw uint16) (time.Time, bool) {
	year := int((raw&tachographYearMask)>>tachographYearBitShift) + tachographEpochYearOffset
	month := int((raw & tachographMonthMask) >> tachographMonthBitShift)
	day := int(raw & tachographDayMask)

	if month < 1 || month > 12 {
		return time.Time{}, false
	}
	if day < 1 || day > 31 {
		return time.Time{}, false
	}

	date := time.Date(year, time.Month(month), day, 0, 0, 0, 0, time.UTC)
	if int(date.Month()) != month || date.Day() != day {
		return time.Time{}, false
	}

	return date, true
}

func readUint24(data []byte, offset int) (uint32, bool) {
	if offset+3 > len(data) {
		return 0, false
	}
	value := uint32(data[offset])<<16 | uint32(data[offset+1])<<8 | uint32(data[offset+2])
	return value, true
}

func distanceKm(start, end int) int {
	diff := end - start
	if diff >= 0 {
		return diff
	}
	return (end + (1 << 24)) - start
}

func marshalResult(status string, payload map[string]any, log string) (*ParseResult, error) {
	data, err := json.Marshal(payload)
	if err != nil {
		return nil, &NativeError{Code: ErrParser, Message: fmt.Sprintf("failed to serialise result: %v", err)}
	}
	return &ParseResult{
		Status:          status,
		Json:            string(data),
		VerificationLog: log,
	}, nil
}

func sha256Digest(payload []byte) string {
	sum := sha256.Sum256(payload)
	return hex.EncodeToString(sum[:])
}

func generateVerificationLog(ctx context.Context, dir string) (string, error) {
	info, err := os.Stat(dir)
	if err != nil {
		return "", err
	}
	if !info.IsDir() {
		return "", fmt.Errorf("%s is not a directory", dir)
	}

	type entry struct {
		Path string `json:"path"`
		Size int64  `json:"size"`
	}

	entries := []entry{}
	walkErr := filepath.WalkDir(dir, func(path string, d os.DirEntry, err error) error {
		if err != nil {
			return err
		}
		select {
		case <-ctx.Done():
			return ctx.Err()
		default:
		}
		if d.IsDir() {
			return nil
		}
		stat, err := d.Info()
		if err != nil {
			return err
		}
		entries = append(entries, entry{Path: path, Size: stat.Size()})
		return nil
	})
	if walkErr != nil {
		return "", walkErr
	}

	data, err := json.Marshal(entries)
	if err != nil {
		return "", err
	}
	return string(data), nil
}

func translateContextError(err error) error {
	if errors.Is(err, context.DeadlineExceeded) {
		return &NativeError{Code: ErrTimeout, Message: "operation timed out"}
	}
	if errors.Is(err, context.Canceled) {
		return &NativeError{Code: ErrCancelled, Message: "operation cancelled"}
	}
	return &NativeError{Code: ErrParser, Message: err.Error()}
}
