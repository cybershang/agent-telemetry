// Copyright (c) 2026 Yingjie Shang
// agent-telemetry is licensed under Mulan PSL v2.

///|
async test "start_chat_span sets GenAI request attributes" {
  let (tracer, exporter) = make_test_tracer()
  let span = start_chat_span(tracer, "stepfun", "step-3.7-flash", 1024)
  end_span_ok(span)
  let spans = exporter.finished_spans()
  assert_eq(spans.length(), 1)
  assert_eq(spans[0].name, "gen_ai.chat")
  assert_true(spans[0].kind == @sdktrace.Client)
  match find_attr(spans[0], "gen_ai.operation.name") {
    Some(String("chat")) => ()
    _ => fail("expected gen_ai.operation.name=chat")
  }
  match find_attr(spans[0], "gen_ai.provider.name") {
    Some(String("stepfun")) => ()
    _ => fail("expected gen_ai.provider.name=stepfun")
  }
  match find_attr(spans[0], "gen_ai.request.model") {
    Some(String("step-3.7-flash")) => ()
    _ => fail("expected gen_ai.request.model")
  }
  match find_attr(spans[0], "gen_ai.request.max_tokens") {
    Some(Int64(1024)) => ()
    _ => fail("expected gen_ai.request.max_tokens=1024")
  }
}

///|
async test "start_chat_span records input messages" {
  let (tracer, exporter) = make_test_tracer()
  let input_messages = [{ "role": "user", "content": "hello" }].to_json()
  let span = start_chat_span(
    tracer,
    "stepfun",
    "step-3.7-flash",
    1024,
    input_messages=Some(input_messages),
  )
  end_span_ok(span)
  let spans = exporter.finished_spans()
  match find_attr(spans[0], "gen_ai.input.messages") {
    Some(String(s)) => assert_true(s.contains("hello"))
    _ => fail("expected gen_ai.input.messages")
  }
}

///|
async test "record_chat_usage sets token attributes" {
  let (tracer, exporter) = make_test_tracer()
  let span = start_chat_span(tracer, "stepfun", "step-3.7-flash", 1024)
  let usage = { "prompt_tokens": 10, "completion_tokens": 20 }.to_json()
  record_chat_usage(span, usage)
  end_span_ok(span)
  let spans = exporter.finished_spans()
  match find_attr(spans[0], "gen_ai.usage.input_tokens") {
    Some(Int64(10)) => ()
    _ => fail("expected input_tokens=10")
  }
  match find_attr(spans[0], "gen_ai.usage.output_tokens") {
    Some(Int64(20)) => ()
    _ => fail("expected output_tokens=20")
  }
}

///|
async test "record_chat_response sets response metadata" {
  let (tracer, exporter) = make_test_tracer()
  let span = start_chat_span(tracer, "stepfun", "step-3.7-flash", 1024)
  let response = Json::object({
    "id": "resp-1".to_json(),
    "model": "step-3.7-flash".to_json(),
    "choices": [
      Json::object({
        "message": Json::object({
          "role": "assistant".to_json(),
          "content": "hi".to_json(),
        }),
        "finish_reason": "stop".to_json(),
      }),
    ].to_json(),
  })
  record_chat_response(span, response)
  end_span_ok(span)
  let spans = exporter.finished_spans()
  match find_attr(spans[0], "gen_ai.response.id") {
    Some(String("resp-1")) => ()
    _ => fail("expected response id")
  }
  match find_attr(spans[0], "gen_ai.response.model") {
    Some(String("step-3.7-flash")) => ()
    _ => fail("expected response model")
  }
  match find_attr(spans[0], "gen_ai.response.finish_reasons") {
    Some(String("stop")) => ()
    _ => fail("expected finish_reason=stop")
  }
}

///|
async test "set_chat_http_error records error event and status" {
  let (tracer, exporter) = make_test_tracer()
  let span = start_chat_span(tracer, "stepfun", "step-3.7-flash", 1024)
  set_chat_http_error(span, 401)
  end_span(span)
  let spans = exporter.finished_spans()
  assert_true(spans[0].status.code == @sdktrace.Error)
  assert_eq(spans[0].events.length(), 1)
  assert_eq(spans[0].events[0].name, "llm.http_error")
  match find_attr(spans[0], "error.type") {
    Some(String("401")) => ()
    _ => fail("expected error.type=401")
  }
}
