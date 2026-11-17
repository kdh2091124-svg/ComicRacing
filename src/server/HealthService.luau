-- 차량 HP / 대폭발 / 부활 (서버).
--   • 데미지: 운전자 화면이 충돌 세기를 보고 → 서버가 상한 검사 후 적용
--     (차 물리를 운전자 컴퓨터가 계산하므로 충돌은 거기서 가장 정확함. 자기 차 데미지라 속여도 이득 없음)
--   • 회복: 데미지 후 regenDelay 초 동안 멈췄다가 초당 regenPerSecond
--   • HP 0 → 대폭발: 탄 사람 전부 래그돌로 날아감, 차는 조각나서 흩어짐
--   • 오픈월드: respawnDelay 초 뒤 마지막 안전 위치에서 차와 함께 부활 (운전자만 자동 탑승)
-- 모델 Attribute: HP, MaxHP (클라이언트 HP 바가 읽음)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")

local Health = require(ReplicatedStorage.Shared.Config.GameplayConfig).Health
local Ragdoll = require(script.Parent.Ragdoll)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local VehicleFX = Remotes:WaitForChild("VehicleFX") :: RemoteEvent

local HealthService = {}

type Info = { lastDamage: number, safeCFrame: CFrame?, lastSafeCheck: number }
local info: { [Model]: Info } = {}

-- VehicleService 가 넣어줌: (player, vehicleId, cframe) -> Model?
local respawnFn: ((Player, string, CFrame) -> Model?)? = nil

local function getInfo(model: Model): Info
	local i = info[model]
	if not i then
		i = { lastDamage = 0, safeCFrame = nil, lastSafeCheck = 0 }
		info[model] = i
	end
	return i
end

function HealthService.SetupVehicle(model: Model)
	local maxHp = model:GetAttribute("Stat_hp") or 100
	model:SetAttribute("MaxHP", maxHp)
	model:SetAttribute("HP", maxHp)
	getInfo(model)
	model.Destroying:Connect(function()
		info[model] = nil
	end)
end

local function occupantsOf(model: Model): { Humanoid }
	local list = {}
	for _, seat in model:GetDescendants() do
		if seat:IsA("Seat") and seat.Occupant then
			table.insert(list, seat.Occupant)
		end
	end
	return list
end

local function explode(model: Model, frozen: { BasePart }?, savedVel: Vector3?)
	if model:GetAttribute("Exploded") then
		return
	end
	model:SetAttribute("Exploded", true)
	model:SetAttribute("HP", 0)
	-- 정지(히트스톱) 풀기
	for _, p in frozen or {} do
		if p.Parent then
			p.Anchored = false
		end
	end
	local chassis = model.PrimaryPart
	if not chassis then
		model:Destroy()
		return
	end
	local pos = chassis.Position
	local carVel = savedVel or chassis.AssemblyLinearVelocity
	local ownerId = model:GetAttribute("OwnerUserId")
	local vehicleId = model:GetAttribute("VehicleId")
	local safe = getInfo(model).safeCFrame

	-- 0) 탄 사람 목록을 "먼저" 확보 (좌석을 끄면 로블록스가 바로 내려버려서 목록이 비어버림)
	local riders: { { hum: Humanoid, seat: BasePart } } = {}
	for _, seat in model:GetDescendants() do
		if seat:IsA("Seat") and seat.Occupant then
			table.insert(riders, { hum = seat.Occupant, seat = seat })
		end
	end
	-- 그 다음 좌석 전부 비활성화: 날아가는 좌석 파편에 다시 앉아버리는 것 방지
	for _, seat in model:GetDescendants() do
		if seat:IsA("Seat") then
			seat.CanTouch = false
			seat.Disabled = true
		end
	end

	-- 1) 탄 사람 전부 내리고 래그돌로 날리기
	for _, r in riders do
		local hum = r.hum
		-- 운전석/동승석 모두 "자동으로 내림" 판정: 좌석 연결 끊고, 차 몸통에 안 걸리게 살짝 위로 빼냄
		local seat = r.seat
		local weld = seat and seat:FindFirstChild("SeatWeld")
		if weld then
			weld:Destroy()
		end
		hum.Sit = false
		local char = hum.Parent
		if char and char:IsA("Model") and seat then
			char:PivotTo(CFrame.new(seat.Position + Vector3.new(0, 3, 0)) * (char:GetPivot() - char:GetPivot().Position))
		end
		local player = Players:GetPlayerFromCharacter(hum.Parent)
		if player then
			-- 차 몸통과 같이 하늘로 (차 발사 방향 + 약간 옆으로 랜덤)
			local a = math.random() * math.pi * 2
			local fling = carVel * 0.3
				+ Vector3.new(math.cos(a) * Health.flingSide, Health.flingUp, math.sin(a) * Health.flingSide)
			Ragdoll.Enable(player, fling)
		end
	end

	-- 2) 폭발 연출 (모두에게): 로블록스 기본 폭발 그림 + 클라이언트 큰 불덩이
	local boom = Instance.new("Explosion")
	boom.Position = pos
	boom.BlastRadius = 14
	boom.BlastPressure = 0 -- 실제 밀어내기는 우리가 직접 (기본 폭발은 사람을 죽일 수 있어서)
	boom.DestroyJointRadiusPercent = 0
	boom.ExplosionType = Enum.ExplosionType.NoCraters
	boom.Parent = workspace
	VehicleFX:FireAllClients("Explode", model, pos)

	-- 3) 차 조각내서 흩어지게
	pcall(function()
		chassis:SetNetworkOwner(nil)
	end)
	for _, d in model:GetDescendants() do
		if d:IsA("JointInstance") or d:IsA("WeldConstraint") or d:IsA("ProximityPrompt")
			or d:IsA("VectorForce") or d:IsA("Torque") then
			d:Destroy()
		end
	end
	for _, p in model:GetDescendants() do
		if p:IsA("BasePart") then
			if p.Name == "ParkingSupport" or p.Name == "CarScratch" then
				p:Destroy()
			else
				p.Anchored = false
				p.Massless = false
				p.CanCollide = true
				local dir = (p.Position - pos)
				if dir.Magnitude < 0.1 then
					dir = Vector3.new(math.random() - 0.5, 0, math.random() - 0.5)
				end
				dir = (dir * Vector3.new(1, 0, 1) + Vector3.new(0, 0.001, 0)).Unit
				local up = Health.debrisUp * (0.7 + math.random() * 0.6)
				p.AssemblyLinearVelocity = carVel * 0.3 + dir * Health.debrisSpeed * (0.6 + math.random() * 0.8) + Vector3.new(0, up, 0)
				p.AssemblyAngularVelocity = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * 30
			end
		end
	end
	-- 차체(몸통)는 하늘로 크게 튀어오르며 빙글빙글
	chassis.AssemblyLinearVelocity = carVel * 0.3 + Vector3.new(0, Health.chassisLaunch, 0)
	chassis.AssemblyAngularVelocity = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * 18
	model.Name = model.Name .. "_Wreck"
	Debris:AddItem(model, Health.debrisTime)

	-- 4) 부활 (오픈월드: 근처 안전 위치에서 차와 함께, 운전자 자동 탑승)
	local owner = ownerId and Players:GetPlayerByUserId(ownerId)
	task.delay(Health.respawnDelay, function()
		-- 날아간 사람들 다시 일으키기
		for _, p in Players:GetPlayers() do
			if p.Character and p.Character:GetAttribute("Ragdolled") then
				local root = p.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
				if root and (root.Position - pos).Magnitude < 400 then
					Ragdoll.Disable(p)
				end
			end
		end
		if owner and owner.Parent and respawnFn and type(vehicleId) == "string" then
			local spot = safe or CFrame.new(pos)
			local yawOnly = CFrame.lookAt(spot.Position, spot.Position + (spot.LookVector * Vector3.new(1, 0, 1) + Vector3.new(0, 0, -0.001)).Unit)
			local newModel = respawnFn(owner, vehicleId, yawOnly + Vector3.new(0, 4, 0))
			local hum = owner.Character and owner.Character:FindFirstChildOfClass("Humanoid")
			local seat = newModel and newModel:FindFirstChild("DriverSeat") :: Seat?
			if hum and seat and hum.Health > 0 then
				task.wait(0.1)
				seat:Sit(hum)
			end
		end
	end)
end

function HealthService.Damage(model: Model, amount: number)
	if model:GetAttribute("Exploded") or amount <= 0 then
		return
	end
	local hp = model:GetAttribute("HP")
	if type(hp) ~= "number" then
		return
	end
	hp = math.max(hp - math.min(amount, Health.maxPerHit), 0)
	model:SetAttribute("HP", hp)
	getInfo(model).lastDamage = os.clock()
	if hp <= 0 then
		HealthService.Explode(model)
	end
end

-- 2단 폭발: "틱" (차가 하얗게 번쩍 + 화면 살짝 하얗게) → tickDelay 뒤 "파아앙"
function HealthService.Explode(model: Model)
	if model:GetAttribute("Exploding") or model:GetAttribute("Exploded") then
		return
	end
	model:SetAttribute("Exploding", true) -- 이 동안 못 내림 (VehicleService 가 검사)
	model:SetAttribute("HP", 0)
	local chassis = model.PrimaryPart
	local savedVel = chassis and chassis.AssemblyLinearVelocity or Vector3.zero

	-- 히트스톱: 박은 그 순간 차 + 탄 사람 전부 그 자리에 "정지"
	local frozen: { BasePart } = {}
	for _, p in model:GetDescendants() do
		if p:IsA("BasePart") and not p.Anchored then
			p.Anchored = true
			table.insert(frozen, p)
		end
	end
	for _, hum in occupantsOf(model) do
		local root = hum.Parent and hum.Parent:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") and not root.Anchored then
			root.Anchored = true
			table.insert(frozen, root)
		end
	end

	VehicleFX:FireAllClients("PreExplode", model, chassis and chassis.Position or Vector3.zero, Health.tickDelay)
	task.delay(Health.tickDelay, function()
		if model.Parent then
			explode(model, frozen, savedVel)
		else
			for _, p in frozen do
				if p.Parent then
					p.Anchored = false
				end
			end
		end
	end)
end

function HealthService.Start(vehiclesFolder: Folder, respawn: (Player, string, CFrame) -> Model?)
	respawnFn = respawn
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc < 0.25 then
			return
		end
		local step = acc
		acc = 0
		local now = os.clock()
		for _, model in vehiclesFolder:GetChildren() do
			if not model:IsA("Model") or model:GetAttribute("Exploded") then
				continue
			end
			local i = getInfo(model)
			-- 회복
			local hp, maxHp = model:GetAttribute("HP"), model:GetAttribute("MaxHP")
			if type(hp) == "number" and type(maxHp) == "number" and hp < maxHp and now - i.lastDamage >= Health.regenDelay then
				model:SetAttribute("HP", math.min(hp + Health.regenPerSecond * step, maxHp))
			end
			-- 부활 위치 기록: 땅 위에 똑바로, 너무 낮지 않은 곳
			local chassis = model.PrimaryPart
			if chassis and now - i.lastSafeCheck >= Health.safeSpotInterval then
				i.lastSafeCheck = now
				local cf = chassis.CFrame
				if cf.UpVector.Y > 0.85 and cf.Position.Y > Health.drownY + 10
					and chassis.AssemblyLinearVelocity.Y > -20 then
					i.safeCFrame = cf
				end
			end
		end
	end)
end

return HealthService
