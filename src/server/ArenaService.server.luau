-- 아레나 서버 담당
-- 1) 아레나 장치(회전 쟁기 등)의 물리를 서버가 맡게 함
--    안 하면 Roblox 가 가까운 플레이어에게 물리를 넘겨서, 그 사람 화면 기준으로 움직이고 다른 사람에겐 끊겨 보임
--    맵 파트에 Attribute "ServerPhysics" = true 가 붙은 것만 대상
-- 2) 장외 저격: 장외로 나간 차(또는 걸어서 나간 사람)를 막 위 스나이퍼가
--    레이저로 조준 + 락온 → 떨어지다가 "바닥에 닿기 직전" 탕 → 한 방에 폭발
--    락온 중엔 대상에 Attribute "SniperLock" = 스나이퍼 이름 (화면 연출은 클라 LockOnClient)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Arena = require(ReplicatedStorage.Shared.Config.GameplayConfig).Arena
local ArenaBounds = require(script.Parent.ArenaBounds)
local HealthService = require(script.Parent.HealthService)

local function claim(inst: Instance)
	if inst:IsA("BasePart") and inst:GetAttribute("ServerPhysics") and not inst.Anchored then
		pcall(function()
			inst:SetNetworkOwner(nil)
		end)
	end
end

for _, d in workspace:GetDescendants() do
	claim(d)
end
workspace.DescendantAdded:Connect(function(d)
	task.defer(claim, d) -- 부모/속성이 다 붙은 뒤에
end)

----------------------------------------------------------------------
-- 장외 저격
----------------------------------------------------------------------

local function snipers(): { Model }
	local list = {}
	local map = workspace:FindFirstChild("Map")
	if map then
		for _, d in map:GetDescendants() do
			if d:IsA("Model") and d:GetAttribute("Sniper") then
				table.insert(list, d)
			end
		end
	end
	return list
end

local function nearestSniper(pos: Vector3): Model?
	local best, bestD = nil, math.huge
	for _, s in snipers() do
		local d = (s:GetPivot().Position - pos).Magnitude
		if d < bestD then
			best, bestD = s, d
		end
	end
	return best
end

local function aim(sniper: Model, target: Vector3)
	local pivot = sniper:GetPivot()
	local flat = Vector3.new(target.X, pivot.Position.Y, target.Z)
	if (flat - pivot.Position).Magnitude > 1 then
		sniper:PivotTo(CFrame.lookAt(pivot.Position, flat))
	end
end

-- "탕": 그림은 각 화면이 그림 (LockOnClient) → 대상의 "지금" 위치로 정확히 박힘
--   (서버가 그리면 서버가 아는 위치 = 통신 지연만큼 예전 위치라 빗나가 보였음)
local WeaponRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Weapon") :: RemoteEvent
local function fire(sniper: Model?, target: Model, targetPos: Vector3)
	if not sniper then
		return
	end
	aim(sniper, targetPos)
	WeaponRemote:FireAllClients("SniperShot", sniper.Name, target, targetPos)
end

type Lock = {
	target: Model,
	part: BasePart,
	sniper: Model?,
	start: number,
	kill: () -> (),
}
local locks: { [Model]: Lock } = {}

local function clearLock(target: Model)
	locks[target] = nil
	if target.Parent then
		target:SetAttribute("SniperLock", nil)
	end
end

local function startLock(target: Model, part: BasePart, kill: () -> ())
	-- 막 태어났거나 막 일어난 대상은 락온 안 걸림
	local grace = target:GetAttribute("SniperGraceUntil")
	if type(grace) == "number" and os.clock() < grace then
		return
	end
	local sniper = nearestSniper(part.Position)
	locks[target] = { target = target, part = part, sniper = sniper, start = os.clock(), kill = kill }
	target:SetAttribute("SniperLock", sniper and sniper.Name or "")
end

-- 쏠 때인가: 최소 조준 시간 지났고, 다음 shotLead 초 안에 바닥(ShotY) 또는 아래 땅에 닿을 것 같으면
local function shouldFire(lock: Lock, now: number): boolean
	local t = now - lock.start
	if t >= Arena.maxLock then
		return true
	end
	if t < Arena.minLock then
		return false
	end
	local pos = lock.part.Position
	local vel = lock.part.AssemblyLinearVelocity
	local lead = Arena.shotLead + Arena.checkInterval
	local shotY = ArenaBounds.ShotY()
	if shotY and pos.Y + math.min(vel.Y, 0) * lead <= shotY then
		return true
	end
	if vel.Y < -1 then
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { lock.target }
		local hit = workspace:Raycast(pos, Vector3.new(0, vel.Y * lead - 6, 0), params)
		if hit then
			return true
		end
	end
	return false
end

-- 새로 태어난 캐릭터 / 새로 나온 차는 잠깐 락온 안 걸림
local function giveGrace(inst: Instance)
	inst:SetAttribute("SniperGraceUntil", os.clock() + Arena.respawnGrace)
end
local function watchPlayer(p: Player)
	p.CharacterAdded:Connect(giveGrace)
	if p.Character then
		giveGrace(p.Character)
	end
end
Players.PlayerAdded:Connect(watchPlayer)
for _, p in Players:GetPlayers() do
	watchPlayer(p)
end
task.spawn(function()
	local vehicles = workspace:WaitForChild("Vehicles")
	vehicles.ChildAdded:Connect(giveGrace)
end)

local acc = 0
RunService.Heartbeat:Connect(function(dt)
	acc += dt
	if acc < Arena.checkInterval then
		return
	end
	acc = 0
	if not ArenaBounds.IsArena() then
		return
	end
	local now = os.clock()

	-- 새로 장외로 나간 대상 찾기
	local vehicles = workspace:FindFirstChild("Vehicles")
	if vehicles then
		for _, model in vehicles:GetChildren() do
			if model:IsA("Model") and not locks[model]
				and not model:GetAttribute("Exploding") and not model:GetAttribute("Exploded") then
				local chassis = model.PrimaryPart
				if chassis and ArenaBounds.IsOut(chassis.Position) then
					startLock(model, chassis, function()
						HealthService.Explode(model) -- 체력 상관없이 한 방
					end)
				end
			end
		end
	end
	if Arena.shootOnFoot then
		for _, player in Players:GetPlayers() do
			local char = player.Character
			local hum = char and char:FindFirstChildOfClass("Humanoid")
			local root = char and char:FindFirstChild("HumanoidRootPart")
			-- 차에 타고 있으면 차가 대상 (사람만 따로 쏘지 않음), 래그돌로 날아가는 중도 제외
			if char and hum and root and root:IsA("BasePart") and hum.Health > 0 and not hum.SeatPart
				and not locks[char] and not char:GetAttribute("Ragdolled") and ArenaBounds.IsOut(root.Position) then
				startLock(char, root, function()
					hum.Health = 0
				end)
			end
		end
	end

	-- 락온 중인 대상: 스나이퍼가 계속 따라 조준 → 때가 되면 탕
	for target, lock in locks do
		local gone = not target.Parent or not lock.part.Parent
			or target:GetAttribute("Exploding") or target:GetAttribute("Exploded")
		local hum = target:FindFirstChildOfClass("Humanoid")
		if hum and (hum.Health <= 0 or hum.SeatPart) then
			gone = true -- 죽었거나, 부활해서 차에 다시 탐 → 사람 락온 취소 (차가 장외면 차가 따로 락온됨)
		end
		if not gone and not ArenaBounds.IsOut(lock.part.Position) then
			gone = true -- 다시 경기장 안으로 돌아옴 (부활 순간이동 등) → 취소
		end
		if gone then
			clearLock(target)
		elseif shouldFire(lock, now) then
			fire(lock.sniper, target, lock.part.Position)
			clearLock(target)
			lock.kill()
		elseif lock.sniper then
			aim(lock.sniper, lock.part.Position)
		end
	end
end)
