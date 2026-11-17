-- 내 화면/조작에만 적용되는 설정 (서버와 상관없음).
-- 지금은 이번 접속 동안만 기억. 3단계 저장 시스템에서 플레이어 데이터로 저장 예정.

local ClientSettings = {}

local values = {
	DriveAssist = true, -- 주행 보조 (스핀 방지, 자동 카운터 스티어, 벽 긁은 뒤 방향 맞춤)
}

local changed = Instance.new("BindableEvent")
ClientSettings.Changed = changed.Event -- (name, value)

function ClientSettings.Get(name: string): any
	return values[name]
end

function ClientSettings.Set(name: string, value: any)
	if values[name] == value then
		return
	end
	values[name] = value
	changed:Fire(name, value)
end

return ClientSettings
