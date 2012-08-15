
local options_meth = {}
local options_mt = { __index = options_meth }

function options_meth:required_positional(name)
	local opts = self.opts
	local p_idx = #opts + 1
	opts[p_idx] = function(conf, arg_idx, arg)
		conf[name] = arg[arg_idx]
		return 1
	end
	local required = self.required_fields
	required[#required + 1] = name
end

function options_meth:required(name, short_name, cb)
	local opts = self.opts
	opts['--' .. name] = cb
	opts['-' .. short_name] = cb
	local required = self.required_fields
	required[#required + 1] = name
end

function options_meth:required_string(name, short_name)
	return self:required(name, short_name, function(conf, arg_idx, arg)
		conf[name] = arg[arg_idx + 1]
		return 2
	end)
end

function options_meth:required_integer(name, short_name)
	return self:required(name, short_name, function(conf, arg_idx, arg)
		conf[name] = tonumber(arg[arg_idx + 1])
		return 2
	end)
end

function options_meth:opt(name, short_name, default, cb)
	local opts = self.opts
	opts['--' .. name] = cb
	opts['-' .. short_name] = cb
	self.defaults[name] = default
end

function options_meth:opt_string(name, short_name, default)
	return self:opt(name, short_name, default, function(conf, arg_idx, arg)
		conf[name] = arg[arg_idx + 1]
		return 2
	end)
end

function options_meth:opt_integer(name, short_name, default)
	return self:opt(name, short_name, default, function(conf, arg_idx, arg)
		conf[name] = tonumber(arg[arg_idx + 1])
		return 2
	end)
end

function options_meth:opt_bool(name, short_name, default)
	return self:opt(name, short_name, default, function(conf, arg_idx, arg)
		conf[name] = true
		return 1
	end)
end

local function tab_dup(src)
	local dst = {}
	for k,v in pairs(src) do
		if type(v) == 'table' then
			dst[k] = tab_dup(v)
		else
			dst[k] = v
		end
	end
	return dst
end

function options_meth:parse(arg)
	local conf = tab_dup(self.defaults)
	local opts = self.opts
	local i=1
	while i <= #arg do
		local p = arg[i]
		local p_idx
		local cb
		if p:sub(1,1) ~= '-' then
			-- positional parameter.
			p_idx = #conf + 1
			conf[p_idx] = p
			cb = opts[p_idx]
		else
			cb = opts[p]
		end
		local cnt = 1
		if cb then
			cnt = (cb(conf, i, arg) or 1)
		else
			print("Unknown parameter:", p)
		end
		i = i + cnt
	end
	-- check required fields.
	for _,name in ipairs(self.required_fields) do
		if not conf[name] then
			print("Missing required field:", name)
			os.exit()
		end
	end
	return conf
end

local _M = {}

function _M.new_options(parent)
	local opts = {}
	local defaults = {}
	local required_fields = {}
	if parent then
		opts = tab_dup(parent.opts)
		defaults = tab_dup(parent.defaults)
		required_fields = tab_dup(parent.required_fields)
	end
	return setmetatable({ opts = opts, defaults = defaults, required_fields = required_fields },
		options_mt)
end

return setmetatable(_M, { __call = function(tab, ...) return _M.new_options(...) end })
