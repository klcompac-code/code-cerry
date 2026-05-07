
local Step    = require("prometheus.step")
local Ast     = require("prometheus.ast")
local visitAst = require("prometheus.visitast")
local Parser  = require("prometheus.parser")
local util    = require("prometheus.util")
local enums   = require("prometheus.enums")

local LuaVersion = enums.LuaVersion

local SplitStrings = Step:extend()
SplitStrings.Description = "Custom: ZigZag / Interleave / Reversal string split with runtime merge"
SplitStrings.Name        = "Split Strings"

SplitStrings.SettingsDescriptor = {
    Threshold = { name="Threshold", type="number", default=1, min=0, max=8 },
    Method    = {
        name   = "Method",
        type   = "enum",
        values = { "zigzag", "interleave", "reversal", "random", "xor" },
        default = "random",
    },
}

function SplitStrings:init(settings) end

local zigzagMergeCode = [[
function MERGE_ZZ(a, b)
    local out, la, lb = {}, #a, #b
    local total = la + lb
    local ai, bi = 1, 1
    for i = 1, total do
        if i % 2 == 1 then
            out[i] = a:sub(ai, ai); ai = ai + 1
        else
            out[i] = b:sub(bi, bi); bi = bi + 1
        end
    end
    return table.concat(out)
end
]]

local function splitZigzag(str)
    local odd, even = {}, {}
    for i = 1, #str do
        local c = str:sub(i, i)
        if i % 2 == 1 then odd[#odd+1] = c
        else           even[#even+1] = c end
    end
    return table.concat(odd), table.concat(even)
end

local interleaveMergeCode = [[
function MERGE_IL(parts, order)
    local buf = {}
    for i = 1, #order do
        local pi, ci = order[i][1], order[i][2]
        buf[i] = parts[pi]:sub(ci, ci)
    end
    return table.concat(buf)
end
]]

local function splitInterleave(str)
    local chunks, order = {}, {}
    local i = 1
    while i <= #str do
        local len = math.random(1, 4)
        local chunk = str:sub(i, i + len - 1)
        chunks[#chunks+1] = chunk
        i = i + len
    end
    local shuffled = {}
    local idx = {}
    for k = 1, #chunks do idx[k] = k end
    util.shuffle(idx)
    for k, v in ipairs(idx) do shuffled[k] = chunks[v] end
    return shuffled, idx
end

local reversalMergeCode = [[
function MERGE_RV(a, b)
    local rb = {}
    for i = #b, 1, -1 do rb[#rb+1] = b:sub(i,i) end
    return a .. table.concat(rb)
end
]]

local function splitReversal(str)
    if #str < 2 then return str, "" end
    local mid  = math.random(1, #str - 1)
    local part1 = str:sub(1, mid)
    local part2 = str:sub(mid + 1)
    local rev = {}
    for i = #part2, 1, -1 do rev[#rev+1] = part2:sub(i,i) end
    return part1, table.concat(rev)
end

local function parseFuncDecl(code, parentScope)
    local parser = Parser:new({ LuaVersion = LuaVersion.Lua51 })
    local parsed = parser:parse(code)
    local decl   = parsed.body.statements[1]
    decl.body.scope:setParent(parentScope)
    return decl
end

function SplitStrings:apply(ast, pipeline)
    local scope     = ast.body.scope
    local mergeVars = {}

    local function getOrCreateMergeVar(method)
        if mergeVars[method] then return mergeVars[method] end
        local id = scope:addVariable()
        mergeVars[method] = id

        local code
        if method == "zigzag"    then code = zigzagMergeCode
        elseif method == "reversal" then code = reversalMergeCode
        else return nil end  -- interleave dihandle inline

        local decl = parseFuncDecl(code, scope)
        decl.scope = scope; decl.id = id
        table.insert(ast.body.statements, 1, decl)
        return id
    end

    local method = self.Method

    visitAst(ast, nil, function(node, data)
        if node.kind ~= Ast.AstKind.StringExpression then return end
        local str = node.value
        if #str < 2 then return end
        if math.random() > self.Threshold then return end

        local m = method
        if m == "random" then
            local methods = {"zigzag", "interleave", "reversal"}
            m = methods[math.random(1, #methods)]
        end

        if m == "zigzag" then
            local odd, even = splitZigzag(str)
            local vid = getOrCreateMergeVar("zigzag")
            if not vid then return end
            data.scope:addReferenceToHigherScope(scope, vid)
            return Ast.FunctionCallExpression(
                Ast.VariableExpression(scope, vid),
                { Ast.StringExpression(odd), Ast.StringExpression(even) }
            )

        elseif m == "reversal" then
            local p1, p2 = splitReversal(str)
            local vid = getOrCreateMergeVar("reversal")
            if not vid then return end
            data.scope:addReferenceToHigherScope(scope, vid)
            return Ast.FunctionCallExpression(
                Ast.VariableExpression(scope, vid),
                { Ast.StringExpression(p1), Ast.StringExpression(p2) }
            )

        elseif m == "interleave" then
            local chunks = {}
            local i = 1
            while i <= #str do
                local len = math.random(1, 4)
                chunks[#chunks+1] = str:sub(i, i + len - 1)
                i = i + len
            end
            util.shuffle(chunks)
            local expr = Ast.StringExpression(chunks[1])
            for k = 2, #chunks do
                expr = Ast.StrCatExpression(expr, Ast.StringExpression(chunks[k]))
            end
            local body = Ast.Block(data.scope)
            body.statements = { Ast.ReturnStatement({ expr }) }
            local literal = Ast.FunctionLiteralExpression({}, body)
            return Ast.FunctionCallExpression(literal, {})
        end
    end)
    return ast
end

return SplitStrings
