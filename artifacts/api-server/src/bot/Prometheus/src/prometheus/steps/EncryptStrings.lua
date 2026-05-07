local Step     = require("prometheus.step")
local Ast      = require("prometheus.ast")
local Parser   = require("prometheus.parser")
local Enums    = require("prometheus.enums")
local visitast = require("prometheus.visitast")
local util     = require("prometheus.util")
local AstKind  = Ast.AstKind

local EncryptStrings = Step:extend()
EncryptStrings.Description = "RC4-inspired KSA+PRGA 4-layer string encryption"
EncryptStrings.Name        = "Encrypt Strings"
EncryptStrings.SettingsDescriptor = {}
function EncryptStrings:init(_) end

local COMPAT_XOR = [[
local _xor=bit32 and bit32.bxor or bit and bit.bxor or function(a,b)
    local r,m=0,1
    for _=1,24 do
        local x,y=a%2,b%2
        if x~=y then r=r+m end
        a,b,m=(a-x)/2,(b-y)/2,m*2
    end
    return r
end]]

function EncryptStrings:CreateEncryptionService()
    local usedSeeds = {}
    local MA = math.random(3,251); if MA%2==0 then MA=MA+1 end
    local MB = math.random(1,127)*2+1
    local RK = math.random(1,7)
    local XM = math.random(1,255)

    local function buildSbox(seed)
        local s,j,k,lcg={},0,{},seed
        for i=0,255 do s[i]=i end
        for i=0,255 do lcg=(lcg*MA+MB)%65536; k[i]=lcg%256 end
        for i=0,255 do j=(j+s[i]+k[i])%256; s[i],s[j]=s[j],s[i] end
        return s
    end

    local function makeStream(s)
        local i,j=0,0
        return function()
            i=(i+1)%256; j=(j+s[i])%256; s[i],s[j]=s[j],s[i]
            return s[(s[i]+s[j])%256]
        end
    end

    local function rotL(b,n)
        n=n%8; return ((b*(2^n))%256)+math.floor(b/(2^(8-n)))
    end

    local function xor8(a,b)
        local r,m=0,1
        for _=1,8 do
            local x,y=a%2,b%2
            if x~=y then r=r+m end
            a,b,m=(a-x)/2,(b-y)/2,m*2
        end
        return r
    end

    local function encrypt(str)
        local seed
        repeat seed=math.random(1,65534) until not usedSeeds[seed]
        usedSeeds[seed]=true
        local sbox=buildSbox(seed)
        local stream=makeStream(sbox)
        local out,prev={},seed%256
        for i=1,#str do
            local b=string.byte(str,i)
            local ks=stream()
            local c=rotL(xor8(xor8(b,ks),prev)%256,RK)
            c=c%256
            out[i]=string.char(c)
            prev=c
        end
        return table.concat(out),seed
    end

    local function genCode()
        return string.format([[
do
%s
local _ma,_mb,_rk=%d,%d,%d
local _cache,_byte,_char,_floor={},string.byte,string.char,math.floor
local function _rot(b,n) n=n%%8; return (b*(2^n))%%256+_floor(b/(2^(8-n))) end
local function _ksa(seed)
    local s,j,k,lcg={},0,{},seed
    for i=0,255 do s[i]=i end
    for i=0,255 do lcg=(lcg*_ma+_mb)%%65536; k[i]=lcg%%256 end
    for i=0,255 do j=(j+s[i]+k[i])%%256; s[i],s[j]=s[j],s[i] end
    return s
end
local function _prga(s)
    local i,j=0,0
    return function()
        i=(i+1)%%256; j=(j+s[i])%%256; s[i],s[j]=s[j],s[i]
        return s[(_xor(s[i],0)+s[j])%%256]
    end
end
function DECRYPT(ct,seed)
    if _cache[seed] then return _cache[seed] end
    local stream,prev,out=_prga(_ksa(seed)),seed%%256,{}
    for i=1,#ct do
        local c=_byte(ct,i)
        local tmp=_rot(c,8-_rk)%%256
        out[i]=_char(_xor(_xor(tmp,stream()),prev)%%256)
        prev=c
    end
    _cache[seed]=table.concat(out); return _cache[seed]
end
STRINGS=setmetatable({},{__index=_cache,__metatable=nil})
end]], COMPAT_XOR, MA, MB, RK)
    end

    return { encrypt=encrypt, genCode=genCode }
end

function EncryptStrings:apply(ast, _)
    local Enc    = self:CreateEncryptionService()
    local code   = Enc.genCode()
    local newAst = Parser:new({LuaVersion=Enums.LuaVersion.Lua51}):parse(code)
    local doStat = newAst.body.statements[1]
    local scope  = ast.body.scope
    local dVar   = scope:addVariable()
    local sVar   = scope:addVariable()
    doStat.body.scope:setParent(scope)

    visitast(newAst, nil, function(node, data)
        local function remap(name, target)
            if (node.kind==AstKind.FunctionDeclaration or
                node.kind==AstKind.AssignmentVariable or
                node.kind==AstKind.VariableExpression) then
                if node.scope and node.scope:getVariableName(node.id)==name then
                    data.scope:removeReferenceToHigherScope(node.scope,node.id)
                    data.scope:addReferenceToHigherScope(scope,target)
                    node.scope=scope; node.id=target
                end
            end
        end
        remap("DECRYPT",dVar); remap("STRINGS",sVar)
    end)

    visitast(ast, nil, function(node, data)
        if node.kind~=AstKind.StringExpression then return end
        data.scope:addReferenceToHigherScope(scope,sVar)
        data.scope:addReferenceToHigherScope(scope,dVar)
        local enc,seed=Enc.encrypt(node.value)
        return Ast.IndexExpression(
            Ast.VariableExpression(scope,sVar),
            Ast.FunctionCallExpression(
                Ast.VariableExpression(scope,dVar),
                {Ast.StringExpression(enc),Ast.NumberExpression(seed)}
            )
        )
    end)

    table.insert(ast.body.statements,1,doStat)
    table.insert(ast.body.statements,1,
        Ast.LocalVariableDeclaration(scope,util.shuffle{dVar,sVar},{}))
    return ast
end

return EncryptStrings
