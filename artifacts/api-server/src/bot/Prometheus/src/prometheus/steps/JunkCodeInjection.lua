
local Step     = require("prometheus.step")
local Ast      = require("prometheus.ast")
local Parser   = require("prometheus.parser")
local Enums    = require("prometheus.enums")
local visitast = require("prometheus.visitast")
local util     = require("prometheus.util")
local AstKind  = Ast.AstKind

local JunkCodeInjection = Step:extend()
JunkCodeInjection.Description = "Injects non-functional junk code blocks to confuse analysis"
JunkCodeInjection.Name        = "Junk Code Injection"
JunkCodeInjection.SettingsDescriptor = {
    Density    = { type="number", default=0.35, min=0.05, max=0.8 },
    MaxPerBlock = { type="number", default=3, min=1, max=8 },
}

function JunkCodeInjection:init(_) end

local function makeJunk()
    local templates = {
        function()
            local a = math.random(1,999); local b = math.random(1,999)
            local ops = {"+","-","*"}
            local op = ops[math.random(#ops)]
            return string.format("do local _j%d = %d %s %d end", math.random(9999), a, op, b)
        end,
        function()
            local words = {"hello","world","data","key","val","tmp","buf","res"}
            local w1 = words[math.random(#words)]; local w2 = words[math.random(#words)]
            return string.format('do local _s%d = "%s" .. "%s" end', math.random(9999), w1, w2)
        end,
        function()
            local n = math.random(2,5)
            local vals = {}
            for i=1,n do vals[i]=tostring(math.random(1,999)) end
            return string.format("do local _t%d = {%s} end", math.random(9999), table.concat(vals,","))
        end,
        function()
            local n = math.random(2,4)
            return string.format(
                "do local _acc%d=0; for _i=1,%d do _acc%d=_acc%d+_i end end",
                math.random(9999), n, math.random(9999), math.random(9999))
        end,
        function()
            local n = math.random(2,50)
            return string.format(
                "do if %d > 0 then local _nop%d = nil end end",
                n, math.random(9999))
        end,
        function()
            local a=math.random(1,99); local b=math.random(1,99)
            return string.format(
                "do do local _x%d=%d local _y%d=%d local _z%d=_x%d+_y%d end end",
                math.random(9999),a,math.random(9999),b,math.random(9999),math.random(9999),math.random(9999))
        end,
    }
    return templates[math.random(#templates)]()
end

function JunkCodeInjection:apply(ast, _)
    local parser = Parser:new({ LuaVersion = Enums.LuaVersion.Lua51 })

    visitast(ast, nil, function(node, data)
        if node.kind ~= AstKind.Block then return end
        if math.random() > self.Density then return end

        local count = math.random(1, self.MaxPerBlock)
        for _ = 1, count do
            local code = makeJunk()
            local ok, parsed = pcall(function() return parser:parse(code) end)
            if ok then
                local doStat = parsed.body.statements[1]
                doStat.body.scope:setParent(data.scope)
                local pos = math.random(1, math.max(1, #node.statements + 1))
                table.insert(node.statements, pos, doStat)
            end
        end
    end)
    return ast
end

return JunkCodeInjection
