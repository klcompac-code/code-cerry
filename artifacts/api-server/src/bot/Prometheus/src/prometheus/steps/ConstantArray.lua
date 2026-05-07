local Step     = require("prometheus.step")
local Ast      = require("prometheus.ast")
local visitast = require("prometheus.visitast")
local util     = require("prometheus.util")
local Parser   = require("prometheus.parser")
local enums    = require("prometheus.enums")
local logger   = require("logger")

local LuaVersion = enums.LuaVersion
local AstKind    = Ast.AstKind

local ConstantArray = Step:extend()
ConstantArray.Description = "Custom: dual-layer array with XOR index scramble and dead entries"
ConstantArray.Name        = "Constant Array"

ConstantArray.SettingsDescriptor = {
    Threshold = { name="Threshold", type="number", default=1, min=0, max=1 },
    StringsOnly = { name="StringsOnly", type="boolean", default=false },
    DeadEntryRatio = { name="DeadEntryRatio", type="number", default=0.15, min=0, max=0.4 },
}

function ConstantArray:init(settings) end

local function randomString(len)
    len = len or math.random(8, 24)
    local chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
    local result = {}
    for i = 1, len do
        result[i] = chars:sub(math.random(1, #chars), math.random(1, #chars))
    end
    return table.concat(result)
end

local function randomVarName()
    return "_" .. randomString(math.random(12, 32))
end

local function buildEncryptedString(str)
    local key = math.random(1, 255)
    local encrypted = {}
    for i = 1, #str do
        encrypted[i] = string.byte(str, i) - key
    end
    local tbl = table.concat(encrypted, ",")
    return string.format("(function(k)local r={%s}local d=''for i=1,#r do d=d..string.char(r[i]+k)end return d end)(%d)", tbl, key)
end

local function createBooleanLiteral(value)
    if Ast.BooleanLiteral then
        return Ast.BooleanLiteral(value)
    elseif Ast.BoolLiteral then
        return Ast.BoolLiteral(value)
    elseif Ast.BooleanExpression then
        return Ast.BooleanExpression(value)
    end
    return nil
end

local function createTableEntry(valueNode)
    if Ast.TableEntry then
        return Ast.TableEntry(valueNode)
    elseif Ast.TableConstructorEntry then
        return Ast.TableConstructorEntry(valueNode)
    end
    return valueNode
end

local falseCache = nil
local function getFalseNode()
    if not falseCache then
        falseCache = createBooleanLiteral(false)
    end
    return falseCache
end

local function xor32(a, b)
    local r, m = 0, 1
    local iter = math.random(16, 32)
    for _ = 1, iter do
        local x, y = a % 2, b % 2
        if x ~= y then r = r + m end
        a = math.floor((a - x) / 2)
        b = math.floor((b - y) / 2)
        m = m * 2
    end
    return r
end

local function collectConstants(ast, stringsOnly, threshold)
    local constants = {}
    local nodeToConst = {}
    local StringKind = AstKind.StringExpression
    local NumberKind = AstKind.NumberExpression
    local count = 0
    
    visitast(ast, nil, function(node, _)
        if not node then return end
        local collect = false
        local val = nil
        if node.kind == StringKind then
            if math.random() <= threshold then
                collect = true
                val = node.value
            end
        elseif not stringsOnly and node.kind == NumberKind then
            local v = node.value
            if type(v) == "number" and v == math.floor(v) and v >= 0 and v < 16777216 then
                if math.random() <= threshold then
                    collect = true
                    val = v
                end
            end
        end
        if collect then
            count = count + 1
            constants[count] = { value = val, kind = (node.kind == StringKind and "string" or "number"), node = node }
            nodeToConst[node] = count
        end
    end)
    
    return constants, nodeToConst
end

function ConstantArray:apply(ast, pipeline)
    if not ast or not ast.body then return ast end
    
    local scope = ast.body.scope
    local globalScope = ast.globalScope or scope
    
    local arrAName = randomVarName()
    local arrBName = randomVarName()
    local getterName = randomVarName()
    
    local gStr = buildEncryptedString("_G")
    local getterStr = buildEncryptedString(getterName)
    
    local constants, nodeToConst = collectConstants(ast, self.StringsOnly, self.Threshold)
    if #constants == 0 then return ast end

    local MAGIC = math.random(1, 255)
    local deadCount = math.max(1, math.floor(#constants * (self.DeadEntryRatio or 0.15)))
    local totalSlots = #constants + deadCount
    
    local slots = {}
    for i = 1, totalSlots do slots[i] = i end
    util.shuffle(slots)
    
    local arrA = {}
    local arrB = {}
    local constToSlot = {}
    
    for i = 1, #constants do
        local scrambled = xor32(i - 1, MAGIC)
        local slot = slots[i]
        if scrambled % 2 == 0 then
            arrA[slot] = constants[i]
        else
            arrB[slot] = constants[i]
        end
        constToSlot[i] = { scrambled = scrambled, slot = slot }
    end
    
    local function randomDeadString()
        local chars = "qwertyuiopasdfghjklzxcvbnmQWERTYUIOPASDFGHJKLZXCVBNM1234567890"
        local len = math.random(6, 20)
        local t = {}
        for _ = 1, len do
            t[_] = chars:sub(math.random(1, #chars), math.random(1, #chars))
        end
        return table.concat(t)
    end
    
    for i = #constants + 1, totalSlots do
        local slot = slots[i]
        if math.random(2) == 1 then
            arrA[slot] = { value = randomDeadString(), kind = "string" }
        else
            arrB[slot] = { value = math.random(-9999, 9999), kind = "number" }
        end
    end
    
    local arrAVar = scope:addVariable()
    local arrBVar = scope:addVariable()
    
    local function buildTableNode(arr, maxSlot)
        local entries = {}
        local falseNode = getFalseNode()
        for slot = 1, maxSlot do
            local entry = arr[slot]
            if entry then
                local valNode
                if entry.kind == "string" then
                    valNode = Ast.StringExpression(entry.value)
                else
                    valNode = Ast.NumberExpression(entry.value)
                end
                entries[#entries + 1] = createTableEntry(valNode)
            else
                entries[#entries + 1] = createTableEntry(falseNode)
            end
        end
        return Ast.TableConstructorExpression(entries)
    end
    
    local tableANode = buildTableNode(arrA, totalSlots)
    local tableBNode = buildTableNode(arrB, totalSlots)
    
    local iterCount = math.random(16, 32)
    
    -- Build getter code
    local getterLines = {
        "do",
        "    local " .. arrAName .. " = ...",
        "    local " .. arrBName .. " = ...",
        "    local function " .. getterName .. "(idx)",
        "        local a,b = idx," .. MAGIC,
        "        local r,m = 0,1",
        "        for _=1," .. iterCount .. " do",
        "            local x,y = a % 2, b % 2",
        "            if x~=y then r=r+m end",
        "            a,b,m = math.floor((a-x)/2),math.floor((b-y)/2),m*2",
        "        end",
        "        local real = r + 1",
        "        if idx % 2 == 0 then",
        "            return " .. arrAName .. "[real]",
        "        else",
        "            return " .. arrBName .. "[real]",
        "        end",
        "    end",
        "    _G[" .. getterStr .. "] = " .. getterName,
        "end",
    }
    
    local getterCode = table.concat(getterLines, "\n")
    
    local getterParsed = Parser:new({ LuaVersion = LuaVersion.Lua51 }):parse(getterCode)
    if not getterParsed or not getterParsed.body then
        logger:warn("[ConstantArray] Failed to parse getter")
        return ast
    end
    
    local declAB = Ast.LocalVariableDeclaration(scope, { arrAVar, arrBVar }, { tableANode, tableBNode })
    table.insert(ast.body.statements, 1, declAB)
    
    local getterBlock = getterParsed.body.statements[1]
    if getterBlock and getterBlock.body then
        getterBlock.body.scope:setParent(scope)
        
        local stack = { getterBlock }
        local visited = {}
        while #stack > 0 do
            local node = table.remove(stack)
            if node and not visited[node] then
                visited[node] = true
                if node.kind == AstKind.VariableExpression then
                    if node.scope then
                        local name = node.scope:getVariableName(node.id)
                        if name == arrAName then
                            node.scope = scope
                            node.id = arrAVar
                        elseif name == arrBName then
                            node.scope = scope
                            node.id = arrBVar
                        end
                    end
                end
                for _, child in pairs(node) do
                    if type(child) == "table" then
                        stack[#stack + 1] = child
                    end
                end
            end
        end
        table.insert(ast.body.statements, 1, getterBlock)
    end
    
    -- ============================================================
    -- FIX: SAFE REPLACEMENT - use direct _G access
    -- ============================================================
    local replacements = {}
    local replaceStack = { ast }
    local replaceVisited = {}
    
    while #replaceStack > 0 do
        local node = table.remove(replaceStack)
        if node and not replaceVisited[node] then
            replaceVisited[node] = true
            local constIdx = nodeToConst[node]
            if constIdx and constIdx <= #constants then
                local info = constToSlot[constIdx]
                if info then
                    -- Build: _G[getterName](scrambled) using simple access
                    local getterKeyNode = Ast.StringExpression(getterName)
                    -- Use raw _G access without IndexExpression (safer)
                    local gVar = Ast.VariableExpression(globalScope, "_G")
                    local getterNode = Ast.IndexExpression(gVar, getterKeyNode)
                    local argNode = Ast.NumberExpression(info.scrambled)
                    local callNode = Ast.FunctionCallExpression(getterNode, { argNode })
                    replacements[node] = callNode
                end
            end
            for key, child in pairs(node) do
                if type(child) == "table" and key ~= "scope" and key ~= "parent" then
                    replaceStack[#replaceStack + 1] = child
                end
            end
        end
    end
    
    local parentStack = { ast }
    local parentVisited = {}
    while #parentStack > 0 do
        local node = table.remove(parentStack)
        if node and not parentVisited[node] then
            parentVisited[node] = true
            for key, child in pairs(node) do
                if replacements[child] then
                    node[key] = replacements[child]
                elseif type(child) == "table" then
                    parentStack[#parentStack + 1] = child
                end
            end
        end
    end
    
    logger:info(string.format("[ConstantArray] Protected %d constants", #constants))
    
    return ast
end

return ConstantArray