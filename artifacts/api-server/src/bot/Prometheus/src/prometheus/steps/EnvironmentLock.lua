
local Step   = require("prometheus.step")
local Parser = require("prometheus.parser")
local Enums  = require("prometheus.enums")
local logger = require("logger")

local EnvironmentLock = Step:extend()
EnvironmentLock.Description = "Locks script to Roblox environment using env fingerprinting"
EnvironmentLock.Name        = "Environment Lock"
EnvironmentLock.SettingsDescriptor = {
    Mode = {
        type    = "enum",
        default = "roblox",
        values  = { "roblox", "roblox_executor", "custom" },
    },
    CustomChecks = { type="table", default = {} },
    HangOnFail   = { type="boolean", default=true },
}

function EnvironmentLock:init(_) end

function EnvironmentLock:apply(ast, pipeline)
    if pipeline.PrettyPrint then
        logger:warn(string.format('"%s" cannot be used with PrettyPrint', self.Name))
        return ast
    end

    local failAction = self.HangOnFail
        and "repeat until false"
        or  'error("unauthorized environment", 0)'

    local code

    if self.Mode == "roblox" then
        code = string.format([[
do
    local _ok = (
        type(game) == "userdata" and
        type(workspace) == "userdata" and
        typeof ~= nil and
        type(Instance) == "table"
    )
    if not _ok then %s end
end]], failAction)

    elseif self.Mode == "roblox_executor" then
        local checks = math.random(2) == 1
            and "getgenv ~= nil and getsenv ~= nil"
            or  "getgenv ~= nil and syn ~= nil"
        code = string.format([[
do
    local _rbx = (type(game) == "userdata" and typeof ~= nil)
    local _exe = (%s)
    if not (_rbx and _exe) then %s end
end]], checks, failAction)

    else
        local checks = self.CustomChecks
        if #checks == 0 then return ast end
        local parts = {}
        for _, c in ipairs(checks) do
            parts[#parts+1] = string.format("(%s)", c)
        end
        code = string.format("do if not (%s) then %s end end",
            table.concat(parts, " and "), failAction)
    end

    local parser = Parser:new({ LuaVersion = Enums.LuaVersion.Lua51 })
    local ok, parsed = pcall(function() return parser:parse(code) end)
    if not ok then return ast end

    local doStat = parsed.body.statements[1]
    doStat.body.scope:setParent(ast.body.scope)
    table.insert(ast.body.statements, 1, doStat)
    return ast
end

return EnvironmentLock
