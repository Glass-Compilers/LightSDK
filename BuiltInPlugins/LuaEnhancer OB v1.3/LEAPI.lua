local tools = 200223784
local core = 200355451
local power = ("off")
local plugin = PluginManager():CreatePlugin()
local toolbar = plugin:CreateToolbar("LuaEnhancer ClientSide")

local button = toolbar:CreateButton(
	"",
	"Enable LuaEnhancer/Disable LuaEnhancer",
	"PLogo.png"
) -- Should not change unless using the ROBLOX publish method.

button.Click:connect(function()
	if power == ("off") then 
		power = ("on")
		print("On method worked.")
		game:GetService("InsertService"):LoadAsset(tools).Parent=game.StarterGui
		game:GetService("InsertService"):LoadAsset(core).Parent=game.Workspace
		wait(4)
		game.StarterGui.Model:Destroy()
		else if power == ("on") then
			power = ("off")
			print("Off method worked.")
			game.Workspace.Model.EnhancerCoreTools.Parent:Destroy()
		end
	end
end)