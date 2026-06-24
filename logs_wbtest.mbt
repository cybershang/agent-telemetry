// Copyright (c) 2026 Yingjie Shang
// agent-telemetry is licensed under Mulan PSL v2.

///|
async test "log_info emits a log record" {
  let exporter = @sdklogs.InMemoryLogExporter::new()
  let provider = @sdklogs.SdkLoggerProvider::builder()
    .with_simple_exporter(exporter.into_log_exporter())
    .build()
  @sdk.set_logger_provider(provider)
  global_providers.val = Some({
    tracer_provider: @sdktrace.SdkTracerProvider::builder().build(),
    meter_provider: @sdkmetrics.SdkMeterProvider::builder().build(),
    logger_provider: provider,
    conversation_logger_provider: provider,
    resource: @resource.Resource::builder().build(),
  })

  log_info("info-test", "hello metrics and logs")
  provider.force_flush() |> ignore

  let logs = exporter.finished_logs()
  inspect(logs.length(), content="1")
}

///|
async test "log_error emits error severity" {
  let exporter = @sdklogs.InMemoryLogExporter::new()
  let provider = @sdklogs.SdkLoggerProvider::builder()
    .with_simple_exporter(exporter.into_log_exporter())
    .build()
  @sdk.set_logger_provider(provider)
  global_providers.val = Some({
    tracer_provider: @sdktrace.SdkTracerProvider::builder().build(),
    meter_provider: @sdkmetrics.SdkMeterProvider::builder().build(),
    logger_provider: provider,
    conversation_logger_provider: provider,
    resource: @resource.Resource::builder().build(),
  })

  log_error("error-test", "something went wrong")
  provider.force_flush() |> ignore

  let logs = exporter.finished_logs()
  inspect(logs.length(), content="1")
}

///|
async test "log_conversation_message emits user and assistant bodies" {
  let exporter = @sdklogs.InMemoryLogExporter::new()
  let provider = @sdklogs.SdkLoggerProvider::builder()
    .with_simple_exporter(exporter.into_log_exporter())
    .build()
  @sdk.set_logger_provider(provider)
  global_providers.val = Some({
    tracer_provider: @sdktrace.SdkTracerProvider::builder().build(),
    meter_provider: @sdkmetrics.SdkMeterProvider::builder().build(),
    logger_provider: provider,
    conversation_logger_provider: provider,
    resource: @resource.Resource::builder().build(),
  })

  log_conversation_message("conv-test", "user", "hello")
  log_conversation_message("conv-test", "assistant", "hi there", index=0)
  log_conversation_message("conv-test", "tool", "sunny")
  provider.force_flush() |> ignore

  let logs = exporter.finished_logs()
  inspect(logs.length(), content="3")
  let bodies = logs.map(fn(log) {
    match log.body {
      @sdklogs.AnyValue::String(s) => s
      _ => ""
    }
  })
  inspect(bodies[0], content="{\"content\":\"hello\"}")
  inspect(
    bodies[1],
    content="{\"index\":0,\"message\":{\"role\":\"assistant\",\"content\":\"hi there\"}}",
  )
  inspect(bodies[2], content="{\"content\":\"sunny\"}")
}
