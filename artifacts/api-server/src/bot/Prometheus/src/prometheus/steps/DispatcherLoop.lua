local Step     = require("prometheus.step")
local Ast      = require("prometheus.ast")
local Parser   = require("prometheus.parser")
local Enums    = require("prometheus.enums")
local visitast = require("prometheus.visitast")
local util     = require("prometheus.util")
local AstKind  = Ast.AstKind

local DispatcherLoop = Step:extend()
DispatcherLoop.Description = "Compresses function bodies into while-true dispatcher with hex-indexed state table"
DispatcherLoop.Name        = "Dispatcher Loop"
DispatcherLoop.SettingsDescriptor = {
    Threshold  = { type="number", default=0.5, min=0, max=1 },
    MinStates  = { type="number", default=4,   min=3, max=8  },
}
function DispatcherLoop:init(_) end

local function hexState(n)
    local styles = {
        string.format("0x%X", n),
        string.format("0x%02x", n),
        string.format("%d", n),
        string.format("0x%04X", n),
    }
    return styles[math.random(#styles)]
end

local function makeUniqueStates(n)
    local used, ids = {}, {}
    while #ids < n do
        local v = math.random(0x10, 0xFFF)
        if not used[v] then used[v]=true; ids[#ids+1]=v end
    end
    return ids
end

function DispatcherLoop:apply(ast, _)
    local scope = ast.body.scope

    local targets = {}
    for i, stmt in ipairs(ast.body.statements) do
        if (stmt.kind == AstKind.LocalFunctionDeclaration or
            stmt.kind == AstKind.FunctionDeclaration) and
           math.random() <= self.Threshold then
            targets[#targets+1] = { idx=i, node=stmt }
        end
    end

    if #targets == 0 then return ast end

    for _, t in ipairs(targets) do
        local fn   = t.node
        local body = fn.body
        if not body or not body.statements then
            -- skip this function
        else
            local stmts = body.statements
            if #stmts < 2 then
                -- skip this function
            else
                local n         = math.min(self.MinStates, #stmts)
                local chunkSize = math.ceil(#stmts / n)
                local chunks    = {}
                local i = 1
                while i <= #stmts do
                    local c = {}
                    for j = i, math.min(i+chunkSize-1, #stmts) do c[#c+1]=stmts[j] end
                    chunks[#chunks+1] = c
                    i = i + chunkSize
                end

                local stateIds  = makeUniqueStates(#chunks + 1)
                local exitState = stateIds[#stateIds]
                local ordered   = {}
                for k=1,#chunks do ordered[k]=stateIds[k] end

                local stateVar = body.scope:addVariable()
                local dispVar  = body.scope:addVariable()

                local dispEntries = {}
                for ci, chunk in ipairs(chunks) do
                    local sid     = ordered[ci]
                    local nextSid = ci < #chunks and ordered[ci+1] or exitState
                    local chunkBlock = {}
                    for _, s in ipairs(chunk) do chunkBlock[#chunkBlock+1] = s end

                    local transStmt = Ast.AssignmentStatement(
                        { Ast.AssignmentVariable(body.scope, stateVar) },
                        { Ast.NumberExpression(nextSid) }
                    )
                    chunkBlock[#chunkBlock+1] = transStmt

                    dispEntries[#dispEntries+1] = {
                        key    = sid,
                        keyHex = hexState(sid),
                        block  = chunkBlock,
                    }
                end

                local tableEntries = {}
                for _, de in ipairs(dispEntries) do
                    local fnBody = Ast.Block(body.scope, true)
                    fnBody.statements = de.block
                    local fnLit = Ast.FunctionLiteralExpression({}, fnBody)
                    tableEntries[#tableEntries+1] = Ast.TableEntry(
                        fnLit,
                        Ast.NumberExpression(de.key)
                    )
                end
                local tableNode = Ast.TableConstructorExpression(tableEntries)

                local fVar    = body.scope:addVariable()
                local fExpr   = Ast.VariableExpression(body.scope, fVar)
                local stateEx = Ast.VariableExpression(body.scope, stateVar)
                local dispEx  = Ast.VariableExpression(body.scope, dispVar)

                local indexExpr = Ast.IndexExpression(dispEx, stateEx)

                local localF = Ast.LocalVariableDeclaration(body.scope, {fVar}, {indexExpr})

                local callStmt  = Ast.CallStatement(Ast.FunctionCallExpression(fExpr, {}))
                local thenBlock = Ast.Block(body.scope, false)
                thenBlock.statements = { callStmt }

                local elseBlock = Ast.Block(body.scope, false)
                elseBlock.statements = { Ast.BreakStatement() }

                local ifNode = Ast.IfStatement(fExpr, thenBlock, {}, elseBlock)

                local whileBody = Ast.Block(body.scope, false)
                whileBody.statements = { localF, ifNode }

                local whileNode = Ast.WhileStatement(Ast.BoolExpression(true), whileBody)

                local initState = Ast.LocalVariableDeclaration(
                    body.scope, {stateVar}, { Ast.NumberExpression(ordered[1]) }
                )
                local initDisp = Ast.LocalVariableDeclaration(
                    body.scope, {dispVar}, { tableNode }
                )

                body.statements = { initState, initDisp, whileNode }
            end
        end
    end

    return ast
end

return DispatcherLoop