"""generate_response in proxy/server.py, driven by a scripted fake model
(see conftest.FakeModel). Covers the response shape Claude Code depends on."""
import pytest

import server


def body(**kw):
    b = {"model": "claude-sonnet-4-6", "max_tokens": 100,
         "messages": [{"role": "user", "content": "hi"}]}
    b.update(kw)
    return b


BASH = {"name": "Bash", "input_schema": {"type": "object", "properties": {
    "command": {"type": "string"}}, "required": ["command"]}}


def test_plain_text_response_shape(fake_model):
    fake_model.outputs = ["Hello there."]
    r = server.generate_response(body())
    assert r["type"] == "message" and r["role"] == "assistant"
    assert r["id"].startswith("msg_")
    assert r["model"] == "claude-sonnet-4-6"
    assert r["content"] == [{"type": "text", "text": "Hello there."}]
    assert r["stop_reason"] == "end_turn"
    assert r["stop_sequence"] is None
    assert r["usage"]["input_tokens"] > 0
    assert r["usage"]["output_tokens"] == 4  # 12 chars in 3-char pieces


def test_empty_output_is_reported_not_blank(fake_model):
    fake_model.outputs = [""]
    r = server.generate_response(body())
    assert r["content"] == [{"type": "text", "text": "(No output)"}]


def test_tool_call_becomes_tool_use_block_with_no_empty_text(fake_model):
    fake_model.outputs = ['<tool_call>{"name": "Bash", "arguments": {"command": "ls"}}</tool_call>']
    r = server.generate_response(body(tools=[BASH]))
    assert r["stop_reason"] == "tool_use"
    assert len(r["content"]) == 1
    block = r["content"][0]
    assert block["type"] == "tool_use" and block["name"] == "Bash"
    assert block["id"].startswith("toolu_")
    assert block["input"] == {"command": "ls"}


WRITE = {"name": "Write", "input_schema": {"type": "object", "properties": {
    "file_path": {"type": "string"}, "content": {"type": "string"}},
    "required": ["file_path", "content"]}}


def test_gemma4_write_with_no_opening_marker_still_writes_the_file(fake_model):
    # Gemma 4 31B 8-bit on a long Write (10/29): the page streams out with only
    # the tail of the call, and before the fix it came back as plain text.
    page = "<!DOCTYPE html>\n<html><body>Rent $1,200</body></html>"
    fake_model.outputs = [page + '\n<|"|>,file_path:<|"|>budget.html<|"|>}<tool_call|>']
    r = server.generate_response(body(tools=[BASH, WRITE]))
    assert r["stop_reason"] == "tool_use"
    assert [b["type"] for b in r["content"]] == ["tool_use"]
    assert r["content"][0]["name"] == "Write"
    assert r["content"][0]["input"]["content"] == page
    assert r["content"][0]["input"]["file_path"].endswith("budget.html")


def test_tool_input_keys_outside_the_schema_are_dropped(fake_model):
    fake_model.outputs = ['<tool_call>{"name": "Bash", "arguments": '
                          '{"command": "ls", "description": "list"}}</tool_call>']
    r = server.generate_response(body(tools=[BASH]))
    assert r["content"][0]["input"] == {"command": "ls"}


def test_code_mode_swaps_system_prompt_before_templating(fake_model):
    fake_model.outputs = ["ok"]
    server.generate_response(body(system="HUGE HARNESS PROMPT", tools=[BASH]))
    messages, kw = server.tokenizer.calls[0]
    assert messages[0] == {"role": "system", "content": server.code_system_prompt({"Bash"})}
    assert kw["tools"][0]["function"]["name"] == "Bash"


def test_append_system_prompt_file(fake_model, monkeypatch, tmp_path):
    extra = tmp_path / "extra.md"
    extra.write_text("Narrate everything.\n")
    monkeypatch.setenv("MLX_APPEND_SYSTEM_PROMPT_FILE", str(extra))
    fake_model.outputs = ["ok"]
    server.generate_response(body(system="base"))
    messages, _ = server.tokenizer.calls[0]
    assert messages[0]["content"] == "base\n\n---\n\nNarrate everything."


def test_append_system_prompt_file_with_block_list_system(fake_model, monkeypatch, tmp_path):
    extra = tmp_path / "extra.md"
    extra.write_text("More rules.")
    monkeypatch.setenv("MLX_APPEND_SYSTEM_PROMPT_FILE", str(extra))
    fake_model.outputs = ["ok"]
    server.generate_response(body(system=[{"type": "text", "text": "base"}]))
    messages, _ = server.tokenizer.calls[0]
    assert messages[0]["content"] == "base\n\n\n---\n\nMore rules."


def test_max_tokens_finish_reason(fake_model, monkeypatch):
    def gen(model, tokenizer, prompt, max_tokens, **kw):
        yield type("R", (), {"text": "abc", "generation_tokens": 1, "finish_reason": "length"})()
    monkeypatch.setattr(server, "stream_generate", gen)
    r = server.generate_response(body())
    assert r["stop_reason"] == "max_tokens"


def test_second_request_reuses_the_cached_prefix(fake_model):
    fake_model.outputs = ["one", "two"]
    first = body()
    server.generate_response(first)
    second = body(messages=first["messages"] + [
        {"role": "assistant", "content": "one"}, {"role": "user", "content": "again"}])
    server.generate_response(second)
    full_first, delta_second = fake_model.prompts
    full_second = server.tokenize_messages(server.convert_messages(second))
    shared = next(i for i, (a, b) in enumerate(zip(full_first, full_second)) if a != b)
    assert shared > 0
    assert delta_second == full_second[shared:]  # only the new tail is prefilled


def test_count_prompt_tokens_matches_generation_prompt(fake_model):
    b = body(tools=[BASH])
    n = server.count_prompt_tokens(b)
    fake_model.outputs = ["ok"]
    # count_prompt_tokens does not apply code mode, so compare with it off.
    server.CODE_MODE_ENABLED, saved = False, server.CODE_MODE_ENABLED
    try:
        r = server.generate_response(b)
    finally:
        server.CODE_MODE_ENABLED = saved
    assert r["usage"]["input_tokens"] == n


# ─── Tool names: case and aliases (phone test 10/30, Qwen 3.5 0.8B) ──────────
READ = {"name": "Read", "input_schema": {"type": "object", "properties": {
    "file_path": {"type": "string"}}, "required": ["file_path"]}}
DECLARED = [BASH, WRITE, READ]


def assembled(name, args, tools=DECLARED):
    r = server.assemble_anthropic_message(
        "", [{"name": name, "arguments": args}], {"tools": tools}, tools, 10, 5)
    return r["content"][0]["name"], r["content"][0]["input"]


@pytest.mark.parametrize("name", ["bash", "BASH", "Bash", "bAsH"])
def test_tool_name_case_is_matched_to_the_declared_tool(name):
    assert assembled(name, {"command": "python3 add.py"}) == ("Bash", {"command": "python3 add.py"})


@pytest.mark.parametrize("name", ["Run", "Execute", "Shell", "Terminal", "RunCommand",
                                  "run_command", "exec", "EXECUTE"])
def test_shell_aliases_go_to_bash(name):
    assert assembled(name, {"command": "python3 add.py"}) == ("Bash", {"command": "python3 add.py"})


@pytest.mark.parametrize("key", ["code", "script", "cmd"])
def test_bash_alias_argument_becomes_command(key):
    assert assembled("Run", {key: "python3 add.py"}) == ("Bash", {"command": "python3 add.py"})


@pytest.mark.parametrize("name", ["CreateFile", "WriteFile", "Save", "write_file"])
def test_write_aliases_go_to_write(name):
    assert assembled(name, {"path": "/w/add.py", "content": "print(5)"}) == (
        "Write", {"file_path": "/w/add.py", "content": "print(5)"})


@pytest.mark.parametrize("name", ["ReadFile", "Open", "Cat", "read_file"])
def test_read_aliases_go_to_read(name):
    assert assembled(name, {"file_path": "/w/add.py"}) == ("Read", {"file_path": "/w/add.py"})


def test_undeclared_tool_is_not_mapped_to_anything():
    assert assembled("Deploy", {"command": "x"}) == ("Deploy", {"command": "x"})


def test_alias_target_must_be_declared():
    assert assembled("Run", {"command": "ls"}, tools=[WRITE, READ])[0] == "Run"


def test_declared_alias_name_keeps_its_own_tool():
    run = {"name": "Run", "input_schema": {"type": "object", "properties": {
        "code": {"type": "string"}}, "required": ["code"]}}
    assert assembled("Run", {"code": "1+1"}, tools=[BASH, run]) == ("Run", {"code": "1+1"})
    assert assembled("run", {"code": "1+1"}, tools=[BASH, run]) == ("Run", {"code": "1+1"})


def test_existing_argument_is_not_overwritten_by_an_alias():
    assert assembled("Run", {"command": "ls", "cmd": "rm -rf /"}) == ("Bash", {"command": "ls"})
