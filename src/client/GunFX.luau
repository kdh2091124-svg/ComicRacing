-- 총 효과 (내 화면에서만 그림, 모두 각자 그림)
-- 섬광(빛 + 별 모양 + 불꽃), 탄피 튕겨 나감, 굵게 빛나다 사라지는 총알 줄기, 맞은 자리 불똥/먼지/피
-- 에셋 ID 없이 기본 파트/파티클만 사용

local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")

local GunFX = {}

GunFX.Styles = {
	-- color = 줄기/섬광 색, width = 줄기 굵기, flash = 섬광 크기, shell = 탄피 종류, life = 줄기 남는 시간
	AR = { color = Color3.fromRGB(255, 200, 90), width = 0.22, flash = 1.0, shell = "rifle", life = 0.08 },
	Sniper = { color = Color3.fromRGB(140, 230, 255), width = 0.55, flash = 2.2, shell = "big", life = 0.35 },
	Revolver = { color = Color3.fromRGB(255, 220, 120), width = 0.32, flash = 1.5, shell = "none", life = 0.12 },
	ColaCannon = { color = Color3.fromRGB(170, 90, 40), width = 0, flash = 1.8, shell = "can", life = 0 },
	ArenaSniper = { color = Color3.fromRGB(255, 70, 70), width = 0.9, flash = 4, shell = "none", life = 0.4 },
	Default = { color = Color3.fromRGB(255, 220, 140), width = 0.2, flash = 1, shell = "rifle", life = 0.08 },
}

function GunFX.Style(id: string?)
	return (id and GunFX.Styles[id]) or GunFX.Styles.Default
end

local function part(size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.Neon
	p.Parent = workspace.CurrentCamera
	return p
end

-- 파티클 한 번 펑 (지형에 붙인 Attachment 에서)
local function burst(pos: Vector3, count: number, color: ColorSequence, speed: NumberRange, size: number, life: NumberRange, dir: Vector3?, spread: number?)
	local att = Instance.new("Attachment")
	att.WorldPosition = pos
	if dir and dir.Magnitude > 0.01 then
		att.WorldCFrame = CFrame.lookAt(pos, pos + dir) * CFrame.Angles(-math.pi / 2, 0, 0) -- 파티클은 위(+Y)로 나감
	end
	att.Parent = workspace.Terrain
	local pe = Instance.new("ParticleEmitter")
	pe.Color = color
	pe.LightEmission = 1
	pe.Speed = speed
	pe.Lifetime = life
	pe.SpreadAngle = Vector2.new(spread or 180, spread or 180)
	pe.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, size), NumberSequenceKeypoint.new(1, 0) })
	pe.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) })
	pe.Drag = 4
	pe.Rate = 0
	pe.Parent = att
	pe:Emit(count)
	Debris:AddItem(att, life.Max + 0.2)
end

-- 총구 섬광: 번쩍 빛 + 별 모양 + 앞으로 튀는 불꽃
function GunFX.Muzzle(pos: Vector3, dir: Vector3, style)
	local s = style.flash
	local cf = CFrame.lookAt(pos, pos + dir)
	local a = part(Vector3.new(0.25, 0.25, 1.6) * s, cf * CFrame.new(0, 0, -0.6 * s), style.color)
	local b = part(Vector3.new(1.1, 0.12, 0.12) * s, cf * CFrame.Angles(0, 0, math.rad(math.random(0, 90))), style.color)
	local c = part(Vector3.new(1.1, 0.12, 0.12) * s, cf * CFrame.Angles(0, 0, math.rad(math.random(0, 90)) + math.pi / 2), Color3.new(1, 1, 1))
	local core = part(Vector3.one * 0.5 * s, cf, Color3.new(1, 1, 0.85))
	core.Shape = Enum.PartType.Ball
	local light = Instance.new("PointLight")
	light.Color = style.color
	light.Range = 10 * s
	light.Brightness = 4
	light.Parent = core
	for _, p in { a, b, c, core } do
		Debris:AddItem(p, 0.05)
	end
	burst(pos, math.floor(6 * s), ColorSequence.new(style.color, Color3.new(1, 1, 1)), NumberRange.new(30, 60), 0.25 * s, NumberRange.new(0.05, 0.15), dir, 18)
end

-- 총알 줄기: 굵게 번쩍 → 가늘어지며 사라짐
function GunFX.Tracer(from: Vector3, to: Vector3, style)
	if style.width <= 0 then
		return
	end
	local d = (to - from).Magnitude
	if d < 0.5 then
		return
	end
	local mid = CFrame.lookAt((from + to) / 2, to)
	local p = part(Vector3.new(style.width, style.width, d), mid, style.color)
	local glow = part(Vector3.new(style.width * 2.5, style.width * 2.5, d), mid, style.color)
	glow.Transparency = 0.75
	local info = TweenInfo.new(style.life, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(p, info, { Size = Vector3.new(0.02, 0.02, d), Transparency = 1 }):Play()
	TweenService:Create(glow, info, { Size = Vector3.new(0.05, 0.05, d), Transparency = 1 }):Play()
	Debris:AddItem(p, style.life + 0.05)
	Debris:AddItem(glow, style.life + 0.05)
end

-- 탄피: 총 오른쪽 위로 튕겨 나가 굴러떨어짐 (실제 물리, 1.5초 뒤 사라짐)
function GunFX.Shell(pos: Vector3, right: Vector3, up: Vector3, style)
	local kind = style.shell
	if kind == "none" then
		return
	end
	local size, color = Vector3.new(0.12, 0.12, 0.35), Color3.fromRGB(230, 180, 60)
	if kind == "big" then
		size = Vector3.new(0.18, 0.18, 0.6)
	elseif kind == "can" then
		size, color = Vector3.new(0.45, 0.7, 0.45), Color3.fromRGB(220, 30, 40) -- 콜라캔
	end
	local p = Instance.new("Part")
	p.Size = size
	p.Color = color
	p.Material = kind == "can" and Enum.Material.SmoothPlastic or Enum.Material.Metal
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.CFrame = CFrame.new(pos) * CFrame.Angles(math.random() * 6, math.random() * 6, 0)
	p.Massless = true
	-- 카메라 안에 넣으면 물리가 안 돌아서 workspace 의 내 화면 전용 폴더에 (클라에서 만든 건 다른 사람에게 안 보임)
	local folder = workspace:FindFirstChild("LocalFX")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "LocalFX"
		folder.Parent = workspace
	end
	p.Parent = folder
	p.AssemblyLinearVelocity = right * (14 + math.random() * 8) + up * (10 + math.random() * 8)
	p.AssemblyAngularVelocity = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * 40
	Debris:AddItem(p, 1.5)
end

-- 맞은 자리: kind = "car"(주황 불똥) / "person"(빨강) / "world"(먼지) / "big"(크게)
function GunFX.Impact(pos: Vector3, normal: Vector3?, kind: string, scale: number?)
	local s = scale or 1
	local n = normal or Vector3.yAxis
	if kind == "person" then
		burst(pos, math.floor(10 * s), ColorSequence.new(Color3.fromRGB(255, 50, 50), Color3.fromRGB(150, 0, 0)), NumberRange.new(8, 20), 0.35 * s, NumberRange.new(0.15, 0.35), n, 60)
	elseif kind == "car" then
		burst(pos, math.floor(14 * s), ColorSequence.new(Color3.fromRGB(255, 220, 120), Color3.fromRGB(255, 120, 30)), NumberRange.new(25, 55), 0.2 * s, NumberRange.new(0.1, 0.3), n, 70)
	else
		burst(pos, math.floor(8 * s), ColorSequence.new(Color3.fromRGB(220, 210, 190), Color3.fromRGB(140, 130, 120)), NumberRange.new(6, 16), 0.5 * s, NumberRange.new(0.2, 0.45), n, 50)
	end
	local flash = part(Vector3.one * 0.8 * s, CFrame.new(pos), Color3.new(1, 1, 0.9))
	flash.Shape = Enum.PartType.Ball
	TweenService:Create(flash, TweenInfo.new(0.1), { Size = Vector3.one * 1.8 * s, Transparency = 1 }):Play()
	Debris:AddItem(flash, 0.12)
end

-- 맞은 인스턴스 → 효과 종류
function GunFX.KindOf(inst: Instance?): string
	if not inst then
		return "world"
	end
	local m = inst:FindFirstAncestorOfClass("Model")
	while m do
		if m:FindFirstChildOfClass("Humanoid") then
			return "person"
		end
		if m.Parent and m.Parent.Name == "Vehicles" then
			return "car"
		end
		m = m:FindFirstAncestorOfClass("Model")
	end
	return "world"
end

return GunFX
