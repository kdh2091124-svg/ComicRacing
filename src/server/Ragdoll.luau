-- 래그돌: 캐릭터 관절(Motor6D)을 풀고 흐물흐물한 공 관절로 바꿈.
-- 날아가는 동안은 "서버가 캐릭터 물리를 직접 맡음" (네트워크 소유권을 서버로)
--   → 차에서 막 내린 순간 소유권이 넘어가는 타이밍에 힘이 씹히는 문제 없이 항상 날아감
--   → 날리기 / 플링 궤적(방향 확확 꺾임) / 몸 빙글빙글 / 팔다리 땡깡 전부 서버에서
-- 일어날 때(Disable) 소유권을 다시 플레이어에게 돌려줌.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local RagdollRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Ragdoll") :: RemoteEvent
local Health = require(ReplicatedStorage.Shared.Config.GameplayConfig).Health

local Ragdoll = {}

local TAG = "RagdollJoint"
local active: { [Model]: RBXScriptConnection } = {}

local function isLimb(name: string): boolean
	return string.find(name, "Arm") ~= nil or string.find(name, "Leg") ~= nil
		or string.find(name, "Hand") ~= nil or string.find(name, "Foot") ~= nil
end

local function parts(char: Model): { BasePart }
	local list = {}
	for _, p in char:GetDescendants() do
		if p:IsA("BasePart") then
			table.insert(list, p)
		end
	end
	return list
end

local function setOwner(char: Model, owner: Player?)
	for _, p in parts(char) do
		pcall(function()
			p:SetNetworkOwner(owner)
		end)
	end
end

-- 날아가는 동안 매 프레임: 플링 꺾임 + 몸 회전 + 팔다리 땡깡
local function startMotion(char: Model, fling: Vector3)
	local all = parts(char)
	local limbs, body = {}, {}
	for _, p in all do
		if isLimb(p.Name) then
			table.insert(limbs, p)
		else
			table.insert(body, p)
		end
	end
	-- 처음 한 번 + 몇 프레임 더 밀어줌
	local function push(v: Vector3)
		for _, p in all do
			local jitter = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * 10
			p.AssemblyLinearVelocity = v + jitter
		end
	end
	push(fling)

	local t0 = os.clock()
	local nextWobble = Health.wobbleInterval
	local frames = 0
	local conn
	conn = RunService.Heartbeat:Connect(function()
		frames += 1
		local t = os.clock() - t0
		if t > Health.flailTime or not char.Parent then
			conn:Disconnect()
			active[char] = nil
			return
		end
		if frames <= 3 then
			push(fling)
		end
		local fade = 1 - 0.6 * (t / Health.flailTime)

		-- 플링 궤적: 일정 간격으로 방향이 확 꺾임 (몸 전체에 같은 속도 → 통째로 꺾임)
		if t >= nextWobble then
			nextWobble += Health.wobbleInterval * (0.6 + math.random() * 0.8)
			local a = math.random() * math.pi * 2
			local kick = Vector3.new(math.cos(a), math.random() - 0.35, math.sin(a)) * Health.wobbleKick * fade
			for _, p in all do
				p.AssemblyLinearVelocity += kick
			end
		end
		-- 몸통 빙글빙글
		local spin = Vector3.new(math.noise(t * 2, 7, 0), math.noise(0, t * 2, 7), math.noise(7, 0, t * 2))
			* Health.bodySpin * 2 * fade
		for _, p in body do
			p.AssemblyAngularVelocity = spin
		end
		-- 팔다리 땡깡 (부위마다 따로, 아주 빠르게)
		local f = t * Health.flailRate
		for i, limb in limbs do
			limb.AssemblyAngularVelocity = Vector3.new(
				math.noise(f, i * 1.7, 0),
				math.noise(i * 2.3, f, 0),
				math.noise(0, i * 3.1, f)
			) * Health.flailSpeed * 2 * fade
		end
	end)
	active[char] = conn
end

function Ragdoll.Enable(player: Player, fling: Vector3)
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not char or not hum or char:GetAttribute("Ragdolled") then
		return
	end
	char:SetAttribute("Ragdolled", true)
	hum.BreakJointsOnDeath = false
	hum.RequiresNeck = false
	hum.Sit = false
	for _, motor in char:GetDescendants() do
		if motor:IsA("Motor6D") and motor.Part0 and motor.Part1 then
			local a0 = Instance.new("Attachment")
			a0.Name = TAG
			a0.CFrame = motor.C0
			a0.Parent = motor.Part0
			local a1 = Instance.new("Attachment")
			a1.Name = TAG
			a1.CFrame = motor.C1
			a1.Parent = motor.Part1
			local ball = Instance.new("BallSocketConstraint")
			ball.Name = TAG
			ball.Attachment0 = a0
			ball.Attachment1 = a1
			ball.LimitsEnabled = true
			ball.TwistLimitsEnabled = true
			ball.UpperAngle = 95 -- 크게 꺾여야 휘적거림이 잘 보임
			ball.TwistLowerAngle = -75
			ball.TwistUpperAngle = 75
			ball.Parent = motor.Part0
			motor.Enabled = false
		end
	end
	for _, p in parts(char) do
		p.Anchored = false
		p.Massless = false
		if p.Name ~= "HumanoidRootPart" then
			p:SetAttribute("RagdollOrigCollide", p.CanCollide)
			p.CanCollide = true
		end
	end
	-- 서버가 물리를 맡고, 흐물흐물 상태로
	setOwner(char, nil)
	hum:SetStateEnabled(Enum.HumanoidStateType.GettingUp, false)
	hum:ChangeState(Enum.HumanoidStateType.Physics)
	RagdollRemote:FireClient(player, "On")
	startMotion(char, fling)
end

function Ragdoll.Disable(player: Player)
	local char = player.Character
	if not char or not char:GetAttribute("Ragdolled") then
		return
	end
	char:SetAttribute("Ragdolled", nil)
	if active[char] then
		active[char]:Disconnect()
		active[char] = nil
	end
	for _, d in char:GetDescendants() do
		if d.Name == TAG then
			d:Destroy()
		elseif d:IsA("Motor6D") then
			d.Enabled = true
		elseif d:IsA("BasePart") and d:GetAttribute("RagdollOrigCollide") ~= nil then
			d.CanCollide = d:GetAttribute("RagdollOrigCollide")
			d:SetAttribute("RagdollOrigCollide", nil)
		end
	end
	local hum = char:FindFirstChildOfClass("Humanoid")
	if hum then
		hum:SetStateEnabled(Enum.HumanoidStateType.GettingUp, true)
		hum:ChangeState(Enum.HumanoidStateType.GettingUp)
	end
	-- 다시 플레이어가 조종하도록 소유권 돌려줌
	setOwner(char, player)
	RagdollRemote:FireClient(player, "Off")
end

return Ragdoll
