-- 고스트: 녹화된 주행 기록을 반투명 차로 다시 보여 줌 (내 화면에만).
-- 녹화 형식: { { t = 초, cf = CFrame }, ... }
-- 지금 타는 차 모델을 복제해서 고스트 모양으로 씀.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TrialConfig = require(ReplicatedStorage:WaitForChild("Shared").Config.GameplayConfig).Trial

local Ghost = {}

local ghostModel: Model? = nil
local samples: { { t: number, cf: CFrame } } = {}
local cursor = 1

local function makeGhostModel(source: Model): Model
	local clone = source:Clone()
	for _, d in clone:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.CastShadow = false
			d.Transparency = math.max(d.Transparency, TrialConfig.ghostTransparency)
			if d.Name == "ParkingSupport" then
				d:Destroy()
			end
		elseif d:IsA("JointInstance") or d:IsA("WeldConstraint") or d:IsA("Constraint")
			or d:IsA("ProximityPrompt") or d:IsA("Trail") or d:IsA("ParticleEmitter")
			or d:IsA("Light") or d:IsA("BillboardGui") then
			d:Destroy()
		end
	end
	clone.Name = "TrialGhost"
	clone.Parent = workspace
	return clone
end

function Ghost.Start(source: Model, recording: { { t: number, cf: CFrame } })
	Ghost.Stop()
	if #recording < 2 then
		return
	end
	samples = recording
	cursor = 1
	ghostModel = makeGhostModel(source)
	ghostModel:PivotTo(samples[1].cf)
end

function Ghost.Update(elapsed: number)
	local m = ghostModel
	if not m then
		return
	end
	while cursor < #samples - 1 and samples[cursor + 1].t <= elapsed do
		cursor += 1
	end
	local a, b = samples[cursor], samples[cursor + 1]
	if not b or elapsed >= b.t then
		m:PivotTo((b or a).cf)
		return
	end
	local alpha = math.clamp((elapsed - a.t) / math.max(b.t - a.t, 1e-3), 0, 1)
	m:PivotTo(a.cf:Lerp(b.cf, alpha))
end

function Ghost.Stop()
	if ghostModel then
		ghostModel:Destroy()
		ghostModel = nil
	end
	samples = {}
	cursor = 1
end

return Ghost
