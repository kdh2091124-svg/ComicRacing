-- 래그돌: 캐릭터 관절(Motor6D)을 풀고 흐물흐물한 공 관절로 바꿈.
-- 캐릭터는 플레이어 컴퓨터가 물리를 계산하므로, 상태 변경/날려보내기는 클라이언트(RagdollClient)도 같이 함.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RagdollRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Ragdoll") :: RemoteEvent

local Ragdoll = {}

local TAG = "RagdollJoint"

function Ragdoll.Enable(player: Player, fling: Vector3)
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not char or not hum or char:GetAttribute("Ragdolled") then
		return
	end
	char:SetAttribute("Ragdolled", true)
	hum.BreakJointsOnDeath = false
	hum.RequiresNeck = false
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
	for _, p in char:GetDescendants() do
		if p:IsA("BasePart") and p.Name ~= "HumanoidRootPart" then
			p:SetAttribute("RagdollOrigCollide", p.CanCollide) -- 나중에 원래대로
			p.CanCollide = true
		end
	end
	RagdollRemote:FireClient(player, "On", fling)
end

function Ragdoll.Disable(player: Player)
	local char = player.Character
	if not char or not char:GetAttribute("Ragdolled") then
		return
	end
	char:SetAttribute("Ragdolled", nil)
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
	RagdollRemote:FireClient(player, "Off")
end

return Ragdoll
