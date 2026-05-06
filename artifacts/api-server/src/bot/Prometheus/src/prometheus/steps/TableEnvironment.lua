local Step     = require("prometheus.step")
local Ast      = require("prometheus.ast")
local Parser   = require("prometheus.parser")
local Enums    = require("prometheus.enums")
local visitast = require("prometheus.visitast")
local util     = require("prometheus.util")
local logger   = require("logger")
local AstKind  = Ast.AstKind

local TableEnvironment = Step:extend()
TableEnvironment.Description = "Stores functions in table environment with hex+binary mix index"
TableEnvironment.Name        = "Table Environment"
TableEnvironment.SettingsDescriptor = {
    Threshold    = { type="number", default=0.6, min=0, max=1 },
    HexBinaryMix = { type="boolean", default=true },
}
function TableEnvironment:init(_) end

-- [FIX] Implement XOR function yang aman untuk Roblox
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

local function makeHexBinKey()
    local n   = math.random(0x10, 0xFF)
    local hex = string.format("0x%02X", n)
    local styles = {
        hex,
        string.format("%d", n),
        string.format("0x%02x", n),
        (function()
            local a = math.random(0, n)
            local b = n - a
            return string.format("(%d+%d)", a, b)
        end)(),
        string.format("(%d)", n),
        string.format("0x%X", n),
    }
    return styles[math.random(#styles)], n
end

local function buildDispatchTable(funcEntries)
    local lines = {}
    for _, e in ipairs(funcEntries) do
        lines[#lines+1] = string.format("    [%s] = %s", e.keyExpr, e.placeholder)
    end
    return "{\n" .. table.concat(lines, ",\n") .. "\n}"
end

function TableEnvironment:apply(ast, _)
    local scope    = ast.body.scope
    local envVar   = scope:addVariable()
    local dispVar  = scope:addVariable()

    local funcNodes = {}
    visitast(ast, nil, function(node, _)
        if node.kind == AstKind.LocalFunctionDeclaration or
           node.kind == AstKind.FunctionDeclaration then
            if math.random() <= self.Threshold then
                funcNodes[#funcNodes+1] = node
            end
        end
    end)

    if #funcNodes == 0 then return ast end

    local funcKeys = {}
    local usedKeys = {}
    for _, fn in ipairs(funcNodes) do
        local keyExpr, keyNum
        repeat 
            keyExpr, keyNum = makeHexBinKey() 
        until not usedKeys[keyNum]
        usedKeys[keyNum] = true
        funcKeys[#funcKeys+1] = { node=fn, keyExpr=keyExpr, keyNum=keyNum }
    end

    -- [FIX] Gunakan pembungkus pcall untuk keamanan Roblox
    local envTableCode = string.format([[
do
    _ENV_TABLE = {}
    _ENV_DISPATCH = function(k, ...)
        local _f = _ENV_TABLE[k]
        if type(_f) ~= "function" then
            if _f == nil then
                error("[TABLE_ENV] Function not found for key: " .. tostring(k), 2)
            else
                error("[TABLE_ENV] Invalid dispatch key: " .. tostring(k), 2)
            end
        end
        return _f(...)
    end
end]])

    local ok, parsed = pcall(function()
        return Parser:new({ LuaVersion = Enums.LuaVersion.Lua51 }):parse(envTableCode)
    end)
    if not ok then return ast end

    local doStat = parsed.body.statements[1]
    if doStat and doStat.body then
        doStat.body.scope:setParent(scope)
    end

    visitast(parsed, nil, function(node, data)
        for _, name in ipairs({"_ENV_TABLE", "_ENV_DISPATCH"}) do
            local targetVar = (name == "_ENV_TABLE") and envVar or dispVar
            if (node.kind == AstKind.AssignmentVariable or
                node.kind == AstKind.VariableExpression) then
                if node.scope and node.scope:getVariableName(node.id) == name then
                    data.scope:removeReferenceToHigherScope(node.scope, node.id)
                    data.scope:addReferenceToHigherScope(scope, targetVar)
                    node.scope = scope
                    node.id = targetVar
                end
            end
        end
    end)

    table.insert(ast.body.statements, 1, doStat)
    table.insert(ast.body.statements, 1,
        Ast.LocalVariableDeclaration(scope, util.shuffle{envVar, dispVar}, {}))

    local insertions = {}
    for _, fk in ipairs(funcKeys) do
        local fn = fk.node
        local idx = nil
        for i, s in ipairs(ast.body.statements) do
            if s == fn then idx = i; break end
        end
        if idx then
            insertions[#insertions+1] = { after=idx, key=fk }
        end
    end

    table.sort(insertions, function(a,b) return a.after > b.after end)
    
    for _, ins in ipairs(insertions) do
        local fn = ins.key.node
        local keyNum = ins.key.keyNum
        local funcId = fn.id
        local funcScope = fn.scope or scope

        local lhs = Ast.IndexExpression(
            Ast.VariableExpression(scope, envVar),
            Ast.NumberExpression(keyNum)
        )
        local rhs = Ast.VariableExpression(funcScope, funcId)
        local stmt = Ast.AssignmentStatement({ lhs }, { rhs })
        table.insert(ast.body.statements, ins.after + 1, stmt)
    end

    logger:info(string.format("[TableEnvironment] %d functions stored in table env", #funcNodes))
    return ast
end

return TableEnvironment