
local app = require"net-bench.app"
local epoller = require"net-bench.epoller"

local sock = require"net-bench.sock"
local new_sock = sock.new
local sock_flags = sock.NONBLOCK + sock.CLOEXEC

local llnet = require"llnet"

local stdout = io.stdout
function printf(fmt, ...)
	return stdout:write(fmt:format(...))
end

-- zmq used for stopwatch timer.
local zmq = require"zmq"

function app:pre_init()
	local opts = self:get_options()
	opts:opt_bool('keep_alive', 'k', false)
	opts:opt_integer('threads', 't', 0)
	opts:opt_string('family', 'f', 'inet')
	opts:required_integer('concurrent', 'c')
	opts:required_integer('requests', 'n')
	opts:required_positional('url')

	return self:bench_pre_init()
end

function app:init(conf)
	assert(conf.concurrent <= conf.requests, "insane arguments")

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
	-- Progress printer
	--
	self.progress_units = 10
	self.checkpoint = math.floor(conf.requests / self.progress_units)
	self.percent = 0
	self.last_done = 0

	--
	-- Parse URL
	--
	local uri = require"handler.uri"
	local url = uri.parse(conf.url)
	conf.port = url.port or 80
	conf.host = url.host
	conf.url = url

	self:bench_init(conf)
	printf("%d concurrent requests, %d total requests\n\n", conf.concurrent, conf.requests)

	self.progress_timer = zmq.stopwatch_start()
	self.timer = zmq.stopwatch_start()

	-- create first batch of clients.
	self.need_clients = conf.concurrent
	self.batch_size = math.max(conf.concurrent / 100, 1)
	self:idle()
end

function app:idle()
	-- check if we still need to create more clients.
	local need = self.need_clients
	if need > 0 then
		--
		-- Create a batch of clients.
		--
		local conf = self.conf
		local s = self.stats
		local create = math.min(self.batch_size, need)
		for i=1,create do
			self:new_client()
		end
		self.need_clients = need - create
		assert(s.clients <= conf.concurrent, "Too many clients.")
	end
end

function app:print_progress()
	local s = self.stats
	local elapsed = self.progress_timer:stop()
	if elapsed == 0 then elapsed = 1 end

	local reqs = s.done - self.last_done
	local throughput = reqs / (elapsed / 1000000)
	self.last_done = s.done

	self.percent = self.percent + self.progress_units
	printf([[
progress: %3i%% done, %7i requests, %5i open conns, %i.%03i%03i sec, %5i req/s
]], self.percent, s.done, s.clients,
	(elapsed / 1000000), (elapsed / 1000) % 1000, (elapsed % 1000), throughput)
	-- start another progress_timer
	if self.percent < 100 then
		self.progress_timer = zmq.stopwatch_start()
	end
end

function app:request_finished(sock, succeeded, need_close)
	local s = self.stats
	local conf = self.conf
	if succeeded then
		s.succeeded = s.succeeded + 1
	else
		s.failed = s.failed + 1
	end
	-- the request is finished.
	s.done = s.done + 1
	if (s.done % self.checkpoint) == 0 then
		self:print_progress()
	end
	-- check if we should close the connection.
	if need_close or not conf.keep_alive then
		self:close_client(sock, false)
		return false
	end
	return true
end

function app:finished()
	local conf = self.conf
	local s = self.stats
	local elapsed = self.timer:stop()
	if elapsed == 0 then elapsed = 1 end

	local throughput = s.done / (elapsed / 1000000)

	printf([[

finished in %i sec, %i millisec and %i microsec, %i req/s
requests: %i total, %i started, %i done, %i succeeded, %i failed, %i errored, %i parsed
connections: %i total, %i concurrent
]],
	(elapsed / 1000000), (elapsed / 1000) % 1000, (elapsed % 1000), throughput,
	conf.requests, s.started, s.done, s.succeeded, s.failed, s.errored, s.parsed,
	s.connections, conf.concurrent
	)
end

function app:close_client(sock, err)
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
				print("error after request sent:", err, sock.fd)
			end
		elseif err ~= 'CLOSED' then
			print("error sending request:", err, sock.fd)
		end
	end
	-- clean-up client socket.
	self.poll:del(sock)
	sock:close()
	s.clients = s.clients - 1
	assert(s.clients >= 0, "Can't close more clients then we create.")
	if s.done == conf.requests then
		-- we should be finished.
		self:stop()
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

function app:next_request(sock)
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
	local self = sock.app
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
	local self = sock.app
	sock.on_io_event = parse_response_cb
	app.poll:mod(sock, epoller.EPOLLIN)
	-- send first request
	return self:next_request(sock)
end

function app:new_client()
	local s = self.stats
	local conf = self.conf
	local sock = assert(new_sock(conf.family, 'stream', 0, sock_flags))
	sock.app = self
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

function app:bench_pre_init()
	-- place-holder
end

function app:bench_init(conf)
	-- place-holder
end

local request = "PING"
function app:send_request(sock)
	-- place-holder
	return sock:send(request)
end

function app:parse_response(sock, buf)
	-- place-holder
	if #buf < #request then return false, "EAGAIN" end
	local s = self.stats
	s.parsed = s.parsed + 1
	return (buf:tostring() == request)
end

return app
