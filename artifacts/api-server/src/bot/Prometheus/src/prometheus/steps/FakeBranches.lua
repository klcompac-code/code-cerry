local Step     = require("prometheus.step")
local Ast      = require("prometheus.ast")
local Parser   = require("prometheus.parser")
local Enums    = require("prometheus.enums")
local visitast = require("prometheus.visitast")
local util     = require("prometheus.util")
local AstKind  = Ast.AstKind

local FakeBranches = Step:extend()
FakeBranches.Description = "Injects fake require, fake branches, and misleading logic"
FakeBranches.Name        = "Fake Branches"
FakeBranches.SettingsDescriptor = {
    FakeBranchThreshold  = { type="number", default=0.4, min=0, max=1 },
    FakeRequireCount     = { type="number", default=3,   min=0, max=10 },
    MisleadingLogicCount = { type="number", default=3,   min=0, max=8 },
}
function FakeBranches:init(_) end

-- [FIX] Safe string escape untuk digunakan dalam kode Lua
local function escapeLuaString(str)
    -- Escape backslash, single quote, double quote, newline, and percent
    return str:gsub("\\", "\\\\"):gsub("'", "\\'"):gsub('"', '\\"'):gsub("\n", "\\n")
end

-- [FIX] Safe module name untuk require (tanpa karakter berbahaya)
local function sanitizeModuleName(mod)
    -- Hanya izinkan alphanumeric, underscore, dot, dash
    return mod:gsub("[^%w_%.%-]", "")
end

local function generateRandomModuleName()
    local prefixes = { "sys", "net", "lib", "core", "util", "data", "cfg", "env" }
    local suffixes = { "loader", "init", "cache", "crypto", "handler", "base" }
    local connectors = { ".", "_", "-" }
    
    local prefix = prefixes[math.random(#prefixes)]
    local suffix = suffixes[math.random(#suffixes)]
    local connector = connectors[math.random(#connectors)]
    
    if math.random() < 0.3 then
        return sanitizeModuleName(prefix .. connector .. suffix .. tostring(math.random(1, 99)))
    end
    return sanitizeModuleName(prefix .. connector .. suffix)
end

local function generateRandomString(length)
    length = length or math.random(6, 16)
    local chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
    local result = {}
    for i = 1, length do
        result[i] = chars:sub(math.random(1, #chars), math.random(1, #chars))
    end
    return table.concat(result)
end

local function generateRandomVarName()
    local prefixes = { "_", "v", "k", "x", "y", "z", "tmp", "var", "val", "data" }
    local prefix = prefixes[math.random(#prefixes)]
    return prefix .. generateRandomString(math.random(4, 10))
end

local function getFakeModules()
    local modules = {}
    local used = {}
    for i = 1, 16 do
        local mod
        repeat
            mod = generateRandomModuleName()
        until not used[mod]
        used[mod] = true
        modules[i] = mod
    end
    return modules
end

local function randomHex(n)
    local t = {}
    local hexChars = "0123456789abcdef"
    for i = 1, n do 
        t[i] = hexChars:sub(math.random(1, 16), math.random(1, 16))
    end
    return table.concat(t)
end

local function getMisleadNames()
    local names = {}
    local prefixes = { "_k", "_c", "_h", "_t", "_s", "_n", "_i", "_m" }
    for i = 1, 12 do
        names[i] = prefixes[math.random(#prefixes)] .. generateRandomString(math.random(3, 8))
    end
    return names
end

-- [FIX] Safe XOR function
local function xor2(a, b)
    local r, m = 0, 1
    for i = 1, 24 do
        local x, y = a % 2, b % 2
        if x ~= y then r = r + m end
        a, b, m = (a - x) / 2, (b - y) / 2, m * 2
    end
    return r
end

-- [FIX] Safe escape untuk string di kode Lua
local function escapeForLuaString(str)
    return str:gsub("\\", "\\\\"):gsub('"', '\\"'):gsub("\n", "\\n"):gsub("\r", "\\r")
end

-- [FIX] Fake require - aman untuk parsing
local function genFakeRequire(modules, names)
    local mod = modules[math.random(#modules)]
    local var = names[math.random(#names)] .. math.random(10, 99)
    local val1 = math.random(1000, 9999)
    local val2 = randomHex(8)
    -- Ensure module name is safe
    local safeMod = sanitizeModuleName(mod)
    return string.format([[
do
    local %s
    local _ok_%d = pcall(function()
        %s = require("%s")
    end)
    if not _ok_%d then
        %s = {_v=%d, _id="%s", _ok=false}
    end
end
]], var, val1, var, safeMod, val1, var, val1, val2)
end

-- [FIX] Fake branch dengan kondisi 100% aman
local function genFakeBranch(names)
    local hex = randomHex(8)
    local deadVar = names[math.random(#names)] .. math.random(10, 99)
    
    -- Kondisi yang selalu FALSE (tidak pernah dieksekusi)
    local conditions = {
        "false",
        "1 == 0",
        "2 == 3",
        "nil == true",
        "type({}) == 'string'",
    }
    local cond = conditions[math.random(#conditions)]
    
    return string.format([[
do
    if %s then
        local %s = "%s"
        for _di = 1, #%s do
            %s = %s:sub(1, _di)
        end
    end
end
]], cond, deadVar, hex, deadVar, deadVar, deadVar)
end

-- [FIX] Misleading logic tanpa karakter berbahaya
local function genMisleadingLogic(names)
    local templates = {
        function()
            local a = math.random(1, 255)
            local b = math.random(1, 255)
            local c = (a + b) % 256
            local vn = names[math.random(#names)] .. math.random(10, 99)
            return string.format("do local %s = (%d + %d) %% 256 == %d end\n", vn, a, b, c)
        end,
        function()
            local vn = names[math.random(#names)] .. math.random(10, 99)
            return string.format("do local %s = {} for i=1,5 do %s[i]=i end end\n", vn, vn)
        end,
        function()
            local n = math.random(3, 6)
            local states = {}
            for i = 1, n do 
                states[i] = math.random(100, 999) 
            end
            local vn = names[math.random(#names)] .. math.random(10, 99)
            local idx = math.random(1, n)
            return string.format("do local %s = {%s} local _idx=%d _=%s[_idx] end\n", 
                vn, table.concat(states, ","), idx, vn)
        end,
        function()
            local vn = names[math.random(#names)] .. math.random(10, 99)
            local len = math.random(5, 15)
            return string.format("do local %s = string.rep('a', %d) end\n", vn, len)
        end,
    }
    return templates[math.random(#templates)]()
end

function FakeBranches:apply(ast, _)
    -- Inisialisasi random seed
    math.randomseed(os.time())
    for _ = 1, math.random(10, 100) do math.random() end
    
    local fakeModules = getFakeModules()
    local misleadNames = getMisleadNames()
    local parser = Parser:new({ LuaVersion = Enums.LuaVersion.Lua51 })

    local function insertBlock(code, pos, targetScope)
        local ok, parsed = pcall(function() return parser:parse(code) end)
        if not ok then return end
        if not parsed or not parsed.body then return end
        local doStat = parsed.body.statements[1]
        if not doStat then return end
        if doStat.body and doStat.body.scope then
            doStat.body.scope:setParent(targetScope or ast.body.scope)
        end
        -- Ensure position is valid
        local insertPos = math.min(pos, #ast.body.statements + 1)
        insertPos = math.max(1, insertPos)
        table.insert(ast.body.statements, insertPos, doStat)
    end

    -- Insert fake requires
    for i = 1, self.FakeRequireCount do
        insertBlock(genFakeRequire(fakeModules, misleadNames), i)
    end

    -- Insert misleading logic
    for i = 1, self.MisleadingLogicCount do
        local pos = math.random(1, math.max(1, #ast.body.statements))
        insertBlock(genMisleadingLogic(misleadNames), pos)
    end

    -- Insert fake branches in blocks
    visitast(ast, nil, function(node, data)
        if node.kind ~= AstKind.Block then return end
        if math.random() > self.FakeBranchThreshold then return end
        if not node.statements or #node.statements == 0 then return end

        local code = genFakeBranch(misleadNames)
        local ok, parsed = pcall(function() return parser:parse(code) end)
        if not ok then return end
        local doStat = parsed.body.statements[1]
        if doStat and doStat.body and doStat.body.scope then
            doStat.body.scope:setParent(data.scope or ast.body.scope)
        end
        local pos = math.random(1, #node.statements)
        table.insert(node.statements, pos, doStat)
    end)

    return ast
end

return FakeBranches