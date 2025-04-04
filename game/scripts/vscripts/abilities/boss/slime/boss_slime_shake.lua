LinkLuaModifier("modifier_boss_slime_shake_slow", "abilities/boss/slime/boss_slime_shake.lua", LUA_MODIFIER_MOTION_NONE)

------------------------------------------------------------------------------------

boss_slime_shake = class(AbilityBaseClass)

------------------------------------------------------------------------------------

function boss_slime_shake:GetPlaybackRateOverride()
	return 2.0
end

function boss_slime_shake:Precache(context)
  PrecacheResource("particle", "particles/units/heroes/heroes_underlord/abyssal_underlord_firestorm_wave.vpcf", context)
  PrecacheResource("particle", "particles/darkmoon_creep_warning.vpcf", context)
end

------------------------------------------------------------------------------------

local function RandomPointInsideCircle(x, y, radius, minLength)
	local dist = math.random((minLength or 0), radius)
	local angle = math.random(0, math.pi * 2)

	local xOffset = dist * math.cos(angle)
	local yOffset = dist * math.sin(angle)

	return Vector(x + xOffset, y + yOffset, 0)
end

------------------------------------------------------------------------------------

local function RandomPointsInsideCircleUniform( pos, radius, count, uniform, minLength )
	local points = {}

	local function CheckPoint( v )
		for i=1,#points do
			if (points[i] - v):Length2D() < uniform then return false end
		end
		return true
	end

	local fallback = 70

	for i=1,count do
		local point

		repeat
			point = RandomPointInsideCircle(pos.x, pos.y, radius, minLength)
			fallback = fallback - 1
			if fallback == 0 then
				return points
			end
		until CheckPoint(point)
			point.z = pos.z
			table.insert(points, point)
	end

	return points
end

------------------------------------------------------------------------------------

function boss_slime_shake:OnAbilityPhaseStart()
  local caster = self:GetCaster()

  -- Make the caster uninterruptible while casting this ability
  caster:AddNewModifier(caster, self, "modifier_anti_stun_oaa", {duration = self:GetCastPoint() + self:GetChannelTime()})

  return true
end

------------------------------------------------------------------------------------

function boss_slime_shake:FireProjectile(point)
	local caster = self:GetCaster()
	local minSize = self:GetSpecialValueFor("projectile_min_size")
	local maxSize = self:GetSpecialValueFor("projectile_max_size")
	local size = RandomInt(minSize, maxSize)
	local delay = self:GetSpecialValueFor("delay")

	local pos = GetGroundPosition(point, caster)

  -- Warning particle
  local indicator = ParticleManager:CreateParticle("particles/darkmoon_creep_warning.vpcf", PATTACH_CUSTOMORIGIN, caster)
  ParticleManager:SetParticleControl(indicator, 0, pos)
  ParticleManager:SetParticleControl(indicator, 1, Vector(size, size, size))
  ParticleManager:SetParticleControl(indicator, 15, Vector(255, 26, 26))

	DebugDrawCircle(pos + Vector(0,0,32), Vector(255,0,0), 55, size, false, delay)

  Timers:CreateTimer(delay, function()
    -- Removing warning particle
    if indicator then
      ParticleManager:DestroyParticle(indicator, true)
      ParticleManager:ReleaseParticleIndex(indicator)
    end
    if caster and not caster:IsNull() then
      -- Create Firestorm particle
      local wave = ParticleManager:CreateParticle("particles/units/heroes/heroes_underlord/abyssal_underlord_firestorm_wave.vpcf", PATTACH_CUSTOMORIGIN, caster)
      ParticleManager:SetParticleControl(wave, 0, pos)
      ParticleManager:ReleaseParticleIndex(wave)
    end
  end)

  local damageTable = {
    attacker = caster,
    damage = self:GetSpecialValueFor("damage"),
    damage_type = self:GetAbilityDamageType(),
    ability = self
  }

  local ability = self

  Timers:CreateTimer(delay + 0.6, function()
    if caster and not caster:IsNull() then
      local units = FindUnitsInRadius(
        caster:GetTeamNumber(),
        pos,
        nil,
        size,
        DOTA_UNIT_TARGET_TEAM_ENEMY,
        DOTA_UNIT_TARGET_HERO + DOTA_UNIT_TARGET_BASIC,
        DOTA_UNIT_TARGET_FLAG_NONE,
        FIND_ANY_ORDER,
        false
      )

      for _, unit in pairs(units) do
        -- Apply modifiers
        unit:AddNewModifier( caster, ability, "modifier_boss_slime_shake_slow", { duration = ability:GetSpecialValueFor("slow_duration") })

        -- Apply damage
        damageTable.victim = unit
        ApplyDamage(damageTable)
      end
    end
  end)
end

------------------------------------------------------------------------------------

function boss_slime_shake:OnSpellStart()
	local caster = self:GetCaster()
	--local minSize = self:GetSpecialValueFor("projectile_min_size")
	local maxSize = self:GetSpecialValueFor("projectile_max_size")
	self.points = RandomPointsInsideCircleUniform( caster:GetAbsOrigin(), self:GetSpecialValueFor("radius"), self:GetSpecialValueFor("projectile_count"), maxSize, maxSize)
	self.n = 1
	self.t = 0
end

------------------------------------------------------------------------------------

function boss_slime_shake:OnChannelThink(flInterval)
	self.t = self.t + flInterval
	if self.n and self.points[self.n] and self.t > (self:GetChannelTime() / #self.points) * self.n then
		self:FireProjectile(self.points[self.n])
		self.n = self.n + 1
	end
end

---------------------------------------------------------------------------------------------------

modifier_boss_slime_shake_slow = class(ModifierBaseClass)

function modifier_boss_slime_shake_slow:IsHidden()
  return false
end

function modifier_boss_slime_shake_slow:IsDebuff()
  return true
end

function modifier_boss_slime_shake_slow:IsPurgable()
  return true
end

function modifier_boss_slime_shake_slow:OnCreated()
  local ability = self:GetAbility()
  local movement_slow = ability:GetSpecialValueFor("slow")
  local attack_slow = ability:GetSpecialValueFor("attack_slow")

  self.attack_speed = attack_slow
  -- Move Speed Slow is reduced with Slow Resistance
  self.slow = movement_slow --parent:GetValueChangedBySlowResistance(movement_slow)
end

function modifier_boss_slime_shake_slow:OnRefresh()
  self:OnCreated()
end

function modifier_boss_slime_shake_slow:DeclareFunctions()
  return {
    MODIFIER_PROPERTY_MOVESPEED_BONUS_PERCENTAGE,
    MODIFIER_PROPERTY_ATTACKSPEED_BONUS_CONSTANT,
  }
end

function modifier_boss_slime_shake_slow:GetModifierMoveSpeedBonus_Percentage()
  return 0 - math.abs(self.slow)
end

function modifier_boss_slime_shake_slow:GetModifierAttackSpeedBonus_Constant()
  return 0 - math.abs(self.attack_speed)
end
