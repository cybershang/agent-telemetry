// Copyright (c) 2026 Yingjie Shang
// agent-telemetry is licensed under Mulan PSL v2.

///|
async test "start_tool_span sets tool attributes" {
  let (tracer, exporter) = make_test_tracer()
  let span = start_tool_span(tracer, "get_weather", "{\"city\":\"Beijing\"}")
  end_span_ok(span)
  let spans = exporter.finished_spans()
  assert_eq(spans.length(), 1)
  assert_eq(spans[0].name, "gen_ai.tool.execution")
  match find_attr(spans[0], "gen_ai.tool.name") {
    Some(String("get_weather")) => ()
    _ => fail("expected tool name")
  }
  match find_attr(spans[0], "gen_ai.tool.call.arguments") {
    Some(String(args)) => assert_true(args.contains("Beijing"))
    _ => fail("expected tool arguments")
  }
}

///|
async test "set_tool_result marks ok for success" {
  let (tracer, exporter) = make_test_tracer()
  let span = start_tool_span(tracer, "get_weather", "{}")
  set_tool_result(span, "{\"temperature\": 25}")
  end_span(span)
  let spans = exporter.finished_spans()
  assert_true(spans[0].status.code == @sdktrace.Ok)
  match find_attr(spans[0], "gen_ai.tool.call.result") {
    Some(String(s)) => assert_true(s.contains("temperature"))
    _ => fail("expected tool result attribute")
  }
}

///|
async test "set_tool_result marks error for error result" {
  let (tracer, exporter) = make_test_tracer()
  let span = start_tool_span(tracer, "get_weather", "{}")
  set_tool_result(span, "{\"error\": \"failed\"}")
  end_span(span)
  let spans = exporter.finished_spans()
  assert_true(spans[0].status.code == @sdktrace.Error)
}
