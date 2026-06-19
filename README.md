# agent-telemetry

MoonBit 的 Agent / LLM / Tool 场景 OpenTelemetry 插桩库。

把原本需要手写的大量 OTel tracer/span/attribute 样板代码，封装成一组面向业务语义的 helper，让 Agent 开发者只关注何时创建 span、需要记录哪些业务数据。

## 设计分层

- **薄封装**（`lib.mbt`）：provider 初始化、tracer 缓存、`start_span` / `end_span` 等生命周期 helper。
- **语义封装**（`genai.mbt` / `tool.mbt` / `agent.mbt`）：按 OpenTelemetry GenAI semantic conventions 设置属性，覆盖 chat / tool execution / agent turn 三类 span。

## 快速开始

```bash
moon add cybershang/agent-telemetry
```

```moonbit
// 方式 1：从环境变量一键初始化
// 读取 OTEL_SERVICE_NAME、OTEL_STDOUT、OTEL_EXPORTER_OTLP_ENDPOINT
// 使用 ProcessUniqueRandom 避免进程重启后 trace/span ID 重复
let provider = @telemetry.init_from_env(
  id_generator=@telemetry.ProcessUniqueRandom,
)

// 方式 2：手动指定 exporter
let config = @telemetry.TelemetryConfig::new(service_name="my-agent")
let provider = @telemetry.init_telemetry(
  config,
  @telemetry.Otlp("http://localhost:4318"),
  id_generator=@telemetry.ProcessUniqueRandom,
)

// 创建 GenAI chat span
let tracer = @telemetry.tracer("my-agent/llm")
let span = @telemetry.start_chat_span(
  tracer,
  provider_name="stepfun",
  model="step-3.7-flash",
  max_tokens=1024,
)
// ... 发起请求并拿到 response_json ...
@telemetry.record_chat_response(span, response_json)
@telemetry.end_span_ok(span)
```

## 主要 API

| 场景 | 函数 |
|---|---|
| 通用 | `TelemetryConfig::new`、`init_telemetry`、`init_from_env`、`IdGeneratorOption`、`tracer`、`start_span`、`end_span`、`end_span_ok`、`end_span_error` |
| LLM chat | `start_chat_span`、`record_chat_usage`、`record_chat_response`、`set_chat_http_error` |
| Tool | `start_tool_span`、`record_tool_result`、`set_tool_error` |
| Agent turn | `start_agent_turn_span`、`record_turn_metrics`、`set_turn_max_tool_turns_error` |

## 环境变量

`init_from_env` 会读取以下变量：

| 变量 | 说明 | 默认值 |
|---|---|---|
| `OTEL_SERVICE_NAME` | 服务名 | `agent-telemetry` |
| `OTEL_STDOUT` | 为 `true` 时使用 stdout exporter | `false` |
| `OTEL_EXPORTER_OTLP_ENDPOINT` | OTLP/HTTP 端点 | `http://localhost:4318` |

## ID 生成器选项

`init_telemetry` / `init_from_env` 通过 `id_generator` 参数支持三种方式：

| 选项 | 说明 |
|---|---|
| `@telemetry.SdkDefault` | 使用 SDK 默认 `RandomIdGenerator` |
| `@telemetry.ProcessUniqueRandom` | 用当前时间戳 + 进程计数器生成唯一种子，避免进程重启后 trace/span ID 重复 |
| `@telemetry.Custom(generator)` | 传入自定义 `IdGenerator` |

## 目标后端

本库依赖 `opentelemetry/otlp` 的 `async/http`、`async/socket` 接口，这些接口只在 **native** 后端可用，因此 `moon.mod` 声明了 `preferred_target = "native"`。使用本库的项目也请以 `--target native` 运行和测试。

## 测试

```bash
moon test -p cybershang/agent-telemetry --target native
```

## 许可证

Mulan PSL v2
