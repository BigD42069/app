package mobile

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"strings"
	"sync"
	"time"

	_ "github.com/company/tachograph/assets/pkg/certificates"
	"github.com/traconiq/tachoparser/pkg/decoder"
)

const (
	statusOk = "ok"
)

// Options konfigurieren das Verhalten des nativen Parsers. Sie werden vor
// jedem Parse-Aufruf in ein Tachograph-Service übersetzt.
type Options struct {
	PKS1Dir    string
	PKS2Dir    string
	StrictMode bool
}

// Parser kapselt den Zugriff auf die Tachograph-Mobile-Bibliothek. Die
// Instanz hält das aktuell initialisierte Service und sorgt dafür, dass
// Zertifikatsoptionen nur bei Bedarf neu geladen werden.
type Parser struct {
	mu     sync.Mutex
	cancel context.CancelFunc
}

// NewParser erzeugt eine Parser-Instanz mit Standardeinstellungen. Die
// eigentliche native Bibliothek wird lazily geladen, sobald `ParseDdd`
// aufgerufen wird.
func NewParser() *Parser {
	return &Parser{}
}

// ParseOptions beschreibt zusätzliche Parameter, die beim Parsen gesetzt
// werden können.
type ParseOptions struct {
	Source     string
	TimeoutMs  int
	PKS1Dir    string
	PKS2Dir    string
	StrictMode bool
}

// ParseResult enthält die Ergebnisse eines Parse-Laufs.
type ParseResult struct {
	Status          string
	Json            string
	Verified        bool
	VerificationLog string
	ErrorDetails    string
}

// ParseDdd führt den Tachograph-Parser gegen die übergebenen Rohdaten aus.
func (p *Parser) ParseDdd(payload []byte, opts *ParseOptions) (*ParseResult, error) {
	if len(payload) == 0 {
		return nil, &NativeError{Code: ErrInvalidArguments, Message: "payload must not be empty"}
	}
	if opts == nil {
		return nil, &NativeError{Code: ErrInvalidArguments, Message: "options must not be nil"}
	}

	mode := strings.ToLower(strings.TrimSpace(opts.Source))
	if mode != "card" && mode != "vu" {
		return nil, &NativeError{Code: ErrInvalidArguments, Message: "source must be 'card' or 'vu'"}
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

	type parseOutcome struct {
		json     string
		verified bool
		err      error
	}
	done := make(chan parseOutcome, 1)

	go func() {
		switch mode {
		case "card":
			var c decoder.Card
			verified, err := decoder.UnmarshalTLV(payload, &c)
			if err != nil {
				done <- parseOutcome{err: err}
				return
			}
			raw, err := json.Marshal(c)
			done <- parseOutcome{json: string(raw), verified: verified, err: err}
		case "vu":
			var v decoder.Vu
			verified, err := decoder.UnmarshalTV(payload, &v)
			if err != nil {
				done <- parseOutcome{err: err}
				return
			}
			raw, err := json.Marshal(v)
			done <- parseOutcome{json: string(raw), verified: verified, err: err}
		default:
			done <- parseOutcome{err: fmt.Errorf("unsupported mode %q", mode)}
		}
	}()

	select {
	case <-ctx.Done():
		p.mu.Lock()
		p.cancel = nil
		p.mu.Unlock()
		return nil, translateParseError(ctx.Err())
	case outcome := <-done:
		p.mu.Lock()
		p.cancel = nil
		p.mu.Unlock()
		if outcome.err != nil {
			return nil, translateParseError(outcome.err)
		}
		return &ParseResult{
			Status:   statusOk,
			Json:     outcome.json,
			Verified: outcome.verified,
		}, nil
	}
}

// CancelActiveParse bricht laufende Parser-Jobs ab.
func (p *Parser) CancelActiveParse() {
	p.mu.Lock()
	cancel := p.cancel
	p.cancel = nil
	p.mu.Unlock()

	if cancel != nil {
		cancel()
	}
}

func translateParseError(err error) error {
	if err == nil {
		return nil
	}
	if errors.Is(err, context.DeadlineExceeded) {
		return &NativeError{Code: ErrTimeout, Message: "parse operation timed out"}
	}
	if errors.Is(err, context.Canceled) {
		return &NativeError{Code: ErrCancelled, Message: "parse operation cancelled"}
	}
	return &NativeError{Code: ErrParser, Message: err.Error()}
}
