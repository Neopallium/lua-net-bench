
local L = require"linenoise"

local meths = {}
local mt = { __index = meths }

function meths:history_save(filename)
	return L.historysave(filename)
end

function meths:history_load(filename)
	return L.historyload(filename)
end

function meths:history_setmaxlen(len)
	return L.historysetmaxlen(len)
end

function meths:history_add(line)
	return L.historyadd(line)
end

function meths:clear_screen()
	return L.clearscreen()
end

function meths:set_prompt(prompt)
	self.prompt = prompt
end

function meths:on_completion(complete, str)
	-- place-holder
end

function meths:on_exit()
	-- place-holder
	print("on_exit callback missing.")
	os.exit()
end

function meths:on_command(cmd)
	-- place-holder
	print("on_command callback missing.")
	return true
end

function meths:next_command()
	local cmd = L.linenoise(self.prompt)
	if cmd then
		return self:on_command(cmd)
	end
	return self:on_exit()
end

local complete_meths = {}
local complete_mt = { __index = complete_meths }
function complete_meths:add(text)
	return L.addcompletion(self.c, text)
end

return function(prompt)
	local self = setmetatable({ prompt = prompt }, mt)
	L.setcompletion(function(c, str)
		return self:on_completion(setmetatable({ c = c }, complete_mt), str)
	end)
	return self
end

