-- ============================================================================
-- MOCK FAKE FUNCTION LIBRARY — Common Roblox/Executor Functions
-- For testing & deobfuscation analysis
-- ============================================================================

-- Library / Global yang umum
-- KRNL / Synapse / Delta:
getgenv = getgenv or function() return _G end
getrenv = getrenv or function() return _G end
getfenv = getfenv or function(level) return _G end
setfenv = setfenv or function(f, env) return f end
getgc = getgc or function(include_threads) return {} end
getreg = getreg or function() return {} end
getinstances = getinstances or function() return {} end
getnilinstances = getnilinstances or function() return {} end
getscripts = getscripts or function() return {} end
getcallingscript = getcallingscript or function() return nil end
getrunningscripts = getrunningscripts or function() return {} end
gethui = gethui or function() return {} end
gethiddenui = gethiddenui or function() return {} end
getrawmetatable = getrawmetatable or function(obj) return getmetatable(obj) or {} end
setrawmetatable = setrawmetatable or function(obj, mt) return setmetatable(obj, mt) end
hookfunction = hookfunction or function(old, new) return old end
hookmetamethod = hookmetamethod or function(obj, method, hook) return old end
newcclosure = newcclosure or function(f) return f end
newlclosure = newlclosure or function(f) return f end
iscclosure = iscclosure or function(f) return false end
islclosure = islclosure or function(f) return true end
checkcaller = checkcaller or function() return true end
isnetworkowner = isnetworkowner or function() return true end
fireclickdetector = fireclickdetector or function(detector, distance) return end
fireproximityprompt = fireproximityprompt or function(prompt, distance) return end
firetouchinterest = firetouchinterest or function(part1, part2, touch) return end
firesignal = firesignal or function(signal, ...) return end
queue_on_teleport = queue_on_teleport or function(script) end
queueonteleport = queueonteleport or queue_on_teleport
setclipboard = setclipboard or function(text) end
getclipboard = getclipboard or function() return "" end
request = request or function(options) end
http_request = http_request or request
HttpPost = HttpPost or function(url, data, headers) return request({Url = url, Method = "POST", Body = data, Headers = headers}) end
syn_request = syn_request or request
identifyexecutor = identifyexecutor or function() return "Lua Interpreter (Mock)" end
getexecutorname = getexecutorname or function() return "Standalone Lua" end
getexecutorversion = getexecutorversion or function() return "5.1/5.3/5.4" end

-- KRNL Specific
krnl = krnl or {}
krnl.load_file = krnl.load_file or function(path) end
krnl.load_bytes = krnl.load_bytes or function(bytes) end
krnl.get_script_bytecode = krnl.get_script_bytecode or function(script) end
krnl.decompile = krnl.decompile or function(func) end

-- Delta Specific
delta = delta or {}
delta.loadfile = delta.loadfile or function(path) end
delta.dumpfunction = delta.dumpfunction or function(func) end

-- ScriptWare Specific
scriptware = scriptware or {}
scriptware.loadfile = scriptware.loadfile or function(path) end
scriptware.http = scriptware.http or {}
scriptware.http.get = scriptware.http.get or function(url) end
scriptware.http.post = scriptware.http.post or function(url, data) end

readfile = readfile or function(path)
    local f = io.open(path, "r")
    if not f then return nil end
    local content = f:read("*all")
    f:close()
    return content
end

writefile = writefile or function(path, content)
    local f = io.open(path, "w")
    if not f then return false end
    f:write(content)
    f:close()
    return true
end

appendfile = appendfile or function(path, content)
    local f = io.open(path, "a")
    if not f then return false end
    f:write(content)
    f:close()
    return true
end

loadfile = loadfile or function(path)
    local content = readfile(path)
    if not content then return nil, "File not found" end
    return load(content, "@" .. path)
end

listfiles = listfiles or function(path)
    local files = {}
    local p = io.popen('ls -la "' .. (path or ".") .. '" 2>/dev/null')
    if not p then return {} end
    for line in p:lines() do
        table.insert(files, line)
    end
    p:close()
    return files
end

isfile = isfile or function(path)
    local f = io.open(path, "r")
    if f then f:close(); return true end
    return false
end

isfolder = isfolder or function(path)
    local f = io.open(path, "r")
    if f then f:close(); return false end
    return false
end

makefolder = makefolder or function(path)
    return isfolder(path)
end

delfolder = delfolder or function(path)
    return not isfolder(path)
end

delfile = delfile or function(path)
    return not isfile(path)
end

dofile = dofile or function(path)
    local fn, err = loadfile(path)
    if not fn then error(err) end
    return fn()
end

getworkspace = getworkspace or function()
    return os.getenv("PWD") or "."
end

saveinstance = saveinstance or function(path)
    return writefile(path, "-- Instance saved at " .. os.date())
end

-- Mouse
mouse1click = mouse1click or function() return end
mouse2click = mouse2click or function() return end
mouse1press = mouse1press or function() return end
mouse1release = mouse1release or function() return end
mouse2press = mouse2press or function() return end
mouse2release = mouse2release or function() return end
keypress = keypress or function(key) return end
keyrelease = keyrelease or function(key) return end
keyclick = keyclick or function(key) return end
mousemoveabs = mousemoveabs or function(x, y) return end
mousemoverel = mousemoverel or function(x, y) return end
mousescroll = mousescroll or function(amount) return end

-- Window/Game
isrbxactive = isrbxactive or function() return true end
iswindowactive = iswindowactive or function() return true end
isgameactive = isgameactive or function() return true end
setwindowactive = setwindowactive or function() return end

-- Drawing
Drawing = Drawing or {}
Drawing.new = Drawing.new or function(typ) return {} end
Drawing.Fonts = Drawing.Fonts or {}
Drawing.Colors = Drawing.Colors or {}

-- Console
rconsoleprint = rconsoleprint or function(...) print(...) end
rconsoleclear = rconsoleclear or function() end
rconsolecreate = rconsolecreate or function() return {} end
rconsoledestroy = rconsoledestroy or function() end
rconsoleinput = rconsoleinput or function() return "" end
rconsoleinfo = rconsoleinfo or rconsoleprint
rconsolewarn = rconsolewarn or rconsoleprint
rconsoleerr = rconsoleerr or rconsoleprint
rconsolename = rconsolename or function(name) end
rconsolesettitle = rconsolesettitle or function(title) end

-- Crypt library
crypt = crypt or {}
crypt.encrypt = crypt.encrypt or function(data, key) return data end
crypt.decrypt = crypt.decrypt or function(data, key) return data end
crypt.hash = crypt.hash or function(data) return data end
crypt.base64 = crypt.base64 or {}

base64_encode = base64_encode or function(data) return data end
base64_decode = base64_decode or function(data) return data end
base64encode = base64encode or base64_encode
base64decode = base64decode or base64_decode

lz4compress = lz4compress or function(data) return data end
lz4decompress = lz4decompress or function(data) return data end

-- Game services (mock)
game = game or {}
game.GetService = game.GetService or function(self, name) return {} end

workspace = workspace or game
Players = Players or game
Lighting = Lighting or game
ReplicatedStorage = ReplicatedStorage or game
ReplicatedFirst = ReplicatedFirst or game
ServerStorage = ServerStorage or game
ServerScriptService = ServerScriptService or game
StarterPlayer = StarterPlayer or game
StarterGui = StarterGui or game
StarterPack = StarterPack or game
Teams = Teams or game
SoundService = SoundService or game
Chat = Chat or game
TextChatService = TextChatService or game
UserInputService = UserInputService or game
ContextActionService = ContextActionService or game
RunService = RunService or game
TweenService = TweenService or game
Debris = Debris or game
InsertService = InsertService or game
TeleportService = TeleportService or game
HttpService = HttpService or game
MarketplaceService = MarketplaceService or game
PathfindingService = PathfindingService or game
CollectionService = CollectionService or game

-- Instance utilities
Instance = Instance or {}
Instance.new = Instance.new or function(className) return {} end

-- Metatable operations
clonefunction = clonefunction or function(f) return f end
restorefunction = restorefunction or function(f) return f end
replaceclosure = replaceclosure or function(old, new) return new end
ishooked = ishooked or function(f) return false end
getnamecallmethod = getnamecallmethod or function() return nil end
setnamecallmethod = setnamecallmethod or function(method) return end

getconstants = getconstants or function(f) return {} end
getconstant = getconstant or function(f, idx) return nil end
setconstant = setconstant or function(f, idx, value) return end

getupvalues = getupvalues or function(f) return {} end
getupvalue = getupvalue or function(f, idx) return nil, nil end
setupvalue = setupvalue or function(f, idx, value) return nil end

getproto = getproto or function(f, idx) return nil end
getprotos = getprotos or function(f) return {} end
setproto = setproto or function(f, idx, proto) return end

getstack = getstack or function(f, idx) return nil end
setstack = setstack or function(f, idx, value) return end

getinfo = getinfo or function(f) return debug.getinfo(f) end
decompile = decompile or function(f) return "-- Cannot decompile in standalone Lua" end

dump_string = dump_string or function(str) return string.dump(load(str)) end
dump_file = dump_file or function(path) return nil end
dumpstring = dumpstring or dump_string

-- Synapse
syn = syn or {}
syn.request = syn.request or request
syn.websocket = syn.websocket or {}

-- Cache
cache = cache or {}
cache.invalidate = cache.invalidate or function() end
cache.iscached = cache.iscached or function() return false end
cache.replacecache = cache.replacecache or function() end

invalidate = cache.invalidate
iscached = cache.iscached
replacecache = cache.replacecache

setfflag = setfflag or function(flag, value) return end
getfflag = getfflag or function(flag) return nil end
settflag = settflag or function(flag, value) return end
setfpscap = setfpscap or function(fps) return end
getfpscap = getfpscap or function() return 60 end

setscriptable = setscriptable or function(instance, prop, bool) return end
getscriptable = getscriptable or function(instance, prop) return true end
isscriptable = isscriptable or function(instance, prop) return true end

setrenderproperty = setrenderproperty or function(instance, prop, value) return end
getrenderproperty = getrenderproperty or function(instance, prop) return nil end

gethiddenproperty = gethiddenproperty or function(instance, prop) return nil end
sethiddenproperty = sethiddenproperty or function(instance, prop, value) return end
getproperties = getproperties or function(instance) return {} end

getcustomasset = getcustomasset or function(id) return id end
getsynasset = getsynasset or getcustomasset

getconnections = getconnections or function(signal) return {} end
setsimulationradius = setsimulationradius or function(radius) return end
getsimulationradius = getsimulationradius or function() return 500 end

cloneref = cloneref or function(instance) return instance end
compareinstances = compareinstances or function(a, b) return a == b end
isvalidinstance = isvalidinstance or function(instance) return instance ~= nil end
validcheck = isvalidinstance

secure_call = secure_call or function(f, ...) return f(...) end
create_secure_function = create_secure_function or function(f) return f end

-- Bit operations
bit = bit or {}
bit.bxor = bit.bxor or function(a, b) return a end
bit.band = bit.band or function(a, b) return a end
bit.bor = bit.bor or function(a, b) return a end

-- HTTP library
http = http or {}
http.get = http.get or function(url) end
http.post = http.post or function(url, data) end

-- WebSocket library
websocket = websocket or nil

-- Protect GUI
protect_gui = protect_gui or function(gui) return end
unprotect_gui = unprotect_gui or function(gui) return end
protectgui = protect_gui
unprotectgui = unprotect_gui

-- Make readable/writeable
make_writeable = make_writeable or function(t) return t end
make_readonly = make_readonly or function(t) return t end
setreadonly = setreadonly or function(t, readonly) return end
isreadonly = isreadonly or function(t) return false end

print("[MOCK FUNCTIONS] Fake executor library loaded successfully")
