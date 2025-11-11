import 'dart:async';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'ddd_parser.dart';

/// Seite zum manuellen Testen des Tachograph-Parsers innerhalb der App.
class ParserTestPage extends StatefulWidget {
  const ParserTestPage({super.key});

  @override
  State<ParserTestPage> createState() => _ParserTestPageState();
}

class _ParserTestPageState extends State<ParserTestPage> {
  late final Future<_ParserTestOutcome> _future = _load();

  Future<_ParserTestOutcome> _load() async {
    const filePath = 'Dateiexplorer.lib/continental.ddd';
    final file = File(filePath);
    final exists = await file.exists();
    if (!exists) {
      throw FileSystemException('Die Testdatei wurde nicht gefunden.', filePath);
    }

    final bytes = await file.readAsBytes();
    final result = await DddParser.instance.parse(
      data: bytes,
      source: DddSource.card,
      timeout: const Duration(seconds: 30),
    );

    return _ParserTestOutcome(
      status: result.status,
      verified: result.verified,
      prettyJson: result.prettyJson,
      verificationLog: result.verificationLog,
      errorDetails: result.errorDetails,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Parsertest'),
      ),
      body: SafeArea(
        child: FutureBuilder<_ParserTestOutcome>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CupertinoActivityIndicator());
            }

            if (snapshot.hasError) {
              final error = snapshot.error;
              final message = error is ParserException
                  ? error.message
                  : error is FileSystemException
                      ? '${error.message}\n${error.path ?? ''}'.trim()
                      : error.toString();
              return Padding(
                padding: const EdgeInsets.all(20),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.error_outline, size: 40, color: cs.error),
                      const SizedBox(height: 12),
                      Text(
                        'Parsen fehlgeschlagen',
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        message,
                        style: theme.textTheme.bodyMedium,
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              );
            }

            final outcome = snapshot.requireData;
            return ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Text(
                  'Status: ${outcome.status}',
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  'Signatur geprüft: ${outcome.verified ? 'ja' : 'nein'}',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 12),
                if (outcome.errorDetails != null) ...[
                  Text(
                    'Fehlerdetails',
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    outcome.errorDetails!,
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 12),
                ],
                if (outcome.verificationLog != null) ...[
                  Text(
                    'Verifikationslog',
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Container(
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: cs.outlineVariant.withOpacity(0.6)),
                    ),
                    padding: const EdgeInsets.all(16),
                    child: SelectableText(
                      outcome.verificationLog!,
                      style: const TextStyle(fontFamily: 'monospace', height: 1.3),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                Text(
                  'Parser-JSON',
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Container(
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: cs.outlineVariant.withOpacity(0.6)),
                  ),
                  padding: const EdgeInsets.all(16),
                  child: outcome.prettyJson != null
                      ? SelectableText(
                          outcome.prettyJson!,
                          style: const TextStyle(fontFamily: 'monospace', height: 1.3),
                        )
                      : Text(
                          'Keine JSON-Daten verfügbar.',
                          style: theme.textTheme.bodyMedium,
                        ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ParserTestOutcome {
  const _ParserTestOutcome({
    required this.status,
    required this.verified,
    this.prettyJson,
    this.verificationLog,
    this.errorDetails,
  });

  final String status;
  final bool verified;
  final String? prettyJson;
  final String? verificationLog;
  final String? errorDetails;
}
