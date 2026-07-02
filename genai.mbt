// Copyright (c) 2026 Yingjie Shang
// agent-telemetry is licensed under Mulan PSL v2.
//
// Attribute descriptions in this file are derived from the OpenTelemetry
// Semantic Conventions for GenAI (https://github.com/open-telemetry/semantic-conventions-genai),
// licensed under Apache 2.0.

///| GenAI chat span helpers

///|
/// Start a span for a GenAI chat request following OpenTelemetry GenAI conventions.
///
/// Sets:
/// - `gen_ai.operation.name` = "chat"
/// - `gen_ai.provider.name`
/// - `gen_ai.request.model`
/// - `gen_ai.request.max_tokens`
/// - `gen_ai.request.temperature` (when provided)
/// - `gen_ai.request.top_p` (when provided)
/// - `gen_ai.request.stream` (when provided)
/// - `gen_ai.request.reasoning.level` (when provided)
/// - `gen_ai.request.stop_sequences` (when provided)
/// - `gen_ai.request.frequency_penalty` (when provided)
/// - `gen_ai.request.presence_penalty` (when provided)
/// - `gen_ai.request.seed` (when provided)
/// - `gen_ai.input.messages` (when `input_messages` is provided)
/// - `server.address` and `server.port` (when provided)
pub fn start_chat_span(
  tracer : @trace.Tracer,
  provider_name : String,
  model : String,
  max_tokens : Int,
  /// The temperature setting for the GenAI request.
  temperature? : Double? = None,
  /// The top_p sampling setting for the GenAI request.
  top_p? : Double? = None,
  /// Indicates whether the GenAI request was made in streaming mode.
  stream? : Bool? = None,
  /// The reasoning or thinking effort level requested for a GenAI model.
  reasoning_level? : String? = None,
  /// List of sequences that the model will use to stop generating further tokens.
  stop_sequences? : Array[String]? = None,
  /// The frequency penalty setting for the GenAI request.
  frequency_penalty? : Double? = None,
  /// The presence penalty setting for the GenAI request.
  presence_penalty? : Double? = None,
  /// Requests with same seed value more likely to return same result.
  seed? : Int64? = None,
  /// The chat history provided to the model as input (opt-in).
  input_messages? : Json? = None,
  /// GenAI server address.
  server_address? : String? = None,
  /// GenAI server port.
  server_port? : Int? = None,
  /// The parent span context to continue an existing trace.
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
  match temperature {
    Some(v) =>
      attributes.push(
        @otel.KeyValue::new("gen_ai.request.temperature", Double(v)),
      )
    None => ()
  }
  match top_p {
    Some(v) =>
      attributes.push(@otel.KeyValue::new("gen_ai.request.top_p", Double(v)))
    None => ()
  }
  match stream {
    Some(v) =>
      attributes.push(@otel.KeyValue::new("gen_ai.request.stream", Bool(v)))
    None => ()
  }
  match reasoning_level {
    Some(v) =>
      attributes.push(
        @otel.KeyValue::new("gen_ai.request.reasoning.level", String(v)),
      )
    None => ()
  }
  match stop_sequences {
    Some(v) =>
      attributes.push(
        @otel.KeyValue::new(
          "gen_ai.request.stop_sequences",
          String(v.to_json().stringify()),
        ),
      )
    None => ()
  }
  match frequency_penalty {
    Some(v) =>
      attributes.push(
        @otel.KeyValue::new("gen_ai.request.frequency_penalty", Double(v)),
      )
    None => ()
  }
  match presence_penalty {
    Some(v) =>
      attributes.push(
        @otel.KeyValue::new("gen_ai.request.presence_penalty", Double(v)),
      )
    None => ()
  }
  match seed {
    Some(v) =>
      attributes.push(@otel.KeyValue::new("gen_ai.request.seed", Int64(v)))
    None => ()
  }
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
/// Also sets `gen_ai.usage.cache_read.input_tokens` and
/// `gen_ai.usage.reasoning.output_tokens` when provided.
pub fn set_usage(
  span : @trace.Span,
  prompt_tokens : Int64,
  completion_tokens : Int64,
  /// The number of input tokens served from a provider-managed cache.
  cache_read_input_tokens? : Int64 = 0L,
  /// The number of output tokens used for reasoning (e.g. chain-of-thought, extended thinking).
  reasoning_output_tokens? : Int64 = 0L,
) -> Unit {
  if prompt_tokens > 0L {
    span.set_attribute(
      @otel.KeyValue::new(
        @semtrace.GEN_AI_USAGE_INPUT_TOKENS,
        Int64(prompt_tokens),
      ),
    )
  }
  if completion_tokens > 0L {
    span.set_attribute(
      @otel.KeyValue::new(
        @semtrace.GEN_AI_USAGE_OUTPUT_TOKENS,
        Int64(completion_tokens),
      ),
    )
  }
  if cache_read_input_tokens > 0L {
    span.set_attribute(
      @otel.KeyValue::new(
        "gen_ai.usage.cache_read.input_tokens",
        Int64(cache_read_input_tokens),
      ),
    )
  }
  if reasoning_output_tokens > 0L {
    span.set_attribute(
      @otel.KeyValue::new(
        "gen_ai.usage.reasoning.output_tokens",
        Int64(reasoning_output_tokens),
      ),
    )
  }
}

///|
/// Set response attributes for a successful chat request.
///
/// Extracts `gen_ai.response.id`, `gen_ai.response.model` and
/// `gen_ai.response.finish_reasons` from `response_json`.
/// Also sets `gen_ai.output.messages` and `gen_ai.response.time_to_first_chunk`
/// when provided.
pub fn set_response(
  span : @trace.Span,
  response_json : Json,
  /// Messages returned by the model (opt-in).
  output_messages? : Json? = None,
  /// Time to first chunk in a streaming response, in seconds.
  time_to_first_chunk? : Double? = None,
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
  match time_to_first_chunk {
    Some(v) =>
      span.set_attribute(
        @otel.KeyValue::new("gen_ai.response.time_to_first_chunk", Double(v)),
      )
    None => ()
  }
}

///|
/// Mark a chat span as failed due to an error.
///
/// Sets `error.type`, records the span status as error,
/// and emits a `gen_ai.client.operation.exception` event following the OTel GenAI
/// semantic conventions.
pub fn set_http_error(
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
  span.add_event("gen_ai.client.operation.exception", attributes=[
    @otel.KeyValue::new("exception.type", String(error_type)),
    @otel.KeyValue::new("exception.message", String("HTTP \{status_code}")),
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
