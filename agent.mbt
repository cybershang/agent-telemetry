// Copyright (c) 2026 Yingjie Shang
// agent-telemetry is licensed under Mulan PSL v2.

///| Agent turn span helpers

///|
/// Start a span for a single agent turn.
///
/// Sets:
/// - `agent.turn.input`
/// - `agent.turn.max_tool_turns`
pub fn start_agent_turn_span(
  tracer : @trace.Tracer,
  input : String,
  max_tool_turns : Int,
) -> @trace.Span {
  let attributes = [
    @otel.KeyValue::new("agent.turn.input", String(input)),
    @otel.KeyValue::new(
      "agent.turn.max_tool_turns",
      Int64(max_tool_turns.to_int64()),
    ),
  ]
  start_span(tracer, "agent.turn", kind=@trace.Internal, attributes~)
}

///|
/// Record turn-level metrics before ending an agent turn span.
///
/// Sets:
/// - `agent.turn.actual_turns`
/// - `agent.turn.tool_call_count`
/// - `agent.turn.output`
pub fn record_turn_metrics(
  span : @trace.Span,
  actual_turns : Int,
  tool_call_count : Int,
  output : String,
) -> Unit {
  span.set_attribute(
    @otel.KeyValue::new(
      "agent.turn.actual_turns",
      Int64(actual_turns.to_int64()),
    ),
  )
  span.set_attribute(
    @otel.KeyValue::new(
      "agent.turn.tool_call_count",
      Int64(tool_call_count.to_int64()),
    ),
  )
  span.set_attribute(@otel.KeyValue::new("agent.turn.output", String(output)))
}

///|
/// Mark an agent turn span as failed due to reaching the maximum tool turns.
pub fn set_turn_max_tool_turns_error(span : @trace.Span) -> Unit {
  span.set_status(
    @trace.Status::error(description=Some("max_tool_turns_reached")),
  )
}
