
local epoller = require"net-bench.epoller"

local sock = require"net-bench.sock"
local new_sock = sock.new
local sock_flags = sock.NONBLOCK + sock.CLOEXEC

local llnet = require"llnet"

local bench_meths = {}

function bench_meths:start(app, conf)
	assert(conf.concurrent <= conf.requests, "insane arguments")

	self.app = app
	self.conf = conf
	self.poll = app:get_poll()

	local stats = {
		started = 0,
		connections = 0,
		done = 0,
		succeeded = 0,
		failed = 0,
		errored = 0,
		clients = 0,
		parsed = 0,
	}
	self.stats = stats

	--
	-- Parse URL
	--
	local uri = require"handler.uri"
	local url = uri.parse(conf.url)
	conf.port = url.port or 80
	conf.host = url.host
	conf.url = url

	-- initialize benchmark.
	self:init(conf)

	-- create first batch of clients.
	self.need_clients = conf.concurrent
	self.batch_size = math.floor(math.max(conf.concurrent / 10, 1))
	self:idle()
end

function bench_meths:idle()
	-- check if we still need to create more clients.
	if self.need_clients <= 0 then return end
	--
	-- Create a batch of clients.
	--
	local conf = self.conf
	local s = self.stats
	local need = self.need_clients
	local create = math.min(self.batch_size, need)
	for i=1,create do
		self:new_client()
	end
	self.need_clients = need - create
	assert(s.clients <= conf.concurrent, "Too many clients.")
end

function bench_meths:request_finished(sock, succeeded, need_close)
	local s = self.stats
	local conf = self.conf
	if succeeded then
		s.succeeded = s.succeeded + 1
	else
		s.failed = s.failed + 1
	end
	-- the request is finished.
	s.done = s.done + 1
	if (s.done % conf.checkpoint) == 0 then
		self.app:print_progress()
	end
	-- check if we should close the connection.
	if need_close or not conf.keep_alive then
		self:close_client(sock, false)
		return false
	end
	return true
end

function bench_meths:close_client(sock, err)
	local s = self.stats
	local conf = self.conf
	-- check for error
	if err then
		if sock.request_active then
			s.errored = s.errored + 1
			if err == 'CLOSED' then
				s.started = s.started - 1
				self:new_client()
			else
				self.app:stop()
				error("error after request sent: " .. err)
			end
		elseif err ~= 'CLOSED' then
			self.app:stop()
			error("error sending request: " .. err)
		end
	end
	-- clean-up client socket.
	self.poll:del(sock)
	sock:close()
	s.clients = s.clients - 1
	assert(s.clients >= 0, "Can't close more clients then we create.")
	if s.done == conf.requests then
		-- we should be finished.
		self.app:stop()
		return
	end
	-- check if we need to spawn a new client.
	if s.clients < conf.concurrent then
		local need = conf.requests - s.started
		if need > s.clients then
			self:new_client()
		end
	end
end

function bench_meths:next_request(sock)
	local s = self.stats
	local conf = self.conf
	if s.started >= conf.requests then
		sock.request_active = false
		self:close_client(sock, false)
		return
	end
	s.started = s.started + 1
	sock.request_active = true
	local sent, err = self:send_request(sock)
	if not sent then
		sock.request_active = false
		return self:close_client(sock, err)
	end
end

local READ_LEN = 2 * 1024

local new_buf = llnet.LIOBuffer.new
local pool = {}
local function get_buffer()
	local idx = #pool
	if idx > 0 then
		-- get buffer from pool
		local buf = pool[idx]
		pool[idx] = nil
		return buf
	end
	-- allocate new buffer
	return new_buf(READ_LEN)
end

local function release_buffer(buf)
	pool[#pool + 1] = buf
	buf:set_size(0)
end

local function parse_response_cb(sock)
	local self = sock.bench
	local len, err
	local off = 0
	local buf = sock.buf
	if buf then
		-- reuse buffer.
		off = buf:get_size()
	else
		-- need new buffer.
		buf = get_buffer()
	end
	local len, err = sock:recv_buffer(buf, off)
	if len then
		buf:set_size(off + len)
		-- parse response.
		local status, err, need_close = self:parse_response(sock, buf)
		if not status then
			if err == 'EAGAIN' then
				-- got partial response.
				sock.buf = buf
				return
			end
			-- bad response.
		end
		sock.buf = nil
		release_buffer(buf)
		if self:request_finished(sock, status, need_close) then
			-- send a new request.
			if sock.request_active then
				sock.request_active = false
			end
			self:next_request(sock)
		end
	elseif err ~= 'EAGAIN' then
		self:close_client(sock, err)
	end
end

local function connected_cb(sock)
	local self = sock.bench
	sock.on_io_event = parse_response_cb
	self.poll:mod(sock, epoller.EPOLLIN)
	-- send first request
	return self:next_request(sock)
end

function bench_meths:new_client()
	local s = self.stats
	local conf = self.conf
	local sock = assert(new_sock(conf.family, 'stream', 0, sock_flags))
	sock.bench = self
	s.connections = s.connections + 1
	s.clients = s.clients + 1
	local stat, err = sock:connect(conf.host, conf.port)
	if not stat then
		if err == 'EINPROGRESS' then
			-- need to wait for connect.
			sock.on_io_event = connected_cb
		else
			error("Failed to connect to server: " .. err)
		end
		self.poll:add(sock, epoller.EPOLLOUT)
	else
		-- socket is connect
		sock.on_io_event = parse_response_cb
		self.poll:add(sock, epoller.EPOLLIN)
		-- send first request
		self:next_request(sock)
	end
end

local request = "PING"
function bench_meths:send_request(sock)
	-- place-holder
	return sock:send(request)
end

function bench_meths:parse_response(sock, buf)
	-- place-holder
	if #buf < #request then return false, "EAGAIN" end
	local s = self.stats
	s.parsed = s.parsed + 1
	return (buf:tostring() == request)
end


-- Create new type of benchmark.
return function(bench_type)
	-- dup methods table
	local meths = {}
	local mt = { __index = meths }
	for k,v in pairs(bench_meths) do
		meths[k] = v
	end
	return meths, mt
end

