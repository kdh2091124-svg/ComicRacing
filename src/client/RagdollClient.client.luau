-- 래그돌 (클라이언트 쪽): 캐릭터는 내 컴퓨터가 물리를 계산하므로
-- 서버가 관절을 풀어주면 여기서 상태를 "흐물흐물(Physics)" 로 바꾸고 날려 보냄.
-- 래그돌이 되면 팔다리가 각각 따로 움직이는 덩어리라서, 날릴 때 "몸 전체" 파트에 속도를 줘야 제대로 날아감.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local RagdollRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Ragdoll") :: RemoteEvent
local Health = require(ReplicatedStorage:WaitForChild("Shared").Config.GameplayConfig).Health
local startFlail -- 아래에서 정의
local player = Players.LocalPlayer

local function pushAll(char: Model, fling: Vector3, spin: Vector3)
	for _, p in char:GetDescendants() do
		if p:IsA("BasePart") then
			-- 부위마다 살짝 다르게 → 팔다리가 흐느적
			local jitter = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * 12
			p.AssemblyLinearVelocity = fling + jitter
			p.AssemblyAngularVelocity = spin
		end
	end
end

-- 땡깡 휘적휘적: 날아가는 동안 팔다리를 아주 빠르게 마구 돌림
local flailing = false
local function isLimb(name: string): boolean
	return string.find(name, "Arm") ~= nil or string.find(name, "Leg") ~= nil
		or string.find(name, "Hand") ~= nil or string.find(name, "Foot") ~= nil
end

function startFlail(char: Model)
	flailing = true
	local limbs: { BasePart } = {}
	for _, p in char:GetDescendants() do
		if p:IsA("BasePart") and isLimb(p.Name) then
			table.insert(limbs, p)
		end
	end
	local body: { BasePart } = {}
	for _, p in char:GetDescendants() do
		if p:IsA("BasePart") and not isLimb(p.Name) then
			table.insert(body, p)
		end
	end
	local t0 = os.clock()
	local nextWobble = Health.wobbleInterval
	local conn
	conn = RunService.Heartbeat:Connect(function()
		local t = os.clock() - t0
		if not flailing or t > Health.flailTime or not char.Parent then
			conn:Disconnect()
			return
		end
		-- 혹시 어디 좌석에 다시 앉아버렸으면 바로 빼냄
		local hum = char:FindFirstChildOfClass("Humanoid")
		if hum and hum.SeatPart then
			local w = hum.SeatPart:FindFirstChild("SeatWeld")
			if w then
				w:Destroy()
			end
			hum.Sit = false
			hum:ChangeState(Enum.HumanoidStateType.Physics)
		end
		-- 끝으로 갈수록 조금씩 지쳐서 느려짐
		local fade = 1 - 0.6 * (t / Health.flailTime)
		local power = Health.flailSpeed * fade

		-- 플링 궤적: 일정 간격으로 날아가는 방향이 확 꺾임 (몸 전체에 같은 속도를 더해서 몸은 같이 감)
		if t >= nextWobble then
			nextWobble += Health.wobbleInterval * (0.6 + math.random() * 0.8)
			local a = math.random() * math.pi * 2
			local kick = Vector3.new(math.cos(a), (math.random() - 0.35), math.sin(a)) * Health.wobbleKick * fade
			for _, p in char:GetDescendants() do
				if p:IsA("BasePart") then
					p.AssemblyLinearVelocity += kick
				end
			end
		end
		-- 몸통은 빙글빙글
		local spin = Vector3.new(math.noise(t * 2, 7, 0), math.noise(0, t * 2, 7), math.noise(7, 0, t * 2)) * Health.bodySpin * 2 * fade
		for _, p in body do
			p.AssemblyAngularVelocity = spin
		end
		for i, limb in limbs do
			local f = t * Health.flailRate
			limb.AssemblyAngularVelocity = Vector3.new(
				math.noise(f, i * 1.7, 0),
				math.noise(i * 2.3, f, 0),
				math.noise(0, i * 3.1, f)
			) * power * 2
		end
	end)
end

RagdollRemote.OnClientEvent:Connect(function(kind: string, fling: Vector3?)
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not char or not hum then
		return
	end
	if kind == "On" then
		-- 아직 좌석에 붙어 있으면 내 화면에서 먼저 떼기 (안 떼면 속도가 차로 들어감)
		for _, d in char:GetDescendants() do
			if d:IsA("Weld") and d.Name == "SeatWeld" then
				d:Destroy()
			end
		end
		local seat = hum.SeatPart
		if seat then
			local w = seat:FindFirstChild("SeatWeld")
			if w then
				w:Destroy()
			end
		end
		hum.Sit = false
		hum:SetStateEnabled(Enum.HumanoidStateType.GettingUp, false)
		hum:ChangeState(Enum.HumanoidStateType.Physics)
		if typeof(fling) == "Vector3" then
			local spin = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * 30
			-- 몇 프레임 동안 계속 밀어줌 (관절/좌석이 풀리는 타이밍 차이 대비)
			local frames = 0
			local conn
			conn = RunService.Heartbeat:Connect(function()
				frames += 1
				if frames <= 3 and char.Parent then
					pushAll(char, fling, spin)
				else
					conn:Disconnect()
				end
			end)
			pushAll(char, fling, spin)
			startFlail(char)
		end
	elseif kind == "Off" then
		flailing = false
		hum:SetStateEnabled(Enum.HumanoidStateType.GettingUp, true)
		hum:ChangeState(Enum.HumanoidStateType.GettingUp)
	end
end)
