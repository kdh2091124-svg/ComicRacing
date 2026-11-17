-- 래그돌 (클라이언트 쪽): 캐릭터는 내 컴퓨터가 물리를 계산하므로
-- 서버가 관절을 풀어주면 여기서 상태를 "흐물흐물(Physics)" 로 바꾸고 날려 보냄.
-- 래그돌이 되면 팔다리가 각각 따로 움직이는 덩어리라서, 날릴 때 "몸 전체" 파트에 속도를 줘야 제대로 날아감.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local RagdollRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Ragdoll") :: RemoteEvent
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
		end
	elseif kind == "Off" then
		hum:SetStateEnabled(Enum.HumanoidStateType.GettingUp, true)
		hum:ChangeState(Enum.HumanoidStateType.GettingUp)
	end
end)
