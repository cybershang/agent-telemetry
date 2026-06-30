# Instrumentation Guide

This guide shows how to instrument a MoonBit agent application with `cybershang/agent-telemetry`. The examples are based on the `agent-observability` sample application.

The library is designed to be inserted into your existing code with minimal changes. The general pattern is:

1. Get a tracer with `@telemetry.tracer("your-scope")`.
2. Start a span at the beginning of an operation.
3. Pass `parent_context=span.context()` to child operations so that LLM, tool, and agent spans form a single trace.
4. Record results, usage, or errors before ending the span.

## Instrumenting an LLM Chat Request

In your chat client, wrap the HTTP request in a `gen_ai.chat` span:

```moonbit
async fn chat(
  messages : Array<Message>,
  parent_context? : @context.Context = @context.Context::empty(),
) -> LLMResponse {
  let tracer = @telemetry.tracer("my-agent/llm")
  let span = @telemetry.start_chat_span(
    tracer,
    provider_name="stepfun",
    model="step-3.7-flash",
    max_tokens=1024,
    input_messages~,        // optional: capture input messages
    server_address~,        // optional: server.address attribute
    server_port~,           // optional: server.port attribute
    parent_context~,        // optional: continue an existing trace
  )

  let (response, body) = @http.post(endpoint, request_json, headers~)

  guard response.code == 200 else {
    @telemetry.set_http_error(span, response.code)
    @telemetry.end_span(span)
    abort("LLM request failed")
  }

  let data = body.json()
  if data is { "usage": { "prompt_tokens": Int64(prompt), "completion_tokens": Int64(completion), .. }, .. } {
    @telemetry.set_usage(span, prompt, completion)
  }
  @telemetry.set_response(span, data, output_messages~)
  @telemetry.end_span(span)

  parse_response(data)
}
```

This produces a span named `gen_ai.chat` with attributes such as `gen_ai.provider.name`, `gen_ai.request.model`, `gen_ai.usage.input_tokens`, and `gen_ai.response.id`. On HTTP failure it also sets `error.type` to the status code string.

## Instrumenting Tool Execution

In your tool dispatcher, wrap each tool call in a `gen_ai.tool.execution` span:

```moonbit
pub async fn execute_tool(
  name : String,
  arguments : String,
  parent_context? : @context.Context = @context.Context::empty(),
) -> String {
  let tracer = @telemetry.tracer("my-agent/tools")
  let span = @telemetry.start_tool_span(
    tracer,
    name,
    arguments,
    parent_context~,
  )

  let result = run_the_tool(name, arguments)

  @telemetry.set_tool_result(span, result)
  @telemetry.end_span(span)
  result
}
```

`set_tool_result` automatically marks the span as error if the result string contains `"error"`. Use `set_tool_error` if you want to set a custom error description.

## Instrumenting an Agent Turn

In your agent's main loop, wrap one complete turn (user prompt → LLM → tools → final reply) in an `agent.turn` span:

```moonbit
pub async fn Agent::run(self : Agent, prompt : String) -> AgentTurnResult {
  let tracer = @telemetry.tracer("my-agent/agent")
  let span = @telemetry.start_agent_turn_span(
    tracer,
    prompt,
    self.max_tool_turns,
  )
  let parent_context = span.context()

  // ... run the LLM / tool loop using parent_context~ ...

  if hit_max_tool_turns {
    @telemetry.set_turn_exhausted(span)
  }

  @telemetry.set_turn(span, turns, executed.length(), final_reply)
  @telemetry.end_span(span)

  { reply: final_reply, tool_calls: executed }
}
```

The `parent_context` is passed to the LLM chat request and each tool execution, so the resulting trace shows the agent turn as the parent of its chat and tool spans.

## Propagating Trace Context

Always pass `parent_context=span.context()` when a function calls another instrumented function. This links the child span to the parent span and produces a single coherent trace. If no parent is available, the helpers default to an empty context.

## Adding Custom Span Attributes

The semantic helpers record the standard GenAI attributes automatically. You can add application-specific attributes with typed helpers:

```moonbit
let span = @telemetry.start_span(tracer, "my.step")
@telemetry.set_string(span, "app.user.id", "user-42")
@telemetry.set_int(span, "app.retry.count", 3L)
@telemetry.set_double(span, "app.score", 0.95)
@telemetry.set_bool(span, "app.cached", true)
@telemetry.set_json(span, "app.metadata", { "source": "api", "depth": 2 })
@telemetry.end_span(span)
```

`set_json` serializes the `Json` value to a string attribute, which is convenient for structured metadata that does not fit the scalar attribute types. If you already have an array of `@otel.KeyValue` values, use `set_attributes(span, attrs)` directly.

### Example: application-specific attributes in this sample app

The `agent-observability` sample application records a small set of `app.*` attributes on top of the standard GenAI ones. Each `Agent::run` invocation starts its own root `agent.turn` span, so every turn is an independent trace; the attributes below live on that turn and its children:

| Span | Attribute | Type | Meaning | Good for aggregation |
|---|---|---|---|---|
| `agent.turn` | `app.agent.tool_count` | int64 | Tools available to the agent | latest value / big number display |
| `agent.turn` | `app.prompt.length` | int64 | User prompt length | avg / p95 / histogram |
| `agent.turn` | `app.response.length` | int64 | Final reply length | avg / p95 / histogram |
| `agent.turn` | `app.agent.reached_max_turns` | bool | Whether max_tool_turns was hit | count of `true` |
| `gen_ai.chat` | `app.llm.capture_content` | bool | Whether this client captures content | toggle / last value display |
| `gen_ai.chat` | `app.llm.tool_calls.count` | int64 | Number of tool calls in the response | avg / sum / max |
| `gen_ai.tool.execution` | `app.tool.result.length` | int64 | Length of the tool result JSON string | avg / p95 / histogram |

These attributes are set with the typed helpers shown above, so they are easy to query in GreptimeDB / Grafana alongside the built-in GenAI attributes.

## Recording Metrics

Get a `Meter` for your scope and call the semantic metric functions:

```moonbit
let meter = @telemetry.meter("my-agent/llm")

@telemetry.record_llm_latency(meter, "stepfun", "step-3.7-flash", seconds=0.85)
@telemetry.record_usage(meter, "stepfun", "step-3.7-flash", "input", 100L)
@telemetry.record_usage(meter, "stepfun", "step-3.7-flash", "output", 25L)
```

The following metrics are emitted:

| Metric | Type | Labels |
|---|---|---|
| `gen_ai.client.operation.duration` | Histogram | `gen_ai.operation.name`, `gen_ai.provider.name`, `gen_ai.request.model` |
| `gen_ai.client.token.usage` | Histogram | `gen_ai.operation.name`, `gen_ai.provider.name`, `gen_ai.request.model`, `gen_ai.token.type` |
| `agent.tool.calls_total` | Counter | `gen_ai.tool.name`, `success` |
| `agent.turn.total` | Counter | `max_tool_turns_reached` |

## Recording Logs

Use severity helpers or the generic `emit_log` function:

```moonbit
@telemetry.log_info("my-agent", "agent started")
@telemetry.log_error(
  "my-agent/llm",
  "LLM request failed with status 401",
  trace_context=Some(span.span_context()),
)
```

When `trace_context` is provided, the log record is linked to the active trace/span.

These severity helpers write to the default OTLP log table (`opentelemetry_logs` when exporting to GreptimeDB).

To record conversation messages in a format compatible with the `genai-observability` GreptimeDB dashboard SQL:

```moonbit
@telemetry.log_conversation_message(
  "my-agent/llm",
  "user",
  "What is GreptimeDB?",
  trace_context=Some(span.span_context()),
)

@telemetry.log_conversation_message(
  "my-agent/llm",
  "assistant",
  "GreptimeDB is a time-series database.",
  index=0,
  trace_context=Some(span.span_context()),
)
```

Body JSON shapes:

- `user` / `tool`: `{"content":"..."}`
- `assistant`: `{"index":0,"message":{"role":"assistant","content":"..."}}`

## OTLP Headers

You can pass custom headers to each OTLP exporter using standard environment variables:

| Variable | Scope | Fallback |
|---|---|---|
| `OTEL_EXPORTER_OTLP_HEADERS` | All signals | — |
| `OTEL_EXPORTER_OTLP_TRACES_HEADERS` | Traces only | `OTEL_EXPORTER_OTLP_HEADERS` |
| `OTEL_EXPORTER_OTLP_METRICS_HEADERS` | Metrics only | `OTEL_EXPORTER_OTLP_HEADERS` |
| `OTEL_EXPORTER_OTLP_LOGS_HEADERS` | Logs only | `OTEL_EXPORTER_OTLP_HEADERS` |

Format is comma-separated `key=value` pairs:

```bash
OTEL_EXPORTER_OTLP_TRACES_HEADERS="Authorization=Bearer my-token"
```

This is useful when your observability backend requires authentication tokens or tenant routing headers.

## GreptimeDB Integration

When exporting to GreptimeDB via OTLP/HTTP, the library automatically adds Greptime-specific headers unless you already provided them via the variables above:

| Variable | Default | Header | Used by |
|---|---|---|---|
| `GREPTIME_TRACE_PIPELINE` | `greptime_trace_v1` | `x-greptime-pipeline-name` | Trace exporter |
| `GREPTIME_LOG_TABLE` | `genai_conversations` | `x-greptime-log-table-name` | Conversation log exporter |

Values are read via `env_with_dotenv`, which checks the process environment first and then the `.env` file in the working directory.

### Log destinations

- `log_info`, `log_warn`, `log_error`, and the generic `emit_log` use the **default logger**, which does not set `x-greptime-log-table-name`. These logs land in GreptimeDB's default `opentelemetry_logs` table.
- `log_conversation_message` uses the **conversation logger**, which sends logs to the table configured by `GREPTIME_LOG_TABLE` (default `genai_conversations`).

This separation makes it easy to query general application logs and LLM conversation logs independently.
