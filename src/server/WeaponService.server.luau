-- 보조수 무기 (서버)
-- • 동승석(PassengerSeat…)에 앉으면 총을 쥐어줌, 내리면 뺏음
-- • 클라가 "어디를 맞혔다" 보고 → 서버가 검사(연사 속도/탄창/거리/위치) 후 피해
--   사람 = Humanoid 체력 (운전수/보조수 언제든 맞을 수 있음), 차 = 차 HP (HealthService)
-- • 콜라캐논 = 서버가 탄을 날려서 터지면 범위 피해 + 차 밀어내기
-- • 죽으면 respawnTime 뒤 부활 → 자기 차가 살아 있으면 원래 좌석에 다시 앉힘
--   (운전수가 죽어 있는 동안 그 차는 운전 불가 = 멈춤)
-- Remotes.Weapon:
--   클라→서버 "Fire", origin, hitPart?, hitPos   /  "FireProjectile", origin, dir
--              "Reload"  /  "Select", weaponId (개발용: 1~4 키)
--   서버→클라 "Shot", shooter, from, to, weaponId  /  "Hit", kind, killed  /  "Knock", model, velocity

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")

local WeaponConfig = require(ReplicatedStorage.Shared.Config.WeaponConfig)
local HealthService = require(script.Parent.HealthService)
local G = WeaponConfig.General

local Remote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Weapon") :: RemoteEvent
local vehiclesFolder = workspace:WaitForChild("Vehicles")

Players.RespawnTime = G.respawnTime

type State = { weapon: string, ammo: number, reloadUntil: number, lastShot: number }
local states: { [Player]: State } = {}

local function isGunnerSeat(seat: Instance?): boolean
	return seat ~= nil and seat:IsA("Seat") and seat.Name:match("^PassengerSeat") ~= nil
end

local function vehicleOf(inst: Instance?): Model?
	while inst and inst.Parent ~= vehiclesFolder do
		inst = inst.Parent
	end
	return inst and inst:IsA("Model") and inst or nil
end

local function gunnerInfo(player: Player)
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 or not isGunnerSeat(hum.SeatPart) then
		return nil
	end
	return char, hum, vehicleOf(hum.SeatPart)
end

----------------------------------------------------------------------
-- 총 쥐어주기 (보이는 모델)
----------------------------------------------------------------------

local function placeholderGun(): Model
	local m = Instance.new("Model")
	local body = Instance.new("Part")
	body.Name = "Handle"
	body.Size = Vector3.new(0.4, 0.6, 3)
	body.Color = Color3.fromRGB(35, 35, 40)
	body.Material = Enum.Material.Metal
	body.Parent = m
	local muzzle = Instance.new("Attachment")
	muzzle.Name = "Muzzle"
	muzzle.Position = Vector3.new(0, 0.1, -1.5)
	muzzle.Parent = body
	m.PrimaryPart = body
	return m
end

local function unequip(char: Model)
	local old = char:FindFirstChild("GunnerWeapon")
	if old then
		old:Destroy()
	end
end

local function equip(player: Player, char: Model, weaponId: string)
	unequip(char)
	local def = WeaponConfig.Get(weaponId)
	if not def then
		return
	end
	states[player] = { weapon = weaponId, ammo = def.magazine, reloadUntil = 0, lastShot = 0 }
	player:SetAttribute("GunnerWeapon", weaponId)
	player:SetAttribute("Ammo", def.magazine)
	player:SetAttribute("Reloading", false)

	local hand = char:FindFirstChild("RightHand") or char:FindFirstChild("Right Arm")
	if not hand or not hand:IsA("BasePart") then
		return
	end
	local folder = ReplicatedStorage:FindFirstChild("WeaponModels")
	local template = folder and folder:FindFirstChild(weaponId)
	local gun = Instance.new("Model")
	gun.Name = "GunnerWeapon"
	local src: Instance = template and template:Clone() or placeholderGun()
	for _, c in src:GetChildren() do
		c.Parent = gun -- Tool 이든 Model 이든 안의 것만 (Tool 로 쥐면 백팩/클릭이 끼어들어서)
	end
	for _, d in gun:GetDescendants() do
		if d:IsA("Script") or d:IsA("LocalScript") then
			d:Destroy()
		elseif d:IsA("BasePart") then
			d.Anchored = false
			d.CanCollide = false
			d.CanQuery = false -- 내 총에 내 총알이 막히지 않게
			d.CanTouch = false
			d.Massless = true
		end
	end
	local handle = gun:FindFirstChild("Handle", true)
	if not (handle and handle:IsA("BasePart")) then
		handle = gun:FindFirstChildWhichIsA("BasePart", true)
	end
	if not handle then
		return
	end
	gun.PrimaryPart = handle :: BasePart
	-- 손 끝에 손잡이, 총열은 팔이 뻗는 방향 (모델 받으면 각도 맞춤)
	gun:PivotTo(hand.CFrame * CFrame.new(0, -hand.Size.Y / 2, 0) * CFrame.Angles(-math.pi / 2, 0, 0))
	for _, p in gun:GetDescendants() do
		if p:IsA("BasePart") then
			local w = Instance.new("WeldConstraint")
			w.Part0, w.Part1 = hand, p
			w.Parent = p
		end
	end
	gun.Parent = char
end

local function onSeatChanged(seat: Seat)
	local hum = seat.Occupant
	if hum then
		local char = hum.Parent
		local player = char and Players:GetPlayerFromCharacter(char)
		if player and char and isGunnerSeat(seat) then
			local id = player:GetAttribute("GunnerWeapon")
			equip(player, char :: Model, type(id) == "string" and WeaponConfig.Get(id) and id or WeaponConfig.DefaultGunnerWeapon)
		end
	end
end

-- 좌석 기억: 죽어서 부활하면 원래 좌석에 다시 앉힘
local crewSeat: { [Player]: Seat } = {}

local function hookSeat(seat: Instance)
	if not seat:IsA("Seat") then
		return
	end
	local last: Humanoid? = nil
	seat:GetPropertyChangedSignal("Occupant"):Connect(function()
		local hum = seat.Occupant
		if hum then
			local player = Players:GetPlayerFromCharacter(hum.Parent)
			if player then
				crewSeat[player] = seat
			end
		elseif last then
			-- 살아서 스스로 내린 거면 좌석 기억 지움 (죽어서 떨어진 거면 유지)
			local player = Players:GetPlayerFromCharacter(last.Parent)
			if player and last.Health > 0 and crewSeat[player] == seat then
				crewSeat[player] = nil
			end
			if last.Parent and last.Parent:IsA("Model") then
				unequip(last.Parent)
			end
		end
		last = hum
		onSeatChanged(seat)
	end)
end

vehiclesFolder.DescendantAdded:Connect(hookSeat)
for _, d in vehiclesFolder:GetDescendants() do
	hookSeat(d)
end

local function onCharacter(player: Player, char: Model)
	local seat = crewSeat[player]
	if not seat then
		return
	end
	local model = vehicleOf(seat)
	local hum = char:WaitForChild("Humanoid", 5) :: Humanoid?
	task.wait(0.3)
	if hum and hum.Health > 0 and model and model.Parent and seat.Parent and not seat.Occupant
		and not model:GetAttribute("Exploding") and not model:GetAttribute("Exploded") then
		char:PivotTo(seat.CFrame + Vector3.new(0, 3, 0))
		seat:Sit(hum)
	else
		crewSeat[player] = nil
	end
end

local function watchPlayer(player: Player)
	player.CharacterAdded:Connect(function(char)
		onCharacter(player, char)
	end)
end
Players.PlayerAdded:Connect(watchPlayer)
for _, p in Players:GetPlayers() do
	watchPlayer(p)
end
Players.PlayerRemoving:Connect(function(p)
	states[p] = nil
	crewSeat[p] = nil
end)

----------------------------------------------------------------------
-- 피해
----------------------------------------------------------------------

local function sameCrew(a: Model?, b: Model?): boolean
	return not G.friendlyFire and a ~= nil and a == b
end

local function damagePerson(shooter: Player, hum: Humanoid, amount: number): boolean
	if hum.Health <= 0 then
		return false
	end
	hum:SetAttribute("LastAttacker", shooter.UserId)
	hum:TakeDamage(amount)
	return hum.Health <= 0
end

local function damageCar(shooter: Player, model: Model, amount: number): boolean
	if model:GetAttribute("Exploded") then
		return false
	end
	model:SetAttribute("LastAttacker", shooter.UserId)
	HealthService.Damage(model, amount)
	local hp = model:GetAttribute("HP")
	return type(hp) == "number" and hp <= 0
end

-- 맞은 파트 → 사람인지 차인지
local function resolve(part: BasePart)
	local model = part:FindFirstAncestorOfClass("Model")
	while model do
		local hum = model:FindFirstChildOfClass("Humanoid")
		if hum then
			return "person", model, hum
		end
		if model.Parent == vehiclesFolder then
			return "car", model, nil
		end
		model = model:FindFirstAncestorOfClass("Model")
	end
	return nil
end

local function canFire(player: Player, def): (boolean, State?)
	local st = states[player]
	if not st or st.weapon ~= def.id then
		return false
	end
	local now = os.clock()
	if now < st.reloadUntil or st.ammo <= 0 then
		return false
	end
	if now - st.lastShot < (1 / def.fireRate) * 0.8 then -- 통신 흔들림 조금 봐줌
		return false
	end
	return true, st
end

local function consume(player: Player, st: State, def)
	st.ammo -= 1
	st.lastShot = os.clock()
	player:SetAttribute("Ammo", st.ammo)
	if st.ammo <= 0 then
		st.reloadUntil = os.clock() + def.reloadTime
		player:SetAttribute("Reloading", true)
		task.delay(def.reloadTime, function()
			if states[player] == st then
				st.ammo = def.magazine
				player:SetAttribute("Ammo", st.ammo)
				player:SetAttribute("Reloading", false)
			end
		end)
	end
end

----------------------------------------------------------------------
-- 콜라캐논 (날아가는 탄)
----------------------------------------------------------------------

type Shell = { pos: Vector3, vel: Vector3, owner: Player, def: any, part: BasePart, traveled: number, ignore: { Instance } }
local shells: { Shell } = {}

local function explodeShell(s: Shell, at: Vector3)
	s.part:Destroy()
	local boom = Instance.new("Explosion")
	boom.Position = at
	boom.BlastRadius = s.def.splashRadius
	boom.BlastPressure = 0
	boom.DestroyJointRadiusPercent = 0
	boom.Parent = workspace
	local fizz = Instance.new("Part")
	fizz.Shape = Enum.PartType.Ball
	fizz.Anchored = true
	fizz.CanCollide = false
	fizz.CanQuery = false
	fizz.Material = Enum.Material.Neon
	fizz.Color = Color3.fromRGB(150, 80, 40)
	fizz.Transparency = 0.4
	fizz.Size = Vector3.one * s.def.splashRadius
	fizz.CFrame = CFrame.new(at)
	fizz.Parent = workspace
	Debris:AddItem(fizz, 0.15)

	local shooterVehicle = s.owner.Character and vehicleOf(s.owner.Character:FindFirstChildOfClass("Humanoid") and s.owner.Character:FindFirstChildOfClass("Humanoid").SeatPart)
	local r = s.def.splashRadius
	local hitAny, killed = false, false
	for _, p in Players:GetPlayers() do
		local char = p.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		local root = char and char:FindFirstChild("HumanoidRootPart")
		if hum and root and root:IsA("BasePart") and p ~= s.owner then
			local d = (root.Position - at).Magnitude
			if d < r and not sameCrew(vehicleOf(hum.SeatPart), shooterVehicle) then
				hitAny = true
				killed = damagePerson(s.owner, hum, s.def.damage * (1 - 0.6 * d / r)) or killed
			end
		end
	end
	for _, model in vehiclesFolder:GetChildren() do
		local chassis = model:IsA("Model") and model.PrimaryPart
		if chassis and model ~= shooterVehicle then
			local d = (chassis.Position - at).Magnitude - chassis.Size.Magnitude / 2
			if d < r then
				local fall = 1 - 0.6 * math.max(d, 0) / r
				hitAny = true
				killed = damageCar(s.owner, model, s.def.carDamage * fall) or killed
				-- 밀어내기: 터진 곳에서 멀어지는 쪽 + 살짝 위로
				local away = chassis.Position - at
				away = Vector3.new(away.X, 0, away.Z)
				away = (away.Magnitude > 0.1 and away.Unit or Vector3.xAxis) + Vector3.new(0, 0.45, 0)
				local push = away.Unit * s.def.knockback * fall
				local owner = chassis:GetNetworkOwner()
				if owner then
					Remote:FireClient(owner, "Knock", model, push) -- 운전자 화면이 물리 담당
				else
					chassis.AssemblyLinearVelocity += push
				end
			end
		end
	end
	if hitAny then
		Remote:FireClient(s.owner, "Hit", "splash", killed)
	end
end

RunService.Heartbeat:Connect(function(dt)
	for i = #shells, 1, -1 do
		local s = shells[i]
		local step = s.vel * dt
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = s.ignore
		local hit = workspace:Raycast(s.pos, step, params)
		s.traveled += step.Magnitude
		if hit or s.traveled > s.def.range or not s.part.Parent then
			table.remove(shells, i)
			explodeShell(s, hit and hit.Position or s.pos + step)
		else
			s.pos += step
			s.vel += Vector3.new(0, -workspace.Gravity * s.def.projectileGravity * dt, 0)
			s.part.CFrame = CFrame.lookAt(s.pos, s.pos + s.vel)
		end
	end
end)

----------------------------------------------------------------------
-- 클라 요청
----------------------------------------------------------------------

Remote.OnServerEvent:Connect(function(player, action, a, b, c)
	if action == "Select" then
		if type(a) == "string" and WeaponConfig.Get(a) then
			player:SetAttribute("GunnerWeapon", a)
			local char, _, _ = gunnerInfo(player)
			if char then
				equip(player, char, a)
			end
		end
		return
	elseif action == "Reload" then
		local st = states[player]
		local def = st and WeaponConfig.Get(st.weapon)
		if st and def and st.ammo < def.magazine and os.clock() >= st.reloadUntil then
			st.reloadUntil = os.clock() + def.reloadTime
			player:SetAttribute("Reloading", true)
			task.delay(def.reloadTime, function()
				if states[player] == st then
					st.ammo = def.magazine
					player:SetAttribute("Ammo", st.ammo)
					player:SetAttribute("Reloading", false)
				end
			end)
		end
		return
	end

	local char, hum, myVehicle = gunnerInfo(player)
	if not char or not hum then
		return
	end
	local st0 = states[player]
	local def = st0 and WeaponConfig.Get(st0.weapon)
	if not def or typeof(a) ~= "Vector3" then
		return
	end
	local head = char:FindFirstChild("Head") :: BasePart?
	if not head or (a - head.Position).Magnitude > G.originTolerance then
		return
	end
	local ok, st = canFire(player, def)
	if not ok or not st then
		return
	end

	if action == "Fire" and def.kind == "hitscan" then
		local hitPart, hitPos = b, c
		if typeof(hitPos) ~= "Vector3" or (hitPos - a).Magnitude > def.range + 10 then
			return
		end
		consume(player, st, def)
		-- 다른 사람들 화면에 총알 줄기
		for _, p in Players:GetPlayers() do
			if p ~= player then
				Remote:FireClient(p, "Shot", player, a, hitPos, def.id)
			end
		end
		if typeof(hitPart) ~= "Instance" or not hitPart:IsA("BasePart") or not hitPart:IsDescendantOf(workspace) then
			return
		end
		if (hitPos - hitPart.Position).Magnitude > hitPart.Size.Magnitude / 2 + G.hitTolerance then
			return -- 맞았다는 위치가 그 파트와 너무 멂 → 무효
		end
		local kind, target, targetHum = resolve(hitPart)
		if kind == "person" and targetHum and target ~= char then
			if sameCrew(vehicleOf(targetHum.SeatPart), myVehicle) then
				return
			end
			local mult = hitPart.Name == "Head" and def.headMultiplier or 1
			local killed = damagePerson(player, targetHum, def.damage * mult)
			Remote:FireClient(player, "Hit", mult > 1 and "head" or "person", killed)
		elseif kind == "car" and target and target ~= myVehicle then
			local killed = damageCar(player, target, def.carDamage)
			Remote:FireClient(player, "Hit", "car", killed)
		end
	elseif action == "FireProjectile" and def.kind == "projectile" then
		if typeof(b) ~= "Vector3" or b.Magnitude < 0.5 then
			return
		end
		consume(player, st, def)
		local dir = b.Unit
		local part = Instance.new("Part")
		part.Name = "ColaShell"
		part.Shape = Enum.PartType.Ball
		part.Size = Vector3.one * 1.6
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.Color = def.projectileColor or Color3.fromRGB(120, 60, 30)
		part.Material = Enum.Material.Glass
		part.CFrame = CFrame.new(a)
		part.Parent = workspace
		local ignore: { Instance } = { char, part }
		if myVehicle then
			table.insert(ignore, myVehicle)
		end
		table.insert(shells, { pos = a, vel = dir * def.projectileSpeed, owner = player, def = def, part = part, traveled = 0, ignore = ignore })
	end
end)
