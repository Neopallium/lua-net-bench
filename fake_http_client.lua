
local bench = require"net-bench.client_bench"

function bench:bench_pre_init()
	-- place-holder
end

local REQUEST
function bench:bench_init(conf)
	--
	-- Pre-make HTTP request.
	--
	local http_port = ''
	if conf.port ~= 80 then
		http_port = ':' .. tostring(conf.port)
	end
	REQUEST =
	  "GET " .. conf.url.path .." HTTP/1.1\r\n" ..
		"Host: " .. conf.url.host .. http_port .. "\r\n" ..
	  "User-Agent: fake_http_client/0.1\r\n" ..
	  "Connection: keep-alive\r\n\r\n"
end

function bench:send_request(sock)
	return sock:send(REQUEST)
end

local lhp = require 'http.parser'
local resp_parsed
local http_parser
local function create_parser()
	local parser
	parser = lhp.response({
	-- lua-http-parser needs 'on_body'
	on_body = function(data)
	end,
	on_message_complete = function()
		resp_parsed.status = parser:status_code()
	end,
	})
	return parser
end
http_parser = create_parser()
local parsed_resps = setmetatable({},{
__index = function(tab, resp)
	resp_parsed = { is_new = true }
	local parsed = http_parser:execute(resp)
	if parsed ~= #resp then
		local errno, err, errmsg = http_parser:error()
		resp_parsed.errno = errno
		resp_parsed.errmsg = errmsg
	else
		-- get keep alive flag.
		resp_parsed.keep_alive = http_parser:should_keep_alive()
		rawset(tab, resp, resp_parsed)
	end
	-- need to re-create parser.
	http_parser = create_parser()
	return resp_parsed
end
})

function bench:parse_response(sock, buf)
	local s = self.stats
	local data = buf:tostring()
	-- check resp.
	local resp = parsed_resps[data]
	if resp.is_new then
		-- newly parsed response.
		s.parsed = s.parsed + 1
		resp.is_new = false
	end
	local succeeded, err, need_close
	if resp.status == 200 then
		succeeded = true
	elseif resp.status == nil then
		-- need more data.
		return nil, "EAGAIN", false
	else
		succeeded = false
	end
	-- check if we should close the connection.
	if not resp.keep_alive then
		need_close = true
	end
	return succeeded, err, need_close
end

bench:start(arg)
