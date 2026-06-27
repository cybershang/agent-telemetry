// Copyright (c) 2026 Yingjie Shang
// agent-telemetry is licensed under Mulan PSL v2.

///| Internal instrument constructors

///|
fn get_gen_ai_operation_duration_histogram(
  meter : @metrics.Meter,
) -> @metrics.Histogram[Double] {
  meter
  .f64_histogram("gen_ai.client.operation.duration")
  .with_description("GenAI client operation duration")
  .with_unit("s")
  .build()
}

///|
fn get_gen_ai_token_usage_histogram(
  meter : @metrics.Meter,
) -> @metrics.Histogram[UInt64] {
  meter
  .u64_histogram("gen_ai.client.token.usage")
  .with_description("Number of input and output tokens used")
  .with_unit("{token}")
  .build()
}

///|
fn get_tool_calls_counter(meter : @metrics.Meter) -> @metrics.Counter[UInt64] {
  meter
  .u64_counter("agent.tool.calls_total")
  .with_description("Total number of tool executions")
  .with_unit("1")
  .build()
}

///|
fn get_turn_total_counter(meter : @metrics.Meter) -> @metrics.Counter[UInt64] {
  meter
  .u64_counter("agent.turn.total")
  .with_description("Total number of agent turns")
  .with_unit("1")
  .build()
}

///| Public metric functions

///|
/// Record the duration of one GenAI chat operation in seconds.
pub fn record_llm_latency(
  meter : @metrics.Meter,
  provider_name : String,
  model : String,
  seconds~ : Double,
) -> Unit {
  get_gen_ai_operation_duration_histogram(meter).record(seconds, attributes=[
    @common.KeyValue::new("gen_ai.operation.name", String("chat")),
    @common.KeyValue::new("gen_ai.provider.name", String(provider_name)),
    @common.KeyValue::new("gen_ai.request.model", String(model)),
  ])
}

///|
/// Record token usage for one GenAI chat operation.
pub fn record_llm_token_usage(
  meter : @metrics.Meter,
  provider_name : String,
  model : String,
  token_type : String,
  value : Int64,
) -> Unit {
  let tokens = if value < 0L { 0UL } else { value.reinterpret_as_uint64() }
  get_gen_ai_token_usage_histogram(meter).record(tokens, attributes=[
    @common.KeyValue::new("gen_ai.operation.name", String("chat")),
    @common.KeyValue::new("gen_ai.provider.name", String(provider_name)),
    @common.KeyValue::new("gen_ai.request.model", String(model)),
    @common.KeyValue::new("gen_ai.token.type", String(token_type)),
  ])
}

///|
/// Record one tool execution.
pub fn record_tool_call(
  meter : @metrics.Meter,
  tool_name : String,
  success~ : Bool,
) -> Unit {
  get_tool_calls_counter(meter).add(1UL, attributes=[
    @common.KeyValue::new("gen_ai.tool.name", String(tool_name)),
    @common.KeyValue::new("success", String(success.to_string())),
  ])
}

///|
/// Record one completed agent turn.
pub fn record_turn(
  meter : @metrics.Meter,
  max_tool_turns_reached~ : Bool,
) -> Unit {
  get_turn_total_counter(meter).add(1UL, attributes=[
    @common.KeyValue::new(
      "max_tool_turns_reached",
      String(max_tool_turns_reached.to_string()),
    ),
  ])
}
