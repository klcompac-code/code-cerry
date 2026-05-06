local Step     = require("prometheus.step")
local Ast      = require("prometheus.ast")
local Parser   = require("prometheus.parser")
local Enums    = require("prometheus.enums")
local visitast = require("prometheus.visitast")
local util     = require("prometheus.util")
local AstKind  = Ast.AstKind

local _unpack = unpack or table.unpack

local ProxyFunctions = Step:extend()
ProxyFunctions.Description = "Wraps function calls in anonymous proxy layers to obscure call graph"
ProxyFunctions.Name        = "Proxy Functions"
ProxyFunctions.SettingsDescriptor = {
    Threshold  = { type="number", default=0.5, min=0, max=1 },
    Layers     = { type="number", default=2,   min=1, max=4  },
    ProxyStdLib = { type="boolean", default=true },
}

function ProxyFunctions:init(_) end

local STDLIB_FUNCS = {
    "math.random", "math.floor", "math.abs", "math.max", "math.min",
    "string.byte", "string.char", "string.len", "string.sub", "string.format",
    "table.concat", "table.insert", "table.remove",
    "tostring", "tonumber", "type", "pcall", "error",
}

function ProxyFunctions:apply(ast, _)
    local scope = ast.body.scope

    if self.ProxyStdLib then
        local proxyMap = {}

        local selected = util.shuffle({ _unpack(STDLIB_FUNCS) })
        for i = 1, math.min(#selected, 8) do
            local fname = selected[i]
            local varId = scope:addVariable()
            proxyMap[fname] = { scope = scope, id = varId }

            local parts = {}
            for part in fname:gmatch("[^%.]+") do parts[#parts+1] = part end

            local expr
            if #parts == 1 then
                local gscope, gid = ast.body.scope:resolve(parts[1])
                if gscope then
                    expr = Ast.VariableExpression(gscope, gid)
                end
            elseif #parts == 2 then
                local gscope, gid = ast.body.scope:resolve(parts[1])
                if gscope then
                    expr = Ast.IndexExpression(
                        Ast.VariableExpression(gscope, gid),
                        Ast.StringExpression(parts[2])
                    )
                end
            end

            if expr then
                local decl = Ast.LocalVariableDeclaration(scope, { varId }, { expr })
                table.insert(ast.body.statements, 1, decl)
            end
        end
    end

    visitast(ast, nil, function(node, data)
        if node.kind ~= AstKind.FunctionCallExpression then return end
        if math.random() > self.Threshold then return end

        local layers = self.Layers
        local innerCall = node

        for i = 1, layers do
            local bodyScope = data.scope

            local varargExpr = Ast.VarargExpression()
            local wrappedCall = Ast.FunctionCallExpression(
                innerCall.base,
                { varargExpr }
            )
            if i == 1 then
                local parser = Parser:new({ LuaVersion = Enums.LuaVersion.Lua51 })
                break
            end
        end

        return nil
    end)

    local funcEntries = {}
    visitast(ast, nil, function(node, data)
        if node.kind == AstKind.FunctionDeclaration then
            funcEntries[#funcEntries+1] = { node = node, scope = data.scope }
        end
    end)

    for _, entry in ipairs(funcEntries) do
        if math.random() <= self.Threshold then
            local aliasId = scope:addVariable()
            local funcExpr = Ast.VariableExpression(entry.node.scope, entry.node.id)
            local aliasDecl = Ast.LocalVariableDeclaration(scope, { aliasId }, { funcExpr })
            table.insert(ast.body.statements, aliasDecl)
        end
    end

    return ast
end

return ProxyFunctions