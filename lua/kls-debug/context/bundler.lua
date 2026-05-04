local M = {}

local PROMPT_CAP_BYTES = 200 * 1024

local severity_names = {
	[1] = "ERROR",
	[2] = "WARN",
	[3] = "INFO",
	[4] = "HINT",
}

local function is_enabled(opts, key)
	if type(opts) ~= "table" or type(opts.context) ~= "table" then
		return true
	end

	return opts.context[key] ~= false
end

local function is_empty(value)
	if value == nil then
		return true
	end
	if type(value) == "string" then
		return value == ""
	end
	if type(value) == "table" then
		return next(value) == nil
	end
	return false
end

local function escape_pipe(text)
	if type(text) ~= "string" then
		return ""
	end

	return (text:gsub("|", "\\|"))
end

local function join_sections(sections)
	local out = {}
	for _, section in ipairs(sections) do
		if type(section) == "string" and section ~= "" then
			table.insert(out, section)
		end
	end
	return table.concat(out, "\n\n")
end

local function fence(lang, body)
	lang = type(lang) == "string" and lang or ""
	body = type(body) == "string" and body or ""
	return table.concat({ "```" .. lang, body, "```" }, "\n")
end

local function render_buffer_section(data, truncated)
	if type(data) ~= "table" or is_empty(data.content) then
		return nil
	end

	local filename = data.filename
	if type(filename) ~= "string" or filename == "" then
		filename = "<unknown>"
	end

	local filetype = data.filetype
	if type(filetype) ~= "string" or filetype == "" then
		filetype = "plain"
	end

	local parts = {
		"## File: " .. filename .. " (" .. filetype .. ")",
		fence(filetype, data.content),
	}
	if truncated then
		table.insert(parts, "[buffer truncated: size cap]")
	end
	return table.concat(parts, "\n\n")
end

local function render_selection_section(data)
	if type(data) ~= "table" or is_empty(data.content) then
		return nil
	end

	local start_line = data.start_line or 0
	local end_line = data.end_line or start_line
	local parts = {
		string.format("## Visual Selection (lines %s-%s)", start_line, end_line),
		fence("text", data.content),
	}
	if not is_empty(data.surrounding_before) then
		table.insert(parts, "Before:\n" .. fence("text", data.surrounding_before))
	end
	if not is_empty(data.surrounding_after) then
		table.insert(parts, "After:\n" .. fence("text", data.surrounding_after))
	end
	return table.concat(parts, "\n\n")
end

local function render_diagnostics_section(items)
	if type(items) ~= "table" or #items == 0 then
		return nil
	end

	local lines = { string.format("## Diagnostics (%d total)", #items) }
	table.insert(lines, "| Line | Sev | Source | Message |")
	table.insert(lines, "| --- | --- | --- | --- |")
	for _, item in ipairs(items) do
		local line = item.line or 0
		local sev = severity_names[item.severity] or "UNKNOWN"
		local source = item.source or ""
		local message = escape_pipe(item.message or "")
		table.insert(lines, string.format("| %s | %s | %s | %s |", line, sev, source, message))
	end
	return table.concat(lines, "\n")
end

local function render_cursor_section(data)
	if type(data) ~= "table" or is_empty(data.line) or is_empty(data.col) then
		return nil
	end

	local symbol = data.symbol
	if type(symbol) ~= "string" then
		symbol = ""
	end

	local parts = {
		string.format("## Cursor: line %s col %s, symbol `%s`", data.line, data.col, symbol),
	}
	if not is_empty(data.line_text) then
		table.insert(parts, fence("text", data.line_text))
	end
	if not is_empty(data.surrounding_before) then
		table.insert(parts, "Before:\n" .. fence("text", data.surrounding_before))
	end
	if not is_empty(data.surrounding_after) then
		table.insert(parts, "After:\n" .. fence("text", data.surrounding_after))
	end
	return table.concat(parts, "\n\n")
end

local function span_text(node)
	if type(node) ~= "table" then
		return ""
	end

	local start = node.start or node.start_line or node.range_start or node.from
	local finish = node["end"] or node.end_line or node.range_end or node.to
	if start == nil and type(node.range) == "table" then
		local range_start = node.range.start
		local range_end = node.range["end"]
		if type(range_start) == "table" and type(range_end) == "table" then
			start = string.format("%s:%s", range_start.line or 0, range_start.character or 0)
			finish = string.format("%s:%s", range_end.line or 0, range_end.character or 0)
		end
	end

	if start == nil and finish == nil then
		return ""
	end

	return string.format("[%s..%s]", tostring(start or "?"), tostring(finish or "?"))
end

local function render_ast_chain_section(items)
	if type(items) ~= "table" or #items == 0 then
		return nil
	end

	local lines = { "## KLS AST chain" }
	for _, node in ipairs(items) do
		if type(node) == "table" then
			local kind = tostring(node.kind or "")
			local name = tostring(node.name or "")
			local span = span_text(node)
			local piece = "- " .. kind
			if name ~= "" then
				piece = piece .. " " .. name
			end
			if span ~= "" then
				piece = piece .. " " .. span
			end
			table.insert(lines, piece)
		end
	end
	if #lines == 1 then
		return nil
	end
	return table.concat(lines, "\n")
end

local function render_type_info_section(data)
	if type(data) ~= "table" or is_empty(data) then
		return nil
	end

	local lines = { "## KLS Type at cursor" }
	for _, key in ipairs({ "type", "nullable", "inferred_from" }) do
		if data[key] ~= nil and data[key] ~= "" then
			table.insert(lines, string.format("- %s: %s", key, tostring(data[key])))
		end
	end
	if #lines == 1 then
		return nil
	end
	return table.concat(lines, "\n")
end

local function render_hover_section(data)
	if data == nil or is_empty(data) then
		return nil
	end

	local value = data
	if type(data) == "table" then
		if type(data.contents) == "table" and type(data.contents.value) == "string" then
			value = data.contents.value
		elseif type(data.value) == "string" then
			value = data.value
		else
			value = vim.inspect(data)
		end
	end

	return table.concat({ "## KLS Hover", fence("markdown", value) }, "\n\n")
end

local function render_summary_section(data)
	if type(data) ~= "table" or is_empty(data) then
		return nil
	end

	local file_count = tonumber(data.file_count) or 0
	local symbol_count = tonumber(data.symbol_count) or 0
	return string.format("## KLS Workspace Summary\n%d files, %d symbols", file_count, symbol_count)
end

local function count_lines(text)
	if type(text) ~= "string" or text == "" then
		return 0
	end

	local count = 1
	for _ in text:gmatch("\n") do
		count = count + 1
	end
	return count
end

local function render_log_section(data, opts, dropped)
	if dropped then
		return "[log dropped: size cap]"
	end

	if type(data) ~= "string" or data == "" then
		return nil
	end

	local line_count = tonumber(type(opts) == "table" and opts.log_tail_lines or nil)
		or count_lines(data)
	local parts = {
		string.format("## Recent KLS log (last %d lines)", line_count),
		fence("text", data),
	}
	return table.concat(parts, "\n\n")
end

local function render_git_section(data, drop_diff)
	if type(data) ~= "table" or is_empty(data) then
		return nil
	end

	local lines = { "## Git" }
	if data.branch ~= nil and data.branch ~= "" then
		table.insert(lines, "- Branch: " .. tostring(data.branch))
	end
	if data.commit ~= nil and data.commit ~= "" then
		table.insert(lines, "- Commit: " .. tostring(data.commit))
	end
	if data.status ~= nil and data.status ~= "" then
		table.insert(lines, "- Status:\n" .. fence("text", tostring(data.status)))
	end
	if not drop_diff and data.diff ~= nil and data.diff ~= "" then
		table.insert(lines, "- Diff:\n" .. fence("diff", tostring(data.diff)))
	elseif drop_diff and data.diff ~= nil and data.diff ~= "" then
		table.insert(lines, "[git diff dropped: size cap]")
	end
	return table.concat(lines, "\n")
end

local function render_agents_section(data, dropped)
	if dropped then
		return "[agents dropped: size cap]"
	end

	if type(data) ~= "string" or data == "" then
		return nil
	end

	local parts = {
		"## AGENTS.md (excerpt)",
		fence("markdown", data),
	}
	return table.concat(parts, "\n\n")
end

local function render_bundle(bundle, user_question, state, opts)
	local sections = { "# KLS Debug Request", user_question or "" }

	local buffer = bundle.buffer
	if is_enabled(opts, "buffer") and type(buffer) == "table" and buffer.ok and buffer.data then
		local buffer_text = state.buffer_content or buffer.data.content
		table.insert(
			sections,
			render_buffer_section({
				filename = buffer.data.filename,
				filetype = buffer.data.filetype,
				content = buffer_text,
			}, state.buffer_truncated)
		)
	end

	local selection = bundle.selection
	if
		is_enabled(opts, "selection")
		and type(selection) == "table"
		and selection.ok
		and selection.data
	then
		table.insert(sections, render_selection_section(selection.data))
	end

	local diagnostics = bundle.diagnostics
	if
		is_enabled(opts, "diagnostics")
		and type(diagnostics) == "table"
		and diagnostics.ok
		and diagnostics.data
	then
		table.insert(sections, render_diagnostics_section(diagnostics.data))
	end

	local cursor = bundle.cursor
	if
		is_enabled(opts, "cursor_symbol")
		and type(cursor) == "table"
		and cursor.ok
		and cursor.data
	then
		table.insert(sections, render_cursor_section(cursor.data))
	end

	local kls = bundle.kls
	if is_enabled(opts, "kls") and type(kls) == "table" then
		table.insert(sections, render_summary_section(kls.summary))
		table.insert(sections, render_ast_chain_section(kls.ast_chain))
		table.insert(sections, render_type_info_section(kls.type_info))
		table.insert(sections, render_hover_section(kls.hover))
	end

	local log = bundle.log
	if is_enabled(opts, "kls_log") and type(log) == "table" and log.ok and log.data then
		table.insert(sections, render_log_section(log.data, opts, state.log_dropped))
	elseif state.log_dropped then
		table.insert(sections, "[log dropped: size cap]")
	end

	local git = bundle.git
	if is_enabled(opts, "git") and type(git) == "table" and git.ok and git.data then
		table.insert(sections, render_git_section(git.data, state.git_diff_dropped))
	elseif state.git_diff_dropped then
		table.insert(sections, "[git diff dropped: size cap]")
	end

	local agents = bundle.agents
	if is_enabled(opts, "agents_md") and type(agents) == "table" and agents.ok and agents.data then
		table.insert(sections, render_agents_section(agents.data, state.agents_dropped))
	end

	return join_sections(sections)
end

local function truncate_buffer_to_fit(bundle, user_question, opts, state, cap)
	local buffer = bundle.buffer
	if
		type(buffer) ~= "table"
		or not buffer.ok
		or not buffer.data
		or is_empty(buffer.data.content)
	then
		return state
	end

	local low, high = 0, #(buffer.data.content or "")
	local best = nil
	while low <= high do
		local mid = math.floor((low + high) / 2)
		local candidate = {
			log_dropped = state.log_dropped,
			agents_dropped = state.agents_dropped,
			git_diff_dropped = state.git_diff_dropped,
			buffer_truncated = mid < #(buffer.data.content or ""),
			buffer_content = (buffer.data.content or ""):sub(1, mid),
		}
		local text = render_bundle(bundle, user_question, candidate, opts)
		if #text <= cap then
			best = candidate
			low = mid + 1
		else
			high = mid - 1
		end
	end

	return best or state
end

function M.format(bundle, user_question, opts)
	opts = opts or {}
	bundle = type(bundle) == "table" and bundle or {}

	local state = {
		log_dropped = false,
		agents_dropped = false,
		git_diff_dropped = false,
		buffer_truncated = false,
		buffer_content = nil,
	}

	local text = render_bundle(bundle, user_question, state, opts)
	if #text <= PROMPT_CAP_BYTES then
		return text
	end

	state.log_dropped = true
	text = render_bundle(bundle, user_question, state, opts)
	if #text <= PROMPT_CAP_BYTES then
		return text
	end

	state.agents_dropped = true
	text = render_bundle(bundle, user_question, state, opts)
	if #text <= PROMPT_CAP_BYTES then
		return text
	end

	state.git_diff_dropped = true
	text = render_bundle(bundle, user_question, state, opts)
	if #text <= PROMPT_CAP_BYTES then
		return text
	end

	state = truncate_buffer_to_fit(bundle, user_question, opts, state, PROMPT_CAP_BYTES)
	text = render_bundle(bundle, user_question, state, opts)
	if #text > PROMPT_CAP_BYTES then
		return text:sub(1, PROMPT_CAP_BYTES)
	end

	return text
end

return M
