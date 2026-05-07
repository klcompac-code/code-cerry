local Step = require("prometheus.step")
local Ast = require("prometheus.ast")
local visitast = require("prometheus.visitast")
local util = require("prometheus.util")
local AstKind = Ast.AstKind

local NumbersToExpressions = Step:extend()
NumbersToExpressions.Description = "Custom: transforms numbers using bitwise, base-decompose, and multi-layer expressions"
NumbersToExpressions.Name = "Numbers To Expressions"

NumbersToExpressions.SettingsDescriptor = {
    Threshold = { type="number", default=1, min=0, max=1 },
    InternalThreshold = { type="number", default=0.25, min=0, max=0.8 },
}

local function num(v) return Ast.NumberExpression(v) end
local function add(a,b) return Ast.AddExpression(a, b, false) end
local function sub(a,b) return Ast.SubExpression(a, b, false) end
local function mul(a,b) return Ast.MulExpression(a, b, false) end
local function mod_(a,b) return Ast.ModExpression(a, b, false) end

function NumbersToExpressions:init(_)
    local function genBase(val, depth, self2)
        if val ~= math.floor(val) or val < 0 or val > 16777216 then return nil end
        local bases = {7, 11, 13, 17, 19, 23, 31, 37, 41, 43}
        local base = bases[math.random(#bases)]
        local r = val % base
        local q = (val - r) / base
        return add(mul(self2:_expr(q, depth+1), num(base)), self2:_expr(r, depth+1))
    end

    local function genXor(val, depth, self2)
        if val ~= math.floor(val) or val < 0 or val >= 16777216 then return nil end
        local k = math.random(1, 255)
        local xorVal = 0
        local a, b = val, k
        local m = 1
        for _ = 1, 24 do
            local x, y = a % 2, b % 2
            if x ~= y then xorVal = xorVal + m end
            a = math.floor((a - x) / 2)
            b = math.floor((b - y) / 2)
            m = m * 2
        end
        local mid = val + k
        return sub(self2:_expr(mid, depth+1), self2:_expr(k, depth+1))
    end

    local function genSquare(val, depth, self2)
        if val ~= math.floor(val) or val < 0 or val > 1048576 then return nil end
        local k = math.random(1, 100)
        local nk = val + k
        local m = math.floor(math.sqrt(nk))
        if m * m == nk then
            return sub(mul(self2:_expr(m, depth+1), self2:_expr(m, depth+1)), self2:_expr(k, depth+1))
        end
        return nil
    end

    local function genTriple(val, depth, self2)
        local p = math.random(-512, 512)
        local q = math.random(-512, 512)
        local pq = p + q
        local np = val + pq
        return sub(add(self2:_expr(np, depth+1), self2:_expr(q, depth+1)), self2:_expr(pq, depth+1))
    end

    local function genModChain(val, depth, self2)
        if val ~= math.floor(val) or val < 0 then return nil end
        local primes = {257, 509, 1021, 2053, 4099, 8191, 16381}
        local r = primes[math.random(#primes)]
        if val < r then
            local m = math.random(1, 100)
            local lhs = val + m * r
            return mod_(self2:_expr(lhs, depth+1), self2:_expr(r, depth+1))
        end
        return nil
    end

    self.generators = { genBase, genXor, genSquare, genTriple, genModChain }
end

function NumbersToExpressions:_expr(val, depth)
    if depth > 12 then return num(val) end
    if math.random() > (self.InternalThreshold or 0.25) then return num(val) end

    local gens = util.shuffle(self.generators)
    for _, gen in ipairs(gens) do
        local result = gen(val, depth, self)
        if result then return result end
    end
    return num(val)
end

function NumbersToExpressions:apply(ast)
    visitast(ast, nil, function(node, parent, key)
        if node and node.kind == AstKind.NumberExpression then
            if math.random() <= (self.Threshold or 1) then
                local newExpr = self:_expr(node.value, 0)
                if parent and key and newExpr then
                    parent[key] = newExpr
                end
            end
        end
    end)
    return ast
end

return NumbersToExpressions