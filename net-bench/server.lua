
local epoller = require("net-bench.epoller")

local sock = require("net-bench.sock")
local new_sock = sock.new

local server_meth = {}
local server_mt = { __index = server_meth }

local function server_accept(acceptor, ev)
	local sock = acceptor:accept()
	if not sock then return end
	return acceptor.server:new_client(sock)
end

function server_meth:new_acceptor(host, port, family, listen)
	print("listen on:", port)
	local acceptor = new_sock(family or 'inet', 'stream')
	acceptor:setblocking(false)
	assert(acceptor:setopt('socket', 'reuseaddr', 1))
	local stat, err = acceptor:bind(host, port)
	if err == 'EADDRINUSE' then
		return false
	end
	assert(acceptor:listen(listen or 30000))
	-- register callback for read events.
	acceptor.server = self
	acceptor.on_io_event = server_accept
	self.poll:add(acceptor, epoller.EPOLLIN)
	self[#self + 1] = acceptor
	return true
end

function server_meth:close()
	local poll = self.poll
	for i=1,#self do
		local acceptor = self[i]
		self[i] = nil
		poll:del(acceptor)
		acceptor:close()
	end
end

function server_meth:new_client(client)
	client:setblocking(false)
	return self.new_client_cb(self.poll, client)
end

local _M = {}

function _M.new_server(poll, new_client)
	local self = { poll = poll, new_client_cb = new_client }
	return setmetatable(self, server_mt)
end

return setmetatable(_M, { __call = function(tab, ...) return _M.new_server(...) end})
