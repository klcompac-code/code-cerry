local Step   = require("prometheus.step")
local Parser = require("prometheus.parser")
local Enums  = require("prometheus.enums")
local logger = require("logger")

local DynamicOpcodeEncryption = Step:extend()
DynamicOpcodeEncryption.Description = "Opcodes encrypted with rotating key every N instructions"
DynamicOpcodeEncryption.Name        = "Dynamic Opcode Encryption"
DynamicOpcodeEncryption.SettingsDescriptor = {
    RotateEvery = { type="number", default=4, min=1, max=16 },
}
function DynamicOpcodeEncryption:init(_) end

function DynamicOpcodeEncryption:apply(ast, _)
    local scope    = ast.body.scope
    local initKey  = math.random(1,254)
    -- Per-build random names for exposed globals
    local _sfx      = tostring(math.random(100000, 999999))
    local nm_DOE_DEC = "_D" .. _sfx .. "d"
    local nm_DOE_ENC = "_D" .. _sfx .. "e"
    local nm_DOE_KEY = "_D" .. _sfx .. "k"
    local rotEvery = self.RotateEvery
    local mul      = math.random(3,37)*2+1
    local add      = math.random(1,63)*2+1

    -- Opcode count only - no readable name strings in output
    local _opcCount = 12
    local key   = initKey
    local opcPairs = {}
    for i = 1, _opcCount do
        local enc = (i + key) % 256
        if enc == 0 then enc = 1 end
        opcPairs[#opcPairs + 1] = "[" .. enc .. "]=" .. enc
        key = (key * mul + add) % 256
    end

    local code = [[
do
local _xor=bit32 and bit32.bxor or bit and bit.bxor or function(a,b)
    local r,m=0,1
    for _=1,24 do
        local x,y=a%2,b%2
        if x~=y then r=r+m end
        a,b,m=(a-x)/2,(b-y)/2,m*2
    end
    return r
end
local _dk,_dm,_da,_dr,_dc = ]] .. initKey .. "," .. mul .. "," .. add .. "," .. rotEvery .. ",0\n"
    
    code = code .. "local _do={" .. table.concat(opcPairs, ",") .. "}\n"
    
    code = code .. "local function _rot() _dk=(_dk*_dm+_da)%256 if _dk==0 then _dk=1 end end\n"
    code = code .. "function " .. nm_DOE_DEC .. "(op)\n"
    code = code .. "    _dc=_dc+1 if _dc%_dr==0 then _rot() end\n"
    code = code .. "    return _xor((_do[op] or op),_dk)\n"
    code = code .. "end\n"
    code = code .. "function " .. nm_DOE_ENC .. "(op)\n"
    code = code .. "    _dc=_dc+1 if _dc%_dr==0 then _rot() end\n"
    code = code .. "    return _xor(op,_dk)\n"
    code = code .. "end\n"
    code = code .. nm_DOE_KEY .. "=function() return _dk end\n"
    code = code .. "end\n"

    local ok, parsed = pcall(function()
        return Parser:new({ LuaVersion = Enums.LuaVersion.Lua51 }):parse(code)
    end)
    if not ok then
        logger:warn("[DynOpcEnc] parse fail: " .. tostring(parsed))
        return ast
    end
    
    local doStat = parsed.body.statements[1]
    if doStat and doStat.body then
        doStat.body.scope:setParent(scope)
    end
    table.insert(ast.body.statements, 1, doStat)
    
    logger:info(string.format("[DynOpcEnc] key=%d mul=%d add=%d rot=%d", initKey, mul, add, rotEvery))
    return ast
end

return DynamicOpcodeEncryption