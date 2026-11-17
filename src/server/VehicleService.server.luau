-- 차 꺼내기 / 탑승(권한 검사) / 내리기 / 라이트 / 네트워크 소유권.
-- 클라이언트 → 서버: Remotes.VehicleAction(action, ...)
--   "Spawn", vehicleId       차 꺼내기 (지금은 개발용 무료)
--   "Exit"                   내리기 (레이스 중엔 Player Attribute "ExitLocked" 로 막힘 → 6단계)
--   "Lights"                 헤드라이트 토글 (운전자만)
--   "SetPermission", kind, level

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local VehicleConfig = require(Shared.Config.VehicleConfig)
local GameplayConfig = require(Shared.Config.GameplayConfig)
local VehicleFactory = require(script.Parent.VehicleFactory)
local PermissionService = require(script.Parent.PermissionService)
local HealthService = require(script.Parent.HealthService)

local spawnAt -- 아래에서 정의 (HealthService 부활에서도 씀)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local VehicleAction = Remotes:WaitForChild("VehicleAction") :: RemoteEvent
local Notify = Remotes:WaitForChild("Notify") :: RemoteEvent
local VehicleFX = Remotes:WaitForChild("VehicleFX") :: RemoteEvent

local vehiclesFolder = workspace:FindFirstChild("Vehicles") or Instance.new("Folder")
vehiclesFolder.Name = "Vehicles"
vehiclesFolder.Parent = workspace

local spawned: { [Player]: Model } = {}
local lastSpawn: { [Player]: number } = {}

local function notify(player: Player, text: string)
	Notify:FireClient(player, text)
end

local function getHumanoid(player: Player): Humanoid?
	local char = player.Character
	return char and char:FindFirstChildOfClass("Humanoid")
end

local function vehicleOfSeat(seat: Instance?): Model?
	if not seat then
		return nil
	end
	local model = seat:FindFirstAncestorOfClass("Model")
	if model and model:GetAttribute("VehicleId") then
		return model
	end
	return nil
end

local function destroyVehicle(player: Player)
	local old = spawned[player]
	spawned[player] = nil
	if old then
		old:Destroy()
	end
end

local function setLights(model: Model, on: boolean)
	model:SetAttribute("LightsOn", on)
	for _, d in model:GetDescendants() do
		if d:IsA("Light") and d.Parent and string.sub(d.Parent.Name, 1, 9) == "Headlight" then
			d.Enabled = on
		elseif d:IsA("BasePart") and string.sub(d.Name, 1, 9) == "Headlight" then
			d.Material = on and Enum.Material.Neon or Enum.Material.SmoothPlastic
		end
	end
end

local lastDenied: { [Player]: number } = {}

-- 좌석 이벤트 연결: 프롬프트 권한 검사 + 운전석 소유권
local function hookSeats(model: Model)
	local chassis = model.PrimaryPart :: BasePart
	local ownerUserId = model:GetAttribute("OwnerUserId") :: number

	for _, seat in model:GetDescendants() do
		if not seat:IsA("Seat") then
			continue
		end
		local isDriver = seat.Name == "DriverSeat"
		local prompt = seat:FindFirstChild("SeatPrompt") :: ProximityPrompt?

		if prompt then
			prompt.Triggered:Connect(function(player: Player)
				local hum = getHumanoid(player)
				if not hum or hum.Health <= 0 or hum.SeatPart or seat.Occupant then
					return
				end
				local kind = isDriver and "Drive" or "Ride"
				if not PermissionService.CanUse(player, ownerUserId, kind) then
					notify(player, isDriver and "이 차는 운전 권한이 없어요" or "이 차는 탑승 권한이 없어요")
					return
				end
				seat:Sit(hum)
			end)
		end

		-- 탄 사람 무게 없애기: 캐릭터 무게 때문에 차가 눌리거나 앞으로 쏠리지 않게
		local weightless: { BasePart } = {}
		local function restoreWeight()
			for _, p in weightless do
				if p.Parent then
					p.Massless = false
				end
			end
			table.clear(weightless)
		end

		seat:GetPropertyChangedSignal("Occupant"):Connect(function()
			if prompt then
				prompt.Enabled = seat.Occupant == nil
			end
			restoreWeight()
			-- 동승석은 닿으면 바로 앉으니까, 앉은 뒤에 권한 검사 → 권한 없으면 차 옆으로 내려놓음
			if not isDriver and seat.Occupant then
				local occ = seat.Occupant
				local rider = Players:GetPlayerFromCharacter(occ.Parent)
				if rider and not PermissionService.CanUse(rider, ownerUserId, "Ride") then
					task.defer(function()
						local w = seat:FindFirstChild("SeatWeld")
						if w then
							w:Destroy()
						end
						occ.Sit = false
						local char = occ.Parent
						if char and chassis.Parent then
							local side = chassis.Size.X / 2 + 5
							char:PivotTo(CFrame.new(chassis.CFrame:PointToWorldSpace(Vector3.new(side, 1, 0))))
						end
					end)
					local now = os.clock()
					if not lastDenied[rider] or now - lastDenied[rider] > 2 then
						lastDenied[rider] = now
						notify(rider, "이 차는 탑승 권한이 없어요")
					end
					return
				end
			end
			local sitter = seat.Occupant and seat.Occupant.Parent
			if sitter then
				for _, p in sitter:GetDescendants() do
					if p:IsA("BasePart") and not p.Massless then
						p.Massless = true
						table.insert(weightless, p)
					end
				end
			end
			if not isDriver or not chassis:IsDescendantOf(workspace) then
				return
			end
			local occupant = seat.Occupant
			local driver = occupant and Players:GetPlayerFromCharacter(occupant.Parent)
			-- 운전자가 바뀌면 이펙트 상태 초기화
			model:SetAttribute("FX_Drift", false)
			model:SetAttribute("FX_Tier", 0)
			model:SetAttribute("FX_Boost", false)
			-- 운전 중엔 서스펜션이 받치므로 주차 받침 충돌 끔
			for _, d in model:GetChildren() do
				if d.Name == "ParkingSupport" and d:IsA("BasePart") then
					d.CanCollide = occupant == nil
				end
			end
			-- 운전자에게 소유권 → 렉 없이 부드럽게. (서버 속도/순간이동 검사는 6단계 레이스에서 추가)
			pcall(function()
				chassis:SetNetworkOwner(driver)
			end)
		end)
	end
end

-- 정해진 위치에 차를 새로 만들어 놓음 (기존 차는 없앰). 폭발 후 부활에서도 씀
function spawnAt(player: Player, vehicleId: string, cframe: CFrame): Model?
	if not VehicleConfig.Get(vehicleId) then
		return nil
	end
	destroyVehicle(player)
	local model = VehicleFactory.Build(vehicleId, player.UserId, nil)
	model:PivotTo(cframe)
	model.Name = player.Name .. "_" .. vehicleId
	model.Parent = vehiclesFolder
	hookSeats(model)
	HealthService.SetupVehicle(model)
	spawned[player] = model
	return model
end

local function spawnVehicle(player: Player, vehicleId: any)
	if type(vehicleId) ~= "string" or not VehicleConfig.Get(vehicleId) then
		return
	end
	if not GameplayConfig.Vehicle.devFreeVehicles then
		-- TODO(4단계): 보유한 차인지 검사
		notify(player, "아직 구매 시스템이 없어요")
		return
	end
	local now = os.clock()
	if lastSpawn[player] and now - lastSpawn[player] < GameplayConfig.Vehicle.spawnCooldown then
		return
	end
	if player:GetAttribute("ExitLocked") then
		return -- 레이스 중
	end
	local hum = getHumanoid(player)
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hum or not root or hum.Health <= 0 then
		return
	end
	lastSpawn[player] = now

	if hum.SeatPart then
		hum.Sit = false
		task.wait(0.1)
	end
	local look = root.CFrame.LookVector * Vector3.new(1, 0, 1)
	if look.Magnitude < 0.01 then
		look = Vector3.new(0, 0, -1)
	end
	look = look.Unit
	local def = VehicleConfig.Get(vehicleId)
	local len = def and def.placeholder.size.Z or 8
	local pos = root.Position + look * (len / 2 + 6) + Vector3.new(0, 4, 0)
	spawnAt(player, vehicleId, CFrame.lookAt(pos, pos + look))
end

-- 차 밖 빈 곳 찾기: 운전석 왼쪽 → 오른쪽 → 앞 → 뒤 순서로, 막혀 있지 않은 곳
local function findExitSpot(model: Model, seat: BasePart, char: Model): CFrame?
	local chassis = model.PrimaryPart
	if not chassis then
		return nil
	end
	local half = chassis.Size / 2
	local seatLocal = chassis.CFrame:PointToObjectSpace(seat.Position)
	local candidates = {
		Vector3.new(-(half.X + 3), 0, seatLocal.Z), -- 왼쪽 (운전석 문)
		Vector3.new(half.X + 3, 0, seatLocal.Z), -- 오른쪽
		Vector3.new(0, 0, -(half.Z + 4)), -- 앞
		Vector3.new(0, 0, half.Z + 4), -- 뒤
	}
	local overlap = OverlapParams.new()
	overlap.FilterType = Enum.RaycastFilterType.Exclude
	overlap.FilterDescendantsInstances = { model, char }
	local ray = RaycastParams.new()
	ray.FilterType = Enum.RaycastFilterType.Exclude
	ray.FilterDescendantsInstances = { model, char }
	local flatLook = chassis.CFrame.LookVector * Vector3.new(1, 0, 1)
	flatLook = flatLook.Magnitude > 0.01 and flatLook.Unit or Vector3.new(0, 0, -1)
	for _, offset in candidates do
		local p = chassis.CFrame:PointToWorldSpace(offset) + Vector3.new(0, 2, 0)
		local blocked = #workspace:GetPartBoundsInBox(CFrame.new(p + Vector3.new(0, 1.5, 0)), Vector3.new(2.5, 4.5, 2.5), overlap) > 0
		if not blocked then
			local hit = workspace:Raycast(p + Vector3.new(0, 3, 0), Vector3.new(0, -20, 0), ray)
			local ground = hit and hit.Position or p
			local standAt = ground + Vector3.new(0, 3, 0)
			return CFrame.lookAt(standAt, standAt + flatLook)
		end
	end
	return nil
end

local function exitVehicle(player: Player)
	if player:GetAttribute("ExitLocked") then
		notify(player, "레이스 중에는 내릴 수 없어요")
		return
	end
	local hum = getHumanoid(player)
	if not hum or not hum.SeatPart then
		return
	end
	local seat = hum.SeatPart
	local model = vehicleOfSeat(seat)
	-- 달리는 중엔 못 내림 (속도를 줄이면 내릴 수 있음)
	if model and model:GetAttribute("Exploding") then
		return -- 터지기 직전 정지 중엔 못 내림
	end
	if model and model.PrimaryPart and not model:GetAttribute("Exploded") then
		local speed = model.PrimaryPart.AssemblyLinearVelocity.Magnitude
		if speed > GameplayConfig.Vehicle.exitMaxSpeed then
			notify(player, "속도를 줄여야 내릴 수 있어요")
			return
		end
	end
	local char = player.Character
	local spot = model and char and findExitSpot(model, seat, char)
	local w = seat:FindFirstChild("SeatWeld")
	if w then
		w:Destroy()
	end
	hum.Sit = false
	if char then
		task.defer(function()
			if spot then
				char:PivotTo(spot)
			elseif model and model.PrimaryPart then
				-- 빈 곳이 없으면 차 위로
				char:PivotTo(CFrame.new(model.PrimaryPart.Position + Vector3.new(0, model.PrimaryPart.Size.Y + 4, 0)))
			end
		end)
	end
end

local function toggleLights(player: Player)
	local hum = getHumanoid(player)
	local seat = hum and hum.SeatPart
	if not seat or seat.Name ~= "DriverSeat" then
		return
	end
	local model = vehicleOfSeat(seat)
	if model then
		setLights(model, not model:GetAttribute("LightsOn"))
	end
end

VehicleAction.OnServerEvent:Connect(function(player: Player, action: any, a: any, b: any)
	if action == "Spawn" then
		spawnVehicle(player, a)
	elseif action == "Exit" then
		exitVehicle(player)
	elseif action == "Lights" then
		toggleLights(player)
	elseif action == "SetPermission" then
		PermissionService.Set(player, a, b)
	end
end)

-- 이펙트 중계: 운전자가 보낸 드리프트/부스터 상태를 모델 Attribute 로, 충돌 스파크는 다른 사람들에게
local lastImpactRelay: { [Player]: number } = {}
local lastHazard: { [Player]: number } = {}
VehicleFX.OnServerEvent:Connect(function(player: Player, kind: any, a: any, b: any, c: any)
	local hum = getHumanoid(player)
	local seat = hum and hum.SeatPart
	if not seat or seat.Name ~= "DriverSeat" then
		return
	end
	local model = vehicleOfSeat(seat)
	if not model or not model.PrimaryPart then
		return
	end
	if kind == "State" then
		model:SetAttribute("FX_Drift", a == true)
		model:SetAttribute("FX_Tier", (type(b) == "number") and math.clamp(math.floor(b), 0, 3) or 0)
		model:SetAttribute("FX_Boost", c == true)
	elseif kind == "Damage" then
		-- 충돌 데미지 (운전자 화면이 계산). 상한은 HealthService 가 검사
		if type(a) == "number" and a == a then
			HealthService.Damage(model, a)
		end
	elseif kind == "Lava" then
		local now = os.clock()
		if not lastHazard[player] or now - lastHazard[player] >= 0.2 then
			lastHazard[player] = now
			HealthService.Damage(model, GameplayConfig.Health.lavaDps * 0.25)
		end
	elseif kind == "Drown" then
		if model.PrimaryPart.Position.Y < GameplayConfig.Health.drownY + 5 then
			HealthService.Explode(model)
		end
	elseif kind == "Impact" then
		if typeof(a) ~= "Vector3" or (a - model.PrimaryPart.Position).Magnitude > 40 then
			return
		end
		local now = os.clock()
		if lastImpactRelay[player] and now - lastImpactRelay[player] < 0.2 then
			return
		end
		lastImpactRelay[player] = now
		local strength = (type(b) == "number") and math.clamp(b, 0, 1.5) or 1
		for _, other in Players:GetPlayers() do
			if other ~= player then
				VehicleFX:FireClient(other, "Impact", model, a, strength)
			end
		end
	end
end)

HealthService.Start(vehiclesFolder, spawnAt)

Players.PlayerAdded:Connect(PermissionService.Init)
for _, p in Players:GetPlayers() do
	PermissionService.Init(p)
end

Players.PlayerRemoving:Connect(function(player)
	destroyVehicle(player)
	lastSpawn[player] = nil
	lastImpactRelay[player] = nil
	lastDenied[player] = nil
	lastHazard[player] = nil
end)
