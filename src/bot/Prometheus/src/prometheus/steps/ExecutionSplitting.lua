local Step     = require("prometheus.step")
local Ast      = require("prometheus.ast")
local Parser   = require("prometheus.parser")
local Enums    = require("prometheus.enums")
local visitast = require("prometheus.visitast")
local util     = require("prometheus.util")
local AstKind  = Ast.AstKind

local ExecutionSplitting = Step:extend()
ExecutionSplitting.Description = "Splits function execution across coroutine-resumed chunks"
ExecutionSplitting.Name        = "Execution Splitting"
ExecutionSplitting.SettingsDescriptor = {
    Threshold  = { type="number", default=0.45, min=0, max=1 },
    ChunkSize  = { type="number", default=3,    min=2, max=8  },
}
function ExecutionSplitting:init(_) end

function ExecutionSplitting:apply(ast, _)
    local scope  = ast.body.scope
    local parser = Parser:new({LuaVersion=Enums.LuaVersion.Lua51})

    visitast(ast, nil, function(node, data)
        if node.kind ~= AstKind.Block then return end
        if not node.isFunctionBlock then return end
        if math.random() > self.Threshold then return end
        local stmts = node.statements
        if #stmts < self.ChunkSize + 1 then return end

        local mid   = math.random(self.ChunkSize, #stmts - 1)
        local part1 = {}
        local part2 = {}
        for i=1,mid       do part1[#part1+1]=stmts[i] end
        for i=mid+1,#stmts do part2[#part2+1]=stmts[i] end

        local resumeVar = data.scope:addVariable()
        local coVar     = data.scope:addVariable()

        local coBody  = Ast.Block(data.scope, true)
        coBody.statements = part2

        local coLit   = Ast.FunctionLiteralExpression({}, coBody)
        local coCreate = Ast.FunctionCallExpression(
            Ast.IndexExpression(
                Ast.VariableExpression(data.scope, data.scope:resolve("coroutine") or coVar),
                Ast.StringExpression("wrap")
            ),
            { coLit }
        )

        local initCo  = Ast.LocalVariableDeclaration(data.scope, {coVar}, {coCreate})
        local callCo  = Ast.CallStatement(
            Ast.FunctionCallExpression(Ast.VariableExpression(data.scope,coVar), {})
        )

        local newStmts = {}
        for _,s in ipairs(part1) do newStmts[#newStmts+1]=s end
        newStmts[#newStmts+1] = initCo
        newStmts[#newStmts+1] = callCo
        node.statements = newStmts
    end)
    return ast
end

return ExecutionSplitting
