// Copyright (c) 2026 Yingjie Shang
// agent-telemetry is licensed under Mulan PSL v2.

///| GenAI chat span helpers

///|
/// Start a span for a GenAI chat request following OpenTelemetry GenAI conventions.
///
/// Sets:
/// - `gen_ai.operation.name` = "chat"
/// - `gen_ai.provider.name`
/// - `gen_ai.request.model`
/// - `gen_ai.request.max_tokens`
/// - `gen_ai.input.messages` when `input_messages` is provided
/// - `server.address` and `server.port` when provided
pub fn start_chat_span(
  tracer : @trace.Tracer,
  provider_name : String,
  model : String,
  max_tokens : Int,
  input_messages? : Json? = None,
  server_address? : String? = None,
  server_port? : Int? = None,
  parent_context? : @context.Context = @context.Context::empty(),
) -> @trace.Span {
  let attributes = [
    @otel.KeyValue::new(@semtrace.GEN_AI_OPERATION_NAME, String("chat")),
    @otel.KeyValue::new("gen_ai.provider.name", String(provider_name)),
    @otel.KeyValue::new(@semtrace.GEN_AI_REQUEST_MODEL, String(model)),
    @otel.KeyValue::new(
      @semtrace.GEN_AI_REQUEST_MAX_TOKENS,
      Int64(max_tokens.to_int64()),
    ),
  ]
  match server_address {
    Some(address) =>
      attributes.push(@otel.KeyValue::new("server.address", String(address)))
    None => ()
  }
  match server_port {
    Some(port) =>
      attributes.push(
        @otel.KeyValue::new("server.port", Int64(port.to_int64())),
      )
    None => ()
  }
  let span = start_span(
    tracer,
    "gen_ai.chat",
    kind=@trace.Client,
    attributes~,
    parent_context~,
  )
  match input_messages {
    Some(messages) =>
      span.set_attribute(
        @otel.KeyValue::new(
          "gen_ai.input.messages",
          String(messages.stringify()),
        ),
      )
    None => ()
  }
  span
}

///|
/// Set usage attributes from a GenAI response usage object.
///
/// Sets `gen_ai.usage.input_tokens` and `gen_ai.usage.output_tokens` when present.
pub fn set_chat_usage(span : @trace.Span, usage_json : Json) -> Unit {
  if usage_json is { "prompt_tokens": Number(pt, ..), .. } {
    span.set_attribute(
      @otel.KeyValue::new(
        @semtrace.GEN_AI_USAGE_INPUT_TOKENS,
        Int64(pt.to_int64()),
      ),
    )
  }
  if usage_json is { "completion_tokens": Number(ct, ..), .. } {
    span.set_attribute(
      @otel.KeyValue::new(
        @semtrace.GEN_AI_USAGE_OUTPUT_TOKENS,
        Int64(ct.to_int64()),
      ),
    )
  }
}

///|
/// Set response attributes for a successful chat request.
///
/// Extracts `gen_ai.response.id`, `gen_ai.response.model` and
/// `gen_ai.response.finish_reasons` from `response_json`.
/// Sets `gen_ai.output.messages` when `output_messages` is provided.
pub fn set_chat_response(
  span : @trace.Span,
  response_json : Json,
  output_messages? : Json? = None,
) -> Unit {
  if response_json is { "id": String(id), .. } {
    span.set_attribute(
      @otel.KeyValue::new(@semtrace.GEN_AI_RESPONSE_ID, String(id)),
    )
  }
  if response_json is { "model": String(model), .. } {
    span.set_attribute(
      @otel.KeyValue::new(@semtrace.GEN_AI_RESPONSE_MODEL, String(model)),
    )
  }
  let finish_reason = extract_finish_reason(response_json)
  if finish_reason != "" {
    span.set_attribute(
      @otel.KeyValue::new(
        @semtrace.GEN_AI_RESPONSE_FINISH_REASONS,
        String(finish_reason),
      ),
    )
  }
  match output_messages {
    Some(messages) =>
      span.set_attribute(
        @otel.KeyValue::new(
          "gen_ai.output.messages",
          String(messages.stringify()),
        ),
      )
    None => ()
  }
}

///|
/// Mark a chat span as failed due to an HTTP error.
///
/// Sets `error.type` to the status code string, records the span status as error,
/// and emits an `llm.http_error` event.
pub fn set_chat_http_error(
  span : @trace.Span,
  status_code : Int,
  message? : String,
) -> Unit {
  let error_type = status_code.to_string()
  span.set_attribute(@otel.KeyValue::new("error.type", String(error_type)))
  span.set_status(
    @trace.Status::error(
      description=Some(message.unwrap_or("HTTP \{status_code}")),
    ),
  )
  span.add_event("llm.http_error", attributes=[
    @otel.KeyValue::new("http.status_code", Int64(status_code.to_int64())),
  ])
}

///| Internal helpers

///|
/// Extract the finish reason from the first choice of a chat response.
fn extract_finish_reason(response_json : Json) -> String {
  guard response_json
    is {
      "choices": Array([{ "finish_reason": String(finish_reason), .. }, ..]),
      ..
    } else {
    return ""
  }
  finish_reason
}
