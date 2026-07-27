-- Rythme cardiaque courant, en haut a droite de l'ecran de selection.
--
-- Utile entre deux morceaux : on voit sa FC redescendre avant de relancer.
-- Etat et connexion partages via Scripts/07 FransysHeartRate.lua.
--
-- PIEGE (docs/03 #6) : SetUpdateFunction n'existe que sur ActorFrame. Posee sur
-- un Def.Actor elle n'est jamais appelee ET ne log aucune erreur.

local HR = FransysHR()

-- Palette A3, echantillonnee dans les PNG du thème.
local C_RULE  = color("#00A4DC")
local C_BAR   = color("#000000")
local C_LABEL = color("#FFFFFF")

local PW   = 150
local PH   = 24
local RULE = 2
local INSET = 5

local t = Def.ActorFrame{}

t[#t+1] = Def.Quad{
	InitCommand = function(self)
		self:halign(1):valign(0):zoomto(PW, PH):diffuse(C_BAR):diffusealpha(0.85)
	end,
}
t[#t+1] = Def.Quad{
	InitCommand = function(self)
		self:halign(1):valign(0):zoomto(PW, RULE):diffuse(C_RULE)
	end,
}

t[#t+1] = Def.BitmapText{
	Font = "_helveticaneuelt pro 55 roman 17px",
	InitCommand = function(self)
		self:halign(0):valign(0.5):xy(-PW + INSET, RULE + (PH - RULE) / 2):zoom(0.45)
			:diffuse(C_LABEL):diffusealpha(0.75):settext("HEART RATE")
	end,
}

-- "BPM" cale a droite, la valeur a gauche de LUI en mesurant sa largeur reelle :
-- deviner une marge en dur fait se toucher les deux textes (cf. docs/05).
local bpmLabel
t[#t+1] = Def.BitmapText{
	Font = "_helveticaneuelt pro 55 roman 17px",
	InitCommand = function(self)
		bpmLabel = self
		self:halign(1):valign(0.5):xy(-INSET, RULE + (PH - RULE) / 2):zoom(0.4)
			:diffuse(C_LABEL):diffusealpha(0.7):settext("BPM")
	end,
}
t[#t+1] = Def.BitmapText{
	Font = "_itc avant garde pro bk 20px",
	Name = "Value",
	InitCommand = function(self)
		local gap = bpmLabel and (bpmLabel:GetZoomedWidth() + 5) or 22
		self:halign(1):valign(0.5):xy(-INSET - gap, RULE + (PH - RULE) / 2):zoom(0.7)
			:DiffuseAndStroke(FransysHR_ZoneColor(0), Color.Black):settext("---")
	end,
}

t.InitCommand = function(self)
	self:xy(SCREEN_RIGHT - 14, SCREEN_TOP + 8)

	local value = self:GetChild("Value")
	local acc, shown = 0, -1

	self:SetUpdateFunction(function(_, dt)
		acc = acc + dt
		if acc < 0.5 then return end
		acc = 0

		local bpm = FransysHR_PollFile()   -- ne lit le fichier que si le WS est absent
		if bpm > 0 then
			value:settext(tostring(bpm)):DiffuseAndStroke(FransysHR_ZoneColor(bpm), Color.Black)
			if bpm ~= shown then
				value:stoptweening():zoom(0.78):linear(0.12):zoom(0.7)
				shown = bpm
			end
		else
			value:settext(HR.connected and "---" or "OFF")
				:DiffuseAndStroke(FransysHR_ZoneColor(0), Color.Black)
		end
	end)
end

return t
