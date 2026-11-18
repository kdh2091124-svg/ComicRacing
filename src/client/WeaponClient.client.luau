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
local GunFX = require(script.Parent:WaitForChild("GunFX"))
local ViewModel = require(script.Parent:WaitForChild("ViewModel"))
local G = WeaponConfig.General
local Remote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Weapon") :: RemoteEvent

local player = Players.LocalPlayer
local BIND = "GunnerCamera"
local DEFAULT_FOV = 70

local active = false
local yaw, pitch = 0, 0
local recoilP, recoilY = 0, 0 -- 반동 (라디안): 쏘면 튀고, 스프링으로 원래 조준으로 돌아옴
local recoilVP, recoilVY = 0, 0 -- 반동 스프링 속도
local reloadStart: number? = nil
local shake, fovKick, bloom = 0, 0, 0 -- 화면 흔들림(스터드), 시야 펀치(도), 조준점 벌어짐(0~1)
local TweenService = game:GetService("TweenService")
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
local function outline(f: Frame)
	local s = Instance.new("UIStroke") -- 검은 테두리 (밝은 배경에서도 보이게)
	s.Thickness = 1
	s.Color = Color3.new(0, 0, 0)
	s.Transparency = 0.3
	s.Parent = f
end
outline(frame(cross, UDim2.fromOffset(4, 4), center, Color3.new(1, 1, 1)))
local CROSS_DIRS = { { 0, -1 }, { 0, 1 }, { -1, 0 }, { 1, 0 } }
local crossArms: { Frame } = {}
for _, o in CROSS_DIRS do
	local vertical = o[1] == 0
	local arm = frame(cross, vertical and UDim2.fromOffset(3, 11) or UDim2.fromOffset(11, 3), UDim2.new(0.5, o[1] * 14, 0.5, o[2] * 14), Color3.new(1, 1, 1))
	outline(arm)
	table.insert(crossArms, arm)
end

-- 조준경 화면 (실제 저격 스코프 느낌)
--   렌즈 바깥 = 거의 검정, 렌즈 가장자리 = 부드러운 그림자(비네팅), 아주 옅은 렌즈 색
--   십자선 = 바깥쪽은 굵은 기둥, 가운데로 갈수록 가는 선 + 거리 눈금 점 + 작은 빨간 중앙점
--   줌 켤 때 그림자가 조였다 열리고, 휙 돌리면 렌즈가 살짝 밀리며 그림자가 진해짐 (정확도와는 상관없음)
--   (이미지 없이: 두꺼운 테두리(UIStroke)를 단 원 여러 겹)
local scope = Instance.new("Frame")
scope.Name = "Scope"
scope.AnchorPoint = Vector2.new(0.5, 0.5)
scope.Position = UDim2.fromScale(0.5, 0.5)
scope.Size = UDim2.fromScale(0.9, 0.9)
scope.BackgroundTransparency = 1
scope.Visible = false
scope.ZIndex = 5
scope.Parent = gui
local vignetteRings: { UIStroke } = {}
local scopeDarkIn: Frame -- 줌 켤 때 렌즈 안이 어두웠다 밝아지는 막
do
	local ratio = Instance.new("UIAspectRatioConstraint")
	ratio.AspectRatio = 1
	ratio.DominantAxis = Enum.DominantAxis.Height
	ratio.Parent = scope
	local function circle(parent: Instance, scale: number): Frame
		local f = Instance.new("Frame")
		f.AnchorPoint = Vector2.new(0.5, 0.5)
		f.Position = UDim2.fromScale(0.5, 0.5)
		f.Size = UDim2.fromScale(scale, scale)
		f.BackgroundTransparency = 1
		f.Parent = parent
		local r = Instance.new("UICorner")
		r.CornerRadius = UDim.new(1, 0)
		r.Parent = f
		return f
	end
	local outer = Instance.new("UIStroke") -- 렌즈 바깥 전체 (거의 검정)
	outer.Thickness = 3000
	outer.Color = Color3.fromRGB(4, 5, 6)
	outer.Transparency = 0.04
	outer.Parent = circle(scope, 1)
	-- 가장자리 그림자: 안쪽으로 갈수록 옅어지는 고리 여러 겹 (두께는 화면 크기에 맞춰 매 프레임)
	for i = 1, 7 do
		local s = Instance.new("UIStroke")
		s.Color = Color3.new(0, 0, 0)
		s.Transparency = 0.35 + i * 0.09
		s.Parent = circle(scope, 1 - i * 0.022)
		table.insert(vignetteRings, s)
	end
	local tint = circle(scope, 1) -- 아주 옅은 렌즈 색
	tint.BackgroundTransparency = 0.94
	tint.BackgroundColor3 = Color3.fromRGB(40, 80, 90)
	scopeDarkIn = circle(scope, 1)
	scopeDarkIn.BackgroundColor3 = Color3.new(0, 0, 0)
	scopeDarkIn.BackgroundTransparency = 1
	local INK = Color3.fromRGB(10, 10, 12)
	local function bar(size: UDim2, pos: UDim2)
		local b = Instance.new("Frame")
		b.AnchorPoint = Vector2.new(0.5, 0.5)
		b.Size = size
		b.Position = pos
		b.BackgroundColor3 = INK
		b.BorderSizePixel = 0
		b.Parent = scope
	end
	-- 굵은 기둥 (가장자리 → 중심 30% 지점까지)
	bar(UDim2.new(0, 5, 0.32, 0), UDim2.fromScale(0.5, 0.16))
	bar(UDim2.new(0, 5, 0.32, 0), UDim2.fromScale(0.5, 0.84))
	bar(UDim2.new(0.32, 0, 0, 5), UDim2.fromScale(0.16, 0.5))
	bar(UDim2.new(0.32, 0, 0, 5), UDim2.fromScale(0.84, 0.5))
	-- 가는 선 (중심까지)
	bar(UDim2.new(0, 1, 0.36, 0), UDim2.fromScale(0.5, 0.5))
	bar(UDim2.new(0.36, 0, 0, 1), UDim2.fromScale(0.5, 0.5))
	-- 거리 눈금 점 (가는 선 위)
	for k = 1, 4 do
		local d = k * 0.035
		for _, p in { { 0.5, 0.5 + d }, { 0.5, 0.5 - d }, { 0.5 + d, 0.5 }, { 0.5 - d, 0.5 } } do
			local dot = Instance.new("Frame")
			dot.AnchorPoint = Vector2.new(0.5, 0.5)
			dot.Position = UDim2.fromScale(p[1], p[2])
			dot.Size = UDim2.fromOffset(4, 4)
			dot.BackgroundColor3 = INK
			dot.BorderSizePixel = 0
			dot.Parent = scope
			local r = Instance.new("UICorner")
			r.CornerRadius = UDim.new(1, 0)
			r.Parent = dot
		end
	end
	-- 작은 빨간 중앙점 (조명 레티클)
	local center = Instance.new("Frame")
	center.AnchorPoint = Vector2.new(0.5, 0.5)
	center.Position = UDim2.fromScale(0.5, 0.5)
	center.Size = UDim2.fromOffset(3, 3)
	center.BackgroundColor3 = Color3.fromRGB(255, 50, 40)
	center.BorderSizePixel = 0
	center.Parent = scope
end
local scopeShift = Vector2.zero -- 휙 돌릴 때 렌즈가 밀리는 양 (픽셀)
local turnShade = 0 -- 휙 돌릴 때 그림자 진해짐 (0~1)

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
	-- 맞힘 표시: 크게 튀어나왔다가 줄어듦 (킬이면 더 크게)
	hitMark.Visible = true
	hitMark.Size = UDim2.fromOffset(killed and 70 or 52, killed and 70 or 52)
	TweenService:Create(hitMark, TweenInfo.new(0.12, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = UDim2.fromOffset(34, 34) }):Play()
	killText.Visible = killed
	if killed then
		killText.TextSize = 64
		TweenService:Create(killText, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { TextSize = 34 }):Play()
		shake = math.max(shake, 0.6)
	end
	task.delay(killed and 0.7 or 0.15, function()
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

-- 지금 탄 퍼짐 (도): hipSpread 가 있는 무기(스나)는 조준 안 하면 크게, 조준하면 spread.
-- 나머지는 조준하면 40% 로 줄어듦
-- 조준(우클릭) 상태: 볼트 당기는 중이면 우클릭을 누르고 있어도 조준 안 됨
local rmbDown = false
local zoomStart = 0
local boltUntil = 0
local scopedSent = false
local turnBlur = 0 -- 화면 돌려서 생긴 흐림 (0~1)
local scopeBlur = 0 -- 지금 조준경 흐림 (0 = 선명 = 탄 안 튐, 1 = 완전 흐림 = hipSpread 만큼 튐)

-- 지금 조준경 흐림: 줌 켠 직후(scopeTime 동안 서서히 선명) 또는 화면 돌릴 때
local function updateScopeBlur(def, dt: number, mouseMove: number)
	if not (zooming and def and def.hipSpread) then
		turnBlur = 0
		scopeBlur = 0
		return
	end
	local scopeIn = 0
	if def.scopeTime and def.scopeTime > 0 then
		scopeIn = 1 - math.clamp((os.clock() - zoomStart) / def.scopeTime, 0, 1)
	end
	-- 정확도는 "줌 켠 직후"만 영향. 화면 돌리는 건 그림자 연출만 (탄 안 튐)
	turnBlur = math.clamp(turnBlur + mouseMove * G.scopeTurnShade - dt * G.scopeSettle, 0, 1)
	scopeBlur = scopeIn
end

local function currentSpread(def): number
	if def.hipSpread then
		if not zooming then
			return def.hipSpread
		end
		-- 흐린 만큼 튐, 완전히 선명하면 spread(=0) → 똑바로
		return def.spread + (def.hipSpread - def.spread) * scopeBlur
	end
	return def.spread * (zooming and 0.4 or 1)
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

-- 총 방향 (탄피 튀는 방향용): 총 모델이 있으면 그 오른쪽/위, 없으면 기본값
local function gunAxes(char: Model?, fallbackDir: Vector3): (Vector3, Vector3)
	-- 내 1인칭 총이 있으면 그 방향 (탄피가 화면에서 자연스럽게 튐)
	if char and char == player.Character and G.firstPerson then
		local r, u = ViewModel.Axes()
		if r and u then
			return r, u
		end
	end
	local gun = char and char:FindFirstChild("GunnerWeapon")
	local handle = gun and gun:IsA("Model") and gun.PrimaryPart
	if handle then
		return handle.CFrame.RightVector, handle.CFrame.UpVector
	end
	local right = fallbackDir:Cross(Vector3.yAxis)
	return right.Magnitude > 0.01 and right.Unit or Vector3.xAxis, Vector3.yAxis
end

-- 탄피 배출구: 내 1인칭 총의 "Eject" → 남의 손 총의 "Eject" → 없으면 nil (총구 뒤쪽에서 대충)
--   반환: 위치, 탄피 날아갈 방향 ("Eject" 의 앞쪽 -Z)
local function ejectPos(char: Model?): (Vector3?, Vector3?)
	if char and char == player.Character and G.firstPerson then
		local p, d = ViewModel.EjectPosition()
		if p then
			return p, d
		end
	end
	local gun = char and char:FindFirstChild("GunnerWeapon")
	local e = gun and gun:FindFirstChild("Eject", true)
	if e and e:IsA("Attachment") then
		return e.WorldPosition, e.WorldCFrame.LookVector
	elseif e and e:IsA("BasePart") then
		return e.Position, e.CFrame.LookVector
	end
	return nil, nil
end

-- 탄피 하나: 배출구가 있으면 그 방향으로, 없으면 총 오른쪽으로
local function spawnShell(char: Model?, fallbackPos: Vector3, right: Vector3, up: Vector3, style)
	local p, d = ejectPos(char)
	if p and d then
		GunFX.Shell(p, d, Vector3.yAxis * 0.25, style)
	else
		GunFX.Shell(fallbackPos, right, up, style)
	end
end

-- 쏘는 연출 한 세트: 섬광 + 탄피 + 줄기 + 맞은 자리
local function shotFX(char: Model?, weaponId: string?, from: Vector3, to: Vector3, hitInst: Instance?, normal: Vector3?, hit: boolean)
	local style = GunFX.Style(weaponId)
	local dir = (to - from).Magnitude > 0.01 and (to - from).Unit or Vector3.zAxis
	GunFX.Muzzle(from, dir, style)
	local def = weaponId and WeaponConfig.Get(weaponId)
	local right, up = gunAxes(char, dir)
	if def and def.boltTime then
		-- 볼트식: 탄피는 쏠 때가 아니라 볼트 당길 때 튐
		task.delay(def.boltTime * 0.15, function()
			spawnShell(char, from - dir * 1.2, right, up, style)
		end)
	else
		spawnShell(char, from - dir * 1.2, right, up, style)
	end
	GunFX.Tracer(from, to, style)
	if hit then
		GunFX.Impact(to, normal, GunFX.KindOf(hitInst), weaponId == "Sniper" and 1.6 or 1)
	end
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
	-- 조준경이 켜져 있으면 "실제로 보이는 십자선" 위치로 (휙 돌릴 때 렌즈와 함께 밀린 자리)
	local camPos, look = cam.CFrame.Position, cam.CFrame.LookVector
	if scope.Visible then
		local vs = cam.ViewportSize
		local ray = cam:ViewportPointToRay(vs.X / 2 + scopeShift.X, vs.Y / 2 + scopeShift.Y)
		camPos, look = ray.Origin, ray.Direction.Unit
	end
	-- 1인칭 총이 반동으로 튄 만큼 총알도 그쪽으로 (조준점도 같이 올라가서 보이는 대로 맞음)
	if G.firstPerson and not scope.Visible then
		local kp, ky = ViewModel.AimKick()
		look = (CFrame.lookAt(Vector3.zero, look) * CFrame.Angles(kp, ky, 0)).LookVector
	end
	local aimHit = workspace:Raycast(camPos, look * (def.range + 60), params)
	local aimPoint = aimHit and aimHit.Position or camPos + look * def.range
	-- 2) 내 머리에서 그곳으로 (탄 퍼짐 적용)
	local origin = head.Position
	local dir = (aimPoint - origin).Unit
	local spreadDeg = currentSpread(def)
	if spreadDeg > 0 then
		local spin = math.random() * math.pi * 2
		local off = math.rad(spreadDeg) * math.sqrt(math.random())
		dir =(CFrame.lookAt(origin, origin + dir) * CFrame.Angles(0, 0, spin) * CFrame.Angles(off, 0, 0)).LookVector
	end
	local from = (G.firstPerson and ViewModel.MuzzlePosition()) or muzzlePos(char) or origin
	if def.kind == "projectile" then
		-- 날아가는 탄은 눈에 보이니까 총구에서 출발 (조준점 쪽으로)
		local pOrigin = from -- 1인칭이면 내 화면 총구
		local pDir = (aimPoint - pOrigin)
		pDir = pDir.Magnitude > 0.1 and pDir.Unit or dir
		Remote:FireServer("FireProjectile", pOrigin, pDir)
		local style = GunFX.Style(def.id)
		GunFX.Muzzle(pOrigin, pDir, style)
		local right, up = gunAxes(char, pDir)
		spawnShell(char, pOrigin - pDir * 1.2, right, up, style)
	else
		local res = workspace:Raycast(origin, dir * def.range, params)
		local hitPos = res and res.Position or origin + dir * def.range
		Remote:FireServer("Fire", origin, res and res.Instance, hitPos)
		shotFX(char, def.id, from, hitPos, res and res.Instance, res and res.Normal, res ~= nil)
	end
	-- 반동: 화면이 위로(+좌우 살짝) 튀었다가 매 프레임 원래 조준으로 돌아옴
	local kick = math.rad(def.recoil or 1) * (zooming and 0.7 or 1)
	-- 절반은 바로 탁, 절반은 속도로 → 순간 튀고 쭉 올라갔다 스프링으로 돌아옴
	recoilP = math.min(recoilP + kick * 0.5, math.rad(G.recoilMax))
	recoilVP += kick * 18
	local side = math.rad(def.recoilSide or 0) * (math.random() * 2 - 1)
	recoilY += side * 0.5
	recoilVY += side * 14
	-- 화면 흔들림 + 시야 펀치 + 조준점 벌어짐
	shake = math.max(shake, def.shake or 0.15)
	fovKick += def.fovKick or 1
	bloom = math.min(bloom + (def.auto and 0.25 or 0.8), 1)
	ViewModel.Kick(def.vmKick or (def.auto and 0.35 or 1)) -- 1인칭 총 반동 모션 (무기별 vmKick)
	-- 볼트식(스나): 한 발 쏘면 조준 풀리고 볼트 당김 → 그동안 다시 조준 못 함
	if def.boltTime then
		boltUntil = now + def.boltTime
		zooming = false
		task.delay(def.boltTime * 0.15, function()
			shake = math.max(shake, 0.12) -- 볼트 "철컥"
			recoilY += math.rad(0.6)
		end)
	end
end

----------------------------------------------------------------------
-- 들어가기 / 나오기
----------------------------------------------------------------------

local function enter(char: Model, vehicle: Model?)
	active = true
	gui.Enabled = true
	holding, zooming = false, false
	recoilP, recoilY, recoilVP, recoilVY = 0, 0, 0, 0
	rmbDown, boltUntil, reloadStart = false, 0, nil
	local look = (vehicle and vehicle.PrimaryPart and vehicle.PrimaryPart.CFrame.LookVector) or Vector3.new(0, 0, -1)
	yaw = math.atan2(-look.X, -look.Z)
	pitch = 0
	local cam = workspace.CurrentCamera
	cam.CameraType = Enum.CameraType.Scriptable
	shake, fovKick, bloom = 0, 0, 0

	table.insert(conns, UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			holding = true
			fire()
		elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
			rmbDown = true
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
			rmbDown = false
		end
	end))
	-- 맨 마지막 순서로 카메라를 잡음 (기본 카메라가 덮어쓰던 문제 → 화면 안 돌아가고 반동도 안 보였음)
	RunService:BindToRenderStep(BIND, Enum.RenderPriority.Last.Value, function(dt)
		local c = player.Character
		local head = c and c:FindFirstChild("Head") :: BasePart?
		if not head then
			return
		end
		cam = workspace.CurrentCamera
		if cam.CameraType ~= Enum.CameraType.Scriptable then
			cam.CameraType = Enum.CameraType.Scriptable -- 다른 코드가 되돌려도 다시 잡음
		end
		UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
		UserInputService.MouseIconEnabled = false -- 마우스 커서 숨김, 조준점만
		-- 조준 상태: 우클릭 누름 + 볼트 당기는 중 아님
		local nowT = os.clock()
		local wantZoom = rmbDown and nowT >= boltUntil
		if wantZoom and not zooming then
			zoomStart = nowT
		end
		zooming = wantZoom
		-- 조준경 반짝임: 스나로 조준 중이면 서버에 알림 → 상대 화면에 반짝
		local d0 = currentDef()
		local scoped = zooming and d0 ~= nil and d0.scopeGlint == true
		if scoped ~= scopedSent then
			scopedSent = scoped
			Remote:FireServer("Scope", scoped)
		end
		-- 마우스 움직임: 매 프레임 직접 읽음 (가운데 고정 상태에서 확실함)
		local md = UserInputService:GetMouseDelta()
		local sens = G.mouseSensitivity * (zooming and G.zoomSensitivityScale or 1)
		yaw -= md.X * sens
		pitch = math.clamp(pitch - md.Y * sens, math.rad(G.pitchMin), math.rad(G.pitchMax))
		-- 반동 되돌아오기
		-- 반동 스프링: 탁 튀었다가 살짝 아래로 튕기며 제자리 (쫄깃)
		local k = G.recoilStiffness
		local cdamp = 2 * G.recoilDamping * math.sqrt(k)
		local steps = math.max(math.ceil(dt * 240), 1)
		local h = dt / steps
		for _ = 1, steps do
			recoilVP += (-k * recoilP - cdamp * recoilVP) * h
			recoilP += recoilVP * h
			recoilVY += (-k * recoilY - cdamp * recoilVY) * h
			recoilY += recoilVY * h
		end
		shake = math.max(shake - dt * 6 * math.max(shake, 0.3), 0)
		fovKick -= fovKick * math.min(dt * 10, 1)
		bloom -= bloom * math.min(dt * 8, 1)
		local rot = CFrame.fromEulerAnglesYXZ(pitch + recoilP, yaw + recoilY, 0)
		local def = currentDef()
		local pos
		if G.firstPerson then
			-- 1인칭: 눈 위치. 내 몸/총은 내 화면에서만 안 보이게
			local jitter = Vector3.new(math.random() - 0.5, math.random() - 0.5, 0) * shake * 0.4
			pos = head.Position + G.eyeOffset + rot:VectorToWorldSpace(jitter)
			for _, d in c:GetDescendants() do
				if d:IsA("BasePart") or d:IsA("Decal") then
					(d :: any).LocalTransparencyModifier = 1
				end
			end
		else
			local offset = zooming and G.cameraOffset * Vector3.new(0.6, 0.5, 0.3) or G.cameraOffset
			local jitter = Vector3.new(math.random() - 0.5, math.random() - 0.5, 0) * shake
			pos = head.Position + rot:VectorToWorldSpace(offset + jitter)
		end
		cam.CFrame = CFrame.lookAt(pos, pos + rot.LookVector) * CFrame.Angles(0, 0, (math.random() - 0.5) * shake * 0.08)
		local fov = (zooming and def and def.zoomFov or DEFAULT_FOV) + fovKick
		cam.FieldOfView += (fov - cam.FieldOfView) * math.min(dt * 14, 1)
		-- 조준경 화면 + 흐림 (흐린 만큼 탄이 튐)
		updateScopeBlur(def, dt, md.Magnitude)
		local scopeOn = zooming and def ~= nil and def.scopeOverlay == true
		scope.Visible = scopeOn
		cross.Visible = not zooming -- 조준(우클릭) 중엔 십자선 없음 (가늠자/스코프로 조준)
		if scopeOn then
			-- 휙 돌리면 렌즈가 반대로 살짝 밀렸다 돌아옴 + 가장자리 그림자 진해짐
			scopeShift += Vector2.new(-md.X, -md.Y) * G.scopeShift
			if scopeShift.Magnitude > G.scopeShiftMax then
				scopeShift = scopeShift.Unit * G.scopeShiftMax
			end
			scopeShift -= scopeShift * math.min(dt * G.scopeShiftReturn, 1)
			local h = scope.AbsoluteSize.Y
			-- 줌 켤 때: 렌즈가 작고 그림자 짙음 → 열리며 선명해짐
			local s = 0.9 * (1 - 0.12 * scopeBlur)
			scope.Size = UDim2.fromScale(s, s)
			scope.Position = UDim2.new(0.5, scopeShift.X, 0.5, scopeShift.Y)
			local shade = math.max(scopeBlur, turnBlur * 0.8)
			for i, ring in vignetteRings do
				ring.Thickness = h * (0.016 + 0.035 * shade) * (1 + i * 0.1)
			end
			scopeDarkIn.BackgroundTransparency = 1 - scopeBlur * 0.7
		else
			scopeShift = Vector2.zero
		end
		-- 1인칭 내 무기
		if G.firstPerson and def then
			ViewModel.Set(def.id)
			local boltProgress = nil
			if nowT < boltUntil and def.boltTime then
				boltProgress = 1 - (boltUntil - nowT) / def.boltTime
			end
			-- 장전 진행도 (0~1): 장전이 시작된 순간부터 reloadTime 동안
			local reloading = player:GetAttribute("Reloading") == true
			if reloading and not reloadStart then
				reloadStart = nowT
				-- 리볼버: 실린더가 열리면 빈 탄피 6개가 쏟아짐
				if ViewModel.CylinderPosition() then
					task.delay(def.reloadTime * 0.3, function()
						local p = ViewModel.CylinderPosition()
						if p then
							for _ = 1, 6 do
								GunFX.Shell(p, Vector3.new(math.random() - 0.5, -1, math.random() - 0.5) * 0.4, -Vector3.yAxis * 0.3, { shell = "rifle" })
							end
						end
					end)
				end
			elseif not reloading then
				reloadStart = nil
			end
			ViewModel.Update(cam, {
				ads = zooming and not scopeOn,
				hidden = scopeOn,
				mouseDelta = md,
				bolt = boltProgress,
				boltAction = def.boltTime ~= nil, -- 볼트식(스나): 손잡이 들기/내리기까지
				reload = reloadStart and math.clamp((nowT - reloadStart) / def.reloadTime, 0, 1) or nil,
				dt = dt,
			})
		end
		-- 조준점 벌어짐 (쏠수록 벌어졌다 모임)
		-- 조준점 간격 = 실제 탄 퍼짐 범위 그대로 (화면 픽셀로 환산) + 쏠 때 살짝 벌어지는 연출
		local spreadPx = 0
		if def then
			local half = math.rad(cam.FieldOfView / 2)
			spreadPx = math.tan(math.rad(currentSpread(def))) / math.tan(half) * cam.ViewportSize.Y / 2
		end
		local gap = 6 + math.min(spreadPx, 220) + bloom * 8
		-- 조준점도 총이 튄 만큼 위로/옆으로 (총알이 가는 곳 그대로)
		if G.firstPerson then
			local kp, ky = ViewModel.AimKick()
			local f = cam.ViewportSize.Y / 2 / math.tan(math.rad(cam.FieldOfView / 2))
			cross.Position = UDim2.new(0.5, -math.tan(ky) * f, 0.5, -math.tan(kp) * f)
		end
		for i, arm in crossArms do
			local o = CROSS_DIRS[i]
			arm.Position = UDim2.new(0.5, o[1] * gap, 0.5, o[2] * gap)
		end
		if holding and def and def.auto then
			fire()
		end
		-- 탄약 표시
		local ammo = player:GetAttribute("Ammo")
		if player:GetAttribute("Reloading") then
			ammoText.Text = (def and def.name or "") .. "  장전 중..."
		elseif nowT < boltUntil then
			ammoText.Text = (def and def.name or "") .. "  볼트 당기는 중..."
		else
			ammoText.Text = string.format("%s  %s / %d", def and def.name or "", tostring(ammo or "-"), def and def.magazine or 0)
		end
	end)
end

local function exit()
	active = false
	gui.Enabled = false
	holding, zooming, rmbDown = false, false, false
	if scopedSent then
		scopedSent = false
		Remote:FireServer("Scope", false)
	end
	scope.Visible = false
	cross.Visible = true
	turnBlur, scopeBlur = 0, 0
	ViewModel.Destroy()
	-- 1인칭에서 숨겼던 내 몸 다시 보이게
	if player.Character then
		for _, d in player.Character:GetDescendants() do
			if d:IsA("BasePart") or d:IsA("Decal") then
				(d :: any).LocalTransparencyModifier = 0
			end
		end
	end
	for _, c in conns do
		c:Disconnect()
	end
	table.clear(conns)
	RunService:UnbindFromRenderStep(BIND)
	UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	UserInputService.MouseIconEnabled = true
	local cam = workspace.CurrentCamera
	cam.FieldOfView = DEFAULT_FOV
	cam.CameraType = Enum.CameraType.Custom
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if hum and hum.Health > 0 then
		cam.CameraSubject = hum
	end
end

-- 보조석 들어가고 나오기 (잠깐 좌석 판정이 흔들려도 바로 나가지 않게 0.25초 기다림)
local lostFor = 0
RunService.Heartbeat:Connect(function(dt)
	local char, _, vehicle = gunner()
	if char then
		lostFor = 0
		if not active then
			enter(char, vehicle)
		end
	elseif active then
		lostFor += dt
		if lostFor > 0.25 then
			exit()
		end
	end
end)

----------------------------------------------------------------------
-- 서버 알림
----------------------------------------------------------------------

Remote.OnClientEvent:Connect(function(kind, a, b, c, d)
	if kind == "Shot" then
		-- 다른 보조수가 쏜 총알 줄기 (그 사람 총구에서)
		local shooter = a :: Player
		local shooterChar = shooter and shooter.Character
		local from = muzzlePos(shooterChar) or b
		if typeof(from) == "Vector3" and typeof(c) == "Vector3" then
			-- 맞은 게 뭔지 내 화면에서 살짝 확인 (불똥 종류)
			local params = RaycastParams.new()
			params.FilterType = Enum.RaycastFilterType.Exclude
			params.FilterDescendantsInstances = shooterChar and { shooterChar, workspace.CurrentCamera } or { workspace.CurrentCamera }
			local dir = c - from
			local res = dir.Magnitude > 0.1 and workspace:Raycast(from, dir * 1.03, params) or nil
			shotFX(shooterChar, type(d) == "string" and d or nil, from, c, res and res.Instance, res and res.Normal, true)
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
