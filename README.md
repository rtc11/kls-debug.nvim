# kls-debug.nvim

Bridge between Kotlin Language Server (KLS) internal state and AI-powered debugging via OhMyOpenCode. 
This plugin gathers deep compiler context (AST, type info, KLS logs) and pipes it to `opencode` for smarter troubleshooting.

## Prerequisites

- Neovim 0.9.0+
- [opencode](https://github.com/OhMyOpenCode) CLI in PATH and authenticated
- KLS running with debug server enabled (check for `.kls-debug-port`)
- [plenary.nvim](https://github.com/nvim-lua/plenary.nvim) (required for tests)

## Install

Using [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
return {
  "your-username/kls-debug.nvim",
  cmd = { "KlsDebugAsk", "KlsDebugChat", "KlsDebugCancel" },
  keys = {
    { "<leader>kd", mode = { "v", "n" }, desc = "kls-debug: ask" },
  },
  opts = {
    -- see Configuration section for defaults
    keymaps = { enabled = true },
  },
  config = function(_, opts)
    require("kls-debug").setup(opts)
  end,
}
```

## Configuration

Default options:

```lua
{
  model = nil, -- LLM model override
  agent = nil, -- opencode agent override
  output = "split", -- "split", "float", or "tab"
  timeout_ms = 60000, -- opencode request timeout
  kls_connect_timeout_ms = 500, -- KLS debug server connection timeout
  buffer_byte_cap = 102400, -- max bytes of buffer content to send
  buffer_around_cursor = 20480, -- bytes around cursor for context
  diagnostic_cap = 50, -- max number of diagnostics to include
  log_tail_lines = 200, -- number of KLS log lines to include
  surrounding_lines = 10, -- lines around selection/diagnostic
  context = {
    diagnostics = true, -- LSP errors/warnings
    buffer = true, -- full source code
    selection = true, -- visual selection
    kls = true, -- KLS internal state (AST, symbols, types)
    cursor_symbol = true, -- symbol under cursor details
    kls_log = true, -- KLS server logs
    git = true, -- git branch/status/diff
    agents_md = true, -- AGENTS.md conventions
  },
  kls_log_path = nil, -- manual path to KLS log file
  keymaps = {
    visual = "<leader>kd",
    normal_diag = "<leader>kd",
    enabled = true,
  },
}
```

## Commands

- `:KlsDebugAsk`: Send context and prompt to opencode. Result goes to `output` destination.
- `:KlsDebugChat`: Open opencode TUI in a terminal split with current context.
- `:KlsDebugCancel`: Kill the active opencode process.

## Keymaps

If `keymaps.enabled = true`:
- `<leader>kd` (Visual): Trigger `KlsDebugAsk` on selection.
- `<leader>kd` (Normal): Trigger `KlsDebugAsk` on diagnostic under cursor.

## Context Sources

| Source | What it provides | Toggle key |
|--------|------------------|------------|
| Buffer file content | full source code with cap | `context.buffer` |
| Visual selection | selected lines + surrounding | `context.selection` |
| Diagnostics | LSP errors/warnings/info/hints | `context.diagnostics` |
| Cursor symbol | symbol under cursor + surrounding | `context.cursor_symbol` |
| KLS debug index | KLS internal state, AST, type info, hover | `context.kls` |
| Git context | branch, last commit, status, diff for file | `context.git` |
| AGENTS.md | repo conventions/instructions excerpt | `context.agents_md` |
| KLS log tail | recent KLS server log lines | `context.kls_log` |

## Health

Run `:checkhealth kls-debug` to verify your environment, opencode authentication, and KLS connectivity.

## Troubleshooting

- **`.kls-debug-port` missing**: Ensure KLS is running with debug server enabled. The plugin looks for this file in the project root.
- **opencode hangs**: Check network connection or run `:KlsDebugCancel`. Verify auth state.
- **opencode not authenticated**: Run `opencode auth` in your terminal to login.
- **No KLS context**: Verify KLS is the active LSP client and debug server is responding.

## Development

Run tests:

```bash
nvim --headless --clean -u NONE \
  --cmd "set rtp+=/path/to/plenary.nvim" \
  --cmd "set rtp+=$PWD" \
  --cmd "runtime plugin/plenary.vim" \
  -c "PlenaryBustedDirectory tests/" -c "qa!"
```

Regenerate fixtures via `tests/fixtures/`.

---
Thanks to wtf.nvim for the idea.
