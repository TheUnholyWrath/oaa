function Spawn( entityKeyValues )
  if not thisEntity or not IsServer() then
    return
  end

  thisEntity.IgniteAbility = thisEntity:FindAbilityByName( "ogre_seer_area_ignite" )
  thisEntity.BloodlustAbility = thisEntity:FindAbilityByName( "ogre_magi_channelled_bloodlust" )

  thisEntity:SetContextThink( "OgreSeerThink", OgreSeerThink, 1 )
end

--------------------------------------------------------------------------------

function FindOgreBoss()
  local friendlies = FindUnitsInRadius(
    thisEntity:GetTeamNumber(),
    thisEntity:GetOrigin(),
    nil,
    thisEntity:GetCurrentVisionRange(),
    DOTA_UNIT_TARGET_TEAM_FRIENDLY,
    DOTA_UNIT_TARGET_ALL,
    DOTA_UNIT_TARGET_FLAG_INVULNERABLE + DOTA_UNIT_TARGET_FLAG_OUT_OF_WORLD,
    FIND_ANY_ORDER,
    false
  )
  for _, friendly in pairs ( friendlies ) do
    if friendly and not friendly:IsNull() then
      if friendly:GetUnitName() == "npc_dota_creature_ogre_tank_boss" then
        return friendly
      end
    end
  end
  return nil
end

--------------------------------------------------------------------------------

function OgreSeerThink()
  if GameRules:State_Get() >= DOTA_GAMERULES_STATE_POST_GAME or not IsValidEntity(thisEntity) or not thisEntity:IsAlive() then
    return -1
  end

  if thisEntity:IsDominated() or thisEntity:IsIllusion() then
    return -1
  end

  if GameRules:IsGamePaused() then
    return 1
  end

  if not thisEntity.bInitialized then
    thisEntity.vInitialSpawnPos = thisEntity:GetAbsOrigin()
    thisEntity.bHasAgro = false
    thisEntity.fAgroRange = thisEntity:GetAcquisitionRange()
    thisEntity:SetIdleAcquire(false)
    thisEntity:SetAcquisitionRange(0)
    thisEntity.hOgreBoss = FindOgreBoss()
    thisEntity.BossTier = thisEntity.BossTier or 3
    thisEntity.bInitialized = true
  end

  if not thisEntity.hOgreBoss or thisEntity.hOgreBoss:IsNull() or not thisEntity.hOgreBoss:IsAlive() then
    thisEntity.hOgreBoss = FindOgreBoss()
  end

  local agro_center = thisEntity.vInitialSpawnPos
  if thisEntity.hOgreBoss and not thisEntity.hOgreBoss:IsNull() then
    agro_center = thisEntity.hOgreBoss.vInitialSpawnPos
  end
  local enemies = FindUnitsInRadius(
    thisEntity:GetTeamNumber(),
    agro_center,
    nil,
    2*BOSS_LEASH_SIZE,
    DOTA_UNIT_TARGET_TEAM_ENEMY,
    DOTA_UNIT_TARGET_HERO + DOTA_UNIT_TARGET_BASIC,
    DOTA_UNIT_TARGET_FLAG_MAGIC_IMMUNE_ENEMIES + DOTA_UNIT_TARGET_FLAG_FOW_VISIBLE,
    FIND_ANY_ORDER,
    false
  )
  local fDistanceToOrigin = ( thisEntity:GetOrigin() - thisEntity.vInitialSpawnPos ):Length2D()
  local hasDamageThreshold = thisEntity:GetHealth() / thisEntity:GetMaxHealth() < 99/100
  -- Difference from tier 5
  if thisEntity.hOgreBoss and not thisEntity.hOgreBoss:IsNull() then
    hasDamageThreshold = thisEntity:GetHealth() / thisEntity:GetMaxHealth() < 98/100
  end

  -- Agro
  if thisEntity.hOgreBoss and not thisEntity.hOgreBoss:IsNull() and thisEntity.hOgreBoss:IsAlive() and not thisEntity.hOgreBoss.bHasAgro and thisEntity.bHasAgro and #enemies == 0 then
    DebugPrint("Ogre Seer Deagro")
    thisEntity.bHasAgro = false
    thisEntity:SetIdleAcquire(false)
    thisEntity:SetAcquisitionRange(0)
    return 2
  elseif not thisEntity.hOgreBoss or thisEntity.hOgreBoss:IsNull() or not thisEntity.hOgreBoss:IsAlive() or (hasDamageThreshold and #enemies > 0) or (thisEntity.hOgreBoss and not thisEntity.hOgreBoss:IsNull() and thisEntity.hOgreBoss.bHasAgro) then
    if not thisEntity.bHasAgro then
      DebugPrint("Ogre Seer Agro")
      thisEntity.bHasAgro = true
      thisEntity:SetIdleAcquire(true)
      thisEntity:SetAcquisitionRange(thisEntity.fAgroRange)
    end
  end

  -- Leash
  if not thisEntity.bHasAgro or #enemies == 0 or fDistanceToOrigin > 800 then
    if fDistanceToOrigin > 10 then
      return RetreatHome()
    end
    return 1
  end

	if thisEntity.BloodlustAbility and thisEntity.BloodlustAbility:IsChanneling() then
		return 0.5
	end

  local bIgniteReady = #enemies > 0 and thisEntity.IgniteAbility and thisEntity.IgniteAbility:IsFullyCastable()
  local bBloodlustReady = thisEntity.hOgreBoss and not thisEntity.hOgreBoss:IsNull() and thisEntity.BloodlustAbility and thisEntity.BloodlustAbility:IsFullyCastable()
  local fBloodlustCastRange = thisEntity.BloodlustAbility:GetCastRange( thisEntity:GetOrigin(), nil )

	if bIgniteReady then
		return IgniteArea( enemies[ RandomInt( 1, #enemies ) ] )
	end

  if bBloodlustReady then
    local fDistanceToOgreBoss = ( thisEntity.hOgreBoss:GetOrigin() - thisEntity:GetOrigin() ):Length2D()
    -- If can cast bloodlust do it
    if ( fDistanceToOgreBoss <= fBloodlustCastRange )   then
      return Bloodlust( thisEntity.hOgreBoss )
    -- If cannot cast try to ignite first, then approach ogre
    elseif ( fDistanceToOgreBoss > 600 ) and ( fDistanceToOgreBoss < 1500 ) and ( not bIgniteReady )  then
      return Approach( thisEntity.hOgreBoss )
    end
	end

	local fFuzz = RandomFloat( -0.1, 0.1 ) -- Adds some timing separation to these seers
	return 0.5 + fFuzz
end

--------------------------------------------------------------------------------

function Approach( hUnit )
  local vToUnit = hUnit:GetOrigin() - thisEntity:GetOrigin()
  vToUnit = vToUnit:Normalized()
  local speed = thisEntity:GetIdealSpeed()
  local think_time = 1
  local distance = speed * think_time

  ExecuteOrderFromTable({
    UnitIndex = thisEntity:entindex(),
    OrderType = DOTA_UNIT_ORDER_MOVE_TO_POSITION,
    Position = thisEntity:GetOrigin() + vToUnit * distance,
    Queue = false,
  })

  return think_time + 0.1
end

--------------------------------------------------------------------------------

function Bloodlust( hUnit )
  local ability = thisEntity.BloodlustAbility
  local cast_point = ability:GetCastPoint()

  thisEntity:CastAbilityOnTarget( hUnit, ability, thisEntity:entindex() ) -- maybe wrong third argument, replace with ExecuteOrderFromTable?

  return cast_point + 0.1
end

--------------------------------------------------------------------------------

function IgniteArea( hEnemy )
  local ability = thisEntity.IgniteAbility
  local cast_point = ability:GetCastPoint()

  thisEntity:CastAbilityOnPosition( hEnemy:GetOrigin(), ability, thisEntity:entindex() ) -- maybe wrong third argument, replace with ExecuteOrderFromTable?

  return cast_point + 0.1
end

--------------------------------------------------------------------------------

function RetreatHome()
  -- Leash
  ExecuteOrderFromTable({
    UnitIndex = thisEntity:entindex(),
    OrderType = DOTA_UNIT_ORDER_MOVE_TO_POSITION,
    Position = thisEntity.vInitialSpawnPos,
    Queue = false,
  })

  local speed = thisEntity:GetIdealSpeedNoSlows()
  local location = thisEntity:GetAbsOrigin()
  local distance = (location - thisEntity.vInitialSpawnPos):Length2D()
  local retreat_time = distance / speed

  return retreat_time + 0.1
end
