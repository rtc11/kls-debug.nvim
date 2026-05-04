#!/usr/bin/env bash
# Fake opencode binary for tests: emits canned JSONL on stdout.
cat <<'JSONL'
{"type":"step_start"}
{"type":"text","part":{"text":"hello "}}
{"type":"text","part":{"text":"world"}}
{"type":"step_finish"}
JSONL
exit 0
