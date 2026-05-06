-- This Script is Part of the Prometheus Obfuscator by Levno_710
--
-- WatermarkCheck.lua
--
-- This Script provides a Step that will add a watermark to the script

local Step = require("prometheus.step");
local Ast = require("prometheus.ast");
local Scope = require("prometheus.scope");
local Watermark = require("prometheus.steps.Watermark");
local LockedWatermark = require("prometheus.steps.LockedWatermark");

local WatermarkCheck = Step:extend();
WatermarkCheck.Description = "This Step will add/lock a watermark to the script";
WatermarkCheck.Name = "WatermarkCheck";

WatermarkCheck.SettingsDescriptor = {
  Content = {
    name = "Content",
    description = "The Content of the WatermarkCheck",
    type = "string",
    default = "This Script is Part of the Prometheus Obfuscator by Haggaicc",
  },
}

local function callNameGenerator(generatorFunction, ...)
	if(type(generatorFunction) == "table") then
		generatorFunction = generatorFunction.generateName;
	end
	return generatorFunction(...);
end

function WatermarkCheck:init(settings)
  -- Pre-generate CustomVariable in init to avoid generating it during pipeline execution
  self.CustomVariable = "_wm_" .. tostring(math.random(10000000000, 100000000000));
end

function WatermarkCheck:apply(ast, pipeline)
  -- Ensure CustomVariable exists (fallback if init wasn't called)
  if not self.CustomVariable then
    self.CustomVariable = "_" .. callNameGenerator(pipeline.namegenerator or tostring, math.random(10000000000, 100000000000));
  end
  
  -- SAFE: Only add LockedWatermark step if not already added
  if not pipeline._lockedWatermarkAdded then
    pipeline:addStep(LockedWatermark:new(self)); -- gunakan LockedWatermark sebagai watermark utama, satu titik konfigurasi
    pipeline._lockedWatermarkAdded = true
  end

  local body = ast.body;
  local watermarkExpression = Ast.StringExpression(self.Content);
  local scope, variable = ast.globalScope:resolve(self.CustomVariable);
  local watermark = Ast.VariableExpression(ast.globalScope, variable);
  local notEqualsExpression = Ast.NotEqualsExpression(watermark, watermarkExpression);
  local ifBody = Ast.Block({Ast.ReturnStatement({})}, Scope:new(ast.body.scope));

  table.insert(body.statements, 1, Ast.IfStatement(notEqualsExpression, ifBody, {}, nil));
end

return WatermarkCheck;