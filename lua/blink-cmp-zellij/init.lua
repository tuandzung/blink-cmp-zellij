---@class blink-cmp-zellij.Opts
---@field all_panes boolean
---@field triggered_only boolean
---@field trigger_chars string[]
---@field cache_ttl integer Cache duration in milliseconds (default 500)

---@type blink-cmp-zellij.Opts
local default_opts = {
	all_panes = false,
	triggered_only = false,
	trigger_chars = { "." },
	cache_ttl = 500,
}

---@module "blink.cmp"
---@class blink.cmp.zellijSource: blink.cmp.Source
---@field opts blink-cmp-zellij.Opts
---@field _cache table|nil
local zellij = {}

---@param opts blink-cmp-zellij.Opts
---@return blink.cmp.zellijSource
function zellij.new(opts)
	local self = setmetatable({}, { __index = zellij })

	self.opts = vim.tbl_deep_extend("force", default_opts, opts)
	self._cache = { words = nil, timestamp = 0 }

	return self
end

---@return boolean
function zellij:enabled()
	return vim.fn.executable("zellij") == 1 and os.getenv("ZELLIJ") ~= nil
end

---@return string[]
function zellij:get_trigger_characters()
	return self.opts.trigger_chars
end

---@param str string
---@return string
local function strip_ansi(str)
	return str:gsub("\27%[[%d;]*%a", ""):gsub("\27%]%d+;[^\7]*\7", "")
end

---@param content string
---@return string[]
local function extract_words(content)
	local words = {}
	for word in string.gmatch(content, "[%w%d_:/.%-~]+") do
		words[word] = true
		for sub_word in string.gmatch(word, "[%w%d]+") do
			words[sub_word] = true
		end
	end
	return vim.tbl_keys(words)
end

---@param context blink.cmp.Context
---@param words string[]
---@return lsp.CompletionItem[]
local function build_completion_items(context, opts, words)
	return vim.iter(words)
		:map(function(word)
			---@type lsp.CompletionItem
			local item = {
				label = word,
				kind = require("blink.cmp.types").CompletionItemKind.Text,
				insertText = word,
			}
			if opts.triggered_only then
				item = vim.tbl_deep_extend("force", item, {
					textEdit = {
						newText = word,
						range = {
							start = { line = context.cursor[1] - 1, character = context.bounds.start_col - 2 },
							["end"] = { line = context.cursor[1] - 1, character = context.cursor[2] },
						},
					},
				})
			end
			return item
		end)
		:totable()
end

---Fetch content from all panes (or current pane) asynchronously.
---@param all_panes boolean
---@param callback fun(words: string[])
---@return fun() cancel
local function fetch_words_async(all_panes, callback)
	local cancelled = false
	local procs = {} ---@type vim.SystemObj[]

	local function cancel()
		cancelled = true
		for _, proc in ipairs(procs) do
			proc:kill()
		end
	end

	if not all_panes then
		local proc = vim.system({ "zellij", "action", "dump-screen" }, { text = true }, function(result)
			if cancelled then return end
			local content = result.code == 0 and strip_ansi(result.stdout or "") or ""
			callback(extract_words(content))
		end)
		table.insert(procs, proc)
		return cancel
	end

	-- all_panes: list panes first, then dump each in parallel
	local proc = vim.system({ "zellij", "action", "list-panes", "--json" }, { text = true }, function(result)
		if cancelled then return end

		local pane_ids = {}
		if result.code == 0 and result.stdout then
			local ok, panes = pcall(vim.json.decode, result.stdout)
			if ok and type(panes) == "table" then
				local current_id = tonumber(os.getenv("ZELLIJ_PANE_ID"))
				for _, pane in ipairs(panes) do
					if not pane.is_plugin and pane.id ~= current_id then
						table.insert(pane_ids, pane.id)
					end
				end
			end
		end

		if #pane_ids == 0 then
			callback({})
			return
		end

		local pending = #pane_ids
		local all_words = {}

		for _, id in ipairs(pane_ids) do
			local p = vim.system(
				{ "zellij", "action", "dump-screen", "--pane-id", tostring(id) },
				{ text = true },
				function(dump_result)
					if cancelled then return end
					if dump_result.code == 0 then
						local content = strip_ansi(dump_result.stdout or "")
						for word in string.gmatch(content, "[%w%d_:/.%-~]+") do
							all_words[word] = true
							for sub_word in string.gmatch(word, "[%w%d]+") do
								all_words[sub_word] = true
							end
						end
					end
					pending = pending - 1
					if pending == 0 then
						callback(vim.tbl_keys(all_words))
					end
				end
			)
			table.insert(procs, p)
		end
	end)
	table.insert(procs, proc)

	return cancel
end

---@param context blink.cmp.Context
---@param callback fun(items: blink.cmp.CompletionItem[])
function zellij:get_completions(context, callback)
	local triggered = not self.opts.triggered_only
		or vim.list_contains(
			self:get_trigger_characters(),
			context.line:sub(context.bounds.start_col - 1, context.bounds.start_col - 1)
		)

	if not triggered then
		callback({
			items = {},
			is_incomplete_backward = true,
			is_incomplete_forward = true,
		})
		return
	end

	-- check TTL cache
	local now = vim.uv.hrtime() / 1e6
	local cache = self._cache
	if cache.words and (now - cache.timestamp) < self.opts.cache_ttl then
		callback({
			items = build_completion_items(context, self.opts, cache.words),
			is_incomplete_backward = true,
			is_incomplete_forward = true,
		})
		return
	end

	-- async fetch
	local cancel = fetch_words_async(self.opts.all_panes, function(words)
		self._cache.words = words
		self._cache.timestamp = vim.uv.hrtime() / 1e6
		callback({
			items = build_completion_items(context, self.opts, words),
			is_incomplete_backward = true,
			is_incomplete_forward = true,
		})
	end)

	return cancel
end

return zellij
