local Step   = require("prometheus.step")
local Parser = require("prometheus.parser")
local Enums  = require("prometheus.enums")
local logger = require("logger")

local RegisterVM = Step:extend()
RegisterVM.Description = "Register-based VM with instruction fusion and per-build opcode shuffle"
RegisterVM.Name        = "Register VM"
RegisterVM.SettingsDescriptor = {
    OpcodeCount = { type="number", default=24, min=16, max=32 },
    FuseOps     = { type="boolean", default=true },
}
function RegisterVM:init(_) end

local XOR_COMPAT = [[local _rxor=bit32 and bit32.bxor or bit and bit.bxor or function(a,b) local r,m=0,1;for _=1,24 do local x,y=a%2,b%2;if x~=y then r=r+m end;a,b,m=(a-x)/2,(b-y)/2,m*2 end;return r end]]

local function mkOps(n)
    local used,t={},{}
    while #t<n do
        local v=math.random(1,253)
        if not used[v] then used[v]=true;t[#t+1]=v end
    end
    return t
end

function RegisterVM:apply(ast, _)
    local scope = ast.body.scope
    local ops   = mkOps(self.OpcodeCount)
    -- Per-build random names for exposed globals
    local _sfx         = tostring(math.random(100000, 999999))
    local nm_RVM_RUN     = "_R" .. _sfx .. "r"
    local nm_RVM_OPCODES = "_R" .. _sfx .. "o"
    local O     = {}
    local names = {
        "LD_K","LD_N","LD_B","LD_NIL","LD_G","ST_G",
        "MOV","ADD","SUB","MUL","DIV","MOD","POW","UNM",
        "NOT","LEN","CONCAT","EQ","LT","LE",
        "JMP","JT","JF","CALL","TCALL","RET","SETLIST",
        "ADD_K","SUB_K","MUL_K",
    }
    for i,nm in ipairs(names) do O[nm]=ops[i] or i end

    local olines={}
    -- Use numeric indices only - no readable opcode name strings in output
    local _oi=0
    for _,v in pairs(O) do
        _oi=_oi+1
        olines[_oi]=string.format("[%d]=%d",_oi,v)
    end

    local fuse = self.FuseOps

    local code = string.format([[
do
%s
local _RVOPC={%s}
local _RV_FUSE=%s
local function _RV_RUN(instructions, consts, upvals, env)
    local _R={}
    local _pc=1
    local _N=#instructions
    while _pc<=_N do
        local _ins=instructions[_pc]
        local _op=_ins[1]; local _A=_ins[2]; local _B=_ins[3]; local _C=_ins[4]
        _pc=_pc+1
        if _op==%d then
            _R[_A]=consts[_B]
        elseif _op==%d then
            _R[_A]=_B+(_C or 0)/1e6
        elseif _op==%d then
            _R[_A]=(_B~=0)
        elseif _op==%d then
            for _i=_A,_A+(_B or 0) do _R[_i]=nil end
        elseif _op==%d then
            _R[_A]=env[consts[_B] or ""]
        elseif _op==%d then
            env[consts[_A] or ""]=_R[_B]
        elseif _op==%d then
            _R[_A]=_R[_B]
        elseif _op==%d then
            _R[_A]=_R[_B]+_R[_C]
        elseif _op==%d then
            _R[_A]=_R[_B]-_R[_C]
        elseif _op==%d then
            _R[_A]=_R[_B]*_R[_C]
        elseif _op==%d then
            _R[_A]=_R[_B]/_R[_C]
        elseif _op==%d then
            _R[_A]=_R[_B]%%_R[_C]
        elseif _op==%d then
            _R[_A]=_R[_B]^_R[_C]
        elseif _op==%d then
            _R[_A]=-_R[_B]
        elseif _op==%d then
            _R[_A]=not _R[_B]
        elseif _op==%d then
            _R[_A]=#_R[_B]
        elseif _op==%d then
            local _parts={}
            for _i=_B,_C do _parts[#_parts+1]=tostring(_R[_i]) end
            _R[_A]=table.concat(_parts)
        elseif _op==%d then
            if _R[_A]==_R[_B] then _pc=_pc+_C end
        elseif _op==%d then
            if _R[_A]<_R[_B] then _pc=_pc+_C end
        elseif _op==%d then
            if _R[_A]<=_R[_B] then _pc=_pc+_C end
        elseif _op==%d then
            _pc=_pc+_A-1
        elseif _op==%d then
            if _R[_A] then _pc=_pc+_B end
        elseif _op==%d then
            if not _R[_A] then _pc=_pc+_B end
        elseif _op==%d then
            local _fn=_R[_A]
            local _args={}
            for _i=_A+1,_A+_B do _args[#_args+1]=_R[_i] end
            local _res={pcall(_fn,table.unpack(_args))}
            if not _res[1] then
                error("[RVM] runtime error: "..tostring(_res[2]),2)
            end
            for _i=2,#_res do _R[_A+_i-2]=_res[_i] end
        elseif _op==%d then
            local _fn=_R[_A]
            local _args={}
            for _i=_A+1,_N do _args[#_args+1]=_R[_i] end
            return _fn(table.unpack(_args))
        elseif _op==%d then
            local _rets={}
            for _i=_A,_A+_B-1 do _rets[#_rets+1]=_R[_i] end
            return table.unpack(_rets)
        elseif _op==%d then
            local _tbl=_R[_A]
            for _i=1,_B do _tbl[_i]=_R[_A+_i] end
        elseif _RV_FUSE and _op==%d then
            _R[_A]=_R[_B]+consts[_C]
        elseif _RV_FUSE and _op==%d then
            _R[_A]=_R[_B]-consts[_C]
        elseif _RV_FUSE and _op==%d then
            _R[_A]=_R[_B]*consts[_C]
        end
    end
end
%s=_RV_RUN
%s=_RVOPC
end]],
        XOR_COMPAT,
        table.concat(olines,","),
        fuse and "true" or "false",
        O.LD_K, O.LD_N, O.LD_B, O.LD_NIL,
        O.LD_G, O.ST_G, O.MOV,
        O.ADD, O.SUB, O.MUL, O.DIV, O.MOD, O.POW,
        O.UNM, O.NOT, O.LEN, O.CONCAT,
        O.EQ, O.LT, O.LE,
        O.JMP, O.JT, O.JF,
        O.CALL, O.TCALL, O.RET, O.SETLIST,
        O.ADD_K, O.SUB_K, O.MUL_K,
        nm_RVM_RUN, nm_RVM_OPCODES
    )

    local ok,parsed=pcall(function()
        return Parser:new({LuaVersion=Enums.LuaVersion.Lua51}):parse(code)
    end)
    if not ok then logger:warn("[RegisterVM] parse fail: "..tostring(parsed)); return ast end

    local ds=parsed.body.statements[1]
    ds.body.scope:setParent(scope)
    table.insert(ast.body.statements,1,ds)

    logger:info(string.format("[RegisterVM] injected, %d opcodes, fuse=%s. LD_K=%d ADD=%d RET=%d",
        self.OpcodeCount, tostring(fuse), O.LD_K, O.ADD, O.RET))
    return ast
end

return RegisterVM
