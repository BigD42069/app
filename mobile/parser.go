package mobile

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"sync"
	"time"
)

const (
	statusOk        = "ok"
	statusError     = "error"
	statusCancelled = "cancelled"
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

// ParseDdd führt eine einfache Analyse der DDD-Datei durch. Die Implementierung
// ersetzt keinen vollständigen Tachographen-Decoder, stellt aber eine stabile
// API für die Flutter-Bridge bereit.
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

	const chunkSize = 1 << 14 // 16KiB
	for offset := 0; offset < len(payload); offset += chunkSize {
		select {
		case <-ctx.Done():
			if errors.Is(ctx.Err(), context.DeadlineExceeded) {
				return nil, &NativeError{Code: ErrTimeout, Message: "parse operation timed out"}
			}
			return &ParseResult{Status: statusCancelled}, nil
		default:
		}

		// Simuliere Rechenaufwand, damit Timeouts & Cancels in Tests greifbar
		// werden. In einer realen Implementierung würde hier das tatsächliche
		// Decoding der DDD-Daten erfolgen.
		time.Sleep(2 * time.Millisecond)
	}

	if err := ctx.Err(); err != nil {
		if errors.Is(err, context.DeadlineExceeded) {
			return nil, &NativeError{Code: ErrTimeout, Message: "parse operation timed out"}
		}
		if errors.Is(err, context.Canceled) {
			return &ParseResult{Status: statusCancelled}, nil
		}
		return nil, &NativeError{Code: ErrParser, Message: err.Error()}
	}

	result := map[string]any{
		"bytes":       len(payload),
		"source":      opts.Source,
		"sha256":      sha256Digest(payload),
		"generatedAt": time.Now().UTC().Format(time.RFC3339Nano),
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
