-- Backpack Version 4.13
-- OnlyTwentyCharacters

---------------------
--| Configurables |--
---------------------

local ICON_SIZE = 60
local ICON_BUFFER = 5

local BACKGROUND_FADE = 0.70

local SLOT_COLOR_NORMAL = Color3.new(49/255, 49/255, 49/255)
local SLOT_COLOR_EQUIP = Color3.new(90/255, 142/255, 233/255)
local SLOT_FADE_LOCKED = 0.50 -- Locked means empty/undraggable
local SLOT_BORDER_COLOR = Color3.new(1, 1, 1)

local ARROW_IMAGE_OPEN = 'rbxasset://textures/ui/Backpack_Open.png'
local ARROW_IMAGE_CLOSE = 'rbxasset://textures/ui/Backpack_Close.png'
local ARROW_SIZE = UDim2.new(0, 14, 0, 9)
local ARROW_HOTKEY = Enum.KeyCode.Backquote.Value --TODO: Hookup '~' too?
local ARROW_HOTKEY_STRING = '`'

local HOTBAR_SLOTS_FULL = 10
local HOTBAR_SLOTS_MINI = 3
local HOTBAR_SLOTS_WIDTH_CUTOFF = 1024 -- Anything smaller is MINI
local HOTBAR_OFFSET_FROMBOTTOM = 30 -- Offset to make room for the Health GUI

local INVENTORY_ROWS = 5
local INVENTORY_HEADER_SIZE = 40

--local TITLE_OFFSET = 20 -- From left side
--local TITLE_TEXT = "Backpack"

local SEARCH_BUFFER = 5
local SEARCH_WIDTH = 200
local SEARCH_TEXT = "Search"
local SEARCH_TEXT_OFFSET_FROMLEFT = 15
local SEARCH_BACKGROUND_COLOR = Color3.new(0.37, 0.37, 0.37)
local SEARCH_BACKGROUND_FADE = 0.15

local DOUBLE_CLICK_TIME = 0.5

-----------------
--| Variables |--
-----------------

local PlayersService = game:GetService('Players')
local UserInputService = game:GetService('UserInputService')
local StarterGui = game:GetService('StarterGui')
local GuiService = game:GetService('GuiService')

local HOTBAR_SLOTS = (UserInputService.TouchEnabled and GuiService:GetScreenResolution().X < HOTBAR_SLOTS_WIDTH_CUTOFF) and HOTBAR_SLOTS_MINI or HOTBAR_SLOTS_FULL
local HOTBAR_SIZE = UDim2.new(0, ICON_BUFFER + (HOTBAR_SLOTS * (ICON_SIZE + ICON_BUFFER)), 0, ICON_BUFFER + ICON_SIZE + ICON_BUFFER)
local ZERO_KEY_VALUE = Enum.KeyCode.Zero.Value
local DROP_HOTKEY_VALUE = Enum.KeyCode.Backspace.Value

local Player = PlayersService.LocalPlayer

local CoreGui = script.Parent

local MainFrame = nil
local HotbarFrame = nil
local InventoryFrame = nil
local ScrollingFrame = nil

local Character = nil
local Humanoid = nil
local Backpack = nil

local Slots = {} -- List of all Slots by index
local LowestEmptySlot = nil
local SlotsByTool = {} -- Map of Tools to their assigned Slots
local HotkeyFns = {} -- Map of KeyCode values to their assigned behaviors
local Dragging = {} -- Only used to check if anything is being dragged, to disable other input
local FullHotbarSlots = 0
local UpdateArrowFrame = nil -- Function defined in arrow init logic at bottom
local ActiveHopper = nil --NOTE: HopperBin
local StarterToolFound = false -- Special handling is required for the gear currently equipped on the site
local WholeThingEnabled = false
local TextBoxFocused = false -- ANY TextBox, not just the search box
local ResultsIndices = nil -- Results of a search
local ResetSearch = nil -- Function defined in search logic at bottom
local HotkeyStrings = {} -- Used for eating/releasing hotkeys
local CharConns = {} -- Holds character connections to be cleared later

-----------------
--| Functions |--
-----------------

local function NewGui(className, objectName)
	local newGui = Instance.new(className)
	newGui.Name = objectName
	newGui.BackgroundColor3 = Color3.new(0, 0, 0)
	newGui.BackgroundTransparency = 1
	newGui.BorderColor3 = Color3.new(0, 0, 0)
	newGui.BorderSizePixel = 0
	newGui.Size = UDim2.new(1, 0, 1, 0)
	if className:match('Text') then
		newGui.TextColor3 = Color3.new(1, 1, 1)
		newGui.Text = ''
		newGui.Font = Enum.Font.SourceSans
		newGui.FontSize = Enum.FontSize.Size14
		newGui.TextWrapped = true
		if className == 'TextButton' then
			newGui.Font = Enum.Font.SourceSansBold
			newGui.BorderSizePixel = 1
		end
	end
	return newGui
end

local function FindLowestEmpty()
	for i = 1, HOTBAR_SLOTS do
		local slot = Slots[i]
		if not slot.Tool then
			return slot
		end
	end
	return nil
end

local function AdjustHotbarFrames()
	local inventoryOpen = InventoryFrame.Visible -- (Show all)
	local visualTotal = (inventoryOpen) and HOTBAR_SLOTS or FullHotbarSlots
	local visualIndex = 0
	for i = 1, HOTBAR_SLOTS do
		local slot = Slots[i]
		if slot.Tool or inventoryOpen then
			visualIndex = visualIndex + 1
			slot:Readjust(visualIndex, visualTotal)
			slot.Frame.Visible = true
		else
			slot.Frame.Visible = false
		end
	end
end

local function CheckBounds(guiObject, x, y)
	local pos = guiObject.AbsolutePosition
	local size = guiObject.AbsoluteSize
	return (x > pos.X and x <= pos.X + size.X and y > pos.Y and y <= pos.Y + size.Y)
end

local function GetOffset(guiObject, point)
	local centerPoint = guiObject.AbsolutePosition + (guiObject.AbsoluteSize / 2)
	return (centerPoint - point).magnitude
end

local function DisableActiveHopper() --NOTE: HopperBin
	ActiveHopper:ToggleSelect()
	SlotsByTool[ActiveHopper]:UpdateEquipView()
	ActiveHopper = nil
end

local function UnequipTools() --NOTE: HopperBin
	Humanoid:UnequipTools()
	if ActiveHopper then
		DisableActiveHopper()
	end
end

local function EquipTool(tool) --NOTE: HopperBin
	UnequipTools()
	if tool:IsA('HopperBin') then
		tool:ToggleSelect()
		SlotsByTool[tool]:UpdateEquipView()
		ActiveHopper = tool
	else
		-- Humanoid:EquipTool(tool) --NOTE: This would also unequip current Tool
		tool.Parent = Character --TODO: Switch back to above line after EquipTool is fixed!
	end
end

local function IsEquipped(tool)
	return (tool.Parent == Character or (tool:IsA('HopperBin') and tool.Active)) --NOTE: HopperBin
end

local function MakeSlot(parent, index)
	index = index or (#Slots + 1)
	
	-- Slot Definition --
	
	local slot = {}
	slot.Tool = nil
	slot.Index = index
	slot.Frame = nil
	
	local SlotFrame = nil
	local ToolIcon = nil
	local ToolName = nil
	local ToolChangeConn = nil
	
	--NOTE: The following are only defined for Hotbar Slots
	local ToolTip = nil
	local SlotNumber = nil
	local ClickArea = nil
	
	-- Slot Functions --
	
	local function UpdateSlotFading(unequippedOverride)
		local equipped = not unequippedOverride and slot.Tool and IsEquipped(slot.Tool)
		SlotFrame.BackgroundTransparency = (equipped or SlotFrame.Draggable) and 0 or SLOT_FADE_LOCKED
	end
	
	function slot:Reposition()
		-- Slots are positioned into rows
		local index = (ResultsIndices and ResultsIndices[self]) or self.Index
		local sizePlus = ICON_BUFFER + ICON_SIZE
		local modSlots = ((index - 1) % HOTBAR_SLOTS) + 1
		local row = (index > HOTBAR_SLOTS) and (math.floor((index - 1) / HOTBAR_SLOTS)) - 1 or 0
		SlotFrame.Position = UDim2.new(0, ICON_BUFFER + ((modSlots - 1) * sizePlus), 0, ICON_BUFFER + (sizePlus * row))
	end
	
	function slot:Readjust(visualIndex, visualTotal) --NOTE: Only used for Hotbar slots
		local centered = HOTBAR_SIZE.X.Offset / 2
		local sizePlus = ICON_BUFFER + ICON_SIZE
		local midpointish = (visualTotal / 2) + 0.5
		local factor = visualIndex - midpointish
		SlotFrame.Position = UDim2.new(0, centered - (ICON_SIZE / 2) + (sizePlus * factor), 0, ICON_BUFFER)
	end
	
	function slot:Fill(tool)
		self.Tool = tool
		
		local function assignToolData()
			local icon = tool.TextureId
			ToolIcon.Image = icon
			ToolName.Text = (icon == '') and tool.Name or '' -- (Only show name if no icon)
			if ToolTip and tool:IsA('Tool') then --NOTE: HopperBin
				--TODO: No magic numbers
				ToolTip.Text = tool.ToolTip
				local width = ToolTip.TextBounds.X + 6
				ToolTip.Size = UDim2.new(0, width, 0, 16)
				ToolTip.Position = UDim2.new(0.5, -width / 2, 0, -25)
			end
		end
		assignToolData()
		
		ToolChangeConn = tool.Changed:connect(function(property)
			if property == 'TextureId' or property == 'Name' or property == 'ToolTip' then
				assignToolData()
			end
		end)
		
		local hotbarSlot = (self.Index <= HOTBAR_SLOTS)
		local inventoryOpen = InventoryFrame.Visible
		
		if not hotbarSlot or inventoryOpen then
			SlotFrame.Draggable = true
		end
		
		self:UpdateEquipView()
		
		if hotbarSlot then
			FullHotbarSlots = FullHotbarSlots + 1
		end
		
		SlotsByTool[tool] = self
		LowestEmptySlot = FindLowestEmpty()
		UpdateArrowFrame()
	end
	
	function slot:Clear()
		ToolChangeConn:disconnect()
		ToolChangeConn = nil
		
		ToolIcon.Image = ''
		ToolName.Text = ''
		if ToolTip then
			ToolTip.Text = ''
			ToolTip.Visible = false
		end
		SlotFrame.Draggable = false
		
		self:UpdateEquipView(true) -- Show as unequipped
		
		if self.Index <= HOTBAR_SLOTS then
			FullHotbarSlots = FullHotbarSlots - 1
		end
		
		SlotsByTool[self.Tool] = nil
		self.Tool = nil
		LowestEmptySlot = FindLowestEmpty()
		UpdateArrowFrame()
	end
	
	function slot:UpdateEquipView(unequippedOverride)
		if not unequippedOverride and IsEquipped(self.Tool) then -- Equipped
			SlotFrame.BackgroundColor3 = SLOT_COLOR_EQUIP
		else -- In the Backpack
			SlotFrame.BackgroundColor3 = SLOT_COLOR_NORMAL
		end
		UpdateSlotFading(unequippedOverride)
	end
	
	function slot:Delete()
		SlotFrame:Destroy() --NOTE: Also clears connections
		table.remove(Slots, self.Index)
		local newSize = #Slots
		
		-- Now adjust the rest (both visually and representationally)
		for i = self.Index, newSize do
			Slots[i]:SlideBack()
		end
		
		if newSize % HOTBAR_SLOTS == 0 then -- We lost a row at the end! Adjust the CanvasSize
			local lastSlot = Slots[newSize]
			local lowestPoint = lastSlot.Frame.Position.Y.Offset + lastSlot.Frame.Size.Y.Offset
			ScrollingFrame.CanvasSize = UDim2.new(0, 0, 0, lowestPoint + ICON_BUFFER)
			local offset = Vector2.new(0, math.max(0, ScrollingFrame.CanvasPosition.Y - (lastSlot.Frame.Size.Y.Offset + ICON_BUFFER)))
			ScrollingFrame.CanvasPosition = offset
		end
	end
	
	function slot:Swap(targetSlot) --NOTE: This slot (self) must not be empty!
		local myTool, otherTool = self.Tool, targetSlot.Tool
		self:Clear()
		if otherTool then -- (Target slot might be empty)
			targetSlot:Clear()
			self:Fill(otherTool)
		end
		targetSlot:Fill(myTool)
	end
	
	function slot:SlideBack() -- For inventory slot shifting
		self.Index = self.Index - 1
		SlotFrame.Name = self.Index
		self:Reposition()
	end
	
	function slot:TurnNumber(on)
		if SlotNumber then
			SlotNumber.Visible = on
		end
	end
	
	function slot:SetClickability(on) -- (Happens on open/close arrow)
		ClickArea.Visible = on
		if self.Tool then
			SlotFrame.Draggable = not on
			UpdateSlotFading()
		end
	end
	
	function slot:CheckTerms(terms)
		local hits = 0
		local function checkEm(str, term)
			local _, n = str:lower():gsub(term, '')
			hits = hits + n
		end
		local tool = self.Tool
		for term in pairs(terms) do
			checkEm(tool.Name, term)
			if tool:IsA('Tool') then --NOTE: HopperBin
				checkEm(tool.ToolTip, term)
			end
		end
		return hits
	end
	
	-- Slot Init Logic --
	
	SlotFrame = NewGui('Frame', index)
	SlotFrame.BackgroundColor3 = SLOT_COLOR_NORMAL
	SlotFrame.BorderColor3 = SLOT_BORDER_COLOR
	SlotFrame.Size = UDim2.new(0, ICON_SIZE, 0, ICON_SIZE)
	SlotFrame.Active = true
	SlotFrame.Draggable = false
	SlotFrame.BackgroundTransparency = SLOT_FADE_LOCKED
	slot.Frame = SlotFrame
	
	ToolIcon = NewGui('ImageLabel', 'Icon')
	ToolIcon.Size = UDim2.new(0.8, 0, 0.8, 0)
	ToolIcon.Position = UDim2.new(0.1, 0, 0.1, 0)
	ToolIcon.Parent = SlotFrame
	
	ToolName = NewGui('TextLabel', 'ToolName')
	ToolName.Size = UDim2.new(1, -2, 1, -2)
	ToolName.Position = UDim2.new(0, 1, 0, 1)
	ToolName.Parent = SlotFrame
	
	slot:Reposition()
	
	if index <= HOTBAR_SLOTS then -- Hotbar-Specific Slot Stuff
		-- ToolTip stuff
		ToolTip = NewGui('TextLabel', 'ToolTip')
		ToolTip.TextWrapped = false
		ToolTip.TextYAlignment = Enum.TextYAlignment.Top
		ToolTip.BackgroundColor3 = Color3.new(0.4, 0.4, 0.4)
		ToolTip.BackgroundTransparency = 0
		ToolTip.Visible = false
		ToolTip.Parent = SlotFrame
		SlotFrame.MouseEnter:connect(function()
			if ToolTip.Text ~= '' then
				ToolTip.Visible = true
			end
		end)
		SlotFrame.MouseLeave:connect(function() ToolTip.Visible = false end)
		
		-- Slot select logic, activated by clicking or pressing hotkey
		local function selectSlot()
			local tool = slot.Tool
			if tool then
				if tool.Parent == Character or (tool:IsA('HopperBin') and tool.Active) then --NOTE: HopperBin
					UnequipTools()
				elseif tool.Parent == Backpack then
					EquipTool(tool)
				end
			end
		end
		
		ClickArea = NewGui('TextButton', 'GimmieYerClicks')
		ClickArea.MouseButton1Click:connect(selectSlot)
		ClickArea.Parent = SlotFrame
		
		-- Show label and assign hotkeys for 1-9 and 0 (zero is always last slot when > 10 total)
		if index < 10 or index == HOTBAR_SLOTS then -- NOTE: Hardcoded on purpose!
			local slotNum = (index < 10) and index or 0
			SlotNumber = NewGui('TextLabel', 'Number')
			SlotNumber.Text = slotNum
			SlotNumber.Size = UDim2.new(0.15, 0, 0.15, 0)
			SlotNumber.Visible = false
			SlotNumber.Parent = SlotFrame
			HotkeyFns[ZERO_KEY_VALUE + slotNum] = selectSlot
		end
	else -- Inventory-Specific Slot Stuff
		if index % HOTBAR_SLOTS == 1 then -- We are the first slot of a new row! Adjust the CanvasSize
			local lowestPoint = SlotFrame.Position.Y.Offset + SlotFrame.Size.Y.Offset
			ScrollingFrame.CanvasSize = UDim2.new(0, 0, 0, lowestPoint + ICON_BUFFER)
		end
	end
	
	do -- Dragging Logic
		local startPoint = SlotFrame.Position
		local lastUpTime = 0
		local startParent = nil
		
		SlotFrame.DragBegin:connect(function(dragPoint)
			Dragging[SlotFrame] = true
			startPoint = dragPoint
			
			SlotFrame.BorderSizePixel = 2
			
			-- Raise above other slots
			SlotFrame.ZIndex = 2
			ToolIcon.ZIndex = 2
			ToolName.ZIndex = 2
			if SlotNumber then
				SlotNumber.ZIndex = 2
			end
			
			-- Circumvent the ScrollingFrame's ClipsDescendants property
			startParent = SlotFrame.Parent
			if startParent == ScrollingFrame then
				SlotFrame.Parent = InventoryFrame
				local pos = ScrollingFrame.Position
				local offset = ScrollingFrame.CanvasPosition - Vector2.new(pos.X.Offset, pos.Y.Offset)
				SlotFrame.Position = SlotFrame.Position - UDim2.new(0, offset.X, 0, offset.Y)
			end
		end)
		
		SlotFrame.DragStopped:connect(function(x, y)
			local now = tick()
			SlotFrame.Position = startPoint
			SlotFrame.Parent = startParent
			
			SlotFrame.BorderSizePixel = 0
			
			-- Restore height
			SlotFrame.ZIndex = 1
			ToolIcon.ZIndex = 1
			ToolName.ZIndex = 1
			if SlotNumber then
				SlotNumber.ZIndex = 1
			end
			
			Dragging[SlotFrame] = nil
			
			-- Make sure the tool wasn't dropped
			if not slot.Tool then
				return
			end
			
			local function moveToInventory()
				if slot.Index <= HOTBAR_SLOTS then -- From a Hotbar slot
					local tool = slot.Tool
					slot:Clear() --NOTE: Order matters here
					local newSlot = MakeSlot(ScrollingFrame)
					newSlot:Fill(tool)
					if tool.Parent == Character or (tool:IsA('HopperBin') and tool.Active) then -- Also unequip it --NOTE: HopperBin
						UnequipTools()
					end
					-- Also hide the inventory slot if we're showing results right now
					if ResultsIndices then
						newSlot.Frame.Visible = false
					end
				end
			end
			
			-- Check where we were dropped
			if CheckBounds(InventoryFrame, x, y) then
				moveToInventory()
				-- Check for double clicking on an inventory slot, to move into empty hotbar slot
				if slot.Index > HOTBAR_SLOTS and now - lastUpTime < DOUBLE_CLICK_TIME then
					if LowestEmptySlot then
						local myTool = slot.Tool
						slot:Clear()
						LowestEmptySlot:Fill(myTool)
						slot:Delete()
					end
					now = 0 -- Resets the timer
				end
			elseif CheckBounds(HotbarFrame, x, y) then
				local closest = {math.huge, nil}
				for i = 1, HOTBAR_SLOTS do
					local otherSlot = Slots[i]
					local offset = GetOffset(otherSlot.Frame, Vector2.new(x, y))
					if offset < closest[1] then
						closest = {offset, otherSlot}
					end
				end
				local closestSlot = closest[2]
				if closestSlot ~= slot then
					slot:Swap(closestSlot)
					if slot.Index > HOTBAR_SLOTS then
						local tool = slot.Tool
						if not tool then -- Clean up after ourselves if we're an inventory slot that's now empty
							slot:Delete()
						else -- Moved inventory slot to hotbar slot, and gained a tool that needs to be unequipped
							if tool.Parent == Character or (tool:IsA('HopperBin') and tool.Active) then --NOTE: HopperBin
								UnequipTools()
							end
							-- Also hide the inventory slot if we're showing results right now
							if ResultsIndices then
								slot.Frame.Visible = false
							end
						end
					end
				end
			else
				-- local tool = slot.Tool
				-- if tool.CanBeDropped then --TODO: HopperBins
					-- tool.Parent = workspace
					-- --TODO: Move away from character
				-- end
				moveToInventory() --NOTE: Temporary
			end
			
			lastUpTime = now
		end)
	end
	
	-- All ready!
	SlotFrame.Parent = parent
	Slots[index] = slot
	return slot
end

local function OnChildAdded(child) -- To Character or Backpack
	if not child:IsA('Tool') and not child:IsA('HopperBin') then --NOTE: HopperBin
		if child:IsA('Humanoid') and child.Parent == Character then
			Humanoid = child
		end
		return
	end
	local tool = child
	
	if ActiveHopper then --NOTE: HopperBin
		DisableActiveHopper()
	end
	
	--TODO: Optimize / refactor / do something else
	if not StarterToolFound and tool.Parent == Character and not SlotsByTool[tool] then
		local starterGear = Player:FindFirstChild('StarterGear')
		if starterGear then
			if starterGear:FindFirstChild(tool.Name) then
				StarterToolFound = true
				local firstEmptyIndex = LowestEmptySlot and LowestEmptySlot.Index or #Slots + 1
				if LowestEmptySlot then
					firstEmptyIndex = LowestEmptySlot.Index
				else -- No slots free in hotbar, make a new inventory slot
					local newSlot = MakeSlot(ScrollingFrame)
					firstEmptyIndex = newSlot.Index
				end
				for i = firstEmptyIndex, 1, -1 do
					local curr = Slots[i] -- An empty slot, because above
					local pIndex = i - 1
					if pIndex > 0 then
						local prev = Slots[pIndex] -- Guaranteed to be full, because above
						prev:Swap(curr)
					else
						curr:Fill(tool)
					end
				end
				return -- We're done here
			end
		end
	end
	
	-- The tool is either moving or new
	local slot = SlotsByTool[tool]
	if slot then
		slot:UpdateEquipView()
	else -- New! Put into lowest hotbar slot or new inventory slot
		slot = LowestEmptySlot or MakeSlot(ScrollingFrame)
		slot:Fill(tool)
		if slot.Index <= HOTBAR_SLOTS and not InventoryFrame.Visible then
			AdjustHotbarFrames()
		end
	end
end

local function OnChildRemoved(child) -- From Character or Backpack
	if not child:IsA('Tool') and not child:IsA('HopperBin') then --NOTE: HopperBin
		return
	end
	local tool = child
	
	-- Ignore this event if we're just moving between the two
	local newParent = tool.Parent
	if newParent == Character or newParent == Backpack then
		return
	end
	
	local slot = SlotsByTool[tool]
	if slot then
		slot:Clear()
		if slot.Index > HOTBAR_SLOTS then -- Inventory slot
			slot:Delete()
		elseif not InventoryFrame.Visible then
			AdjustHotbarFrames()
		end
	end
	
	if tool == ActiveHopper then --NOTE: HopperBin
		ActiveHopper = nil
	end
end

local function OnCharacterAdded(character)
	-- First, clean up any old slots
	for i = #Slots, 1, -1 do
		local slot = Slots[i]
		if slot.Tool then
			slot:Clear()
		end
		if i > HOTBAR_SLOTS then
			slot:Delete()
		end
	end
	ActiveHopper = nil
	
	-- And any old connections
	for _, conn in pairs(CharConns) do
		conn:disconnect()
	end
	CharConns = {}
	
	-- Hook up the new character
	Character = character
	table.insert(CharConns, character.ChildRemoved:connect(OnChildRemoved))
	table.insert(CharConns, character.ChildAdded:connect(OnChildAdded))
	for _, child in pairs(character:GetChildren()) do
		OnChildAdded(child)
	end
	--NOTE: Humanoid is set inside OnChildAdded
	
	-- And the new backpack, when it gets here
	Backpack = Player:WaitForChild('Backpack')
	table.insert(CharConns, Backpack.ChildRemoved:connect(OnChildRemoved))
	table.insert(CharConns, Backpack.ChildAdded:connect(OnChildAdded))
	for _, child in pairs(Backpack:GetChildren()) do
		OnChildAdded(child)
	end
	
	AdjustHotbarFrames()
end

local function OnInputBegan(input, isProcessed)
	if input.UserInputType == Enum.UserInputType.Keyboard and not TextBoxFocused and (WholeThingEnabled or input.KeyCode.Value == DROP_HOTKEY_VALUE) then
		local hotkeyBehavior = HotkeyFns[input.KeyCode.Value]
		if hotkeyBehavior then
			hotkeyBehavior()
		end
	end
end

local function OnUISChanged(property)
	if property == 'KeyboardEnabled' then
		local on = UserInputService.KeyboardEnabled
		for i = 1, HOTBAR_SLOTS do
			Slots[i]:TurnNumber(on)
		end
	end
end

local function OnCoreGuiChanged(coreGuiType, enabled)
	-- Check for enabling/disabling the whole thing
	if coreGuiType == Enum.CoreGuiType.Backpack or coreGuiType == Enum.CoreGuiType.All then
		WholeThingEnabled = enabled
		MainFrame.Visible = enabled
		
		-- Eat/Release hotkeys (Doesn't affect UserInputService)
		for _, keyString in pairs(HotkeyStrings) do
			if enabled then
				GuiService:AddKey(keyString)
			else
				GuiService:RemoveKey(keyString)
			end
		end
	end
	
	-- Also check if the Health GUI is showing, and shift everything down (or back up) accordingly
	if coreGuiType == Enum.CoreGuiType.Health or coreGuiType == Enum.CoreGuiType.All then
		MainFrame.Position = UDim2.new(0, 0, 0, enabled and 0 or HOTBAR_OFFSET_FROMBOTTOM)
	end
end

--------------------
--| Script Logic |--
--------------------

-- Make the main frame, which (mostly) covers the screen
MainFrame = NewGui('Frame', 'Backpack')
MainFrame.Visible = false
MainFrame.Parent = CoreGui

-- Make the HotbarFrame, which holds only the Hotbar Slots
HotbarFrame = NewGui('Frame', 'Hotbar')
HotbarFrame.Active = true
HotbarFrame.Size = HOTBAR_SIZE
HotbarFrame.Position = UDim2.new(0.5, -HotbarFrame.Size.X.Offset / 2, 1, -HotbarFrame.Size.Y.Offset - HOTBAR_OFFSET_FROMBOTTOM)
HotbarFrame.Parent = MainFrame

-- Make all the Hotbar Slots
for i = 1, HOTBAR_SLOTS do
	local slot = MakeSlot(HotbarFrame, i)
	slot.Frame.Visible = false
	
	if not LowestEmptySlot then
		LowestEmptySlot = slot
	end
end

-- Make the Inventory, which holds the ScrollingFrame, the header, and the search box
InventoryFrame = NewGui('Frame', 'Inventory')
InventoryFrame.BackgroundTransparency = BACKGROUND_FADE
InventoryFrame.Active = true
InventoryFrame.Size = UDim2.new(0, HotbarFrame.Size.X.Offset, 0, HotbarFrame.Size.Y.Offset * 5) --TODO: No MNs
InventoryFrame.Position = UDim2.new(0.5, -InventoryFrame.Size.X.Offset / 2, 1, HotbarFrame.Position.Y.Offset - InventoryFrame.Size.Y.Offset)
InventoryFrame.Visible = false
InventoryFrame.Parent = MainFrame

-- Make the header title, in the Inventory
-- local headerText = NewGui('TextLabel', 'Header')
-- headerText.Text = TITLE_TEXT
-- headerText.TextXAlignment = Enum.TextXAlignment.Left
-- headerText.Font = Enum.Font.SourceSansBold
-- headerText.FontSize = Enum.FontSize.Size48
-- headerText.TextStrokeColor3 = SLOT_COLOR_EQUIP
-- headerText.TextStrokeTransparency = 0.75 --TODO: No MNs
-- headerText.Size = UDim2.new(0, (InventoryFrame.Size.X.Offset / 2) - TITLE_OFFSET, 0, INVENTORY_HEADER_SIZE)
-- headerText.Position = UDim2.new(0, TITLE_OFFSET, 0, 0)
-- headerText.Parent = InventoryFrame

do -- Search stuff
	local searchFrame = NewGui('Frame', 'Search')
	searchFrame.BackgroundColor3 = SEARCH_BACKGROUND_COLOR
	searchFrame.BackgroundTransparency = SEARCH_BACKGROUND_FADE
	searchFrame.Size = UDim2.new(0, SEARCH_WIDTH, 0, INVENTORY_HEADER_SIZE - (SEARCH_BUFFER * 2))
	searchFrame.Position = UDim2.new(1, -searchFrame.Size.X.Offset - SEARCH_BUFFER, 0, SEARCH_BUFFER)
	searchFrame.Parent = InventoryFrame
	
	local searchBox = NewGui('TextBox', 'TextBox')
	searchBox.Text = SEARCH_TEXT
	searchBox.ClearTextOnFocus = false
	searchBox.FontSize = Enum.FontSize.Size24
	searchBox.TextXAlignment = Enum.TextXAlignment.Left
	searchBox.Size = searchFrame.Size - UDim2.new(0, SEARCH_TEXT_OFFSET_FROMLEFT, 0, 0)
	searchBox.Position = UDim2.new(0, SEARCH_TEXT_OFFSET_FROMLEFT, 0, 0)
	searchBox.Parent = searchFrame
	
	local xButton = NewGui('TextButton', 'X')
	xButton.Text = 'x'
	xButton.TextColor3 = SLOT_COLOR_EQUIP
	xButton.FontSize = Enum.FontSize.Size24
	xButton.TextYAlignment = Enum.TextYAlignment.Bottom
	xButton.BackgroundColor3 = SEARCH_BACKGROUND_COLOR
	xButton.BackgroundTransparency = 0
	xButton.Size = UDim2.new(0, searchFrame.Size.Y.Offset - (SEARCH_BUFFER * 2), 0, searchFrame.Size.Y.Offset - (SEARCH_BUFFER * 2))
	xButton.Position = UDim2.new(1, -xButton.Size.X.Offset - (SEARCH_BUFFER * 2), 0.5, -xButton.Size.Y.Offset / 2)
	xButton.ZIndex = 3
	xButton.Visible = false
	xButton.Parent = searchFrame
	
	local clickArea = NewGui('TextButton', 'GimmieYerClicks')
	clickArea.ZIndex = 2
	clickArea.Parent = searchFrame
	
	local function search()
		local terms = {}
		for word in searchBox.Text:gmatch('%S+') do
			terms[word:lower()] = true
		end
		
		local hitTable = {}
		for i = HOTBAR_SLOTS + 1, #Slots do -- Only search inventory slots
			local slot = Slots[i]
			local hits = slot:CheckTerms(terms)
			table.insert(hitTable, {slot, hits})
			slot.Frame.Visible = false
		end
		
		table.sort(hitTable, function(left, right)
			return left[2] > right[2]
		end)
		ResultsIndices = {}
		
		for i, data in ipairs(hitTable) do
			local slot, hits = data[1], data[2]
			if hits > 0 then
				ResultsIndices[slot] = HOTBAR_SLOTS + i
				slot:Reposition()
				slot.Frame.Visible = true
			end
		end
		
		xButton.Visible = true
	end
	
	local function clearResults()
		if xButton.Visible then
			ResultsIndices = nil
			for i = HOTBAR_SLOTS + 1, #Slots do
				local slot = Slots[i]
				slot:Reposition()
				slot.Frame.Visible = true
			end
			xButton.Visible = false
		end
	end
	
	local function reset()
		clearResults()
		searchBox.Text = SEARCH_TEXT
	end
	
	local function onChanged(property)
		if property == 'Text' then
			local text = searchBox.Text
			if text == '' then
				clearResults()
			elseif text ~= SEARCH_TEXT then
				search()
			end
		end
	end
	
	local function gainFocus()
		searchBox:CaptureFocus()
		if searchBox.Text == SEARCH_TEXT then
			searchBox.Text = ''
		end
	end
	
	local function loseFocus(enterPressed)
		if enterPressed then
			--TODO: Could optimize
			search()
		elseif searchBox.Text == '' then
			searchBox.Text = SEARCH_TEXT
		end
	end
	
	clickArea.MouseButton1Click:connect(gainFocus)
	xButton.MouseButton1Click:connect(reset)
	searchBox.Changed:connect(onChanged)
	searchBox.FocusLost:connect(loseFocus)
	HotkeyFns[Enum.KeyCode.Escape.Value] = reset
	
	ResetSearch = reset -- Define global function
end

-- Make the ScrollingFrame, which holds the rest of the Slots (however many) 
ScrollingFrame = NewGui('ScrollingFrame', 'ScrollingFrame')
ScrollingFrame.Size = UDim2.new(1, ScrollingFrame.ScrollBarThickness + 1, 1, -INVENTORY_HEADER_SIZE)
ScrollingFrame.Position = UDim2.new(0, 0, 0, INVENTORY_HEADER_SIZE)
ScrollingFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
ScrollingFrame.Parent = InventoryFrame

do -- Make the Inventory expand/collapse arrow
	local arrowFrame = NewGui('Frame', 'Arrow')
	arrowFrame.BackgroundTransparency = BACKGROUND_FADE
	arrowFrame.Size = UDim2.new(0, ICON_SIZE, 0, ICON_SIZE / 2)
	local hotbarBottom = HotbarFrame.Position.Y.Offset + HotbarFrame.Size.Y.Offset
	arrowFrame.Position = UDim2.new(0.5, -arrowFrame.Size.X.Offset / 2, 1, hotbarBottom - arrowFrame.Size.Y.Offset)
	
	local arrowIcon = NewGui('ImageLabel', 'Icon')
	arrowIcon.Image = ARROW_IMAGE_OPEN
	arrowIcon.Size = ARROW_SIZE
	arrowIcon.Position = UDim2.new(0.5, -arrowIcon.Size.X.Offset / 2, 0.5, -arrowIcon.Size.Y.Offset / 2)
	arrowIcon.Parent = arrowFrame
	
	local collapsed = arrowFrame.Position
	local closed = collapsed + UDim2.new(0, 0, 0, -HotbarFrame.Size.Y.Offset)
	local opened = closed + UDim2.new(0, 0, 0, -InventoryFrame.Size.Y.Offset)
	
	local clickArea = NewGui('TextButton', 'GimmieYerClicks')
	local function openClose()
		if not next(Dragging) then -- Only continue if nothing is being dragged
			InventoryFrame.Visible = not InventoryFrame.Visible
			local nowOpen = InventoryFrame.Visible
			arrowIcon.Image = (nowOpen) and ARROW_IMAGE_CLOSE or ARROW_IMAGE_OPEN
			clickArea.Modal = nowOpen -- Allows free mouse movement even in first person
			AdjustHotbarFrames()
			UpdateArrowFrame()
			for i = 1, HOTBAR_SLOTS do
				Slots[i]:SetClickability(not nowOpen)
			end
			if not nowOpen then
				ResetSearch()
			end
		end
	end
	clickArea.MouseButton1Click:connect(openClose)
	clickArea.Parent = arrowFrame
	HotkeyFns[ARROW_HOTKEY] = openClose
	
	-- Define global function
	UpdateArrowFrame = function()
		arrowFrame.Position = (InventoryFrame.Visible) and opened or ((FullHotbarSlots == 0) and collapsed or closed)
	end
	
	arrowFrame.Parent = MainFrame
end

-- Now that we're done building the GUI, we connect to all the major events

-- Wait for the player if LocalPlayer wasn't ready earlier
while not Player do
	wait()
	Player = PlayersService.LocalPlayer
end

-- Listen to current and all future characters of our player
Player.CharacterAdded:connect(OnCharacterAdded)
if Player.Character then
	OnCharacterAdded(Player.Character)
end

do -- Hotkey stuff
	-- Init HotkeyStrings, used for eating hotkeys
	for i = 0, 9 do
		table.insert(HotkeyStrings, tostring(i))
	end
	table.insert(HotkeyStrings, ARROW_HOTKEY_STRING)
	
	-- Listen to key down
	UserInputService.InputBegan:connect(OnInputBegan)
	
	-- Listen to ANY TextBox gaining or losing focus, for disabling all hotkeys
	UserInputService.TextBoxFocused:connect(function() TextBoxFocused = true end)
	UserInputService.TextBoxFocusReleased:connect(function() TextBoxFocused = false end)
	
	-- Manual unequip for HopperBins on drop button pressed
	HotkeyFns[DROP_HOTKEY_VALUE] = function() --NOTE: HopperBin
		if ActiveHopper then
			UnequipTools()
		end
	end
	
	-- Listen to keyboard status, for showing/hiding hotkey labels
	UserInputService.Changed:connect(OnUISChanged)
	OnUISChanged('KeyboardEnabled')
end

-- Listen to enable/disable signals from the StarterGui
StarterGui.CoreGuiChangedSignal:connect(OnCoreGuiChanged)
local backpackType = Enum.CoreGuiType.Backpack
OnCoreGuiChanged(backpackType, StarterGui:GetCoreGuiEnabled(backpackType))
