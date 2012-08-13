
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

function meths:finish()
	-- place-holder
end

function meths:stop()
	self.poll:stop()
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
	self.poll:start()
	-- run any cleanup code.
	self:finished()
end

return app
