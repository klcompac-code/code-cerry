local Step       = require("prometheus.step")
local Ast        = require("prometheus.ast")
local Parser     = require("prometheus.parser")
local Enums      = require("prometheus.enums")
local visitast   = require("prometheus.visitast")
local util       = require("prometheus.util")
local logger     = require("logger")
local AstKind    = Ast.AstKind

local UrlProtect = Step:extend()
UrlProtect.Description = "Encrypts all https:// URLs in source (skip comments), runtime decrypt"
UrlProtect.Name        = "Url Protect"
UrlProtect.SettingsDescriptor = {
    EnableWebhook   = { type="boolean", default=false, description="Send webhook notification (DISABLED for Roblox)" },
    ValidateRuntime = { type="boolean", default=true,  description="Add runtime URL integrity check" },
    ErrorOnTamper   = { type="boolean", default=true,  description="Error with clear message if URL tampered" },
    SkipNonString   = { type="boolean", default=false, description="Skip URLs not inside string literals" },
}

function UrlProtect:init(_) end

-- [FIX] Implement XOR function untuk Roblox (tanpa bit32)
local function xor(a, b)
    local result = 0
    local bit = 1
    for _ = 1, 32 do
        local a_bit = a % 2
        local b_bit = b % 2
        if a_bit ~= b_bit then
            result = result + bit
        end
        a = (a - a_bit) / 2
        b = (b - b_bit) / 2
        bit = bit * 2
    end
    return result
end

local function xorEncrypt(str, key)
    local out = {}
    local klen = #key
    for i = 1, #str do
        local b = string.byte(str, i)
        local k = string.byte(key, ((i-1) % klen) + 1)
        out[i] = string.format("%02x", xor(b, k))
    end
    return table.concat(out)
end

local function makeKey(seed)
    local k = {}
    local s = seed
    for i = 1, 16 do
        s = (s * 1664525 + 1013904223) % (2^32)
        k[i] = string.char(32 + (s % 95))
    end
    return table.concat(k)
end

-- [FIX] Runtime code tanpa bit32, pakai XOR manual
local function genRuntimeCode(seed, urlMap)

    local function urlHash(url)
        local h = 5381
        for i = 1, #url do
            h = ((h * 33) + string.byte(url, i)) % (2^24)
        end
        return h
    end

    local hashLines = {}
    for enc, info in pairs(urlMap) do
        hashLines[#hashLines+1] = string.format(
            '    ["%s"] = %d',
            enc, urlHash(info.url)
        )
    end

    local hashTable = "{\n" .. table.concat(hashLines, ",\n") .. "\n}"

    -- [FIX] Implement XOR manual di runtime
    return string.format([[
do
    local _UP_SEED = %d
    local _UP_KEY_LEN = 16
    local _UP_CACHE = {}
    local _UP_HASHES = %s

    -- XOR implementation tanpa bit32
    local function _xor(a, b)
        local result = 0
        local bit = 1
        for _ = 1, 32 do
            local a_bit = a %% 2
            local b_bit = b %% 2
            if a_bit ~= b_bit then
                result = result + bit
            end
            a = (a - a_bit) / 2
            b = (b - b_bit) / 2
            bit = bit * 2
        end
        return result
    end

    local function _UP_DECRYPT(enc)
        if _UP_CACHE[enc] then return _UP_CACHE[enc] end

        local _k = {}
        local _s = _UP_SEED
        for _i = 1, _UP_KEY_LEN do
            _s = (_s * 1664525 + 1013904223) %% (2^32)
            _k[_i] = 32 + (_s %% 95)
        end

        local _out = {}
        local _ki = 1
        for _i = 1, #enc, 2 do
            local _byte = tonumber(enc:sub(_i, _i+1), 16)
            if not _byte then
                error("[URL_PROTECT] Invalid encrypted string: " .. enc, 2)
            end
            local _xb = _xor(_byte, string.byte(_k[_ki]))
            _out[#_out+1] = string.char(_xb)
            _ki = (_ki %% _UP_KEY_LEN) + 1
        end
        local _result = table.concat(_out)

        local _expected = _UP_HASHES[enc]
        if _expected then
            local _h = 5381
            for _i = 1, #_result do
                _h = ((_h * 33) + string.byte(_result, _i)) %% (2^24)
            end
            if _h ~= _expected then
                error("[URL_PROTECT] URL integrity check FAILED! URL may have been tampered.", 2)
            end
        end

        _UP_CACHE[enc] = _result
        return _result
    end

    _URL_DECRYPT = _UP_DECRYPT
end]], seed, hashTable)
end

function UrlProtect:apply(ast, pipeline)
    local source = pipeline.lastSource or ""
    local filename = pipeline.lastFilename or "unknown"

    if source == "" then
        logger:warn("[UrlProtect] No source in pipeline, skipping")
        return ast
    end

    logger:info("[UrlProtect] Scanning for URLs...")
    
    -- [FIX] Simple URL scanner (tanpa dependency)
    local urlList = {}
    for url in source:gmatch("https?://[%w%-%.%?%=&%/%:%%_%~%#%+%[%]@!%$%;%,%*%(%)]+") do
        -- Cari line number (approximate)
        local line = 1
        local pos = 1
        while true do
            local nl = source:find("\n", pos)
            if not nl or nl > (source:find(url, pos, true) or 0) then
                break
            end
            line = line + 1
            pos = nl + 1
        end
        table.insert(urlList, {
            url = url,
            line = line,
            varName = "unknown"
        })
    end

    -- Deduplicate
    local seen = {}
    local uniqueUrls = {}
    for _, u in ipairs(urlList) do
        if not seen[u.url] then
            seen[u.url] = true
            table.insert(uniqueUrls, u)
        end
    end
    urlList = uniqueUrls

    if #urlList == 0 then
        logger:info("[UrlProtect] No URLs found.")
        return ast
    end

    logger:info(string.format("[UrlProtect] %d URLs found", #urlList))

    local seed = math.random(100000, 999999)
    local key = makeKey(seed)
    local urlMap = {}

    local encByUrl = {}
    for _, u in ipairs(urlList) do
        if not encByUrl[u.url] then
            local enc = xorEncrypt(u.url, key)
            encByUrl[u.url] = enc
            urlMap[enc] = { url=u.url, varName=u.varName, line=u.line }
        end
    end

    local runtimeCode = genRuntimeCode(seed, urlMap)
    local ok, parsed = pcall(function()
        return Parser:new({ LuaVersion = Enums.LuaVersion.Lua51 }):parse(runtimeCode)
    end)

    if not ok then
        logger:error("[UrlProtect] Failed to parse runtime code: " .. tostring(parsed))
        return ast
    end

    local scope = ast.body.scope
    local decryptVar = scope:addVariable()

    local doStat = parsed.body.statements[1]
    if doStat and doStat.body then
        doStat.body.scope:setParent(scope)
    end

    visitast(parsed, nil, function(node, data)
        local function remap(name)
            if (node.kind == AstKind.AssignmentVariable or
                node.kind == AstKind.VariableExpression) then
                if node.scope and node.scope:getVariableName(node.id) == name then
                    data.scope:removeReferenceToHigherScope(node.scope, node.id)
                    data.scope:addReferenceToHigherScope(scope, decryptVar)
                    node.scope = scope
                    node.id = decryptVar
                end
            end
        end
        remap("_URL_DECRYPT")
    end)

    local replaceCount = 0
    visitast(ast, nil, function(node, data)
        if node.kind ~= AstKind.StringExpression then return end
        local val = node.value
        if not val:match("^https?://") then return end

        local enc = encByUrl[val]
        if not enc then return end

        data.scope:addReferenceToHigherScope(scope, decryptVar)
        replaceCount = replaceCount + 1
        
        return Ast.FunctionCallExpression(
            Ast.VariableExpression(scope, decryptVar),
            { Ast.StringExpression(enc) }
        )
    end)

    logger:info(string.format("[UrlProtect] %d URLs encrypted and replaced.", replaceCount))

    table.insert(ast.body.statements, 1, doStat)
    table.insert(ast.body.statements, 1,
        Ast.LocalVariableDeclaration(scope, { decryptVar }, {}))

    return ast
end

return UrlProtect