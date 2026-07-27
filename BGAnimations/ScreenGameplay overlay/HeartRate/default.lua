-- Rythme cardiaque temps reel (Polar H10) + graphe d'evolution sur la duree du
-- morceau, en haut a droite de ScreenGameplay.
--
-- Source : scripts/hr_bridge.py (repo fransys-ddr) lit le H10 en BLE cote Windows
-- et pousse la BPM en texte brut sur ws://127.0.0.1:8765.
--
-- Prerequis : ajouter 127.0.0.1 a HttpAllowHosts dans Save/Preferences.ini
-- (preference Immutable -> editer jeu ferme). Sans ca, NETWORK:WebSocket refuse
-- l'URL et on retombe sur le fichier.
--
-- HABILLAGE : on reprend la grammaire visuelle des panneaux de donnees A3
-- (cf. "ScreenEvaluation decorations/frame") pour que ca lise comme un element
-- natif du theme, et pas comme un overlay colle par-dessus :
--   * fond bleu pale #C3D8FA a 85 % d'opacite (couleur de frame/base.png)
--   * filets cyan #00A4DC en haut et en bas (couleur de frame/data/BASE.png)
--   * bandeaux NOIRS pour la ligne de titre et la ligne de totaux, comme les
--     lignes "MAX COMBO" et "EX SCORE" du panneau de stats
--   * memes fontes que StepStats : _itc avant garde pro bk 20px pour les
--     chiffres, _helveticaneuelt pro 55 roman 17px pour les libelles
--
-- DEUX PIEGES A NE PAS RECASSER (cf. docs/03 pieges #6 et #7) :
--  1. SetUpdateFunction n'existe que sur ActorFrame. Sur un Def.Actor elle n'est
--     jamais appelee ET ne log aucune erreur.
--  2. Le callback onMessage survit a l'ecran, pas les acteurs. Il n'ecrit donc
--     QUE dans la table d'etat ; tout le rendu vit dans l'UpdateFunction.

-- Connexion, etat et zones de FC : partages par Scripts/07 FransysHeartRate.lua
-- (regler FC max et couleurs la-bas, un seul endroit pour les trois ecrans).
local HR        = FransysHR()
local FC_MAX    = FRANSYS_HR_FCMAX
local ZONES     = FRANSYS_HR_ZONES
local ZoneColor = FransysHR_ZoneColor

-- Palette A3 (echantillonnee dans les PNG du theme).
local C_BASE  = color("#C3D8FA")
local C_RULE  = color("#00A4DC")
local C_BAR   = color("#000000")
local C_LABEL = color("#FFFFFF")
local C_GRID  = color("#2A3F5F")

-- Geometrie (unites virtuelles du theme ; en 16:9 l'ecran fait 853 x 480).
local PW      = 236          -- largeur du panneau
local RULE    = 3            -- epaisseur des filets cyan
local HEAD    = 22           -- hauteur du bandeau titre
local FOOT    = 20           -- hauteur du bandeau totaux
local PLOT_H  = 52           -- hauteur de la zone de trace
local PH      = RULE * 2 + HEAD + FOOT + PLOT_H
local INSET   = 5            -- marge laterale de la zone de trace
local COLS    = 92           -- resolution horizontale du graphe

-- Echantillons du morceau courant : local au chunk, donc remis a zero a chaque
-- entree dans ScreenGameplay = un graphe par morceau.
local samples, lastCol, peak, trough, sum, count = {}, 0, 0, 999, 0, 0

-- Fontes du theme (identiques a celles de "ScreenGameplay decorations/StepStats").
local Label = Def.BitmapText{ Font = "_helveticaneuelt pro 55 roman 17px" }
local Num   = Def.BitmapText{ Font = "_itc avant garde pro bk 20px" }

-- Reperes verticaux du panneau (y = 0 en haut du panneau).
local PLOT_Y0 = RULE + HEAD
local PLOT_Y1 = PLOT_Y0 + PLOT_H
local GX0     = -PW + INSET
local GW      = PW - INSET * 2
local CW      = GW / COLS

local t = Def.ActorFrame{}

-- --- Fond + filets cyan (grammaire des panneaux de donnees A3) ---------------
t[#t+1] = Def.Quad{
	InitCommand = function(self)
		self:halign(1):valign(0):zoomto(PW, PH):diffuse(C_BASE):diffusealpha(0.85)
	end,
}
t[#t+1] = Def.Quad{
	InitCommand = function(self)
		self:halign(1):valign(0):zoomto(PW, RULE):diffuse(C_RULE)
	end,
}
t[#t+1] = Def.Quad{
	InitCommand = function(self)
		self:halign(1):valign(0):y(PH - RULE):zoomto(PW, RULE):diffuse(C_RULE)
	end,
}

-- --- Bandeau titre noir (comme la ligne "MAX COMBO") -------------------------
t[#t+1] = Def.Quad{
	InitCommand = function(self)
		self:halign(1):valign(0):y(RULE):zoomto(PW, HEAD):diffuse(C_BAR):diffusealpha(0.88)
	end,
}
local HEAD_CY = RULE + HEAD / 2   -- axe vertical du bandeau titre

t[#t+1] = Label .. {
	InitCommand = function(self)
		self:halign(0):valign(0.5):xy(-PW + INSET + 2, HEAD_CY):zoom(0.6)
			:diffuse(C_LABEL):settext("HEART RATE")
	end,
}
-- "BPM" est cale a droite ; la valeur se pose a gauche de LUI, en mesurant sa
-- largeur reelle (GetZoomedWidth). Deviner une marge en dur fait se toucher les
-- deux textes des que la fonte ou le zoom bouge.
local bpmLabel
t[#t+1] = Label .. {
	InitCommand = function(self)
		bpmLabel = self
		self:halign(1):valign(0.5):xy(-INSET - 2, HEAD_CY):zoom(0.5)
			:diffuse(C_LABEL):diffusealpha(0.8):settext("BPM")
	end,
}
t[#t+1] = Num .. {
	Name = "Value",
	InitCommand = function(self)
		local gap = bpmLabel and (bpmLabel:GetZoomedWidth() + 6) or 26
		self:halign(1):valign(0.5):xy(-INSET - 2 - gap, HEAD_CY):zoom(0.85)
			:DiffuseAndStroke(ZoneColor(0), Color.Black):settext("---")
	end,
}

-- --- Zone de trace -----------------------------------------------------------
-- Fond de trace plus clair que le panneau : les couleurs de zone (bleu, vert,
-- or, orange) ressortent mal sur le bleu pale, tres bien sur ce blanc casse.
t[#t+1] = Def.Quad{
	InitCommand = function(self)
		self:halign(0):valign(0):xy(GX0, PLOT_Y0):zoomto(GW, PLOT_H)
			:diffuse(color("#F2F7FF")):diffusealpha(0.92)
	end,
}

-- Reperes horizontaux : 4 lignes discretes, l'echelle etant auto-ajustee.
for i = 1, 3 do
	t[#t+1] = Def.Quad{
		InitCommand = function(self)
			self:halign(0):valign(0)
				:xy(GX0, PLOT_Y0 + (PLOT_H / 4) * i)
				:zoomto(GW, 1):diffuse(C_GRID):diffusealpha(0.16)
		end,
	}
end

-- Les colonnes : une Quad par echantillon, ancrees sur la ligne de base.
for i = 1, COLS do
	t[#t+1] = Def.Quad{
		Name = "c" .. i,
		InitCommand = function(self)
			self:halign(0):valign(1)
				:xy(GX0 + (i - 1) * CW, PLOT_Y1)
				:zoomto(CW - 0.5, 0)
				:diffuse(ZoneColor(0))
		end,
	}
end

-- Tete de lecture : position courante dans le morceau.
t[#t+1] = Def.Quad{
	Name = "Head",
	InitCommand = function(self)
		self:halign(0):valign(1):xy(GX0, PLOT_Y1):zoomto(1, PLOT_H)
			:diffuse(C_GRID):diffusealpha(0)
	end,
}

-- --- Bandeau totaux noir (comme la ligne "EX SCORE") -------------------------
t[#t+1] = Def.Quad{
	InitCommand = function(self)
		self:halign(1):valign(0):y(PH - RULE - FOOT):zoomto(PW, FOOT)
			:diffuse(C_BAR):diffusealpha(0.88)
	end,
}
local FOOT_CY = PH - RULE - FOOT / 2   -- axe vertical du bandeau totaux

t[#t+1] = Label .. {
	Name = "Stats",
	InitCommand = function(self)
		self:halign(0):valign(0.5):xy(-PW + INSET + 2, FOOT_CY):zoom(0.55)
			:diffuse(C_LABEL):settext("")
	end,
}
t[#t+1] = Label .. {
	Name = "Scale",
	InitCommand = function(self)
		self:halign(1):valign(0.5):xy(-INSET - 2, FOOT_CY):zoom(0.5)
			:diffuse(C_LABEL):diffusealpha(0.65):settext("")
	end,
}

-- --- Boucle de rafraichissement ---------------------------------------------
-- SetUpdateFunction DOIT etre posee sur l'ActorFrame (piege #6 de docs/03).
t.InitCommand = function(self)
	-- Coin haut droit, AU-DESSUS du panneau de stats : celui-ci est centre sur
	-- (_screen.cx+160, _screen.cy) au zoom 0.8 avec une base de 462x292, donc il
	-- monte jusqu'a y ~= 123. On garde le panneau FC entierement au-dessus.
	self:xy(SCREEN_RIGHT - 10, SCREEN_TOP + 6)

	local value  = self:GetChild("Value")
	local stats  = self:GetChild("Stats")
	local scale  = self:GetChild("Scale")
	local head   = self:GetChild("Head")
	local cols   = {}
	for i = 1, COLS do cols[i] = self:GetChild("c" .. i) end

	local song = GAMESTATE:GetCurrentSong()
	local songLen = song and song:GetLastSecond() or 120
	if songLen <= 0 then songLen = 120 end

	local acc, shownBpm = 0, -1

	self:SetUpdateFunction(function(_, dt)
		acc = acc + dt
		if acc < 0.5 then return end
		acc = 0

		-- Ne lit Save/hr.txt que si le WebSocket n'est pas etabli.
		local bpm = FransysHR_PollFile()

		-- 1) Valeur courante : petit "battement" a chaque changement.
		if bpm > 0 then
			value:settext(tostring(bpm)):DiffuseAndStroke(ZoneColor(bpm), Color.Black)
			if bpm ~= shownBpm then
				value:stoptweening():zoom(0.95):linear(0.12):zoom(0.85)
				shownBpm = bpm
			end
		else
			value:settext(HR.connected and "---" or "OFF")
				:DiffuseAndStroke(ZoneColor(0), Color.Black)
		end

		if bpm <= 0 then return end

		-- 2) Position dans le morceau -> colonne cible.
		local pos = GAMESTATE:GetCurMusicSeconds()
		local col = math.floor((pos / songLen) * COLS) + 1
		if col < 1 then col = 1 elseif col > COLS then col = COLS end

		-- Remplir les colonnes sautees (morceau rapide / update lent).
		for i = math.max(1, lastCol), col do
			samples[i] = bpm
		end
		lastCol = col

		-- 3) Totaux du morceau.
		if bpm > peak then peak = bpm end
		if bpm < trough then trough = bpm end
		sum, count = sum + bpm, count + 1
		stats:settext(("MAX %d    AVG %d"):format(peak, sum / count + 0.5))

		-- Publie le morceau courant pour ScreenEvaluation. `samples` est un local
		-- de ce chunk : la reference stockee ici survit a l'ecran, et le morceau
		-- suivant repartira sur une table neuve (donc pas de melange entre eux).
		HR.last = {
			samples = samples, cols = COLS, lastCol = lastCol,
			peak = peak, trough = trough, avg = sum / count,
		}

		-- 4) Echelle verticale auto : une FC au repos (55-65) doit se lire aussi
		--    bien qu'un effort (150-180). Amplitude minimale de 24 bpm.
		local lo, hi = 1000, 0
		for i = 1, col do
			local v = samples[i]
			if v then
				if v < lo then lo = v end
				if v > hi then hi = v end
			end
		end
		if lo > hi then lo, hi = bpm, bpm end
		local mid = (lo + hi) / 2
		if hi - lo < 24 then lo, hi = mid - 12, mid + 12 end
		lo, hi = math.floor(lo - 2), math.ceil(hi + 2)
		scale:settext(("%d-%d"):format(lo, hi))

		-- 5) Redessiner les colonnes.
		local span = hi - lo
		for i = 1, COLS do
			local v = samples[i]
			if v then
				local ratio = (v - lo) / span
				if ratio < 0.04 then ratio = 0.04 elseif ratio > 1 then ratio = 1 end
				cols[i]:zoomy(ratio * PLOT_H):diffuse(ZoneColor(v))
					:diffusealpha(i == col and 1 or 0.9)
			end
		end

		-- 6) Tete de lecture.
		head:x(GX0 + col * CW):diffusealpha(0.45)
	end)
end

return t
