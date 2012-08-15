
local meths = {}
local mt = { __index = meths }

function meths:history_save()
end

function meths:history_load()
end

function meths:history_setmaxlen()
end

function meths:history_add()
end

function meths:clear_screen()
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
	print(self.prompt or '')
	local cmd = io.read("*l")
	if cmd then
		return self:on_command(cmd)
	end
	return self:on_exit()
end

return function(prompt)
	return setmetatable({ prompt = prompt }, mt)
end

