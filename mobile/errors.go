package mobile

// NativeError signalisiert Fehlercodes, die auf die MethodChannel-Codes der
// Flutter-Brücke abgebildet werden können.
type NativeError struct {
	Code    string
	Message string
}

func (e *NativeError) Error() string {
	if e == nil {
		return ""
	}
	return e.Message
}

const (
	// ErrParser markiert interne Fehler in der Verarbeitung.
	ErrParser = "parser-error"
	// ErrTimeout signalisiert ein überschrittenes Timeout.
	ErrTimeout = "timeout"
	// ErrCancelled zeigt einen durch Cancel abgebrochenen Vorgang an.
	ErrCancelled = "cancelled"
	// ErrInvalidArguments signalisiert ungültige Eingaben.
	ErrInvalidArguments = "invalid-arguments"
)
