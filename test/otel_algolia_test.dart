// Licensed under the Dartastic Pro Software License Agreement.
// Copyright 2025-2026 Mindful Software LLC d/b/a Dartastic.io, All rights reserved.

import 'package:dartastic_opentelemetry/dartastic_opentelemetry.dart';
import 'package:dartastic_opentelemetry/testing.dart';
import 'package:otel_algolia/otel_algolia.dart';
import 'package:test/test.dart';

void main() {
  late TestHarness harness;
  late InMemorySpanExporter spans;

  setUpAll(() async {
    harness = await maybeInitializeOtelForTest(
      serviceName: 'otel_algolia-test',
    );
    spans = harness.spans;
  });

  setUp(() => harness.clear());

  Map<String, Object> attrsOf(Span s) =>
      {for (final a in s.attributes.toList()) a.key: a.value};

  test('search records CLIENT span with hits + time', () async {
    await tracedAlgoliaSearch<String>(
      indexName: 'products',
      query: 'shoes',
      limit: 20,
      appId: 'APP1',
      invoke: () async => const AlgoliaSearchResult(
        value: 'rows',
        hits: 42,
        processingTimeMs: 3,
      ),
    );
    final span = spans.findSpanByName('algolia search products');
    expect(span, isNotNull);
    expect(span!.kind, SpanKind.client);
    final a = attrsOf(span);
    expect(a['db.system'], 'algolia');
    expect(a['db.operation'], 'search');
    expect(a['db.collection.name'], 'products');
    expect(a['algolia.index'], 'products');
    expect(a['algolia.query'], 'shoes');
    expect(a['algolia.limit'], 20);
    expect(a['algolia.app.id'], 'APP1');
    expect(a['algolia.hits'], 42);
    expect(a['algolia.processing_time_ms'], 3);
  });

  test('index op records CLIENT span with object count', () async {
    await tracedAlgoliaIndexOp<String>(
      operation: 'saveObjects',
      indexName: 'products',
      objectCount: 100,
      invoke: () async => 'ok',
    );
    final a = attrsOf(spans.findSpanByName('algolia saveObjects products')!);
    expect(a['db.operation'], 'saveObjects');
    expect(a['algolia.object_count'], 100);
  });

  test('records exception', () async {
    await expectLater(
      tracedAlgoliaSearch<String>(
        indexName: 'p',
        query: 'q',
        invoke: () async => throw StateError('boom'),
      ),
      throwsA(isA<StateError>()),
    );
    expect(
      spans.findSpanByName('algolia search p')!.status,
      SpanStatusCode.Error,
    );
  });

  test('suppression skips spans', () async {
    await runWithoutAlgoliaInstrumentationAsync(() async {
      await tracedAlgoliaSearch<String>(
        indexName: 'p',
        query: 'q',
        invoke: () async => const AlgoliaSearchResult(value: 'v'),
      );
    });
    expect(spans.findSpansStartingWith('algolia '), isEmpty);
  });
}
