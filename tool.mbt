// Copyright (c) 2026 Yingjie Shang
// agent-telemetry is licensed under Mulan PSL v2.

///| Tool execution span helpers

///|
/// Start a span for a GenAI tool execution.
///
/// Sets:
/// - `gen_ai.tool.name`
/// - `gen_ai.tool.call.arguments`
pub fn start_tool_span(
  tracer : @trace.Tracer,
  name : String,
  arguments : String,
  parent_context? : @context.Context = @context.Context::empty(),
) -> @trace.Span {
  let attributes = [
    @otel.KeyValue::new("gen_ai.tool.name", String(name)),
    @otel.KeyValue::new("gen_ai.tool.call.arguments", String(arguments)),
  ]
  start_span(
    tracer,
    "gen_ai.tool.execution",
    kind=@trace.Internal,
    attributes~,
    parent_context~,
  )
}

///|
/// Set the result of a tool execution and mark the span as successful.
pub fn set_tool_result(span : @trace.Span, result : String) -> Unit {
  if result.contains("\"error\"") {
    span.set_status(
      @trace.Status::error(description=Some("tool returned error")),
    )
  } else {
    span.set_status(@trace.Status::ok())
  }
  span.set_attribute(
    @otel.KeyValue::new("gen_ai.tool.call.result", String(result)),
  )
}

///|
/// Mark a tool span as failed with a description.
pub fn set_tool_error(span : @trace.Span, description : String) -> Unit {
  span.set_status(@trace.Status::error(description=Some(description)))
  span.set_attribute(
    @otel.KeyValue::new("gen_ai.tool.call.result", String(description)),
  )
}
