local M = {}

local MAX_DIFF_BYTES = 50 * 1024

local function build_env()
	return {
		GIT_OPTIONAL_LOCKS = "0",
		PATH = vim.env.PATH,
		HOME = vim.env.HOME,
	}
end

local function trim(s)
	if type(s) ~= "string" then
		return ""
	end
	return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function join_lines(lines)
	if type(lines) ~= "table" then
		return ""
	end
	local out = {}
	for _, line in ipairs(lines) do
		if line ~= nil and line ~= "" then
			table.insert(out, line)
		end
	end
	return table.concat(out, "\n")
end

local function resolve_file_path(opts, workspace_root)
	if type(opts) ~= "table" then
		return nil
	end

	local file = opts.file_path or opts.current_file or opts.path
	if type(file) == "number" then
		local ok, name = pcall(vim.api.nvim_buf_get_name, file)
		if ok then
			file = name
		end
	elseif file == nil and type(opts.bufnr) == "number" then
		local ok, name = pcall(vim.api.nvim_buf_get_name, opts.bufnr)
		if ok then
			file = name
		end
	end

	if type(file) ~= "string" or file == "" then
		return nil
	end

	local root = vim.fs.normalize(workspace_root)
	local norm = vim.fs.normalize(file)
	if norm:sub(1, #root) ~= root then
		return nil
	end

	local rel = norm:sub(#root + 1)
	if rel:sub(1, 1) == "/" then
		rel = rel:sub(2)
	end
	if rel == "" then
		return nil
	end

	return rel
end

local function collect_command(args, workspace_root, on_done)
	local finished = false
	local stdout = {}
	local function finish(ok, data)
		if finished then
			return
		end
		finished = true
		on_done(ok, data)
	end

	local ok_start, jid = pcall(vim.fn.jobstart, args, {
		cwd = workspace_root,
		clear_env = true,
		env = build_env(),
		stdout_buffered = false,
		stderr_buffered = true,
		on_stdout = function(_, data)
			if type(data) ~= "table" then
				return
			end
			for _, line in ipairs(data) do
				if line ~= nil and line ~= "" then
					table.insert(stdout, line)
				end
			end
		end,
		on_exit = function(_, code, _)
			if code ~= 0 then
				finish(false, "")
				return
			end
			finish(true, join_lines(stdout))
		end,
	})

	if not ok_start or type(jid) ~= "number" or jid <= 0 then
		finish(false, "")
	end
	return jid
end

local function cap_text(text, cap)
	if type(text) ~= "string" then
		return ""
	end
	if #text <= cap then
		return text
	end
	return text:sub(1, cap)
end

local function collect_git_data(opts, workspace_root, callback)
	local result = {
		kind = "git",
		ok = false,
		data = nil,
	}

	if type(workspace_root) ~= "string" or workspace_root == "" then
		result.reason = "not found"
		callback(result)
		return
	end

	local function done(ok, data, reason)
		result.ok = ok
		result.data = data
		result.reason = reason
		callback(result)
	end

	collect_command(
		{ "git", "rev-parse", "--abbrev-ref", "HEAD" },
		workspace_root,
		function(ok_branch, branch)
			if not ok_branch then
				done(false, nil, "not found")
				return
			end

			collect_command(
				{ "git", "log", "-1", "--format=%h %s" },
				workspace_root,
				function(ok_commit, commit)
					if not ok_commit then
						done(false, nil, "not found")
						return
					end

					collect_command(
						{ "git", "status", "--short" },
						workspace_root,
						function(ok_status, status)
							if not ok_status then
								done(false, nil, "not found")
								return
							end

							local rel = resolve_file_path(opts, workspace_root)
							if rel == nil then
								done(true, {
									branch = trim(branch),
									commit = trim(commit),
									status = trim(status),
									diff = "",
								})
								return
							end

							collect_command(
								{ "git", "diff", "--cached", "--", rel },
								workspace_root,
								function(ok_cached, cached)
									if not ok_cached then
										done(false, nil, "not found")
										return
									end

									collect_command(
										{ "git", "diff", "HEAD", "--", rel },
										workspace_root,
										function(ok_worktree, worktree)
											if not ok_worktree then
												done(false, nil, "not found")
												return
											end

											local diff = {
												"--- staged",
												cap_text(trim(cached), MAX_DIFF_BYTES),
												"--- unstaged",
												cap_text(trim(worktree), MAX_DIFF_BYTES),
											}

											done(true, {
												branch = trim(branch),
												commit = trim(commit),
												status = trim(status),
												diff = trim(table.concat(diff, "\n")),
											})
										end
									)
								end
							)
						end
					)
				end
			)
		end
	)
end

function M.collect(opts, workspace_root, callback)
	local cb = type(callback) == "function" and callback or function() end
	local ok, err = pcall(function()
		collect_git_data(opts, workspace_root, cb)
	end)
	if not ok then
		cb({
			kind = "git",
			ok = false,
			data = nil,
			reason = tostring(err),
		})
	end
end

return M
