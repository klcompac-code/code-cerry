
local Step   = require("prometheus.step")
local Parser = require("prometheus.parser")
local Enums  = require("prometheus.enums")
local logger = require("logger")

local DebugDetection = Step:extend()
DebugDetection.Description = "Detects debug library usage, sethook, and RE tools at runtime"
DebugDetection.Name        = "Debug Detection"
DebugDetection.SettingsDescriptor = {
    DetectSethook   = { type="boolean", default=true },
    DetectGetinfo   = { type="boolean", default=true },
    DetectProfiler  = { type="boolean", default=true },
    DetectRobloxRE  = { type="boolean", default=true },
    Action          = { type="enum", default="hang", values={"hang","error","poison"} },
}
function DebugDetection:init(_) end

function DebugDetection:apply(ast, pipeline)
    if pipeline.PrettyPrint then return ast end

    local action
    if self.Action == "hang"   then action = "repeat until false"
    elseif self.Action == "error" then action = 'error("[DBG_DETECT] Debugger detected",0)'
    else action = "local _t={} for _i=1,1e7 do _t[_i]=_i end" end  -- memory poison

    local blocks = {}

    if self.DetectSethook then
        blocks[#blocks+1] = string.format([[
do
    local _dbg_ok = pcall(function()
        if type(debug) ~= "table" then return end
        local _hooked = false
        local _orig = debug.sethook
        if type(_orig) ~= "function" then
            _hooked = true
        else
            local _hook, _mask, _count = debug.gethook and debug.gethook()
            if _hook ~= nil then _hooked = true end
        end
        if _hooked then %s end
    end)
end]], action)
    end

    if self.DetectGetinfo then
        local magic = math.random(1000,9999)
        blocks[#blocks+1] = string.format([[
do
    local _gi_ok = pcall(function()
        if type(debug) ~= "table" then return end
        if type(debug.getinfo) ~= "function" then return end
        local _info = debug.getinfo(1, "S")
        if _info and _info.what == "Lua" then
            local _info2 = debug.getinfo(2, "Sln")
            if _info2 and _info2.what == "C" and _info2.name ~= "pcall" and _info2.name ~= "xpcall" then
                %s
            end
        end
    end)
    _ = %d  -- anti-strip sentinel
end]], action, magic)
    end

    if self.DetectProfiler then
        blocks[#blocks+1] = string.format([[
do
    local _t0 = os.clock()
    local _acc = 0
    for _i = 1, 500 do _acc = _acc + _i end
    local _t1 = os.clock()
    local _elapsed = _t1 - _t0
    if _elapsed > 0.05 then
        pcall(print, "[DBG_DETECT] Timing anomaly: " .. tostring(_elapsed) .. "s (profiler?)")
        %s
    end
    _ = _acc  -- prevent optimizer removal
end]], action)
    end

    if self.DetectRobloxRE then
        blocks[#blocks+1] = string.format([[
do
    local _re_detected = false
    if type(rconsoleprint) == "function" and type(getgenv) ~= "function" then
        _re_detected = true
    end
    if type(hookfunction) == "function" then
        _re_detected = true
    end
    if type(replaceclosure) == "function" then
        _re_detected = true
    end
    if _re_detected then
        pcall(warn, "[DBG_DETECT] RE tool detected")
        %s
    end
end]], action)
    end

    local parser = Parser:new({ LuaVersion = Enums.LuaVersion.Lua51 })
    for i = #blocks, 1, -1 do
        local ok, parsed = pcall(function() return parser:parse(blocks[i]) end)
        if ok then
            local doStat = parsed.body.statements[1]
            doStat.body.scope:setParent(ast.body.scope)
            table.insert(ast.body.statements, 1, doStat)
        else
            logger:warn("[DebugDetection] block " .. i .. " parse failed")
        end
    end
    return ast
end

return DebugDetection
