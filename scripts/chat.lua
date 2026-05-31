-- 聊天喵化（头顶气泡版）：玩家发言后，按其【客户端语言 player.locale】在角色头顶飘一段"消息 + 后缀"文字。
--
-- 为什么用头顶飘字而非加到聊天框：Factorio 的 on_console_chat 是只读通知，改不了/撤不掉原聊天，
-- 往聊天框补发会让每句出现两行。改在【角色头顶】用 rendering 飘字，聊天框保持原生单行、不重复。
-- 走 events 总线（多订阅安全、单个出错不崩服）。
local events = require('scripts.events')

local M = {}

-- 按 locale 选后缀；查不到用默认（en）。Factorio 日语 locale 代码是 'ja'（不是 'jp'）。
local SUFFIX = {
    ['zh-CN'] = '喵~',
    ['ja']    = 'にゃ~',
}
local DEFAULT_SUFFIX = ' meow~'

events.on(defines.events.on_console_chat, function(e)
    if not e.player_index then return end          -- 控制台/脚本消息无玩家，跳过
    local p = game.get_player(e.player_index)
    if not (p and p.valid and e.message) then return end
    if e.message:sub(1, 1) == '/' then return end   -- 以 / 开头的当命令、不喵化

    local char = p.character
    if not (char and char.valid) then return end     -- 没角色（死亡/观战中）就不飘字
    local suffix = SUFFIX[p.locale] or DEFAULT_SUFFIX
    -- 跨表面坑：挂角色的渲染必须用【角色自己的 surface】，否则跃迁/复活瞬间会报跨表面错。
    rendering.draw_text{
        text = e.message .. suffix,
        surface = char.surface,
        target = {entity = char, offset = {0, -2.6}},   -- 头顶上方
        color = p.chat_color,
        scale = 1.2,
        alignment = 'center',
        vertical_alignment = 'bottom',
        time_to_live = 240,                             -- ~4 秒后自动消失，不留存档
    }
end)

return M
