local pn = ...;

-- Live step statistics pane for single player. In single the notefield only uses one half of
-- the screen, so the counters go on the other half. Artwork, fonts and row offsets are reused
-- from "ScreenEvaluation decorations/frame" so this reads as the very same pane the player
-- gets on the results screen -- only the values are refreshed while the song plays.

local pss = STATSMAN:GetCurStageStats():GetPlayerStageStats(pn)
local short = ToEnumShortString(pn)

local function Art(file)
	return THEME:GetPathB("ScreenEvaluation","decorations/frame/"..file)
end

local Large = Def.BitmapText{
	Font="_itc avant garde pro bk 20px",
	InitCommand=function(s) s:zoom(1.2):halign(1) end,
};

local Judge = Def.BitmapText{
	Font="_helveticaneuelt pro 55 roman 17px",
	InitCommand=function(s) s:zoom(1.3):halign(1)
		:DiffuseAndStroke(Color.Black,Color.White)
	end,
};

-- Same rows, same y offsets as frame/data/default.lua.
local Rows = {
	{ y=-76, Get=function() return pss:GetTapNoteScores("TapNoteScore_W1") end },
	{ y=-45, Get=function() return pss:GetTapNoteScores("TapNoteScore_W2") end },
	{ y=-15, Get=function() return pss:GetTapNoteScores("TapNoteScore_W3") end },
	{ y= 15, Get=function() return pss:GetTapNoteScores("TapNoteScore_W4") end },
	{ y= 45, Get=function() return pss:GetHoldNoteScores("HoldNoteScore_Held") end },
	{ y= 75, Get=function() return pss:GetTapNoteScores("TapNoteScore_Miss")
		+ pss:GetTapNoteScores("TapNoteScore_W5") end },
};

local t = Def.ActorFrame{
	InitCommand=function(s)
		-- centred in the half the notefield leaves free (notefield sits at cx-/+240, so the
		-- free span runs from about cx-110 to the screen edge)
		s:xy(pn == PLAYER_1 and _screen.cx+160 or _screen.cx-160, _screen.cy)
		s:zoom(0.8):draworder(2)
	end,
	OnCommand=function(s) s:playcommand("Set") end,
	-- The player's stats are incremented *after* JudgmentMessage is broadcast (TargetScore.lua
	-- compensates by hand instead), so refresh on the following frame to read settled values.
	JudgmentMessageCommand=function(s,params)
		if params.Player == pn then s:queuecommand("Refresh") end
	end,
	RefreshCommand=function(s) s:playcommand("Set") end,
	CurrentSongChangedMessageCommand=function(s) s:queuecommand("Refresh") end,

	LoadActor(Art("base.png"))..{
		InitCommand=function(s) s:diffusealpha(0.85) end,
	};
	LoadActor(Art("data/BASE.png"));
	LoadActor(Art("data/"..(IsEXScore() and "EX.png" or "NORMAL.png")));
	LoadActor(Art("data/FAST.png"))..{
		InitCommand=function(s) s:visible(ShowFastSlow()) end,
	};

	Large..{
		InitCommand=function(s) s:xy(90,-105) end,
		SetCommand=function(s) s:settextf("%d",pss:MaxCombo()) end,
	};

	-- Bottom row: like the evaluation pane, show whichever score the main HUD is not showing.
	Large..{
		InitCommand=function(s) s:xy(IsEXScore() and 133 or 93, 107) end,
		SetCommand=function(s)
			if IsEXScore() then
				s:settextf("%4d",pss:GetScore())
			else
				s:settextf("%4d",math.floor(pss:GetPossibleDancePoints()*pss:GetPercentDancePoints()+0.5))
			end
		end,
	};

	Def.ActorFrame{
		Condition=ShowFastSlow();
		Judge..{
			InitCommand=function(s) s:xy(205,11) end,
			SetCommand=function(s) s:settextf("%d",getenv("numFast"..short) or 0) end,
		};
		Judge..{
			InitCommand=function(s) s:xy(205,70) end,
			SetCommand=function(s) s:settextf("%d",getenv("numSlow"..short) or 0) end,
		};
	};
};

for _,row in ipairs(Rows) do
	t[#t+1] = Judge..{
		InitCommand=function(s) s:xy(93,row.y) end,
		SetCommand=function(s) s:settextf("%d",row.Get()) end,
	};
end

return t
