if SERVER then
	AddCSLuaFile()
	resource.AddFile("materials/vgui/ttt/dynamic/roles/icon_curs.vmt")
	util.AddNetworkString("TTT2CursedSendTagRequest")
end

function ROLE:PreInitialize()
	self.color = Color(48, 25, 52, 255)
	self.abbr = "curs"
	
	self.fallbackTable = {}
	self.unknownTeam = true --Disables team chat (among other things)
	
	--Scores have no meaning to the cursed
	self.scoreKillsMultiplier = 0
	self.scoreTeamKillsMultiplier = 0
	
	--Materialistic pleasures have no meaning to the cursed
	self.preventFindCredits = true
	self.preventKillCredits = true
	self.preventTraitorAloneCredits = true
	
	--Winning, losing, and kinship among others have no meaning to the cursed
	self.defaultTeam = TEAM_NONE
	--The cursed cannot win if they stand alone.
	self.preventWin = true
	
	self.conVarData = {
		pct = 0.13,
		maximum = 1,
		minPlayers = 6,
		random = 30,
		traitorButton = 0,
		
		--Materialistic pleasures have no meaning to the cursed
		credits = 0,
		creditsTraitorKill = 0,
		creditsTraitorDead = 0,
		shopFallback = SHOP_DISABLED,
		
		togglable = true
	}
end

local function IsInSpecDM(ply)
	if SpecDM and (ply.IsGhost and ply:IsGhost()) then
		return true
	end
	
	return false
end

if SERVER then
	function ROLE:GiveRoleLoadout(ply, isRoleChange)
		if GetConVar("ttt2_role_swap_deagle_enable"):GetBool() then
			ply:GiveEquipmentWeapon("weapon_ttt2_role_swap_deagle")
		end
	end
	
	function ROLE:RemoveRoleLoadout(ply, isRoleChange)
		if GetConVar("ttt2_role_swap_deagle_enable"):GetBool() then
			--Hacky timer exists here because an internal SWEP:ShootBullet call will expect the owner of the role swap deagle to still be the owner after a successful shot.
			timer.Simple(0.2, function()
				ply:StripWeapon("weapon_ttt2_role_swap_deagle")
			end)
		end
	end
	
	hook.Add("TTT2PostPlayerDeath", "TTT2PostPlayerDeathCursed", function(ply)
		local respawn_delay = GetConVar("ttt2_cursed_seconds_until_respawn"):GetInt()
		--Always attempt to revive the Cursed if they happen to die.
		--A slight exception: If preventWin is false, then DO NOT revive the Cursed, as it would force other teams to constantly check for and kill the Cursed in order to win.
		if ply:GetSubRole() == ROLE_CURSED and respawn_delay > 0 and ply:GetSubRoleData().preventWin and not IsInSpecDM(ply) then
			local spawn_pos = nil
			if GetConVar("ttt2_cursed_respawn_at_mapspawn"):GetBool() then
				--This function will do many checks to ensure that the randomly selected spawn position is safe.
				local spawn_entity = spawn.GetRandomPlayerSpawnEntity(ply)
				if spawn_entity then
					spawn_pos = spawn_entity:GetPos()
				end
			end
			
			ply:Revive(respawn_delay, --Delay
				nil, --OnRevive function
				function(ply) --DoCheck function
					--Return false (do not go through with the revival) if doing so could cause issues
					return GetRoundState() == ROUND_ACTIVE and (not ply:Alive() or IsInSpecDM(ply))
				end,
				false, --needsCorpse
				false, --blocksRound (Prevents anyone from winning during respawn delay)
				nil, --OnFail function
				spawn_pos, --The player's respawn point (If nil, will be their corpse if present, and their point of death otherwise)
				nil --spawnEyeAngle
			)
		end
	end)
	
	hook.Add("EntityTakeDamage", "EntityTakeDamageCursed", function(target, dmg_info)
		if not IsValid(target) or not target:IsPlayer() then
			return
		end
		
		local attacker = dmg_info:GetAttacker()
		local attacker_is_cursed = (IsValid(attacker) and attacker:IsPlayer() and attacker:GetSubRole() == ROLE_CURSED and not IsInSpecDM(attacker))
		
		--Cursed can't deal any damage to any player.
		--If damage_immunity is set, then the Cursed can't receive any damage either.
		if attacker_is_cursed or (GetConVar("ttt2_cursed_damage_immunity"):GetBool() and target:GetSubRole() == ROLE_CURSED and not IsInSpecDM(target) and target:GetSubRoleData().preventWin) then
			dmg_info:SetDamage(0)
		end
	end)
	
	net.Receive("TTT2CursedSendTagRequest", function(len, ply)
		--Determine if the Cursed is looking at someone who can be "tagged", and swap roles if they can.
		local trace = ply:GetEyeTrace(MASK_SHOT_HULL)
		local dist = trace.StartPos:Distance(trace.HitPos)
		local tgt = trace.Entity
		CURS_DATA.AttemptSwap(ply, tgt, dist)
	end)
end

if CLIENT then
	hook.Add("TTTRenderEntityInfo", "TTTRenderEntityInfoCursed", function(tData)
		local client = LocalPlayer()
		local ent = tData:GetEntity()
		
		--If the player can tag the player they're looking at, inform them by putting a notification
		--on the body. Also tell them which key they need to press.
		if CURS_DATA.CanSwapRoles(client, ent, tData:GetEntityDistance()) then
			local tag_key = string.upper(input.GetKeyName(bind.Find("CursedSendTagRequest")))
			
			if tData:GetAmountDescriptionLines() > 0 then
				tData:AddDescriptionLine()
			end
			
			tData:AddDescriptionLine(LANG.GetParamTranslation("PRESS_TO_TAG_" .. CURSED.name, {k = tag_key}), CURSED.color)
		end
	end)
	
	local function SendTagRequest()
		local client = LocalPlayer()
		if IsInSpecDM(client) then
			return
		end
		
		net.Start("TTT2CursedSendTagRequest")
		net.SendToServer()
	end
	bind.Register("CursedSendTagRequest", SendTagRequest, nil, "Cursed", "Tag", KEY_E)
end

------------
-- SHARED --
------------

hook.Add("TTTPlayerSpeedModifier", "TTTPlayerSpeedModifierCursed", function(ply, _, _, no_lag)
	if not IsValid(ply) or ply:GetSubRole() ~= ROLE_CURSED or IsInSpecDM(ply) then
		return
	end
	
	no_lag[1] = no_lag[1] * GetConVar("ttt2_cursed_speed_multi"):GetFloat()
end)

hook.Add("TTT2StaminaDrain", "TTT2StaminaDrainCursed", function(ply, stamina_drain_mod)
	if not IsValid(ply) or ply:GetSubRole() ~= ROLE_CURSED or IsInSpecDM(ply) then
		return
	end
	
	stamina_drain_mod[1] = stamina_drain_mod[1] * GetConVar("ttt2_cursed_stamina_drain"):GetFloat()
end)

hook.Add("TTT2StaminaRegen", "TTT2StaminaRegenCursed", function(ply, stamina_regen_mod)
	if not IsValid(ply) or ply:GetSubRole() ~= ROLE_CURSED or IsInSpecDM(ply) then
		return
	end
	
	stamina_regen_mod[1] = stamina_regen_mod[1] * GetConVar("ttt2_cursed_stamina_regen"):GetFloat()
end)