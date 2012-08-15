
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

end

function app:send_cmd(name, param)
	self.conn:send_msg({ command = name, param = param })
	return true
end

function app:init(conf)
	--
	-- Enable command prompt
	--
	local prompt = self:create_prompt("? ")
	prompt:history_load(".control_history.txt")

	--
	-- prompt commands.
	--
	local cmds = self:get_commands()
	cmds:cmd('get_stats', 'send_cmd',
		[[Get stats from control node.]]
	)
	cmds:cmd('force_shutdown', 'send_cmd',
		[[Force shutdown of control node, don't wait for clients to disconnect.]]
	)
	cmds:cmd('shutdown', 'send_cmd',
		[[Shutdown control node and all clients connected to it.]]
	)
	cmds:cmd_json('send_to_all', 'send_cmd',
		{ command = 'cmd' },
		[[Send a command to all clients of the control node.]]
	)
	cmds:cmd_json('send_to_workers', 'send_cmd',
		{ command = 'cmd' },
		[[Send a command to all workers of the control node.]]
	)

	return self:connect_to_control()
end

function app:connect_to_control()
	--
	-- connect to control server
	--
	local conf = self.conf
	self.conn = new_connection(self, conf.host, conf.port)
	self.is_connecting = true
	app:send_cmd("get_stats")
end


function app:idle()
	if self.is_running then
		return self.prompt:next_command()
	end
end

function app:finished()
	self.prompt:history_save(".control_history.txt")
	print("Exiting....")
end

function app:close_client(client, err)
	if err ~= 'CLOSED' then
		print("client error:", err)
	end
	print("Connection to control server closed.")
	self.conn = nil
	if not self.is_reconnect then
		self:stop()
		return
	end
	self.is_reconnect = false
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
	elseif cmd == 'force_shutdown' then
		os.exit()
	elseif cmd == 'reconnect' then
		self.is_reconnect = true
		self.conn:on_close()
	elseif cmd == 'shutdown' then
		self:stop()
	else
		print("got control msg:", cmd)
	end
end

app:start(arg)
