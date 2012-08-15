
local function try_require(name)
	local stat, mod = pcall(require, name)
	if stat then return mod end
	print("Failed to load:", name, mod)
	return nil
end

local base = "net-bench.cmd_prompts."
local prompts = { "linenoise", "simple" }
for _,name in ipairs(prompts) do
	local prompt = try_require(base .. name)
	if prompt then return prompt end
end

error("Failed to create command prompt.")
