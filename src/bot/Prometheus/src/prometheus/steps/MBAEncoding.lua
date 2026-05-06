local Step     = require("prometheus.step")
local Ast      = require("prometheus.ast")
local visitast = require("prometheus.visitast")
local AstKind  = Ast.AstKind

local MBAEncoding = Step:extend()
MBAEncoding.Description = "Mixed Boolean-Arithmetic encoding: replaces numbers with semantically equivalent MBA expressions"
MBAEncoding.Name        = "MBA Encoding"
MBAEncoding.SettingsDescriptor = {
    Threshold = { type="number", default=0.8, min=0, max=1 },
    Depth     = { type="number", default=2,   min=1, max=4  },
}
function MBAEncoding:init(_) end

local function N(v) return Ast.NumberExpression(v) end
local function ADD(a,b) return Ast.AddExpression(a,b,false) end
local function SUB(a,b) return Ast.SubExpression(a,b,false) end
local function MUL(a,b) return Ast.MulExpression(a,b,false) end
local function DIV(a,b) return Ast.DivExpression(a,b,false) end
local function MOD(a,b) return Ast.ModExpression(a,b,false) end
local function POW(a,b) return Ast.PowExpression(a,b,false) end
local function FLOOR(x) return Ast.FunctionCallExpression(
    Ast.IndexExpression(Ast.VariableExpression(nil,nil), Ast.StringExpression("floor")),x) end

-- MBA identities (all pure Lua51 arithmetic, no bitwise)
-- Each returns an AST expression equivalent to `val`
local function mba_generators(val, depth, self2)
    if depth > self2.Depth then return N(val) end

    -- Guard: only integers in safe range
    if val ~= math.floor(val) or math.abs(val) > 2^20 then return N(val) end

    local r = math.random

    local generators = {
        -- Identity: val = (val + a) - a
        function()
            local a = r(1,999)
            return SUB(self2:_mba(val+a, depth+1), self2:_mba(a, depth+1))
        end,
        -- Identity: val = (val * a) / a  [a != 0]
        function()
            local a = r(2,7)
            if (val*a) ~= math.floor(val*a) then return nil end
            return DIV(self2:_mba(val*a, depth+1), N(a))
        end,
        -- Identity: val = (val + b*p) % p  [p prime, val < p, val >= 0]
        function()
            if val < 0 then return nil end
            local primes = {1009,2003,4001,8009,16007}
            local p = primes[r(1,#primes)]
            if val >= p then return nil end
            local b = r(1,50)
            return MOD(self2:_mba(val + b*p, depth+1), N(p))
        end,
        -- Identity: val = ((val+c)^2 - c^2 - 2*val*c) / ... simplified: val = a - b
        function()
            local a = r(1,500)
            local b = a - val
            if b < 0 or b > 2^20 then return nil end
            return SUB(self2:_mba(a, depth+1), self2:_mba(b, depth+1))
        end,
        -- Table-length identity: #{a,b,...} = n (runtime computed)
        function()
            if val < 0 or val > 12 or val ~= math.floor(val) then return nil end
            local entries = {}
            for i=1,val do entries[i] = Ast.TableEntry(N(r(1,999))) end
            return Ast.LenExpression(Ast.TableConstructorExpression(entries))
        end,
        -- Identity: val = (m^2 - k) where m^2 = val+k
        function()
            if val < 0 then return nil end
            local k = r(1,100)
            local m = math.floor(math.sqrt(val+k))
            if m*m ~= val+k then return nil end
            return SUB(
                MUL(self2:_mba(m,depth+1), self2:_mba(m,depth+1)),
                self2:_mba(k,depth+1)
            )
        end,
        -- Identity: val = (p*q - r) where p*q-r = val
        function()
            local p = r(2,20); local q = r(2,20)
            local residue = p*q - val
            if residue < 0 or residue > 2^20 then return nil end
            return SUB(MUL(N(p),N(q)), self2:_mba(residue,depth+1))
        end,
    }

    -- Shuffle generators and try until one succeeds
    local order = {}
    for i=1,#generators do order[i]=i end
    for i=#order,2,-1 do
        local j=r(1,i); order[i],order[j]=order[j],order[i]
    end

    for _,i in ipairs(order) do
        local ok, result = pcall(generators[i])
        if ok and result then return result end
    end

    return N(val)
end

function MBAEncoding:_mba(val, depth)
    if depth > self.Depth then return N(val) end
    if math.random() > 0.7 then return N(val) end
    return mba_generators(val, depth, self)
end

function MBAEncoding:apply(ast, _)
    visitast(ast, nil, function(node, _)
        if node.kind ~= AstKind.NumberExpression then return end
        if math.random() > self.Threshold then return end
        local val = node.value
        if type(val) ~= "number" then return end
        if val ~= math.floor(val) or math.abs(val) > 2^20 then return end
        return self:_mba(val, 0)
    end)
    return ast
end

return MBAEncoding
