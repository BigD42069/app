package mobile

import (
	"context"
	"errors"
	"fmt"
	"strings"
	"sync"

	tachomobile "github.com/traconiq/tachoparser/pkg/mobile"
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

type parserConfig struct {
	pks1       string
	pks2       string
	strictMode bool
}

// Parser kapselt den Zugriff auf die Tachograph-Mobile-Bibliothek. Die
// Instanz hält das aktuell initialisierte Service und sorgt dafür, dass
// Zertifikatsoptionen nur bei Bedarf neu geladen werden.
type Parser struct {
	mu      sync.Mutex
	service *tachomobile.Parser
	cfg     parserConfig
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

	service, err := p.ensureService(opts)
	if err != nil {
		return nil, err
	}

	timeout := opts.TimeoutMs
	result, err := service.ParseWithTimeout(payload, mode, timeout)
	if err != nil {
		return nil, translateParseError(err)
	}

	if result == nil {
		return nil, &NativeError{Code: ErrParser, Message: "native parser returned no result"}
	}

	return &ParseResult{
		Status:   statusOk,
		Json:     result.PayloadJSON,
		Verified: result.Verified,
	}, nil
}

// CancelActiveParse bricht laufende Parser-Jobs ab.
func (p *Parser) CancelActiveParse() {
	p.mu.Lock()
	service := p.service
	p.mu.Unlock()

	if service != nil {
		service.CancelActiveParse()
	}
}

func (p *Parser) ensureService(opts *ParseOptions) (*tachomobile.Parser, error) {
	desired := parserConfig{
		pks1:       opts.PKS1Dir,
		pks2:       opts.PKS2Dir,
		strictMode: opts.StrictMode,
	}

	p.mu.Lock()
	defer p.mu.Unlock()

	if p.service != nil && p.cfg == desired {
		return p.service, nil
	}

	if p.service != nil {
		p.service.CancelActiveParse()
	}

	service, err := tachomobile.NewParser(tachomobile.Options{
		PKS1Dir:    desired.pks1,
		PKS2Dir:    desired.pks2,
		StrictMode: desired.strictMode,
	})
	if err != nil {
		return nil, &NativeError{Code: ErrParser, Message: fmt.Sprintf("failed to initialise native parser: %v", err)}
	}

	p.service = service
	p.cfg = desired
	return service, nil
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
