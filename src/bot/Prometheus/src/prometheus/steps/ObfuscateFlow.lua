local Step     = require("prometheus.step")
local Ast      = require("prometheus.ast")
local Parser   = require("prometheus.parser")
local Enums    = require("prometheus.enums")
local visitast = require("prometheus.visitast")
local util     = require("prometheus.util")
local AstKind  = Ast.AstKind

local ObfuscateFlow = Step:extend()
ObfuscateFlow.Description = "Converts code blocks into state machine dispatchers"
ObfuscateFlow.Name        = "Obfuscate Flow"
ObfuscateFlow.SettingsDescriptor = {
    Threshold  = { type="number", default=0.5, min=0, max=1 },
    MinStates  = { type="number", default=3,   min=2, max=6 },
}

function ObfuscateFlow:init(_) end

local function makeStateIds(n)
    local ids = {}
    local used = {}
    while #ids < n do
        local id = math.random(10, 9999)
        if not used[id] then
            used[id] = true
            ids[#ids+1] = id
        end
    end
    return ids
end

-- Safe function to create comparison
local function createEqualExpression(left, right)
    if Ast.EqualExpression then
        return Ast.EqualExpression(left, right)
    elseif Ast.EqualsExpression then
        return Ast.EqualsExpression(left, right)
    elseif Ast.ComparisonExpression then
        return Ast.ComparisonExpression(left, right, "==")
    else
        -- Fallback: create via parser
        local parser = Parser:new({ LuaVersion = Enums.LuaVersion.Lua51 })
        local code = "return " .. tostring(left) .. " == " .. tostring(right)
        local parsed = parser:parse(code)
        if parsed and parsed.body and parsed.body.statements[1] then
            local stmt = parsed.body.statements[1]
            if stmt.kind == AstKind.ReturnStatement and stmt.expressions[1] then
                return stmt.expressions[1]
            end
        end
        return nil
    end
end

function ObfuscateFlow:apply(ast, _)
    if not ast or not ast.body then return ast end

    visitast(ast, nil, function(node, data)
        if node.kind ~= AstKind.Block then return end
        if not node.isFunctionBlock and node ~= ast.body then return end
        if math.random() > self.Threshold then return end

        local stmts = node.statements
        if not stmts or #stmts < self.MinStates then return end

        local numStates = math.random(self.MinStates, math.min(self.MinStates + 2, #stmts))
        local chunkSize = math.ceil(#stmts / numStates)

        local chunks = {}
        local i = 1
        while i <= #stmts do
            local chunk = {}
            for j = i, math.min(i + chunkSize - 1, #stmts) do
                chunk[#chunk+1] = stmts[j]
            end
            chunks[#chunks+1] = chunk
            i = i + chunkSize
        end

        local stateIds = makeStateIds(#chunks + 1)
        local exitState = stateIds[#stateIds]
        local ordered = {}
        for k = 1, #chunks do ordered[k] = stateIds[k] end

        local stateVar = data.scope:addVariable()

        local initDecl = Ast.LocalVariableDeclaration(
            data.scope, { stateVar },
            { Ast.NumberExpression(ordered[1]) }
        )

        -- Build dispatcher string manually (avoid AST issues)
        local codeLines = { "do local _S = " .. ordered[1] .. " while true do" }
        
        for ci, chunk in ipairs(chunks) do
            local sid = ordered[ci]
            local nextSid = ci < #chunks and ordered[ci+1] or exitState
            codeLines[#codeLines+1] = "  if _S == " .. sid .. " then"
            for _, stmt in ipairs(chunk) do
                -- Convert statement to string (simplified)
                codeLines[#codeLines+1] = "    " .. tostring(stmt)
            end
            codeLines[#codeLines+1] = "    _S = " .. nextSid
            codeLines[#codeLines+1] = "  elseif "
        end
        
        codeLines[#codeLines+1] = "_S == " .. exitState .. " then break end end end"

        local fullCode = table.concat(codeLines, "\n")
        
        -- Parse and inject
        local parser = Parser:new({ LuaVersion = Enums.LuaVersion.Lua51 })
        local ok, parsed = pcall(function() return parser:parse(fullCode) end)
        if not ok or not parsed or not parsed.body then
            -- Fallback: keep original
            return
        end

        local doStat = parsed.body.statements[1]
        if doStat and doStat.body then
            doStat.body.scope:setParent(data.scope)
            node.statements = { initDecl, doStat }
        end
    end)

    return ast
end

return ObfuscateFlow