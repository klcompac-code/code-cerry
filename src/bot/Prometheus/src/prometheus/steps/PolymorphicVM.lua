local Step   = require("prometheus.step")
local Parser = require("prometheus.parser")
local Enums  = require("prometheus.enums")
local Ast    = require("prometheus.ast")
local util   = require("prometheus.util")
local logger = require("logger")

local PolymorphicVM = Step:extend()
PolymorphicVM.Description = "Per-build opcode randomization: every build produces unique VM opcodes"
PolymorphicVM.Name        = "Polymorphic VM"
PolymorphicVM.SettingsDescriptor = {
    InjectMiniVM = { type="boolean", default=true,  description="Inject a small polymorphic mini-VM for constant operations" },
    OpcodeCount  = { type="number",  default=16,    min=8, max=32 },
}

function PolymorphicVM:init(_) end

local function genOpcodes(n)
    local ops = {}
    local used = {}
    local i = 0
    while i < n do
        local v = math.random(1, 255)
        if not used[v] then
            used[v] = true
            i = i + 1
            ops[i] = v
        end
    end
    return ops
end

local OP_NAMES = {
    "LOAD_K", "LOAD_NUM", "LOAD_BOOL", "LOAD_NIL",
    "ADD", "SUB", "MUL", "DIV", "MOD", "POW",
    "CONCAT", "NOT", "NEG", "LEN",
    "MOVE", "RETURN",
}

function PolymorphicVM:apply(ast, _)
    if not self.InjectMiniVM then return ast end

    local n    = math.min(self.OpcodeCount, #OP_NAMES)
    local vals = genOpcodes(n)

    local opMap = {}
    for i = 1, n do
        opMap[OP_NAMES[i]] = vals[i]
    end

    local vmVarNames = {
        vm  = "_VM"  .. math.random(1000, 9999),
        run = "_RUN" .. math.random(1000, 9999),
        op  = "_OP"  .. math.random(1000, 9999),
    }

    -- BUILD STRING MANUALLY (no string.format for the VM body)
    local vmTableLines = {
        "    local " .. vmVarNames.vm .. " = {",
        "        [" .. opMap.LOAD_K .. "] = function(r,a) r[a[2]] = a[3] end,",
        "        [" .. opMap.LOAD_NUM .. "] = function(r,a) r[a[2]] = a[3] + 0 end,",
        "        [" .. opMap.LOAD_BOOL .. "] = function(r,a) r[a[2]] = a[3] == 1 end,",
        "        [" .. opMap.LOAD_NIL .. "] = function(r,a) r[a[2]] = nil end,",
        "        [" .. opMap.ADD .. "] = function(r,a) r[a[2]] = r[a[3]] + r[a[4]] end,",
        "        [" .. opMap.SUB .. "] = function(r,a) r[a[2]] = r[a[3]] - r[a[4]] end,",
        "        [" .. opMap.MUL .. "] = function(r,a) r[a[2]] = r[a[3]] * r[a[4]] end,",
        "        [" .. opMap.DIV .. "] = function(r,a) r[a[2]] = r[a[3]] / r[a[4]] end,",
        "        [" .. opMap.MOD .. "] = function(r,a) r[a[2]] = r[a[3]] % r[a[4]] end,",  -- Single % for modulus
        "        [" .. opMap.POW .. "] = function(r,a) r[a[2]] = r[a[3]] ^ r[a[4]] end,",
        "        [" .. opMap.CONCAT .. "] = function(r,a) r[a[2]] = r[a[3]] .. r[a[4]] end,",
        "        [" .. opMap.NOT .. "] = function(r,a) r[a[2]] = not r[a[3]] end,",
        "        [" .. opMap.NEG .. "] = function(r,a) r[a[2]] = -r[a[3]] end,",
        "        [" .. opMap.LEN .. "] = function(r,a) r[a[2]] = #r[a[3]] end,",
        "        [" .. opMap.MOVE .. "] = function(r,a) r[a[2]] = r[a[3]] end,",
        "        [" .. opMap.RETURN .. "] = function(r,a) return r[a[2]] end,",
        "    }",
    }

    local runFuncLines = {
        "    local function " .. vmVarNames.run .. "(prog)",
        "        local _r = {}",
        "        for _i = 1, #prog do",
        "            local _a = prog[_i]",
        "            local _h = " .. vmVarNames.vm .. "[_a[1]]",
        "            if _h then",
        "                local _res = _h(_r, _a)",
        "                if _a[1] == " .. opMap.RETURN .. " then return _res end",
        "            end",
        "        end",
        "        return _r[1]",
        "    end",
    }

    local assignLines = {
        "    " .. vmVarNames.run .. " = " .. vmVarNames.run,
        "end",
    }

    -- Assemble complete code
    local codeLines = { "do" }
    for _, line in ipairs(vmTableLines) do table.insert(codeLines, line) end
    for _, line in ipairs(runFuncLines) do table.insert(codeLines, line) end
    for _, line in ipairs(assignLines) do table.insert(codeLines, line) end

    local code = table.concat(codeLines, "\n")

    -- Inject into AST
    local scope = ast.body.scope
    local ok, parsed = pcall(function()
        return Parser:new({ LuaVersion = Enums.LuaVersion.Lua51 }):parse(code)
    end)
    if not ok then
        logger:warn("[PolymorphicVM] parse failed: " .. tostring(parsed))
        return ast
    end

    local doStat = parsed.body.statements[1]
    if doStat and doStat.body then
        doStat.body.scope:setParent(scope)
    end
    table.insert(ast.body.statements, 1, doStat)

    logger:info(string.format("[PolymorphicVM] Generated VM with %d randomized opcodes. LOAD_K=%d ADD=%d RETURN=%d",
        n, opMap.LOAD_K, opMap.ADD, opMap.RETURN))

    return ast
end

return PolymorphicVM