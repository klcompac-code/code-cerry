local Step     = require("prometheus.step")
local Ast      = require("prometheus.ast")
local Parser   = require("prometheus.parser")
local Enums    = require("prometheus.enums")
local visitast = require("prometheus.visitast")
local util     = require("prometheus.util")
local AstKind  = Ast.AstKind

local OpaquePredicate = Step:extend()
OpaquePredicate.Description = "Inserts always-true/false conditions that cannot be statically resolved"
OpaquePredicate.Name        = "Opaque Predicate"
OpaquePredicate.SettingsDescriptor = {
    Threshold = { type="number", default=0.4, min=0, max=1 },
    InsertDeadCode = { type="boolean", default=true },
}

function OpaquePredicate:init(_) end

-- SAFE predicates (no % issues, proper placeholders)
local truePredicates = {
    function()
        local n = math.random(2, 999)
        return "(((" .. n .. " * (" .. n .. "+1)) % 2) == 0)"
    end,
    function()
        local a = math.random(1,99)
        local b = math.random(1,99)
        return "(((" .. a .. "*" .. a .. ") + (" .. b .. "*" .. b .. ")) >= 0)"
    end,
    function()
        local a = math.random(10,999)
        return "(((" .. a .. " + " .. a .. ") - (" .. a .. "*2)) == 0)"
    end,
    function()
        local n = math.random(2, 100)
        return "(math.floor(math.sqrt(" .. n*n .. ")) == " .. n .. ")"
    end,
    function()
        local a = math.random(1, 100)
        local b = math.random(1, 100)
        return "((" .. a .. " + " .. b .. ") > 0)"
    end,
    function()
        local a = math.random(1, 50)
        local b = math.random(1, 50)
        return "(((" .. a .. " + " .. b .. ") * 0) == 0)"
    end,
}

local falsePredicates = {
    function()
        local n = math.random(1,999)
        return "((" .. n .. " * " .. n .. ") < 0)"
    end,
    function()
        local a = math.random(1,99)
        return "(" .. a .. " ~= " .. a .. ")"
    end,
    function()
        local n = math.random(2,100)
        return "(math.floor(math.sqrt(" .. n*n .. ")) == " .. n+1 .. ")"
    end,
    function()
        local a = math.random(1, 100)
        local b = math.random(1, 100)
        return "((" .. a .. " + " .. b .. ") < 0)"
    end,
    function()
        return "(1 == 0)"
    end,
    function()
        return "(2 == 3)"
    end,
}

function OpaquePredicate:apply(ast, pipeline)
    if not ast or not ast.body then return ast end
    
    local scope = ast.body.scope
    local parser = Parser:new({ LuaVersion = Enums.LuaVersion.Lua51 })

    visitast(ast, nil, function(node, parent, key)
        if node.kind ~= AstKind.Block then return end
        if not node.statements or #node.statements == 0 then return end
        if math.random() > self.Threshold then return end

        local stmts = node.statements
        local insertAt = math.random(1, #stmts)

        local isTrue = math.random(2) == 1
        local predFns = isTrue and truePredicates or falsePredicates
        local predCode = predFns[math.random(#predFns)]()

        local deadBody = ""
        if self.InsertDeadCode and not isTrue then
            deadBody = "local _d" .. math.random(9999) .. " = " .. math.random(9999)
        end

        local code
        if isTrue then
            local junkVal = math.random(1000, 9999)
            code = "do if " .. predCode .. " then local _x" .. math.random(9999) .. " = " .. junkVal .. " end end"
        else
            if deadBody ~= "" then
                code = "do if " .. predCode .. " then " .. deadBody .. " end end"
            else
                code = "do if " .. predCode .. " then local _n=nil end end"
            end
        end

        local ok, parsed = pcall(function()
            return parser:parse(code)
        end)
        
        if not ok or not parsed or not parsed.body then
            return
        end

        local doStat = parsed.body.statements[1]
        if not doStat then return end
        
        local targetScope = node.scope or scope
        if doStat.body then
            doStat.body.scope:setParent(targetScope)
        elseif doStat.scope then
            doStat.scope:setParent(targetScope)
        end
        
        table.insert(stmts, insertAt, doStat)
    end)

    return ast
end

return OpaquePredicate