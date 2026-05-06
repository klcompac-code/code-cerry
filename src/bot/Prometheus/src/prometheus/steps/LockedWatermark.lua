-- LockedWatermark.lua  (Prometheus Upgrade Layer)
--
-- Watermark muncul sebagai komentar di baris pertama output:
--   --[[ BY-BASIC-OR-HAGGAICC:1528610281 ]]
--
-- PROTEKSI:
--   1. Hash komentar = seed sbox/alpha CompressPayload → hapus komentar = decode junk
--   2. Hash juga di-validasi runtime via arithmetic murni (no debug lib)
--      → tidak bisa dihapus dari dalam kode tanpa merusak validasi
--   3. Content watermark di-embed sebagai byte array (tidak ada string literal
--      "BY-BASIC-OR-HAGGAICC" di dalam kode yang bisa di-grep)

local Step          = require("prometheus.step")
local Parser        = require("prometheus.parser")
local Enums         = require("prometheus.enums")
local RandomStrings = require("prometheus.randomStrings")
local logger        = require("logger")

local LockedWatermark      = Step:extend()
LockedWatermark.Name        = "Locked Watermark"
LockedWatermark.Description = "Watermark komentar dikunci ke payload. Hapus/ubah = script mati."

LockedWatermark.SettingsDescriptor = {
    Content = {
        name = "Content", type = "string", default = "BY-BASIC-OR-HAGGAICC",
        description = "watermark huhuhu.",
    },
}

function LockedWatermark:init(settings) end

-- Constants (harus identik antara build-time dan runtime)
local WM_POLY = 1000033
local WM_STEP = 1009
local WM_BIAS = 97
local WM_MOD  = 2147483647
local WM_INIT = 1356711  -- 0x14B3A7

local function wmHash(s)
    local h = WM_INIT
    for _ = 1, 3 do
        for i = 1, #s do
            h = (h * WM_POLY + s:byte(i) * WM_STEP + WM_BIAS) % WM_MOD
        end
        h = (h + math.floor(h / 65536)) % WM_MOD
    end
    return h
end

function LockedWatermark:apply(ast, pipeline)
    local content = self.Content
    local hash    = wmHash(content)

    -- Simpan ke pipeline untuk CompressPayload
    pipeline._wmHash    = hash
    pipeline._wmContent = content

    -- Split hash ke 3 bagian kecil
    local hA = hash % 10000
    local hB = math.floor(hash / 10000) % 10000
    local hC = math.floor(hash / 100000000)

    -- Byte sum content sebagai check kedua
    local byteSum = 0
    for i = 1, #content do byteSum = byteSum + content:byte(i) end

    -- Embed content sebagai byte array (tidak ada string literal)
    local contentBytes = {}
    for i = 1, #content do
        contentBytes[#contentBytes+1] = tostring(content:byte(i))
    end
    local byteLit = "{" .. table.concat(contentBytes, ",") .. "}"
    local cLen = #content

    -- Random var prefix
    local px  = "_lw" .. tostring(math.random(1000, 9999)) .. "_"

    -- Build guard: 3 separate for loops matching wmHash logic exactly
    -- Semua aritmatika murni, tidak ada string concat di runtime
    local lines = {
        "do",
        -- reconstruct expected from split parts
        string.format("local %sA=%d", px, hA),
        string.format("local %sB=%d", px, hB),
        string.format("local %sC=%d", px, hC),
        string.format("local %sE=%sC*100000000+%sB*10000+%sA", px,px,px,px),
        -- embed content as byte table
        string.format("local %sT=%s", px, byteLit),
        -- byte sum check
        string.format("local %sS=0", px),
        string.format("for %si=1,#%sT do %sS=%sS+%sT[%si] end", px,px, px,px,px,px),
        string.format("if %sS~=%d then return end", px, byteSum),
        -- compute hash: 3 rounds
        string.format("local %sH=%d", px, WM_INIT),
        -- round 1
        string.format("for %si=1,#%sT do", px, px),
        string.format("%sH=(%sH*%d+%sT[%si]*%d+%d)%%%d",
            px,px,WM_POLY,px,px,WM_STEP,WM_BIAS,WM_MOD),
        "end",
        string.format("%sH=(%sH+math.floor(%sH/65536))%%%d", px,px,px,WM_MOD),
        -- round 2
        string.format("for %si=1,#%sT do", px, px),
        string.format("%sH=(%sH*%d+%sT[%si]*%d+%d)%%%d",
            px,px,WM_POLY,px,px,WM_STEP,WM_BIAS,WM_MOD),
        "end",
        string.format("%sH=(%sH+math.floor(%sH/65536))%%%d", px,px,px,WM_MOD),
        -- round 3
        string.format("for %si=1,#%sT do", px, px),
        string.format("%sH=(%sH*%d+%sT[%si]*%d+%d)%%%d",
            px,px,WM_POLY,px,px,WM_STEP,WM_BIAS,WM_MOD),
        "end",
        string.format("%sH=(%sH+math.floor(%sH/65536))%%%d", px,px,px,WM_MOD),
        -- final check
        string.format("if %sH~=%sE then return end", px, px),
        "end",
    }

    local guardSrc = table.concat(lines, "\n")

    local parser = Parser:new({ LuaVersion = Enums.LuaVersion.Lua51 })
    local ok, guardAst = pcall(function()
        return parser:parse(guardSrc)
    end)

    if not ok then
        logger:warn("LockedWatermark: guard parse failed: " .. tostring(guardAst))
        return
    end

    local doStat = guardAst.body.statements[1]
    if not (doStat and doStat.body and doStat.body.scope) then
        logger:warn("LockedWatermark: unexpected AST structure")
        return
    end

    doStat.body.scope:setParent(ast.body.scope)
    doStat.body.scope:rewireScope(ast.globalScope, guardAst.globalScope)
    table.insert(ast.body.statements, 1, doStat)

    logger:info(string.format(
        "LockedWatermark: '%s' hash=%d split=(%d|%d|%d) byteSum=%d",
        content, hash, hA, hB, hC, byteSum
    ))
end

return LockedWatermark
