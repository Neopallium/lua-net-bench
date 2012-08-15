
local app = require"net-bench.app"

local client = require"net-bench.json.client"
local new_connection = client.new_connection
local wrap_client = client.wrap_connection
local format_message = client.format_message

local stdout = io.stdout
function printf(fmt, ...)
	return stdout:write(fmt:format(...))
end

function app:pre_init()
	local opts = self:get_options()
	opts:opt_bool('daemon', 'd', false)
	opts:opt_integer('port', 'p', 2020)
	self.clients = {}
	self.workers = {}
	self.stats = {
		connections = 0,
		workers = 0,
	}
end

function app:init(conf)
	if conf.daemon then
		local nixio = require"nixio"
		local pid = nixio.fork()
		if pid ~= 0 then
			printf("Daemonized pid = %d\n", pid)
			os.exit()
		end
	end
	self.server = app:new_server(function(poll, client)
		return self:new_client(client)
	end)
	app:start_listen()
end

function app:start_listen()
	local conf = self.conf
	local stat = self.server:new_acceptor("0.0.0.0", conf.port)
	if not stat then
		print("----- Failed to listen.  Trying to shutdown old server.")
		-- try to shutdown current server.
		self.old_server = new_connection(self, "127.0.0.1", conf.port)
		self.old_server:send_msg({ command = "new_server" })
		return
	end
	self.old_server = nil
	printf("Running...\n")
end

function app:finished()
	printf("Finished...\n")
	print("---- Stats:")
	for k,v in pairs(self.stats) do
		printf('  %s: %d\n',tostring(k),tonumber(v) or 0)
	end
end

function app:reg_worker(client, msg)
	local s = self.stats
	local worker_id = client.worker_id
	-- ignore if already a worker
	if worker_id then return end
	-- add client to workers list.
	local workers = self.workers
	worker_id = #workers + 1 -- allocate worker id
	client.worker_id = worker_id
	workers[worker_id] = client

	-- track how many workers are available.
	client.sub_workers = tonumber(msg.sub_workers) or 1
	s.workers = s.workers + client.sub_workers
end

function app:unreg_worker(client)
	local s = self.stats
	local worker_id = client.worker_id
	-- ignore if not worker
	if not worker_id then return end
	-- remove client from workers list.
	self.workers[worker_id] = nil
	client.worker_id = nil

	-- remove worker's sub_workers from total worker count
	s.workers = s.workers - client.sub_workers
end

function app:close_client(client, err)
	if self.old_server == client then
		self:start_listen()
		return
	end
	local s = self.stats
	if err ~= 'CLOSED' then
		print("client error:", err)
	end
	self.clients[client.id] = nil
	s.connections = s.connections - 1
	self:unreg_worker(client)
	if self.need_shutdown and s.connections == 0 then
		self:stop()
	end
end

function app:send_to_clients(clients, msg)
	if not msg or type(msg) ~= 'table' then return end
	local data = format_message(msg)
	for id,client in pairs(clients) do
		client:send_msg(data)
	end
end

function app:stats_msg()
	return { command = "stats", stats = self.stats }
end

function app:on_message(client, msg)
	local cmd = msg.command
	print("got client msg:", cmd)
	if cmd == 'get_stats' then
		client:send_msg(self:stats_msg())
	elseif cmd == 'force_shutdown' then
		os.exit()
	elseif cmd == 'ack_new_server' then
		if self.old_server == client then
			client:on_close()
			return
		end
	elseif cmd == 'new_server' then
		self.need_shutdown = true
		-- stop accepting clients.
		self.server:close()
		-- reply to new server.
		client:send_msg({ command = 'ack_new_server' })
		-- send reconnect message to all clients.
		self:send_to_clients(self.clients, { command = 'reconnect' })
	elseif cmd == 'shutdown' then
		self.need_shutdown = true
		-- stop accepting clients.
		self.server:close()
		-- send shutdown message to all clients.
		self:send_to_clients(self.clients, msg)
	elseif cmd == 'reg_worker' then
		self:reg_worker(client, msg)
	elseif cmd == 'unreg_worker' then
		self:unreg_worker(client)
	elseif cmd == 'send_to_all' then
		self:send_to_clients(self.clients, msg.param)
	elseif cmd == 'send_to_workers' then
		self:send_to_clients(self.workers, msg.param)
	end
end

function app:new_client(client)
	if self.need_shutdown then
		-- don't accept new clients when we are shutting down.
		client:close()
		return
	end
	local clients = self.clients
	local s = self.stats
	local id = #clients + 1
	s.connections = s.connections + 1
	client = wrap_client(self, client)
	client.id = id
	clients[id] = client
end

app:start(arg)
