
local meths = {}
local mt = { __index = meths }

local wrap_io = { "close", "flush", "lines", "read", "write", "setvbuf", "seek" }
for _,name in ipairs(wrap_io) do
	local io_func = io[name]
	meths[name] = function(self, ...)
		return io_func(self.file, ...)
	end
end

function meths:fileno()
	return self.fd
end

return function(fd, file)
	return setmetatable({ fd = fd, file = file }, mt)
end

