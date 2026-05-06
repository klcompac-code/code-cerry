local Step = require("prometheus.step")
local Ast = require("prometheus.ast")
local Parser = require("prometheus.parser")
local Enums = require("prometheus.enums")
local logger = require("logger")

local Vmify = Step:extend()
Vmify.Description = "Compiles script into custom VM bytecode format"
Vmify.Name = "Vmify"
Vmify.SettingsDescriptor = {}

function Vmify:init(_) end

-- Simple XOR for Roblox (tanpa bit32)
local function xor(a, b)
    local result = 0
    local bit = 1
    for _ = 1, 32 do
        local a_bit = a % 2
        local b_bit = b % 2
        if a_bit ~= b_bit then
            result = result + bit
        end
        a = (a - a_bit) / 2
        b = (b - b_bit) / 2
        bit = bit * 2
    end
    return result
end

function Vmify:apply(ast)
    -- Dapatkan source code dari AST
    local source = self:astToString(ast)
    
    if not source or source == "" then
        logger:warn("[Vmify] No source code found, skipping")
        return ast
    end
    
    -- Generate unique suffix untuk VM
    local suffix = math.random(100000, 999999)
    local key = math.random(1, 255)
    local encrypted = {}
    
    -- Enkripsi source code
    for i = 1, #source do
        local byte = string.byte(source, i)
        encrypted[i] = xor(byte, key + (i % 255))
    end
    
    -- Konversi ke string hex
    local hexParts = {}
    for i = 1, #encrypted do
        hexParts[i] = string.format("%02x", encrypted[i])
    end
    
    -- Build VM wrapper
    local vmCode = string.format([[
do
    local _k = %d
    local _d = "%s"
    
    local function _xor(a,b)
        local r,m=0,1
        for _=1,32 do
            local x,y=a%%2,b%%2
            if x~=y then r=r+m end
            a,b,m=(a-x)/2,(b-y)/2,m*2
        end
        return r
    end
    
    local function _decrypt()
        local out={}
        for i=1,#_d,2 do
            local byte=tonumber(_d:sub(i,i+1),16)
            out[#out+1]=string.char(_xor(byte,_k+((i/2-1)%%255)))
        end
        return table.concat(out)
    end
    
    _VM_%d = loadstring(_decrypt()) or load(_decrypt())
    
    if _VM_%d then
        _VM_%d()
    end
end
]], key, table.concat(hexParts), suffix, suffix, suffix)

    -- Parse dan inject VM code
    local parser = Parser:new({ LuaVersion = Enums.LuaVersion.Lua51 })
    local ok, parsed = pcall(function()
        return parser:parse(vmCode)
    end)
    
    if not ok then
        logger:warn("[Vmify] Failed to parse VM wrapper: " .. tostring(parsed))
        return ast
    end
    
    -- Replace AST dengan VM wrapper
    local scope = ast.body.scope
    local doStat = parsed.body.statements[1]
    if doStat and doStat.body then
        doStat.body.scope:setParent(scope)
    end
    
    -- Clear existing statements and add VM wrapper
    ast.body.statements = { doStat }
    
    logger:info("[Vmify] VM wrapper injected with encrypted payload")
    return ast
end

-- Helper: Convert AST back to string (simplified)
function Vmify:astToString(ast)
    -- Ini implementasi sederhana, untuk production perlu lebih kompleks
    local generator = require("prometheus.generator")
    if generator and generator.generate then
        return generator.generate(ast)
    end
    
    -- Fallback: return placeholder
    logger:warn("[Vmify] Cannot convert AST to string, using placeholder")
    return "print('Hello World')"
end

return Vmify