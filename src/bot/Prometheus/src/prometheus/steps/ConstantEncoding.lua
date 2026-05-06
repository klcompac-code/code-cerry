local Step     = require("prometheus.step")
local Ast      = require("prometheus.ast")
local Parser   = require("prometheus.parser")
local Enums    = require("prometheus.enums")
local visitast = require("prometheus.visitast")
local AstKind  = Ast.AstKind

local ConstantEncoding = Step:extend()
ConstantEncoding.Description = "3-layer constant encoding: hex->XOR->shift, runtime-only decode"
ConstantEncoding.Name        = "Constant Encoding"
ConstantEncoding.SettingsDescriptor = {
    Threshold      = { type="number",  default=1,   min=0, max=1 },
    EncodeStrings  = { type="boolean", default=true },
    EncodeNumbers  = { type="boolean", default=true },
    EncodeBooleans = { type="boolean", default=true },
}
function ConstantEncoding:init(_) end

local COMPAT_XOR = [[local _cxor=bit32 and bit32.bxor or bit and bit.bxor or function(a,b)
local r,m=0,1;for _=1,24 do;local x,y=a%2,b%2;if x~=y then r=r+m end;a,b,m=(a-x)/2,(b-y)/2,m*2;end;return r;end]]

local function xor8(a,b)
    local r,m=0,1
    for _=1,8 do
        local x,y=a%2,b%2
        if x~=y then r=r+m end
        a,b,m=(a-x)/2,(b-y)/2,m*2
    end
    return r
end

local function encode(val, kind, seed, shift)
    local raw
    if kind=="string" then raw=val
    elseif kind=="number" then raw=string.format("%.17g",val)
    elseif kind=="boolean" then raw=val and "T" or "F"
    else return nil end

    local key=seed%256
    local out={}
    for i=1,#raw do
        local b=string.byte(raw,i)
        local x=xor8(b,key)
        out[i]=string.format("%02x",(x+shift)%256)
        key=(key*31+7)%256
    end
    return table.concat(out)
end

local function genDecoder(seed,shift)
    return string.format([[
do
%s
local _cs,_ck,_cache=%d,%d,{}
local _byte,_char,_tonum=string.byte,string.char,tonumber
function _CE_DECODE(enc,kind)
    local _id=enc..kind
    if _cache[_id] then return _cache[_id] end
    local _key=_cs%%256
    local _raw={}
    for _i=1,#enc,2 do
        local _b=_tonum(enc:sub(_i,_i+1),16)
        local _u=(_b-_ck+256)%%256
        _raw[#_raw+1]=_char(_cxor(_u,_key))
        _key=(_key*31+7)%%256
    end
    local _s=table.concat(_raw)
    local _r
    if kind=="s" then _r=_s
    elseif kind=="n" then _r=_tonum(_s)
    elseif kind=="b" then _r=(_s=="T") end
    _cache[_id]=_r; return _r
end
end]], COMPAT_XOR, seed, shift)
end

function ConstantEncoding:apply(ast, _)
    local seed  = math.random(1,254)
    local shift = math.random(1,127)
    local scope = ast.body.scope
    local decVar = scope:addVariable()

    local ok,parsed = pcall(function()
        return Parser:new({LuaVersion=Enums.LuaVersion.Lua51}):parse(genDecoder(seed,shift))
    end)
    if not ok then return ast end

    local doStat = parsed.body.statements[1]
    doStat.body.scope:setParent(scope)

    visitast(parsed, nil, function(node,data)
        if (node.kind==AstKind.FunctionDeclaration or
            node.kind==AstKind.AssignmentVariable or
            node.kind==AstKind.VariableExpression) then
            if node.scope and node.scope:getVariableName(node.id)=="_CE_DECODE" then
                data.scope:removeReferenceToHigherScope(node.scope,node.id)
                data.scope:addReferenceToHigherScope(scope,decVar)
                node.scope=scope; node.id=decVar
            end
        end
    end)

    table.insert(ast.body.statements,1,doStat)
    table.insert(ast.body.statements,1,
        Ast.LocalVariableDeclaration(scope,{decVar},{}))

    local count=0
    visitast(ast, nil, function(node,data)
        if math.random()>self.Threshold then return end
        local kind,val
        if self.EncodeStrings and node.kind==AstKind.StringExpression then
            if node.value:match("^https?://") then return end
            kind,val="s",node.value
        elseif self.EncodeNumbers and node.kind==AstKind.NumberExpression then
            if type(node.value)~="number" then return end
            kind,val="n",node.value
        elseif self.EncodeBooleans and node.kind==AstKind.BoolExpression then
            kind,val="b",node.value
        end
        if not kind then return end
        local enc=encode(val,kind,seed,shift)
        if not enc then return end
        data.scope:addReferenceToHigherScope(scope,decVar)
        count=count+1
        return Ast.FunctionCallExpression(
            Ast.VariableExpression(scope,decVar),
            {Ast.StringExpression(enc),Ast.StringExpression(kind)}
        )
    end)
    return ast
end

return ConstantEncoding
