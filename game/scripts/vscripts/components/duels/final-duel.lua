-- Taken from bb template
if FinalDuel == nil then
  DebugPrint ( 'Creating new FinalDuel object.' )
  FinalDuel = class({})
  Debug.EnabledModules['duels:final-duel'] = true
end

-- Duels.onStart = DuelStartEvent.listen
-- Duels.onPreparing = DuelPreparingEvent.listen
-- Duels.onEnd = DuelEndEvent.listen

function FinalDuel:Init ()
  self.moduleName = "FinalDuel"
  Duels.onEnd(partial(FinalDuel.EndDuelHandler, FinalDuel))
  Duels.onPreparing(partial(FinalDuel.PreparingDuelHandler, FinalDuel))
  Duels.onStart(partial(FinalDuel.StartDuelHandler, FinalDuel))
  PointsManager.onWinner(partial(FinalDuel.Trigger, FinalDuel))
  PointsManager.onLimitChanged(partial(FinalDuel.CheckCancelDuel, FinalDuel))
end

function FinalDuel:CheckCancelDuel ()
  if not self.isCurrentlyFinalDuel then
    return
  end
  local limit = PointsManager:GetLimit()
  local goodPoints = PointsManager:GetPoints(DOTA_TEAM_GOODGUYS)
  local badPoints = PointsManager:GetPoints(DOTA_TEAM_BADGUYS)
  if goodPoints < limit and badPoints < limit then
    Duels:CancelDuel()
    self.isCurrentlyFinalDuel = false
    self.needsFinalDuel = false
  end
end

function FinalDuel:Trigger (team)
  local limit = PointsManager:GetLimit()
  local goodPoints = PointsManager:GetPoints(DOTA_TEAM_GOODGUYS)
  local badPoints = PointsManager:GetPoints(DOTA_TEAM_BADGUYS)
  if goodPoints < limit and badPoints < limit then
    self.needsFinalDuel = false
    return
  end
  self.needsFinalDuel = true

  if Duels.currentDuel then
    -- let end of duel handler sort it out
    return
  end

  Duels:StartDuel({
    players = 0,
    timeout = Duels:GetDuelTimeout(2),
    isFinalDuel = true,
    forceAllPlayers = true
  })
end

function FinalDuel:PreparingDuelHandler (keys)
  if self.needsFinalDuel then
    self.isCurrentlyFinalDuel = true
    self.needsFinalDuel = false
    Notifications:TopToAll({text="#duel_final_duel_imminent", duration=4.0})
  end
end

function FinalDuel:StartDuelHandler (keys)
  local limit = PointsManager:GetLimit()
  local goodPoints = PointsManager:GetPoints(DOTA_TEAM_GOODGUYS)
  local badPoints = PointsManager:GetPoints(DOTA_TEAM_BADGUYS)
  self.goodCanWin = goodPoints >= limit
  self.badCanWin = badPoints >= limit
  self.pointDifference = math.abs(goodPoints - badPoints)

  if self.isCurrentlyFinalDuel then
    local extraMessage = ""
    if self.goodCanWin then
      if self.badCanWin then
        extraMessage = "#duel_final_duel_both_can_win"
      else
        extraMessage = "#duel_final_duel_good_can_win"
      end
    else
      extraMessage = "#duel_final_duel_bad_can_win"
    end

    Notifications:TopToAll({text="#duel_final_duel_start", duration=10.0})
    Notifications:TopToAll({text=extraMessage, duration=10.0})
  end
end

function FinalDuel:EndDuelHandler (currentDuel)
  if not self.isCurrentlyFinalDuel then
    DebugPrint('Normal Duel has ended')
    if self.needsFinalDuel then
      -- a duel just ended and we need to trigger the final duel
      Timers:CreateTimer(10, function ()
        FinalDuel:Trigger()
      end)
    end
    return
  end
  DebugPrint('Final Duel has ended')
  self.isCurrentlyFinalDuel = false
  self.needsFinalDuel = false

  -- currentDuel.duelEnd1
  -- currentDuel.duelEnd2
  local loser = currentDuel.duelEnd1
  if loser == true then
    loser = currentDuel.duelEnd2
  end

  if loser == "bad" and self.goodCanWin then
    PointsManager:SetWinner(DOTA_TEAM_GOODGUYS)
    return
  end
  if loser == "good" and self.badCanWin then
    PointsManager:SetWinner(DOTA_TEAM_BADGUYS)
    return
  end

  -- Increase the score limit
  PointsManager:IncreaseLimit()

  -- Give points to winners as a comeback compensation
  local playerCount = PlayerResource:SafeGetTeamPlayerCount()
  local pointAward = math.ceil(playerCount * self.pointDifference / 20)
  -- Capping the reward
  if pointAward > playerCount then
    pointAward = playerCount
  end
  -- If the loser is DOTA_TEAM_BADGUYS and they had a chance to win, give points to DOTA_TEAM_GOODGUYS
  if loser == "bad" and self.badCanWin then
    PointsManager:AddPoints(DOTA_TEAM_GOODGUYS, pointAward)
  end
  -- If the loser is DOTA_TEAM_GOODGUYS and they had a chance to win, give points to DOTA_TEAM_BADGUYS
  if loser == "good" and self.goodCanWin then
    PointsManager:AddPoints(DOTA_TEAM_BADGUYS, pointAward)
  end

  self.goodCanWin = false
  self.badCanWin = false
end
