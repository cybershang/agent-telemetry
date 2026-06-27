# agent-telemetry

OpenTelemetry instrumentation library for MoonBit Agent / LLM / Tool scenarios.

It wraps the boilerplate OTel tracer / span / attribute code into business-semantic helpers, so agent developers only need to decide when to create spans and what business data to record.

## Design Layers

- **Thin wrapper** (`lib.mbt`): provider initialization, tracer cache, span lifecycle helpers such as `start_span` / `end_span`.
- **Semantic wrapper** (`genai.mbt`, `tool.mbt`, `agent.mbt`): sets attributes according to the OpenTelemetry GenAI semantic conventions, covering chat, tool execution, and agent turn spans.

## Quick Start

```bash
moon add cybershang/agent-telemetry
```

```moonbit
// Option 1: one-line initialization from environment variables.
// Reads OTEL_SERVICE_NAME, OTEL_STDOUT, and OTEL_EXPORTER_OTLP_ENDPOINT.
// Use ProcessUniqueRandom to avoid duplicate trace/span IDs across restarts.
let providers = @telemetry.init_from_env(
  id_generator=@telemetry.ProcessUniqueRandom,
)

// Option 2: manually select an exporter.
let config = @telemetry.TelemetryConfig::new(service_name="my-agent")
let providers = @telemetry.init_telemetry(
  config,
  @telemetry.Otlp("http://localhost:4318"),
  id_generator=@telemetry.ProcessUniqueRandom,
)

// Metrics and logs need background tasks.
@async.with_task_group((group) => {
  providers.spawn_background_tasks(group)

  // Create a GenAI chat span.
  let tracer = @telemetry.tracer("my-agent/llm")
  let meter = @telemetry.meter("my-agent/llm")
  let span = @telemetry.start_chat_span(
    tracer,
    provider_name="stepfun",
    model="step-3.7-flash",
    max_tokens=1024,
  )
  // ... send the request and obtain response_json ...
  @telemetry.set_chat_response(span, response_json)
  @telemetry.end_span(span)

  providers.force_flush()
  providers.shutdown()
})
```

## Main API

| Scenario | Functions |
|---|---|
| General | `TelemetryConfig::new`, `init_telemetry`, `init_from_env`, `TelemetryProviders`, `IdGeneratorOption`, `tracer`, `meter`, `logger`, `conversation_logger`, `start_span`, `end_span`, `set_attributes`, `set_string`, `set_int`, `set_double`, `set_bool`, `set_json` |
| LLM chat | `start_chat_span`, `set_chat_usage`, `set_chat_response`, `set_http_error` |
| Tool | `start_tool_span`, `set_tool_result`, `set_tool_error` |
| Agent turn | `start_agent_turn_span`, `set_turn`, `set_turn_exhausted` |
| Metrics | `record_llm_latency`, `record_llm_token_usage`, `record_tool_call`, `record_turn` |
| Logs | `emit_log`, `log_info`, `log_warn`, `log_error`, `log_conversation_message` |

## Custom Span Attributes

The library already sets the standard GenAI semantic attributes for chat/tool/agent spans. When you need to record your own domain-specific metadata, use the typed attribute helpers:

```moonbit
let span = @telemetry.start_span(tracer, "my.step")
@telemetry.set_string(span, "app.user.id", "user-42")
@telemetry.set_int(span, "app.retry.count", 3L)
@telemetry.set_double(span, "app.score", 0.95)
@telemetry.set_bool(span, "app.cached", true)
@telemetry.set_json(span, "app.metadata", { "source": "api", "depth": 2 })
@telemetry.end_span(span)
```

`set_json_attribute` serializes the `Json` value to a string, which is useful for structured metadata that does not fit the scalar attribute types. For arbitrary attribute lists you can still use `set_attributes(span, attrs)` with `@otel.KeyValue` values.

## Instrumentation Guide

See [docs/instrumentation.md](docs/instrumentation.md) for a step-by-step guide that shows how to instrument LLM chat requests, tool executions, and agent turns using the `agent-observability` sample application as a reference.

## Environment Variables

`init_from_env` reads the following variables:

| Variable | Description | Default |
|---|---|---|
| `OTEL_SERVICE_NAME` | Service name | `agent-telemetry` |
| `OTEL_STDOUT` | Use the stdout exporter when set to `true` | `false` |
| `OTEL_EXPORTER_OTLP_ENDPOINT` | OTLP/HTTP endpoint | `http://localhost:4318` |
| `OTEL_EXPORTER_OTLP_HEADERS` | Global OTLP headers, comma-separated `key=value` pairs | *(empty)* |
| `OTEL_EXPORTER_OTLP_TRACES_HEADERS` | Trace-specific OTLP headers | *(empty, falls back to global)* |
| `OTEL_EXPORTER_OTLP_METRICS_HEADERS` | Metric-specific OTLP headers | *(empty, falls back to global)* |
| `OTEL_EXPORTER_OTLP_LOGS_HEADERS` | Log-specific OTLP headers | *(empty, falls back to global)* |
| `GREPTIME_TRACE_PIPELINE` | GreptimeDB trace pipeline name | `greptime_trace_v1` |
| `GREPTIME_LOG_TABLE` | Target table for conversation logs | `genai_conversations` |

Signal-specific header variables take precedence over `OTEL_EXPORTER_OTLP_HEADERS`. This is useful for backends that require authentication tokens or custom routing headers.

For example:

```bash
OTEL_EXPORTER_OTLP_LOGS_HEADERS="Authorization=Bearer my-token, X-Scope-OrgID=tenant-1"
```

## Log Routing

The library maintains two separate loggers:

- **Default logger** (`logger` / `log_info` / `log_warn` / `log_error`) writes to the standard OTLP logs table (`opentelemetry_logs` by default).
- **Conversation logger** (`conversation_logger` / `log_conversation_message`) writes to the table configured by `GREPTIME_LOG_TABLE` (default `genai_conversations`).

When exporting to GreptimeDB, this lets you keep general application logs and LLM conversation logs in separate tables.

## Flushing and Shutting Down

`TelemetryProviders` exposes `force_flush()` and `shutdown()` methods that flush/shutdown all three providers (traces, metrics, logs) and print any errors to stdout.

```moonbit
providers.force_flush()
providers.shutdown()
```

Always call `shutdown` before the process exits so pending telemetry is exported.

## ID Generator Option

The `id_generator` parameter of `init_telemetry` / `init_from_env` supports:

| Option | Description |
|---|---|
| `@telemetry.SdkDefault` | Use the SDK default `RandomIdGenerator` |
| `@telemetry.ProcessUniqueRandom` | Generate a process-unique seed from the current timestamp and a counter, avoiding duplicate trace/span IDs across restarts |
| `@telemetry.Custom(generator)` | Provide your own `IdGenerator` |

## Target Backend

This library depends on `opentelemetry/otlp`, whose `async/http` and `async/socket` interfaces are **native-only**. Therefore `moon.mod` declares `preferred_target = "native"`. Projects using this library should also run and test with `--target native`.

## Example Project

A complete agent example using this library can be found at:

[github.com/cybershang/moonbit-agent-observability](https://github.com/cybershang/moonbit-agent-observability)

## Testing

```bash
moon test -p cybershang/agent-telemetry --target native
```

## License

Mulan PSL v2
