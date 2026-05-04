# Fixtures

## KLS JSON-RPC responses

Files in `tests/fixtures/kls/` are complete JSON-RPC responses for debug ops.

- `listOpenDocuments.json` — capture from `kotlin.listOpenDocuments`
- `lastEditedUri.json` — capture from `kotlin.lastEditedUri`
- `lastCursor.json` — capture from `kotlin.lastCursor`
- `diagnosticsForUri.json` — capture from `kotlin.diagnosticsForUri`
- `hoverAt.json` — capture from `kotlin.hoverAt`
- `definitionAt.json` — capture from `kotlin.definitionAt`
- `referencesAt.json` — capture from `kotlin.referencesAt`
- `astAt.json` — capture from `kotlin.astAt`
- `typeAt.json` — capture from `kotlin.typeAt`
- `queryIndex.json` — capture from `kotlin.queryIndex`

Regenerate by starting KLS on a workspace with debug server enabled, then calling `.opencode/tools/kls-query.ts` for each op and saving full `{jsonrpc,id,result/error}` output.

## opencode JSONL

Files in `tests/fixtures/opencode/` are line-delimited JSON event streams.

- `simple_response.jsonl` — captured from `opencode run --format json "say hi in 3 words"`
- `multi_text.jsonl` — multiple text parts for concatenation tests
- `error.jsonl` — error event shape
- `with_thinking.jsonl` — includes thinking events that parser should skip

Regenerate the simple response with:

```bash
echo "say hi in 3 words" | opencode run --format json 2>/dev/null
```

Then sanitize session IDs and any workspace-specific paths before saving.

## Sample Kotlin

`sample_kotlin/Main.kt` is a tiny end-to-end input with:

- one package declaration
- one unused import
- one obvious type error: `val x: String = 42`

Use it for fixture-based diagnostics and parsing tests.
