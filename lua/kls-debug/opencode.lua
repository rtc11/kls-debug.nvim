local M = {}

local DEFAULT_TIMEOUT_MS = 60000

local ENV_ALLOW_EXACT = {
	PATH = true,
	HOME = true,
}

local ENV_ALLOW_PREFIX = {
	"XDG_",
	"OPENCODE_",
}

local function build_env()
	local env = {}
	local source = vim.fn.environ()
	for key, val in pairs(source) do
		if ENV_ALLOW_EXACT[key] then
			env[key] = val
		else
			for _, prefix in ipairs(ENV_ALLOW_PREFIX) do
				if key:sub(1, #prefix) == prefix then
					env[key] = val
					break
				end
			end
		end
	end
	return env
end

local function make_jsonl_decoder()
	local buf = ""
	return function(chunks, on_event)
		if not chunks then
			return
		end
		-- jobstart on_stdout: list of strings split on \n by neovim;
		-- entries between indices are completed lines, last entry is partial.
		for i, piece in ipairs(chunks) do
			buf = buf .. piece
			if i < #chunks then
				local line = buf
				buf = ""
				if line ~= "" then
					local ok, decoded = pcall(vim.json.decode, line)
					if ok and type(decoded) == "table" then
						on_event(decoded, line)
					end
				end
			end
		end
	end
end

function M.is_in_path()
	return vim.fn.executable("opencode") == 1
end

--- Run opencode headlessly, accumulate text, invoke callback on exit.
--- @param prompt string  the prompt to send on stdin
--- @param opts table     { cmd?: string, model?: string, agent?: string, cwd?: string, timeout_ms?: number, extra_args?: string[] }
--- @param on_done fun(exit_code: integer, full_text: string, raw_jsonl: string)
--- @return integer jid   job id (>0 on success, <=0 on failure)
function M.run_headless(prompt, opts, on_done)
	opts = opts or {}
	prompt = prompt or ""
	local cmd_bin = opts.cmd or "opencode"
	local timeout_ms = tonumber(opts.timeout_ms) or DEFAULT_TIMEOUT_MS

	local args = { cmd_bin, "run", "--format", "json" }
	if opts.model and opts.model ~= "" then
		table.insert(args, "--model")
		table.insert(args, opts.model)
	end
	if opts.agent and opts.agent ~= "" then
		table.insert(args, "--agent")
		table.insert(args, opts.agent)
	end
	if type(opts.extra_args) == "table" then
		for _, a in ipairs(opts.extra_args) do
			table.insert(args, a)
		end
	end

	local accumulated = {}
	local raw_lines = {}
	local decode = make_jsonl_decoder()

	local function on_stdout(_, data, _)
		decode(data, function(event, line)
			table.insert(raw_lines, line)
			local et = event.type
			if
				et == "text"
				and type(event.part) == "table"
				and type(event.part.text) == "string"
			then
				table.insert(accumulated, event.part.text)
			end
		end)
	end

	local timed_out = { value = false }
	local done_called = { value = false }

	local function on_exit(_, code, _)
		if done_called.value then
			return
		end
		done_called.value = true
		local final_code = code
		if timed_out.value and final_code == 0 then
			final_code = 124
		end
		local full = table.concat(accumulated, "")
		local raw = table.concat(raw_lines, "\n")
		if on_done then
			pcall(on_done, final_code, full, raw)
		end
	end

	local jobopts = {
		cwd = opts.cwd,
		clear_env = true,
		env = build_env(),
		stdout_buffered = false,
		stderr_buffered = false,
		on_stdout = on_stdout,
		on_exit = on_exit,
	}

	local ok_start, jid = pcall(vim.fn.jobstart, args, jobopts)
	if not ok_start or type(jid) ~= "number" or jid <= 0 then
		return -1
	end

	-- Send prompt on stdin, then close to signal EOF.
	if prompt and prompt ~= "" then
		pcall(vim.fn.chansend, jid, prompt)
	end
	pcall(vim.fn.chanclose, jid, "stdin")

	if timeout_ms > 0 then
		vim.defer_fn(function()
			-- jobwait timeout=0 returns -1 sentinel for still-running job
			local res = vim.fn.jobwait({ jid }, 0)
			if res and res[1] == -1 then
				timed_out.value = true
				pcall(vim.fn.jobstop, jid)
			end
		end, timeout_ms)
	end

	return jid
end

--- Open a terminal split running `opencode run` interactively.
--- @param prompt string|nil  optional prompt; piped to opencode stdin via tmpfile
--- @param opts table         { cmd?: string, model?: string, agent?: string, cwd?: string, split?: string }
--- @return integer jid
function M.run_terminal(prompt, opts)
	opts = opts or {}
	local cmd_bin = opts.cmd or "opencode"
	local split_cmd = opts.split or "rightbelow vsplit"

	local args = { cmd_bin, "run" }
	if opts.model and opts.model ~= "" then
		table.insert(args, "--model")
		table.insert(args, opts.model)
	end
	if opts.agent and opts.agent ~= "" then
		table.insert(args, "--agent")
		table.insert(args, opts.agent)
	end
	if prompt and prompt ~= "" then
		table.insert(args, prompt)
	end

	vim.cmd(split_cmd)
	local jid = vim.fn.jobstart(args, {
		cwd = opts.cwd,
		clear_env = true,
		env = build_env(),
		term = true,
	})
	return jid
end

--- Cancel a previously-started job. Returns true if a stop was issued.
function M.cancel(jid)
	if not jid or jid <= 0 then
		return false
	end
	local ok = pcall(vim.fn.jobstop, jid)
	return ok
end

M._build_env = build_env
M._make_jsonl_decoder = make_jsonl_decoder

return M
