-- 全局常量。无副作用，可被任意模块 require。
return {
    hour_to_tick = 216000,
    min_to_tick = 3600,

    not_admin_text = {'wn.permission-denied'},

    -- 跃迁后 level 会被 force.reset() 清零，需要在 reset 前后记录并恢复。
    persistent_infinite_tech_names = {
        'steel-plate-productivity', 'plastic-bar-productivity',
        'low-density-structure-productivity', 'rocket-fuel-productivity',
        'processing-unit-productivity', 'rocket-part-productivity',
        'research-productivity', 'mining-productivity-3'
    },
}
