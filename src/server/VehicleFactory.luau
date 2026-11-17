-- 차 모델 만들기.
-- 1) ReplicatedStorage.VehicleModels.<id> 가 있으면 복제
-- 2) 없으면 VehicleConfig.placeholder(크기/색)로 임시 상자 차 생성
-- 그 다음 Rig(): 용접, 좌석, 프롬프트, 라이트, 능력치 Attribute 설정.
-- 모델 규칙은 docs/MODEL_RULES.md 참고.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local VehicleConfig = require(Shared.Config.VehicleConfig)
local StatCalculator = require(Shared.StatCalculator)

local VehicleFactory = {}

local WHEEL_PREFIX = "Wheel_" -- 보이는 바퀴 파트 (그림 전용)
local SUSP_PREFIX = "Susp_" -- 물리 서스펜션 위치 (Chassis 안의 Attachment)

local function newPart(props: { [string]: any }): Part
	local p = Instance.new("Part")
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in props do
		(p :: any)[k] = v
	end
	return p
end

-- 모델이 없을 때 쓰는 임시 차
local function buildPlaceholder(def, stats): Model
	local size: Vector3 = def.placeholder.size
	local model = Instance.new("Model")
	model.Name = def.id

	local chassis = newPart({
		Name = "Chassis",
		Size = Vector3.new(size.X, math.max(size.Y, 1), size.Z),
		Color = def.placeholder.color,
		Material = Enum.Material.SmoothPlastic,
		CFrame = CFrame.new(),
	})
	chassis.Parent = model
	model.PrimaryPart = chassis

	-- 보이는 바퀴 (그림 전용): 차체 네 모서리, 주차 상태에서 땅에 닿는 높이
	local r = stats.wheelRadius
	local groundY = -chassis.Size.Y / 2 + VehicleConfig.BaseLayout.mountAboveBottom
		- (stats.suspensionRest + r - workspace.Gravity / stats.suspensionStiffness)
	local hx = size.X / 2 + 0.4
	local hz = math.max(size.Z / 2 - r, 0.8)
	local visuals = {
		Wheel_FL = Vector3.new(-hx, groundY + r, -hz),
		Wheel_FR = Vector3.new(hx, groundY + r, -hz),
		Wheel_RL = Vector3.new(-hx, groundY + r, hz),
		Wheel_RR = Vector3.new(hx, groundY + r, hz),
	}
	for name, pos in visuals do
		local wheel = newPart({
			Name = name,
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.8, r * 2, r * 2),
			Color = Color3.fromRGB(30, 30, 30),
			CFrame = CFrame.new(pos),
		})
		wheel.Parent = model
	end

	-- 좌석: 운전석 맨 앞, 동승석은 뒤로 2열씩
	local topY = chassis.Size.Y / 2 + 0.5
	local seatCount = math.max(def.seats, 1)
	local rows = math.ceil(seatCount / 2)
	local usableZ = math.max(size.Z - 2, 2)
	local rowGap = rows > 1 and usableZ / rows or 0
	local startZ = -usableZ / 2 + 1
	for i = 1, seatCount do
		local seat = Instance.new("Seat")
		seat.Name = i == 1 and "DriverSeat" or ("PassengerSeat" .. (i - 1))
		seat.Size = Vector3.new(2, 1, 2)
		seat.Color = Color3.fromRGB(50, 50, 50)
		seat.TopSurface = Enum.SurfaceType.Smooth
		local row = math.floor((i - 1) / 2)
		local side = ((i - 1) % 2 == 0) and -1 or 1
		local x = (seatCount == 1) and 0 or side * math.min(size.X / 4, 1.5)
		seat.CFrame = CFrame.new(x, topY, startZ + row * rowGap)
		seat.Parent = model
	end

	-- 헤드라이트 2개 (앞면 = -Z)
	for _, side in { -1, 1 } do
		local light = newPart({
			Name = "Headlight",
			Size = Vector3.new(0.6, 0.4, 0.2),
			Color = Color3.fromRGB(255, 250, 220),
			Material = Enum.Material.SmoothPlastic,
			CFrame = CFrame.new(side * size.X / 3, 0, -size.Z / 2 - 0.1),
		})
		local spot = Instance.new("SpotLight")
		spot.Face = Enum.NormalId.Front
		spot.Range = 45
		spot.Angle = 70
		spot.Brightness = 3
		spot.Enabled = false
		spot.Parent = light
		light.Parent = model
	end

	-- 이름표 (임시 차 구분용)
	local bb = Instance.new("BillboardGui")
	bb.Name = "PlaceholderLabel"
	bb.Size = UDim2.fromOffset(160, 30)
	bb.StudsOffset = Vector3.new(0, size.Y / 2 + 3, 0)
	bb.MaxDistance = 80
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.TextScaled = true
	label.Font = Enum.Font.GothamBold
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.3
	label.Text = def.name .. " (임시)"
	label.Parent = bb
	bb.Parent = chassis

	return model
end

-- 공통 장착: 어떤 모델이든 이 규칙대로 정리
local function rig(model: Model, def, stats, ownerUserId: number)
	local chassis = model:FindFirstChild("Chassis") :: BasePart
	assert(chassis and chassis:IsA("BasePart"), def.id .. ": Chassis 파트가 없음 (MODEL_RULES 참고)")
	model.PrimaryPart = chassis

	chassis.Anchored = false
	chassis.CanCollide = true
	-- 차체 마찰 거의 0 (가중치를 크게 줘서 벽 마찰보다 우선) → 벽에 걸려서 휙 돌아가는 것 방지
	chassis.CustomPhysicalProperties = PhysicalProperties.new(stats.density, 0.02, 0.1, 100, 1)

	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and d ~= chassis then
			d.Anchored = false
			d.Massless = true
			if not d:GetAttribute("KeepCollision") then
				d.CanCollide = false
			end

			local isWheel = string.sub(d.Name, 1, #WHEEL_PREFIX) == WHEEL_PREFIX
			if isWheel then
				-- 보이는 바퀴: 클라이언트가 C0 를 움직여 출렁임/회전/조향을 그림으로만 표현
				local w = Instance.new("Weld")
				w.Name = "WheelWeld"
				w.Part0 = chassis
				w.Part1 = d
				w.C0 = chassis.CFrame:ToObjectSpace(d.CFrame)
				w.Parent = d
			else
				local wc = Instance.new("WeldConstraint")
				wc.Part0 = chassis
				wc.Part1 = d
				wc.Parent = d
			end

			if d:IsA("Seat") and d.Name ~= "DriverSeat" then
				-- 동승석: 가까이 가서 닿으면 바로 앉음 (권한은 VehicleService 가 앉은 뒤 검사)
				d.CanTouch = true
			elseif d:IsA("Seat") then
				-- 운전석: 닿기만 해선 안 앉고 E 프롬프트로만 (차 뺏기 방지 + 실수로 앉는 것 방지)
				d.CanTouch = false
				local prompt = Instance.new("ProximityPrompt")
				prompt.Name = "SeatPrompt"
				prompt.ActionText = "운전하기"
				prompt.ObjectText = def.name
				prompt.KeyboardKeyCode = Enum.KeyCode.E
				prompt.RequiresLineOfSight = false
				prompt.MaxActivationDistance = 10
				prompt.Parent = d
			end
		end
	end

	assert(model:FindFirstChild("DriverSeat"), def.id .. ": DriverSeat 가 없음")

	-- 물리용 서스펜션 위치: 모든 차 공통 배치 (BaseLayout) + 차 크기에 따라 조금만 조정.
	-- 모델에 Susp_ 어태치먼트가 이미 있으면 그걸 그대로 씀 (특수한 차용).
	if not chassis:FindFirstChild("Susp_FL") then
		local L = VehicleConfig.BaseLayout
		local custom = def.layout or {}
		local function scaled(base: number, actual: number): number
			local s = 1 + (actual / base - 1) * L.sizeInfluence
			return base * math.clamp(s, L.minScale, L.maxScale)
		end
		local track = custom.track or scaled(L.track, chassis.Size.X)
		local wheelbase = custom.wheelbase or scaled(L.wheelbase, chassis.Size.Z)
		local y = -chassis.Size.Y / 2 + L.mountAboveBottom
		local mounts = {
			Susp_FL = Vector3.new(-track / 2, y, -wheelbase / 2),
			Susp_FR = Vector3.new(track / 2, y, -wheelbase / 2),
			Susp_RL = Vector3.new(-track / 2, y, wheelbase / 2),
			Susp_RR = Vector3.new(track / 2, y, wheelbase / 2),
		}
		for name, pos in mounts do
			local att = Instance.new("Attachment")
			att.Name = name
			att.Position = pos
			att.Parent = chassis
		end
	end

	-- 주차 받침: 아무도 안 탔을 때 서스펜션이 꺼져 차가 주저앉는 것 방지.
	-- 바퀴 바닥 높이에 보이지 않는 받침을 두고, 운전자가 타면 VehicleService 가 충돌을 끈다.
	local drop = stats.suspensionRest + stats.wheelRadius - workspace.Gravity / stats.suspensionStiffness
	for _, att in chassis:GetChildren() do
		if att:IsA("Attachment") and string.sub(att.Name, 1, #SUSP_PREFIX) == SUSP_PREFIX then
			local support = Instance.new("Part")
			support.Name = "ParkingSupport"
			support.Size = Vector3.new(1, 0.4, 1)
			support.Transparency = 1
			support.Massless = true
			support.CanCollide = true
			support.CanQuery = false
			support.CanTouch = false
			support.CustomPhysicalProperties = PhysicalProperties.new(1, 1.5, 0, 100, 1)
			support.CFrame = chassis.CFrame * CFrame.new(att.Position - Vector3.new(0, drop - 0.2, 0))
			local wc = Instance.new("WeldConstraint")
			wc.Part0 = chassis
			wc.Part1 = support
			wc.Parent = support
			support.Parent = model
		end
	end

	model:SetAttribute("VehicleId", def.id)
	model:SetAttribute("OwnerUserId", ownerUserId)
	model:SetAttribute("LightsOn", false)
	StatCalculator.WriteToModel(model, stats)
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic -- 차 전체가 한 번에 로드되게
end

function VehicleFactory.Build(vehicleId: string, ownerUserId: number, tuning: any?): Model
	local def = VehicleConfig.Get(vehicleId)
	assert(def, "VehicleFactory: 없는 차 id " .. tostring(vehicleId))
	local stats = StatCalculator.Compute(vehicleId, tuning)

	local folder = ReplicatedStorage:FindFirstChild("VehicleModels")
	local template = folder and folder:FindFirstChild(vehicleId)
	local model: Model
	if template and template:IsA("Model") then
		model = template:Clone()
	else
		model = buildPlaceholder(def, stats)
	end

	rig(model, def, stats, ownerUserId)
	return model
end

return VehicleFactory
