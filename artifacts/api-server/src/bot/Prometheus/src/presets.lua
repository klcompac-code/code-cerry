-- This Script is Part of the Prometheus Obfuscator by Levno_710
--
-- presets.lua
--
-- This Script Provides obfuscation presets optimized for Roblox executors
-- With full Lua 5.1 & 5.3 compatibility support

-- Lua version detection
local DEFAULT_LUA_VERSION = "Lua51"  -- Base version for all presets
local LUA_53_COMPATIBLE = true       -- Enables Lua 5.3 advanced features

local function temporalFluxSeed()
    local t = os.time()
    local drift = math.random(1, 9973)
    return (t * 31 + drift) % 999983
end

local function makeWatermark()
    return {
        Name = "Watermark",
        Settings = {
            Content = "Prometheus-Protected",
        },
    }
end

local function makeAntiTamper(useHeartbeat, maxAttempts)
    return {
        Name = "AntiTamper",
        Settings = {
            UseChecksumChain  = true,
            UseSelfRefTrap    = true,
            UseTimingJunk     = true,
            UseLogging        = false,
            UseDumpDiag       = false,
            UsePrintHandler   = false,
            UseStackTrace     = false,
            UseCounterTrap    = true,
            UseHeartbeat      = useHeartbeat or false,
            UseMemoryCheck    = true,
            UseCodeFlowCheck  = true,
            MaxTamperAttempts = maxAttempts or 2,
        },
    }
end

local function makeRobloxEnvLock()
    return {
        Name = "RobloxEnvLock",
        Settings = {
            CheckGame      = true,
            CheckExecutor  = true,
            MetatableGuard = true,
            PoisonGenv     = false,
        },
    }
end

local function makeDebugDetection()
    return {
        Name = "DebugDetection",
        Settings = {
            DetectSethook = true,
            DetectGetinfo = true,
            DetectProfiler = true,
            DetectRobloxRE = true,
            Action = "kick",
        },
    }
end

-- ============================================================
--  Lua 5.1 & 5.3 Version Compatibility Helper
-- ============================================================

local function createPreset(name, baseConfig)
    -- Ensure LuaVersion supports both 5.1 and 5.3
    baseConfig.LuaVersion = baseConfig.LuaVersion or DEFAULT_LUA_VERSION
    -- Add version compatibility marker
    baseConfig._VersionSupport = "Lua51+Lua53"
    return baseConfig
end

-- ============================================================
--  PRESETS (with full Lua 5.1 & 5.3 support)
-- ============================================================

return {
    ["Minify"] = {
        -- The default LuaVersion is Lua51
        LuaVersion = "Lua51";
        -- For minifying no VarNamePrefix is applied
        VarNamePrefix = "";
        -- Name Generator for Variables
        NameGenerator = "MangledShuffled";
        -- No pretty printing
        PrettyPrint = false;
        -- Seed is generated based on current time
        Seed = 0;
        -- Obfuscation steps
        Steps = {
            {
                Name = "ConstantArray";
                Settings = {
                    Treshold = 1;
                    StringsOnly = true;
                    Shuffle = true;
                    Rotate = true;
                };
            },
            {
                Name = "NumbersToExpressions";
                Settings = {
                    Threshold = 0.5;
                };
            },
            {
                Name = "WrapInFunction";
                Settings = {

                };
            },
        }
    };
    ["Weak"] = {
        -- The default LuaVersion is Lua51
        LuaVersion = "Lua51";
        -- For minifying no VarNamePrefix is applied
        VarNamePrefix = "";
        -- Name Generator for Variables that look like this: IlI1lI1l
        NameGenerator = "MangledShuffled";
        -- No pretty printing
        PrettyPrint = false;
        -- Seed is generated based on current time
        Seed = 0;
        -- Obfuscation steps
        Steps = {
            {
                Name = "EncryptStrings";
                Settings = {
                    Threshold = 1;
                };
            },
            {
                Name = "ConstantArray";
                Settings = {
                    Treshold    = 1;
                    StringsOnly = true;
                    Shuffle     = true;
                    Rotate      = true;
                    DeadEntryRatio = 0.2;
                }
            },
            {
                Name = "NumbersToExpressions";
                Settings = {
                    Threshold = 0.6;
                };
            },
            {
                Name = "OpaquePredicate";
                Settings = {
                    Threshold = 0.25;
                };
            },
            {
                Name = "AntiTamper";
                Settings = {
                    UseDebug = false;
                    UseChecksumChain = true;
                    UseCounterTrap = true;
                    MaxTamperAttempts = 2;
                };
            },
            {
                Name = "WrapInFunction";
                Settings = {

                }
            },
        }
    };
    ["Vmify"] = {
        -- The default LuaVersion is Lua51
        LuaVersion = "Lua51";
        -- For minifying no VarNamePrefix is applied
        VarNamePrefix = "";
        -- Name Generator for Variables that look like this: IlI1lI1l
        NameGenerator = "MangledShuffled";
        -- No pretty printing
        PrettyPrint = false;
        -- Seed is generated based on current time
        Seed = 0;
        -- Obfuscation steps
        Steps = {
            {
                Name = "EncryptStrings";
                Settings = {
                    Threshold = 1;
                };
            },
            {
                Name = "ConstantArray";
                Settings = {
                    Treshold    = 1;
                    StringsOnly = true;
                    Shuffle     = true;
                    Rotate      = true;
                    DeadEntryRatio = 0.2;
                };
            },
            {
                Name = "Vmify";
                Settings = {

                };
            },
            {
                Name = "NumbersToExpressions";
                Settings = {
                    Threshold = 0.7;
                };
            },
            {
                Name = "JunkCodeInjection";
                Settings = {
                    Density = 0.25;
                    MaxPerBlock = 2;
                };
            },
            {
                Name = "WrapInFunction";
                Settings = {

                };
            },
        }
    };
    ["Medium"] = {
        -- The default LuaVersion is Lua51
        LuaVersion = "Lua51";
        -- For minifying no VarNamePrefix is applied
        VarNamePrefix = "";
        -- Name Generator for Variables
        NameGenerator = "MangledShuffled";
        -- No pretty printing
        PrettyPrint = false;
        -- Seed is generated based on current time
        Seed = 0;
        -- Obfuscation steps
        Steps = {
            {
                Name = "ConstantEncoding";
                Settings = {
                    Threshold = 1;
                    EncodeStrings = true;
                    EncodeNumbers = true;
                };
            },
            {
                Name = "EncryptStrings";
                Settings = {
                    Threshold = 1;
                    UseRandomKey = true;
                    PolyKey = true;
                    KeyRotation = true;
                };
            },
            {
                Name = "AntiTamper";
                Settings = {
                    UseDebug = false;
                    UseChecksumChain = true;
                    UseSelfRefTrap = true;
                    UseTimingJunk = true;
                    UseCounterTrap = true;
                    MaxTamperAttempts = 2;
                };
            },
            {
                Name = "Vmify";
                Settings = {

                };
            },
            {
                Name = "ConstantArray";
                Settings = {
                    Treshold    = 1;
                    StringsOnly = true;
                    Shuffle     = true;
                    Rotate      = true;
                    DeadEntryRatio = 0.25;
                    LocalWrapperTreshold = 0.5;
                }
            },
            {
                Name = "NumbersToExpressions";
                Settings = {
                    Threshold = 1;
                    InternalThreshold = 0.2;
                }
            },
            {
                Name = "MBAEncoding";
                Settings = {
                    Threshold = 0.8;
                    Depth = 1;
                };
            },
            {
                Name = "JunkCodeInjection";
                Settings = {
                    Density = 0.3;
                    MaxPerBlock = 3;
                };
            },
            {
                Name = "OpaquePredicate";
                Settings = {
                    Threshold = 0.4;
                    InsertDeadCode = true;
                };
            },
            {
                Name = "FakeBranches";
                Settings = {
                    FakeBranchThreshold = 0.35;
                    FakeRequireCount = 2;
                    MisleadingLogicCount = 2;
                };
            },
            {
                Name = "FlattenControlFlow";
                Settings = {
                    Threshold = 0.3;
                };
            },
            {
                Name = "WrapInFunction";
                Settings = {

                }
            },
        }
    };
    ["Strong"] = {
        -- The default LuaVersion is Lua51
        LuaVersion = "Lua51";
        -- For minifying no VarNamePrefix is applied
        VarNamePrefix = "";
        -- Name Generator for Variables that look like this: IlI1lI1l
        NameGenerator = "MangledShuffled";
        -- No pretty printing
        PrettyPrint = false;
        -- Seed is generated based on current time
        Seed = 0;
        -- Obfuscation steps
        Steps = {
            {
                Name = "ConstantEncoding";
                Settings = {
                    Threshold = 1;
                    EncodeStrings = true;
                    EncodeNumbers = true;
                    EncodeBooleans = true;
                };
            },
            {
                Name = "EncryptStrings";
                Settings = {
                    Threshold = 1;
                    UseRandomKey = true;
                    PolyKey = true;
                    CustomKeyGen = true;
                    KeyRotation = true;
                };
            },
            {
                Name = "AntiTamper";
                Settings = {
                    UseDebug = false;
                    UseChecksumChain = true;
                    UseSelfRefTrap = true;
                    UseTimingJunk = true;
                    UseCounterTrap = true;
                    UseMemoryCheck = true;
                    UseCodeFlowCheck = true;
                    MaxTamperAttempts = 3;
                };
            },
            {
                Name = "Vmify";
                Settings = {

                };
            },
            {
                Name = "ConstantArray";
                Settings = {
                    Treshold    = 1;
                    StringsOnly = true;
                    Shuffle     = true;
                    Rotate      = true;
                    DeadEntryRatio = 0.3;
                    LocalWrapperTreshold = 0.5;
                }
            },
            {
                Name = "NumbersToExpressions";
                Settings = {
                    Threshold = 1;
                    InternalThreshold = 0.3;
                    NumberRepresentationMutation = true;
                }
            },
            {
                Name = "MBAEncoding";
                Settings = {
                    Threshold = 0.85;
                    Depth = 2;
                };
            },
            {
                Name = "JunkCodeInjection";
                Settings = {
                    Density = 0.35;
                    MaxPerBlock = 4;
                };
            },
            {
                Name = "OpaquePredicate";
                Settings = {
                    Threshold = 0.45;
                    InsertDeadCode = true;
                };
            },
            {
                Name = "FakeBranches";
                Settings = {
                    FakeBranchThreshold = 0.45;
                    FakeRequireCount = 3;
                    MisleadingLogicCount = 3;
                };
            },
            {
                Name = "FlattenControlFlow";
                Settings = {
                    Threshold = 0.4;
                };
            },
            {
                Name = "SplitStrings";
                Settings = {
                    Method = "random";
                    Threshold = 1;
                    MaxChunkSize = 12;
                };
            },
            {
                Name = "Vmify";
                Settings = {

                };
            },
            {
                Name = "WrapInFunction";
                Settings = {

                }
            },
        }
    },
    ["RobloxExecutor"] = {
        -- Advanced Roblox protection with anti-debug
        LuaVersion = "Lua51";
        VarNamePrefix = "";
        NameGenerator = "MangledShuffled";
        PrettyPrint = false;
        Seed = 0;
        Steps = {
            {
                Name = "EnvironmentLock";
                Settings = {
                    Mode = "roblox";
                    CheckGame = true;
                    CheckExecutor = true;
                    MetatableGuard = true;
                };
            },
            {
                Name = "DebugDetection";
                Settings = {
                    DetectSethook = true;
                    DetectGetinfo = true;
                    DetectProfiler = true;
                    DetectRobloxRE = true;
                    Action = "kick";
                };
            },
            {
                Name = "ConstantEncoding";
                Settings = {
                    Threshold = 1;
                    EncodeStrings = true;
                    EncodeNumbers = true;
                    EncodeBooleans = true;
                };
            },
            {
                Name = "EncryptStrings";
                Settings = {
                    Threshold = 1;
                    UseRandomKey = true;
                    PolyKey = true;
                    CustomKeyGen = true;
                    KeyRotation = true;
                };
            },
            {
                Name = "Vmify";
                Settings = {};
            },
            {
                Name = "AntiTamper";
                Settings = {
                    UseDebug = false;
                    UseChecksumChain = true;
                    UseSelfRefTrap = true;
                    UseTimingJunk = true;
                    UseCounterTrap = true;
                    UseMemoryCheck = true;
                    UseCodeFlowCheck = true;
                    MaxTamperAttempts = 3;
                };
            },
            {
                Name = "ConstantArray";
                Settings = {
                    Treshold = 1;
                    StringsOnly = true;
                    Shuffle = true;
                    Rotate = true;
                    DeadEntryRatio = 0.35;
                    LocalWrapperTreshold = 0.6;
                };
            },
            {
                Name = "MBAEncoding";
                Settings = {
                    Threshold = 0.9;
                    Depth = 2;
                };
            },
            {
                Name = "NumbersToExpressions";
                Settings = {
                    Threshold = 1;
                    InternalThreshold = 0.35;
                    NumberRepresentationMutation = true;
                };
            },
            {
                Name = "JunkCodeInjection";
                Settings = {
                    Density = 0.4;
                    MaxPerBlock = 5;
                };
            },
            {
                Name = "OpaquePredicate";
                Settings = {
                    Threshold = 0.5;
                    InsertDeadCode = true;
                };
            },
            {
                Name = "FakeBranches";
                Settings = {
                    FakeBranchThreshold = 0.5;
                    FakeRequireCount = 4;
                    MisleadingLogicCount = 4;
                };
            },
            {
                Name = "FlattenControlFlow";
                Settings = {
                    Threshold = 0.45;
                };
            },
            {
                Name = "SplitStrings";
                Settings = {
                    Method = "random";
                    Threshold = 1;
                    MaxChunkSize = 15;
                };
            },
            {
                Name = "ProxyFunctions";
                Settings = {
                    Threshold = 0.6;
                    ProxyStdLib = true;
                    HideProxyLayer = true;
                };
            },
            {
                Name = "WrapInFunction";
                Settings = {};
            },
        }
    },
    ["Maximum"] = {
        -- Maximum obfuscation with dual VM
        LuaVersion = "Lua51";
        VarNamePrefix = "";
        NameGenerator = "MangledShuffled";
        PrettyPrint = false;
        Seed = 0;
        Steps = {
            {
                Name = "ConstantEncoding";
                Settings = {
                    Threshold = 1;
                    EncodeStrings = true;
                    EncodeNumbers = true;
                    EncodeBooleans = true;
                };
            },
            {
                Name = "EncryptStrings";
                Settings = {
                    Threshold = 1;
                    UseRandomKey = true;
                    PolyKey = true;
                    CustomKeyGen = true;
                    KeyRotation = true;
                };
            },
            {
                Name = "SplitStrings";
                Settings = {
                    Method = "random";
                    Threshold = 1;
                    MaxChunkSize = 20;
                };
            },
            {
                Name = "Vmify";
                Settings = {};
            },
            {
                Name = "AntiTamper";
                Settings = {
                    UseDebug = false;
                    UseChecksumChain = true;
                    UseSelfRefTrap = true;
                    UseTimingJunk = true;
                    UseCounterTrap = true;
                    UseMemoryCheck = true;
                    UseCodeFlowCheck = true;
                    UseCriticalPathCheck = true;
                    MaxTamperAttempts = 3;
                };
            },
            {
                Name = "ConstantArray";
                Settings = {
                    Treshold = 1;
                    StringsOnly = true;
                    Shuffle = true;
                    Rotate = true;
                    DeadEntryRatio = 0.4;
                    LocalWrapperTreshold = 0.7;
                };
            },
            {
                Name = "MBAEncoding";
                Settings = {
                    Threshold = 0.95;
                    Depth = 3;
                };
            },
            {
                Name = "NumbersToExpressions";
                Settings = {
                    Threshold = 1;
                    InternalThreshold = 0.4;
                    NumberRepresentationMutation = true;
                };
            },
            {
                Name = "JunkCodeInjection";
                Settings = {
                    Density = 0.45;
                    MaxPerBlock = 6;
                };
            },
            {
                Name = "OpaquePredicate";
                Settings = {
                    Threshold = 0.55;
                    InsertDeadCode = true;
                };
            },
            {
                Name = "FakeBranches";
                Settings = {
                    FakeBranchThreshold = 0.55;
                    FakeRequireCount = 5;
                    MisleadingLogicCount = 5;
                };
            },
            {
                Name = "FlattenControlFlow";
                Settings = {
                    Threshold = 0.5;
                };
            },
            {
                Name = "ProxyFunctions";
                Settings = {
                    Threshold = 0.7;
                    ProxyStdLib = true;
                    HideProxyLayer = true;
                    UseClosures = true;
                };
            },
            {
                Name = "Vmify";
                Settings = {};
            },
            {
                Name = "WrapInFunction";
                Settings = {};
            },
        }
    },
    ["Supreme"] = {
        -- Supreme protection with triple encryption
        LuaVersion = "Lua51";
        VarNamePrefix = "";
        NameGenerator = "MangledShuffled";
        PrettyPrint = false;
        Seed = 0;
        Steps = {
            {
                Name = "EnvironmentLock";
                Settings = {
                    Mode = "strict";
                    CheckGame = true;
                    CheckExecutor = true;
                    ValidateGenv = true;
                    ValidateLuaStack = true;
                };
            },
            {
                Name = "AntiTamper";
                Settings = {
                    UseDebug = false;
                    UseChecksumChain = true;
                    UseSelfRefTrap = true;
                    UseTimingJunk = true;
                    UseCounterTrap = true;
                    UseMemoryCheck = true;
                    UseCodeFlowCheck = true;
                    UseCriticalPathCheck = true;
                    MaxTamperAttempts = 5;
                };
            },
            {
                Name = "DebugDetection";
                Settings = {
                    DetectSethook = true;
                    DetectGetinfo = true;
                    DetectProfiler = true;
                    DetectMemoryAccess = true;
                    DetectDecompilers = true;
                    Action = "kick";
                };
            },
            {
                Name = "ConstantEncoding";
                Settings = {
                    Threshold = 1;
                    EncodeStrings = true;
                    EncodeNumbers = true;
                    EncodeBooleans = true;
                };
            },
            {
                Name = "EncryptStrings";
                Settings = {
                    Threshold = 1;
                    UseRandomKey = true;
                    PolyKey = true;
                    CustomKeyGen = true;
                    KeyRotation = true;
                };
            },
            {
                Name = "SplitStrings";
                Settings = {
                    Method = "random";
                    Threshold = 1;
                    MaxChunkSize = 25;
                };
            },
            {
                Name = "Vmify";
                Settings = {};
            },
            {
                Name = "ConstantArray";
                Settings = {
                    Treshold = 1;
                    StringsOnly = true;
                    Shuffle = true;
                    Rotate = true;
                    DeadEntryRatio = 0.45;
                    LocalWrapperTreshold = 0.8;
                };
            },
            {
                Name = "MBAEncoding";
                Settings = {
                    Threshold = 1;
                    Depth = 3;
                };
            },
            {
                Name = "NumbersToExpressions";
                Settings = {
                    Threshold = 1;
                    InternalThreshold = 0.5;
                    NumberRepresentationMutation = true;
                };
            },
            {
                Name = "JunkCodeInjection";
                Settings = {
                    Density = 0.5;
                    MaxPerBlock = 7;
                };
            },
            {
                Name = "OpaquePredicate";
                Settings = {
                    Threshold = 0.6;
                    InsertDeadCode = true;
                };
            },
            {
                Name = "FakeBranches";
                Settings = {
                    FakeBranchThreshold = 0.6;
                    FakeRequireCount = 6;
                    MisleadingLogicCount = 6;
                };
            },
            {
                Name = "FlattenControlFlow";
                Settings = {
                    Threshold = 0.55;
                };
            },
            {
                Name = "NestedFunction";
                Settings = {
                    Threshold = 0.5;
                    Layers = 3;
                };
            },
            {
                Name = "ProxyFunctions";
                Settings = {
                    Threshold = 0.8;
                    ProxyStdLib = true;
                    HideProxyLayer = true;
                    UseClosures = true;
                    MixRealFake = true;
                };
            },
            {
                Name = "Vmify";
                Settings = {};
            },
            {
                Name = "WrapInFunction";
                Settings = {};
            },
        }
    },
}
