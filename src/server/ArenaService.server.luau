-- 아레나 서버 담당
-- 1) 아레나 장치(회전 쟁기 등)의 물리를 서버가 맡게 함
--    안 하면 Roblox 가 가까운 플레이어에게 물리를 넘겨서, 그 사람 화면 기준으로 움직이고 다른 사람에겐 끊겨 보임
--    맵 파트에 Attribute "ServerPhysics" = true 가 붙은 것만 대상
-- 2) 장외 저격: 장외로 나간 차(또는 걸어서 나간 사람)를 막 위 스나이퍼가 쏴서 한 방에 터뜨림

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")

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

local function fx(name: string, size: Vector3, cf: CFrame, color: Color3, life: number, shape: Enum.PartType?)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	p.Color = color
	p.Size = size
	p.CFrame = cf
	if shape then
		p.Shape = shape
	end
	p.Parent = workspace
	Debris:AddItem(p, life)
end

-- 가장 가까운 스나이퍼가 target 쪽으로 몸을 돌리고 "탕" (총구 섬광 + 총알 줄기)
local function shootAt(target: Vector3)
	local best, bestD = nil, math.huge
	for _, s in snipers() do
		local d = (s:GetPivot().Position - target).Magnitude
		if d < bestD then
			best, bestD = s, d
		end
	end
	if not best then
		return
	end
	local pivot = best:GetPivot()
	local flat = Vector3.new(target.X, pivot.Position.Y, target.Z)
	if (flat - pivot.Position).Magnitude > 1 then
		best:PivotTo(CFrame.lookAt(pivot.Position, flat))
	end
	local muzzle = best:FindFirstChild("Muzzle")
	local from = muzzle and (muzzle :: BasePart).Position or pivot.Position
	local dist = (target - from).Magnitude
	fx("SniperTracer", Vector3.new(0.6, 0.6, dist), CFrame.lookAt((from + target) / 2, target), Color3.fromRGB(255, 240, 150), Arena.tracerTime)
	fx("MuzzleFlash", Vector3.one * 5, CFrame.new(from), Color3.fromRGB(255, 200, 80), 0.08, Enum.PartType.Ball)
	fx("HitFlash", Vector3.one * 6, CFrame.new(target), Color3.fromRGB(255, 255, 255), 0.08, Enum.PartType.Ball)
end

local targeted: { [Instance]: boolean } = {} -- 같은 대상 두 번 안 쏘게

local function snipeVehicle(model: Model)
	targeted[model] = true
	task.delay(Arena.sniperDelay, function()
		local chassis = model.PrimaryPart
		if model.Parent and chassis and not model:GetAttribute("Exploded") then
			shootAt(chassis.Position)
			HealthService.Explode(model) -- 체력 상관없이 한 방
		end
		task.delay(3, function()
			targeted[model] = nil
		end)
	end)
end

local function snipeCharacter(char: Model, hum: Humanoid, root: BasePart)
	targeted[char] = true
	task.delay(Arena.sniperDelay, function()
		if char.Parent and hum.Health > 0 then
			shootAt(root.Position)
			hum.Health = 0
		end
		task.delay(3, function()
			targeted[char] = nil
		end)
	end)
end

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
	local vehicles = workspace:FindFirstChild("Vehicles")
	if vehicles then
		for _, model in vehicles:GetChildren() do
			if model:IsA("Model") and not targeted[model]
				and not model:GetAttribute("Exploding") and not model:GetAttribute("Exploded") then
				local chassis = model.PrimaryPart
				if chassis and ArenaBounds.IsOut(chassis.Position) then
					snipeVehicle(model)
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
				and not targeted[char] and not char:GetAttribute("Ragdolled") and ArenaBounds.IsOut(root.Position) then
				snipeCharacter(char, hum, root)
			end
		end
	end
end)
