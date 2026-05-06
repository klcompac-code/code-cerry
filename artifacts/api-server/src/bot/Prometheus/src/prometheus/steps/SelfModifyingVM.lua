local Step   = require("prometheus.step")
local Parser = require("prometheus.parser")
local Enums  = require("prometheus.enums")
local logger = require("logger")

local SelfModifyingVM = Step:extend()
SelfModifyingVM.Description = "VM that mutates its own opcode table each call"
SelfModifyingVM.Name        = "Self Modifying VM"
SelfModifyingVM.SettingsDescriptor = {
    MutationRounds = { type="number", default=3, min=1, max=8 },
}

function SelfModifyingVM:init(_) end

function SelfModifyingVM:apply(ast, _)
    if not ast or not ast.body then return ast end
    
    local scope = ast.body.scope
    local s1 = math.random(1, 60)
    local s2 = math.random(61, 120)
    local s3 = math.random(121, 180)
    local s4 = math.random(181, 240)
    local key = math.random(1, 254)
    local rot = math.random(1, 7)
    local mr = self.MutationRounds or 3

    -- Per-build random name for the exposed VM function
    local _sfx    = tostring(math.random(100000, 999999))
    local nm_SMVM = "_S" .. _sfx .. "v"

    -- Build code manually (no string.format)
    local lines = {
        "do",
        "local _xor=bit32 and bit32.bxor or bit and bit.bxor or function(a,b)",
        "    local r,m=0,1",
        "    for _=1,24 do",
        "        local x,y=a%2,b%2",
        "        if x~=y then r=r+m end",
        "        a,b,m=(a-x)/2,(b-y)/2,m*2",
        "    end",
        "    return r",
        "end",
        "local _so={",
        "    [" .. s1 .. "]=function(r,a,b) return r[a]+r[b] end,",
        "    [" .. s2 .. "]=function(r,a,b) return r[a]-r[b] end,",
        "    [" .. s3 .. "]=function(r,a,b) return r[a]*r[b] end,",
        "    [" .. s4 .. "]=function(r,a,b) return r[a] end,",
        "}",
        "local _sk=" .. key,
        "local _sr=" .. rot,
        "local function _smut()",
        "    local _n={}",
        "    for _k,_f in pairs(_so) do",
        "        local _nk=(_xor(_k,_sk)+_sr)%256",
        "        if _nk==0 then _nk=1 end",
        "        _n[_nk]=_f",
        "        _sk=(_sk*31+7)%256",
        "    end",
        "    _so=_n",
        "end",
        "for _i=1," .. mr .. " do _smut() end",
        "function " .. nm_SMVM .. "(prog,regs)",
        "    regs=regs or {}",
        "    for _i=1,#prog do",
        "        local _ins=prog[_i]",
        "        local _f=_so[_ins[1]]",
        "        if _f then",
        "            regs[_ins[4] or 1]=_f(regs,_ins[2] or 1,_ins[3] or 1)",
        "        end",
        "    end",
        "    return regs",
        "end",
        "end",
    }

    local code = table.concat(lines, "\n")

    local ok, parsed = pcall(function()
        return Parser:new({ LuaVersion = Enums.LuaVersion.Lua51 }):parse(code)
    end)
    
    if not ok then
        logger:warn("[SelfModVM] parse failed: " .. tostring(parsed))
        return ast
    end

    local ds = parsed.body.statements[1]
    if ds and ds.body then
        ds.body.scope:setParent(scope)
    end
    table.insert(ast.body.statements, 1, ds)
    
    logger:info(string.format("[SelfModVM] key=%d rounds=%d", key, mr))
    return ast
end

return SelfModifyingVM