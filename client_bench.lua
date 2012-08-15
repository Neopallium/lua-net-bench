
local app = require"net-bench.app"

local stdout = io.stdout
function printf(fmt, ...)
	return stdout:write(fmt:format(...))
end

-- zmq used for stopwatch timer.
local zmq = require"zmq"

function app:pre_init()
	local opts = self:get_options()
	opts:opt_string('bench', 'b', 'fake_http')
	opts:opt_bool('keep_alive', 'k', false)
	opts:opt_integer('threads', 't', 0)
	opts:opt_string('family', 'f', 'inet')
	opts:required_integer('concurrent', 'c')
	opts:required_integer('requests', 'n')
	opts:required_positional('url')

end

function app:init(conf)
	assert(conf.concurrent <= conf.requests, "insane arguments")

	--
	-- create selected benchmark.
	--
	local stat, bench = pcall(require, "net-bench.benchs." .. conf.bench)
	if stat then
		bench = bench()
		self.bench = bench
	else
		error("Failed to load benchmark module:" .. bench)
	end
	--
	-- Progress printer
	--
	conf.progress_units = 10
	conf.checkpoint = math.floor(conf.requests / conf.progress_units)
	self.percent = 0
	self.last_done = 0

	printf("%d concurrent requests, %d total requests\n\n", conf.concurrent, conf.requests)

	self.progress_timer = zmq.stopwatch_start()
	self.timer = zmq.stopwatch_start()

	bench:start(self, conf)
	self.stats = bench.stats
end

function app:idle()
	return self.bench:idle()
end

function app:print_progress()
	local conf = self.conf
	local s = self.stats
	local elapsed = self.progress_timer:stop()
	if elapsed == 0 then elapsed = 1 end

	local reqs = s.done - self.last_done
	local throughput = reqs / (elapsed / 1000000)
	self.last_done = s.done

	self.percent = self.percent + conf.progress_units
	printf([[
progress: %3i%% done, %7i requests, %5i open conns, %i.%03i%03i sec, %5i req/s
]], self.percent, s.done, s.clients,
	(elapsed / 1000000), (elapsed / 1000) % 1000, (elapsed % 1000), throughput)
	-- start another progress_timer
	if self.percent < 100 then
		self.progress_timer = zmq.stopwatch_start()
	end
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

return app:start(arg)
