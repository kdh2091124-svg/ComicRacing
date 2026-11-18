-- 아레나 장치(회전 쟁기 등)의 물리를 서버가 맡게 함
-- 안 하면 Roblox 가 가까운 플레이어에게 물리를 넘겨서, 그 사람 화면 기준으로 움직이고 다른 사람에겐 끊겨 보임
-- 맵 파트에 Attribute "ServerPhysics" = true 가 붙은 것만 대상

local function claim(inst: Instance)
	if inst:IsA("BasePart") and inst:GetAttribute("ServerPhysics") and not inst.Anchored then
		pcall(function()
			inst:SetNetworkOwner(nil)
		end)
	end
end

for _, d in workspace:GetDescendants() do
	claim(d)
end
workspace.DescendantAdded:Connect(function(d)
	task.defer(claim, d) -- 부모/속성이 다 붙은 뒤에
end)
