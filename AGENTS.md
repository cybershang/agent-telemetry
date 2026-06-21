# agent-telemetry

`agent-telemetry` is a MoonBit library that wraps OpenTelemetry boilerplate into
business-semantic helpers for MoonBit Agent / LLM / Tool scenarios. It is
published as `cybershang/agent-telemetry` on [mooncakes.io](https://mooncakes.io).

## Technology stack

- **Language**: MoonBit
- **Build tool**: `moon` (the MoonBit toolchain)
- **Package manager**: `mooncakes` / `moon add`
- **Supported target**: `native` only (`preferred_target = "native"` in `moon.mod`)
- **License**: Mulan PSL v2

The library depends on:

- `moonbitlang/async@0.19.2`
- `moonbitlang/protobuf@0.1.1`
- `moonbit-community/opentelemetry@0.1.4`

Because `opentelemetry/otlp` exposes `async/http` and `async/socket` interfaces
that are native-only, all build and test commands must use `--target native`.

## Local reference sources

A local clone of the MoonBit standard library and related ecosystem repositories
is available at `../moonbit-repos/` (relative to this project root). The
`moonbit-repos/core/` directory contains the MoonBit core package source, which
can be consulted to learn the implementation details of builtin and standard
library functions/methods before modifying code.

## Project structure

The project is a single MoonBit package with all source files at the repository
root:

| File | Purpose |
|---|---|
| `moon.mod` | Module metadata: name, version, dependencies, supported targets. |
| `moon.pkg` | Package imports, aliased with `@process`, `@random`, `@otel`, `@common`, `@context`, `@trace`, `@otlp`, `@print`, `@sdk`, `@resource`, `@sdktrace`, `@semtrace`. `moonbitlang/async` is imported only for tests because the library's production code does not reference it directly. |
| `lib.mbt` | Core API: `TelemetryConfig`, `ExporterType`, `IdGeneratorOption`, `init_telemetry`, `init_from_env`, `tracer`, `start_span`, `end_span`, `end_span_ok`, `end_span_error`, `set_attributes`. |
| `id_generator.mbt` | Process-unique random ID generator workaround for the SDK default fixed seed. |
| `genai.mbt` | GenAI chat span helpers: `start_chat_span`, `record_chat_usage`, `record_chat_response`, `set_chat_http_error`. |
| `tool.mbt` | Tool execution span helpers: `start_tool_span`, `record_tool_result`, `set_tool_error`. |
| `agent.mbt` | Agent turn span helpers: `start_agent_turn_span`, `record_turn_metrics`, `set_turn_max_tool_turns_error`. |
| `lib_test.mbt` | Tests for core span lifecycle and tracer cache. |
| `genai_test.mbt` | Tests for GenAI chat span attributes and error handling. |
| `tool_test.mbt` | Tests for tool span attributes and result handling. |
| `agent_test.mbt` | Tests for agent turn span attributes and error handling. |

The public package name used by consumers is `@telemetry` (derived from the
module name `cybershang/agent-telemetry`).

## Build and test commands

Always target `native`:

```bash
# Check the package
moon check --target native

# Build the package
moon build --target native

# Run tests
moon test --target native
```

The current test suite contains 15 tests and should pass without failures. The
CI also runs these commands implicitly before publishing.

## Code style guidelines

- Every `.mbt` file starts with the standard copyright header:

  ```
  // Copyright (c) 2026 Yingjie Shang
  // agent-telemetry is licensed under Mulan PSL v2.
  ```

- Use `///|` for public API documentation comments.
- Use section banners such as `///| Types`, `///| OpenTelemetry provider initialization`,
  and `///| Internal helpers` to group related code.
- Public structs, enums, and functions are documented with a short purpose line.
- Aliased imports are used consistently; prefer the aliases defined in
  `moon.pkg` when touching OTel-related code.
- Async functions are used for initialization and span finalization because
  exporters and ID generator setup perform async I/O.

## Testing instructions

- Tests live in `*_test.mbt` files next to the code they exercise.
- Tests use an in-memory span exporter (`@sdktrace.InMemorySpanExporter`) and a
  helper named `make_test_tracer()` defined in `lib_test.mbt`.
- A shared helper `find_attr(span, key)` is used to inspect span attributes in
  tests.
- Tests are written as `async test "..." { ... }` blocks because many helper
  functions are async.
- Run `moon test --target native` to execute the full suite.

## Runtime architecture

1. **Initialization**: Call `init_telemetry` or `init_from_env` to create an
   `@sdktrace.SdkTracerProvider`, configure a resource, and install it as the
   global tracer provider.
2. **Exporter selection**: `ExporterType` supports `Stdout`, `Otlp(endpoint)`,
   `Custom(exporter)`, and `NoOp`. OTLP exporter construction errors are logged
   to stdout and fall back to a no-op provider.
3. **Tracer cache**: `tracer(scope_name)` caches tracers by scope name so repeat
   calls return the same instance.
4. **Span helpers**: Domain-specific helpers in `genai.mbt`, `tool.mbt`, and
   `agent.mbt` create spans with the correct names, kinds, and attributes
   according to OpenTelemetry GenAI semantic conventions.
5. **ID generator option**: `SdkDefault`, `ProcessUniqueRandom`, or a custom
   `@sdktrace.IdGenerator`. `ProcessUniqueRandom` works around duplicate IDs
   across process restarts by seeding from a timestamp and a per-process counter.

## Environment variables

`init_from_env` reads:

| Variable | Description | Default |
|---|---|---|
| `OTEL_SERVICE_NAME` | Service name | `agent-telemetry` |
| `OTEL_STDOUT` | Use the stdout exporter when set to `true` | `false` |
| `OTEL_EXPORTER_OTLP_ENDPOINT` | OTLP/HTTP endpoint | `http://localhost:4318` |

## Deployment process

The project is published to mooncakes.io via GitHub Actions
(`.github/workflows/publish.yml`):

- Triggered on pushes to tags matching `v*` or manually via `workflow_dispatch`.
- Uses `cogna-dev/moonbit-actions/setup@v0` to install the MoonBit toolchain.
- Decodes `MOONCAKES_TOKEN` into `~/.moon/credentials.json` and runs
  `yes | moon publish`.

## Security considerations

- The OTLP exporter is built with the endpoint string supplied by the caller or
  environment. Validate endpoints if they come from untrusted input.
- `init_from_env` reads environment variables directly; ensure the runtime
  environment is trusted when using this convenience initializer.
- The `ProcessUniqueRandom` ID generator shells out to `date +%s%N` to obtain a
  timestamp seed. If this subprocess fails, it falls back to `"0"`, which
  weakens the uniqueness guarantee for that generator instance.
- The `Custom(@sdktrace.SpanExporter)` and `Custom(@sdktrace.IdGenerator)`
  variants allow caller-supplied code; treat these as trusted extensions.
