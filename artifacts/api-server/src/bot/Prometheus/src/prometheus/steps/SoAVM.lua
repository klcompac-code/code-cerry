local Step   = require("prometheus.step")
local Parser = require("prometheus.parser")
local Enums  = require("prometheus.enums")
local logger = require("logger")

local SoAVM = Step:extend()
SoAVM.Description = "Structure-of-Arrays VM: separates opcode/A/B/C into distinct arrays (Luraph-style)"
SoAVM.Name        = "SoA VM"
SoAVM.SettingsDescriptor = {
    OpcodeCount   = { type="number",  default=20, min=12, max=32 },
    CompressConst = { type="boolean", default=true },
}
function SoAVM:init(_) end

local XOR_COMPAT = [[local _xor=bit32 and bit32.bxor or bit and bit.bxor or function(a,b) local r,m=0,1;for _=1,24 do local x,y=a%2,b%2;if x~=y then r=r+m end;a,b,m=(a-x)/2,(b-y)/2,m*2 end;return r end]]

local ALPHA = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"

local function rname(n)
    n = n or math.random(8, 13)
    local t = { ALPHA:sub(math.random(1,52), math.random(1,52)) }
    if #t[1] == 0 then t[1] = "a" end
    for i = 2, n do
        local idx = math.random(1, 62)
        if idx <= 52 then
            t[i] = ALPHA:sub(idx, idx)
        else
            t[i] = tostring(idx - 53)
        end
    end
    return "_" .. table.concat(t, "")
end

local function mkOpcodes(n)
    local used, ops = {}, {}
    while #ops < n do
        local v = math.random(1, 254)
        if not used[v] then used[v] = true; ops[#ops+1] = v end
    end
    return ops
end

function SoAVM:apply(ast, _)
    local scope = ast.body.scope

    -- Per-build randomized opcodes
    local op  = mkOpcodes(self.OpcodeCount)
    local O   = {}
    local names = {
        "LOAD_K","LOAD_NUM","LOAD_BOOL","LOAD_NIL","LOAD_UPVAL",
        "STORE","MOVE","ADD","SUB","MUL","DIV","MOD","POW","UNM",
        "NOT","LEN","CONCAT","JMP","EQ","LT","LE","CALL","RET"
    }
    for i, nm in ipairs(names) do O[nm] = op[i] or i end

    local opcLines = {}
    -- Numeric indices only - readable opcode names must not appear in output
    local _oi = 0
    for _, v in pairs(O) do
        _oi = _oi + 1
        opcLines[_oi] = string.format("[%d]=%d", _oi, v)
    end

    -- Per-build randomized internal variable names (no hardcoded globals)
    local fnName  = rname()   -- the exec function
    local opcName = rname()   -- the opcode table

    local callErrMsg = "(function(_t,_k) local _r={} for _i=1,#_t do _r[_i]=string.char(_t[_i]+_k) end return table.concat(_r) end)({"
    -- encode "[VM]err" with offset 3
    local errStr = "VM_E"
    local errBytes = {}
    for i = 1, #errStr do errBytes[i] = tostring(string.byte(errStr, i) + 3) end
    local errExpr = string.format(
        "(function(_t,_k) local _r={} for _i=1,#_t do _r[_i]=string.char(_t[_i]-_k) end return table.concat(_r) end)({%s},3)",
        table.concat(errBytes, ","))

    local code = string.format([[
do
%s
local %s={%s}
local function %s(e,u,Y,L,H,upv)
    local _pc=1
    local _stk={}
    local _top=0
    local _floor=math.floor
    local _type=type
    repeat
        local _op=e[_pc]
        local _A=u[_pc]; local _B=Y[_pc]; local _C=L[_pc]
        _pc=_pc+1
        if _op==%d then
            _stk[_A]=H[_B]
        elseif _op==%d then
            _stk[_A]=_B+(_C/1000)
        elseif _op==%d then
            _stk[_A]=(_B==1)
        elseif _op==%d then
            _stk[_A]=nil
        elseif _op==%d then
            _stk[_A]=upv and upv[_B] or nil
        elseif _op==%d then
            if upv then upv[_A]=_stk[_B] end
        elseif _op==%d then
            _stk[_A]=_stk[_B]
        elseif _op==%d then
            _stk[_A]=_stk[_B]+_stk[_C]
        elseif _op==%d then
            _stk[_A]=_stk[_B]-_stk[_C]
        elseif _op==%d then
            _stk[_A]=_stk[_B]*_stk[_C]
        elseif _op==%d then
            _stk[_A]=_stk[_B]/_stk[_C]
        elseif _op==%d then
            _stk[_A]=_stk[_B]%%_stk[_C]
        elseif _op==%d then
            _stk[_A]=_stk[_B]^_stk[_C]
        elseif _op==%d then
            _stk[_A]=-_stk[_B]
        elseif _op==%d then
            _stk[_A]=not _stk[_B]
        elseif _op==%d then
            _stk[_A]=#_stk[_B]
        elseif _op==%d then
            local _t={}
            for _i=_B,_C do _t[#_t+1]=tostring(_stk[_i]) end
            _stk[_A]=table.concat(_t)
        elseif _op==%d then
            _pc=_pc+_B-1
        elseif _op==%d then
            if (_stk[_A]==_stk[_B])==(_C==1) then _pc=_pc+1 end
        elseif _op==%d then
            if (_stk[_A]<_stk[_B])==(_C==1) then _pc=_pc+1 end
        elseif _op==%d then
            if (_stk[_A]<=_stk[_B])==(_C==1) then _pc=_pc+1 end
        elseif _op==%d then
            local _f=_stk[_A]
            local _args={}
            for _i=_A+1,_A+_B do _args[#_args+1]=_stk[_i] end
            local _res={pcall(_f,table.unpack(_args))}
            if _res[1] then
                for _i=2,#_res do _stk[_A+_i-2]=_res[_i] end
            else
                error(%s,2)
            end
        elseif _op==%d then
            local _r={}
            for _i=_A,_A+_B-1 do _r[#_r+1]=_stk[_i] end
            return table.unpack(_r)
        end
    until false
end
_G[%s]=%s
_G[%s]=%s
end]],
        XOR_COMPAT,
        opcName, table.concat(opcLines, ","),
        fnName,
        O.LOAD_K, O.LOAD_NUM, O.LOAD_BOOL, O.LOAD_NIL, O.LOAD_UPVAL,
        O.STORE, O.MOVE,
        O.ADD, O.SUB, O.MUL, O.DIV, O.MOD, O.POW,
        O.UNM, O.NOT, O.LEN, O.CONCAT,
        O.JMP, O.EQ, O.LT, O.LE,
        O.CALL,
        errExpr,
        O.RET,
        -- store into _G with random-string keys (not hardcoded global names)
        string.format("%q", fnName),  fnName,
        string.format("%q", opcName), opcName
    )

    local ok, parsed = pcall(function()
        return Parser:new({ LuaVersion = Enums.LuaVersion.Lua51 }):parse(code)
    end)
    if not ok then logger:warn("[SoAVM] parse fail: " .. tostring(parsed)); return ast end

    local ds = parsed.body.statements[1]
    ds.body.scope:setParent(scope)
    table.insert(ast.body.statements, 1, ds)

    logger:info(string.format("[SoAVM] injected SoA VM, %d opcodes. fn=%s",
        self.OpcodeCount, fnName))
    return ast
end

return SoAVM