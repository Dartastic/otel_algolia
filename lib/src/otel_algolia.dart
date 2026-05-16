// Licensed under the Apache License, Version 2.0
// Copyright 2025, Mindful Software LLC, All rights reserved.

import 'package:dartastic_opentelemetry/dartastic_opentelemetry.dart';

import 'otel_algolia_suppression.dart';

const _tracerName = 'dartastic_otel_libs_algolia';
const _systemValue = 'algolia';

Tracer _tracer() => OTel.tracerProvider().getTracer(_tracerName);

/// Pair returned from `tracedAlgoliaSearch` callback.
class AlgoliaSearchResult<T> {
  const AlgoliaSearchResult({
    required this.value,
    this.hits,
    this.processingTimeMs,
  });
  final T value;
  final int? hits;
  final int? processingTimeMs;
}

/// Wraps an Algolia `search` query in a CLIENT span using OTel
/// db.* semconv with system=algolia.
Future<T> tracedAlgoliaSearch<T>({
  required String indexName,
  required String query,
  required Future<AlgoliaSearchResult<T>> Function() invoke,
  int? limit,
  String? appId,
}) async {
  if (algoliaInstrumentationSuppressed()) {
    final r = await invoke();
    return r.value;
  }
  final m = <String, Object>{
    'db.system': _systemValue,
    'db.operation': 'search',
    'db.collection.name': indexName,
    'algolia.index': indexName,
    'algolia.query': query,
  };
  if (limit != null) m['algolia.limit'] = limit;
  if (appId != null) m['algolia.app.id'] = appId;

  final span = _tracer().startSpan(
    'algolia search $indexName',
    kind: SpanKind.client,
    attributes: OTel.attributesFromMap(m),
  );
  try {
    final r = await invoke();
    final extras = <Attribute<Object>>[];
    if (r.hits != null) {
      extras.add(OTel.attributeInt('algolia.hits', r.hits!));
    }
    if (r.processingTimeMs != null) {
      extras.add(OTel.attributeInt(
        'algolia.processing_time_ms',
        r.processingTimeMs!,
      ));
    }
    if (extras.isNotEmpty) span.addAttributes(OTel.attributes(extras));
    return r.value;
  } catch (e, st) {
    span.addAttributes(OTel.attributes([
      OTel.attributeString(
        ErrorResource.errorType.key,
        e.runtimeType.toString(),
      ),
    ]));
    span.recordException(e, stackTrace: st);
    span.setStatus(SpanStatusCode.Error, e.toString());
    rethrow;
  } finally {
    span.end();
  }
}

/// Wraps an Algolia indexing op (saveObject/saveObjects/deleteObject)
/// in a CLIENT span.
Future<T> tracedAlgoliaIndexOp<T>({
  required String operation,
  required String indexName,
  required Future<T> Function() invoke,
  int? objectCount,
  String? appId,
}) async {
  if (algoliaInstrumentationSuppressed()) {
    return invoke();
  }
  final m = <String, Object>{
    'db.system': _systemValue,
    'db.operation': operation,
    'db.collection.name': indexName,
    'algolia.index': indexName,
  };
  if (objectCount != null) m['algolia.object_count'] = objectCount;
  if (appId != null) m['algolia.app.id'] = appId;

  final span = _tracer().startSpan(
    'algolia $operation $indexName',
    kind: SpanKind.client,
    attributes: OTel.attributesFromMap(m),
  );
  try {
    return await invoke();
  } catch (e, st) {
    span.addAttributes(OTel.attributes([
      OTel.attributeString(
        ErrorResource.errorType.key,
        e.runtimeType.toString(),
      ),
    ]));
    span.recordException(e, stackTrace: st);
    span.setStatus(SpanStatusCode.Error, e.toString());
    rethrow;
  } finally {
    span.end();
  }
}
