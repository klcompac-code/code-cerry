-- generator.lua
-- AST to Lua code generator untuk Prometheus Compiler
-- FIXED: All syntax errors resolved

local Ast = require("prometheus.ast")
local AstKind = Ast.AstKind

local generator = {}

local function escapeString(str)
    return string.format("%q", str):gsub("\\\n", "\\n"):gsub("\\\r", "\\r")
end

local function dumpTable(tbl, indent)
    indent = indent or ""
    local lines = {}
    
    for k, v in pairs(tbl) do
        local keyStr
        if type(k) == "string" then
            keyStr = "[" .. escapeString(k) .. "]"
        else
            keyStr = "[" .. tostring(k) .. "]"
        end
        lines[#lines + 1] = indent .. keyStr .. " = " .. generator.generate(v, indent .. "  ")
    end
    
    if #lines == 0 then
        return "{}"
    end
    return "{\n" .. table.concat(lines, ",\n") .. "\n" .. indent .. "}"
end

function generator.generate(node, indent)
    indent = indent or ""
    
    if not node then
        return "nil"
    end
    
    -- Handle raw values
    if type(node) ~= "table" then
        if type(node) == "string" then
            return escapeString(node)
        elseif type(node) == "number" then
            if node == math.floor(node) and node >= 0 and node < 1000000 then
                return string.format("0x%X", node)
            end
            return tostring(node)
        elseif type(node) == "boolean" then
            return node and "true" or "false"
        end
        return tostring(node)
    end
    
    -- Handle AST nodes by kind
    local kind = node.kind
    
    if not kind then
        return dumpTable(node, indent)
    end
    
    -- TopNode
    if kind == AstKind.TopNode then
        return generator.generate(node.body, indent)
    end
    
    -- Block
    if kind == AstKind.Block then
        local statements = {}
        for _, stmt in ipairs(node.statements or {}) do
            local stmtStr = generator.generate(stmt, indent)
            if stmtStr and stmtStr ~= "" then
                statements[#statements + 1] = stmtStr
            end
        end
        if #statements == 0 then
            return ""
        end
        return table.concat(statements, "\n" .. indent)
    end
    
    -- ============================================================
    -- STATEMENTS
    -- ============================================================
    
    if kind == AstKind.AssignmentStatement then
        local lhs = {}
        local rhs = {}
        for _, v in ipairs(node.lhs or {}) do
            lhs[#lhs + 1] = generator.generate(v, indent)
        end
        for _, v in ipairs(node.rhs or {}) do
            rhs[#rhs + 1] = generator.generate(v, indent)
        end
        if #lhs == 0 then
            return ""
        end
        return table.concat(lhs, ", ") .. " = " .. table.concat(rhs, ", ")
    end
    
    if kind == AstKind.LocalVariableDeclaration then
        local names = {}
        for _, id in ipairs(node.ids or {}) do
            local name = "_var" .. tostring(id)
            if node.scope and node.scope.getVariableName then
                local scopedName = node.scope:getVariableName(id)
                if scopedName then
                    name = scopedName
                end
            end
            names[#names + 1] = name
        end
        local result = "local " .. table.concat(names, ", ")
        if node.expressions and #node.expressions > 0 then
            local exprs = {}
            for _, expr in ipairs(node.expressions) do
                exprs[#exprs + 1] = generator.generate(expr, indent)
            end
            result = result .. " = " .. table.concat(exprs, ", ")
        end
        return result
    end
    
    if kind == AstKind.ReturnStatement then
        local args = {}
        for _, arg in ipairs(node.args or {}) do
            args[#args + 1] = generator.generate(arg, indent)
        end
        if #args > 0 then
            return "return " .. table.concat(args, ", ")
        end
        return "return"
    end
    
    if kind == AstKind.FunctionCallStatement then
        local base = generator.generate(node.base, indent)
        local args = {}
        for _, arg in ipairs(node.args or {}) do
            args[#args + 1] = generator.generate(arg, indent)
        end
        return base .. "(" .. table.concat(args, ", ") .. ")"
    end
    
    if kind == AstKind.PassSelfFunctionCallStatement then
        local base = generator.generate(node.base, indent)
        local args = {}
        for _, arg in ipairs(node.args or {}) do
            args[#args + 1] = generator.generate(arg, indent)
        end
        return base .. ":" .. node.passSelfFunctionName .. "(" .. table.concat(args, ", ") .. ")"
    end
    
    if kind == AstKind.BreakStatement then
        return "break"
    end
    
    if kind == AstKind.ContinueStatement then
        return "continue"
    end
    
    if kind == AstKind.DoStatement then
        local lines = { "do" }
        for _, stmt in ipairs(node.body.statements or {}) do
            lines[#lines + 1] = indent .. "  " .. generator.generate(stmt, indent .. "  ")
        end
        lines[#lines + 1] = "end"
        return table.concat(lines, "\n" .. indent)
    end
    
    -- ============================================================
    -- IF STATEMENT (FIXED: no syntax error)
    -- ============================================================
    
    if kind == AstKind.IfStatement then
        local lines = {}
        lines[#lines + 1] = "if " .. generator.generate(node.condition, indent) .. " then"
        
        -- Then block
        for _, stmt in ipairs(node.body.statements or {}) do
            lines[#lines + 1] = indent .. "  " .. generator.generate(stmt, indent .. "  ")
        end
        
        -- Elseif blocks
        for _, elseifNode in ipairs(node.elseifs or {}) do
            if type(elseifNode) == "table" and elseifNode[1] and elseifNode[2] then
                lines[#lines + 1] = "elseif " .. generator.generate(elseifNode[1], indent) .. " then"
                for _, stmt in ipairs(elseifNode[2].statements or {}) do
                    lines[#lines + 1] = indent .. "  " .. generator.generate(stmt, indent .. "  ")
                end
            end
        end
        
        -- Else block
        if node.elseBody then
            lines[#lines + 1] = "else"
            for _, stmt in ipairs(node.elseBody.statements or {}) do
                lines[#lines + 1] = indent .. "  " .. generator.generate(stmt, indent .. "  ")
            end
        end
        
        lines[#lines + 1] = "end"
        return table.concat(lines, "\n" .. indent)
    end
    
    -- ============================================================
    -- LOOP STATEMENTS
    -- ============================================================
    
    if kind == AstKind.WhileStatement then
        local lines = {}
        lines[#lines + 1] = "while " .. generator.generate(node.condition, indent) .. " do"
        for _, stmt in ipairs(node.body.statements or {}) do
            lines[#lines + 1] = indent .. "  " .. generator.generate(stmt, indent .. "  ")
        end
        lines[#lines + 1] = "end"
        return table.concat(lines, "\n" .. indent)
    end
    
    if kind == AstKind.RepeatStatement then
        local lines = { "repeat" }
        for _, stmt in ipairs(node.body.statements or {}) do
            lines[#lines + 1] = indent .. "  " .. generator.generate(stmt, indent .. "  ")
        end
        lines[#lines + 1] = "until " .. generator.generate(node.condition, indent)
        return table.concat(lines, "\n" .. indent)
    end
    
    if kind == AstKind.ForStatement then
        local varName = "_forvar"
        if node.scope and node.scope.getVariableName then
            varName = node.scope:getVariableName(node.id) or varName
        end
        local startVal = generator.generate(node.initialValue, indent)
        local endVal = generator.generate(node.finalValue, indent)
        local stepVal = generator.generate(node.incrementBy, indent)
        
        local lines = {}
        lines[#lines + 1] = "for " .. varName .. " = " .. startVal .. ", " .. endVal .. ", " .. stepVal .. " do"
        for _, stmt in ipairs(node.body.statements or {}) do
            lines[#lines + 1] = indent .. "  " .. generator.generate(stmt, indent .. "  ")
        end
        lines[#lines + 1] = "end"
        return table.concat(lines, "\n" .. indent)
    end
    
    if kind == AstKind.ForInStatement then
        local names = {}
        for _, id in ipairs(node.ids or {}) do
            local name = "_forvar" .. tostring(id)
            if node.scope and node.scope.getVariableName then
                local scopedName = node.scope:getVariableName(id)
                if scopedName then
                    name = scopedName
                end
            end
            names[#names + 1] = name
        end
        local exprs = {}
        for _, expr in ipairs(node.expressions or {}) do
            exprs[#exprs + 1] = generator.generate(expr, indent)
        end
        
        local lines = {}
        lines[#lines + 1] = "for " .. table.concat(names, ", ") .. " in " .. table.concat(exprs, ", ") .. " do"
        for _, stmt in ipairs(node.body.statements or {}) do
            lines[#lines + 1] = indent .. "  " .. generator.generate(stmt, indent .. "  ")
        end
        lines[#lines + 1] = "end"
        return table.concat(lines, "\n" .. indent)
    end
    
    -- ============================================================
    -- FUNCTION DECLARATIONS
    -- ============================================================
    
    if kind == AstKind.FunctionDeclaration then
        local funcName = "_func"
        if node.scope and node.scope.getVariableName then
            funcName = node.scope:getVariableName(node.id) or funcName
        end
        
        -- Build full name with indices
        local fullName = funcName
        for _, idx in ipairs(node.indices or {}) do
            fullName = fullName .. "." .. tostring(idx)
        end
        
        local args = {}
        for _, arg in ipairs(node.args or {}) do
            if arg.kind == AstKind.VariableExpression then
                local argName = "_arg"
                if arg.scope and arg.scope.getVariableName then
                    argName = arg.scope:getVariableName(arg.id) or argName
                end
                args[#args + 1] = argName
            elseif arg.kind == AstKind.VarargExpression then
                args[#args + 1] = "..."
            else
                args[#args + 1] = generator.generate(arg, indent)
            end
        end
        
        local lines = {}
        lines[#lines + 1] = "function " .. fullName .. "(" .. table.concat(args, ", ") .. ")"
        for _, stmt in ipairs(node.body.statements or {}) do
            lines[#lines + 1] = indent .. "  " .. generator.generate(stmt, indent .. "  ")
        end
        lines[#lines + 1] = "end"
        return table.concat(lines, "\n" .. indent)
    end
    
    if kind == AstKind.LocalFunctionDeclaration then
        local funcName = "_localfunc"
        if node.scope and node.scope.getVariableName then
            funcName = node.scope:getVariableName(node.id) or funcName
        end
        
        local args = {}
        for _, arg in ipairs(node.args or {}) do
            if arg.kind == AstKind.VariableExpression then
                local argName = "_arg"
                if arg.scope and arg.scope.getVariableName then
                    argName = arg.scope:getVariableName(arg.id) or argName
                end
                args[#args + 1] = argName
            elseif arg.kind == AstKind.VarargExpression then
                args[#args + 1] = "..."
            else
                args[#args + 1] = generator.generate(arg, indent)
            end
        end
        
        local lines = {}
        lines[#lines + 1] = "local function " .. funcName .. "(" .. table.concat(args, ", ") .. ")"
        for _, stmt in ipairs(node.body.statements or {}) do
            lines[#lines + 1] = indent .. "  " .. generator.generate(stmt, indent .. "  ")
        end
        lines[#lines + 1] = "end"
        return table.concat(lines, "\n" .. indent)
    end
    
    if kind == AstKind.FunctionLiteralExpression then
        local args = {}
        for _, arg in ipairs(node.args or {}) do
            if arg.kind == AstKind.VariableExpression then
                local argName = "_arg"
                if arg.scope and arg.scope.getVariableName then
                    argName = arg.scope:getVariableName(arg.id) or argName
                end
                args[#args + 1] = argName
            elseif arg.kind == AstKind.VarargExpression then
                args[#args + 1] = "..."
            else
                args[#args + 1] = generator.generate(arg, indent)
            end
        end
        
        local lines = { "function(" .. table.concat(args, ", ") .. ")" }
        for _, stmt in ipairs(node.body.statements or {}) do
            lines[#lines + 1] = indent .. "  " .. generator.generate(stmt, indent .. "  ")
        end
        lines[#lines + 1] = "end"
        return table.concat(lines, "\n" .. indent)
    end
    
    -- ============================================================
    -- EXPRESSIONS
    -- ============================================================
    
    if kind == AstKind.VariableExpression then
        if node.scope and node.scope.getVariableName then
            local name = node.scope:getVariableName(node.id)
            if name then
                return name
            end
        end
        return "_var" .. tostring(node.id)
    end
    
    if kind == AstKind.AssignmentVariable then
        if node.scope and node.scope.getVariableName then
            local name = node.scope:getVariableName(node.id)
            if name then
                return name
            end
        end
        return "_var" .. tostring(node.id)
    end
    
    if kind == AstKind.IndexExpression or kind == AstKind.AssignmentIndexing then
        local base = generator.generate(node.base, indent)
        local idx = generator.generate(node.index, indent)
        return base .. "[" .. idx .. "]"
    end
    
    if kind == AstKind.StringExpression then
        return escapeString(node.value)
    end
    
    if kind == AstKind.NumberExpression then
        local val = node.value
        if val == math.floor(val) and val >= 0 and val < 1000000 then
            -- Use hex for integers
            return string.format("0x%X", val)
        end
        return tostring(val)
    end
    
    if kind == AstKind.BooleanExpression then
        return node.value and "true" or "false"
    end
    
    if kind == AstKind.NilExpression then
        return "nil"
    end
    
    if kind == AstKind.VarargExpression then
        return "..."
    end
    
    if kind == AstKind.TableConstructorExpression then
        local entries = {}
        for _, entry in ipairs(node.entries or {}) do
            if entry.kind == AstKind.TableEntry then
                entries[#entries + 1] = generator.generate(entry.value, indent)
            elseif entry.kind == AstKind.KeyedTableEntry then
                local key = generator.generate(entry.key, indent)
                local val = generator.generate(entry.value, indent)
                entries[#entries + 1] = "[" .. key .. "] = " .. val
            end
        end
        if #entries == 0 then
            return "{}"
        end
        return "{ " .. table.concat(entries, ", ") .. " }"
    end
    
    if kind == AstKind.FunctionCallExpression then
        local base = generator.generate(node.base, indent)
        local args = {}
        for _, arg in ipairs(node.args or {}) do
            args[#args + 1] = generator.generate(arg, indent)
        end
        return base .. "(" .. table.concat(args, ", ") .. ")"
    end
    
    if kind == AstKind.PassSelfFunctionCallExpression then
        local base = generator.generate(node.base, indent)
        local args = {}
        for _, arg in ipairs(node.args or {}) do
            args[#args + 1] = generator.generate(arg, indent)
        end
        return base .. ":" .. node.passSelfFunctionName .. "(" .. table.concat(args, ", ") .. ")"
    end
    
    -- ============================================================
    -- BINARY OPERATORS
    -- ============================================================
    
    if kind == AstKind.AddExpression then
        return "(" .. generator.generate(node.left, indent) .. " + " .. generator.generate(node.right, indent) .. ")"
    end
    
    if kind == AstKind.SubExpression then
        return "(" .. generator.generate(node.left, indent) .. " - " .. generator.generate(node.right, indent) .. ")"
    end
    
    if kind == AstKind.MulExpression then
        return "(" .. generator.generate(node.left, indent) .. " * " .. generator.generate(node.right, indent) .. ")"
    end
    
    if kind == AstKind.DivExpression then
        return "(" .. generator.generate(node.left, indent) .. " / " .. generator.generate(node.right, indent) .. ")"
    end
    
    if kind == AstKind.ModExpression then
        return "(" .. generator.generate(node.left, indent) .. " % " .. generator.generate(node.right, indent) .. ")"
    end
    
    if kind == AstKind.PowExpression then
        return "(" .. generator.generate(node.left, indent) .. " ^ " .. generator.generate(node.right, indent) .. ")"
    end
    
    if kind == AstKind.StrCatExpression then
        return "(" .. generator.generate(node.left, indent) .. " .. " .. generator.generate(node.right, indent) .. ")"
    end
    
    if kind == AstKind.EqualsExpression then
        return "(" .. generator.generate(node.left, indent) .. " == " .. generator.generate(node.right, indent) .. ")"
    end
    
    if kind == AstKind.NotEqualsExpression then
        return "(" .. generator.generate(node.left, indent) .. " ~= " .. generator.generate(node.right, indent) .. ")"
    end
    
    if kind == AstKind.LessThanExpression then
        return "(" .. generator.generate(node.left, indent) .. " < " .. generator.generate(node.right, indent) .. ")"
    end
    
    if kind == AstKind.GreaterThanExpression then
        return "(" .. generator.generate(node.left, indent) .. " > " .. generator.generate(node.right, indent) .. ")"
    end
    
    if kind == AstKind.LessThanOrEqualsExpression then
        return "(" .. generator.generate(node.left, indent) .. " <= " .. generator.generate(node.right, indent) .. ")"
    end
    
    if kind == AstKind.GreaterThanOrEqualsExpression then
        return "(" .. generator.generate(node.left, indent) .. " >= " .. generator.generate(node.right, indent) .. ")"
    end
    
    if kind == AstKind.AndExpression then
        return "(" .. generator.generate(node.left, indent) .. " and " .. generator.generate(node.right, indent) .. ")"
    end
    
    if kind == AstKind.OrExpression then
        return "(" .. generator.generate(node.left, indent) .. " or " .. generator.generate(node.right, indent) .. ")"
    end
    
    -- ============================================================
    -- UNARY OPERATORS
    -- ============================================================
    
    if kind == AstKind.NotExpression then
        return "(not " .. generator.generate(node.rhs, indent) .. ")"
    end
    
    if kind == AstKind.NegateExpression then
        return "(-" .. generator.generate(node.rhs, indent) .. ")"
    end
    
    if kind == AstKind.LenExpression then
        return "(# " .. generator.generate(node.rhs, indent) .. ")"
    end
    
    -- ============================================================
    -- COMPOUND ASSIGNMENTS (LuaU)
    -- ============================================================
    
    if kind == AstKind.CompoundAddStatement then
        return generator.generate(node.lhs, indent) .. " += " .. generator.generate(node.rhs, indent)
    end
    
    if kind == AstKind.CompoundSubStatement then
        return generator.generate(node.lhs, indent) .. " -= " .. generator.generate(node.rhs, indent)
    end
    
    if kind == AstKind.CompoundMulStatement then
        return generator.generate(node.lhs, indent) .. " *= " .. generator.generate(node.rhs, indent)
    end
    
    if kind == AstKind.CompoundDivStatement then
        return generator.generate(node.lhs, indent) .. " /= " .. generator.generate(node.rhs, indent)
    end
    
    if kind == AstKind.CompoundModStatement then
        return generator.generate(node.lhs, indent) .. " %= " .. generator.generate(node.rhs, indent)
    end
    
    if kind == AstKind.CompoundPowStatement then
        return generator.generate(node.lhs, indent) .. " ^= " .. generator.generate(node.rhs, indent)
    end
    
    if kind == AstKind.CompoundConcatStatement then
        return generator.generate(node.lhs, indent) .. " ..= " .. generator.generate(node.rhs, indent)
    end
    
    -- ============================================================
    -- FALLBACK
    -- ============================================================
    
    return tostring(node)
end

return generator