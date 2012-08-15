
local commands = require"net-bench.commands"
local options = require"net-bench.options"
local epoller = require"net-bench.epoller"

local meths = {}
local app = setmetatable({
	poll = epoller.new(),
	opts = options(),
}, { __index = meths })

function meths:get_poll()
	return self.poll
end

function meths:get_options()
	return self.opts
end

function meths:get_commands()
	return self.cmds
end

local server
function meths:new_server(...)
	if not server then
		server = require"net-bench.server"
	end
	return server(self.poll, ...)
end

function meths:create_prompt(prompt)
	local cmd_prompt = require"net-bench.cmd_prompt"
	if not cmd_prompt then return nil end

	--
	-- prompt commands.
	--
	local cmds = commands(self)
	cmds:cmd('exit', 'stop', [[Exit application]])
	cmds:alias('quit', 'exit')
	cmds:cmd('help', 'on_help_command')
	self.cmds = cmds

	--
	-- prompt
	--
	local prompt = cmd_prompt(prompt)
	self.prompt = prompt
	prompt.on_completion = function(prompt, complete, str)
		return self:on_command_completion(prompt, complete, str)
	end
	prompt.on_command = function(prompt, cmd)
		return self:on_command(prompt, cmd)
	end
	prompt.on_exit = function()
		return self:stop()
	end
	return prompt
end

function app:on_help_command(help, cmd)
	return self.cmds:help(cmd)
end

function app:on_command_completion(prompt, complete, str)
	return self.cmds:on_completion(complete, str)
end

function app:on_command(prompt, line)
	if not line then
		-- stdin closed, stop application.
		self:stop()
	end
	local cmd,idx = line:match("([-%w_]+)[ ]*()")
	if cmd then
		local params = line:sub(idx)
		local stat, err = self.cmds(cmd, params)
		if stat then
			prompt:history_add(line)
		elseif err ~= 'UNKNOWN' then
			return false
		end
	end
	return true
end

function meths:pre_init()
	-- place-holder
end

function meths:init(conf)
	-- place-holder
end

function meths:idle()
	-- place-holder
end

function meths:finish()
	-- place-holder
end

function meths:stop()
	self.is_running = false
end

function meths:start(arg)
	-- call pre-config initialization.
	self:pre_init()
	-- parse command line options
	local conf = self.opts:parse(arg)
	app.conf = conf
	-- initialize application using command line options.
	self:init(conf)
	-- start event loop
	local poll = self.poll
	self.is_running = true
	while self.is_running do
		poll:step(200)
		self:idle()
	end
	-- run any cleanup code.
	self:finished()
	poll:close()
end

return app
