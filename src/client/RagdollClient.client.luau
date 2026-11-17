-- 래그돌 (클라이언트 쪽): 날리기/휘적거리기는 서버가 직접 함 (Ragdoll.luau).
-- 여기서는 내 화면의 캐릭터 상태만 맞춰줌: 좌석에서 떼고, 흐물흐물(Physics) 상태 / 일어나기.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RagdollRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Ragdoll") :: RemoteEvent
local player = Players.LocalPlayer

RagdollRemote.OnClientEvent:Connect(function(kind: string)
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not char or not hum then
		return
	end
	if kind == "On" then
		-- 내 화면에 좌석 연결이 남아 있으면 떼기
		local seat = hum.SeatPart
		local w = seat and seat:FindFirstChild("SeatWeld")
		if w then
			w:Destroy()
		end
		hum.Sit = false
		hum:SetStateEnabled(Enum.HumanoidStateType.GettingUp, false)
		hum:ChangeState(Enum.HumanoidStateType.Physics)
	elseif kind == "Off" then
		hum:SetStateEnabled(Enum.HumanoidStateType.GettingUp, true)
		hum:ChangeState(Enum.HumanoidStateType.GettingUp)
	end
end)
