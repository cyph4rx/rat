local loadStartedAt = os.clock()

-- Loading --------------------------------------------------------------------

local function PrintLoad(message)
	print(string.format("[rat.lua] [load +%.2fs] %s", os.clock() - loadStartedAt, tostring(message)))
end

PrintLoad("starting")

local RUNTIME_UNLOAD_KEY = "__RAT_LUA_UNLOAD"
local runtimeEnvironment = nil

pcall(function()
	if typeof(getgenv) == "function" then
		runtimeEnvironment = getgenv()
	end
end)

if runtimeEnvironment and typeof(runtimeEnvironment[RUNTIME_UNLOAD_KEY]) == "function" then
	PrintLoad("unloading previous instance")
	pcall(runtimeEnvironment[RUNTIME_UNLOAD_KEY])
end

-- Services -------------------------------------------------------------------

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local UserInputService = game:GetService("UserInputService")
local StarterGui = game:GetService("StarterGui")
local CoreGui = game:GetService("CoreGui")
local Lighting = game:GetService("Lighting")
local GuiService = game:GetService("GuiService")
local VirtualUser = game:GetService("VirtualUser")

PrintLoad("services ready")

-- Configuration --------------------------------------------------------------

local UI_LIBRARY_URL = "https://raw.githubusercontent.com/muzscripter/ui-librarys/main/octohook%20ui%20source.lua"
local ESP_HIGHLIGHT_NAME = "RatESPHighlight"
local ESP_INFO_NAME = "RatESPInfo"
local ENVIRONMENT_UPDATE_INTERVAL = 0.25
local DEFAULT_FOV = 70
local config = {
	Path = "rat_config.json",
	CacheKey = "__RAT_LUA_CONFIG",
	Http = game:GetService("HttpService"),
}

local ui = nil

do
	PrintLoad("downloading Octohook UI")

	local downloadSucceeded, uiSource = pcall(function()
		return game:HttpGet(UI_LIBRARY_URL, true)
	end)

	assert(downloadSucceeded, "[rat.lua] failed to download Octohook UI: " .. tostring(uiSource))
	assert(typeof(uiSource) == "string" and #uiSource > 0, "[rat.lua] Octohook UI returned an empty response")

	local function ReplaceLiteral(source, oldText, newText, expectedCount)
		local count = 0
		local searchFrom = 1
		local pieces = {}

		while true do
			local first, last = string.find(source, oldText, searchFrom, true)

			if not first then
				table.insert(pieces, string.sub(source, searchFrom))
				break
			end

			table.insert(pieces, string.sub(source, searchFrom, first - 1))
			table.insert(pieces, newText)
			count += 1
			searchFrom = last + 1
		end

		assert(
			count == expectedCount,
			string.format(
				"[rat.lua] Octohook compatibility patch mismatch: expected %d, found %d",
				expectedCount,
				count
			)
		)

		return table.concat(pieces)
	end

	local compatibilityPrelude = [=[
local getgenv = getgenv or function()
	return _G
end

local __ratSignal = {}

function __ratSignal.new()
	local signal = {
		_handlers = {},
		_destroyed = false,
	}

	function signal:Connect(callback)
		assert(typeof(callback) == "function", "signal callback must be a function")

		local connection = {
			Connected = true,
		}
		local entry = {
			connection = connection,
			callback = callback,
		}

		function connection:Disconnect()
			if not self.Connected then
				return
			end

			self.Connected = false

			for index, candidate in ipairs(signal._handlers) do
				if candidate == entry then
					table.remove(signal._handlers, index)
					break
				end
			end
		end

		table.insert(self._handlers, entry)
		return connection
	end

	function signal:Once(callback)
		local connection = nil

		connection = self:Connect(function(...)
			connection:Disconnect()
			callback(...)
		end)

		return connection
	end

	function signal:Fire(...)
		if self._destroyed then
			return
		end

		local arguments = table.pack(...)
		local handlers = table.clone(self._handlers)

		for _, entry in ipairs(handlers) do
			if entry.connection.Connected then
				task.spawn(entry.callback, table.unpack(arguments, 1, arguments.n))
			end
		end
	end

	function signal:Wait()
		local waitingThread = coroutine.running()
		local connection = nil

		connection = self:Connect(function(...)
			connection:Disconnect()
			task.spawn(waitingThread, ...)
		end)

		return coroutine.yield()
	end

	function signal:Destroy()
		self._destroyed = true

		for _, entry in ipairs(self._handlers) do
			entry.connection.Connected = false
		end

		table.clear(self._handlers)
	end

	return signal
end

local function __ratBase64Decode(encoded)
	local decoder = nil

	if syn and syn.crypt and syn.crypt.base64 and syn.crypt.base64.decode then
		decoder = syn.crypt.base64.decode
	elseif crypt and crypt.base64decode then
		decoder = crypt.base64decode
	elseif crypt and crypt.base64 and crypt.base64.decode then
		decoder = crypt.base64.decode
	end

	if decoder then
		local succeeded, decoded = pcall(decoder, encoded)

		if succeeded and typeof(decoded) == "string" then
			return decoded
		end
	end

	local alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
	local cleaned = string.gsub(encoded, "[^" .. alphabet .. "=]", "")
	local bits = string.gsub(cleaned, ".", function(character)
		if character == "=" then
			return ""
		end

		local value = string.find(alphabet, character, 1, true) - 1
		local result = ""

		for bit = 6, 1, -1 do
			result ..= value % (2 ^ bit) - value % (2 ^ (bit - 1)) > 0 and "1" or "0"
		end

		return result
	end)

	return string.gsub(bits, "%d%d%d?%d?%d?%d?%d?%d?", function(byte)
		if #byte ~= 8 then
			return ""
		end

		local value = 0

		for bit = 1, 8 do
			if string.sub(byte, bit, bit) == "1" then
				value += 2 ^ (8 - bit)
			end
		end

		return string.char(value)
	end)
end
]=]

	uiSource = ReplaceLiteral(
		uiSource,
		"if getgenv().library ~= nil then\n    getgenv().library:Unload();\nend",
		[=[local previousLibrary = getgenv().library
if previousLibrary ~= nil then
    pcall(function()
        previousLibrary:Unload()
    end)

    if typeof(previousLibrary.drawings) == 'table' then
        local previousDrawings = {}

        for _, drawing in next, previousLibrary.drawings do
            table.insert(previousDrawings, drawing)
        end

        for _, drawing in ipairs(previousDrawings) do
            pcall(function()
                if typeof(drawing) == 'table' and typeof(drawing.Remove) == 'function' then
                    drawing:Remove()
                elseif typeof(drawing) == 'table' and drawing.Object and typeof(drawing.Object.Remove) == 'function' then
                    drawing.Object:Remove()
                end
            end)
        end

        table.clear(previousLibrary.drawings)
    end

    getgenv().library = nil
end]=],
		1
	)
	uiSource = ReplaceLiteral(
		uiSource,
		"    signal = loadstring(game:HttpGet('https://raw.githubusercontent.com/Quenty/NevermoreEngine/main/src/signal/src/Shared/Signal.lua'))();",
		"    signal = __ratSignal;",
		1
	)
	uiSource = ReplaceLiteral(
		uiSource,
		"        local proxy = newproxy(true);\n        local mt = getmetatable(proxy);",
		"        local proxy = {};\n        local mt = {};\n        setmetatable(proxy, mt);",
		1
	)
	uiSource = ReplaceLiteral(
		uiSource,
		"    makefolder(self.cheatname)\n    makefolder(self.cheatname..'/assets')\n    makefolder(self.cheatname..'/'..self.gamename)\n    makefolder(self.cheatname..'/'..self.gamename..'/configs');",
		"    -- rat.lua keeps Octohook assets in memory and does not create external files.",
		1
	)
	uiSource = ReplaceLiteral(
		uiSource,
		"    for i,v in next, self.images do\n        if not isfile(self.cheatname..'/assets/'..i..'.oh') then\n            writefile(self.cheatname..'/assets/'..i..'.oh', game:HttpGet(v))\n        end\n        self.images[i] = readfile(self.cheatname..'/assets/'..i..'.oh');\n    end",
		"    for i,v in next, self.images do\n        local ok, imageData = pcall(function() return game:HttpGet(v) end)\n        self.images[i] = ok and imageData or ''\n    end",
		1
	)
	uiSource = ReplaceLiteral(
		uiSource,
		"    self.cursor1 = utility:Draw('Triangle', {Filled = true, Color = fromrgb(255,255,255), ZIndex = self.zindexOrder.cursor});\n    self.cursor2 = utility:Draw('Triangle', {Filled = true, Color = fromrgb(85,85,85), self.zindexOrder.cursor-1});\n    local function updateCursor()\n        self.cursor1.Visible = self.open\n        self.cursor2.Visible = self.open\n        if self.cursor1.Visible then\n            local pos = inputservice:GetMouseLocation();\n            self.cursor1.PointA = pos;\n            self.cursor1.PointB = pos + newVector2(16,5);\n            self.cursor1.PointC = pos + newVector2(5,16);\n            self.cursor2.PointA = self.cursor1.PointA + newVector2(0, 0)\n            self.cursor2.PointB = self.cursor1.PointB + newVector2(1, 1)\n            self.cursor2.PointC = self.cursor1.PointC + newVector2(1, 1)\n        end\n    end",
		[=[    -- This executor exposes unsupported Triangle drawings as numeric handles.
    -- Keep Roblox's native cursor and avoid creating those incompatible objects.
    self.cursor1 = {Visible = false};
    self.cursor2 = {Visible = false};
    local function updateCursor()
        self.cursor1.Visible = false
        self.cursor2.Visible = false
    end]=],
		1
	)
	uiSource = ReplaceLiteral(
		uiSource,
		"    if syn then syn.protect_gui(screenGui); end\n    screenGui.Parent = game:GetService('CoreGui');",
		"    if syn and syn.protect_gui then pcall(syn.protect_gui, screenGui); end\n    pcall(function() screenGui.Parent = game:GetService('CoreGui') end)\n    if not screenGui.Parent then screenGui.Parent = players.LocalPlayer:WaitForChild('PlayerGui') end;",
		1
	)
	uiSource = ReplaceLiteral(
		uiSource,
		"function library:Unload()\n    library.unloaded:Fire();\n    for _,c in next, self.connections do\n        c:Disconnect()\n    end\n    for obj in next, self.drawings do\n        obj:Remove()\n    end\n    table.clear(self.drawings)\n    getgenv().library = nil\nend",
		[=[function library:Unload()
    if self._unloading then
        return
    end

    self._unloading = true
    library.unloaded:Fire()

    for _, connection in next, self.connections do
        pcall(function()
            connection:Disconnect()
        end)
    end

    local drawings = {}

    for _, drawing in next, self.drawings do
        table.insert(drawings, drawing)
    end

    for _, drawing in ipairs(drawings) do
        pcall(function()
            if typeof(drawing) == 'table' and typeof(drawing.Remove) == 'function' then
                drawing:Remove()
            elseif typeof(drawing) == 'table' and drawing.Object and typeof(drawing.Object.Remove) == 'function' then
                drawing.Object:Remove()
            end
        end)
    end

    table.clear(self.drawings)
    getgenv().library = nil
end]=],
		1
	)
	uiSource = ReplaceLiteral(uiSource, "syn.crypt.base64.decode", "__ratBase64Decode", 2)
	uiSource = compatibilityPrelude .. "\n" .. uiSource

	local uiLoader, uiLoadError = loadstring(uiSource)

	assert(uiLoader, "[rat.lua] failed to compile Octohook UI: " .. tostring(uiLoadError))
	PrintLoad("Octohook UI downloaded and patched")

	local nativeUi = uiLoader({
		cheatname = "rat.lua",
		gamename = "universal",
		fileext = ".txt",
	})

	assert(typeof(nativeUi) == "table", "[rat.lua] Octohook UI did not return a library")
	assert(typeof(nativeUi.init) == "function", "[rat.lua] Octohook UI is missing init()")

	for themeName, themeColor in pairs(nativeUi.themes[1].theme) do
		nativeUi.theme[themeName] = themeColor
	end

	nativeUi.toggleKey = Enum.KeyCode.RightShift
	nativeUi:init()

	ui = {
		native = nativeUi,
		events = {},
		controlId = 0,
		destroyed = false,
		destroying = false,
		autoDisableToggles = true,
	}

	function ui:NextFlag(kind)
		self.controlId += 1
		return string.format("rat_%s_%d", kind, self.controlId)
	end

	function ui:CreateControl()
		local control = {
			native = nil,
			events = {},
		}

		function control:bindToEvent(eventName, callback)
			if typeof(callback) == "function" then
				self.events[eventName] = callback
			end

			return self
		end

		function control:emit(eventName, ...)
			local callback = self.events[eventName]

			if callback then
				local succeeded, callbackError = pcall(callback, ...)

				if not succeeded then
					warn("[rat.lua] UI callback failed: " .. tostring(callbackError))
				end
			end
		end

		function control:setTooltip(tooltip)
			if self.native then
				self.native.tooltip = tostring(tooltip or "")
			end

			return self
		end

		function control:setText(text)
			if self.native and typeof(self.native.SetText) == "function" then
				self.native:SetText(tostring(text or ""))
			end

			return self
		end

		function control:setState(state)
			if self.native and typeof(self.native.SetState) == "function" then
				self.native:SetState(state == true)
			end

			return self
		end

		function control:getState()
			return self.native and self.native.state == true or false
		end

		return control
	end

	function ui:WrapSection(nativeSection)
		local section = {
			native = nativeSection,
		}

		function section:addLabel(data)
			local control = ui:CreateControl()
			control.native = self.native:AddText({
				text = tostring(data.text or ""),
			})
			return control
		end

		function section:addToggle(data)
			local control = ui:CreateControl()
			control.native = self.native:AddToggle({
				text = tostring(data.text or "Toggle"),
				state = data.state == true,
				flag = ui:NextFlag("toggle"),
				callback = function(state)
					control:emit("onToggle", state)
				end,
			})
			return control
		end

		function section:addSlider(data, callback)
			local control = ui:CreateControl()
			control:bindToEvent("onChange", callback)
			control.native = self.native:AddSlider({
				text = tostring(data.text or "Slider"),
				min = tonumber(data.min) or 0,
				max = tonumber(data.max) or 100,
				increment = tonumber(data.step) or 1,
				value = tonumber(data.value) or tonumber(data.min) or 0,
				flag = ui:NextFlag("slider"),
				callback = function(value)
					control:emit("onChange", value)
				end,
			})
			return control
		end

		function section:addTextbox(data)
			local control = ui:CreateControl()
			control.native = self.native:AddBox({
				text = tostring(data.text or "Text"),
				input = tostring(data.value or ""),
				flag = ui:NextFlag("box"),
				callback = function(value)
					control:emit("onFocusLost", value)
				end,
			})
			return control
		end

		function section:addColorPicker(data, callback)
			local control = ui:CreateControl()
			control:bindToEvent("onChange", callback)
			control.native = self.native:AddColor({
				text = tostring(data.text or "Color"),
				color = data.color or Color3.new(1, 1, 1),
				flag = ui:NextFlag("color"),
				callback = function(color)
					control:emit("onChange", color)
				end,
			})
			return control
		end

		function section:addButton(data, callback)
			local control = ui:CreateControl()
			control.native = self.native:AddButton({
				text = tostring(data.text or "Button"),
				callback = function()
					if typeof(callback) == "function" then
						local succeeded, callbackError = pcall(callback)

						if not succeeded then
							warn("[rat.lua] UI button failed: " .. tostring(callbackError))
						end
					end
				end,
			})
			return control
		end

		return section
	end

	function ui.newWindow(data)
		local requestedSize = data.size or Vector2.new(560, 650)
		local width = math.max(math.floor(requestedSize.X), 560)
		local height = math.max(math.floor(requestedSize.Y), 650)
		local position = data.position

		if typeof(position) == "Vector2" then
			position = UDim2.fromOffset(position.X, position.Y)
		elseif typeof(position) ~= "UDim2" then
			position = UDim2.new(0.5, -math.floor(width / 2), 0.5, -math.floor(height / 2))
		end

		local nativeWindow = ui.native.NewWindow({
			title = tostring(data.text or "rat.lua"),
			size = UDim2.fromOffset(width, height),
			position = position,
		})
		local window = {
			native = nativeWindow,
		}

		function window:addMenu(menuData)
			local nativeTab = self.native:AddTab(tostring(menuData.text or "Menu"))
			local menu = {
				native = nativeTab,
			}

			function menu:addSection(sectionData)
				local side = sectionData.side == "right" and 2 or 1
				return ui:WrapSection(self.native:AddSection(tostring(sectionData.text or "Section"), side))
			end

			return menu
		end

		return window
	end

	function ui.notify(data)
		local title = tostring(data.title or "rat.lua")
		local message = tostring(data.message or "")
		ui.native:SendNotification(title .. " | " .. message, tonumber(data.duration) or 4)
	end

	function ui:bindToEvent(eventName, callback)
		if typeof(callback) == "function" then
			self.events[eventName] = callback
		end

		return self
	end

	function ui.destroy()
		if ui.destroyed or ui.destroying then
			return
		end

		ui.destroying = true
		local callback = ui.events.onPreDestroy

		if callback then
			pcall(callback)
		end

		pcall(function()
			ui.native:Unload()
		end)
		ui.destroyed = true
		ui.destroying = false
	end

	nativeUi.unloaded:Connect(function()
		if not ui.destroyed and not ui.destroying then
			ui.destroyed = true
			local callback = ui.events.onPreDestroy

			if callback then
				pcall(callback)
			end
		end
	end)

	PrintLoad("Octohook UI initialized; RightShift toggles the menu")
end

-- Runtime state ---------------------------------------------------------------

local localPlayer = Players.LocalPlayer
local camera = Workspace.CurrentCamera

local espEnabled = false
local espNameEnabled = true
local espInfoEnabled = true
local espTracersEnabled = true
local espBonesEnabled = false
local espTeamColorEnabled = true
local fullbrightEnabled = false
local terrainGrassDisabled = false
local aimbotEnabled = false
local mouseAimbotEnabled = false
local wallCheckEnabled = true
local aimbotTeamCheckEnabled = false
local triggerbotEnabled = false
local noclipEnabled = false
local infiniteJumpEnabled = false
local flyEnabled = false
local clickTeleportEnabled = false
local antiAFKEnabled = false
local crosshairEnabled = false
local respectAdsFov = true
local adsHeld = false
local aimbotBindHeld = false
local aimbotBindType = Enum.UserInputType.MouseButton2
local aimbotBindKey = nil
local wallCheckHotkeyType = nil
local wallCheckHotkeyKey = nil
local desiredWalkSpeed = nil

local aimbotSettings = {
	Smoothness = 55,
	FOVRadius = 150,
	LockFOVMultiplier = 1.2,
	AimPart = "Head",
	TargetPriority = "Cursor",
	PredictionEnabled = false,
	PredictionTime = 0.12,
	StickyTarget = true,
	TargetHudEnabled = true,
	MouseDeadzone = 0.35,
	MouseMaxStep = 180,
	MouseRemainder = Vector2.zero,
}
local visualSettings = {
	Boxes = true,
	HealthBars = true,
	UpdateInterval = 1 / 30,
	RefreshInterval = 0.25,
	FarDistance = 750,
	VeryFarDistance = 1500,
	FarUpdateInterval = 0.1,
	VeryFarUpdateInterval = 0.2,
	UpdateAccumulator = 0,
	RefreshAccumulator = 0,
}
local radar = {
	Enabled = false,
	Range = 500,
	Size = 190,
	Dots = {},
	Dragging = false,
	DragInput = nil,
	DragStart = Vector2.zero,
	StartPosition = Vector2.zero,
}
local triggerbotSettings = {
	HoldBind = false,
	Delay = 0.1,
	ReactionDelay = 0.03,
	WarningShown = false,
	LastShot = 0,
	Target = nil,
	TargetSince = 0,
}
local TRACER_DISTANCE = 100
local ESP_DISTANCE_CAP = 1000
local ESP_DISTANCE_UNCAPPED = true
local FLY_SPEED = 60
local CROSSHAIR_SIZE = 8
local espColor = Color3.fromRGB(0, 255, 0)
local espExcludedColor = Color3.fromRGB(255, 0, 0)
local crosshairColor = Color3.fromRGB(255, 255, 255)
local espDrawings = {}
local targetModels = {}
local aimbotExclusions = {}
local aimbotExclusionNames = {}
local noclipOriginalCollisions = setmetatable({}, { __mode = "k" })
local originalLightingSettings = nil
local originalLightingEffects = {}
local originalTerrainDecoration = nil
local hasOriginalTerrainDecoration = false
local originalCameraFOVs = {}
local originalHumanoidWalkSpeeds = setmetatable({}, { __mode = "k" })
local trackedConnections = {}
local exclusionsLabel = nil
local aimbotBindLabel = nil
local wallCheckToggle = nil
local playerFov = camera and camera.FieldOfView or DEFAULT_FOV
local environmentUpdateAccumulator = 0
local mouseAimbotWarningShown = false
local isUnloaded = false
local wallCheckRaycastParams = RaycastParams.new()
local groundRaycastParams = RaycastParams.new()
local triggerbotRaycastParams = RaycastParams.new()
local teleportRaycastParams = RaycastParams.new()
local flyVelocity = nil
local flyGyro = nil
local flyHumanoid = nil
local flyOriginalPlatformStand = nil
local flyOriginalAutoRotate = nil

wallCheckRaycastParams.FilterType = Enum.RaycastFilterType.Exclude
wallCheckRaycastParams.IgnoreWater = true
groundRaycastParams.FilterType = Enum.RaycastFilterType.Exclude
triggerbotRaycastParams.FilterType = Enum.RaycastFilterType.Exclude
teleportRaycastParams.FilterType = Enum.RaycastFilterType.Exclude

if camera then
	originalCameraFOVs[camera] = camera.FieldOfView
end

-- Overlay --------------------------------------------------------------------

local espGui = Instance.new("ScreenGui")
espGui.Name = "RatESPOverlay"
espGui.IgnoreGuiInset = true
espGui.ResetOnSpawn = false
espGui.DisplayOrder = 1000
espGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

local overlayParented = pcall(function()
	espGui.Parent = CoreGui
end)

if not overlayParented then
	espGui.Parent = localPlayer:WaitForChild("PlayerGui")
end

local espOverlay = Instance.new("Frame")
espOverlay.Name = "Overlay"
espOverlay.BackgroundTransparency = 1
espOverlay.Size = UDim2.fromScale(1, 1)
espOverlay.ZIndex = 100
espOverlay.Parent = espGui

local aimbotFOVCircle = Instance.new("Frame")
aimbotFOVCircle.Name = "AimbotFOVCircle"
aimbotFOVCircle.AnchorPoint = Vector2.new(0.5, 0.5)
aimbotFOVCircle.BackgroundTransparency = 1
aimbotFOVCircle.BorderSizePixel = 0
aimbotFOVCircle.Visible = false
aimbotFOVCircle.ZIndex = 101
aimbotFOVCircle.Parent = espOverlay

local aimbotFOVCorner = Instance.new("UICorner")
aimbotFOVCorner.CornerRadius = UDim.new(1, 0)
aimbotFOVCorner.Parent = aimbotFOVCircle

local aimbotFOVStroke = Instance.new("UIStroke")
aimbotFOVStroke.Color = Color3.fromRGB(255, 255, 255)
aimbotFOVStroke.Transparency = 0.15
aimbotFOVStroke.Thickness = 1
aimbotFOVStroke.Parent = aimbotFOVCircle

local crosshairLines = {}

for index = 1, 4 do
	local line = Instance.new("Frame")
	line.Name = "CrosshairLine" .. index
	line.AnchorPoint = Vector2.new(0.5, 0.5)
	line.BackgroundColor3 = crosshairColor
	line.BorderSizePixel = 0
	line.Visible = false
	line.ZIndex = 102
	line.Parent = espOverlay
	crosshairLines[index] = line
end

aimbotSettings.TargetHud = Instance.new("TextLabel")
aimbotSettings.TargetHud.Name = "TargetHUD"
aimbotSettings.TargetHud.AnchorPoint = Vector2.new(0.5, 0)
aimbotSettings.TargetHud.Position = UDim2.new(0.5, 0, 0.5, 28)
aimbotSettings.TargetHud.Size = UDim2.fromOffset(320, 22)
aimbotSettings.TargetHud.BackgroundColor3 = Color3.fromRGB(12, 12, 16)
aimbotSettings.TargetHud.BackgroundTransparency = 0.25
aimbotSettings.TargetHud.BorderSizePixel = 0
aimbotSettings.TargetHud.Font = Enum.Font.Code
aimbotSettings.TargetHud.TextColor3 = Color3.fromRGB(255, 255, 255)
aimbotSettings.TargetHud.TextSize = 13
aimbotSettings.TargetHud.TextStrokeTransparency = 0.65
aimbotSettings.TargetHud.Visible = false
aimbotSettings.TargetHud.ZIndex = 102
aimbotSettings.TargetHud.Parent = espOverlay

do
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 4)
	corner.Parent = aimbotSettings.TargetHud
end

radar.Frame = Instance.new("Frame")
radar.Frame.Name = "Radar"
radar.Frame.AnchorPoint = Vector2.zero
radar.Frame.Position = UDim2.new(1, -(radar.Size + 24), 1, -(radar.Size + 24))
radar.Frame.Size = UDim2.fromOffset(radar.Size, radar.Size)
radar.Frame.BackgroundColor3 = Color3.fromRGB(12, 12, 16)
radar.Frame.BackgroundTransparency = 0.2
radar.Frame.BorderSizePixel = 0
radar.Frame.ClipsDescendants = true
radar.Frame.Active = true
radar.Frame.Visible = false
radar.Frame.ZIndex = 103
radar.Frame.Parent = espOverlay

radar.Corner = Instance.new("UICorner")
radar.Corner.CornerRadius = UDim.new(1, 0)
radar.Corner.Parent = radar.Frame

radar.Stroke = Instance.new("UIStroke")
radar.Stroke.Color = Color3.fromRGB(215, 215, 225)
radar.Stroke.Transparency = 0.25
radar.Stroke.Thickness = 1
radar.Stroke.Parent = radar.Frame

radar.Horizontal = Instance.new("Frame")
radar.Horizontal.Name = "Horizontal"
radar.Horizontal.AnchorPoint = Vector2.new(0.5, 0.5)
radar.Horizontal.Position = UDim2.fromScale(0.5, 0.5)
radar.Horizontal.Size = UDim2.new(1, -12, 0, 1)
radar.Horizontal.BackgroundColor3 = Color3.fromRGB(150, 150, 160)
radar.Horizontal.BackgroundTransparency = 0.6
radar.Horizontal.BorderSizePixel = 0
radar.Horizontal.ZIndex = 104
radar.Horizontal.Parent = radar.Frame

radar.Vertical = radar.Horizontal:Clone()
radar.Vertical.Name = "Vertical"
radar.Vertical.Rotation = 90
radar.Vertical.Parent = radar.Frame

radar.Ring = Instance.new("Frame")
radar.Ring.Name = "RangeRing"
radar.Ring.AnchorPoint = Vector2.new(0.5, 0.5)
radar.Ring.Position = UDim2.fromScale(0.5, 0.5)
radar.Ring.Size = UDim2.fromScale(0.5, 0.5)
radar.Ring.BackgroundTransparency = 1
radar.Ring.BorderSizePixel = 0
radar.Ring.ZIndex = 104
radar.Ring.Parent = radar.Frame

radar.RingCorner = Instance.new("UICorner")
radar.RingCorner.CornerRadius = UDim.new(1, 0)
radar.RingCorner.Parent = radar.Ring

radar.RingStroke = Instance.new("UIStroke")
radar.RingStroke.Color = Color3.fromRGB(150, 150, 160)
radar.RingStroke.Transparency = 0.72
radar.RingStroke.Thickness = 1
radar.RingStroke.Parent = radar.Ring

radar.Center = Instance.new("Frame")
radar.Center.Name = "LocalPlayer"
radar.Center.AnchorPoint = Vector2.new(0.5, 0.5)
radar.Center.Position = UDim2.fromScale(0.5, 0.5)
radar.Center.Size = UDim2.fromOffset(7, 7)
radar.Center.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
radar.Center.BorderSizePixel = 0
radar.Center.ZIndex = 106
radar.Center.Parent = radar.Frame

radar.CenterCorner = Instance.new("UICorner")
radar.CenterCorner.CornerRadius = UDim.new(1, 0)
radar.CenterCorner.Parent = radar.Center

radar.Label = Instance.new("TextLabel")
radar.Label.Name = "Range"
radar.Label.AnchorPoint = Vector2.new(0.5, 0)
radar.Label.Position = UDim2.new(0.5, 0, 0, 7)
radar.Label.Size = UDim2.new(1, -20, 0, 18)
radar.Label.BackgroundTransparency = 1
radar.Label.Font = Enum.Font.Code
radar.Label.Text = "radar | 500 studs"
radar.Label.TextColor3 = Color3.fromRGB(225, 225, 235)
radar.Label.TextSize = 12
radar.Label.TextStrokeTransparency = 0.65
radar.Label.ZIndex = 106
radar.Label.Parent = radar.Frame

radar.Forward = Instance.new("TextLabel")
radar.Forward.Name = "Forward"
radar.Forward.AnchorPoint = Vector2.new(0.5, 0)
radar.Forward.Position = UDim2.new(0.5, 0, 0, 24)
radar.Forward.Size = UDim2.fromOffset(24, 18)
radar.Forward.BackgroundTransparency = 1
radar.Forward.Font = Enum.Font.Code
radar.Forward.Text = "^"
radar.Forward.TextColor3 = Color3.fromRGB(255, 255, 255)
radar.Forward.TextSize = 16
radar.Forward.TextStrokeTransparency = 0.5
radar.Forward.ZIndex = 106
radar.Forward.Parent = radar.Frame

radar.Hint = Instance.new("TextLabel")
radar.Hint.Name = "Hint"
radar.Hint.AnchorPoint = Vector2.new(0.5, 1)
radar.Hint.Position = UDim2.new(0.5, 0, 1, -7)
radar.Hint.Size = UDim2.new(1, -20, 0, 16)
radar.Hint.BackgroundTransparency = 1
radar.Hint.Font = Enum.Font.Code
radar.Hint.Text = "drag to move | edge = out of range"
radar.Hint.TextColor3 = Color3.fromRGB(175, 175, 185)
radar.Hint.TextSize = 10
radar.Hint.TextStrokeTransparency = 0.75
radar.Hint.ZIndex = 106
radar.Hint.Parent = radar.Frame

PrintLoad("overlay initialized")

-- Shared utilities ------------------------------------------------------------

local function Notify(title, text)
	if isUnloaded then
		return
	end

	task.spawn(function()
		local sent = pcall(function()
			ui.notify({
				title = title,
				message = text,
				duration = 4,
			})
		end)

		if sent then
			return
		end

		for _ = 1, 10 do
			if isUnloaded then
				break
			end

			local coreSent = pcall(function()
				StarterGui:SetCore("SendNotification", {
					Title = title,
					Text = text,
					Duration = 4,
				})
			end)

			if coreSent then
				break
			end

			task.wait(0.5)
		end
	end)
end

local function TrackConnection(connection)
	table.insert(trackedConnections, connection)
	return connection
end

local function DisconnectAllConnections()
	for _, connection in ipairs(trackedConnections) do
		if connection.Connected then
			connection:Disconnect()
		end
	end

	table.clear(trackedConnections)
end

-- Character and target registry ----------------------------------------------

local function GetLocalRoot()
	local character = localPlayer.Character
	return character and character:FindFirstChild("HumanoidRootPart")
end

local function GetCharacterParts(model)
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local head = model:FindFirstChild("Head")
	local root = model:FindFirstChild("HumanoidRootPart") or head

	return humanoid, head, root
end

local function IsLocalCharacter(model)
	return localPlayer.Character and model == localPlayer.Character
end

local function IsTargetModel(model)
	if not model:IsA("Model") or not model:IsDescendantOf(Workspace) or IsLocalCharacter(model) then
		return false
	end

	local humanoid, head = GetCharacterParts(model)
	return humanoid ~= nil and humanoid.Health > 0 and head ~= nil and head:IsA("BasePart")
end

local function IsTargetCandidate(model)
	if not model or not model:IsA("Model") or not model:IsDescendantOf(Workspace) or IsLocalCharacter(model) then
		return false
	end

	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local head = model:FindFirstChild("Head")

	return humanoid ~= nil and head ~= nil and head:IsA("BasePart")
end

local function RegisterTarget(model)
	if IsTargetCandidate(model) then
		targetModels[model] = true
		return true
	end

	return false
end

local function RegisterTargetFromInstance(instance)
	if not instance then
		return
	end

	local model = instance:IsA("Model") and instance or instance:FindFirstAncestorOfClass("Model")

	if model and model:IsDescendantOf(Workspace) then
		RegisterTarget(model)
	end
end

local function RegisterExistingTargets()
	for _, player in ipairs(Players:GetPlayers()) do
		if player.Character then
			RegisterTarget(player.Character)
		end
	end

	for _, descendant in ipairs(Workspace:GetDescendants()) do
		if descendant:IsA("Humanoid") then
			RegisterTarget(descendant.Parent)
		end
	end
end

local function NormalizeName(text)
	return tostring(text):lower():match("^%s*(.-)%s*$")
end

local function IsESPExcluded(model)
	if aimbotExclusions[NormalizeName(model.Name)] then
		return true
	end

	local player = Players:GetPlayerFromCharacter(model)

	if player then
		return aimbotExclusions[NormalizeName(player.Name)] or aimbotExclusions[NormalizeName(player.DisplayName)]
	end

	return false
end

local function GetESPColor(model)
	local player = Players:GetPlayerFromCharacter(model)

	if IsESPExcluded(model) then
		return espExcludedColor
	end

	if espTeamColorEnabled and player then
		if player.Team then
			return player.Team.TeamColor.Color
		end

		return player.TeamColor.Color
	end

	return espColor
end

local function GetCharacterFromPart(part)
	local current = part

	while current and current ~= Workspace do
		if current:IsA("Model") and current:FindFirstChildOfClass("Humanoid") then
			return current
		end

		current = current.Parent
	end

	return nil
end

local function HasWallCheck(model, targetPart)
	camera = Workspace.CurrentCamera

	if not camera or not targetPart then
		return false, nil
	end

	local ignoreList = { camera }

	if localPlayer.Character then
		table.insert(ignoreList, localPlayer.Character)
	end

	wallCheckRaycastParams.FilterDescendantsInstances = ignoreList

	local origin = camera.CFrame.Position
	local center = targetPart.Position
	local rightOffset = targetPart.CFrame.RightVector * math.min(targetPart.Size.X * 0.32, 0.65)
	local upOffset = targetPart.CFrame.UpVector * math.min(targetPart.Size.Y * 0.32, 0.65)
	local samplePoints = {
		center,
		center + upOffset,
		center + rightOffset,
		center - rightOffset,
		center - (upOffset * 0.55),
	}

	for _, samplePoint in ipairs(samplePoints) do
		local direction = samplePoint - origin

		if direction.Magnitude <= 0.001 then
			return true, samplePoint
		end

		local result = Workspace:Raycast(origin, direction, wallCheckRaycastParams)

		if not result or result.Instance:IsDescendantOf(model) then
			return true, samplePoint
		end
	end

	return false, center
end

local function GetTargets()
	local targets = {}

	for model in pairs(targetModels) do
		if not model.Parent or not model:IsDescendantOf(Workspace) or not IsTargetCandidate(model) then
			targetModels[model] = nil
		elseif IsTargetModel(model) then
			table.insert(targets, model)
		end
	end

	return targets
end

local IsWithinESPDistance

function radar.IsPointInside(screenPosition)
	if not radar.Enabled or not radar.Frame.Visible then
		return false
	end

	local position = radar.Frame.AbsolutePosition
	local size = radar.Frame.AbsoluteSize
	return screenPosition.X >= position.X
		and screenPosition.X <= position.X + size.X
		and screenPosition.Y >= position.Y
		and screenPosition.Y <= position.Y + size.Y
end

function radar.SetAbsolutePosition(position)
	local viewportSize = espOverlay.AbsoluteSize
	local frameSize = radar.Frame.AbsoluteSize

	if viewportSize.X <= 0 or viewportSize.Y <= 0 then
		camera = Workspace.CurrentCamera
		viewportSize = camera and camera.ViewportSize or Vector2.new(1920, 1080)
	end

	if frameSize.X <= 0 or frameSize.Y <= 0 then
		frameSize = Vector2.new(radar.Size, radar.Size)
	end

	local x = math.clamp(position.X, 8, math.max(8, viewportSize.X - frameSize.X - 8))
	local y = math.clamp(position.Y, 8, math.max(8, viewportSize.Y - frameSize.Y - 8))
	radar.Frame.Position = UDim2.fromOffset(x, y)
end

function radar.ClampPosition()
	radar.SetAbsolutePosition(radar.Frame.AbsolutePosition)
end

function radar.ResetPosition()
	radar.Frame.Position = UDim2.new(1, -(radar.Size + 24), 1, -(radar.Size + 24))
	task.defer(radar.ClampPosition)
end

function radar.SetSize(size)
	radar.Size = math.clamp(tonumber(size) or radar.Size, 140, 260)
	radar.Frame.Size = UDim2.fromOffset(radar.Size, radar.Size)
	task.defer(radar.ClampPosition)
end

function radar.BeginDrag(input)
	if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then
		return
	end

	radar.Dragging = true
	radar.DragInput = input
	radar.DragStart = Vector2.new(input.Position.X, input.Position.Y)
	radar.StartPosition = radar.Frame.AbsolutePosition
end

function radar.UpdateDrag(input)
	if not radar.Dragging then
		return
	end

	if radar.DragInput.UserInputType == Enum.UserInputType.Touch then
		if input ~= radar.DragInput then
			return
		end
	elseif input.UserInputType ~= Enum.UserInputType.MouseMovement then
		return
	end

	local currentPosition = Vector2.new(input.Position.X, input.Position.Y)
	radar.SetAbsolutePosition(radar.StartPosition + (currentPosition - radar.DragStart))
end

function radar.EndDrag(input)
	if not radar.Dragging then
		return
	end

	if input == radar.DragInput or input.UserInputType == Enum.UserInputType.MouseButton1 then
		radar.Dragging = false
		radar.DragInput = nil
	end
end

function radar.RemoveDot(model)
	local dot = radar.Dots[model]

	if dot then
		dot:Destroy()
		radar.Dots[model] = nil
	end
end

function radar.Clear()
	for model in pairs(radar.Dots) do
		radar.RemoveDot(model)
	end
end

function radar.SetEnabled(enabled)
	radar.Enabled = enabled
	radar.Frame.Visible = enabled

	if enabled then
		radar.ClampPosition()
		radar.Update()
	else
		radar.Dragging = false
		radar.DragInput = nil
		radar.Clear()
	end
end

function radar.Update()
	if not radar.Enabled then
		return
	end

	radar.ClampPosition()

	local localRoot = GetLocalRoot()

	if not localRoot then
		radar.Clear()
		return
	end

	local activeModels = {}
	local center = radar.Frame.AbsoluteSize / 2
	local radius = math.max(1, math.min(center.X, center.Y) - 13)
	local activeCount = 0

	for _, model in ipairs(GetTargets()) do
		local humanoid, _, root = GetCharacterParts(model)

		if humanoid and humanoid.Health > 0 and root then
			local worldOffset = root.Position - localRoot.Position
			local localOffset = localRoot.CFrame:VectorToObjectSpace(worldOffset)
			local mapOffset = Vector2.new(localOffset.X, localOffset.Z)
			local distance = mapOffset.Magnitude
			local outOfRange = distance > radar.Range
			local scaledOffset = Vector2.zero

			if distance > 0.001 then
				scaledOffset = mapOffset.Unit * (radius * math.clamp(distance / math.max(radar.Range, 1), 0, 1))
			end

			local dot = radar.Dots[model]

			if not dot then
				dot = Instance.new("Frame")
				dot.Name = "Target"
				dot.AnchorPoint = Vector2.new(0.5, 0.5)
				dot.BorderSizePixel = 0
				dot.ZIndex = 107
				dot.Parent = radar.Frame

				local corner = Instance.new("UICorner")
				corner.CornerRadius = UDim.new(1, 0)
				corner.Parent = dot
				radar.Dots[model] = dot
			end

			local dotSize = outOfRange and 6 or 8
			dot.Position = UDim2.fromOffset(center.X + scaledOffset.X, center.Y + scaledOffset.Y)
			dot.Size = UDim2.fromOffset(dotSize, dotSize)
			dot.BackgroundColor3 = GetESPColor(model)
			dot.BackgroundTransparency = outOfRange and 0.35 or 0
			dot.Visible = true

			activeCount += 1
			activeModels[model] = true
		end
	end

	for model in pairs(radar.Dots) do
		if not activeModels[model] then
			radar.RemoveDot(model)
		end
	end

	radar.Label.Text = string.format("radar | %d studs | %d targets", math.floor(radar.Range), activeCount)
end

-- ESP ------------------------------------------------------------------------

local function DrawLine(line, fromPoint, toPoint, color, thickness)
	local difference = toPoint - fromPoint

	line.BackgroundColor3 = color
	line.Position = UDim2.fromOffset((fromPoint.X + toPoint.X) / 2, (fromPoint.Y + toPoint.Y) / 2)
	line.Rotation = math.deg(math.atan2(difference.Y, difference.X))
	line.Size = UDim2.fromOffset(difference.Magnitude, thickness)
	line.Visible = true
end

local function MakeLine(parent, name)
	local line = Instance.new("Frame")
	line.Name = name
	line.AnchorPoint = Vector2.new(0.5, 0.5)
	line.BackgroundTransparency = 0.1
	line.BorderSizePixel = 0
	line.ZIndex = 100
	line.Visible = false
	line.Parent = parent

	return line
end

local function GetDrawing(model)
	if espDrawings[model] then
		return espDrawings[model]
	end

	local container = Instance.new("Frame")
	container.Name = model.Name .. "_ESPDrawings"
	container.BackgroundTransparency = 1
	container.Size = UDim2.fromScale(1, 1)
	container.ZIndex = 100
	container.Parent = espOverlay

	espDrawings[model] = {
		container = container,
		lastUpdate = 0,
		tracer = MakeLine(container, "Tracer"),
		box = {
			MakeLine(container, "BoxTop"),
			MakeLine(container, "BoxRight"),
			MakeLine(container, "BoxBottom"),
			MakeLine(container, "BoxLeft"),
		},
		healthBackground = MakeLine(container, "HealthBackground"),
		healthFill = MakeLine(container, "HealthFill"),
		bones = {},
	}

	return espDrawings[model]
end

local function RemoveDrawing(model)
	local drawing = espDrawings[model]

	if drawing then
		drawing.container:Destroy()
		espDrawings[model] = nil
	end
end

local function ClearDrawings()
	for model in pairs(espDrawings) do
		RemoveDrawing(model)
	end
end

local function GetScreenPoint(part)
	camera = Workspace.CurrentCamera

	if not camera or not part or not part:IsA("BasePart") or not part:IsDescendantOf(Workspace) then
		return nil
	end

	local position, onScreen = camera:WorldToViewportPoint(part.Position)

	if not onScreen or position.Z <= 0 then
		return nil
	end

	return Vector2.new(position.X, position.Y)
end

local r15BonePairs = {
	{ "Head", "UpperTorso" },
	{ "UpperTorso", "LowerTorso" },
	{ "UpperTorso", "LeftUpperArm" },
	{ "LeftUpperArm", "LeftLowerArm" },
	{ "LeftLowerArm", "LeftHand" },
	{ "UpperTorso", "RightUpperArm" },
	{ "RightUpperArm", "RightLowerArm" },
	{ "RightLowerArm", "RightHand" },
	{ "LowerTorso", "LeftUpperLeg" },
	{ "LeftUpperLeg", "LeftLowerLeg" },
	{ "LeftLowerLeg", "LeftFoot" },
	{ "LowerTorso", "RightUpperLeg" },
	{ "RightUpperLeg", "RightLowerLeg" },
	{ "RightLowerLeg", "RightFoot" },
}

local r6BonePairs = {
	{ "Head", "Torso" },
	{ "Torso", "Left Arm" },
	{ "Torso", "Right Arm" },
	{ "Torso", "Left Leg" },
	{ "Torso", "Right Leg" },
}

local function HideDrawing(drawing)
	drawing.tracer.Visible = false
	drawing.healthBackground.Visible = false
	drawing.healthFill.Visible = false

	for _, line in ipairs(drawing.box) do
		line.Visible = false
	end

	for _, line in pairs(drawing.bones) do
		line.Visible = false
	end
end

local function UpdateESPDrawings(model)
	local humanoid, _, root = GetCharacterParts(model)
	local rootPoint = GetScreenPoint(root)
	local localRoot = GetLocalRoot()
	local drawing = GetDrawing(model)

	if not humanoid or humanoid.Health <= 0 or not rootPoint then
		HideDrawing(drawing)
		return
	end

	local color = GetESPColor(model)
	local boxCFrame, boxSize = model:GetBoundingBox()
	local minimum = Vector2.new(math.huge, math.huge)
	local maximum = Vector2.new(-math.huge, -math.huge)
	local projectedCornerCount = 0

	for x = -1, 1, 2 do
		for y = -1, 1, 2 do
			for z = -1, 1, 2 do
				local offset = Vector3.new(boxSize.X * x, boxSize.Y * y, boxSize.Z * z) / 2
				local worldPosition = boxCFrame:PointToWorldSpace(offset)
				local point = camera:WorldToViewportPoint(worldPosition)

				if point.Z > 0 then
					minimum = Vector2.new(math.min(minimum.X, point.X), math.min(minimum.Y, point.Y))
					maximum = Vector2.new(math.max(maximum.X, point.X), math.max(maximum.Y, point.Y))
					projectedCornerCount += 1
				end
			end
		end
	end

	if projectedCornerCount > 0 and maximum.X > minimum.X and maximum.Y > minimum.Y then
		local topLeft = Vector2.new(minimum.X, minimum.Y)
		local topRight = Vector2.new(maximum.X, minimum.Y)
		local bottomRight = Vector2.new(maximum.X, maximum.Y)
		local bottomLeft = Vector2.new(minimum.X, maximum.Y)

		if visualSettings.Boxes then
			DrawLine(drawing.box[1], topLeft, topRight, color, 1)
			DrawLine(drawing.box[2], topRight, bottomRight, color, 1)
			DrawLine(drawing.box[3], bottomRight, bottomLeft, color, 1)
			DrawLine(drawing.box[4], bottomLeft, topLeft, color, 1)
		else
			for _, line in ipairs(drawing.box) do
				line.Visible = false
			end
		end

		if visualSettings.HealthBars then
			local healthRatio = math.clamp(humanoid.Health / math.max(humanoid.MaxHealth, 1), 0, 1)
			local barX = minimum.X - 6
			local barBottom = Vector2.new(barX, maximum.Y)
			local barTop = Vector2.new(barX, minimum.Y)
			local fillTop = Vector2.new(barX, maximum.Y - ((maximum.Y - minimum.Y) * healthRatio))
			DrawLine(drawing.healthBackground, barBottom, barTop, Color3.fromRGB(15, 15, 15), 5)
			DrawLine(drawing.healthFill, barBottom, fillTop, Color3.fromHSV(healthRatio * 0.33, 1, 1), 3)
		else
			drawing.healthBackground.Visible = false
			drawing.healthFill.Visible = false
		end
	else
		for _, line in ipairs(drawing.box) do
			line.Visible = false
		end

		drawing.healthBackground.Visible = false
		drawing.healthFill.Visible = false
	end

	if espTracersEnabled and localRoot and (localRoot.Position - root.Position).Magnitude <= TRACER_DISTANCE then
		DrawLine(drawing.tracer, Vector2.new(camera.ViewportSize.X / 2, camera.ViewportSize.Y), rootPoint, color, 1)
	else
		drawing.tracer.Visible = false
	end

	if not espBonesEnabled then
		for _, line in pairs(drawing.bones) do
			line.Visible = false
		end

		return
	end

	local activeBonePairs = model:FindFirstChild("UpperTorso") and r15BonePairs or r6BonePairs

	for index, pair in ipairs(activeBonePairs) do
		local firstPoint = GetScreenPoint(model:FindFirstChild(pair[1]))
		local secondPoint = GetScreenPoint(model:FindFirstChild(pair[2]))

		if not drawing.bones[index] then
			drawing.bones[index] = MakeLine(drawing.container, "Bone" .. index)
		end

		if firstPoint and secondPoint then
			DrawLine(drawing.bones[index], firstPoint, secondPoint, color, 2)
		else
			drawing.bones[index].Visible = false
		end
	end

	for index = #activeBonePairs + 1, #drawing.bones do
		drawing.bones[index].Visible = false
	end
end

IsWithinESPDistance = function(model)
	if ESP_DISTANCE_UNCAPPED then
		return true
	end

	local _, _, root = GetCharacterParts(model)
	local localRoot = GetLocalRoot()

	if not root or not localRoot then
		return false
	end

	return (localRoot.Position - root.Position).Magnitude <= ESP_DISTANCE_CAP
end

local function UpdateESPLabel(model)
	local billboard = model:FindFirstChild(ESP_INFO_NAME)
	local label = billboard and billboard:FindFirstChild("Info")
	local humanoid, _, root = GetCharacterParts(model)
	local targetPlayer = Players:GetPlayerFromCharacter(model)
	local localRoot = GetLocalRoot()
	local showLabel = espNameEnabled or espInfoEnabled

	if billboard then
		billboard.Enabled = showLabel
	end

	if not showLabel then
		return
	end

	if not label or not humanoid or not root or not localRoot then
		return
	end

	local distance = math.floor((localRoot.Position - root.Position).Magnitude)
	local health = math.floor(humanoid.Health)
	local lines = {}
	label.TextColor3 = GetESPColor(model)

	if espNameEnabled then
		local displayName = model.Name

		if targetPlayer then
			displayName = targetPlayer.DisplayName ~= targetPlayer.Name
					and (targetPlayer.DisplayName .. " (@" .. targetPlayer.Name .. ")")
				or ("@" .. targetPlayer.Name)
		end

		table.insert(lines, displayName)
	end

	if espInfoEnabled then
		table.insert(lines, health .. " HP | " .. distance .. " studs")
	end

	label.Text = table.concat(lines, "\n")
end

local function CreateESP(model)
	if not IsTargetModel(model) or not IsWithinESPDistance(model) then
		return
	end

	local _, head = GetCharacterParts(model)
	local highlight = model:FindFirstChild(ESP_HIGHLIGHT_NAME)

	if not highlight then
		highlight = Instance.new("Highlight")
		highlight.Name = ESP_HIGHLIGHT_NAME
		highlight.Parent = model
	end

	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	highlight.Enabled = true
	highlight.FillColor = GetESPColor(model)
	highlight.FillTransparency = 0.88
	highlight.OutlineColor = GetESPColor(model)
	highlight.OutlineTransparency = 0

	if (espNameEnabled or espInfoEnabled) and not model:FindFirstChild(ESP_INFO_NAME) then
		local billboard = Instance.new("BillboardGui")
		billboard.Name = ESP_INFO_NAME
		billboard.Adornee = head
		billboard.AlwaysOnTop = true
		billboard.MaxDistance = ESP_DISTANCE_UNCAPPED and 1000000 or ESP_DISTANCE_CAP
		billboard.Size = UDim2.fromOffset(220, 55)
		billboard.StudsOffset = Vector3.new(0, 3, 0)
		billboard.Parent = model

		local label = Instance.new("TextLabel")
		label.Name = "Info"
		label.BackgroundTransparency = 1
		label.Size = UDim2.fromScale(1, 1)
		label.Font = Enum.Font.Code
		label.TextColor3 = Color3.new(1, 1, 1)
		label.TextSize = 14
		label.TextStrokeTransparency = 0.25
		label.TextWrapped = true
		label.Parent = billboard
	end

	local billboard = model:FindFirstChild(ESP_INFO_NAME)

	if billboard then
		billboard.MaxDistance = ESP_DISTANCE_UNCAPPED and 1000000 or ESP_DISTANCE_CAP
	end

	UpdateESPLabel(model)
end

local function RemoveESP(model)
	local highlight = model:FindFirstChild(ESP_HIGHLIGHT_NAME)
	local billboard = model:FindFirstChild(ESP_INFO_NAME)

	if highlight then
		highlight:Destroy()
	end

	if billboard then
		billboard:Destroy()
	end

	RemoveDrawing(model)
end

local function RefreshESP()
	for model in pairs(espDrawings) do
		if not model.Parent or not IsTargetModel(model) or not IsWithinESPDistance(model) then
			RemoveESP(model)
		end
	end

	for _, model in ipairs(GetTargets()) do
		if IsWithinESPDistance(model) then
			CreateESP(model)
		else
			RemoveESP(model)
		end
	end
end

local function UpdateESPVisuals()
	local localRoot = GetLocalRoot()
	local now = os.clock()

	for model in pairs(targetModels) do
		if IsTargetModel(model) and IsWithinESPDistance(model) then
			local _, _, root = GetCharacterParts(model)
			local drawing = espDrawings[model]
			local updateInterval = 0

			if localRoot and root then
				local distance = (localRoot.Position - root.Position).Magnitude

				if distance >= visualSettings.VeryFarDistance then
					updateInterval = visualSettings.VeryFarUpdateInterval
				elseif distance >= visualSettings.FarDistance then
					updateInterval = visualSettings.FarUpdateInterval
				end
			end

			if not drawing or now - drawing.lastUpdate >= updateInterval then
				UpdateESPDrawings(model)
				drawing = espDrawings[model]

				if drawing then
					drawing.lastUpdate = now
				end
			end
		elseif espDrawings[model] then
			HideDrawing(espDrawings[model])
		end
	end
end

local function RemoveAllESP()
	for model in pairs(targetModels) do
		RemoveESP(model)
	end

	ClearDrawings()
end

local function SetESP(enabled)
	espEnabled = enabled
	visualSettings.UpdateAccumulator = 0
	visualSettings.RefreshAccumulator = 0

	if espEnabled then
		for _, model in ipairs(GetTargets()) do
			if IsWithinESPDistance(model) then
				CreateESP(model)
			end
		end
	else
		RemoveAllESP()
	end
end

-- Lighting and environment ----------------------------------------------------

local function IsLightingPostEffect(instance)
	return instance:IsA("BloomEffect")
		or instance:IsA("BlurEffect")
		or instance:IsA("ColorCorrectionEffect")
		or instance:IsA("DepthOfFieldEffect")
		or instance:IsA("SunRaysEffect")
end

local function CaptureLightingEffect(instance)
	if originalLightingEffects[instance] then
		return
	end

	if instance:IsA("Atmosphere") then
		originalLightingEffects[instance] = {
			Density = instance.Density,
			Haze = instance.Haze,
			Glare = instance.Glare,
		}
	elseif IsLightingPostEffect(instance) then
		originalLightingEffects[instance] = {
			Enabled = instance.Enabled,
		}
	end
end

local function CaptureLightingSettings()
	if originalLightingSettings then
		return
	end

	originalLightingSettings = {
		Ambient = Lighting.Ambient,
		Brightness = Lighting.Brightness,
		ClockTime = Lighting.ClockTime,
		ColorShift_Bottom = Lighting.ColorShift_Bottom,
		ColorShift_Top = Lighting.ColorShift_Top,
		ExposureCompensation = Lighting.ExposureCompensation,
		FogColor = Lighting.FogColor,
		FogEnd = Lighting.FogEnd,
		FogStart = Lighting.FogStart,
		GlobalShadows = Lighting.GlobalShadows,
		OutdoorAmbient = Lighting.OutdoorAmbient,
	}

	table.clear(originalLightingEffects)

	for _, child in ipairs(Lighting:GetChildren()) do
		CaptureLightingEffect(child)
	end
end

local function DisableLightingEffect(instance)
	CaptureLightingEffect(instance)

	if instance:IsA("Atmosphere") then
		instance.Density = 0
		instance.Haze = 0
		instance.Glare = 0
	elseif IsLightingPostEffect(instance) then
		instance.Enabled = false
	end
end

local function MaintainFullbright()
	if not fullbrightEnabled then
		return
	end

	CaptureLightingSettings()

	Lighting.Ambient = Color3.fromRGB(190, 190, 190)
	Lighting.Brightness = 2
	Lighting.ExposureCompensation = 0
	Lighting.OutdoorAmbient = Color3.fromRGB(190, 190, 190)

	Lighting.ClockTime = 14
	Lighting.ColorShift_Bottom = Color3.new(0, 0, 0)
	Lighting.ColorShift_Top = Color3.new(0, 0, 0)
	Lighting.FogColor = Color3.new(1, 1, 1)
	Lighting.FogEnd = 1000000
	Lighting.FogStart = 0
	Lighting.GlobalShadows = false

	for _, child in ipairs(Lighting:GetChildren()) do
		DisableLightingEffect(child)
	end
end

local function RestoreLightingSettings()
	if originalLightingSettings then
		for property, value in pairs(originalLightingSettings) do
			Lighting[property] = value
		end
	end

	for instance, settings in pairs(originalLightingEffects) do
		if instance and instance.Parent then
			for property, value in pairs(settings) do
				instance[property] = value
			end
		end
	end

	originalLightingSettings = nil
	table.clear(originalLightingEffects)
end

local function SetFullbright(enabled)
	fullbrightEnabled = enabled

	if fullbrightEnabled then
		MaintainFullbright()
	else
		RestoreLightingSettings()
	end
end

local function ApplyTerrainGrass()
	if not terrainGrassDisabled then
		return
	end

	if not hasOriginalTerrainDecoration then
		local success, value = pcall(function()
			return Workspace.Terrain.Decoration
		end)

		if success then
			originalTerrainDecoration = value
			hasOriginalTerrainDecoration = true
		end
	end

	pcall(function()
		Workspace.Terrain.Decoration = false
	end)
end

local function SetTerrainGrassDisabled(enabled)
	terrainGrassDisabled = enabled

	if terrainGrassDisabled then
		ApplyTerrainGrass()
	elseif hasOriginalTerrainDecoration then
		pcall(function()
			Workspace.Terrain.Decoration = originalTerrainDecoration
		end)

		originalTerrainDecoration = nil
		hasOriginalTerrainDecoration = false
	end
end

-- Player movement and camera --------------------------------------------------

local function SetWalkSpeed(value)
	local numericValue = tonumber(value)

	if not numericValue then
		return false
	end

	desiredWalkSpeed = math.clamp(numericValue, 0, 500)

	local character = localPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")

	if humanoid then
		if originalHumanoidWalkSpeeds[humanoid] == nil then
			originalHumanoidWalkSpeeds[humanoid] = humanoid.WalkSpeed
		end

		humanoid.WalkSpeed = desiredWalkSpeed
	end

	return true
end

local function setPlayerFov(value)
	playerFov = math.clamp(tonumber(value) or playerFov, 40, 120)
	camera = Workspace.CurrentCamera

	if camera and (not respectAdsFov or not adsHeld) then
		originalCameraFOVs[camera] = originalCameraFOVs[camera] or camera.FieldOfView
		camera.FieldOfView = playerFov
	end
end

local function RestorePlayerSettings()
	camera = Workspace.CurrentCamera

	for originalCamera, fieldOfView in pairs(originalCameraFOVs) do
		if originalCamera and originalCamera.Parent then
			originalCamera.FieldOfView = fieldOfView
		end
	end

	for humanoid, walkSpeed in pairs(originalHumanoidWalkSpeeds) do
		if humanoid and humanoid.Parent then
			humanoid.WalkSpeed = walkSpeed
		end
	end

	table.clear(originalHumanoidWalkSpeeds)
	table.clear(originalCameraFOVs)
	desiredWalkSpeed = nil
end

local function RestoreNoclipCollisions()
	for part, canCollide in pairs(noclipOriginalCollisions) do
		if part and part.Parent then
			part.CanCollide = canCollide
		end
	end

	table.clear(noclipOriginalCollisions)
end

local function SetNoclip(enabled)
	noclipEnabled = enabled

	if not noclipEnabled then
		RestoreNoclipCollisions()
	end
end

local function SetInfiniteJump(enabled)
	infiniteJumpEnabled = enabled
end

local function DestroyFlyMovers()
	if flyVelocity then
		flyVelocity:Destroy()
		flyVelocity = nil
	end

	if flyGyro then
		flyGyro:Destroy()
		flyGyro = nil
	end

	if flyHumanoid and flyHumanoid.Parent then
		if flyOriginalPlatformStand ~= nil then
			flyHumanoid.PlatformStand = flyOriginalPlatformStand
		end

		if flyOriginalAutoRotate ~= nil then
			flyHumanoid.AutoRotate = flyOriginalAutoRotate
		end
	end

	flyHumanoid = nil
	flyOriginalPlatformStand = nil
	flyOriginalAutoRotate = nil
end

local function SetFly(enabled)
	flyEnabled = enabled

	if not flyEnabled then
		DestroyFlyMovers()
	end
end

local function UpdateFly()
	if not flyEnabled then
		return
	end

	camera = Workspace.CurrentCamera

	local character = localPlayer.Character
	local humanoid, _head, root

	if character then
		humanoid, _head, root = GetCharacterParts(character)
	end

	if not camera or not humanoid or humanoid.Health <= 0 or not root then
		DestroyFlyMovers()
		return
	end

	if
		flyHumanoid ~= humanoid
		or not flyVelocity
		or flyVelocity.Parent ~= root
		or not flyGyro
		or flyGyro.Parent ~= root
	then
		DestroyFlyMovers()

		flyHumanoid = humanoid
		flyOriginalPlatformStand = humanoid.PlatformStand
		flyOriginalAutoRotate = humanoid.AutoRotate

		flyVelocity = Instance.new("BodyVelocity")
		flyVelocity.Name = "RatFlyVelocity"
		flyVelocity.MaxForce = Vector3.new(1e9, 1e9, 1e9)
		flyVelocity.P = 25000
		flyVelocity.Velocity = Vector3.zero
		flyVelocity.Parent = root

		flyGyro = Instance.new("BodyGyro")
		flyGyro.Name = "RatFlyGyro"
		flyGyro.D = 500
		flyGyro.MaxTorque = Vector3.new(1e9, 1e9, 1e9)
		flyGyro.P = 25000
		flyGyro.Parent = root
	end

	humanoid.PlatformStand = true
	humanoid.AutoRotate = false

	local direction = Vector3.zero
	local cameraFrame = camera.CFrame

	if not UserInputService:GetFocusedTextBox() then
		if UserInputService:IsKeyDown(Enum.KeyCode.W) then
			direction += cameraFrame.LookVector
		end

		if UserInputService:IsKeyDown(Enum.KeyCode.S) then
			direction -= cameraFrame.LookVector
		end

		if UserInputService:IsKeyDown(Enum.KeyCode.D) then
			direction += cameraFrame.RightVector
		end

		if UserInputService:IsKeyDown(Enum.KeyCode.A) then
			direction -= cameraFrame.RightVector
		end

		if UserInputService:IsKeyDown(Enum.KeyCode.Space) then
			direction += Vector3.yAxis
		end

		if
			UserInputService:IsKeyDown(Enum.KeyCode.LeftControl)
			or UserInputService:IsKeyDown(Enum.KeyCode.RightControl)
		then
			direction -= Vector3.yAxis
		end
	end

	flyVelocity.Velocity = direction.Magnitude > 0 and direction.Unit * FLY_SPEED or Vector3.zero
	flyGyro.CFrame = CFrame.lookAt(root.Position, root.Position + cameraFrame.LookVector)
end

local function TeleportToCursor()
	camera = Workspace.CurrentCamera

	local character = localPlayer.Character
	local humanoid, _head, root

	if character then
		humanoid, _head, root = GetCharacterParts(character)
	end

	if not camera or not character or not humanoid or humanoid.Health <= 0 or not root then
		return
	end

	local mousePosition = UserInputService:GetMouseLocation()
	local topLeftInset = GuiService:GetGuiInset()
	local viewportPosition = mousePosition - topLeftInset
	local ray = camera:ViewportPointToRay(viewportPosition.X, viewportPosition.Y)

	teleportRaycastParams.FilterDescendantsInstances = { character, camera }

	local result = Workspace:Raycast(ray.Origin, ray.Direction * 5000, teleportRaycastParams)

	if not result then
		return
	end

	local heightOffset = humanoid.HipHeight + (root.Size.Y / 2) + 0.5
	local targetPosition = result.Position + result.Normal * heightOffset

	root.CFrame = CFrame.new(targetPosition) * root.CFrame.Rotation
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
end

local function ApplyWallNoclip(character)
	for _, instance in ipairs(character:GetDescendants()) do
		if instance:IsA("BasePart") then
			if noclipOriginalCollisions[instance] == nil then
				noclipOriginalCollisions[instance] = instance.CanCollide
			end

			instance.CanCollide = false
		end
	end
end

local function KeepNoclipOnGround(character)
	local humanoid, _, root = GetCharacterParts(character)

	if not humanoid or not root then
		return
	end

	local ignoreList = { character }

	if camera then
		table.insert(ignoreList, camera)
	end

	groundRaycastParams.FilterDescendantsInstances = ignoreList

	local origin = root.Position + Vector3.new(0, 1, 0)
	local result = Workspace:Raycast(origin, Vector3.new(0, -12, 0), groundRaycastParams)

	if not result or result.Normal.Y < 0.55 then
		return
	end

	local targetY = result.Position.Y + humanoid.HipHeight + (root.Size.Y / 2)

	if root.Position.Y >= targetY then
		return
	end

	root.CFrame = root.CFrame + Vector3.new(0, targetY - root.Position.Y, 0)

	if root.AssemblyLinearVelocity.Y < 0 then
		root.AssemblyLinearVelocity = Vector3.new(root.AssemblyLinearVelocity.X, 0, root.AssemblyLinearVelocity.Z)
	end
end

local function UpdateNoclip()
	if not noclipEnabled then
		return
	end

	local character = localPlayer.Character

	if not character then
		return
	end

	ApplyWallNoclip(character)
	KeepNoclipOnGround(character)
end

-- Aimbot, exclusions, and binds ----------------------------------------------

local keyCodesByName = {}

for _, keyCode in ipairs(Enum.KeyCode:GetEnumItems()) do
	keyCodesByName[keyCode.Name:lower()] = keyCode
end

local function TrimText(text)
	return tostring(text):match("^%s*(.-)%s*$")
end

local function UpdateExclusionsLabel()
	if not exclusionsLabel then
		return
	end

	if #aimbotExclusionNames == 0 then
		exclusionsLabel:setText("Excluded: none")
	else
		exclusionsLabel:setText("Excluded: " .. table.concat(aimbotExclusionNames, ", "))
	end
end

local function SetAimbotExclusionsFromText(text)
	table.clear(aimbotExclusions)
	table.clear(aimbotExclusionNames)

	for name in tostring(text):gmatch("[^,\n;]+") do
		local trimmed = TrimText(name)
		local normalized = NormalizeName(trimmed)

		if normalized ~= "" and not aimbotExclusions[normalized] then
			aimbotExclusions[normalized] = true
			table.insert(aimbotExclusionNames, trimmed)
		end
	end

	UpdateExclusionsLabel()

	if espEnabled then
		RefreshESP()
	end

	Notify("Aimbot Exclusions", exclusionsLabel and exclusionsLabel:getText() or "Updated excluded players")
end

local function ClearAimbotExclusions()
	table.clear(aimbotExclusions)
	table.clear(aimbotExclusionNames)
	UpdateExclusionsLabel()

	if espEnabled then
		RefreshESP()
	end

	Notify("Aimbot Exclusions", "Excluded: none")
end

function aimbotSettings.SetAimPartFromText(text)
	local modes = { head = "Head", torso = "Torso", root = "Root", closest = "Closest" }
	local mode = modes[NormalizeName(text)]
	if not mode then
		Notify("Invalid Aim Part", "Use Head, Torso, Root, or Closest")
		return false
	end

	aimbotSettings.AimPart = mode
	aimbotSettings.LockedModel = nil
	return true
end

function aimbotSettings.SetTargetPriorityFromText(text)
	local modes = { cursor = "Cursor", distance = "Distance", health = "Health" }
	local mode = modes[NormalizeName(text)]
	if not mode then
		Notify("Invalid Priority", "Use Cursor, Distance, or Health")
		return false
	end

	aimbotSettings.TargetPriority = mode
	aimbotSettings.LockedModel = nil
	return true
end

local function IsAimbotExcluded(model)
	local player = Players:GetPlayerFromCharacter(model)

	if aimbotExclusions[NormalizeName(model.Name)] then
		return true
	end

	if player then
		return aimbotExclusions[NormalizeName(player.Name)] or aimbotExclusions[NormalizeName(player.DisplayName)]
	end

	return false
end

local function GetBindName()
	if not aimbotBindType then
		return "none"
	end

	if aimbotBindType == Enum.UserInputType.Keyboard and aimbotBindKey then
		return aimbotBindKey.Name
	end

	if aimbotBindType == Enum.UserInputType.MouseButton2 then
		return "RMB"
	elseif aimbotBindType == Enum.UserInputType.MouseButton1 then
		return "LMB"
	elseif aimbotBindType == Enum.UserInputType.MouseButton3 then
		return "MMB"
	end

	return aimbotBindType.Name
end

local function GetInputBindName(inputType, keyCode)
	if inputType == Enum.UserInputType.Keyboard and keyCode then
		return keyCode.Name
	end

	if inputType == Enum.UserInputType.MouseButton2 then
		return "RMB"
	elseif inputType == Enum.UserInputType.MouseButton1 then
		return "LMB"
	elseif inputType == Enum.UserInputType.MouseButton3 then
		return "MMB"
	elseif inputType then
		return inputType.Name
	end

	return "none"
end

local function ParseInputBind(text)
	local cleaned = tostring(text):gsub("%s+", "")
	local lowered = cleaned:lower()

	if lowered == "" or lowered == "none" or lowered == "clear" then
		return nil, nil
	elseif lowered == "rmb" or lowered == "rightmouse" or lowered == "mousebutton2" then
		return Enum.UserInputType.MouseButton2, nil
	elseif lowered == "lmb" or lowered == "leftmouse" or lowered == "mousebutton1" then
		return Enum.UserInputType.MouseButton1, nil
	elseif lowered == "mmb" or lowered == "middlemouse" or lowered == "mousebutton3" then
		return Enum.UserInputType.MouseButton3, nil
	end

	local keyCode = keyCodesByName[lowered]

	if keyCode then
		return Enum.UserInputType.Keyboard, keyCode
	end

	return false, nil
end

local function SetAimbotBindFromText(text)
	local inputType, keyCode = ParseInputBind(text)

	if inputType == false then
		Notify("Invalid Bind", "Use RMB, LMB, MMB, or a KeyCode like Q")
		return false
	end

	aimbotBindType = inputType
	aimbotBindKey = keyCode
	aimbotBindHeld = false
	aimbotSettings.LockedModel = nil
	aimbotSettings.MouseRemainder = Vector2.zero

	if aimbotBindLabel then
		aimbotBindLabel:setText(
			aimbotBindType and ("Hold " .. GetBindName() .. " while enabled") or "Aimbot hold bind: none"
		)
	end

	Notify("Aimbot Bind", aimbotBindType and ("Set to " .. GetBindName()) or "Cleared")
	return true
end

local function SetWallCheckHotkeyFromText(text)
	local inputType, keyCode = ParseInputBind(text)

	if inputType == false then
		Notify("Invalid Hotkey", "Use RMB, LMB, MMB, or a KeyCode like Q")
		return false
	end

	wallCheckHotkeyType = inputType
	wallCheckHotkeyKey = keyCode

	if not wallCheckHotkeyType then
		Notify("Wallcheck Hotkey", "Cleared")
	else
		Notify("Wallcheck Hotkey", "Set to " .. GetInputBindName(wallCheckHotkeyType, wallCheckHotkeyKey))
	end

	return true
end

local function SetWallCheck(enabled, syncToggle)
	wallCheckEnabled = enabled
	aimbotSettings.LockedModel = nil
	aimbotSettings.MouseRemainder = Vector2.zero

	if
		syncToggle
		and wallCheckToggle
		and typeof(wallCheckToggle.getState) == "function"
		and wallCheckToggle:getState() ~= wallCheckEnabled
	then
		pcall(function()
			if typeof(wallCheckToggle.setState) == "function" then
				wallCheckToggle:setState(wallCheckEnabled)
			end
		end)
	end
end

local function ToggleWallCheckFromHotkey()
	SetWallCheck(not wallCheckEnabled, true)
	Notify("Wallcheck", wallCheckEnabled and "Enabled" or "Disabled")
end

local function IsAimbotBind(input)
	if not aimbotBindType then
		return false
	end

	if aimbotBindType == Enum.UserInputType.Keyboard then
		return input.UserInputType == Enum.UserInputType.Keyboard and input.KeyCode == aimbotBindKey
	end

	return input.UserInputType == aimbotBindType
end

local function IsWallCheckHotkey(input)
	if not wallCheckHotkeyType then
		return false
	end

	if wallCheckHotkeyType == Enum.UserInputType.Keyboard then
		return input.UserInputType == Enum.UserInputType.Keyboard and input.KeyCode == wallCheckHotkeyKey
	end

	return input.UserInputType == wallCheckHotkeyType
end

local function GetAimbotScreenOrigin()
	camera = Workspace.CurrentCamera

	if not camera then
		return nil, Vector2.zero
	end

	local topLeftInset = Vector2.zero
	local insetSucceeded, inset = pcall(function()
		return GuiService:GetGuiInset()
	end)

	if insetSucceeded then
		topLeftInset = inset
	end

	if mouseAimbotEnabled and UserInputService.MouseBehavior ~= Enum.MouseBehavior.LockCenter then
		return UserInputService:GetMouseLocation() - topLeftInset, topLeftInset
	end

	return camera.ViewportSize / 2, topLeftInset
end

local function UpdateAimbotFOVCircle()
	local aimOrigin = GetAimbotScreenOrigin()

	if not aimOrigin then
		aimbotFOVCircle.Visible = false
		return
	end

	local diameter = aimbotSettings.FOVRadius * 2

	aimbotFOVCircle.Position = UDim2.fromOffset(aimOrigin.X, aimOrigin.Y)
	aimbotFOVCircle.Size = UDim2.fromOffset(diameter, diameter)
	aimbotFOVCircle.Visible = aimbotEnabled
	aimbotFOVStroke.Color = aimbotSettings.LockedModel and Color3.fromRGB(80, 255, 120) or Color3.fromRGB(255, 255, 255)
end

function aimbotSettings.UpdateTargetHud()
	local model = aimbotSettings.LockedModel
	local humanoid = model and model:FindFirstChildOfClass("Humanoid")
	local targetRoot = nil
	if model then
		local _, _, root = GetCharacterParts(model)
		targetRoot = root
	end
	local localRoot = GetLocalRoot()

	if not aimbotSettings.TargetHudEnabled or not aimbotBindHeld or not humanoid or humanoid.Health <= 0 or not targetRoot then
		aimbotSettings.TargetHud.Visible = false
		return
	end

	local player = Players:GetPlayerFromCharacter(model)
	local name = player and player.DisplayName or model.Name
	local distance = localRoot and math.floor((targetRoot.Position - localRoot.Position).Magnitude) or 0
	aimbotSettings.TargetHud.Text = string.format("%s | %d/%d hp | %d studs", name, math.ceil(humanoid.Health), math.ceil(humanoid.MaxHealth), distance)
	aimbotSettings.TargetHud.TextColor3 = Color3.fromHSV(math.clamp(humanoid.Health / math.max(humanoid.MaxHealth, 1), 0, 1) * 0.33, 0.8, 1)
	aimbotSettings.TargetHud.Visible = true
end

local function UpdateCrosshair()
	camera = Workspace.CurrentCamera

	if not camera or not crosshairEnabled then
		for _, line in ipairs(crosshairLines) do
			line.Visible = false
		end

		return
	end

	local center = camera.ViewportSize / 2
	local length = CROSSHAIR_SIZE
	local gap = 4
	local thickness = 2

	for _, line in ipairs(crosshairLines) do
		line.BackgroundColor3 = crosshairColor
		line.Visible = true
	end

	crosshairLines[1].Position = UDim2.fromOffset(center.X - gap - (length / 2), center.Y)
	crosshairLines[1].Size = UDim2.fromOffset(length, thickness)
	crosshairLines[2].Position = UDim2.fromOffset(center.X + gap + (length / 2), center.Y)
	crosshairLines[2].Size = UDim2.fromOffset(length, thickness)
	crosshairLines[3].Position = UDim2.fromOffset(center.X, center.Y - gap - (length / 2))
	crosshairLines[3].Size = UDim2.fromOffset(thickness, length)
	crosshairLines[4].Position = UDim2.fromOffset(center.X, center.Y + gap + (length / 2))
	crosshairLines[4].Size = UDim2.fromOffset(thickness, length)
end

local function IsScreenPointInAimbotFOV(screenPosition, radiusMultiplier)
	local aimOrigin = GetAimbotScreenOrigin()

	if not aimOrigin then
		return false
	end

	return (screenPosition - aimOrigin).Magnitude <= aimbotSettings.FOVRadius * (radiusMultiplier or 1)
end

local function IsSameTeam(model)
	if not aimbotTeamCheckEnabled or not localPlayer.Team then
		return false
	end

	local player = Players:GetPlayerFromCharacter(model)
	return player ~= nil and player.Team == localPlayer.Team
end

function aimbotSettings.IsEligibleCombatTarget(model)
	return IsTargetModel(model)
		and IsWithinESPDistance(model)
		and not IsAimbotExcluded(model)
		and not IsSameTeam(model)
end

function aimbotSettings.GetConfiguredAimParts(model)
	local _, head, root = GetCharacterParts(model)
	local torso = model:FindFirstChild("UpperTorso") or model:FindFirstChild("Torso") or root
	local mode = aimbotSettings.AimPart

	if mode == "Closest" then
		return { head, torso, root }
	elseif mode == "Torso" then
		return { torso }
	elseif mode == "Root" then
		return { root }
	end

	return { head }
end

function aimbotSettings.GetPredictedAimPosition(part, position)
	if not aimbotSettings.PredictionEnabled then
		return position
	end

	local velocity = part.AssemblyLinearVelocity
	if velocity.Magnitude > 250 then
		velocity = velocity.Unit * 250
	end

	return position + (velocity * aimbotSettings.PredictionTime)
end

local function GetAimbotTargetPoint(model)
	if not aimbotSettings.IsEligibleCombatTarget(model) then
		return nil, nil
	end

	camera = Workspace.CurrentCamera
	local aimOrigin = GetAimbotScreenOrigin()
	local bestPart, bestPosition, bestDistance = nil, nil, math.huge

	for _, part in ipairs(aimbotSettings.GetConfiguredAimParts(model)) do
		if part and part:IsA("BasePart") then
			local visible, position = true, part.Position

			if wallCheckEnabled then
				visible, position = HasWallCheck(model, part)
			end

			if visible then
				position = aimbotSettings.GetPredictedAimPosition(part, position or part.Position)
				local point, onScreen = nil, false
				if camera then
					point, onScreen = camera:WorldToViewportPoint(position)
				end
				local distance = onScreen and aimOrigin and (Vector2.new(point.X, point.Y) - aimOrigin).Magnitude or math.huge

				if distance < bestDistance then
					bestPart, bestPosition, bestDistance = part, position, distance
				end
			end
		end
	end

	return bestPart, bestPosition
end

function aimbotSettings.GetTargetPriorityScore(model, screenDistance)
	if aimbotSettings.TargetPriority == "Distance" then
		local localRoot = GetLocalRoot()
		local _, _, targetRoot = GetCharacterParts(model)
		return localRoot and targetRoot and (targetRoot.Position - localRoot.Position).Magnitude + (screenDistance * 0.001)
			or math.huge
	elseif aimbotSettings.TargetPriority == "Health" then
		local humanoid = model:FindFirstChildOfClass("Humanoid")
		return humanoid and humanoid.Health + (screenDistance * 0.001) or math.huge
	end

	return screenDistance
end

function aimbotSettings.GetBestTarget()
	camera = Workspace.CurrentCamera

	if not camera then
		return nil
	end

	local aimOrigin = GetAimbotScreenOrigin()

	if not aimOrigin then
		return nil
	end

	local bestPart, bestScreenPosition, bestModel, bestAimPosition = nil, nil, nil, nil
	local bestScore = math.huge

	for _, model in ipairs(GetTargets()) do
		local targetPart, aimPosition = GetAimbotTargetPoint(model)

		if targetPart and aimPosition then
			local screenPoint, onScreen = camera:WorldToViewportPoint(aimPosition)

			if onScreen and screenPoint.Z > 0 then
				local screenPosition = Vector2.new(screenPoint.X, screenPoint.Y)
				local screenDistance = (screenPosition - aimOrigin).Magnitude
				local score = aimbotSettings.GetTargetPriorityScore(model, screenDistance)

				if IsScreenPointInAimbotFOV(screenPosition) and score < bestScore then
					bestScore = score
					bestPart = targetPart
					bestScreenPosition = screenPosition
					bestModel = model
					bestAimPosition = aimPosition
				end
			end
		end
	end

	return bestPart, bestScreenPosition, bestModel, bestAimPosition
end

local function GetLockedAimbotTarget()
	camera = Workspace.CurrentCamera

	if not camera then
		aimbotSettings.LockedModel = nil
		aimbotSettings.MouseRemainder = Vector2.zero
		return nil
	end

	if aimbotSettings.StickyTarget and aimbotSettings.LockedModel then
		local targetPart, aimPosition = GetAimbotTargetPoint(aimbotSettings.LockedModel)

		if targetPart and aimPosition then
			local point, onScreen = camera:WorldToViewportPoint(aimPosition)

			if onScreen and point.Z > 0 then
				local screenPosition = Vector2.new(point.X, point.Y)

				if IsScreenPointInAimbotFOV(screenPosition, aimbotSettings.LockFOVMultiplier) then
					return targetPart, screenPosition, aimPosition
				end
			end
		end
	end

	aimbotSettings.LockedModel = nil
	aimbotSettings.MouseRemainder = Vector2.zero

	local targetPart, screenPosition, model, aimPosition = aimbotSettings.GetBestTarget()
	aimbotSettings.LockedModel = model
	return targetPart, screenPosition, aimPosition
end

local function MoveMouseTowardScreenPosition(screenPosition, deltaTime)
	camera = Workspace.CurrentCamera

	if not camera or not screenPosition then
		return false
	end

	local aimOrigin, topLeftInset = GetAimbotScreenOrigin()

	if not aimOrigin then
		return false
	end

	local rawDelta = screenPosition - aimOrigin

	if rawDelta.Magnitude <= aimbotSettings.MouseDeadzone then
		aimbotSettings.MouseRemainder = Vector2.zero
		return true
	end

	local baseResponse = math.clamp(aimbotSettings.Smoothness / 100, 0.01, 1)
	baseResponse = math.clamp(baseResponse + ((rawDelta.Magnitude / math.max(aimbotSettings.FOVRadius, 1)) * 0.18), 0.01, 1)
	local frameScale = math.clamp((tonumber(deltaTime) or (1 / 60)) * 60, 0.25, 3)
	local response = 1 - math.pow(1 - baseResponse, frameScale)
	local delta = (rawDelta * response) + aimbotSettings.MouseRemainder

	if delta.Magnitude > aimbotSettings.MouseMaxStep then
		delta = delta.Unit * aimbotSettings.MouseMaxStep
		aimbotSettings.MouseRemainder = Vector2.zero
	end

	local deltaX = delta.X >= 0 and math.floor(delta.X + 0.5) or math.ceil(delta.X - 0.5)
	local deltaY = delta.Y >= 0 and math.floor(delta.Y + 0.5) or math.ceil(delta.Y - 0.5)

	if deltaX == 0 and math.abs(rawDelta.X) > aimbotSettings.MouseDeadzone then
		deltaX = rawDelta.X > 0 and 1 or -1
	end

	if deltaY == 0 and math.abs(rawDelta.Y) > aimbotSettings.MouseDeadzone then
		deltaY = rawDelta.Y > 0 and 1 or -1
	end

	aimbotSettings.MouseRemainder = delta - Vector2.new(deltaX, deltaY)

	if
		UserInputService.MouseBehavior ~= Enum.MouseBehavior.LockCenter
		and typeof(mousemoveabs) == "function"
	then
		local nextPosition = rawDelta.Magnitude <= 2
			and (screenPosition + topLeftInset)
			or (aimOrigin + Vector2.new(deltaX, deltaY) + topLeftInset)

		if rawDelta.Magnitude <= 2 then
			aimbotSettings.MouseRemainder = Vector2.zero
		end

		return pcall(mousemoveabs, nextPosition.X, nextPosition.Y)
	end

	if typeof(mousemoverel) == "function" then
		return pcall(mousemoverel, deltaX, deltaY)
	end

	if typeof(mousemoveabs) == "function" then
		local nextPosition = aimOrigin + Vector2.new(deltaX, deltaY) + topLeftInset
		return pcall(mousemoveabs, nextPosition.X, nextPosition.Y)
	end

	return false
end

local function AimAtTarget(targetPart, aimPosition, deltaTime)
	camera = Workspace.CurrentCamera

	if not camera or not targetPart or not targetPart:IsDescendantOf(Workspace) then
		return
	end

	aimPosition = typeof(aimPosition) == "Vector3" and aimPosition or targetPart.Position

	if mouseAimbotEnabled then
		local point, onScreen = camera:WorldToViewportPoint(aimPosition)

		if not onScreen or point.Z <= 0 then
			return
		end

		local screenPosition = Vector2.new(point.X, point.Y)
		local aimOrigin = GetAimbotScreenOrigin()

		if
			aimOrigin
			and UserInputService.MouseBehavior == Enum.MouseBehavior.LockCenter
			and (screenPosition - aimOrigin).Magnitude <= 1.5
		then
			aimbotSettings.MouseRemainder = Vector2.zero
			camera.CFrame = CFrame.lookAt(camera.CFrame.Position, aimPosition)
			return
		end

		local movedMouse = MoveMouseTowardScreenPosition(screenPosition, deltaTime)

		if not movedMouse and not mouseAimbotWarningShown then
			mouseAimbotWarningShown = true
			Notify("Mouse Aimbot", "Mouse movement is not supported in this executor")
		end

		return
	end

	local position = camera.CFrame.Position
	local targetCFrame = CFrame.lookAt(position, aimPosition)
	local baseResponse = math.clamp(aimbotSettings.Smoothness / 100, 0.01, 1)
	local direction = aimPosition - position
	local angle = direction.Magnitude > 0.001 and math.acos(math.clamp(camera.CFrame.LookVector:Dot(direction.Unit), -1, 1)) or 0
	baseResponse = math.clamp(baseResponse + ((angle / math.pi) * 0.18), 0.01, 1)
	local frameScale = math.clamp((tonumber(deltaTime) or (1 / 60)) * 60, 0.25, 3)
	local response = 1 - math.pow(1 - baseResponse, frameScale)
	camera.CFrame = camera.CFrame:Lerp(targetCFrame, response)
end

local function ClickMouseOnce()
	if typeof(mouse1click) == "function" then
		return pcall(mouse1click)
	end

	if typeof(mouse1press) == "function" and typeof(mouse1release) == "function" then
		local pressed = pcall(mouse1press)

		if pressed then
			task.delay(0.02, function()
				pcall(mouse1release)
			end)
		end

		return pressed
	end

	return false
end

local function UpdateTriggerbot()
	if
		not triggerbotEnabled
		or UserInputService:GetFocusedTextBox()
		or (triggerbotSettings.HoldBind and not aimbotBindHeld)
	then
		triggerbotSettings.Target = nil
		return
	end

	local now = os.clock()
	camera = Workspace.CurrentCamera

	if not camera then
		triggerbotSettings.Target = nil
		return
	end

	local character = localPlayer.Character
	local center = camera.ViewportSize / 2
	local ray = camera:ViewportPointToRay(center.X, center.Y)
	local ignoreList = { camera }

	if character then
		table.insert(ignoreList, character)
	end

	triggerbotRaycastParams.FilterDescendantsInstances = ignoreList

	local result = Workspace:Raycast(ray.Origin, ray.Direction * 10000, triggerbotRaycastParams)
	local model = result and GetCharacterFromPart(result.Instance)

	if not model or not aimbotSettings.IsEligibleCombatTarget(model) then
		triggerbotSettings.Target = nil
		return
	end
	if triggerbotSettings.Target ~= model then
		triggerbotSettings.Target = model
		triggerbotSettings.TargetSince = now
	end
	if
		now - triggerbotSettings.TargetSince < triggerbotSettings.ReactionDelay
		or now - triggerbotSettings.LastShot < triggerbotSettings.Delay
	then
		return
	end

	triggerbotSettings.LastShot = now

	if not ClickMouseOnce() and not triggerbotSettings.WarningShown then
		triggerbotSettings.WarningShown = true
		Notify("Triggerbot", "Mouse clicking is not supported in this executor")
	end
end

local function WatchPlayer(player)
	TrackConnection(player.CharacterAdded:Connect(function(character)
		local humanoid = character:WaitForChild("Humanoid", 5)
		character:WaitForChild("Head", 5)

		if isUnloaded then
			return
		end

		if player == localPlayer then
			RestoreNoclipCollisions()
			DestroyFlyMovers()

			if desiredWalkSpeed and humanoid then
				SetWalkSpeed(desiredWalkSpeed)
			end

			return
		end

		RegisterTarget(character)

		if espEnabled then
			CreateESP(character)
		end
	end))
end

function config.BuildText()
	local values = {}

	for flag, option in pairs(ui.native.options or {}) do
		if option.class == "toggle" then
			values[flag] = option.state and 1 or 0
		elseif option.class == "slider" then
			values[flag] = option.value
		elseif option.class == "box" then
			values[flag] = option.input
		elseif option.class == "color" then
			values[flag] = { option.color.R, option.color.G, option.color.B, option.trans }
		elseif option.class == "list" then
			values[flag] = option.selected
		elseif option.class == "bind" and option.bind then
			values[flag] = option.bind.Name
		end
	end

	return config.Http:JSONEncode({ version = 1, values = values })
end

function config.ApplyText(text, silent)
	local decoded
	local succeeded, configError = pcall(function()
		decoded = config.Http:JSONDecode(text)
	end)

	if not succeeded or typeof(decoded) ~= "table" or typeof(decoded.values) ~= "table" then
		if not silent then
			Notify("Config", "Invalid config: " .. tostring(configError or "missing values"))
		end
		return false
	end

	local loaded = 0
	for flag, value in pairs(decoded.values) do
		local option = ui.native.options and ui.native.options[flag]
		if option then
			local applied = pcall(function()
				if option.class == "toggle" then
					option:SetState(value == 1 or value == true)
				elseif option.class == "slider" then
					option:SetValue(value)
				elseif option.class == "box" then
					option:SetInput(value)
				elseif option.class == "color" then
					option:SetColor(Color3.new(value[1], value[2], value[3]))
					option:SetTrans(value[4] == nil and 1 or value[4])
				elseif option.class == "list" then
					option:Select(value)
				end
			end)
			loaded += applied and 1 or 0
		end
	end

	if not silent then
		Notify("Config", string.format("Loaded %d settings", loaded))
	end
	return true
end

function config.Save()
	local text = config.BuildText()
	if runtimeEnvironment then
		runtimeEnvironment[config.CacheKey] = text
	end

	local saved = typeof(writefile) == "function" and pcall(writefile, config.Path, text)
	if saved then
		Notify("Config", "Saved to " .. config.Path)
	elseif typeof(setclipboard) == "function" and pcall(setclipboard, text) then
		Notify("Config", "File access unavailable; copied config JSON")
	else
		Notify("Config", "Saved for this executor session")
	end
end

function config.Load(silent)
	local text = runtimeEnvironment and runtimeEnvironment[config.CacheKey]
	if typeof(isfile) == "function" and typeof(readfile) == "function" then
		local exists, hasFile = pcall(isfile, config.Path)
		if exists and hasFile then
			local readSucceeded, fileText = pcall(readfile, config.Path)
			text = readSucceeded and fileText or text
		end
	end
	if (typeof(text) ~= "string" or text == "") and typeof(getclipboard) == "function" then
		local clipboardSucceeded, clipboardText = pcall(getclipboard)
		text = clipboardSucceeded and clipboardText or text
	end

	if typeof(text) ~= "string" or text == "" then
		if not silent then
			Notify("Config", "No saved config found")
		end
		return false
	end

	return config.ApplyText(text, silent)
end

function config.Copy()
	if typeof(setclipboard) == "function" and pcall(setclipboard, config.BuildText()) then
		Notify("Config", "Copied config JSON")
	else
		Notify("Config", "Clipboard access is unavailable")
	end
end

local function Unload(skipUIDestroy)
	if isUnloaded then
		return
	end

	PrintLoad("unloading")
	isUnloaded = true
	aimbotEnabled = false
	mouseAimbotEnabled = false
	aimbotBindHeld = false
	aimbotSettings.LockedModel = nil
	aimbotSettings.MouseRemainder = Vector2.zero
	triggerbotEnabled = false
	triggerbotSettings.Target = nil
	clickTeleportEnabled = false
	antiAFKEnabled = false
	crosshairEnabled = false
	adsHeld = false

	SetFullbright(false)
	SetTerrainGrassDisabled(false)
	SetNoclip(false)
	SetInfiniteJump(false)
	SetFly(false)
	RestorePlayerSettings()
	SetESP(false)
	radar.SetEnabled(false)
	DisconnectAllConnections()

	table.clear(targetModels)
	aimbotFOVCircle.Visible = false

	if runtimeEnvironment and runtimeEnvironment[RUNTIME_UNLOAD_KEY] == Unload then
		runtimeEnvironment[RUNTIME_UNLOAD_KEY] = nil
	end

	if espGui.Parent then
		espGui:Destroy()
	end

	if not skipUIDestroy then
		pcall(function()
			ui.destroy(true)
		end)
	end

	PrintLoad("unloaded")
end

ui:bindToEvent("onPreDestroy", function()
	Unload(true)
end)

if runtimeEnvironment then
	runtimeEnvironment[RUNTIME_UNLOAD_KEY] = Unload
end

PrintLoad("feature systems ready")

-- Interface ------------------------------------------------------------------

local function BuildInterface()
	local window = ui.newWindow({
		text = "rat.lua",
		resize = true,
		size = Vector2.new(560, 380),
		position = nil,
	})

	local combatMenu = window:addMenu({
		text = "Combat",
	})

	local visualsMenu = window:addMenu({
		text = "Visuals",
	})

	local playerMenu = window:addMenu({
		text = "Player",
	})

	local settingsMenu = window:addMenu({
		text = "Settings",
	})

	local aimbotSection = combatMenu:addSection({
		text = "Aimbot",
		side = "left",
		showMinButton = false,
	})

	aimbotBindLabel = aimbotSection:addLabel({
		text = "Hold " .. GetBindName() .. " while enabled",
	})

	aimbotSection
		:addToggle({
			text = "Aimbot",
			state = false,
		})
		:bindToEvent("onToggle", function(newState)
			aimbotEnabled = newState

			if not aimbotEnabled then
				aimbotSettings.LockedModel = nil
				aimbotSettings.MouseRemainder = Vector2.zero
				aimbotBindHeld = false
			end
		end)

	wallCheckToggle = aimbotSection:addToggle({
		text = "Wallcheck",
		state = true,
	})

	wallCheckToggle:bindToEvent("onToggle", function(newState)
		SetWallCheck(newState, false)
	end)

	aimbotSection
		:addToggle({
			text = "Team Check",
			state = false,
		})
		:bindToEvent("onToggle", function(newState)
			aimbotTeamCheckEnabled = newState
		end)
		:setTooltip("Aimbot and triggerbot ignore players on your team.")

	aimbotSection
		:addToggle({
			text = "Mouse Aimbot",
			state = false,
		})
		:bindToEvent("onToggle", function(newState)
			mouseAimbotEnabled = newState
			aimbotSettings.LockedModel = nil
			aimbotSettings.MouseRemainder = Vector2.zero
		end)
		:setTooltip("Uses center aim while the mouse is locked and real cursor position otherwise.")

	aimbotSection
		:addSlider({
			text = "Smoothness",
			min = 1,
			max = 100,
			step = 1,
			value = aimbotSettings.Smoothness,
		}, function(newValue)
			aimbotSettings.Smoothness = math.clamp(tonumber(newValue) or aimbotSettings.Smoothness, 1, 100)
			aimbotSettings.MouseRemainder = Vector2.zero
		end)
		:setTooltip("Frame-rate independent response. 55 is balanced; lower is smoother and higher is faster.")

	aimbotSection
		:addSlider({
			text = "FOV Radius",
			min = 25,
			max = 500,
			step = 5,
			value = aimbotSettings.FOVRadius,
		}, function(newValue)
			aimbotSettings.FOVRadius = tonumber(newValue) or aimbotSettings.FOVRadius
			UpdateAimbotFOVCircle()
		end)
		:setTooltip("Targets must be inside the circle, inside ESP distance, and visible when wallcheck is on.")

	aimbotSection
		:addTextbox({
			text = "Hold Bind",
			value = GetBindName(),
		})
		:bindToEvent("onFocusLost", function(text)
			SetAimbotBindFromText(text)
		end)

	aimbotSection
		:addTextbox({
			text = "Wallcheck Hotkey",
			value = "none",
		})
		:bindToEvent("onFocusLost", function(text)
			SetWallCheckHotkeyFromText(text)
		end)

	local aimTuningSection = combatMenu:addSection({
		text = "Aim Tuning",
		side = "left",
		showMinButton = false,
	})

	aimTuningSection
		:addTextbox({
			text = "Aim Part",
			value = aimbotSettings.AimPart,
		})
		:bindToEvent("onFocusLost", aimbotSettings.SetAimPartFromText)
		:setTooltip("Head, Torso, Root, or Closest. Closest chooses the nearest visible body point.")

	aimTuningSection
		:addTextbox({
			text = "Target Priority",
			value = aimbotSettings.TargetPriority,
		})
		:bindToEvent("onFocusLost", aimbotSettings.SetTargetPriorityFromText)
		:setTooltip("Cursor, Distance, or Health.")

	aimTuningSection
		:addToggle({
			text = "Sticky Target",
			state = true,
		})
		:bindToEvent("onToggle", function(newState)
			aimbotSettings.StickyTarget = newState
			aimbotSettings.LockedModel = nil
		end)

	aimTuningSection
		:addToggle({
			text = "Velocity Prediction",
			state = false,
		})
		:bindToEvent("onToggle", function(newState)
			aimbotSettings.PredictionEnabled = newState
		end)

	aimTuningSection
		:addSlider({
			text = "Prediction Time",
			min = 0,
			max = 0.3,
			step = 0.01,
			value = aimbotSettings.PredictionTime,
		}, function(newValue)
			aimbotSettings.PredictionTime = math.clamp(tonumber(newValue) or 0.12, 0, 0.3)
		end)
		:setTooltip("Leads moving targets by this many seconds.")

	aimTuningSection
		:addToggle({
			text = "Target HUD",
			state = true,
		})
		:bindToEvent("onToggle", function(newState)
			aimbotSettings.TargetHudEnabled = newState
			if not newState then
				aimbotSettings.TargetHud.Visible = false
			end
		end)

	local exclusionsSection = combatMenu:addSection({
		text = "Exclusions",
		side = "right",
		showMinButton = false,
	})

	exclusionsSection
		:addTextbox({
			text = "Excluded Players",
		})
		:bindToEvent("onFocusLost", function(text)
			SetAimbotExclusionsFromText(text)
		end)

	exclusionsLabel = exclusionsSection:addLabel({
		text = "Excluded: none",
		dim = true,
	})

	exclusionsSection:addButton({
		text = "Clear Exclusions",
		style = "small",
	}, function()
		ClearAimbotExclusions()
	end)

	local triggerbotSection = combatMenu:addSection({
		text = "Triggerbot",
		side = "right",
		showMinButton = false,
	})

	triggerbotSection
		:addToggle({
			text = "Triggerbot",
			state = false,
		})
		:bindToEvent("onToggle", function(newState)
			triggerbotEnabled = newState
			triggerbotSettings.LastShot = 0
			triggerbotSettings.Target = nil
		end)

	triggerbotSection
		:addSlider({
			text = "Shot Delay",
			min = 0.02,
			max = 0.5,
			step = 0.01,
			value = triggerbotSettings.Delay,
		}, function(newValue)
			triggerbotSettings.Delay = tonumber(newValue) or triggerbotSettings.Delay
		end)
		:setTooltip("Delay between automatic shots while an eligible target is under the crosshair.")

	triggerbotSection
		:addToggle({
			text = "Require Aim Bind",
			state = false,
		})
		:bindToEvent("onToggle", function(newState)
			triggerbotSettings.HoldBind = newState
			triggerbotSettings.Target = nil
		end)
		:setTooltip("Only fires while the configured aimbot hold bind is pressed.")

	triggerbotSection
		:addSlider({
			text = "Reaction Delay",
			min = 0,
			max = 0.25,
			step = 0.01,
			value = triggerbotSettings.ReactionDelay,
		}, function(newValue)
			triggerbotSettings.ReactionDelay = math.clamp(tonumber(newValue) or 0.03, 0, 0.25)
		end)
		:setTooltip("Waits for the crosshair to remain on the same target before firing.")

	local espSection = visualsMenu:addSection({
		text = "ESP",
		side = "left",
		showMinButton = false,
	})

	espSection
		:addToggle({
			text = "ESP",
			state = false,
		})
		:bindToEvent("onToggle", function(newState)
			SetESP(newState)
		end)

	espSection
		:addToggle({
			text = "Name",
			state = true,
		})
		:bindToEvent("onToggle", function(newState)
			espNameEnabled = newState

			if espEnabled then
				RefreshESP()
			end
		end)

	espSection
		:addToggle({
			text = "Info",
			state = true,
		})
		:bindToEvent("onToggle", function(newState)
			espInfoEnabled = newState

			if espEnabled then
				RefreshESP()
			end
		end)

	espSection
		:addToggle({
			text = "Boxes",
			state = true,
		})
		:bindToEvent("onToggle", function(newState)
			visualSettings.Boxes = newState

			if espEnabled then
				RefreshESP()
			end
		end)

	espSection
		:addToggle({
			text = "Health Bars",
			state = true,
		})
		:bindToEvent("onToggle", function(newState)
			visualSettings.HealthBars = newState

			if espEnabled then
				RefreshESP()
			end
		end)

	espSection
		:addToggle({
			text = "Tracers",
			state = true,
		})
		:bindToEvent("onToggle", function(newState)
			espTracersEnabled = newState

			if not espTracersEnabled then
				for _, drawing in pairs(espDrawings) do
					drawing.tracer.Visible = false
				end
			end
		end)

	espSection
		:addToggle({
			text = "Bones",
			state = false,
		})
		:bindToEvent("onToggle", function(newState)
			espBonesEnabled = newState

			if not espBonesEnabled then
				for _, drawing in pairs(espDrawings) do
					for _, line in pairs(drawing.bones) do
						line.Visible = false
					end
				end
			end
		end)

	local espSettingsSection = visualsMenu:addSection({
		text = "ESP Settings",
		side = "right",
		showMinButton = false,
	})

	espSettingsSection
		:addToggle({
			text = "Team Color",
			state = true,
		})
		:bindToEvent("onToggle", function(newState)
			espTeamColorEnabled = newState

			if espEnabled then
				RefreshESP()
			end
		end)

	espSettingsSection:addColorPicker({
		text = "ESP Color",
		color = espColor,
	}, function(newColor)
		espColor = newColor

		if espEnabled then
			RefreshESP()
		end
	end)

	espSettingsSection:addColorPicker({
		text = "Excluded Color",
		color = espExcludedColor,
	}, function(newColor)
		espExcludedColor = newColor

		if espEnabled then
			RefreshESP()
		end
	end)

	espSettingsSection
		:addSlider({
			text = "Tracer Distance",
			min = 10,
			max = 500,
			step = 10,
			value = TRACER_DISTANCE,
		}, function(newValue)
			TRACER_DISTANCE = tonumber(newValue) or TRACER_DISTANCE
		end)
		:setTooltip("Tracers only draw within this many studs.")

	espSettingsSection
		:addToggle({
			text = "Uncapped Distance",
			state = true,
		})
		:bindToEvent("onToggle", function(newState)
			ESP_DISTANCE_UNCAPPED = newState

			if espEnabled then
				RefreshESP()
			end
		end)

	espSettingsSection
		:addSlider({
			text = "ESP Distance",
			min = 100,
			max = 10000,
			step = 50,
			value = ESP_DISTANCE_CAP,
		}, function(newValue)
			ESP_DISTANCE_CAP = tonumber(newValue) or ESP_DISTANCE_CAP

			if espEnabled then
				RefreshESP()
			end
		end)
		:setTooltip("Used when uncapped distance is off. This also limits aimbot and triggerbot targets.")

	local radarSection = visualsMenu:addSection({
		text = "Radar",
		side = "right",
		showMinButton = false,
	})

	radarSection
		:addToggle({
			text = "Radar",
			state = false,
		})
		:bindToEvent("onToggle", function(newState)
			radar.SetEnabled(newState)
		end)
		:setTooltip("Rotates with your character and shows nearby registered targets.")

	radarSection
		:addSlider({
			text = "Radar Range",
			min = 50,
			max = 2000,
			step = 50,
			value = radar.Range,
		}, function(newValue)
			radar.Range = math.clamp(tonumber(newValue) or radar.Range, 50, 2000)
			radar.Update()
		end)
		:setTooltip("Maximum radar distance in studs.")

	radarSection
		:addSlider({
			text = "Radar Size",
			min = 140,
			max = 260,
			step = 10,
			value = radar.Size,
		}, function(newValue)
			radar.SetSize(newValue)
		end)
		:setTooltip("Changes the radar size while keeping it inside the screen.")

	radarSection:addButton({
		text = "Reset Radar Position",
		style = "small",
	}, function()
		radar.ResetPosition()
	end)

	local lightingSection = visualsMenu:addSection({
		text = "Lighting",
		side = "right",
		showMinButton = false,
	})

	lightingSection
		:addToggle({
			text = "Fullbright",
			state = false,
		})
		:bindToEvent("onToggle", function(newState)
			SetFullbright(newState)
		end)

	lightingSection
		:addToggle({
			text = "Disable Terrain Grass",
			state = false,
		})
		:bindToEvent("onToggle", function(newState)
			SetTerrainGrassDisabled(newState)
		end)

	local crosshairSection = visualsMenu:addSection({
		text = "Crosshair",
		side = "left",
		showMinButton = false,
	})

	crosshairSection
		:addToggle({
			text = "Crosshair",
			state = false,
		})
		:bindToEvent("onToggle", function(newState)
			crosshairEnabled = newState
			UpdateCrosshair()
		end)

	crosshairSection:addColorPicker({
		text = "Crosshair Color",
		color = crosshairColor,
	}, function(newColor)
		crosshairColor = newColor
		UpdateCrosshair()
	end)

	crosshairSection
		:addSlider({
			text = "Crosshair Size",
			min = 2,
			max = 30,
			step = 1,
			value = CROSSHAIR_SIZE,
		}, function(newValue)
			CROSSHAIR_SIZE = tonumber(newValue) or CROSSHAIR_SIZE
			UpdateCrosshair()
		end)
		:setTooltip("Length of each crosshair arm in pixels.")

	local movementSection = playerMenu:addSection({
		text = "Movement",
		side = "left",
		showMinButton = false,
	})

	movementSection
		:addTextbox({
			text = "Walkspeed",
		})
		:bindToEvent("onFocusLost", function(text)
			if not SetWalkSpeed(text) then
				Notify("Invalid Walkspeed", "Enter a number from 0 to 500")
			end
		end)

	movementSection
		:addSlider({
			text = "FOV",
			min = 40,
			max = 120,
			step = 1,
			value = playerFov,
		}, function(newValue)
			setPlayerFov(newValue)
		end)
		:setTooltip("Changes your camera field of view.")

	movementSection
		:addToggle({
			text = "Respect ADS FOV",
			state = true,
		})
		:bindToEvent("onToggle", function(newState)
			respectAdsFov = newState
			setPlayerFov(playerFov)
		end)
		:setTooltip("Lets the game control camera zoom while holding right-click to ADS.")

	movementSection
		:addToggle({
			text = "Noclip",
			state = false,
		})
		:bindToEvent("onToggle", function(newState)
			SetNoclip(newState)
		end)

	movementSection
		:addToggle({
			text = "Infinite Jump",
			state = false,
		})
		:bindToEvent("onToggle", function(newState)
			SetInfiniteJump(newState)
		end)

	local flightSection = playerMenu:addSection({
		text = "Flight & Teleport",
		side = "right",
		showMinButton = false,
	})

	flightSection
		:addToggle({
			text = "Fly",
			state = false,
		})
		:bindToEvent("onToggle", function(newState)
			SetFly(newState)
		end)

	flightSection
		:addSlider({
			text = "Fly Speed",
			min = 10,
			max = 250,
			step = 5,
			value = FLY_SPEED,
		}, function(newValue)
			FLY_SPEED = tonumber(newValue) or FLY_SPEED
		end)
		:setTooltip("WASD to move, Space to rise, and Ctrl to descend.")

	flightSection
		:addToggle({
			text = "Ctrl-Click Teleport",
			state = false,
		})
		:bindToEvent("onToggle", function(newState)
			clickTeleportEnabled = newState
		end)
		:setTooltip("Hold either Ctrl key and left-click a visible surface.")

	local interfaceSection = settingsMenu:addSection({
		text = "Interface",
		side = "left",
		showMinButton = false,
	})

	interfaceSection:addButton({
		text = "Unload",
		style = "large",
	}, Unload)

	local configSection = settingsMenu:addSection({
		text = "Config",
		side = "left",
		showMinButton = false,
	})

	configSection:addButton({
		text = "Save Config",
		style = "small",
	}, config.Save)

	configSection:addButton({
		text = "Load Config",
		style = "small",
	}, function()
		config.Load(false)
	end)

	configSection:addButton({
		text = "Copy Config JSON",
		style = "small",
	}, config.Copy)

	local utilitySection = settingsMenu:addSection({
		text = "Utility",
		side = "right",
		showMinButton = false,
	})

	utilitySection
		:addToggle({
			text = "Anti-AFK",
			state = false,
		})
		:bindToEvent("onToggle", function(newState)
			antiAFKEnabled = newState
		end)
		:setTooltip("Sends a small virtual input when Roblox marks the player as idle.")

	PrintLoad("interface built")
end

BuildInterface()
PrintLoad(config.Load(true) and "saved config loaded" or "no saved config found")

-- Runtime --------------------------------------------------------------------

RegisterExistingTargets()

for _, player in ipairs(Players:GetPlayers()) do
	WatchPlayer(player)
end

PrintLoad("existing players registered")

TrackConnection(Players.PlayerAdded:Connect(function(player)
	WatchPlayer(player)

	if player ~= localPlayer then
		Notify("Player Joined", player.Name .. " joined the game")
	end
end))

TrackConnection(Players.PlayerRemoving:Connect(function(player)
	if player ~= localPlayer then
		Notify("Player Left", player.Name .. " left the game")
	end

	if player.Character then
		if triggerbotSettings.Target == player.Character then
			triggerbotSettings.Target = nil
		end
		RemoveESP(player.Character)
		radar.RemoveDot(player.Character)
		targetModels[player.Character] = nil
	end
end))

TrackConnection(Workspace.DescendantAdded:Connect(function(instance)
	if not instance:IsA("Humanoid") and instance.Name ~= "Head" then
		return
	end

	task.defer(function()
		if isUnloaded then
			return
		end

		RegisterTargetFromInstance(instance)

		local model = instance:FindFirstAncestorOfClass("Model")

		if espEnabled and model and targetModels[model] then
			CreateESP(model)
		end
	end)
end))

TrackConnection(Workspace.DescendantRemoving:Connect(function(instance)
	local model = nil

	if instance:IsA("Model") then
		model = instance
	elseif instance:IsA("Humanoid") or instance.Name == "Head" then
		model = instance:FindFirstAncestorOfClass("Model")
	end

	if model and targetModels[model] then
		if aimbotSettings.LockedModel == model then
			aimbotSettings.LockedModel = nil
			aimbotSettings.MouseRemainder = Vector2.zero
		end
		if triggerbotSettings.Target == model then
			triggerbotSettings.Target = nil
		end

		RemoveESP(model)
		radar.RemoveDot(model)
		targetModels[model] = nil
	end
end))

TrackConnection(Lighting.ChildAdded:Connect(function(instance)
	if fullbrightEnabled then
		DisableLightingEffect(instance)
	end
end))

TrackConnection(radar.Frame.InputBegan:Connect(function(input)
	radar.BeginDrag(input)
end))

TrackConnection(radar.Frame.InputEnded:Connect(function(input)
	radar.EndDrag(input)
end))

TrackConnection(UserInputService.InputChanged:Connect(function(input)
	radar.UpdateDrag(input)
end))

TrackConnection(UserInputService.InputBegan:Connect(function(input, gameProcessedEvent)
	if UserInputService:GetFocusedTextBox() then
		return
	end
	if input.UserInputType == Enum.UserInputType.MouseButton2 then
		adsHeld = true
	end

	if
		clickTeleportEnabled
		and not gameProcessedEvent
		and input.UserInputType == Enum.UserInputType.MouseButton1
		and (
			UserInputService:IsKeyDown(Enum.KeyCode.LeftControl)
			or UserInputService:IsKeyDown(Enum.KeyCode.RightControl)
		)
	then
		TeleportToCursor()
		return
	end

	if IsWallCheckHotkey(input) then
		ToggleWallCheckFromHotkey()
	end

	if IsAimbotBind(input) then
		aimbotBindHeld = true
	end
end))

TrackConnection(UserInputService.InputEnded:Connect(function(input)
	radar.EndDrag(input)
	if input.UserInputType == Enum.UserInputType.MouseButton2 then
		adsHeld = false
		setPlayerFov(playerFov)
	end

	if IsAimbotBind(input) then
		aimbotBindHeld = false
		aimbotSettings.LockedModel = nil
		aimbotSettings.MouseRemainder = Vector2.zero
	end
end))

TrackConnection(UserInputService.JumpRequest:Connect(function()
	if not infiniteJumpEnabled then
		return
	end

	local character = localPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")

	if humanoid and humanoid.Health > 0 then
		humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
	end
end))

TrackConnection(localPlayer.Idled:Connect(function()
	if not antiAFKEnabled or isUnloaded then
		return
	end

	pcall(function()
		VirtualUser:CaptureController()
		VirtualUser:ClickButton2(Vector2.zero)
	end)
end))

TrackConnection(RunService.RenderStepped:Connect(function(deltaTime)
	if isUnloaded then
		return
	end

	UpdateAimbotFOVCircle()
	UpdateCrosshair()
	MaintainFullbright()

	camera = Workspace.CurrentCamera

	if camera and (not respectAdsFov or not adsHeld) then
		originalCameraFOVs[camera] = originalCameraFOVs[camera] or camera.FieldOfView
		if camera.FieldOfView ~= playerFov then
			camera.FieldOfView = playerFov
		end
	end

	UpdateNoclip()
	UpdateFly()

	environmentUpdateAccumulator += deltaTime

	if environmentUpdateAccumulator >= ENVIRONMENT_UPDATE_INTERVAL then
		environmentUpdateAccumulator %= ENVIRONMENT_UPDATE_INTERVAL
		ApplyTerrainGrass()
	end

	if aimbotEnabled and aimbotBindHeld then
		local targetPart, _, aimPosition = GetLockedAimbotTarget()

		if targetPart then
			AimAtTarget(targetPart, aimPosition, deltaTime)
		end
	else
		aimbotSettings.LockedModel = nil
		aimbotSettings.MouseRemainder = Vector2.zero
	end
	aimbotSettings.UpdateTargetHud()

	UpdateTriggerbot()

	if espEnabled or radar.Enabled then
		visualSettings.UpdateAccumulator += deltaTime

		if visualSettings.UpdateAccumulator >= visualSettings.UpdateInterval then
			visualSettings.UpdateAccumulator %= visualSettings.UpdateInterval

			if espEnabled then
				UpdateESPVisuals()
			end

			if radar.Enabled then
				radar.Update()
			end
		end
	else
		visualSettings.UpdateAccumulator = 0
	end

	if espEnabled then
		visualSettings.RefreshAccumulator += deltaTime

		if visualSettings.RefreshAccumulator >= visualSettings.RefreshInterval then
			visualSettings.RefreshAccumulator %= visualSettings.RefreshInterval
			RefreshESP()
		end
	else
		visualSettings.RefreshAccumulator = 0
	end
end))

PrintLoad("ready")
