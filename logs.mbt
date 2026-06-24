// Copyright (c) 2026 Yingjie Shang
// agent-telemetry is licensed under Mulan PSL v2.

///|
/// Emit a structured log record.
pub async fn emit_log(
  scope_name : String,
  severity : @logs.Severity,
  body : String,
  attributes? : Array[@common.KeyValue] = [],
  trace_context? : @common.SpanContext? = None,
) -> Unit {
  let logger = logger(scope_name)
  let record = logger.create_log_record()
  record.set_severity_number(severity)
  record.set_body(@logs.AnyValue::String(body))
  record.add_attributes(attributes)
  match trace_context {
    Some(ctx) =>
      record.set_trace_context(
        ctx.trace_id(),
        ctx.span_id(),
        trace_flags=Some(ctx.trace_flags()),
      )
    None => ()
  }
  logger.emit(record)
}

///|
/// Emit an info log.
pub async fn log_info(
  scope_name : String,
  body : String,
  attributes? : Array[@common.KeyValue] = [],
  trace_context? : @common.SpanContext? = None,
) -> Unit {
  emit_log(scope_name, @logs.Info, body, attributes~, trace_context~)
}

///|
/// Emit a warning log.
pub async fn log_warn(
  scope_name : String,
  body : String,
  attributes? : Array[@common.KeyValue] = [],
  trace_context? : @common.SpanContext? = None,
) -> Unit {
  emit_log(scope_name, @logs.Warn, body, attributes~, trace_context~)
}

///|
/// Emit an error log.
pub async fn log_error(
  scope_name : String,
  body : String,
  attributes? : Array[@common.KeyValue] = [],
  trace_context? : @common.SpanContext? = None,
) -> Unit {
  emit_log(scope_name, @logs.Error, body, attributes~, trace_context~)
}

///|
/// Emit a conversation message log compatible with the `genai-observability`
/// GreptimeDB dashboard SQL.
///
/// Body JSON shape:
/// - `user` / `tool`: `{"content":"..."}`
/// - `assistant`: `{"index":0,"message":{"role":"assistant","content":"..."}}`
pub async fn log_conversation_message(
  scope_name : String,
  role : String,
  content : String,
  index? : Int = 0,
  trace_context? : @common.SpanContext? = None,
) -> Unit {
  let body_json = if role == "assistant" {
    {
      "index": index.to_json(),
      "message": { "role": "assistant".to_json(), "content": content.to_json() }.to_json(),
    }.to_json()
  } else {
    { "content": content.to_json() }.to_json()
  }
  let logger = conversation_logger(scope_name)
  let record = logger.create_log_record()
  record.set_severity_number(@logs.Info)
  record.set_body(@logs.AnyValue::String(body_json.stringify()))
  match trace_context {
    Some(ctx) =>
      record.set_trace_context(
        ctx.trace_id(),
        ctx.span_id(),
        trace_flags=Some(ctx.trace_flags()),
      )
    None => ()
  }
  logger.emit(record)
}
