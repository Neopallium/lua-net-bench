
local epoller = require"net-bench.epoller"

local sock = require"net-bench.sock"
local new_sock = sock.new
local sock_flags = sock.NONBLOCK + sock.CLOEXEC

local llnet = require"llnet"

local json = require"json"

local function format_message(msg)
	local msg = json.encode(msg)
	return #msg .. ":" .. msg
end

local function send_data(sock, data)
	if sock.is_connected then
		-- TODO: handle error/blocking
		sock:send(data)
	else
		-- queue data for sending when connected
		sock.out_data = (sock.out_data or '') .. data
		return
	end
end

local function send_msg(sock, msg)
	if type(msg) ~= 'string' then
		msg = format_message(msg)
	end
	return sock:send_data(msg)
end

local MAX_MESSAGE_SIZE = 8 * 1024 -- 8Kbytes
local MAX_SIZE_LEN = 8
local function parse_msgs(sock, data)
	-- find end of "size:" prefix.
	local idx = data:find(":", 1, true)
	if not idx then
		if #data > MAX_SIZE_LEN then
			sock:on_close("Invalid message")
			return
		end
		-- need more data
		return data
	end
	if idx > MAX_SIZE_LEN then
		sock:on_close("Invalid message")
		return
	end
	-- parse message size
	local size = tonumber(data:sub(1,idx - 1))
	-- check if full message is available
	local msg_len = idx + size
	local data_len = #data
	if msg_len > data_len then
		-- need more data
		return data
	end
	-- cut message from data.
	local msg = data:sub(idx+1, msg_len)
	-- parse json message
	local stat, msg = pcall(json.decode,msg)
	if not stat then
		sock:on_close("Malformed message:" .. msg)
		return
	end
	if type(msg) ~= 'table' then
		sock:on_close("Malformed message: type=" .. type(msg))
		return
	end
	-- deliver message to app.
	sock.app:on_message(sock, msg)
	-- check if there is more data available.
	if data_len > msg_len then
		-- remove parsed data.
		data = data:sub(msg_len+1)
		-- parse next message
		return parse_msgs(sock, data)
	end
end

local READ_LEN = 2 * 1024
local function on_data_event(sock, ev)
	local data, err = sock:recv(READ_LEN)
	if data then
		-- append data to buffered data
		if sock.in_data then
			data = sock.in_data .. data
			sock.in_data = nil
		end
		data = parse_msgs(sock, data)
		if data then
			-- partial data?
			if #data > MAX_MESSAGE_SIZE then
				return sock:on_close("ENOBUF")
			end
			sock.in_data = data
		end
	elseif err ~= 'EAGAIN' then
		sock:on_close(err)
	end
end

local function on_connected_event(sock, ev)
	sock.on_io_event = on_data_event
	sock.is_connected = true
	sock.poll:mod(sock, epoller.EPOLLIN)
	local data = sock.out_data
	if data then
		-- TODO: check for error or blocking.
		sock:send(data)
	end
end

local function on_close(sock, err)
	sock.in_data = nil
	sock.out_data = nil
	sock.poll:del(sock)
	sock:close()
	sock.app:close_client(sock, err)
end

local _M = { format_message = format_message }

-- wrap sock
local function wrap_sock(app, sock, is_connected)
	sock.app = app
	sock.poll = app:get_poll()
	sock.send_msg = send_msg
	sock.send_data = send_data
	sock.on_close = on_close
	sock.is_connected = is_connected
	if is_connected then
		-- socket is connect
		sock.on_io_event = on_data_event
		sock.poll:add(sock, epoller.EPOLLIN)
	else
		-- need to wait for connect.
		sock.on_io_event = on_connected_event
		sock.poll:add(sock, epoller.EPOLLOUT)
	end
	return sock
end

function _M.wrap_connection(app, sock)
	return wrap_sock(app, sock, true)
end

-- create new client.
function _M.new_connection(app, host, port)
	local sock = assert(new_sock('inet', 'stream', 0, sock_flags))
	local stat, err = sock:connect(host, port)
	local is_connected = true
	if not stat then
		if err ~= 'EINPROGRESS' then
			error("Failed to connect to server: " .. err)
		end
		is_connected = false
	end
	return wrap_sock(app, sock, is_connected)
end

return setmetatable(_M, { __call = function(tab, ...) return _M.new_connection(...) end})
