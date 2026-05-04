local config = require("kls-debug.config")

describe("kls-debug.config", function()
	it("exposes defaults", function()
		assert.is_table(config.defaults)
		assert.are.same({
			model = nil,
			agent = nil,
			output = "split",
			timeout_ms = 60000,
			kls_connect_timeout_ms = 500,
			buffer_byte_cap = 102400,
			buffer_around_cursor = 20480,
			diagnostic_cap = 50,
			log_tail_lines = 200,
			surrounding_lines = 10,
			context = {
				diagnostics = true,
				buffer = true,
				selection = true,
				kls = true,
				cursor_symbol = true,
				kls_log = true,
				git = true,
				agents_md = true,
			},
			kls_log_path = nil,
			keymaps = {
				visual = "<leader>kd",
				normal_diag = "<leader>kd",
				enabled = true,
			},
		}, config.defaults)
	end)

	it("deep merges user values", function()
		local merged = config.merge({
			output = "float",
			context = {
				git = false,
			},
			keymaps = {
				enabled = false,
			},
		})

		assert.are.equal("float", merged.output)
		assert.is_false(merged.context.git)
		assert.is_true(merged.context.buffer)
		assert.is_false(merged.keymaps.enabled)
		assert.are.equal("<leader>kd", merged.keymaps.visual)
	end)

	it("rejects bad values", function()
		assert.has_error(function()
			config.validate({ output = "bogus" })
		end, "output must be one of split, float, tab")

		assert.has_error(function()
			config.validate({ timeout_ms = -1 })
		end, "timeout_ms must be a positive integer")

		assert.has_error(function()
			config.validate({
				keymaps = { visual = 10, normal_diag = "<leader>kd", enabled = true },
			})
		end, "keymaps.visual must be string")
	end)

	it("accepts good values", function()
		local validated = config.validate({
			model = "gpt-5.4-mini",
			agent = "oracle",
			output = "tab",
			timeout_ms = 120000,
			kls_connect_timeout_ms = 750,
			buffer_byte_cap = 204800,
			buffer_around_cursor = 40960,
			diagnostic_cap = 25,
			log_tail_lines = 100,
			surrounding_lines = 5,
			context = {
				diagnostics = true,
				buffer = false,
				selection = true,
				kls = true,
				cursor_symbol = false,
				kls_log = true,
				git = false,
				agents_md = true,
			},
			kls_log_path = "/tmp/kls-debug.log",
			keymaps = {
				visual = "<leader>kD",
				normal_diag = "<leader>kD",
				enabled = true,
			},
		})

		assert.are.equal("gpt-5.4-mini", validated.model)
		assert.are.equal("oracle", validated.agent)
		assert.are.equal("tab", validated.output)
		assert.are.equal(120000, validated.timeout_ms)
		assert.are.equal("/tmp/kls-debug.log", validated.kls_log_path)
	end)
end)
