// Copyright (c) 2026 Yingjie Shang
// agent-telemetry is licensed under Mulan PSL v2.

///|
test "record_llm_latency emits histogram metric" {
  let _providers = make_test_telemetry()
  let meter = meter("test")
  record_llm_latency(meter, "openai", "gpt-4", seconds=0.42)
  record_llm_latency(meter, "openai", "gpt-4", seconds=1.23)
}

///|
test "record_llm_token_usage emits histogram metric" {
  let _providers = make_test_telemetry()
  let meter = meter("test")
  record_llm_token_usage(meter, "openai", "gpt-4", "input", 42L)
  record_llm_token_usage(meter, "openai", "gpt-4", "output", 7L)
}

///|
test "metric instruments are cached and reused" {
  let _providers = make_test_telemetry()
  let meter = meter("test")
  record_llm_latency(meter, "a", "b", seconds=0.1)
  record_llm_token_usage(meter, "a", "b", "input", 1L)
  record_llm_token_usage(meter, "a", "b", "output", 2L)
}

///|
async test "manual reader collects gen_ai operation duration metric" {
  let reader = @sdkmetrics.ManualReader::builder().build()
  let provider = @sdkmetrics.SdkMeterProvider::builder()
    .with_reader(reader)
    .with_resource(@resource.Resource::builder().build())
    .build()
  @sdk.set_meter_provider(provider)
  global_providers.val = Some({
    tracer_provider: @sdktrace.SdkTracerProvider::builder().build(),
    meter_provider: provider,
    logger_provider: @sdklogs.SdkLoggerProvider::builder().build(),
    conversation_logger_provider: @sdklogs.SdkLoggerProvider::builder().build(),
    resource: @resource.Resource::builder().build(),
  })

  let meter = meter("manual-reader-test")
  record_llm_latency(meter, "openai", "gpt-4", seconds=0.42)

  let metrics = reader.collect()
  inspect(metrics.length(), content="1")
  inspect(metrics[0].name, content="gen_ai.client.operation.duration")
}

///|
async test "manual reader collects gen_ai token usage metric" {
  let reader = @sdkmetrics.ManualReader::builder().build()
  let provider = @sdkmetrics.SdkMeterProvider::builder()
    .with_reader(reader)
    .with_resource(@resource.Resource::builder().build())
    .build()
  @sdk.set_meter_provider(provider)
  global_providers.val = Some({
    tracer_provider: @sdktrace.SdkTracerProvider::builder().build(),
    meter_provider: provider,
    logger_provider: @sdklogs.SdkLoggerProvider::builder().build(),
    conversation_logger_provider: @sdklogs.SdkLoggerProvider::builder().build(),
    resource: @resource.Resource::builder().build(),
  })

  let meter = meter("token-usage-test")
  record_llm_token_usage(meter, "openai", "gpt-4", "input", 100L)
  record_llm_token_usage(meter, "openai", "gpt-4", "output", 25L)

  let metrics = reader.collect()
  inspect(metrics.length(), content="2")
  inspect(metrics[0].name, content="gen_ai.client.token.usage")
  inspect(metrics[1].name, content="gen_ai.client.token.usage")
}
