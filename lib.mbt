// Copyright (c) 2026 Yingjie Shang
// agent-telemetry is licensed under Mulan PSL v2.

///| Types

///|
/// Configuration for initializing OpenTelemetry in an agent application.
pub struct TelemetryConfig {
  service_name : String
} derive(Debug)

///|
/// Create a new telemetry configuration.
pub fn TelemetryConfig::new(
  service_name? : String = "agent-telemetry",
) -> TelemetryConfig {
  { service_name, }
}

///|
/// Exporter type for telemetry initialization.
pub(all) enum ExporterType {
  /// Print spans to stdout using the simple span processor.
  Stdout
  /// Export spans via OTLP/HTTP to the given endpoint.
  Otlp(String)
  /// Use a caller-provided span exporter.
  Custom(@sdktrace.SpanExporter)
  /// Do not export any spans (no-op provider).
  NoOp
}

///|
/// ID generator option for telemetry initialization.
pub(all) enum IdGeneratorOption {
  /// Use the SDK default RandomIdGenerator.
  SdkDefault
  /// Use a process-unique random seed (workaround for SDK default duplicate IDs).
  ProcessUniqueRandom
  /// Use a caller-provided IdGenerator.
  Custom(@sdktrace.IdGenerator)
}

///|
/// Holder for all initialized OpenTelemetry SDK providers.
pub struct TelemetryProviders {
  tracer_provider : @sdktrace.SdkTracerProvider
  meter_provider : @sdkmetrics.SdkMeterProvider
  logger_provider : @sdklogs.SdkLoggerProvider
  conversation_logger_provider : @sdklogs.SdkLoggerProvider
  resource : @resource.Resource
}

///|
/// Global TelemetryProviders set by `init_telemetry` / `init_from_env`.
/// Used by the parameter-less `meter()` / `logger()` functions.
let global_providers : Ref[TelemetryProviders?] = Ref(None)

///| OpenTelemetry provider initialization

///|
/// Initialize the global OpenTelemetry providers (traces, metrics, logs).
pub async fn init_telemetry(
  config : TelemetryConfig,
  exporter_type : ExporterType,
  id_generator? : IdGeneratorOption = SdkDefault,
) -> TelemetryProviders {
  do_init_telemetry(config, exporter_type, id_generator~)
}

///|
/// Initialize the global providers from standard environment variables.
///
/// Reads:
/// - `OTEL_SERVICE_NAME` (overrides `service_name`)
/// - `OTEL_STDOUT` (`true` selects the stdout exporter)
/// - `OTEL_EXPORTER_OTLP_ENDPOINT` (when `OTEL_STDOUT` is not `true`)
pub async fn init_from_env(
  service_name? : String = "agent-telemetry",
  id_generator? : IdGeneratorOption = SdkDefault,
) -> TelemetryProviders {
  let service_name = env_with_dotenv("OTEL_SERVICE_NAME").unwrap_or(
    service_name,
  )
  let config = TelemetryConfig::new(service_name~)
  let otel_stdout = env_with_dotenv("OTEL_STDOUT").unwrap_or("").to_lower() ==
    "true"
  let otel_endpoint = env_with_dotenv("OTEL_EXPORTER_OTLP_ENDPOINT").unwrap_or(
    "http://localhost:4318",
  )
  let exporter_type = if otel_stdout { Stdout } else { Otlp(otel_endpoint) }
  do_init_telemetry(config, exporter_type, id_generator~)
}

///| Internal helpers

///|
/// Read a configuration value from the process environment or `.env` file.
async fn env_with_dotenv(key : String) -> String? {
  match @env.get_env_var(key) {
    Some(value) => Some(value)
    None => read_dotenv(key)
  }
}

///|
/// Read a value from the `.env` file in the current working directory.
async fn read_dotenv(key : String) -> String? {
  let content = (@fs.read_file(".env").text() : String) catch {
    _ => return None
  }
  for line in content.split("\n") {
    let trimmed = line.trim(char_set="\r ")
    if trimmed.is_empty() || trimmed.has_prefix("#") {
      continue
    }
    match trimmed.split_once("=") {
      Some((k, v)) => if k == key { return Some(v.to_owned()) }
      None => continue
    }
  }
  None
}

///|
/// Resolve an IdGeneratorOption into a concrete IdGenerator.
async fn resolve_id_generator(
  option : IdGeneratorOption,
) -> @sdktrace.IdGenerator {
  match option {
    SdkDefault => @sdktrace.RandomIdGenerator::new().into_id_generator()
    ProcessUniqueRandom => make_random_id_generator()
    Custom(generator) => generator
  }
}

///|
/// Shared provider setup used by `init_telemetry` and `init_from_env`.
async fn do_init_telemetry(
  config : TelemetryConfig,
  exporter_type : ExporterType,
  id_generator? : IdGeneratorOption = SdkDefault,
) -> TelemetryProviders {
  let id_generator = resolve_id_generator(id_generator)
  let resource = build_resource(config.service_name)

  // Traces
  let trace_exporter = match build_trace_exporter(exporter_type) {
    Some(exporter) => safe_span_exporter(exporter)
    None => noop_span_exporter()
  }
  let trace_batch_config = @sdktrace.BatchConfig::new(
    max_queue_size=64,
    max_export_batch_size=16,
    scheduled_delay_millis=1000,
    export_timeout_millis=5000,
  )
  let tracer_provider = @sdk.tracer_provider_builder()
    .with_resource(resource)
    .with_id_generator(id_generator)
    .with_batch_exporter(trace_exporter, config=trace_batch_config)
    .build()
  @sdk.set_tracer_provider(tracer_provider)

  // Metrics
  let metric_exporter = match build_metric_exporter(exporter_type) {
    Some(exporter) => exporter
    None => @sdkmetrics.InMemoryMetricExporter::new().into_metric_exporter()
  }
  let meter_provider = @sdkmetrics.SdkMeterProvider::builder()
    .with_resource(resource)
    .with_periodic_exporter(metric_exporter, interval_millis=60000)
    .build()
  @sdk.set_meter_provider(meter_provider)

  // Logs
  let log_batch_config = @sdklogs.BatchConfig::new(
    max_queue_size=2048,
    max_export_batch_size=512,
    scheduled_delay_millis=1000,
    export_timeout_millis=30000,
  )

  // Default logger writes to opentelemetry_logs (no custom table header).
  let log_exporter = match build_log_exporter(exporter_type) {
    Some(exporter) => safe_log_exporter(exporter)
    None => @sdklogs.InMemoryLogExporter::new().into_log_exporter()
  }
  let logger_provider = @sdklogs.SdkLoggerProvider::builder()
    .with_resource(resource)
    .with_batch_exporter(log_exporter, config=log_batch_config)
    .build()
  @sdk.set_logger_provider(logger_provider)

  // Conversation logger writes to the configured GenAI conversations table.
  let conversation_log_table = env_with_dotenv("GREPTIME_LOG_TABLE").unwrap_or(
    "genai_conversations",
  )
  let conversation_log_exporter = match
    build_log_exporter(exporter_type, log_table=Some(conversation_log_table)) {
    Some(exporter) => safe_log_exporter(exporter)
    None => @sdklogs.InMemoryLogExporter::new().into_log_exporter()
  }
  let conversation_logger_provider = @sdklogs.SdkLoggerProvider::builder()
    .with_resource(resource)
    .with_batch_exporter(conversation_log_exporter, config=log_batch_config)
    .build()

  let providers = {
    tracer_provider,
    meter_provider,
    logger_provider,
    conversation_logger_provider,
    resource,
  }
  global_providers.val = Some(providers)
  let exporter_kind = match exporter_type {
    Stdout => "stdout"
    Otlp(endpoint) => "otlp:" + endpoint
    Custom(_) => "custom"
    NoOp => "noop"
  }
  log_info("cybershang/agent-telemetry", "Telemetry initialized", attributes=[
    @otel.KeyValue::new("service.name", String(config.service_name)),
    @otel.KeyValue::new("telemetry.exporter.kind", String(exporter_kind)),
  ]) catch {
    _ => ()
  }
  providers
}

///| Internal helpers

///|
/// Build a no-op span exporter that silently discards all spans.
fn noop_span_exporter() -> @sdktrace.SpanExporter {
  @sdktrace.SpanExporter::new(
    fn(_batch) { @error.ok() },
    force_flush_fn=fn() { @error.ok() },
    shutdown_fn=fn() { @error.ok() },
    name_fn=() => "noop",
  )
}

///|
/// Wrap a span exporter so that export/flush/shutdown errors are turned into
/// `ExportFailure` results instead of being raised. This keeps OTLP network
/// failures (e.g. "Connection refused") from crashing the application.
fn safe_span_exporter(inner : @sdktrace.SpanExporter) -> @sdktrace.SpanExporter {
  let name = inner.name()
  @sdktrace.SpanExporter::new(
    async fn(batch) {
      inner.export_batch(batch) catch {
        err =>
          @error.export_failure(
            name,
            "export failed: " + format_telemetry_error(err),
          )
      }
    },
    force_flush_fn=async fn() {
      inner.force_flush() catch {
        err =>
          @error.export_failure(
            name,
            "force_flush failed: " + format_telemetry_error(err),
          )
      }
    },
    shutdown_fn=async fn() {
      inner.shutdown() catch {
        err =>
          @error.export_failure(
            name,
            "shutdown failed: " + format_telemetry_error(err),
          )
      }
    },
    name_fn=() => name,
  )
}

///|
/// Wrap a log exporter so that export/flush/shutdown errors are logged to stdout
/// instead of being raised. This prevents OTLP network failures from crashing
/// the application or failing log emission.
fn safe_log_exporter(inner : @sdklogs.LogExporter) -> @sdklogs.LogExporter {
  let name = inner.name()
  @sdklogs.LogExporter::new(
    async fn(batch) {
      inner.export_batch(batch) catch {
        err => {
          @stdio.stdout.write(
            "[Telemetry] log export failed: " +
            format_telemetry_error(err) +
            "\n",
          )
          @error.export_failure(
            name,
            "export failed: " + format_telemetry_error(err),
          )
        }
      }
    },
    force_flush_fn=async fn() {
      inner.force_flush() catch {
        err => {
          @stdio.stdout.write(
            "[Telemetry] log force_flush failed: " +
            format_telemetry_error(err) +
            "\n",
          )
          @error.export_failure(
            name,
            "force_flush failed: " + format_telemetry_error(err),
          )
        }
      }
    },
    shutdown_fn=async fn() {
      inner.shutdown() catch {
        err => {
          @stdio.stdout.write(
            "[Telemetry] log shutdown failed: " +
            format_telemetry_error(err) +
            "\n",
          )
          @error.export_failure(
            name,
            "shutdown failed: " + format_telemetry_error(err),
          )
        }
      }
    },
    name_fn=() => name,
  )
}

///|
/// Current wall-clock time in seconds since the Unix epoch.
pub async fn now_seconds() -> Double {
  let (code, stdout, _stderr) = @process.collect_output("date", ["+%s.%N"])
  let text = if code == 0 { stdout.text().trim().to_owned() } else { "0" }
  @string.parse_double(text) catch {
    _ => 0.0
  }
}

///|
/// Format an arbitrary error for telemetry diagnostics.
fn format_telemetry_error(err : Error) -> String {
  err.to_string()
}

///|
/// Format an OTel SDK error for diagnostics.
fn format_otel_sdk_error(err : @error.OTelSdkError) -> String {
  match err {
    AlreadyShutdown => "AlreadyShutdown"
    Timeout(ms) => "Timeout(\{ms}ms)"
    InvalidArgument(msg) => "InvalidArgument(\{msg})"
    InternalFailure(msg) => "InternalFailure(\{msg})"
    ExportFailure(name, msg) => "ExportFailure(\{name}, \{msg})"
  }
}

///|
/// Append the OTLP signal path if the endpoint is a base URL.
fn normalize_signal_endpoint(endpoint : String, signal_path : String) -> String {
  let trimmed = endpoint.trim_end(chars="/").to_owned()
  if trimmed.has_suffix(signal_path) {
    trimmed
  } else {
    trimmed + signal_path
  }
}

///|
/// Parse a comma-separated `key1=value1,key2=value2` string into a header map.
fn parse_header_env(value : String) -> Map[String, String] {
  let headers : Map[String, String] = {}
  for part in value.split(",") {
    let trimmed = part.trim(char_set=" ")
    if trimmed.is_empty() {
      continue
    }
    match trimmed.split_once("=") {
      Some((k, v)) =>
        headers[k.trim(char_set=" ").to_owned()] = v
          .trim(char_set=" ")
          .to_owned()
      None => ()
    }
  }
  headers
}

///|
/// Build the initial header map for a signal-specific OTLP exporter.
/// Reads `OTEL_EXPORTER_OTLP_<SIGNAL>_HEADERS` first, then falls back to
/// `OTEL_EXPORTER_OTLP_HEADERS`.
async fn build_signal_headers(signal_key : String) -> Map[String, String] {
  let signal_value = env_with_dotenv(
    "OTEL_EXPORTER_OTLP_" + signal_key + "_HEADERS",
  ).unwrap_or("")
  if signal_value != "" {
    parse_header_env(signal_value)
  } else {
    let global_value = env_with_dotenv("OTEL_EXPORTER_OTLP_HEADERS").unwrap_or(
      "",
    )
    if global_value != "" {
      parse_header_env(global_value)
    } else {
      {}
    }
  }
}

///|
/// Build a span exporter from the requested exporter type.
async fn build_trace_exporter(
  exporter_type : ExporterType,
) -> @sdktrace.SpanExporter? {
  match exporter_type {
    Stdout => Some(@print.SpanExporter::new().into_span_exporter())
    Otlp(endpoint) => {
      let headers = build_signal_headers("TRACES")
      let trace_pipeline = env_with_dotenv("GREPTIME_TRACE_PIPELINE").unwrap_or(
        "greptime_trace_v1",
      )
      if !headers.contains("X-Greptime-Pipeline-Name") {
        headers["X-Greptime-Pipeline-Name"] = trace_pipeline
      }
      match
        @otlp.SpanExporter::builder()
        .with_http()
        .with_endpoint(normalize_signal_endpoint(endpoint, "/v1/traces"))
        .with_headers(headers)
        .build() {
        Ok(exporter) => Some(exporter.into_span_exporter())
        Err(err) => {
          let err_text = match err {
            InvalidConfig(key, msg) => "InvalidConfig(\{key}, \{msg})"
            UnsupportedProtocol(p) => "UnsupportedProtocol(\{p})"
            UnsupportedCompressionAlgorithm(a) =>
              "UnsupportedCompressionAlgorithm(\{a})"
          }
          @stdio.stdout.write(
            "[Telemetry] Failed to build OTLP trace exporter for endpoint " +
            endpoint +
            ": " +
            err_text +
            ". Traces will be disabled.\n",
          )
          None
        }
      }
    }
    Custom(exporter) => Some(exporter)
    NoOp => None
  }
}

///|
/// Build a metric exporter from the requested exporter type.
async fn build_metric_exporter(
  exporter_type : ExporterType,
) -> @sdkmetrics.MetricExporter? {
  match exporter_type {
    Stdout => None
    Otlp(endpoint) => {
      let headers = build_signal_headers("METRICS")
      match
        @otlp.MetricExporter::builder()
        .with_http()
        .with_endpoint(normalize_signal_endpoint(endpoint, "/v1/metrics"))
        .with_headers(headers)
        .build() {
        Ok(exporter) => Some(exporter.into_metric_exporter())
        Err(err) => {
          let err_text = match err {
            InvalidConfig(key, msg) => "InvalidConfig(\{key}, \{msg})"
            UnsupportedProtocol(p) => "UnsupportedProtocol(\{p})"
            UnsupportedCompressionAlgorithm(a) =>
              "UnsupportedCompressionAlgorithm(\{a})"
          }
          @stdio.stdout.write(
            "[Telemetry] Failed to build OTLP metric exporter: " +
            err_text +
            ". Metrics will be disabled.\n",
          )
          None
        }
      }
    }
    Custom(_) => None
    NoOp => None
  }
}

///|
/// Build a log exporter from the requested exporter type.
/// When `log_table` is provided, the exporter sets `X-Greptime-Log-Table-Name`
/// so logs are routed to that custom table. Otherwise logs go to the default
/// `opentelemetry_logs` table.
async fn build_log_exporter(
  exporter_type : ExporterType,
  log_table? : String? = None,
) -> @sdklogs.LogExporter? {
  match exporter_type {
    Stdout => None
    Otlp(endpoint) => {
      let headers = build_signal_headers("LOGS")
      match log_table {
        Some(table) =>
          if !headers.contains("X-Greptime-Log-Table-Name") {
            headers["X-Greptime-Log-Table-Name"] = table
          }
        None => ()
      }
      match
        @otlp.LogExporter::builder()
        .with_http()
        .with_endpoint(normalize_signal_endpoint(endpoint, "/v1/logs"))
        .with_headers(headers)
        .build() {
        Ok(exporter) => Some(exporter.into_log_exporter())
        Err(err) => {
          let err_text = match err {
            InvalidConfig(key, msg) => "InvalidConfig(\{key}, \{msg})"
            UnsupportedProtocol(p) => "UnsupportedProtocol(\{p})"
            UnsupportedCompressionAlgorithm(a) =>
              "UnsupportedCompressionAlgorithm(\{a})"
          }
          @stdio.stdout.write(
            "[Telemetry] Failed to build OTLP log exporter: " +
            err_text +
            ". Logs will be disabled.\n",
          )
          None
        }
      }
    }
    Custom(_) => None
    NoOp => None
  }
}

///| Lifecycle helpers

///|
/// Spawn background tasks required by metrics (periodic reader) and logs (batch processor).
pub fn TelemetryProviders::spawn_background_tasks(
  self : TelemetryProviders,
  group : @async.TaskGroup[Unit],
  allow_failure? : Bool = false,
) -> Unit {
  self.meter_provider.spawn_periodic_readers(group, allow_failure~)
  self.logger_provider.spawn_batch_processor_tasks(group, allow_failure~)
  self.conversation_logger_provider.spawn_batch_processor_tasks(
    group,
    allow_failure~,
  )
}

///|
/// Flush all providers and print any errors.
pub async fn TelemetryProviders::force_flush(self : TelemetryProviders) -> Unit {
  match self.tracer_provider.force_flush() {
    Ok(_) => ()
    Err(err) =>
      @stdio.stdout.write(
        "[Telemetry] trace force_flush failed: " +
        format_otel_sdk_error(err) +
        "\n",
      )
  }
  match self.meter_provider.force_flush() {
    Ok(_) => ()
    Err(err) =>
      @stdio.stdout.write(
        "[Telemetry] metric force_flush failed: " +
        format_otel_sdk_error(err) +
        "\n",
      )
  }
  match self.logger_provider.force_flush() {
    Ok(_) => ()
    Err(err) =>
      @stdio.stdout.write(
        "[Telemetry] log force_flush failed: " +
        format_otel_sdk_error(err) +
        "\n",
      )
  }
  match self.conversation_logger_provider.force_flush() {
    Ok(_) => ()
    Err(err) =>
      @stdio.stdout.write(
        "[Telemetry] conversation log force_flush failed: " +
        format_otel_sdk_error(err) +
        "\n",
      )
  }
}

///|
/// Shut down all providers and print any errors.
pub async fn TelemetryProviders::shutdown(self : TelemetryProviders) -> Unit {
  match self.tracer_provider.shutdown() {
    Ok(_) => ()
    Err(err) =>
      @stdio.stdout.write(
        "[Telemetry] trace shutdown failed: " +
        format_otel_sdk_error(err) +
        "\n",
      )
  }
  match self.meter_provider.shutdown() {
    Ok(_) => ()
    Err(err) =>
      @stdio.stdout.write(
        "[Telemetry] metric shutdown failed: " +
        format_otel_sdk_error(err) +
        "\n",
      )
  }
  match self.logger_provider.shutdown() {
    Ok(_) => ()
    Err(err) =>
      @stdio.stdout.write(
        "[Telemetry] log shutdown failed: " + format_otel_sdk_error(err) + "\n",
      )
  }
  match self.conversation_logger_provider.shutdown() {
    Ok(_) => ()
    Err(err) =>
      @stdio.stdout.write(
        "[Telemetry] conversation log shutdown failed: " +
        format_otel_sdk_error(err) +
        "\n",
      )
  }
}

///| Meter cache

///|
/// Cache of meters keyed by scope name.
let meter_cache : Ref[Map[String, @metrics.Meter]] = Ref({})

///|
/// Get or create a meter for the given scope name.
pub fn meter(scope_name : String) -> @metrics.Meter {
  match meter_cache.val.get(scope_name) {
    Some(m) => m
    None => {
      let provider = match global_providers.val {
        Some(providers) => providers.meter_provider.into_meter_provider()
        None => @metrics.MeterProvider::noop()
      }
      let m = provider.meter(scope_name)
      meter_cache.val.set(scope_name, m)
      m
    }
  }
}

///| Logger caches

///|
/// Cache of default loggers keyed by scope name.
let logger_cache : Ref[Map[String, @logs.Logger]] = Ref({})

///|
/// Get or create a logger for the given scope name.
/// Logs from this logger go to the default `opentelemetry_logs` table.
pub fn logger(scope_name : String) -> @logs.Logger {
  match logger_cache.val.get(scope_name) {
    Some(l) => l
    None => {
      let provider = match global_providers.val {
        Some(providers) => providers.logger_provider.into_logger_provider()
        None => @logs.LoggerProvider::noop()
      }
      let l = provider.logger(scope_name)
      logger_cache.val.set(scope_name, l)
      l
    }
  }
}

///|
/// Cache of conversation loggers keyed by scope name.
let conversation_logger_cache : Ref[Map[String, @logs.Logger]] = Ref({})

///|
/// Get or create a logger for conversation messages.
/// Logs from this logger go to the configured GenAI conversations table
/// (default `genai_conversations`).
pub fn conversation_logger(scope_name : String) -> @logs.Logger {
  match conversation_logger_cache.val.get(scope_name) {
    Some(l) => l
    None => {
      let provider = match global_providers.val {
        Some(providers) =>
          providers.conversation_logger_provider.into_logger_provider()
        None => @logs.LoggerProvider::noop()
      }
      let l = provider.logger(scope_name)
      conversation_logger_cache.val.set(scope_name, l)
      l
    }
  }
}

///| Tracer cache

///|
/// Cache of tracers keyed by scope name.
let tracer_cache : Ref[Map[String, @trace.Tracer]] = Ref({})

///|
/// Get or create a tracer for the given scope name.
pub fn tracer(
  scope_name : String,
  version? : String = "0.1.0",
) -> @trace.Tracer {
  match tracer_cache.val.get(scope_name) {
    Some(t) => t
    None => {
      let t = @otel.tracer(scope_name, version=Some(version))
      tracer_cache.val.set(scope_name, t)
      t
    }
  }
}

///| Span lifecycle helpers

///|
/// Start a new span with the given tracer.
pub fn start_span(
  tracer : @trace.Tracer,
  name : String,
  kind? : @trace.SpanKind = @trace.Internal,
  attributes? : Array[@otel.KeyValue] = [],
  parent_context? : @context.Context = @context.Context::empty(),
) -> @trace.Span {
  let builder = tracer
    .span_builder(name)
    .with_kind(kind)
    .with_attributes(attributes)
  tracer.build_with_context(builder, parent_context)
}

///|
/// End a span, optionally setting a final status.
pub async fn end_span(span : @trace.Span, status? : @trace.Status) -> Unit {
  match status {
    Some(s) => span.set_status(s)
    None => ()
  }
  span.end()
}

///|
/// End a span marking it as successful.
pub async fn end_span_ok(span : @trace.Span) -> Unit {
  end_span(span, status=@trace.Status::ok())
}

///|
/// End a span marking it as failed.
pub async fn end_span_error(span : @trace.Span, description~ : String) -> Unit {
  end_span(span, status=@trace.Status::error(description=Some(description)))
}

///|
/// Set multiple attributes on a span.
pub fn set_attributes(
  span : @trace.Span,
  attributes : Array[@otel.KeyValue],
) -> Unit {
  for attr in attributes {
    span.set_attribute(attr)
  }
}

///|
/// Set a string attribute on a span.
pub fn set_string_attribute(
  span : @trace.Span,
  name : String,
  value : String,
) -> Unit {
  span.set_attribute(@otel.KeyValue::new(name, String(value)))
}

///|
/// Set an integer attribute on a span.
pub fn set_int_attribute(
  span : @trace.Span,
  name : String,
  value : Int64,
) -> Unit {
  span.set_attribute(@otel.KeyValue::new(name, Int64(value)))
}

///|
/// Set a floating-point attribute on a span.
pub fn set_double_attribute(
  span : @trace.Span,
  name : String,
  value : Double,
) -> Unit {
  span.set_attribute(@otel.KeyValue::new(name, Double(value)))
}

///|
/// Set a boolean attribute on a span.
pub fn set_bool_attribute(
  span : @trace.Span,
  name : String,
  value : Bool,
) -> Unit {
  span.set_attribute(@otel.KeyValue::new(name, Bool(value)))
}

///|
/// Set a JSON attribute on a span.
/// The JSON value is serialized to a string, which is useful for structured
/// custom metadata that does not have a dedicated scalar attribute.
pub fn set_json_attribute(
  span : @trace.Span,
  name : String,
  value : Json,
) -> Unit {
  span.set_attribute(@otel.KeyValue::new(name, String(value.stringify())))
}

///| Internal helpers

///|
/// Build a default resource, ensuring service.name is set.
fn build_resource(service_name : String) -> @resource.Resource {
  @resource.Resource::builder()
  .build()
  .merge(
    @resource.Resource::new([
      @common.KeyValue::new("service.name", String(service_name)),
    ]),
  )
}
