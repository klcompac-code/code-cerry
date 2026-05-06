-- This Script is Part of the Prometheus Obfuscator by Levno_710
--
-- namegenerators/mangled.lua
--
-- This Script provides a function for generation of mangled names


local util = require("prometheus.util");
local chararray = util.chararray;

local idGen = 0
local VarDigits = chararray("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_");
local VarStartDigits = chararray("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ");

-- Alternative digit sets for variation
local AltDigits = chararray("zyxwvutsrqponmlkjihgfedcbaZYXWVUTSRQPONMLKJIHGFEDCBA9876543210_");
local AltStartDigits = chararray("zyxwvutsrqponmlkjihgfedcbaZYXWVUTSRQPONMLKJIHGFEDCBA");

return function(id, scope)
	-- Randomize antara normal dan alternate digit sets
	local useAlt = math.random(1, 2) == 1
	local digits = useAlt and AltDigits or VarDigits
	local startDigits = useAlt and AltStartDigits or VarStartDigits
	
	local name = ''
	local d = id % #startDigits
	id = (id - d) / #startDigits
	name = name..startDigits[d+1]
	while id > 0 do
		local d = id % #digits
		id = (id - d) / #digits
		name = name..digits[d+1]
	end
	return name
end