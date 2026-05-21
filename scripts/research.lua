-- 研究完成时的两种动作：
--   1. 完成产能类无限科技 → 触发跃迁
--   2. 完成其它无限科技 → 自动把下一级加入研究队列
local constants = require('scripts.constants')
local reset = require('scripts.reset')

script.on_event(defines.events.on_research_finished, function(event)
    if event.by_script then
        return
    end
    local research = event.research
    local research_name = research.name
    local force = game.forces.player

    for _, tech_name in pairs(constants.persistent_infinite_tech_names) do
        if tech_name == research_name then
            game.print({'wn.persistent-tech', research.name, research.level})
            reset.reset()
        else
            -- 自动添加非产能无限科技到队列
            if research.level > research.prototype.level then
                local queue = force.research_queue
                queue[table_size(queue) + 1] = research
                force.research_queue = queue
                game.print({'wn.start-tech', research.name, research.level + 1})
            end
        end
    end
end)
