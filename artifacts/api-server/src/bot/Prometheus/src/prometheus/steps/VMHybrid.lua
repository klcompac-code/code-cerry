local Step   = require("prometheus.step")
local Parser = require("prometheus.parser")
local Enums  = require("prometheus.enums")
local Ast    = require("prometheus.ast")
local visitast = require("prometheus.visitast")
local util   = require("prometheus.util")
local logger = require("logger")
local AstKind = Ast.AstKind

local VMHybrid = Step:extend()
VMHybrid.Description = "VM+CFG hybrid: Converts code to custom VM bytecode"
VMHybrid.Name        = "VM Hybrid"
VMHybrid.SettingsDescriptor = {
    Enabled = { type="boolean", default=true },
}
function VMHybrid:init(_) end

-- Generate unique opcodes for this build
local function generateOpcodeMap()
    local used = {}
    local function randOp()
        local op
        repeat
            op = math.random(0x01, 0xFE)
        until not used[op]
        used[op] = true
        return op
    end
    
    return {
        PUSH   = randOp(),
        POP    = randOp(),
        ADD    = randOp(),
        SUB    = randOp(),
        MUL    = randOp(),
        DIV    = randOp(),
        MOD    = randOp(),
        POW    = randOp(),
        CONCAT = randOp(),
        JMP    = randOp(),
        JMPIF  = randOp(),
        CALL   = randOp(),
        RET    = randOp(),
        LOAD   = randOp(),
        STORE  = randOp(),
        LOADK  = randOp(),
        NEG    = randOp(),
        NOT    = randOp(),
        LEN    = randOp(),
        EQ     = randOp(),
        LT     = randOp(),
        LE     = randOp(),
    }
end

-- [FIX] Convert AST node to VM bytecode
local function compileExpression(node, constants, scopeMap)
    if not node then return {} end
    
    if node.kind == AstKind.NumberExpression then
        local constIdx = #constants + 1
        constants[constIdx] = node.value
        return { { op = "LOADK", arg = constIdx } }
        
    elseif node.kind == AstKind.StringExpression then
        local constIdx = #constants + 1
        constants[constIdx] = node.value
        return { { op = "LOADK", arg = constIdx } }
        
    elseif node.kind == AstKind.BooleanExpression then
        local constIdx = #constants + 1
        constants[constIdx] = node.value
        return { { op = "LOADK", arg = constIdx } }
        
    elseif node.kind == AstKind.VariableExpression then
        local varIdx = scopeMap[node.id] or 1
        return { { op = "LOAD", arg = varIdx } }
        
    elseif node.kind == AstKind.AddExpression then
        local left = compileExpression(node.left, constants, scopeMap)
        local right = compileExpression(node.right, constants, scopeMap)
        local result = {}
        for _, ins in ipairs(left) do table.insert(result, ins) end
        for _, ins in ipairs(right) do table.insert(result, ins) end
        table.insert(result, { op = "ADD" })
        return result
        
    elseif node.kind == AstKind.SubExpression then
        local left = compileExpression(node.left, constants, scopeMap)
        local right = compileExpression(node.right, constants, scopeMap)
        local result = {}
        for _, ins in ipairs(left) do table.insert(result, ins) end
        for _, ins in ipairs(right) do table.insert(result, ins) end
        table.insert(result, { op = "SUB" })
        return result
        
    elseif node.kind == AstKind.MulExpression then
        local left = compileExpression(node.left, constants, scopeMap)
        local right = compileExpression(node.right, constants, scopeMap)
        local result = {}
        for _, ins in ipairs(left) do table.insert(result, ins) end
        for _, ins in ipairs(right) do table.insert(result, ins) end
        table.insert(result, { op = "MUL" })
        return result
        
    elseif node.kind == AstKind.DivExpression then
        local left = compileExpression(node.left, constants, scopeMap)
        local right = compileExpression(node.right, constants, scopeMap)
        local result = {}
        for _, ins in ipairs(left) do table.insert(result, ins) end
        for _, ins in ipairs(right) do table.insert(result, ins) end
        table.insert(result, { op = "DIV" })
        return result
        
    elseif node.kind == AstKind.ModExpression then
        local left = compileExpression(node.left, constants, scopeMap)
        local right = compileExpression(node.right, constants, scopeMap)
        local result = {}
        for _, ins in ipairs(left) do table.insert(result, ins) end
        for _, ins in ipairs(right) do table.insert(result, ins) end
        table.insert(result, { op = "MOD" })
        return result
        
    elseif node.kind == AstKind.PowExpression then
        local left = compileExpression(node.left, constants, scopeMap)
        local right = compileExpression(node.right, constants, scopeMap)
        local result = {}
        for _, ins in ipairs(left) do table.insert(result, ins) end
        for _, ins in ipairs(right) do table.insert(result, ins) end
        table.insert(result, { op = "POW" })
        return result
        
    elseif node.kind == AstKind.StrCatExpression then
        local left = compileExpression(node.left, constants, scopeMap)
        local right = compileExpression(node.right, constants, scopeMap)
        local result = {}
        for _, ins in ipairs(left) do table.insert(result, ins) end
        for _, ins in ipairs(right) do table.insert(result, ins) end
        table.insert(result, { op = "CONCAT" })
        return result
        
    elseif node.kind == AstKind.NegateExpression then
        local expr = compileExpression(node.expression, constants, scopeMap)
        local result = {}
        for _, ins in ipairs(expr) do table.insert(result, ins) end
        table.insert(result, { op = "NEG" })
        return result
        
    elseif node.kind == AstKind.NotExpression then
        local expr = compileExpression(node.expression, constants, scopeMap)
        local result = {}
        for _, ins in ipairs(expr) do table.insert(result, ins) end
        table.insert(result, { op = "NOT" })
        return result
        
    elseif node.kind == AstKind.LenExpression then
        local expr = compileExpression(node.expression, constants, scopeMap)
        local result = {}
        for _, ins in ipairs(expr) do table.insert(result, ins) end
        table.insert(result, { op = "LEN" })
        return result
    end
    
    return {}
end

function VMHybrid:apply(ast, _)
    if not self.Enabled then return ast end

    local opcodes = generateOpcodeMap()
    
    -- Build opcode mapping tables
    local opToNum = {}
    local numToOp = {}
    for name, num in pairs(opcodes) do
        opToNum[name] = num
        numToOp[num] = name
    end
    
    -- Collect all statements
    local allStatements = {}
    local function collectStatements(block)
        for _, stmt in ipairs(block.statements or {}) do
            table.insert(allStatements, stmt)
            if stmt.body then
                collectStatements(stmt.body)
            end
        end
    end
    collectStatements(ast.body)
    
    -- Build scope mapping for variables
    local scopeMap = {}
    local nextVar = 1
    local function mapScope(scope)
        for id, var in pairs(scope.variables or {}) do
            if not scopeMap[id] then
                scopeMap[id] = nextVar
                nextVar = nextVar + 1
            end
        end
        if scope.parent then
            mapScope(scope.parent)
        end
    end
    mapScope(ast.body.scope)
    
    -- Compile each statement to bytecode
    local constants = {}
    local bytecode = {}
    local labelMap = {}
    local pendingJumps = {}
    
    for idx, stmt in ipairs(allStatements) do
        local stmtBytecode = {}
        
        if stmt.kind == AstKind.AssignmentStatement then
            -- Compile RHS first
            for _, rhs in ipairs(stmt.rhs) do
                local rhsCode = compileExpression(rhs, constants, scopeMap)
                for _, ins in ipairs(rhsCode) do
                    table.insert(stmtBytecode, ins)
                end
            end
            -- Store to LHS (pop order - last rhs to first lhs)
            for i = #stmt.lhs, 1, -1 do
                table.insert(stmtBytecode, { op = "STORE", arg = scopeMap[stmt.lhs[i].id] or 1 })
            end
            
        elseif stmt.kind == AstKind.LocalVariableDeclaration then
            for i, id in ipairs(stmt.ids) do
                scopeMap[id] = nextVar
                nextVar = nextVar + 1
                if stmt.expressions[i] then
                    local exprCode = compileExpression(stmt.expressions[i], constants, scopeMap)
                    for _, ins in ipairs(exprCode) do
                        table.insert(stmtBytecode, ins)
                    end
                    table.insert(stmtBytecode, { op = "STORE", arg = scopeMap[id] })
                else
                    table.insert(stmtBytecode, { op = "LOADK", arg = #constants + 1 })
                    constants[#constants + 1] = nil
                    table.insert(stmtBytecode, { op = "STORE", arg = scopeMap[id] })
                end
            end
            
        elseif stmt.kind == AstKind.FunctionCallStatement then
            -- Compile function call
            local funcCode = compileExpression(stmt.base, constants, scopeMap)
            for _, ins in ipairs(funcCode) do
                table.insert(stmtBytecode, ins)
            end
            -- Compile arguments
            for _, arg in ipairs(stmt.args or {}) do
                local argCode = compileExpression(arg, constants, scopeMap)
                for _, ins in ipairs(argCode) do
                    table.insert(stmtBytecode, ins)
                end
            end
            table.insert(stmtBytecode, { op = "CALL", arg = #(stmt.args or {}) })
            -- Pop return value if any (discard)
            table.insert(stmtBytecode, { op = "POP" })
            
        elseif stmt.kind == AstKind.ReturnStatement then
            for _, expr in ipairs(stmt.expressions) do
                local exprCode = compileExpression(expr, constants, scopeMap)
                for _, ins in ipairs(exprCode) do
                    table.insert(stmtBytecode, ins)
                end
            end
            table.insert(stmtBytecode, { op = "RET" })
            
        elseif stmt.kind == AstKind.IfStatement then
            -- Compile condition
            local condCode = compileExpression(stmt.condition, constants, scopeMap)
            for _, ins in ipairs(condCode) do
                table.insert(stmtBytecode, ins)
            end
            
            -- Mark for jump patching
            local jumpIdx = #stmtBytecode + 1
            table.insert(stmtBytecode, { op = "JMPIF", arg = 0, targetLabel = "else_" .. idx })
            table.insert(pendingJumps, { idx = jumpIdx, label = "else_" .. idx })
            
            -- Compile then body
            for _, bodyStmt in ipairs(stmt.body.statements or {}) do
                -- Will be handled separately
            end
            
        elseif stmt.kind == AstKind.WhileStatement then
            -- Mark loop start
            local loopStart = #bytecode + #stmtBytecode + 1
            labelMap["loop_" .. idx] = loopStart
            
            -- Compile condition
            local condCode = compileExpression(stmt.condition, constants, scopeMap)
            for _, ins in ipairs(condCode) do
                table.insert(stmtBytecode, ins)
            end
            
            -- Jump if false
            local jumpIdx = #stmtBytecode + 1
            table.insert(stmtBytecode, { op = "JMPIF", arg = 0, targetLabel = "end_" .. idx })
            table.insert(pendingJumps, { idx = jumpIdx, label = "end_" .. idx })
            
            -- Body will be compiled later
            -- Jump back to start
            table.insert(stmtBytecode, { op = "JMP", arg = loopStart })
            labelMap["end_" .. idx] = #bytecode + #stmtBytecode + 1
        end
        
        for _, ins in ipairs(stmtBytecode) do
            table.insert(bytecode, ins)
        end
    end
    
    -- Patch jumps
    for _, jump in ipairs(pendingJumps) do
        local target = labelMap[jump.label]
        if target then
            bytecode[jump.idx].arg = target
        end
    end
    
    -- Build VM engine with actual bytecode
    local suffix = math.random(100000, 999999)
    local vmFuncName = "_VM_" .. suffix
    local constTableName = "_C_" .. suffix
    local opTableName = "_O_" .. suffix
    
    -- Convert opcodes to numbers
    local opValues = {}
    for name, num in pairs(opcodes) do
        opValues[name] = num
    end
    
    -- Build constant array
    local constArray = {}
    for i, const in ipairs(constants) do
        if const == nil then
            constArray[i] = "nil"
        elseif type(const) == "string" then
            constArray[i] = string.format("%q", const)
        else
            constArray[i] = tostring(const)
        end
    end
    
    -- Build bytecode array
    local bcArray = {}
    for i, ins in ipairs(bytecode) do
        if ins.op == "LOADK" then
            bcArray[i] = string.format("{op=%d,arg=%d}", opValues.LOADK, ins.arg)
        elseif ins.op == "LOAD" then
            bcArray[i] = string.format("{op=%d,arg=%d}", opValues.LOAD, ins.arg)
        elseif ins.op == "STORE" then
            bcArray[i] = string.format("{op=%d,arg=%d}", opValues.STORE, ins.arg)
        elseif ins.op == "ADD" then
            bcArray[i] = string.format("{op=%d}", opValues.ADD)
        elseif ins.op == "SUB" then
            bcArray[i] = string.format("{op=%d}", opValues.SUB)
        elseif ins.op == "MUL" then
            bcArray[i] = string.format("{op=%d}", opValues.MUL)
        elseif ins.op == "DIV" then
            bcArray[i] = string.format("{op=%d}", opValues.DIV)
        elseif ins.op == "MOD" then
            bcArray[i] = string.format("{op=%d}", opValues.MOD)
        elseif ins.op == "POW" then
            bcArray[i] = string.format("{op=%d}", opValues.POW)
        elseif ins.op == "CONCAT" then
            bcArray[i] = string.format("{op=%d}", opValues.CONCAT)
        elseif ins.op == "NEG" then
            bcArray[i] = string.format("{op=%d}", opValues.NEG)
        elseif ins.op == "NOT" then
            bcArray[i] = string.format("{op=%d}", opValues.NOT)
        elseif ins.op == "LEN" then
            bcArray[i] = string.format("{op=%d}", opValues.LEN)
        elseif ins.op == "JMP" then
            bcArray[i] = string.format("{op=%d,arg=%d}", opValues.JMP, ins.arg or 0)
        elseif ins.op == "JMPIF" then
            bcArray[i] = string.format("{op=%d,arg=%d}", opValues.JMPIF, ins.arg or 0)
        elseif ins.op == "CALL" then
            bcArray[i] = string.format("{op=%d,arg=%d}", opValues.CALL, ins.arg or 0)
        elseif ins.op == "RET" then
            bcArray[i] = string.format("{op=%d}", opValues.RET)
        elseif ins.op == "POP" then
            bcArray[i] = string.format("{op=%d}", opValues.POP)
        elseif ins.op == "PUSH" then
            bcArray[i] = string.format("{op=%d}", opValues.PUSH)
        else
            bcArray[i] = string.format("{op=%d}", ins.op)
        end
    end
    
    local vmCode = string.format([[
do
    local %s = {
        %s
    }
    local %s = {
        LOADK=%d, LOAD=%d, STORE=%d, ADD=%d, SUB=%d, MUL=%d, DIV=%d,
        MOD=%d, POW=%d, CONCAT=%d, NEG=%d, NOT=%d, LEN=%d, JMP=%d,
        JMPIF=%d, CALL=%d, RET=%d, POP=%d
    }
    
    local %s = function()
        local stack = {}
        local sp = 0
        local vars = {}
        local pc = 1
        
        local function push(v)
            sp = sp + 1
            stack[sp] = v
        end
        
        local function pop()
            local v = stack[sp]
            stack[sp] = nil
            sp = sp - 1
            return v
        end
        
        while pc <= #%s do
            local ins = %s[pc]
            local op = ins.op
            
            if op == %s.LOADK then
                push(%s[ins.arg])
            elseif op == %s.LOAD then
                push(vars[ins.arg])
            elseif op == %s.STORE then
                vars[ins.arg] = pop()
            elseif op == %s.ADD then
                local b, a = pop(), pop()
                push(a + b)
            elseif op == %s.SUB then
                local b, a = pop(), pop()
                push(a - b)
            elseif op == %s.MUL then
                local b, a = pop(), pop()
                push(a * b)
            elseif op == %s.DIV then
                local b, a = pop(), pop()
                push(a / b)
            elseif op == %s.MOD then
                local b, a = pop(), pop()
                push(a %% b)
            elseif op == %s.POW then
                local b, a = pop(), pop()
                push(a ^ b)
            elseif op == %s.CONCAT then
                local b, a = pop(), pop()
                push(tostring(a) .. tostring(b))
            elseif op == %s.NEG then
                push(-pop())
            elseif op == %s.NOT then
                push(not pop())
            elseif op == %s.LEN then
                push(#pop())
            elseif op == %s.JMP then
                pc = ins.arg
                goto continue
            elseif op == %s.JMPIF then
                local cond = pop()
                if cond then
                    pc = ins.arg
                    goto continue
                end
            elseif op == %s.CALL then
                local func = pop()
                local argc = ins.arg or 0
                local args = {}
                for i = argc, 1, -1 do
                    args[i] = pop()
                end
                local results = {pcall(func, table.unpack(args))}
                if results[1] then
                    for i = 2, #results do
                        push(results[i])
                    end
                end
            elseif op == %s.RET then
                return pop()
            elseif op == %s.POP then
                pop()
            end
            
            pc = pc + 1
            ::continue::
        end
        
        return pop()
    end
    
    %s()
end
]],
    constTableName, table.concat(constArray, ", "),
    opTableName,
    opValues.LOADK, opValues.LOAD, opValues.STORE, opValues.ADD, opValues.SUB, opValues.MUL, opValues.DIV,
    opValues.MOD, opValues.POW, opValues.CONCAT, opValues.NEG, opValues.NOT, opValues.LEN, opValues.JMP,
    opValues.JMPIF, opValues.CALL, opValues.RET, opValues.POP,
    vmFuncName,
    constTableName,
    constTableName,
    opTableName,
    constTableName,
    opTableName,
    opTableName,
    opTableName,
    opTableName,
    opTableName,
    opTableName,
    opTableName,
    opTableName,
    opTableName,
    opTableName,
    opTableName,
    opTableName,
    opTableName,
    opTableName,
    opTableName,
    opTableName,
    opTableName,
    opTableName,
    opTableName,
    opTableName,
    opTableName,
    opTableName,
    vmFuncName
)

    -- Parse and inject VM code
    local ok, parsed = pcall(function()
        return Parser:new({ LuaVersion = Enums.LuaVersion.Lua51 }):parse(vmCode)
    end)
    
    if not ok then
        logger:warn("[VMHybrid] Failed to parse VM code: " .. tostring(parsed))
        return ast
    end

    local scope = ast.body.scope
    local doStat = parsed.body.statements[1]
    if doStat and doStat.body then
        doStat.body.scope:setParent(scope)
    end
    table.insert(ast.body.statements, 1, doStat)

    logger:info(string.format("[VMHybrid] VM engine injected with %d instructions and %d constants",
        #bytecode, #constants))
    
    return ast
end

return VMHybrid