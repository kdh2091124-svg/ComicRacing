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

-- 날리기: 처음 한 번 깔끔하게 (위 + 달리던 방향 뒤쪽) + 뒤로 공중제비 회전 → 나머진 물리에 맡김 (자연스러운 포물선)
-- 날아가는 동안엔 팔다리만 박자 맞춰 휘두름 (땡깡). 몸통 궤적은 건드리지 않음.
local function startMotion(char: Model, fling: Vector3)
	local all = parts(char)
	local limbs = {}
	for _, p in all do
		if isLimb(p.Name) then
			table.insert(limbs, p)
		end
	end
	-- 뒤로 도는 공중제비 축 (날아가는 수평 방향에 수직)
	local flat = Vector3.new(fling.X, 0, fling.Z)
	local tumbleAxis = flat.Magnitude > 1 and Vector3.yAxis:Cross(flat.Unit) or Vector3.xAxis
	local tumble = tumbleAxis * Health.bodySpin

	local function launch()
		local done: { [BasePart]: boolean } = {}
		for _, p in all do
			local root = p.AssemblyRootPart or p
			if not done[root] then
				done[root] = true
				root.AssemblyLinearVelocity = fling
				root.AssemblyAngularVelocity = tumble
			end
		end
	end
	launch()

	local t0 = os.clock()
	local frames = 0
	local phases = {}
	for i = 1, #limbs do
		phases[i] = (i % 2 == 0) and math.pi or 0 -- 왼쪽/오른쪽 엇갈려 휘두르기
		phases[i] += math.random() * 0.8
	end
	local conn
	conn = RunService.Heartbeat:Connect(function()
		frames += 1
		local t = os.clock() - t0
		if t > Health.flailTime or not char.Parent then
			conn:Disconnect()
			active[char] = nil
			return
		end
		-- 관절이 풀리는 타이밍 차이 대비: 처음 2프레임만 다시 발사
		if frames <= 2 then
			launch()
		end
		-- 땡깡: 팔다리를 각자 축으로 앞뒤로 크게 휘두름 (박자 엇갈림), 끝으로 갈수록 지침
		local fade = 1 - 0.25 * (t / Health.flailTime)
		local w = 2 * math.pi * Health.flailRate
		for i, limb in limbs do
			local swing = math.sin(w * t + phases[i])
			local axis = limb.CFrame.RightVector
			local wobble = limb.CFrame.LookVector * math.sin(w * 0.73 * t + phases[i] * 1.3) * 0.9
				+ limb.CFrame.UpVector * math.sin(w * 1.31 * t + phases[i] * 2.1) * 0.6 -- 여러 방향으로 정신없이
			limb.AssemblyAngularVelocity = (axis * swing + wobble) * Health.flailSpeed * fade
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
		ball.UpperAngle = 130 -- 크게 꺾여야 휘적거림이 우스꽝스럽게 보임
		ball.TwistLowerAngle = -110
		ball.TwistUpperAngle = 110
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
