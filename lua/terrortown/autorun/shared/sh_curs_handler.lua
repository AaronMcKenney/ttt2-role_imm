if SERVER then
	AddCSLuaFile()
end

CURS_DATA = {}

local function IsInSpecDM(ply)
	if SpecDM and (ply.IsGhost and ply:IsGhost()) then
		return true
	end
	
	return false
end

function CURS_DATA.CanSwapRoles(ply, tgt, dist)
	if GetRoundState() == ROUND_ACTIVE and IsValid(ply) and ply:IsPlayer() and ply:Alive() and not IsInSpecDM(ply) and ply:GetSubRole() == ROLE_CURSED and IsValid(tgt) and tgt:IsPlayer() and tgt:Alive() and not IsInSpecDM(tgt) and tgt.curs_last_tagged == nil and dist <= GetConVar("ttt2_cursed_tag_dist"):GetInt() then
		return true
	else
		return false
	end
end

if SERVER then
	function CURS_DATA.SwapRoles(old_cursed, tgt)
		--Return early if both players have the same role and team, making sure to inform the tagger so they don't think the role is broken
		--Edge case: Break off early if a Dop!Cursed tries to swap with a regular Cursed, as a Dop!Cursed can't lose their team.
		if old_cursed:GetSubRole() == tgt:GetSubRole() and (old_cursed:GetTeam() == tgt:GetTeam() or (old_cursed:GetTeam() == TEAM_DOPPELGANGER and tgt:GetTeam() == TEAM_NONE)) then
			LANG.Msg(old_cursed, "SAME_" .. CURSED.name, nil, MSG_MSTACK_WARN)
			return false
		end
		
		local old_cursed_role = old_cursed:GetSubRole()
		local old_cursed_team = old_cursed:GetTeam()
		local backsies_timer_len = GetConVar("ttt2_cursed_backsies_timer"):GetInt()
		
		--Immediately mark the Cursed with no backsies to prevent a counterswap.
		old_cursed.curs_last_tagged = tgt:SteamID64()
		
		--Give the Cursed their new role/team first so as to not accidentally end the game due to preventWin
		if not (DOPPELGANGER and old_cursed_team == TEAM_DOPPELGANGER) then
			old_cursed:SetRole(tgt:GetSubRole(), tgt:GetTeam())
			tgt:SetRole(old_cursed_role, old_cursed_team)
		else
			--Edge case: If a Dop!Cursed tags a player, they shall keep their team, but change roles.
			--This is done because otherwise a Dop!Cursed is mechanically the same as a normal Cursed, due to preventWin making them useless.
			--This method is more fun for the Dop.
			old_cursed:SetRole(tgt:GetSubRole(), old_cursed_team)
			
			--Hardcode the tgt's team to TEAM_NONE, so that they are falsely lead to believe that they weren't tagged by a Doppelganger.
			tgt:SetRole(old_cursed_role, TEAM_NONE)
		end
		SendFullStateUpdate()
		
		--Now that the roles/teams have been switched, unmark any player that is registered as having tagged the previous Cursed
		for _, ply in ipairs(player.GetAll()) do
			if ply.curs_last_tagged == old_cursed:SteamID64() then
				ply.curs_last_tagged = nil
				STATUS:RemoveStatus(ply, "ttt2_curs_no_backsies")
			end
		end
		
		--Finally take care of ensuring no backsies occur.
		if backsies_timer_len > 0 then
			STATUS:AddTimedStatus(old_cursed, "ttt2_curs_no_backsies", backsies_timer_len, true)
			timer.Simple(backsies_timer_len, function()
				old_cursed.curs_last_tagged = nil
			end)
		else
			STATUS:AddStatus(old_cursed, "ttt2_curs_no_backsies")
		end
		
		return true
	end

	function CURS_DATA.AttemptSwap(ply, tgt, dist)
		local did_swap = false
		
		if CURS_DATA.CanSwapRoles(ply, tgt, dist) then
			did_swap = CURS_DATA.SwapRoles(ply, tgt)
		elseif tgt.curs_last_tagged ~= nil then
			LANG.Msg(ply, "NO_BACKSIES_" .. CURSED.name, nil, MSG_MSTACK_WARN)
		end
		
		return did_swap
	end
	
	hook.Add("TTTEndRound", "TTTEndRoundCursedData", function()
		for _, ply in ipairs(player.GetAll()) do
			ply.curs_last_tagged = nil
			STATUS:RemoveStatus(ply, "ttt2_curs_no_backsies")
		end
	end)
end

if CLIENT then
	hook.Add("Initialize", "InitializeCursedData", function()
		STATUS:RegisterStatus("ttt2_curs_no_backsies", {
			hud = Material("vgui/ttt/icon_cursed_no_backsies.png"),
			type = "good"
		})
	end)
end