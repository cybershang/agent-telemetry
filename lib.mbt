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

///| OpenTelemetry provider initialization

///|
/// Initialize the global OpenTelemetry tracer provider.
///
/// Creates an exporter based on `exporter_type`, attaches it to a batch span
/// processor, and installs the provider as the global tracer provider.
pub async fn init_telemetry(
  config : TelemetryConfig,
  exporter_type : ExporterType,
  id_generator? : IdGeneratorOption = SdkDefault,
) -> @sdktrace.SdkTracerProvider {
  do_init_telemetry(config, exporter_type, id_generator~)
}

///|
/// Initialize the global tracer provider from standard environment variables.
///
/// Reads:
/// - `OTEL_SERVICE_NAME` (overrides `service_name`)
/// - `OTEL_STDOUT` (`true` selects the stdout exporter)
/// - `OTEL_EXPORTER_OTLP_ENDPOINT` (when `OTEL_STDOUT` is not `true`)
pub async fn init_from_env(
  service_name? : String = "agent-telemetry",
  id_generator? : IdGeneratorOption = SdkDefault,
) -> @sdktrace.SdkTracerProvider {
  let service_name = @env.get_env_var("OTEL_SERVICE_NAME").unwrap_or(
    service_name,
  )
  let config = TelemetryConfig::new(service_name~)
  let otel_stdout = @env.get_env_var("OTEL_STDOUT").unwrap_or("").to_lower() ==
    "true"
  let otel_endpoint = @env.get_env_var("OTEL_EXPORTER_OTLP_ENDPOINT").unwrap_or(
    "http://localhost:4318",
  )
  let exporter_type = if otel_stdout { Stdout } else { Otlp(otel_endpoint) }
  do_init_telemetry(config, exporter_type, id_generator~)
}

///| Internal helpers

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
) -> @sdktrace.SdkTracerProvider {
  let id_generator = resolve_id_generator(id_generator)
  let exporter = match build_exporter(exporter_type) {
    Some(exporter) => exporter
    None =>
      abort(
        "Telemetry exporter could not be built; check OTEL_EXPORTER_OTLP_ENDPOINT and OTEL_STDOUT.",
      )
  }
  let resource = build_resource(config.service_name)
  let batch_config = @sdktrace.BatchConfig::new(
    max_queue_size=64,
    max_export_batch_size=16,
    scheduled_delay_millis=1000,
    export_timeout_millis=5000,
  )
  let provider = @sdk.tracer_provider_builder()
    .with_resource(resource)
    .with_id_generator(id_generator)
    .with_batch_exporter(exporter, config=batch_config)
    .build()
  @sdk.set_tracer_provider(provider)
  provider
}

///| Internal helpers

///|
/// Append the OTLP/HTTP traces signal path if the endpoint is a base URL.
///
/// The `OTEL_EXPORTER_OTLP_ENDPOINT` environment variable is defined as a
/// base URL; the SDK expects the signal path (`/v1/traces`) to be added.
/// If the endpoint already ends with `/v1/traces`, it is returned unchanged.
fn normalize_trace_endpoint(endpoint : String) -> String {
  let trimmed = endpoint.trim_end(chars="/").to_owned()
  if trimmed.has_suffix("/v1/traces") {
    trimmed
  } else {
    trimmed + "/v1/traces"
  }
}

///|
/// Build a span exporter from the requested exporter type.
async fn build_exporter(
  exporter_type : ExporterType,
) -> @sdktrace.SpanExporter? {
  match exporter_type {
    Stdout => Some(@print.SpanExporter::new().into_span_exporter())
    Otlp(endpoint) =>
      match
        @otlp.SpanExporter::builder()
        .with_http()
        .with_endpoint(normalize_trace_endpoint(endpoint))
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
            "Failed to build OTLP exporter: " + err_text + "\n",
          )
          None
        }
      }
    Custom(exporter) => Some(exporter)
    NoOp => None
  }
}

///| Tracer cache

///|
/// Cache of tracers keyed by scope name.
let tracer_cache : Ref[Map[String, @trace.Tracer]] = Ref({})

///|
/// Get or create a tracer for the given scope name.
///
/// Tracers are cached so repeated calls return the same instance.
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

///| Internal helpers

///|
/// Build a default resource, ensuring service.name is set.
fn build_resource(service_name : String) -> @resource.Resource {
  let base = @resource.Resource::builder().build()
  match @env.get_env_var("OTEL_SERVICE_NAME") {
    Some(_) => base
    None =>
      base.merge(
        @resource.Resource::new([
          @common.KeyValue::new("service.name", String(service_name)),
        ]),
      )
  }
}
