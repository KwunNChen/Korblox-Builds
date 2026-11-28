local ContentProvider=game:GetService("ContentProvider");
local Music=script;
local Sound=Music.Parent;
local Audio=Sound:FindFirstChild("Music");
if Audio.IsPlaying == true then
Audio:Stop()
end
Audio:Play()
