// Copyright (c) 2026 Yingjie Shang
// agent-telemetry is licensed under Mulan PSL v2.

///|
/// Per-process counter to keep seeds unique even if called multiple times.
let seed_counter : Ref[Int] = Ref(0)

///|
/// Build a 32-byte seed from the current timestamp and a process counter.
///
/// The SDK's default RandomIdGenerator uses a fixed ChaCha8 seed, which causes
/// duplicate trace/span IDs across process restarts. Mixing in the current
/// nanosecond timestamp and a per-process counter ensures every process
/// produces unique IDs.
async fn make_seed() -> Bytes {
  let (code, stdout, _stderr) = @process.collect_output("date", ["+%s%N"])
  let timestamp = if code == 0 { stdout.text().trim().to_owned() } else { "0" }
  let counter = seed_counter.val
  seed_counter.val = seed_counter.val + 1
  let text = "seed-" +
    counter.to_string() +
    "-" +
    timestamp +
    "-abcdefghijklmnopqrstuvwx"
  // Take exactly 32 bytes; pad with '0' if shorter.
  let mut padded = ""
  for i = 0; i < 32; i = i + 1 {
    if i < text.length() {
      padded = padded + text[i:i + 1].to_owned()
    } else {
      padded = padded + "0"
    }
  }
  let bytes : Array[Byte] = []
  for ch in padded {
    bytes.push(ch.to_int().to_byte())
  }
  Bytes::from_iter(bytes.iter())
}

///|
/// Create an IdGenerator with a process-unique seed.
///
/// This helper works around the SDK default RandomIdGenerator's fixed ChaCha8
/// seed, which produces duplicate trace/span IDs across process restarts.
pub async fn make_random_id_generator() -> @sdktrace.IdGenerator {
  let seed = make_seed()
  let random = @random.Rand::chacha8(seed~)
  @sdktrace.IdGenerator::new(
    fn() {
      match @common.TraceId::from_hex(random_hex_32(random)) {
        Some(id) => id
        None => @common.TraceId::invalid()
      }
    },
    fn() {
      match @common.SpanId::from_hex(random_hex_16(random)) {
        Some(id) => id
        None => @common.SpanId::invalid()
      }
    },
  )
}

///|
/// Generate a 32-character hex string (16 bytes).
fn random_hex_32(random : @random.Rand) -> String {
  random_hex_16(random) + random_hex_16(random)
}

///|
/// Generate a 16-character hex string (8 bytes).
fn random_hex_16(random : @random.Rand) -> String {
  random.uint64().to_string(radix=16).pad_start(16, '0')
}
