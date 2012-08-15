
local app = require"net-bench.app"

local epoller = require"net-bench.epoller"

local client = require"net-bench.json.client"
local new_connection = client.new_connection

local stdout = io.stdout
function printf(fmt, ...)
	return stdout:write(fmt:format(...))
end

function app:pre_init()
	local opts = self:get_options()
	opts:opt_string('host', 'h', "127.0.0.1")
	opts:opt_integer('port', 'p', 2020)

	opts:opt_integer('workers', 'w', 1)

end

function app:send_cmd(name, params)
	local msg
	if type(params) ~= 'table' then
		msg = { command = name }
		if params then
			msg.params = params
		end
	else
		msg = params
		msg.command = name
	end
	self.conn:send_msg(msg)
	return true
end

function app:init(conf)
	return self:connect_to_control()
end

function app:connect_to_control()
	--
	-- connect to control server
	--
	local conf = self.conf
	self.conn = new_connection(self, conf.host, conf.port)
	self.is_connecting = true

	-- register this worker with the control node.
	self:send_cmd('reg_worker', { sub_workers = conf.workers })
end

function app:finished()
	print("Exiting....")
end

function app:close_client(client, err)
	if err ~= 'CLOSED' then
		print("client error:", err)
	end
	print("Connection to control server closed.")
	self.conn = nil
	-- try to re-connect
	self:connect_to_control()
end

function app:on_message(client, msg)
	local cmd = msg.command
	if cmd == 'stats' then
		printf("Stats:")
		for k,v in pairs(msg.stats) do
			printf(' %s: %d,',tostring(k),tonumber(v))
		end
		printf("\n")
	elseif cmd == 'reconnect' then
		self.conn:on_close()
	elseif cmd == 'force_shutdown' then
		os.exit()
	elseif cmd == 'shutdown' then
		self:stop()
	else
		print("got control unhandled msg:", cmd)
	end
end

app:start(arg)
