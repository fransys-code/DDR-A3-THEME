local t = Def.ActorFrame{};

for pn in ivalues(GAMESTATE:GetHumanPlayers()) do
	t[#t+1] = LoadActor("FullCombo",pn);
end;

-- Rythme cardiaque temps reel (Polar H10 via hr_bridge.py). Cf. docs/05.
t[#t+1] = LoadActor("HeartRate");



if not GAMESTATE:IsCourseMode() then
	if GAMESTATE:GetCurrentSong():GetDisplayFullTitle() == "LET'S CHECK YOUR LEVEL!" then
		t[#t+1] = LoadActor("LET'S CHECK YOUR LEVEL!");
	elseif GAMESTATE:GetCurrentSong():GetDisplayFullTitle() == "Lesson by DJ" then
		t[#t+1] = LoadActor("Lesson by DJ");
	end;
end

return t;