
local client_type = table.remove(arg, 1) or 'fake_http'

local bench = require("net-bench.clients." .. client_type)

bench:start(arg)

