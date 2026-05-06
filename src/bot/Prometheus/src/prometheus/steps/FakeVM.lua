local Step   = require("prometheus.step")
local Parser = require("prometheus.parser")
local Enums  = require("prometheus.enums")
local logger = require("logger")

local FakeVM = Step:extend()
FakeVM.Description = "Injects decoy VM that runs but produces nothing useful"
FakeVM.Name        = "Fake VM"
FakeVM.SettingsDescriptor = {
    DecoyCount = { type="number", default=2, min=1, max=5 },
}
function FakeVM:init(_) 
    math.randomseed(os.time())
    for _ = 1, math.random(10, 50) do math.random() end
end

-- [FIX] Safe random hex generator
local function randomHex(n)
    n = n or 8
    local t = {}
    local hexChars = "0123456789abcdef"
    for i = 1, n do 
        t[i] = hexChars:sub(math.random(1, 16), math.random(1, 16))
    end
    return table.concat(t)
end

-- [FIX] Safe fake VM code builder (tanpa karakter berbahaya)
local function buildFakeVM(seed, noise, op1, op2, op3, op4, tv)
    return string.format([[
do
    local _xor = bit32 and bit32.bxor or bit and bit.bxor or function(a,b)
        local r,m = 0,1
        for _=1,24 do
            local x,y = a%%2, b%%2
            if x~=y then r = r + m end
            a,b,m = (a-x)/2, (b-y)/2, m*2
        end
        return r
    end
    local %s = nil
    local _fo = {[%d]=1, [%d]=2, [%d]=3, [%d]=4}
    local _fb = "%s"
    local _fs = %d
    local _fr = {}
    for _i=1,#_fb,2 do
        local _b = tonumber(_fb:sub(_i,_i+1), 16) or 0
        local _oid = _xor(_b, _fs) %% 256
        if _fo[_oid] then
            _fr[#_fr+1] = _fo[_oid]
        end
        _fs = (_fs * 31 + _b) %% 256
    end
    %s = {_r=_fr, _s=_fs, _n=%d}
end
]], tv, op1, op2, op3, op4, noise, seed, tv, seed)
end

function FakeVM:apply(ast, _)
    if not ast or not ast.body then return ast end
    
    local scope = ast.body.scope
    local parser = Parser:new({ LuaVersion = Enums.LuaVersion.Lua51 })
    local inserted = 0
    
    for d = 1, self.DecoyCount do
        -- Generate unique values for each decoy
        local op1 = math.random(1, 63)
        local op2 = math.random(64, 127)
        local op3 = math.random(128, 191)
        local op4 = math.random(192, 254)
        local seed = math.random(1000, 9999)
        local noise = randomHex(math.random(4, 12))
        local tv = "_fv" .. math.random(10000, 99999)
        
        local code = buildFakeVM(seed, noise, op1, op2, op3, op4, tv)
        
        local ok, parsed = pcall(function()
            return parser:parse(code)
        end)
        
        if ok and parsed and parsed.body then
            local doStat = parsed.body.statements[1]
            if doStat and doStat.body and doStat.body.scope then
                doStat.body.scope:setParent(scope)
                -- Insert at random position
                local pos = math.min(d, #ast.body.statements + 1)
                table.insert(ast.body.statements, pos, doStat)
                inserted = inserted + 1
            end
        else
            logger:warn(string.format("[FakeVM] Failed to inject decoy %d: %s", d, tostring(parsed)))
        end
    end
    
    logger:info(string.format("[FakeVM] Injected %d/%d decoy VMs", inserted, self.DecoyCount))
    return ast
end

return FakeVM