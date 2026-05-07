local Step          = require("prometheus.step")
local RandomStrings = require("prometheus.randomStrings")
local Parser        = require("prometheus.parser")
local Enums         = require("prometheus.enums")
local logger        = require("logger")

local AntiTamper = Step:extend()
AntiTamper.Description = "Extended AntiTamper: checksum+dump+logging+print handler+callback+heartbeat"
AntiTamper.Name        = "Anti Tamper"

AntiTamper.SettingsDescriptor = {
    UseChecksumChain  = { type="boolean", default=true  },
    UseSelfRefTrap    = { type="boolean", default=true  },
    UseTimingJunk     = { type="boolean", default=true  },
    UseLogging        = { type="boolean", default=true  },
    UseDumpDiag       = { type="boolean", default=true  },
    UsePrintHandler   = { type="boolean", default=true  },
    UseStackTrace     = { type="boolean", default=true  },
    UseCounterTrap    = { type="boolean", default=true  },
    UseHeartbeat      = { type="boolean", default=false },
    PrintPrefix       = { type="string",  default="" },
    MaxTamperAttempts = { type="number",  default=1, min=1, max=5 },
}

function AntiTamper:init(_) end

-- Random variable name generator (per-build, unguessable)
local function rvar(n)
    local chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"
    n = n or math.random(8, 14)
    local s = {}
    -- first char must be letter
    s[1] = chars:sub(math.random(1, #chars), math.random(1, #chars))
    if #s[1] == 0 then s[1] = "a" end
    for i = 2, n do
        local idx = math.random(1, #chars + 10)
        if idx > #chars then
            s[i] = tostring(math.random(0,9))
        else
            s[i] = chars:sub(idx, idx)
        end
    end
    -- ensure first char is alpha
    local first = chars:sub(math.random(1,52), math.random(1,52))
    if #first < 1 then first = "x" end
    return "_" .. first .. table.concat(s, "")
end

-- For Lua 5.1 compat (no ~ operator), XOR done manually at generator time
local function xorEncodeL51(str)
    local key = math.random(1, 127)
    local bytes = {}
    for i = 1, #str do
        local b = string.byte(str, i)
        -- xor manually
        local xorb = 0
        local a_, b_ = b, key
        local m = 1
        for _ = 1, 8 do
            local xa, xb = a_ % 2, b_ % 2
            if xa ~= xb then xorb = xorb + m end
            a_, b_, m = (a_ - xa) / 2, (b_ - xb) / 2, m * 2
        end
        bytes[i] = tostring(xorb)
    end
    local k2 = tostring(key)
    return string.format(
        [[(function(_t,_k) local _xf=function(a,b) local r,m=0,1 for _=1,8 do local x,y=a%%2,b%%2 if x~=y then r=r+m end a,b,m=(a-x)/2,(b-y)/2,m*2 end return r end local _r={} for _i=1,#_t do _r[_i]=string.char(_xf(_t[_i],_k)) end return table.concat(_r) end)({%s},%s)]],
        table.concat(bytes, ","), k2
    )
end

local ES = xorEncodeL51  -- alias

-- Generate per-build unique names for internal AT globals
local function makeNames()
    return {
        log      = rvar(),
        attempts = rvar(),
        handle   = rvar(),
    }
end

local function genRuntimeCore(settings, names)
    local prefix      = settings.PrintPrefix or ""
    local maxAttempts = settings.MaxTamperAttempts or 1

    local msgExpr     = ES("TAMPER")
    local dumpPfxExpr = ES("D")
    local sumPfxExpr  = ES("S")
    local logPfxExpr  = ES("L")

    local printPart = settings.UsePrintHandler and string.format([[
        local _msg = ("%s:" .. _reason .. "@" .. tostring(_ts))
        pcall(print, _msg)
        pcall(warn, _msg)
    ]], prefix) or "-- print disabled"

    local stackPart = settings.UseStackTrace and [[
        if type(debug) == "table" and type(debug.traceback) == "function" then
            local _tr = debug.traceback("", 2)
            pcall(print, _tr)
        end
    ]] or "-- stack trace disabled"

    local logPart = settings.UseLogging and string.format([[
        %s[#%s+1] = { r=_reason, t=_ts, a=%s }
    ]], names.log, names.log, names.attempts) or ""

    local counterPart = settings.UseCounterTrap and string.format([[
        %s = %s + 1
        if %s < %d then return end
    ]], names.attempts, names.attempts, names.attempts, maxAttempts) or ""

    local dumpPart = settings.UseDumpDiag and string.format([[
        local _diag = {
            r=_reason, t=_ts,
            l=#%s, a=%s,
            d=tostring(type(debug)=="table")
        }
        local _dp={}
        for k,v in pairs(_diag) do _dp[#_dp+1]=k.."="..tostring(v) end
        pcall(print, %s .. table.concat(_dp,"|"))
    ]], names.log, names.attempts, dumpPfxExpr) or ""

    local summaryPart = settings.UseLogging and string.format([[
        pcall(function()
            if not %s then return end
            for _i,_e in ipairs(%s) do
                local _p={}
                for k,v in pairs(_e) do _p[#_p+1]=k.."="..tostring(v) end
                print(%s .. _i .. " " .. table.concat(_p,"|"))
            end
        end)
    ]], names.log, names.log, sumPfxExpr) or ""

    return string.format([[
do
    %s = {}
    %s = 0

    %s = function(_reason)
        local _ts = (pcall(function() return os.clock() end) and os.clock()) or 0

        %s
        %s
        %s
        %s
        %s
        %s

        repeat until false
    end
end
]], names.log, names.attempts,
    names.handle,
    logPart, counterPart, printPart, stackPart, dumpPart, summaryPart)
end

local function genChecksumChain(names)
    local BIG_PRIME = 1000003
    local n = math.random(5, 10)
    local keys = {}
    for i = 1, n do keys[i] = math.random(1000, 99999) end
    local chain = { keys[1] % BIG_PRIME }
    for i = 2, n do
        chain[i] = (chain[i-1] * keys[i] + keys[i] * keys[i]) % BIG_PRIME
    end
    local final = chain[n]
    local failExpr = ES("CK_BAD")
    local okExpr   = ES("CK_OK")

    return string.format([[
do
    local _p    = %d
    local _keys = {%s}
    local _c    = _keys[1] %% _p
    for _i = 2, #_keys do
        _c = (_c * _keys[_i] + _keys[_i]*_keys[_i]) %% _p
    end
    if _c ~= %d then
        %s(_reason or %s)
    else
        if %s then %s[#%s+1] = {r=%s, v=_c} end
    end
end]], BIG_PRIME, table.concat(keys,","), final,
    names.handle, failExpr,
    names.log, names.log, names.log, okExpr)
end

local function genSelfRefTrap(names)
    local magic    = math.random(1000, 9999)
    local failExpr = ES("BC_BAD")
    local okExpr   = ES("BC_OK")
    local infoExpr = ES("BC_I")

    return string.format([[
do
    local _ok1, _d1 = pcall(string.dump, function() return %d end)
    local _ok2, _d2 = pcall(string.dump, function() return %d end)
    if _ok1 and _ok2 then
        local _s1, _s2 = #_d1, #_d2
        if %s then %s[#%s+1] = {s1=_s1,s2=_s2} end
        if _s1 ~= _s2 then
            %s(%s)
        end
    else
        if %s then %s[#%s+1] = {r=%s} end
    end
end]], magic, magic,
    names.log, names.log, names.log,
    names.handle, failExpr,
    names.log, names.log, names.log, infoExpr)
end

local function genTimingJunk(names)
    local v1       = math.random(100, 9999)
    local v2       = math.random(100, 9999)
    local expected = v1 * v2
    local failExpr = ES("PC_BAD")
    local okExpr   = ES("PC_OK")

    return string.format([[
do
    local _results = {}
    for _j = 1, 3 do
        local _ok, _v = pcall(function() return %d * %d end)
        _results[_j] = _ok and _v or nil
    end
    local _consistent = true
    for _j = 2, #_results do
        if _results[_j] ~= _results[1] then _consistent = false; break end
    end
    if not _consistent then
        %s(%s)
    elseif _results[1] ~= %d then
        %s(%s)
    else
        if %s then %s[#%s+1] = {r=%s,v=_results[1]} end
    end
end]], v1, v2,
    names.handle, failExpr,
    expected,
    names.handle, failExpr,
    names.log, names.log, names.log, okExpr)
end

local function genHeartbeat(names)
    local magic    = math.random(1000, 9999)
    local expected = magic * 2 + 1
    local failExpr = ES("HB_BAD")
    local okExpr   = ES("HB_OK")

    return string.format([[
do
    local _hb_magic    = %d
    local _hb_expected = %d
    local _hb_ok = pcall(function()
        if type(task) ~= "table" then return end
        task.spawn(function()
            while true do
                task.wait(math.random(5, 15))
                local _v = _hb_magic * 2 + 1
                if _v ~= _hb_expected then
                    %s(%s)
                end
                if %s then %s[#%s+1] = {r=%s,t=os.clock()} end
            end
        end)
    end)
    if not _hb_ok then
        if %s then %s[#%s+1] = {r=%s} end
    end
end]], magic, expected,
    names.handle, failExpr,
    names.log, names.log, names.log, okExpr,
    names.log, names.log, names.log, ES("HB_SKIP"))
end

function AntiTamper:apply(ast, pipeline)
    if pipeline.PrettyPrint then
        logger:warn('"Anti Tamper" cannot be used with PrettyPrint, ignoring')
        return ast
    end

    local scope  = ast.body.scope
    local parser = Parser:new({ LuaVersion = Enums.LuaVersion.Lua51 })
    local names  = makeNames()  -- fresh random names every build
    local blocks = {}

    blocks[#blocks+1] = genRuntimeCore(self, names)
    if self.UseChecksumChain then blocks[#blocks+1] = genChecksumChain(names) end
    if self.UseSelfRefTrap   then blocks[#blocks+1] = genSelfRefTrap(names)   end
    if self.UseTimingJunk    then blocks[#blocks+1] = genTimingJunk(names)    end
    if self.UseHeartbeat     then blocks[#blocks+1] = genHeartbeat(names)     end

    for i = #blocks, 1, -1 do
        local ok, parsed = pcall(function()
            return parser:parse(blocks[i])
        end)
        if ok and parsed and parsed.body then
            local doStat = parsed.body.statements[1]
            if doStat and doStat.body then
                doStat.body.scope:setParent(scope)
            end
            table.insert(ast.body.statements, 1, doStat)
        else
            logger:warn("AntiTamper: failed to parse block " .. i .. ": " .. tostring(parsed))
        end
    end

    logger:info(string.format("[AntiTamper] injected. log=%s attempts=%s handle=%s",
        names.log, names.attempts, names.handle))
    return ast
end

return AntiTamper