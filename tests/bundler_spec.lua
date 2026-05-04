local bundler = require("kls-debug.context.bundler")

local function make_bundle()
	return {
		buffer = {
			kind = "buffer",
			ok = true,
			data = {
				filename = "Main.kt",
				filetype = "kotlin",
				content = 'package sample\n\nfun greet(name: String): String {\n\treturn "hi " + name\n}\n',
				truncated = false,
				byte_count = 73,
			},
		},
		selection = {
			kind = "selection",
			ok = true,
			data = {
				start_line = 2,
				start_col = 0,
				end_line = 4,
				end_col = 1,
				content = 'fun greet(name: String): String {\n\treturn "hi " + name\n}',
				surrounding_before = "package sample",
				surrounding_after = "",
			},
		},
		diagnostics = {
			kind = "diagnostics",
			ok = true,
			data = {
				{
					line = 5,
					col = 12,
					severity = vim.diagnostic.severity.ERROR,
					message = "Type mismatch: inferred type is Int but String was expected",
					source = "kls",
				},
			},
		},
		cursor = {
			kind = "cursor",
			ok = true,
			data = {
				line = 12,
				col = 4,
				symbol = "greet",
				line_text = "fun greet(name: String): String {",
				surrounding_before = "package sample",
				surrounding_after = '\treturn "hi " + name',
			},
		},
		kls = {
			summary = { file_count = 2, symbol_count = 5 },
			ast_chain = {
				{ kind = "FILE", name = "Main.kt", start = 1, ["end"] = 40 },
				{ kind = "FUN_DECL", name = "greet", start = 3, ["end"] = 5 },
			},
			type_info = {
				type = "String",
				nullable = false,
				inferred_from = 'val greeting = greet("Ada")',
			},
			hover = {
				contents = {
					kind = "markdown",
					value = "```kotlin\nfun greet(name: String): String\n```",
				},
			},
			errors = {},
		},
		git = {
			kind = "git",
			ok = true,
			data = {
				branch = "main",
				commit = "abc1234 feat: base",
				status = "M lua/kls-debug/context/bundler.lua",
				diff = "diff --git a/lua/kls-debug/context/bundler.lua b/lua/kls-debug/context/bundler.lua\n+new file",
			},
		},
		agents = {
			kind = "agents",
			ok = true,
			data = "# AGENTS\n- keep it small\n- test it",
		},
		log = {
			kind = "log",
			ok = true,
			data = "line 1\nline 2\nline 3",
		},
	}
end

describe("kls-debug.context.bundler", function()
	it("formats full bundle with all sections", function()
		local out = bundler.format(make_bundle(), "How do I debug?", { log_tail_lines = 200 })

		assert.is_string(out)
		assert.is_truthy(out:find("# KLS Debug Request", 1, true))
		assert.is_truthy(out:find("How do I debug?", 1, true))
		assert.is_truthy(out:find("## File: Main.kt (kotlin)", 1, true))
		assert.is_truthy(out:find("## Visual Selection (lines 2-4)", 1, true))
		assert.is_truthy(out:find("## Diagnostics (1 total)", 1, true))
		assert.is_truthy(out:find("## Cursor: line 12 col 4, symbol `greet`", 1, true))
		assert.is_truthy(out:find("## KLS AST chain", 1, true))
		assert.is_truthy(out:find("## KLS Type at cursor", 1, true))
		assert.is_truthy(out:find("## KLS Hover", 1, true))
		assert.is_truthy(out:find("## KLS Workspace Summary", 1, true))
		assert.is_truthy(out:find("## Recent KLS log (last 200 lines)", 1, true))
		assert.is_truthy(out:find("## Git", 1, true))
		assert.is_truthy(out:find("## AGENTS.md (excerpt)", 1, true))
	end)

	it("skips git section when toggled off", function()
		local out = bundler.format(make_bundle(), "Q", { context = { git = false } })
		assert.is_nil(out:find("## Git", 1, true))
		assert.is_truthy(out:find("## File: Main.kt (kotlin)", 1, true))
	end)

	it("drops log first at size cap", function()
		local bundle = make_bundle()
		bundle.log.data = string.rep("x\n", 150000)

		local out = bundler.format(bundle, "Q", { log_tail_lines = 300 })

		assert.is_true(#out < 200 * 1024)
		assert.is_nil(out:find("## Recent KLS log", 1, true))
		assert.is_truthy(out:find("[log dropped: size cap]", 1, true))
	end)

	it("skips failed and empty sources silently", function()
		local bundle = {
			buffer = { kind = "buffer", ok = false, error = "invalid buffer" },
			selection = { kind = "selection", ok = false, error = "missing" },
			diagnostics = { kind = "diagnostics", ok = true, data = {} },
			cursor = { kind = "cursor", ok = false, error = "missing" },
			kls = nil,
			git = { kind = "git", ok = false, reason = "not found" },
			agents = { kind = "agents", ok = false, reason = "not found" },
			log = { kind = "log", ok = false, reason = "not found" },
		}

		local out = bundler.format(bundle, "Q", {})
		assert.is_truthy(out:find("# KLS Debug Request", 1, true))
		assert.is_nil(out:find("## File:", 1, true))
		assert.is_nil(out:find("## Visual Selection", 1, true))
		assert.is_nil(out:find("## Diagnostics", 1, true))
		assert.is_nil(out:find("## Cursor:", 1, true))
		assert.is_nil(out:find("## KLS ", 1, true))
		assert.is_nil(out:find("## Git", 1, true))
		assert.is_nil(out:find("## AGENTS.md", 1, true))
	end)

	it("skips all KLS sections on soft degrade", function()
		local bundle = make_bundle()
		bundle.kls = nil

		local out = bundler.format(bundle, "Q", {})
		assert.is_nil(out:find("## KLS AST chain", 1, true))
		assert.is_nil(out:find("## KLS Type at cursor", 1, true))
		assert.is_nil(out:find("## KLS Hover", 1, true))
		assert.is_nil(out:find("## KLS Workspace Summary", 1, true))
	end)

	it("drops buffer when still over cap", function()
		local bundle = make_bundle()
		bundle.buffer.data.content = string.rep("x", 250 * 1024)
		bundle.buffer.data.byte_count = #bundle.buffer.data.content

		local out = bundler.format(bundle, "Q", {})
		assert.is_true(#out <= 200 * 1024)
		assert.is_truthy(out:find("## File: Main.kt (kotlin)", 1, true))
		assert.is_truthy(out:find("[buffer truncated: size cap]", 1, true))
	end)
end)
