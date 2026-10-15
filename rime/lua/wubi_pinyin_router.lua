-- Short input shares Wubi and pinyin; long input uses native pinyin.
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
    if letters:match("^[a-z]+$") then
        local previous = segmentation.size >= 2 and segmentation:get_at(-2) or nil
        local continuation = previous and previous:has_tag("partial")
            and previous:has_tag("smart_pinyin")
        segment.tags = segment.tags + Set({"smart_pinyin"})
        if #letters > 4 or continuation then
            segment.tags = segment.tags - Set({"abc"})
            segment.prompt = "〔拼音〕"
        end
    end
    -- affix_segmentor@smart_pinyin preserves pinyin after a partial selection.
    return true
end

return M
