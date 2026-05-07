
local Step     = require("prometheus.step")
local Ast      = require("prometheus.ast")
local visitast = require("prometheus.visitast")
local util     = require("prometheus.util")
local AstKind  = Ast.AstKind

local NestedFunction = Step:extend()
NestedFunction.Description = "Wraps functions in nested closure layers for call graph obfuscation"
NestedFunction.Name        = "Nested Function"
NestedFunction.SettingsDescriptor = {
    Threshold = { type="number", default=0.5, min=0, max=1 },
    Layers    = { type="number", default=2,   min=1, max=4 },
}
function NestedFunction:init(_) end

function NestedFunction:apply(ast, _)
    visitast(ast, nil, function(node, data)
        if node.kind ~= AstKind.FunctionLiteralExpression then return end
        if math.random() > self.Threshold then return end

        local inner = node
        for i = 1, self.Layers do
            local wrapBody  = Ast.Block(data.scope, true)
            wrapBody.statements = { Ast.ReturnStatement({ inner }) }
            local wrapper   = Ast.FunctionLiteralExpression({}, wrapBody)
            inner = Ast.FunctionCallExpression(wrapper, {})
        end
        return inner
    end)
    return ast
end

return NestedFunction
