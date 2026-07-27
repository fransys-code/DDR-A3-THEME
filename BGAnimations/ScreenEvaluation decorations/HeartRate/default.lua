-- Bilan cardio du morceau, sur l'ecran de resultats.
--
-- Rejoue le graphe construit pendant le gameplay : l'overlay de ScreenGameplay
-- publie ses echantillons dans le global FRANSYS_HR.last (cf. docs/05), qui
-- survit au changement d'ecran. Ici on ne lit rien du capteur, on ne fait que
-- redessiner -- le pont peut meme etre arrete, le bilan reste affiche.
--
-- Meme habillage que le panneau de jeu : base bleu pale #C3D8FA, filets cyan
-- #00A4DC, bandeaux noirs pour le titre et les totaux, fontes du theme.
-- Difference : le trace se revele de gauche a droite a l'arrivee sur l'ecran.

local HR = FRANSYS_HR
local data = HR and HR.last

-- Pas de morceau mesure (pont eteint, ou entree directe sur l'ecran) : on
-- n'affiche rien du tout plutot qu'un panneau vide.
if not data or not data.avg or data.avg <= 0 then
	return Def.ActorFrame{}
end

-- Zones de FC partagees par Scripts/07 FransysHeartRate.lua.
local FC_MAX = FRANSYS_HR_FCMAX
local ZONES  = FRANSYS_HR_ZONES

local C_BASE  = color("#C3D8FA")
local C_RULE  = color("#00A4DC")
local C_BAR   = color("#000000")
local C_LABEL = color("#FFFFFF")
local C_GRID  = color("#2A3F5F")

local PW     = 250
local RULE   = 3
local HEAD   = 24
local FOOT   = 21
local PLOT_H = 66
local PH     = RULE * 2 + HEAD + FOOT + PLOT_H
local INSET  = 5

local COLS = data.cols or 92
local CW   = (PW - INSET * 2) / COLS
local GX0  = -PW + INSET
local GW   = PW - INSET * 2
local PLOT_Y0 = RULE + HEAD
local PLOT_Y1 = PLOT_Y0 + PLOT_H

local ZoneColor = FransysHR_ZoneColor

-- Echelle verticale : identique a celle du jeu (amplitude minimale 24 bpm),
-- pour que les deux graphes se comparent a l'oeil.
local lo, hi = data.trough or 0, data.peak or 0
if lo > hi then lo, hi = hi, lo end
local mid = (lo + hi) / 2
if hi - lo < 24 then lo, hi = mid - 12, mid + 12 end
lo, hi = math.floor(lo - 2), math.ceil(hi + 2)
local span = hi - lo

local t = Def.ActorFrame{}

-- --- Fond + filets cyan ------------------------------------------------------
t[#t+1] = Def.Quad{
	InitCommand = function(self)
		self:halign(1):valign(0):zoomto(PW, PH):diffuse(C_BASE):diffusealpha(0.85)
	end,
}
t[#t+1] = Def.Quad{
	InitCommand = function(self) self:halign(1):valign(0):zoomto(PW, RULE):diffuse(C_RULE) end,
}
t[#t+1] = Def.Quad{
	InitCommand = function(self) self:halign(1):valign(0):y(PH - RULE):zoomto(PW, RULE):diffuse(C_RULE) end,
}

-- --- Bandeau titre : libelle + pic du morceau --------------------------------
local HEAD_CY = RULE + HEAD / 2
t[#t+1] = Def.Quad{
	InitCommand = function(self)
		self:halign(1):valign(0):y(RULE):zoomto(PW, HEAD):diffuse(C_BAR):diffusealpha(0.88)
	end,
}
t[#t+1] = Def.BitmapText{
	Font = "_helveticaneuelt pro 55 roman 17px",
	InitCommand = function(self)
		self:halign(0):valign(0.5):xy(-PW + INSET + 2, HEAD_CY):zoom(0.6)
			:diffuse(C_LABEL):settext("HEART RATE")
	end,
}
-- Le libelle est cale a droite ; la valeur se pose a gauche de LUI, en mesurant
-- sa largeur reelle (GetZoomedWidth) plutot qu'en devinant une marge -- c'est
-- ce qui avait fait chevaucher les deux la premiere fois.
local peakLabel
t[#t+1] = Def.BitmapText{
	Font = "_helveticaneuelt pro 55 roman 17px",
	InitCommand = function(self)
		peakLabel = self
		self:halign(1):valign(0.5):xy(-INSET - 2, HEAD_CY):zoom(0.5)
			:diffuse(C_LABEL):diffusealpha(0.8):settext("PEAK BPM")
	end,
}
t[#t+1] = Def.BitmapText{
	Font = "_itc avant garde pro bk 20px",
	InitCommand = function(self)
		local gap = peakLabel and (peakLabel:GetZoomedWidth() + 8) or 60
		self:halign(1):valign(0.5):xy(-INSET - 2 - gap, HEAD_CY):zoom(0.9)
			:DiffuseAndStroke(ZoneColor(data.peak), Color.Black)
			:settext(tostring(math.floor(data.peak)))
	end,
	-- Petit accent a l'arrivee, comme les compteurs du theme.
	OnCommand = function(self) self:zoom(1.15):sleep(0.15):decelerate(0.25):zoom(0.9) end,
}

-- --- Zone de trace -----------------------------------------------------------
t[#t+1] = Def.Quad{
	InitCommand = function(self)
		self:halign(0):valign(0):xy(GX0, PLOT_Y0):zoomto(GW, PLOT_H)
			:diffuse(color("#F2F7FF")):diffusealpha(0.92)
	end,
}
for i = 1, 3 do
	t[#t+1] = Def.Quad{
		InitCommand = function(self)
			self:halign(0):valign(0):xy(GX0, PLOT_Y0 + (PLOT_H / 4) * i)
				:zoomto(GW, 1):diffuse(C_GRID):diffusealpha(0.16)
		end,
	}
end

-- Ligne de la moyenne : repere horizontal en pointille clair.
local avgRatio = (data.avg - lo) / span
if avgRatio > 0 and avgRatio < 1 then
	t[#t+1] = Def.Quad{
		InitCommand = function(self)
			self:halign(0):valign(0.5):xy(GX0, PLOT_Y1 - avgRatio * PLOT_H)
				:zoomto(GW, 1):diffuse(C_GRID):diffusealpha(0.45)
		end,
	}
end

-- Les colonnes, revelees de gauche a droite.
for i = 1, COLS do
	local v = data.samples and data.samples[i]
	if v then
		local ratio = (v - lo) / span
		if ratio < 0.04 then ratio = 0.04 elseif ratio > 1 then ratio = 1 end
		t[#t+1] = Def.Quad{
			InitCommand = function(self)
				self:halign(0):valign(1)
					:xy(GX0 + (i - 1) * CW, PLOT_Y1)
					:zoomto(CW - 0.5, 0):diffuse(ZoneColor(v))
			end,
			OnCommand = function(self)
				self:sleep(0.25 + i * 0.006):linear(0.12):zoomy(ratio * PLOT_H)
			end,
		}
	end
end

-- --- Bandeau totaux ----------------------------------------------------------
local FOOT_CY = PH - RULE - FOOT / 2
t[#t+1] = Def.Quad{
	InitCommand = function(self)
		self:halign(1):valign(0):y(PH - RULE - FOOT):zoomto(PW, FOOT)
			:diffuse(C_BAR):diffusealpha(0.88)
	end,
}
t[#t+1] = Def.BitmapText{
	Font = "_helveticaneuelt pro 55 roman 17px",
	InitCommand = function(self)
		self:halign(0):valign(0.5):xy(-PW + INSET + 2, FOOT_CY):zoom(0.55)
			:diffuse(C_LABEL)
			:settext(("AVG %d    MIN %d"):format(data.avg + 0.5, data.trough or 0))
	end,
}
t[#t+1] = Def.BitmapText{
	Font = "_helveticaneuelt pro 55 roman 17px",
	InitCommand = function(self)
		self:halign(1):valign(0.5):xy(-INSET - 2, FOOT_CY):zoom(0.5)
			:diffuse(C_LABEL):diffusealpha(0.65):settext(("%d-%d"):format(lo, hi))
	end,
}

-- Placement : a droite, au-dessus du panneau de stats (celui-ci est pose sur
-- (cx+168, cy+85) au zoom 0.667 pour une base 462x292, donc son bord haut est
-- vers cy-12). On reste au-dessus, et a droite de la jaquette.
t.InitCommand = function(self)
	self:xy(SCREEN_RIGHT - 14, _screen.cy - 196)
end
t.OffCommand = function(self)
	self:linear(0.2):diffusealpha(0)
end

return t
