// Copyright (c) 2026 Yingjie Shang
// agent-telemetry is licensed under Mulan PSL v2.

///|
suberror TestExportError

///|
/// Create a test TelemetryProviders value with in-memory exporters for all signals.
fn make_test_telemetry() -> TelemetryProviders {
  let trace_exporter = @sdktrace.InMemorySpanExporter::new()
  let tracer_provider = @sdktrace.SdkTracerProvider::builder()
    .with_simple_exporter(trace_exporter.into_span_exporter())
    .build()
  @sdk.set_tracer_provider(tracer_provider)

  let metric_exporter = @sdkmetrics.InMemoryMetricExporter::new()
  let meter_provider = @sdkmetrics.SdkMeterProvider::builder()
    .with_periodic_exporter(
      metric_exporter.into_metric_exporter(),
      interval_millis=1000,
    )
    .build()
  @sdk.set_meter_provider(meter_provider)

  let log_exporter = @sdklogs.InMemoryLogExporter::new()
  let logger_provider = @sdklogs.SdkLoggerProvider::builder()
    .with_simple_exporter(log_exporter.into_log_exporter())
    .build()
  @sdk.set_logger_provider(logger_provider)

  let providers = {
    tracer_provider,
    meter_provider,
    logger_provider,
    conversation_logger_provider: logger_provider,
    resource: @resource.Resource::builder().build(),
  }
  global_providers.val = Some(providers)
  providers
}

///|
async test "safe_exporter turns raised export errors into ExportFailure" {
  let inner = @sdktrace.SpanExporter::new(_batch => raise TestExportError)
  let wrapped = safe_span_exporter(inner)
  match wrapped.export_batch([]) {
    Ok(_) => fail("expected export failure")
    Err(err) =>
      match err {
        @error.ExportFailure(_, msg) =>
          assert_true(msg.contains("export failed"))
        _ => fail("expected ExportFailure")
      }
  }
}

///|
async test "init_telemetry tolerates unreachable OTLP endpoint" {
  let config = TelemetryConfig::new(service_name="test-safe-init")
  let providers = init_telemetry(config, Otlp("http://localhost:59999"))
  // Span creation and ending should not crash even though the endpoint is
  // unreachable, because the exporter is wrapped by safe_span_exporter.
  let tracer = @otel.tracer("test-scope")
  let span = start_span(tracer, "test.span")
  end_span(span)
  providers.force_flush()
}

///|
test "parse_header_env parses comma separated key=value pairs" {
  let headers = parse_header_env(
    "Authorization=Bearer token, X-Custom = value ",
  )
  assert_eq(headers["Authorization"], "Bearer token")
  assert_eq(headers["X-Custom"], "value")
}
