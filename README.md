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
let provider = @telemetry.init_from_env(
  id_generator=@telemetry.ProcessUniqueRandom,
)

// Option 2: manually select an exporter.
let config = @telemetry.TelemetryConfig::new(service_name="my-agent")
let provider = @telemetry.init_telemetry(
  config,
  @telemetry.Otlp("http://localhost:4318"),
  id_generator=@telemetry.ProcessUniqueRandom,
)

// Create a GenAI chat span.
let tracer = @telemetry.tracer("my-agent/llm")
let span = @telemetry.start_chat_span(
  tracer,
  provider_name="stepfun",
  model="step-3.7-flash",
  max_tokens=1024,
)
// ... send the request and obtain response_json ...
@telemetry.record_chat_response(span, response_json)
@telemetry.end_span_ok(span)
```

## Main API

| Scenario | Functions |
|---|---|
| General | `TelemetryConfig::new`, `init_telemetry`, `init_from_env`, `IdGeneratorOption`, `tracer`, `start_span`, `end_span`, `end_span_ok`, `end_span_error` |
| LLM chat | `start_chat_span`, `record_chat_usage`, `record_chat_response`, `set_chat_http_error` |
| Tool | `start_tool_span`, `record_tool_result`, `set_tool_error` |
| Agent turn | `start_agent_turn_span`, `record_turn_metrics`, `set_turn_max_tool_turns_error` |

## Environment Variables

`init_from_env` reads the following variables:

| Variable | Description | Default |
|---|---|---|
| `OTEL_SERVICE_NAME` | Service name | `agent-telemetry` |
| `OTEL_STDOUT` | Use the stdout exporter when set to `true` | `false` |
| `OTEL_EXPORTER_OTLP_ENDPOINT` | OTLP/HTTP endpoint | `http://localhost:4318` |

## ID Generator Option

The `id_generator` parameter of `init_telemetry` / `init_from_env` supports:

| Option | Description |
|---|---|
| `@telemetry.SdkDefault` | Use the SDK default `RandomIdGenerator` |
| `@telemetry.ProcessUniqueRandom` | Generate a process-unique seed from the current timestamp and a counter, avoiding duplicate trace/span IDs across restarts |
| `@telemetry.Custom(generator)` | Provide your own `IdGenerator` |

## Target Backend

This library depends on `opentelemetry/otlp`, whose `async/http` and `async/socket` interfaces are **native-only**. Therefore `moon.mod` declares `preferred_target = "native"`. Projects using this library should also run and test with `--target native`.

## Testing

```bash
moon test -p cybershang/agent-telemetry --target native
```

## License

Mulan PSL v2
