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

local UI_LIBRARY_URL = "https://raw.githubusercontent.com/topitbopit/dollarware/main/library.lua"
local ESP_HIGHLIGHT_NAME = "RatESPHighlight"
local ESP_INFO_NAME = "RatESPInfo"
local ESP_UPDATE_INTERVAL = 1 / 60
local ENVIRONMENT_UPDATE_INTERVAL = 0.25
local DEFAULT_FOV = 70

local windowThemes = {
	"cherry",
	"orange",
	"lemon",
	"lime",
	"raspberry",
	"blueberry",
	"grape",
	"watermelon",
}

PrintLoad("downloading ui library")

local downloadSucceeded, uiSource = pcall(function()
	return game:HttpGet(UI_LIBRARY_URL, true)
end)

assert(downloadSucceeded, "[rat.lua] failed to download ui library: " .. tostring(uiSource))

local uiLoader, uiLoadError = loadstring(uiSource)

assert(uiLoader, "[rat.lua] failed to compile ui library: " .. tostring(uiLoadError))
PrintLoad("ui library downloaded")

local ui = uiLoader({
	rounding = false,
	theme = windowThemes[math.random(1, #windowThemes)],
	smoothDragging = true,
})

ui.autoDisableToggles = true
PrintLoad("ui library initialized")

-- Runtime state ---------------------------------------------------------------

local localPlayer = Players.LocalPlayer
local camera = Workspace.CurrentCamera

local espEnabled = false
local espNameEnabled = true
local espInfoEnabled = true
local espTracersEnabled = true
local espBonesEnabled = true
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
local aimbotBindHeld = false
local aimbotBindType = Enum.UserInputType.MouseButton2
local aimbotBindKey = nil
local wallCheckHotkeyType = nil
local wallCheckHotkeyKey = nil
local desiredWalkSpeed = nil

local aimbotSettings = {
	Smoothness = 55,
	FOVRadius = 150,
	MouseDeadzone = 1.25,
	MouseMaxStep = 90,
	MouseRemainder = Vector2.zero,
}
local visualSettings = {
	Boxes = true,
	HealthBars = true,
}
local radar = {
	Enabled = false,
	Range = 500,
	Dots = {},
}
local TRIGGERBOT_DELAY = 0.1
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
local PLAYER_FOV = camera and camera.FieldOfView or DEFAULT_FOV
local espUpdateAccumulator = 0
local environmentUpdateAccumulator = 0
local mouseAimbotWarningShown = false
local triggerbotWarningShown = false
local lastTriggerbotShot = 0
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

radar.Frame = Instance.new("Frame")
radar.Frame.Name = "Radar"
radar.Frame.AnchorPoint = Vector2.new(1, 1)
radar.Frame.Position = UDim2.new(1, -24, 1, -24)
radar.Frame.Size = UDim2.fromOffset(170, 170)
radar.Frame.BackgroundColor3 = Color3.fromRGB(12, 12, 16)
radar.Frame.BackgroundTransparency = 0.2
radar.Frame.BorderSizePixel = 0
radar.Frame.ClipsDescendants = true
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
		return false
	end

	local ignoreList = { camera }
	local obscuringIgnoreList = { camera, model }

	if localPlayer.Character then
		table.insert(ignoreList, localPlayer.Character)
		table.insert(obscuringIgnoreList, localPlayer.Character)
	end

	wallCheckRaycastParams.FilterDescendantsInstances = ignoreList

	local origin = camera.CFrame.Position
	local direction = targetPart.Position - origin

	if direction.Magnitude <= 0.001 then
		return true
	end

	local obscuringSucceeded, obscuringParts = pcall(function()
		return camera:GetPartsObscuringTarget({ targetPart.Position }, obscuringIgnoreList)
	end)

	if obscuringSucceeded then
		for _, part in ipairs(obscuringParts) do
			if part:IsA("BasePart") and part.Transparency < 0.95 and part.LocalTransparencyModifier < 0.95 then
				return false
			end
		end
	end

	local result = Workspace:Raycast(origin, direction, wallCheckRaycastParams)

	return not result or GetCharacterFromPart(result.Instance) == model
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
		radar.Update()
	else
		radar.Clear()
	end
end

function radar.Update()
	if not radar.Enabled then
		return
	end

	local localRoot = GetLocalRoot()

	if not localRoot then
		radar.Clear()
		return
	end

	local activeModels = {}
	local center = radar.Frame.AbsoluteSize / 2
	local radius = math.max(1, math.min(center.X, center.Y) - 9)

	for _, model in ipairs(GetTargets()) do
		local humanoid, _, root = GetCharacterParts(model)

		if humanoid and humanoid.Health > 0 and root then
			local worldOffset = root.Position - localRoot.Position
			local localOffset = localRoot.CFrame:VectorToObjectSpace(worldOffset)
			local mapOffset = Vector2.new(localOffset.X, localOffset.Z)

			if mapOffset.Magnitude <= radar.Range then
				local dot = radar.Dots[model]

				if not dot then
					dot = Instance.new("Frame")
					dot.Name = "Target"
					dot.AnchorPoint = Vector2.new(0.5, 0.5)
					dot.Size = UDim2.fromOffset(7, 7)
					dot.BorderSizePixel = 0
					dot.ZIndex = 107
					dot.Parent = radar.Frame

					local corner = Instance.new("UICorner")
					corner.CornerRadius = UDim.new(1, 0)
					corner.Parent = dot
					radar.Dots[model] = dot
				end

				local scaledOffset = mapOffset * (radius / math.max(radar.Range, 1))
				dot.Position = UDim2.fromOffset(center.X + scaledOffset.X, center.Y + scaledOffset.Y)
				dot.BackgroundColor3 = GetESPColor(model)
				dot.Visible = true
				activeModels[model] = true
			end
		end
	end

	for model in pairs(radar.Dots) do
		if not activeModels[model] then
			radar.RemoveDot(model)
		end
	end

	radar.Label.Text = "radar | " .. math.floor(radar.Range) .. " studs"
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

local function IsWithinESPDistance(model)
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
			UpdateESPLabel(model)
			UpdateESPDrawings(model)
		else
			RemoveESP(model)
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

local function SetPlayerFOV(value)
	PLAYER_FOV = math.clamp(tonumber(value) or PLAYER_FOV, 40, 120)
	camera = Workspace.CurrentCamera

	if camera then
		if originalCameraFOVs[camera] == nil then
			originalCameraFOVs[camera] = camera.FieldOfView
		end

		camera.FieldOfView = PLAYER_FOV
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
			if wallCheckEnabled and typeof(wallCheckToggle.enable) == "function" then
				wallCheckToggle:enable()
			elseif not wallCheckEnabled and typeof(wallCheckToggle.disable) == "function" then
				wallCheckToggle:disable()
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

local function IsScreenPointInAimbotFOV(screenPosition)
	local aimOrigin = GetAimbotScreenOrigin()

	if not aimOrigin then
		return false
	end

	return (screenPosition - aimOrigin).Magnitude <= aimbotSettings.FOVRadius
end

local function IsSameTeam(model)
	if not aimbotTeamCheckEnabled or not localPlayer.Team then
		return false
	end

	local player = Players:GetPlayerFromCharacter(model)
	return player ~= nil and player.Team == localPlayer.Team
end

local function IsValidAimbotTarget(model)
	if not IsTargetModel(model) then
		return false
	end

	if not IsWithinESPDistance(model) then
		return false
	end

	if espEnabled and not model:FindFirstChild(ESP_HIGHLIGHT_NAME) then
		return false
	end

	if IsAimbotExcluded(model) then
		return false
	end

	if IsSameTeam(model) then
		return false
	end

	local _, head = GetCharacterParts(model)
	return not wallCheckEnabled or HasWallCheck(model, head)
end

local function GetClosestHeadToCrosshair()
	camera = Workspace.CurrentCamera

	if not camera then
		return nil
	end

	local aimOrigin = GetAimbotScreenOrigin()

	if not aimOrigin then
		return nil
	end

	local closestHead = nil
	local closestScreenPosition = nil
	local closestModel = nil
	local closestDistance = math.huge

	for _, model in ipairs(GetTargets()) do
		if IsValidAimbotTarget(model) then
			local head = model:FindFirstChild("Head")
			local screenPoint, onScreen = camera:WorldToViewportPoint(head.Position)

			if onScreen and screenPoint.Z > 0 then
				local screenPosition = Vector2.new(screenPoint.X, screenPoint.Y)
				local distance = (screenPosition - aimOrigin).Magnitude

				if IsScreenPointInAimbotFOV(screenPosition) and distance < closestDistance then
					closestDistance = distance
					closestHead = head
					closestScreenPosition = screenPosition
					closestModel = model
				end
			end
		end
	end

	return closestHead, closestScreenPosition, closestModel
end

local function GetLockedAimbotTarget()
	camera = Workspace.CurrentCamera

	if not camera then
		aimbotSettings.LockedModel = nil
		aimbotSettings.MouseRemainder = Vector2.zero
		return nil
	end

	if aimbotSettings.LockedModel and IsValidAimbotTarget(aimbotSettings.LockedModel) then
		local head = aimbotSettings.LockedModel:FindFirstChild("Head")

		if head then
			local point, onScreen = camera:WorldToViewportPoint(head.Position)

			if onScreen and point.Z > 0 then
				local screenPosition = Vector2.new(point.X, point.Y)

				if IsScreenPointInAimbotFOV(screenPosition) then
					return head, screenPosition
				end
			end
		end
	end

	aimbotSettings.LockedModel = nil
	aimbotSettings.MouseRemainder = Vector2.zero

	local head, screenPosition, model = GetClosestHeadToCrosshair()
	aimbotSettings.LockedModel = model
	return head, screenPosition
end

local function MoveMouseTowardScreenPosition(screenPosition)
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

	local response = math.clamp(aimbotSettings.Smoothness / 100, 0.01, 1)
	local delta = (rawDelta * response) + aimbotSettings.MouseRemainder

	if delta.Magnitude > aimbotSettings.MouseMaxStep then
		delta = delta.Unit * aimbotSettings.MouseMaxStep
		aimbotSettings.MouseRemainder = Vector2.zero
	end

	local deltaX = delta.X >= 0 and math.floor(delta.X) or math.ceil(delta.X)
	local deltaY = delta.Y >= 0 and math.floor(delta.Y) or math.ceil(delta.Y)
	aimbotSettings.MouseRemainder = delta - Vector2.new(deltaX, deltaY)

	if typeof(mousemoverel) == "function" then
		return pcall(mousemoverel, deltaX, deltaY)
	end

	if typeof(mousemoveabs) == "function" then
		local nextPosition = aimOrigin + Vector2.new(deltaX, deltaY) + topLeftInset
		return pcall(mousemoveabs, nextPosition.X, nextPosition.Y)
	end

	return false
end

local function AimAtHead(head)
	camera = Workspace.CurrentCamera

	if not camera or not head or not head:IsDescendantOf(Workspace) then
		return
	end

	if mouseAimbotEnabled then
		local point, onScreen = camera:WorldToViewportPoint(head.Position)

		if not onScreen or point.Z <= 0 then
			return
		end

		local movedMouse = MoveMouseTowardScreenPosition(Vector2.new(point.X, point.Y))

		if not movedMouse and not mouseAimbotWarningShown then
			mouseAimbotWarningShown = true
			Notify("Mouse Aimbot", "Mouse movement is not supported in this executor")
		end

		return
	end

	local position = camera.CFrame.Position
	local targetCFrame = CFrame.lookAt(position, head.Position)
	camera.CFrame = camera.CFrame:Lerp(targetCFrame, math.clamp(aimbotSettings.Smoothness / 100, 0.01, 1))
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
	if not triggerbotEnabled or UserInputService:GetFocusedTextBox() then
		return
	end

	local now = os.clock()

	if now - lastTriggerbotShot < TRIGGERBOT_DELAY then
		return
	end

	camera = Workspace.CurrentCamera

	if not camera then
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

	if not model or not IsValidAimbotTarget(model) then
		return
	end

	lastTriggerbotShot = now

	if not ClickMouseOnce() and not triggerbotWarningShown then
		triggerbotWarningShown = true
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
	clickTeleportEnabled = false
	antiAFKEnabled = false
	crosshairEnabled = false

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
		:setTooltip("Percentage response. 55 is balanced; lower is smoother and higher is faster.")

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
		})
		:bindToEvent("onFocusLost", function(text)
			SetAimbotBindFromText(text)
		end)

	aimbotSection
		:addTextbox({
			text = "Wallcheck Hotkey",
		})
		:bindToEvent("onFocusLost", function(text)
			SetWallCheckHotkeyFromText(text)
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
			lastTriggerbotShot = 0
		end)

	triggerbotSection
		:addSlider({
			text = "Shot Delay",
			min = 0.02,
			max = 0.5,
			step = 0.01,
			value = TRIGGERBOT_DELAY,
		}, function(newValue)
			TRIGGERBOT_DELAY = tonumber(newValue) or TRIGGERBOT_DELAY
		end)
		:setTooltip("Delay between automatic shots while an eligible target is under the crosshair.")

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
			state = true,
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
			value = PLAYER_FOV,
		}, function(newValue)
			SetPlayerFOV(newValue)
		end)
		:setTooltip("Changes your camera field of view.")

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

TrackConnection(UserInputService.InputBegan:Connect(function(input, gameProcessedEvent)
	if UserInputService:GetFocusedTextBox() then
		return
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

	if camera then
		if originalCameraFOVs[camera] == nil then
			originalCameraFOVs[camera] = camera.FieldOfView
		end

		if camera.FieldOfView ~= PLAYER_FOV then
			camera.FieldOfView = PLAYER_FOV
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
		local targetHead = GetLockedAimbotTarget()

		if targetHead then
			AimAtHead(targetHead)
		end
	else
		aimbotSettings.LockedModel = nil
		aimbotSettings.MouseRemainder = Vector2.zero
	end

	UpdateTriggerbot()

	if espEnabled or radar.Enabled then
		espUpdateAccumulator += deltaTime

		if espUpdateAccumulator >= ESP_UPDATE_INTERVAL then
			espUpdateAccumulator %= ESP_UPDATE_INTERVAL

			if espEnabled then
				RefreshESP()
			end

			if radar.Enabled then
				radar.Update()
			end
		end
	else
		espUpdateAccumulator = 0
	end
end))

PrintLoad("ready")
