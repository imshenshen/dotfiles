-- After abc_segmentor: five or more letters use the native pinyin translator.
-- Keep native candidates intact so script_translator can learn selected words.
local M = {}

function M.func(segmentation, env)
    if segmentation:empty() then
        return true
    end
    local segment = segmentation:back()
    if not segment:has_tag("abc") or segment:has_tag("reverse_lookup") then
        return true -- Preserve explicit zz reverse lookup, URLs and punctuation.
    end
    local input = segmentation.input:sub(segment.start + 1, segment._end)
    local letters = input:gsub("'", "")
    if letters:match("^[a-z]+$") and #letters > 4 then
        segment.tags = (segment.tags - Set({"abc"})) + Set({"smart_pinyin"})
        segment.prompt = "〔拼音〕"
    end
    -- affix_segmentor@smart_pinyin preserves pinyin after a partial selection.
    return true
end

return M
