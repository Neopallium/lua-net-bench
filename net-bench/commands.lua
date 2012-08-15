
local stdout = io.stdout
local function printf(fmt, ...)
	return stdout:write(fmt:format(...))
end

local json = require"json"

local command_json_mt = {
	__call = function(self, name, app, params)
		if params then
			local stat, parsed = pcall(json.decode, params)
			if stat then
				params = parsed
			else
				print("Failed to parse parameters:", parsed)
				return
			end
		end
		return app[self.method](app, name, params)
	end,
}

local command_mt = {
	__call = function(self, name, app, params)
		if params then
			local list = {}
			for p in params:gmatch("([^%s]+)") do
				list[#list + 1] = p
			end
			return app[self.method](app, name, unpack(list))
		else
			return app[self.method](app, name)
		end
	end,
}

local commands_meth = {}
local commands_mt = {
	__index = commands_meth,
	__call = function(self, ...) return self:do_command(...) end,
}

local function add_cmd(self, name, cmd)
	self.cmds[name] = cmd
	self.list[#self.list + 1] = cmd
	if #name > self.max_name_len then
		self.max_name_len = #name
	end
end

function commands_meth:cmd_json(name, app_method, defaults, short_desc, long_desc)
	local cmd = setmetatable({
		name = name, method = app_method,
		format = 'json',
		defaults = json.encode(defaults or {}),
		short_desc = short_desc,
		long_desc = long_desc,
	}, command_json_mt)
	return add_cmd(self, name, cmd)
end

function commands_meth:cmd(name, app_method, short_desc, long_desc)
	local cmd = setmetatable({
		name = name, method = app_method, format = ' ',
		short_desc = short_desc,
		long_desc = long_desc,
	}, command_mt)
	return add_cmd(self, name, cmd)
end

function commands_meth:alias(name, cmd)
	return add_cmd(self, name, {
		name = name,
		alias = cmd,
		short_desc = "Alias for command '" .. cmd .. "'",
	})
end

local function help_completion(self, list, str)
	local prefix = 'help '
	list:add('help') -- quick access to command list.
	for _,cmd in ipairs(self.list) do
		if cmd.name ~= 'help' then
			list:add(prefix .. cmd.name)
		end
	end
end

function commands_meth:on_completion(list, str)
	local prefix = ''
	-- check for a full command
	local name,idx = str:match("([-%w_]+)[ ]*()")
	local cmd = self.cmds[name]
	if cmd then
		-- handle help completion
		if name == 'help' then
			return help_completion(self, list, str)
		end
		-- completion command with defaults if any.
		if cmd.defaults then
			list:add(name .. ' ' .. cmd.defaults)
			return
		end
	end
	local len = #str
	local cnt = 0
	local match_help = false
	for _,cmd in ipairs(self.list) do
		local cmd = cmd.name
		if #cmd >= len and cmd:sub(1,len) == str then
			if cmd == 'help' then
				match_help = true
			else
				cnt = cnt + 1
				list:add(prefix .. cmd .. ' ')
			end
		end
	end
	if match_help then
		if cnt == 0 then
			-- only the 'help' command matched
			return help_completion(self, list, str)
		else
			-- other commands matched so just add 'help' to the end of the list.
			list:add('help')
		end
	end
end

function commands_meth:help(name)
	if name then
		local cmd = self.cmds[name]
		if cmd then
			printf(name .. ":\n")
			print(cmd.long_desc or cmd.short_desc or 'No description')
			return true
		end
	end
	-- list all commands.
	printf("Commands:\n")
	local fmt = ("  %%-%2ds  %%s\n"):format(self.max_name_len)
	for _,cmd in ipairs(self.list) do
		printf(fmt, cmd.name, cmd.short_desc or '')
	end
	return true
end

function commands_meth:do_command(name, params)
	local cmd = self.cmds[name]
	if cmd then
		if cmd.alias then
			return self:do_command(cmd.alias, params)
		end
		return cmd(name, self.app, params)
	end
	print("Unknown command:", name)
	return nil, "UNKNOWN"
end

local _M = {}

function _M.new_commands(app)
	return setmetatable({
		list = {}, cmds = {}, app = app,
		max_name_len = 4,
	}, commands_mt)
end

return setmetatable(_M, { __call = function(tab, ...) return _M.new_commands(...) end })
