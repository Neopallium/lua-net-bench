
local options = require"net-bench.options"
local epoller = require"net-bench.epoller"
local server = require"net-bench.server"

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

function meths:new_server(...)
	return server(self.poll, ...)
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
