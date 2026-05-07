local Ast = require("prometheus.ast")
local utils = require("prometheus.util")

-- Multiple randomized character pools untuk anti-pattern
local charsetPools = {
	utils.chararray("qwertyuiopasdfghjklzxcvbnmQWERTYUIOPASDFGHJKLZXCVBNM1234567890"),
	utils.chararray("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_"),
	utils.chararray("zyxwvutsrqponmlkjihgfedcbaZYXWVUTSRQPONMLKJIHGFEDCBA9876543210"),
}

local function getRandomCharset()
	return charsetPools[math.random(1, #charsetPools)]
end

local function randomString(wordsOrLen)
	if type(wordsOrLen) == "table" then
		return wordsOrLen[math.random(1, #wordsOrLen)];
	end

	local charset = getRandomCharset()
	wordsOrLen = wordsOrLen or math.random(3, 20)
	
	local result = ""
	for i = 1, wordsOrLen do
		result = result .. charset[math.random(1, #charset)]
	end
	return result
end

local function randomStringNode(wordsOrLen)
	return Ast.StringExpression(randomString(wordsOrLen))
end

return {
	randomString = randomString,
	randomStringNode = randomStringNode,
}
