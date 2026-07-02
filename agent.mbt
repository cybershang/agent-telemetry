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
/// Record turn-level attributes before ending an agent turn span.
///
/// Sets:
/// - `agent.turn.actual_turns`
/// - `agent.turn.tool_call_count`
/// - `agent.turn.output`
pub fn set_turn(
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
pub fn set_turn_exhausted(span : @trace.Span) -> Unit {
  span.set_status(
    @trace.Status::error(description=Some("max_tool_turns_reached")),
  )
}

///|
/// Start a span for a GenAI agent invocation within the same process.
///
/// Follows the `gen_ai.invoke_agent.internal` semantic convention.
///
/// Sets:
/// - `gen_ai.operation.name` = "invoke_agent"
/// - `gen_ai.agent.name` (when provided)
///
/// Span name: `invoke_agent {name}` or `invoke_agent` when name is unavailable.
pub fn start_invoke_agent_span(
  tracer : @trace.Tracer,
  /// The human-readable name of the invoked GenAI agent.
  agent_name? : String? = None,
  /// The parent span context to continue an existing trace.
  parent_context? : @context.Context = @context.Context::empty(),
) -> @trace.Span {
  let span_name = match agent_name {
    Some(name) => "invoke_agent " + name
    None => "invoke_agent"
  }
  let attributes : Array[@common.KeyValue] = [
    @otel.KeyValue::new("gen_ai.operation.name", String("invoke_agent")),
  ]
  match agent_name {
    Some(name) =>
      attributes.push(@otel.KeyValue::new("gen_ai.agent.name", String(name)))
    None => ()
  }
  start_span(
    tracer,
    span_name,
    kind=@trace.Internal,
    attributes~,
    parent_context~,
  )
}

///|
/// Start a span for an agent planning or task decomposition phase.
///
/// Follows the `gen_ai.plan.internal` semantic convention.
///
/// Sets:
/// - `gen_ai.operation.name` = "plan"
/// - `gen_ai.agent.name` (when provided)
///
/// Span name: `plan {name}` or `plan` when name is unavailable.
pub fn start_plan_span(
  tracer : @trace.Tracer,
  /// The human-readable name of the agent performing the planning.
  agent_name? : String? = None,
  /// The parent span context to continue an existing trace.
  parent_context? : @context.Context = @context.Context::empty(),
) -> @trace.Span {
  let span_name = match agent_name {
    Some(name) => "plan " + name
    None => "plan"
  }
  let attributes : Array[@common.KeyValue] = [
    @otel.KeyValue::new("gen_ai.operation.name", String("plan")),
  ]
  match agent_name {
    Some(name) =>
      attributes.push(@otel.KeyValue::new("gen_ai.agent.name", String(name)))
    None => ()
  }
  start_span(
    tracer,
    span_name,
    kind=@trace.Internal,
    attributes~,
    parent_context~,
  )
}
