职业系统、吃其他物品作为经验，化为：背包里初始物品
更多事件
更多文案

/c local r = 333;game.forces.player.chart(game.surfaces.nauvis, {{-r, -r}, {r, r}}))


  /sc local s=storage local now=game.tick local rs=s.run_start_tick or now local wh=s.warp_hours
  local rem=(wh or 0)*216000-(now-rs)
  game.players.hncsltok.print('now='..now..'  run_start='..tostring(s.run_start_tick)..'  elapsed='..(now-rs))
    game.players.hncsltok.print('warp_hours='..tostring(wh)..'  warp_initial_minutes='..tostring(s.warp_initial_minutes))
    game.players.hncsltok.print('remaining_ticks='..tostring(rem)..'  ('..string.format('%.1f',rem/3600)..' 分钟)')
    game.players.hncsltok.print('warp_fx='..serpent.line(s.warp_fx)..'  vote_delta='..tostring(s.warp_vote_delta))
    

一亿瓶 = 10^8 = (10^4) = 1000 级


