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
			-- 거의 옆으로만 꺾임 (위로 계속 더해지면 우주까지 날아감)
			local a = math.random() * math.pi * 2
			local kick = Vector3.new(math.cos(a), (math.random() - 0.5) * 0.3, math.sin(a)) * Health.wobbleKick * fade
			for _, p in all do
				local v = p.AssemblyLinearVelocity + kick
				-- 위로 올라가는 속도는 처음 날린 것보다 커지지 않게
				p.AssemblyLinearVelocity = Vector3.new(v.X, math.min(v.Y, fling.Y), v.Z)
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
	local function addSocket(a0: Attachment, a1: Attachment, parent: Instance)
		local ball = Instance.new("BallSocketConstraint")
		ball.Name = TAG
		ball.Attachment0 = a0
		ball.Attachment1 = a1
		ball.LimitsEnabled = true
		ball.TwistLimitsEnabled = true
		ball.UpperAngle = 95 -- 크게 꺾여야 휘적거림이 잘 보임
		ball.TwistLowerAngle = -75
		ball.TwistUpperAngle = 75
		ball.Parent = parent
	end
	for _, joint in char:GetDescendants() do
		if joint:IsA("Motor6D") and joint.Part0 and joint.Part1 and joint.Enabled then
			-- 예전 방식 관절
			local a0 = Instance.new("Attachment")
			a0.Name = TAG
			a0.CFrame = joint.C0
			a0.Parent = joint.Part0
			local a1 = Instance.new("Attachment")
			a1.Name = TAG
			a1.CFrame = joint.C1
			a1.Parent = joint.Part1
			addSocket(a0, a1, joint.Part0)
			joint.Enabled = false
			joint:SetAttribute("RagdollDisabled", true)
		elseif joint:IsA("AnimationConstraint") and joint.Enabled and joint.Attachment0 and joint.Attachment1 then
			-- 새 방식 관절 (최신 아바타): 같은 위치에 공 관절을 만들고 원래 관절은 끔
			addSocket(joint.Attachment0, joint.Attachment1, joint.Parent or char)
			joint.Enabled = false
			joint:SetAttribute("RagdollDisabled", true)
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
		elseif d:GetAttribute("RagdollDisabled") then
			(d :: any).Enabled = true -- 예전/새 방식 관절 다시 켜기
			d:SetAttribute("RagdollDisabled", nil)
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
