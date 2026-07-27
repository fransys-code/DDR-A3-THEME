-- Rythme cardiaque temps reel (Polar H10) — etat partage du thème.
--
-- Charge au boot du thème. Centralise ce qui etait duplique dans chaque ecran :
-- la connexion WebSocket, l'etat courant, et les zones de FC.
--
-- Source des donnees : scripts/hr_bridge.py (repo fransys-ddr) lit le capteur en
-- BLE cote Windows et pousse la BPM en texte brut sur ws://127.0.0.1:8765.
-- Prerequis : 127.0.0.1 dans HttpAllowHosts de Save/Preferences.ini (preference
-- Immutable -> jeu ferme pour l'editer). Detail complet : docs/05 du repo.
--
-- Consommateurs : "ScreenSelectMusic overlay/HeartRate" (valeur courante),
-- "ScreenGameplay overlay/HeartRate" (valeur + graphe du morceau),
-- "ScreenEvaluation decorations/HeartRate" (bilan du morceau).

FRANSYS_HR_URL      = "ws://127.0.0.1:8765"
FRANSYS_HR_FALLBACK = "Save/hr.txt"     -- si le WebSocket est indisponible
FRANSYS_HR_FCMAX    = 190               -- FC max : pilote toutes les couleurs

FRANSYS_HR_ZONES = {
	{ pct = 0.60, color = color("#0F8FD0") },  -- recuperation
	{ pct = 0.70, color = color("#1FA83C") },  -- aerobie
	{ pct = 0.80, color = color("#D9A400") },  -- tempo
	{ pct = 0.90, color = color("#F26B1D") },  -- seuil
	{ pct = 1.00, color = color("#E02020") },  -- max
}

-- Couleur de la zone d'une BPM. Gris si pas de mesure.
function FransysHR_ZoneColor(v)
	if not v or v <= 0 then return color("#7A8CA6") end
	local ratio = v / FRANSYS_HR_FCMAX
	for _, z in ipairs(FRANSYS_HR_ZONES) do
		if ratio < z.pct then return z.color end
	end
	return FRANSYS_HR_ZONES[#FRANSYS_HR_ZONES].color
end

-- Etat partage. `last` porte le graphe du dernier morceau joue, pour l'ecran
-- de resultats (cf. docs/05).
FRANSYS_HR = FRANSYS_HR or { bpm = 0, connected = false, ws = nil, last = nil, stamp = -999 }

-- Sans mesure fraiche depuis ce delai, la valeur affichee est reputee morte.
-- Le capteur pousse ~1x/s : 6 s laissent passer quelques trames perdues sans
-- jamais faire croire a une mesure vivante alors que le pont est tombe.
FRANSYS_HR_STALE_AFTER = 6

--- Vrai si la derniere BPM recue est trop vieille pour etre affichee.
-- Un pont qui meurt (crash, capteur retire) laissait sinon le dernier chiffre
-- fige a l'ecran indefiniment, ce qui est pire que pas de chiffre du tout.
function FransysHR_IsStale()
	return (GetTimeSinceStart() - (FRANSYS_HR.stamp or -999)) > FRANSYS_HR_STALE_AFTER
end

--- Retourne l'etat partage, en ouvrant le WebSocket au premier appel.
-- Idempotent : un seul socket par session, quel que soit le nombre d'ecrans
-- qui appellent (les fichiers de BGAnimations sont re-executes a chaque entree
-- d'ecran ; sans cette garde on ouvrirait un socket par morceau).
--
-- REGLE A NE PAS CASSER : onMessage survit a l'ecran qui l'a cree, pas ses
-- acteurs. Le callback n'ecrit donc QUE dans cette table ; tout rendu se fait
-- dans l'UpdateFunction de l'ecran, qui meurt avec lui. Sinon : "stale
-- BitmapText referenced" a chaque changement d'ecran (docs/03, piege #7).
function FransysHR()
	local HR = FRANSYS_HR
	if HR.ws == nil then
		if NETWORK and NETWORK.WebSocket and NETWORK:IsUrlAllowed(FRANSYS_HR_URL) then
			HR.ws = NETWORK:WebSocket{
				url = FRANSYS_HR_URL,
				pingInterval = 30,
				automaticReconnect = true,
				onMessage = function(msg)
					local t = ToEnumShortString(msg.type)
					if t == "Open" then
						HR.connected = true
					elseif t == "Close" or t == "Error" then
						HR.connected = false
					elseif t == "Message" then
						local v = tonumber((msg.data:gsub("%s+", "")))
						if v then
							HR.bpm = v
							HR.stamp = GetTimeSinceStart()   -- horodate la fraicheur
						end
					end
				end,
			}
		else
			Trace("FRANSYS HR: WebSocket indisponible (127.0.0.1 absent de HttpAllowHosts ?) -> fallback fichier")
		end
	end
	return HR
end

--- Met a jour HR.bpm depuis Save/hr.txt quand le WebSocket n'est pas etabli.
-- A appeler depuis une UpdateFunction throttlee, jamais a chaque frame.
function FransysHR_PollFile()
	local HR = FRANSYS_HR
	if not HR.connected then
		local raw = File.Read(FRANSYS_HR_FALLBACK)
		local v = raw and tonumber((raw:gsub("%s+", "")))
		if v and v ~= HR.bpm then
			HR.bpm = v
			HR.stamp = GetTimeSinceStart()
		end
	end
	-- Une valeur perimee ne doit pas se faire passer pour une mesure : on rend 0,
	-- que les ecrans affichent deja comme "pas de donnee".
	if FransysHR_IsStale() then return 0 end
	return HR.bpm
end
