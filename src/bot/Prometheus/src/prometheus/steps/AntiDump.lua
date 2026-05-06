local Step   = require("prometheus.step")
local Parser = require("prometheus.parser")
local Enums  = require("prometheus.enums")
local logger = require("logger")

local AntiDump = Step:extend()
AntiDump.Description = "Detects script dumping/tampering on own VM bytecode"
AntiDump.Name        = "Anti Dump"
AntiDump.SettingsDescriptor = {
    DetectDumper      = { type="boolean", default=true  },
    DetectHookVM      = { type="boolean", default=true  },
    DetectMemoryRead  = { type="boolean", default=true  },
    DetectLoadstring  = { type="boolean", default=true  },
    KickOnDetect      = { type="boolean", default=true  },
    KickMessage       = { type="string",  default="[PROTECTED] Tamper/Dump detected." },
    LogToOutput       = { type="boolean", default=true  },
}

function AntiDump:init(_) end

function AntiDump:apply(ast, pipeline)
    if pipeline.PrettyPrint then return ast end

    local kick  = self.KickMessage:gsub('"','\\"')
    local doLog = self.LogToOutput

    -- [FIX-3] Safe kick action dengan pcall + environment check
    local ACTION = string.format([[
        local _ok, _lp = pcall(function()
            local Players = game and game:GetService("Players")
            if Players then
                return Players.LocalPlayer
            end
            return nil
        end)
        if _ok and _lp then
            if %s then
                pcall(warn, "[ANTIDUMP] " .. (_reason or "tamper") .. ": " .. tostring(_detail or ""))
                pcall(print, "[ANTIDUMP] detected=" .. (_reason or "?"))
            end
            if %s then
                pcall(function() _lp:Kick("%s") end)
            end
        else
            pcall(print, "[ANTIDUMP] cannot kick (no LocalPlayer): " .. (_reason or "unknown"))
        end
    ]], doLog and "true" or "false", 
        self.KickOnDetect and "true" or "false", 
        kick)

    local blocks = {}

    -- 1. Detect script dumper via rawget (safe)
    if self.DetectDumper then
        local magic = math.random(100000,999999)
        local magic2 = magic * 3 + 7
        blocks[#blocks+1] = string.format([[
do
    local _ok, _err = pcall(function()
        local _sentinel=setmetatable({},{
            __index=function(t,k)
                local _reason="DUMP_DETECTED"
                local _detail="sentinel_read:k="..tostring(k)
                %s
            end,
            __newindex=function(t,k,v)
                local _reason="DUMP_WRITE"
                local _detail="sentinel_write:k="..tostring(k)
                %s
            end,
            __metatable="locked_%d"
        })
        local _check=rawget(_sentinel,"_internal_%d")
    end)
end]], ACTION, ACTION, magic, magic2)
    end

    -- 2. Detect VM function hooking
    if self.DetectHookVM then
        local tag = math.random(1000,9999)
        blocks[#blocks+1] = string.format([[
do
    local _hook_detected=false
    local _ok, _err = pcall(function()
        if type(hookfunction)=="function" then _hook_detected=true end
        if type(replaceclosure)=="function" then _hook_detected=true end
    end)
    if _hook_detected then
        local _reason="VM_HOOK_DETECTED"
        local _detail="hookfunction/replaceclosure present"
        %s
    end
end]], ACTION)
    end

    -- 3. Detect memory read (tanpa string.dump)
    -- [FIX-2] Tidak menggunakan string.dump karena tidak ada di Roblox
    if self.DetectMemoryRead then
        blocks[#blocks+1] = string.format([[
do
    local _ok, _err = pcall(function()
        local _env = getfenv and getfenv(0) or _G
        if type(_env.debug) == "table" then
            if type(_env.debug.getregistry) == "function" then
                local _reason="MEMORY_READ_DETECTED"
                local _detail="debug.getregistry accessible"
                %s
            end
        end
    end)
end]], ACTION)
    end

    -- 4. Detect loadstring abuse
    if self.DetectLoadstring then
        local magic = math.random(10000,99999)
        blocks[#blocks+1] = string.format([[
do
    local _ls_orig = loadstring or load
    if type(_ls_orig)=="function" then
        local _test_ok, _test_err = pcall(_ls_orig, "return " .. %d)
        if _test_ok and type(_test_err)=="function" then
            local _r_ok, _r_val = pcall(_test_err)
            if not _r_ok or _r_val ~= %d then
                local _reason="LOADSTRING_TAMPERED"
                local _detail="return value mismatch"
                %s
            end
        end
    end
end]], magic, magic, ACTION)
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
            logger:warn("[AntiDump] block "..i.." parse fail")
        end
    end

    logger:info("[AntiDump] injected anti-dump protection (safe for Roblox)")
    return ast
end

return AntiDump