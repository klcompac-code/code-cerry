
local Step   = require("prometheus.step")
local Parser = require("prometheus.parser")
local Enums  = require("prometheus.enums")
local RandomStrings = require("prometheus.randomStrings")
local logger = require("logger")

local RobloxEnvLock = Step:extend()
RobloxEnvLock.Description = "Roblox-specific env lock: getgenv, getsenv, metatable guard, executor fingerprint"
RobloxEnvLock.Name        = "Roblox Env Lock"
RobloxEnvLock.SettingsDescriptor = {
    CheckGame      = { type="boolean", default=true,  description="Check game/workspace globals" },
    CheckExecutor  = { type="boolean", default=false, description="Check executor-specific APIs (getgenv, getsenv)" },
    MetatableGuard = { type="boolean", default=true,  description="Protect script metatable from tampering" },
    PoisonGenv     = { type="boolean", default=false, description="Poison getgenv with fake globals" },
}

function RobloxEnvLock:init(_) end

function RobloxEnvLock:apply(ast, pipeline)
    if pipeline.PrettyPrint then
        logger:warn(string.format('"%s" cannot be used with PrettyPrint', self.Name))
        return ast
    end

    local blocks = {}

    -- FIX 1: Removed memory-bomb fail path (local _tag loop with 1e9 ceiling).
    -- The bomb could terminate once ~1 GB was allocated, making it bypassable.
    -- Replaced with `repeat until false` so failure hangs unconditionally,
    -- consistent with every other block in this step.
    if self.CheckGame then
        blocks[#blocks+1] = [[
do
    local _g_ok = (
        type(game)      == "userdata" and
        type(workspace) == "userdata" and
        type(script)    == "userdata" and
        typeof          ~= nil        and
        type(Instance)  == "table"
    )
    if not _g_ok then
        repeat until false
    end
end]]
    end

    if self.CheckExecutor then
        blocks[#blocks+1] = [[
do
    local _exe_ok = (
        type(getgenv)  == "function" and
        type(getsenv)  == "function"
    )
    if not _exe_ok then
        repeat until false
    end
end]]
    end

    if self.MetatableGuard then
        local sentinelKey = RandomStrings.randomString()
        local sentinelVal = math.random(100000, 999999)
        blocks[#blocks+1] = string.format([[
do
    local _sentinel = setmetatable({}, {
        __index = function(t, k)
            if k ~= "%s" then
                repeat until false
            end
            return %d
        end,
        __newindex = function(t, k, v)
            repeat until false
        end,
        __metatable = "locked",
    })
    if _sentinel["%s"] ~= %d then
        repeat until false
    end
end]], sentinelKey, sentinelVal, sentinelKey, sentinelVal)
    end

    -- FIX 2: Wrapped getgenv in an anonymous function inside pcall.
    -- Previously `pcall(getgenv)` evaluated getgenv before passing it to pcall,
    -- so on standard Roblox (where getgenv is nil) the expression threw
    -- "attempt to call a nil value" before pcall could catch anything.
    -- `pcall(function() return getgenv() end)` defers the call safely.
    if self.PoisonGenv then
        local fakeKeys = {}
        for i = 1, math.random(3, 6) do
            fakeKeys[#fakeKeys+1] = string.format(
                '    _genv["%s"] = %d',
                RandomStrings.randomString(),
                math.random(1, 99999)
            )
        end
        blocks[#blocks+1] = string.format([[
do
    local _genv_ok, _genv = pcall(function() return getgenv() end)
    if _genv_ok and type(_genv) == "table" then
%s
    end
end]], table.concat(fakeKeys, "\n"))
    end

    if #blocks == 0 then return ast end

    local parser = Parser:new({ LuaVersion = Enums.LuaVersion.Lua51 })
    for i = #blocks, 1, -1 do
        local ok, parsed = pcall(function() return parser:parse(blocks[i]) end)
        -- FIX 3: Guard against nil doStat/doStat.body before dereferencing.
        -- If the parser succeeds but returns an empty body (statements[1] == nil),
        -- the previous code crashed with "attempt to index a nil value".
        -- Now we skip the block and emit a warning instead of panicking.
        if ok and parsed and parsed.body and parsed.body.statements[1] then
            local doStat = parsed.body.statements[1]
            -- FIX 4: Guard doStat.body before calling setParent.
            -- A valid top-level statement that is not a do-block has no .body,
            -- so setParent would crash. Skip with a warning if the shape is wrong.
            if doStat.body and doStat.body.scope then
                doStat.body.scope:setParent(ast.body.scope)
                table.insert(ast.body.statements, 1, doStat)
            else
                logger:warn(string.format('[%s] block %d has no body scope, skipping', self.Name, i))
            end
        elseif not ok then
            logger:warn(string.format('[%s] block %d parse failed: %s', self.Name, i, tostring(parsed)))
        end
    end

    return ast
end

return RobloxEnvLock
