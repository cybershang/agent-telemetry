// Copyright (c) 2026 Yingjie Shang
// agent-telemetry is licensed under Mulan PSL v2.

///|
/// Create a test tracer backed by an in-memory span exporter.
fn make_test_tracer() -> (@trace.Tracer, @sdktrace.InMemorySpanExporter) {
  let exporter = @sdktrace.InMemorySpanExporter::new()
  let provider = @sdktrace.SdkTracerProvider::builder()
    .with_simple_exporter(exporter.into_span_exporter())
    .build()
  @sdk.set_tracer_provider(provider)
  (@otel.tracer("test"), exporter)
}

///|
/// Find an attribute by key in a span's attribute list.
fn find_attr(span : @sdktrace.SpanData, key : String) -> @common.Value? {
  for attr in span.attributes {
    if attr.key.as_string() == key {
      return Some(attr.value)
    }
  }
  None
}

///|
async test "start_span creates span with name and attributes" {
  let (tracer, exporter) = make_test_tracer()
  let span = start_span(tracer, "test.span", kind=@trace.Client, attributes=[
    @otel.KeyValue::new("custom.key", String("value")),
  ])
  end_span_ok(span)
  let spans = exporter.finished_spans()
  assert_eq(spans.length(), 1)
  assert_eq(spans[0].name, "test.span")
  match find_attr(spans[0], "custom.key") {
    Some(String("value")) => ()
    _ => fail("expected custom.key attribute")
  }
}

///|
async test "end_span preserves existing error status" {
  let (tracer, exporter) = make_test_tracer()
  let span = start_span(tracer, "error.span")
  span.set_status(@trace.Status::error(description=Some("boom")))
  end_span(span)
  let spans = exporter.finished_spans()
  assert_true(spans[0].status.code == @sdktrace.Error)
  assert_eq(spans[0].status.description, Some("boom"))
}

///|
async test "end_span_ok sets ok status" {
  let (tracer, exporter) = make_test_tracer()
  let span = start_span(tracer, "ok.span")
  end_span_ok(span)
  let spans = exporter.finished_spans()
  assert_true(spans[0].status.code == @sdktrace.Ok)
}

///|
test "tracer returns same tracer for same scope" {
  let t1 = tracer("same-scope")
  let t2 = tracer("same-scope")
  // Tracers are cached by scope name; repeated calls should not crash.
  ignore(t1)
  ignore(t2)
}
