local visible = true

script.Parent.ClickDetector.MouseClick:Connect(function()
	visible = not visible
	script.Parent.Transparency = visible and 0 or 1
end)