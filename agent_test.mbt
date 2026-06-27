// Copyright (c) 2026 Yingjie Shang
// agent-telemetry is licensed under Mulan PSL v2.

///|
async test "start_agent_turn_span sets input and max turns" {
  let (tracer, exporter) = make_test_tracer()
  let span = start_agent_turn_span(tracer, "What is the weather?", 10)
  end_span_ok(span)
  let spans = exporter.finished_spans()
  assert_eq(spans.length(), 1)
  assert_eq(spans[0].name, "agent.turn")
  match find_attr(spans[0], "agent.turn.input") {
    Some(String("What is the weather?")) => ()
    _ => fail("expected agent.turn.input")
  }
  match find_attr(spans[0], "agent.turn.max_tool_turns") {
    Some(Int64(10)) => ()
    _ => fail("expected max_tool_turns=10")
  }
}

///|
async test "set_turn sets turn attributes" {
  let (tracer, exporter) = make_test_tracer()
  let span = start_agent_turn_span(tracer, "hello", 10)
  set_turn(span, 3, 2, "final reply")
  end_span_ok(span)
  let spans = exporter.finished_spans()
  match find_attr(spans[0], "agent.turn.actual_turns") {
    Some(Int64(3)) => ()
    _ => fail("expected actual_turns=3")
  }
  match find_attr(spans[0], "agent.turn.tool_call_count") {
    Some(Int64(2)) => ()
    _ => fail("expected tool_call_count=2")
  }
  match find_attr(spans[0], "agent.turn.output") {
    Some(String("final reply")) => ()
    _ => fail("expected agent.turn.output")
  }
}

///|
async test "set_turn_max_tool_turns_error marks error" {
  let (tracer, exporter) = make_test_tracer()
  let span = start_agent_turn_span(tracer, "hello", 1)
  set_turn_exhausted(span)
  end_span(span)
  let spans = exporter.finished_spans()
  assert_true(spans[0].status.code == @sdktrace.Error)
}
