-- 보조수 무기 (클라)
-- 동승석에 앉으면 "보조수 모드":
--   • 어깨 너머 카메라, 마우스로 조준 (화면 가운데 조준점)
--   • 왼클릭 = 쏘기 (AR 은 꾹 = 연사), 우클릭 꾹 = 조준(확대), R = 재장전
--   • 1~4 = 무기 바꾸기 (테스트용, 나중엔 상점)
-- 맞았는지는 내 화면에서 계산해서 서버에 보고 → 서버가 검사 후 피해 (WeaponService)

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")

local WeaponConfig = require(ReplicatedStorage.Shared.Config.WeaponConfig)
local G = WeaponConfig.General
local Remote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Weapon") :: RemoteEvent

local player = Players.LocalPlayer
local BIND = "GunnerCamera"
local DEFAULT_FOV = 70

local active = false
local yaw, pitch = 0, 0
local holding, zooming = false, false
local lastFire = 0
local conns: { RBXScriptConnection } = {}

----------------------------------------------------------------------
-- 화면 (조준점, 탄약, 맞힘 표시)
----------------------------------------------------------------------

local gui = Instance.new("ScreenGui")
gui.Name = "GunnerHUD"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.Enabled = false
gui.Parent = player:WaitForChild("PlayerGui")

local function frame(parent: Instance, size: UDim2, pos: UDim2, color: Color3, rot: number?): Frame
	local f = Instance.new("Frame")
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Size = size
	f.Position = pos
	f.BackgroundColor3 = color
	f.BorderSizePixel = 0
	f.Rotation = rot or 0
	f.Parent = parent
	return f
end

local center = UDim2.fromScale(0.5, 0.5)
local cross = Instance.new("Frame")
cross.AnchorPoint = Vector2.new(0.5, 0.5)
cross.Position = center
cross.Size = UDim2.fromOffset(40, 40)
cross.BackgroundTransparency = 1
cross.Parent = gui
frame(cross, UDim2.fromOffset(4, 4), center, Color3.new(1, 1, 1))
for _, o in { { 0, -14 }, { 0, 14 }, { -14, 0 }, { 14, 0 } } do
	local vertical = o[1] == 0
	frame(cross, vertical and UDim2.fromOffset(2, 9) or UDim2.fromOffset(9, 2), UDim2.new(0.5, o[1], 0.5, o[2]), Color3.new(1, 1, 1))
end

local hitMark = Instance.new("Frame")
hitMark.AnchorPoint = Vector2.new(0.5, 0.5)
hitMark.Position = center
hitMark.Size = UDim2.fromOffset(34, 34)
hitMark.BackgroundTransparency = 1
hitMark.Visible = false
hitMark.Parent = gui
local hitBars = {
	frame(hitMark, UDim2.fromOffset(30, 3), center, Color3.new(1, 1, 1), 45),
	frame(hitMark, UDim2.fromOffset(30, 3), center, Color3.new(1, 1, 1), -45),
}

local function label(size: UDim2, pos: UDim2, anchor: Vector2, textSize: number): TextLabel
	local t = Instance.new("TextLabel")
	t.AnchorPoint = anchor
	t.Size = size
	t.Position = pos
	t.BackgroundTransparency = 1
	t.Font = Enum.Font.GothamBlack
	t.TextSize = textSize
	t.TextColor3 = Color3.new(1, 1, 1)
	t.TextStrokeTransparency = 0.4
	t.Parent = gui
	return t
end
local ammoText = label(UDim2.fromOffset(300, 40), UDim2.new(1, -24, 1, -90), Vector2.new(1, 1), 28)
ammoText.TextXAlignment = Enum.TextXAlignment.Right
local killText = label(UDim2.fromOffset(300, 40), UDim2.new(0.5, 0, 0.5, 60), Vector2.new(0.5, 0.5), 30)
killText.TextColor3 = Color3.fromRGB(255, 70, 70)
killText.Text = "KILL"
killText.Visible = false
local hintText = label(UDim2.fromOffset(600, 24), UDim2.new(0.5, 0, 1, -20), Vector2.new(0.5, 1), 15)
do
	local names = {}
	for i, w in WeaponConfig.Weapons do
		table.insert(names, i .. " " .. w.name)
	end
	hintText.Text = "좌클릭 쏘기 · 우클릭 조준 · R 장전 · " .. table.concat(names, "  ") .. " (테스트)"
end

local hitToken = 0
local function showHit(kind: string, killed: boolean)
	hitToken += 1
	local my = hitToken
	local color = killed and Color3.fromRGB(255, 60, 60) or (kind == "head" and Color3.fromRGB(255, 220, 60) or Color3.new(1, 1, 1))
	for _, b in hitBars do
		b.BackgroundColor3 = color
	end
	hitMark.Visible = true
	killText.Visible = killed
	task.delay(killed and 0.6 or 0.12, function()
		if hitToken == my then
			hitMark.Visible = false
			killText.Visible = false
		end
	end)
end

----------------------------------------------------------------------
-- 보조수 상태
----------------------------------------------------------------------

local function vehicleOf(inst: Instance?): Model?
	local folder = workspace:FindFirstChild("Vehicles")
	while inst and inst.Parent ~= folder do
		inst = inst.Parent
	end
	return inst and inst:IsA("Model") and inst or nil
end

local function gunner()
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local seat = hum and hum.SeatPart
	if hum and hum.Health > 0 and seat and seat.Name:match("^PassengerSeat") then
		return char, hum, vehicleOf(seat)
	end
	return nil
end

local function currentDef()
	local id = player:GetAttribute("GunnerWeapon")
	return type(id) == "string" and WeaponConfig.Get(id) or WeaponConfig.Get(WeaponConfig.DefaultGunnerWeapon)
end

local function muzzlePos(char: Model?): Vector3?
	local gun = char and char:FindFirstChild("GunnerWeapon")
	local m = gun and gun:FindFirstChild("Muzzle", true)
	if m and m:IsA("Attachment") then
		return m.WorldPosition
	elseif m and m:IsA("BasePart") then
		return m.Position
	end
	return nil
end

local function tracer(from: Vector3, to: Vector3, color: Color3?)
	local d = (to - from).Magnitude
	if d < 0.5 then
		return
	end
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	p.Color = color or Color3.fromRGB(255, 230, 140)
	p.Size = Vector3.new(0.18, 0.18, d)
	p.CFrame = CFrame.lookAt((from + to) / 2, to)
	p.Parent = workspace.CurrentCamera
	Debris:AddItem(p, G.tracerTime)
end

local function rayParams(char: Model, vehicle: Model?): RaycastParams
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local list: { Instance } = { char, workspace.CurrentCamera }
	if vehicle then
		table.insert(list, vehicle)
	end
	params.FilterDescendantsInstances = list
	return params
end

local function fire()
	local char, hum, vehicle = gunner()
	local def = currentDef()
	if not char or not hum or not def then
		return
	end
	if player:GetAttribute("Reloading") then
		return
	end
	local ammo = player:GetAttribute("Ammo")
	if type(ammo) == "number" and ammo <= 0 then
		Remote:FireServer("Reload")
		return
	end
	local now = os.clock()
	if now - lastFire < 1 / def.fireRate then
		return
	end
	lastFire = now
	local head = char:FindFirstChild("Head") :: BasePart?
	if not head then
		return
	end
	local cam = workspace.CurrentCamera
	local params = rayParams(char, vehicle)
	-- 1) 화면 가운데가 가리키는 곳
	local look = cam.CFrame.LookVector
	local aimHit = workspace:Raycast(cam.CFrame.Position, look * (def.range + 60), params)
	local aimPoint = aimHit and aimHit.Position or cam.CFrame.Position + look * def.range
	-- 2) 내 머리에서 그곳으로 (탄 퍼짐 적용)
	local origin = head.Position
	local dir = (aimPoint - origin).Unit
	if def.spread > 0 then
		local spin = math.random() * math.pi * 2
		local off = math.rad(def.spread) * math.sqrt(math.random())
		if zooming then
			off *= 0.4 -- 조준하면 덜 퍼짐
		end
		dir = (CFrame.lookAt(origin, origin + dir) * CFrame.Angles(0, 0, spin) * CFrame.Angles(off, 0, 0)).LookVector
	end
	local from = muzzlePos(char) or origin
	if def.kind == "projectile" then
		Remote:FireServer("FireProjectile", origin, dir)
	else
		local res = workspace:Raycast(origin, dir * def.range, params)
		local hitPos = res and res.Position or origin + dir * def.range
		Remote:FireServer("Fire", origin, res and res.Instance, hitPos)
		tracer(from, hitPos)
	end
	-- 반동: 화면이 살짝 위로
	pitch = math.clamp(pitch + (0.004 + def.damage * 0.0004), math.rad(G.pitchMin), math.rad(G.pitchMax))
end

----------------------------------------------------------------------
-- 들어가기 / 나오기
----------------------------------------------------------------------

local function enter(char: Model, vehicle: Model?)
	active = true
	gui.Enabled = true
	holding, zooming = false, false
	local look = (vehicle and vehicle.PrimaryPart and vehicle.PrimaryPart.CFrame.LookVector) or Vector3.new(0, 0, -1)
	yaw = math.atan2(-look.X, -look.Z)
	pitch = 0
	local cam = workspace.CurrentCamera
	cam.CameraType = Enum.CameraType.Scriptable

	table.insert(conns, UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			holding = true
			fire()
		elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
			zooming = true
		elseif input.KeyCode == Enum.KeyCode.R then
			Remote:FireServer("Reload")
		else
			local n = ({
				[Enum.KeyCode.One] = 1, [Enum.KeyCode.Two] = 2, [Enum.KeyCode.Three] = 3, [Enum.KeyCode.Four] = 4,
				[Enum.KeyCode.Five] = 5, [Enum.KeyCode.Six] = 6,
			})[input.KeyCode]
			local w = n and WeaponConfig.Weapons[n]
			if w then
				Remote:FireServer("Select", w.id)
			end
		end
	end))
	table.insert(conns, UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			holding = false
		elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
			zooming = false
		end
	end))
	table.insert(conns, UserInputService.InputChanged:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseMovement then
			local sens = G.mouseSensitivity * (zooming and G.zoomSensitivityScale or 1)
			yaw -= input.Delta.X * sens
			pitch = math.clamp(pitch - input.Delta.Y * sens, math.rad(G.pitchMin), math.rad(G.pitchMax))
		end
	end))

	RunService:BindToRenderStep(BIND, Enum.RenderPriority.Camera.Value + 2, function(dt)
		local c = player.Character
		local head = c and c:FindFirstChild("Head") :: BasePart?
		if not head then
			return
		end
		UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
		local rot = CFrame.fromEulerAnglesYXZ(pitch, yaw, 0)
		local def = currentDef()
		local offset = zooming and G.cameraOffset * Vector3.new(0.6, 0.5, 0.3) or G.cameraOffset
		local pos = head.Position + rot:VectorToWorldSpace(offset)
		cam.CFrame = CFrame.lookAt(pos, pos + rot.LookVector)
		local fov = zooming and def and def.zoomFov or DEFAULT_FOV
		cam.FieldOfView += (fov - cam.FieldOfView) * math.min(dt * 12, 1)
		if holding and def and def.auto then
			fire()
		end
		-- 탄약 표시
		local ammo = player:GetAttribute("Ammo")
		if player:GetAttribute("Reloading") then
			ammoText.Text = (def and def.name or "") .. "  장전 중..."
		else
			ammoText.Text = string.format("%s  %s / %d", def and def.name or "", tostring(ammo or "-"), def and def.magazine or 0)
		end
	end)
end

local function exit()
	active = false
	gui.Enabled = false
	holding, zooming = false, false
	for _, c in conns do
		c:Disconnect()
	end
	table.clear(conns)
	RunService:UnbindFromRenderStep(BIND)
	UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	local cam = workspace.CurrentCamera
	cam.FieldOfView = DEFAULT_FOV
	cam.CameraType = Enum.CameraType.Custom
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if hum and hum.Health > 0 then
		cam.CameraSubject = hum
	end
end

RunService.Heartbeat:Connect(function()
	local char, _, vehicle = gunner()
	if char and not active then
		enter(char, vehicle)
	elseif not char and active then
		exit()
	end
end)

----------------------------------------------------------------------
-- 서버 알림
----------------------------------------------------------------------

Remote.OnClientEvent:Connect(function(kind, a, b, c, d)
	if kind == "Shot" then
		-- 다른 보조수가 쏜 총알 줄기 (그 사람 총구에서)
		local shooter = a :: Player
		local from = muzzlePos(shooter and shooter.Character) or b
		if typeof(from) == "Vector3" and typeof(c) == "Vector3" then
			local def = type(d) == "string" and WeaponConfig.Get(d)
			tracer(from, c, def and def.kind == "projectile" and Color3.fromRGB(150, 80, 40) or nil)
		end
	elseif kind == "Hit" then
		showHit(a, b == true)
	elseif kind == "Knock" then
		-- 콜라캐논에 맞은 내 차 밀려나기 (운전자 화면이 물리 담당)
		local model, vel = a, b
		local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		local seat = hum and hum.SeatPart
		if typeof(model) == "Instance" and model:IsA("Model") and typeof(vel) == "Vector3"
			and seat and seat.Name == "DriverSeat" and seat:IsDescendantOf(model) and model.PrimaryPart then
			model.PrimaryPart.AssemblyLinearVelocity += vel
		end
	end
end)
