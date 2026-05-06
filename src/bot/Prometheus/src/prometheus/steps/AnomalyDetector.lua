local Step   = require("prometheus.step")
local Parser = require("prometheus.parser")
local Enums  = require("prometheus.enums")
local logger = require("logger")

local AnomalyDetector = Step:extend()
AnomalyDetector.Description = "Detects executor anomalies on own VM"
AnomalyDetector.Name        = "Anomaly Detector"
AnomalyDetector.SettingsDescriptor = {
    DetectDump     = { type="boolean", default=false }, -- [FIX-2] default false
    DetectHook     = { type="boolean", default=true },
    DetectTiming   = { type="boolean", default=true },
    DetectEnvSpoof = { type="boolean", default=true },
    KickMessage    = { type="string",  default="Protected: anomaly detected" },
}

function AnomalyDetector:init(_) end

function AnomalyDetector:apply(ast, pipeline)
    if pipeline.PrettyPrint then return ast end

    local kmsg = self.KickMessage:gsub('"','\\"')

    -- [FIX-3] Safe kick handler
    local function ACTION(reason)
        return string.format([[
            pcall(warn, "[ANOMALY] detected: %s | "..tostring(_detail or ""))
            pcall(print, "[ANOMALY] %s")
            local _ok, _lp = pcall(function()
                local Players = game and game:GetService("Players")
                return Players and Players.LocalPlayer
            end)
            if _ok and _lp then
                pcall(function() _lp:Kick("%s") end)
            end
        ]], reason, reason, kmsg)
    end

    local blocks = {}

    -- [FIX-2] DetectDump default false - tidak pakai string.dump
    if self.DetectDump then
        -- Tidak digunakan (string.dump not available)
        logger:warn("[AnomalyDetector] DetectDump enabled but string.dump not available in Roblox")
    end

    -- 2. Hook detection
    if self.DetectHook then
        local tag = math.random(10000,99999)
        blocks[#blocks+1] = string.format([[
do
    local _anomaly=false
    local _ok, _err = pcall(function()
        if type(hookfunction)=="function" then _anomaly=true end
        if type(replaceclosure)=="function" then _anomaly=true end
    end)
    if _anomaly then
        local _detail="hook_api_present"
        %s
    end
end]], ACTION("HOOK_ANOMALY"))
    end

    -- 3. Timing anomaly (safe)
    if self.DetectTiming then
        local iters = math.random(800,1200)
        blocks[#blocks+1] = string.format([[
do
    local _t0 = os.clock()
    local _acc = 0
    for _i=1,%d do _acc = _acc + _i end
    local _elapsed = os.clock() - _t0
    if _elapsed > 0.08 then
        local _detail="timing:"..string.format("%%.4f",_elapsed).."s"
        %s
    end
    _ = _acc
end]], iters, ACTION("TIMING_ANOMALY"))
    end

    -- 4. Environment spoof (safe)
    if self.DetectEnvSpoof then
        local k1 = math.random(100000,999999)
        blocks[#blocks+1] = string.format([[
do
    local _ev = getfenv and getfenv(0) or _G
    local _spoofed = false
    local _ok, _err = pcall(function()
        if type(_ev.type)~="function" then _spoofed=true end
        if type(_ev.pcall)~="function" then _spoofed=true end
        if type(_ev.error)~="function" then _spoofed=true end
        local _t_res = type(%d)
        if _t_res~="number" then _spoofed=true end
    end)
    if _spoofed then
        local _detail="env_spoof"
        %s
    end
end]], k1, ACTION("ENV_SPOOF"))
    end

    local parser = Parser:new({LuaVersion=Enums.LuaVersion.Lua51})
    for i=#blocks,1,-1 do
        local ok, parsed = pcall(function() return parser:parse(blocks[i]) end)
        if ok then
            local ds = parsed.body.statements[1]
            if ds and ds.body then
                ds.body.scope:setParent(ast.body.scope)
                table.insert(ast.body.statements, 1, ds)
            end
        else
            logger:warn("[AnomalyDetector] block "..i.." parse fail")
        end
    end

    logger:info("[AnomalyDetector] injected (safe for Roblox)")
    return ast
end

return AnomalyDetector