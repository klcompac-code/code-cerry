local Step     = require("prometheus.step")
local Ast      = require("prometheus.ast")
local visitast = require("prometheus.visitast")
local util     = require("prometheus.util")
local AstKind  = Ast.AstKind

local FlattenControlFlow = Step:extend()
FlattenControlFlow.Description = "Flattens if/elseif chains into dispatch-table form"
FlattenControlFlow.Name        = "Flatten Control Flow"
FlattenControlFlow.SettingsDescriptor = {
    Threshold = { type="number", default=0.5, min=0, max=1 },
}

function FlattenControlFlow:init(_) 
    math.randomseed(os.time())
    for _ = 1, math.random(10, 50) do math.random() end
end

-- [FIX] Safe ID generator dengan range terbatas
local function generateUniqueId(usedIds)
    local id
    repeat
        id = math.random(100, 9999)
    until not usedIds[id]
    usedIds[id] = true
    return id
end

function FlattenControlFlow:apply(ast, _)
    visitast(ast, nil, function(node, data)
        if node.kind ~= AstKind.Block then return end
        if not node.statements or #node.statements == 0 then return end

        local newStmts = {}
        for _, stmt in ipairs(node.statements) do
            -- [FIX] Check if statement is flattenable
            local isFlattenable = stmt.kind == AstKind.IfStatement
                and stmt.elseifs 
                and type(stmt.elseifs) == "table" 
                and #stmt.elseifs >= 1
                and math.random() <= self.Threshold
            
            if isFlattenable then
                -- Create selector variable
                local selVar = data.scope:addVariable()
                local initDecl = Ast.LocalVariableDeclaration(
                    data.scope, { selVar }, { Ast.NumberExpression(0) }
                )
                newStmts[#newStmts + 1] = initDecl

                -- Generate unique branch IDs
                local branchIds = {}
                local usedIds = {}
                local numBranches = 1 + #stmt.elseifs + (stmt.elseBody and 1 or 0)
                numBranches = math.min(numBranches, 50) -- Limit maksimum
                
                for _ = 1, numBranches do
                    branchIds[#branchIds + 1] = generateUniqueId(usedIds)
                end

                -- Helper untuk membuat assignment
                local function makeAssign(id)
                    return Ast.AssignmentStatement(
                        { Ast.AssignmentVariable(data.scope, selVar) },
                        { Ast.NumberExpression(id) }
                    )
                end

                -- Selector if untuk menentukan branch
                local selBlock0 = Ast.Block(data.scope, false)
                selBlock0.statements = { makeAssign(branchIds[1]) }

                local selElseifs = {}
                for k, ei in ipairs(stmt.elseifs) do
                    if ei and ei[1] and ei[2] then
                        local b = Ast.Block(data.scope, false)
                        b.statements = { makeAssign(branchIds[k + 1]) }
                        selElseifs[#selElseifs + 1] = { ei[1], b }
                    end
                end

                local selElseBlock = nil
                if stmt.elseBody then
                    selElseBlock = Ast.Block(data.scope, false)
                    selElseBlock.statements = { makeAssign(branchIds[numBranches]) }
                end

                local selectorIf = Ast.IfStatement(
                    stmt.condition, selBlock0, selElseifs, selElseBlock
                )
                newStmts[#newStmts + 1] = selectorIf

                -- Dispatch if untuk eksekusi
                local function makeSelExpr()
                    return Ast.VariableExpression(data.scope, selVar)
                end
                
                local function makeEq(id)
                    return Ast.EqualExpression(makeSelExpr(), Ast.NumberExpression(id))
                end

                local dispBlock0 = stmt.body
                local dispElseifs = {}
                for k, ei in ipairs(stmt.elseifs) do
                    if ei and ei[1] and ei[2] then
                        dispElseifs[#dispElseifs + 1] = { makeEq(branchIds[k + 1]), ei[2] }
                    end
                end
                local dispElseBlock = stmt.elseBody

                local dispatchIf = Ast.IfStatement(
                    makeEq(branchIds[1]), dispBlock0, dispElseifs, dispElseBlock
                )
                newStmts[#newStmts + 1] = dispatchIf
            else
                newStmts[#newStmts + 1] = stmt
            end
        end
        node.statements = newStmts
    end)
    return ast
end

return FlattenControlFlow