-- 래그돌 (클라이언트 쪽): 캐릭터는 내 컴퓨터가 물리를 계산하므로
-- 서버가 관절을 풀어주면 여기서 상태를 "흐물흐물(Physics)" 로 바꾸고 날려 보냄.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RagdollRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Ragdoll") :: RemoteEvent
local player = Players.LocalPlayer

RagdollRemote.OnClientEvent:Connect(function(kind: string, fling: Vector3?)
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hum or not root then
		return
	end
	if kind == "On" then
		hum:SetStateEnabled(Enum.HumanoidStateType.GettingUp, false)
		hum:ChangeState(Enum.HumanoidStateType.Physics)
		if typeof(fling) == "Vector3" then
			root.AssemblyLinearVelocity = fling
			root.AssemblyAngularVelocity = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * 25
		end
	elseif kind == "Off" then
		hum:SetStateEnabled(Enum.HumanoidStateType.GettingUp, true)
		hum:ChangeState(Enum.HumanoidStateType.GettingUp)
	end
end)
