-- Commit ` # % * literally in Chinese mode, including full-shape mode.
--
-- The punctuator maps alone cannot do this in full-shape mode: librime's
-- global shape_formatter rewrites every ASCII commit to its full-width form.
-- Briefly disabling full_shape around the direct commit keeps the character
-- ASCII and restores the user's punctuation mode immediately afterwards.
--
-- This runs only at an empty composition. While composing, these keys keep
-- their normal role (for example * remains the Wubi wildcard).
local literal = {
  ["`"] = true,
  ["#"] = true,
  ["%"] = true,
  ["*"] = true,
}

local function processor(key, env)
  if key:release() or key:ctrl() or key:alt() or key:super() then
    return 2 -- kNoop
  end
  local context = env.engine.context
  if context:get_option("ascii_mode") or context.input ~= "" then
    return 2
  end
  local repr = key:repr()
  local code = key.keycode
  local text = nil
  if literal[repr] then
    text = repr
  elseif code == 0x60 then
    text = "`"
  elseif code == 0x23 then
    text = "#"
  elseif code == 0x25 then
    text = "%"
  elseif code == 0x2a then
    text = "*"
  end
  if not text then
    return 2
  end
  local full_shape = context:get_option("full_shape")
  if full_shape then
    context:set_option("full_shape", false)
  end
  env.engine:commit_text(text)
  if full_shape then
    context:set_option("full_shape", true)
  end
  return 1 -- kAccepted
end

return processor
