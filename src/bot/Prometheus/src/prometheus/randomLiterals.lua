

local Ast = require("prometheus.ast");
local RandomStrings = require("prometheus.randomStrings");

local RandomLiterals = {};

local function callNameGenerator(generatorFunction, ...)
	if(type(generatorFunction) == "table") then
		generatorFunction = generatorFunction.generateName;
	end
	return generatorFunction(...);
end

-- Randomized number ranges untuk avoid pattern detection
local function getRandomNumberRange()
	local rangeType = math.random(1, 4)
	if rangeType == 1 then
		return -16777216, 16777216  -- 24-bit range
	elseif rangeType == 2 then
		return -33554432, 33554432  -- 25-bit range
	elseif rangeType == 3 then
		return -67108864, 67108864  -- 26-bit range
	else
		return -2147483648, 2147483647  -- 32-bit range
	end
end

function RandomLiterals.String(pipeline)
    return Ast.StringExpression(callNameGenerator(pipeline.namegenerator, math.random(1, 4096)));
end

function RandomLiterals.Dictionary()
    return RandomStrings.randomStringNode(true);
end

function RandomLiterals.Number()
	local min, max = getRandomNumberRange()
	local baseNum = math.random(min, max)
	
	return Ast.NumberExpression(baseNum)
end

function RandomLiterals.Any(pipeline)
    local type = math.random(1, 3);
    if type == 1 then
        return RandomLiterals.String(pipeline);
    elseif type == 2 then
        return RandomLiterals.Number();
    elseif type == 3 then
        return RandomLiterals.Dictionary();
    end
end


return RandomLiterals;