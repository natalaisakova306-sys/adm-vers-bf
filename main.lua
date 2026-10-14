-- [[ XENO BLOX FRUITS HUB v22.14 - FAST CLICK EDITION (Sea 1) ]] --
-- v22.14: Fast Click (сетевая AoE-аура урона по мобам в радиусе), фикс чтения квестов "0/5",
--         снятие блокировки кликов при открытом хабе, сохранена вся база v22.13.
-- v22.13: быстрее удары (скорость/комбо фрукта, быстрый подлёт), камера держит твой зум, хаб сворачивается при старте фарма.
-- v22.12: конец квеста определяется сразу, камера на мобе, 4 способа атаки с самоподбором, Mixed (фрукт+стиль+меч), скиллы для любого оружия, кэш спавнов.
-- v22.11: Anti-PvP выключен по умолчанию.
-- v22.10: проверка квестов (не бросаем недобитый квест), кнопка "Полный отчёт для Claude", телепорт (3 попытки + отпускает на острове), клики не при открытом хабе.
-- v22.9: уровни Колизея (Toga 250), фолбэк на предыдущий квест, клики только при фокусе окна/закрытом меню/в центре экрана.
-- v22.8: фикс запуска: блок экспорта/облёта вынесен в отдельную функцию (лимит 200 локальных в Luau).
-- v22.6: прицел курсора на моба (фрукты больше не стреляют в небо), пропуск мобов без урона.
-- v22.5: все NPC квестов сверены со вторым экспортом (Sky Adventurer, Mole, Sky Quest Giver 2, Freezeburg Quest Giver, ...).
-- v22.4: точки квестов сверены с экспортом Adm Perms (NPC по имени, реальные спавны мобов, PlaceId 85211729168715).
-- v22.3: исправлена атака фруктами (Ice и др.) + авто-скиллы Z/X/C/V + кнопка Debug.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local TeleportService = game:GetService("TeleportService")
local StarterGui = game:GetService("StarterGui")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local VirtualUser = game:GetService("VirtualUser")
local UserInputService = game:GetService("UserInputService")
local Lighting = game:GetService("Lighting")
local VIM = game:GetService("VirtualInputManager")

local LocalPlayer = Players.LocalPlayer
local Camera = workspace.CurrentCamera

-- ==================== БАЗА: ЖИЗНЕННЫЙ ЦИКЛ ====================
local alive = true
local Connections = {}
local function Connect(signal, fn)
    local c = signal:Connect(fn)
    table.insert(Connections, c)
    return c
end

local function Notify(text, dur)
    pcall(function()
        StarterGui:SetCore("SendNotification", {Title = "Xeno Hub", Text = text, Duration = dur or 2})
    end)
end

local function GetGuiParent()
    if gethui then
        local ok, h = pcall(gethui)
        if ok and h then return h end
    end
    local ok = pcall(function()
        local f = Instance.new("Folder")
        f.Parent = game:GetService("CoreGui")
        f:Destroy()
    end)
    if ok then return game:GetService("CoreGui") end
    return LocalPlayer:WaitForChild("PlayerGui")
end

local TargetParent = GetGuiParent()
local old = TargetParent:FindFirstChild("XenoModernHub")
if old then old:Destroy() end

local SEA1_PLACE_IDS = {[2753915549] = true, [85211729168715] = true}
if not SEA1_PLACE_IDS[game.PlaceId] then
    Notify("Скрипт рассчитан на Sea 1! Квесты/координаты не подойдут.")
end

local Remotes = ReplicatedStorage:WaitForChild("Remotes", 5)
local CommF = Remotes and Remotes:WaitForChild("CommF_", 5)
if not CommF then Notify("CommF_ не найден: квесты/статы/хаки работать не будут") end

-- [v22.14] Сетевые модули урона (Fast Click / AoE Aura)
local NetModules = ReplicatedStorage:WaitForChild("Modules", 5) and ReplicatedStorage.Modules:WaitForChild("Net", 5)
local RegisterAttack = NetModules and NetModules:FindFirstChild("RE/RegisterAttack")
local RegisterHit = NetModules and NetModules:FindFirstChild("RE/RegisterHit")

local function Invoke(...)
    if not CommF then return nil end
    local args = {...}
    local ok, res = pcall(function() return CommF:InvokeServer(unpack(args)) end)
    return ok and res or nil
end

-- ==================== СОХРАНЕНИЕ НАСТРОЕК ====================
local HttpService = game:GetService("HttpService")
local CONFIG_FILE = "XenoHub_BloxFruits.json"
local Config = {}
pcall(function()
    if isfile and readfile and isfile(CONFIG_FILE) then
        local t = HttpService:JSONDecode(readfile(CONFIG_FILE))
        if type(t) == "table" then Config = t end
    end
end)

local saveQueued = false
local function SaveConfig()
    if not writefile or saveQueued then return end
    saveQueued = true
    task.delay(0.5, function()
        saveQueued = false
        pcall(function() writefile(CONFIG_FILE, HttpService:JSONEncode(Config)) end)
    end)
end
local function Cfg(key, default)
    local v = Config[key]
    if v == nil then return default end
    return v
end
local function CfgSet(key, v)
    Config[key] = v
    SaveConfig()
end
local PendingToggles = {}

-- ==================== СОСТОЯНИЕ ====================
local State = {
    Farm = false,
    Chests = false,
    Stats = false,
    Bring = true,
    Buso = true,
    AntiPvP = false,
    Skills = false,
    Front = true,
    AtkInterval = 0.10,
    ComboMode = "1-3",
    CamLock = true,
    Weapon = Cfg("Weapon", "Any"),
    StatMode = Cfg("StatMode", "Fruit"),
    FrontDist = Cfg("FrontDist", "Близко"),
    Hover = 7.3,
}
local farmRun = 0

local Diag = {
    status = {}, errors = {}, hiddenSince = nil,
    spawnCache = {},
    camTarget = nil, camOwned = false,
    varSwitchT = 0,
    variant = {["Blox Fruit"] = 1, Melee = 1, Sword = 1, Gun = 1},
}

-- Анти-AFK
Connect(LocalPlayer.Idled, function()
    pcall(function()
        VirtualUser:CaptureController()
        VirtualUser:ClickButton2(Vector2.zero)
    end)
end)

-- ==================== БАЗА КВЕСТОВ SEA 1 ====================
local QuestsData = {
    {Level = 1, Quest = "BanditQuest1", Id = 1, Mob = "Bandit", NpcName = "Bandit Quest Giver", NpcPos = Vector3.new(1052, 15, 1558), MobPos = Vector3.new(991, 14, 1571)},
    {Level = 10, Quest = "JungleQuest", Id = 1, Mob = "Monkey", NpcName = "Adventurer", NpcPos = Vector3.new(-1680, 49, 176), MobPos = Vector3.new(-1526, 27, 164)},
    {Level = 15, Quest = "JungleQuest", Id = 2, Mob = "Gorilla", NpcName = "Adventurer", NpcPos = Vector3.new(-1680, 49, 176), MobPos = Vector3.new(-1352, 18, -501)},
    {Level = 30, Quest = "BuggyQuest1", Id = 1, Mob = "Pirate", NpcName = "Pirate Adventurer", NpcPos = Vector3.new(-1152, 17, 3863), MobPos = Vector3.new(-1150, 20, 3997)},
    {Level = 40, Quest = "BuggyQuest1", Id = 2, Mob = "Brute", NpcName = "Pirate Adventurer", NpcPos = Vector3.new(-1152, 17, 3863), MobPos = Vector3.new(-1090, 28, 4393)},
    {Level = 60, Quest = "DesertQuest", Id = 1, Mob = "Desert Bandit", NpcName = "Desert Adventurer", NpcPos = Vector3.new(922, 5, 4202), MobPos = Vector3.new(924, 8, 4514)},
    {Level = 75, Quest = "DesertQuest", Id = 2, Mob = "Desert Officer", NpcName = "Desert Adventurer", NpcPos = Vector3.new(922, 5, 4202), MobPos = Vector3.new(1573, 14, 4159)},
    {Level = 90, Quest = "SnowQuest", Id = 1, Mob = "Snow Bandit", NpcName = "Villager", NpcPos = Vector3.new(1401, 77, -1311), MobPos = Vector3.new(1352, 78, -1421)},
    {Level = 100, Quest = "SnowQuest", Id = 2, Mob = "Snowman", NpcName = "Villager", NpcPos = Vector3.new(1401, 77, -1311), MobPos = Vector3.new(1260, 98, -1601)},
    {Level = 120, Quest = "MarineQuest2", Id = 1, Mob = "Chief Petty Officer", NpcName = "Marine", NpcPos = Vector3.new(-4699, 5, 4228), MobPos = Vector3.new(-4796, 13, 4243)},
    {Level = 150, Quest = "SkyQuest", Id = 1, Mob = "Sky Bandit", NpcName = "Sky Adventurer", NpcPos = Vector3.new(-5406, 410, -694), MobPos = Vector3.new(-5014, 281, -972)},
    {Level = 175, Quest = "SkyQuest", Id = 2, Mob = "Dark Master", NpcName = "Sky Adventurer", NpcPos = Vector3.new(-5406, 410, -694), MobPos = Vector3.new(-5245, 505, -285)},
    {Level = 190, Quest = "PrisonerQuest", Id = 1, Mob = "Prisoner", NpcName = "Jail Keeper", NpcPos = Vector3.new(5208, 19, 737), MobPos = Vector3.new(5414, 7, 483)},
    {Level = 210, Quest = "PrisonerQuest", Id = 2, Mob = "Dangerous Prisoner", NpcName = "Jail Keeper", NpcPos = Vector3.new(5208, 19, 737), MobPos = Vector3.new(5242, 9, 1081)},
    {Level = 250, Quest = "ColosseumQuest", Id = 1, Mob = "Toga Warrior", NpcName = "Colosseum Quest Giver", NpcPos = Vector3.new(-1342, 11, -2929), MobPos = Vector3.new(-1657, 11, -2653)},
    {Level = 275, Quest = "ColosseumQuest", Id = 2, Mob = "Gladiator", NpcName = "Colosseum Quest Giver", NpcPos = Vector3.new(-1342, 11, -2929), MobPos = Vector3.new(-1199, 12, -3319)},
    {Level = 300, Quest = "MagmaQuest", Id = 1, Mob = "Military Soldier", NpcName = "The Mayor", NpcPos = Vector3.new(-5309, 17, 8483), MobPos = Vector3.new(-5302, 17, 8592)},
    {Level = 325, Quest = "MagmaQuest", Id = 2, Mob = "Military Spy", NpcName = "The Mayor", NpcPos = Vector3.new(-5309, 17, 8483), MobPos = Vector3.new(-5921, 77, 8733)},
    {Level = 375, Quest = "FishmanQuest", Id = 1, Mob = "Fishman Warrior", NpcName = "King Neptune", NpcPos = Vector3.new(61406, 25, 1627), MobPos = Vector3.new(60871, 24, 1459)},
    {Level = 400, Quest = "FishmanQuest", Id = 2, Mob = "Fishman Commando", NpcName = "King Neptune", NpcPos = Vector3.new(61406, 25, 1627), MobPos = Vector3.new(61848, 25, 1281)},
    {Level = 450, Quest = "SkyExp1Quest", Id = 1, Mob = "God's Guard", NpcName = "Mole", NpcPos = Vector3.new(-4309, 1086, -556), MobPos = Vector3.new(-4384, 1089, -441)},
    {Level = 475, Quest = "SkyExp1Quest", Id = 2, Mob = "Shanda", NpcName = "Mole", NpcPos = Vector3.new(-5949, 5468, 2087), MobPos = Vector3.new(-6008, 5469, 1779)},
    {Level = 525, Quest = "SkyExp2Quest", Id = 1, Mob = "Royal Squad", NpcName = "Sky Quest Giver 2", NpcPos = Vector3.new(-7033, 5591, 1353), MobPos = Vector3.new(-6756, 5551, 1119)},
    {Level = 550, Quest = "SkyExp2Quest", Id = 2, Mob = "Royal Soldier", NpcName = "Sky Quest Giver 2", NpcPos = Vector3.new(-7033, 5591, 1353), MobPos = Vector3.new(-7151, 5541, 964)},
    {Level = 625, Quest = "FountainQuest", Id = 1, Mob = "Galley Pirate", NpcName = "Freezeburg Quest Giver", NpcPos = Vector3.new(5263, 75, 4088), MobPos = Vector3.new(5379, 77, 3984)},
    {Level = 650, Quest = "FountainQuest", Id = 2, Mob = "Galley Captain", NpcName = "Freezeburg Quest Giver", NpcPos = Vector3.new(5263, 75, 4088), MobPos = Vector3.new(5685, 78, 4733)},
}

local MarineStartQuest = {Level = 1, Quest = "MarineQuest", Id = 1, Mob = "Trainee", NpcName = "Marine Leader",
    NpcPos = Vector3.new(-2655, 31, 2114), MobPos = Vector3.new(-2730, 31, 2216)}

local questFail = {}

local function GetCurrentQuest()
    local lvl = 1
    pcall(function() lvl = LocalPlayer.Data.Level.Value end)

    local isMarine = false
    pcall(function() isMarine = LocalPlayer.Team and LocalPlayer.Team.Name == "Marines" end)
    if isMarine and lvl < 10 then return MarineStartQuest end

    local q = QuestsData[1]
    for _, item in ipairs(QuestsData) do
        if lvl >= item.Level then
            if questFail[item.Quest .. ":" .. item.Id] ~= lvl then q = item end
        else
            break
        end
    end
    return q
end

local function BaseName(name)
    return (string.lower(name):gsub("%s*%[lv.*$", ""))
end

local function IsMobNamed(model, mobName)
    local n, m = BaseName(model.Name), string.lower(mobName)
    return n == m or string.sub(n, 1, #m + 1) == m .. " "
end

local function GetLiveMobOwned(part)
    if isnetworkowner then
        local ok, r = pcall(isnetworkowner, part)
        return ok and r == true
    end
    return true
end

local badMobs = {}
local function GetLiveMob(mobName, fromPos)
    local enemies = workspace:FindFirstChild("Enemies")
    if not enemies then return nil end
    local best, bestDist = nil, math.huge
    local bestOwned, bestOwnedDist = nil, math.huge
    for _, mob in ipairs(enemies:GetChildren()) do
        if IsMobNamed(mob, mobName) and not (badMobs[mob] and badMobs[mob] > os.clock()) then
            local hum = mob:FindFirstChildOfClass("Humanoid")
            local hrp = mob:FindFirstChild("HumanoidRootPart")
            if hum and hrp and hum.Health > 0 then
                local d = fromPos and (hrp.Position - fromPos).Magnitude or 0
                if d < bestDist then
                    best, bestDist = mob, d
                end
                if d < bestOwnedDist and GetLiveMobOwned(hrp) then
                    bestOwned, bestOwnedDist = mob, d
                end
            end
        end
    end
    return bestOwned or best
end

local function Norm(s)
    s = string.lower(s)
    s = string.gsub(s, "%s*%[lv.*$", "")
    s = string.gsub(s, "[^%w]", "")
    s = string.gsub(s, "%d+$", "")
    return s
end

local lastMobSeen = {}
local function GetDynamicSpawn(mobName, fallbackPos, fromPos)
    local want = Norm(mobName)
    local origin = workspace:FindFirstChild("_WorldOrigin")
    local spawns = origin and origin:FindFirstChild("EnemySpawns")
    if spawns then
        local cache = Diag.spawnCache[want]
        if not cache then
            cache = {list = {}, keys = {}}
            Diag.spawnCache[want] = cache
        end
        for _, sp in ipairs(spawns:GetChildren()) do
            if sp:IsA("BasePart") and Norm(sp.Name) == want then
                local p = sp.Position
                local key = math.floor(p.X / 4) .. ":" .. math.floor(p.Y / 4) .. ":" .. math.floor(p.Z / 4)
                if not cache.keys[key] then
                    cache.keys[key] = true
                    cache.list[#cache.list + 1] = p
                end
            end
        end
    end
    local cache = Diag.spawnCache[want]
    if cache and #cache.list > 0 then
        local best, bd = nil, math.huge
        for _, p in ipairs(cache.list) do
            local d = fromPos and (p - fromPos).Magnitude or 0
            if d < bd then best, bd = p, d end
        end
        if best then return best, "spawn" end
    end
    if lastMobSeen[mobName] then return lastMobSeen[mobName], "seen" end
    return fallbackPos, "table"
end

local function GetQuestPanel()
    local pGui = LocalPlayer:FindFirstChild("PlayerGui")
    local main = pGui and pGui:FindFirstChild("Main")
    return main and main:FindFirstChild("Quest")
end

local function AnyQuestShown()
    local q = GetQuestPanel()
    if not q then return false end
    for _, d in ipairs(q:GetDescendants()) do
        if d:IsA("TextLabel") and d.Text ~= ""
            and (string.find(d.Text, "Defeat", 1, true) or string.find(d.Text, "%d+%s*/%s*%d+")) then
            return true
        end
    end
    return false
end

local lastQuestKey = nil
local takenKey = nil
local function QuestKey(qd) return qd.Quest .. ":" .. qd.Id end

-- [v22.14] Исправлено чтение: находит счетчик в любом тексте (например, "DEFEAT 5 BANDITS (0/5)")
local lastProgress = nil
local function ReadProgress()
    local panel = GetQuestPanel()
    if not panel then return nil end
    for _, d in ipairs(panel:GetDescendants()) do
        if d:IsA("TextLabel") and d.Text ~= "" then
            local a, b = string.match(d.Text, "(%d+)%s*/%s*(%d+)")
            if a and b then return tonumber(a), tonumber(b) end
        end
    end
    return nil
end

local STALL_SEC = 90
local panelVisOK = false
local lastProgSeen, progChangedAt = nil, 0

local function ResetProgressWatch()
    lastProgSeen = nil
    progChangedAt = os.clock()
end

local questTakenAt = 0
local questTakenFor = nil

local function IsQuestActive(qd)
    if takenKey ~= QuestKey(qd) then return false end
    local panel = GetQuestPanel()
    if panel and panelVisOK and not panel.Visible then
        Diag.hiddenSince = Diag.hiddenSince or os.clock()
        if os.clock() - Diag.hiddenSince > 1.2 then
            lastProgress = nil
            return false
        end
        return true
    end
    Diag.hiddenSince = nil
    if panel and panel.Visible then panelVisOK = true end
    local a, b = ReadProgress()
    if a and b then
        local cur = a .. "/" .. b
        lastProgress = cur
        if cur ~= lastProgSeen then
            lastProgSeen = cur
            progChangedAt = os.clock()
        end
        if a >= b then return false end
        if os.clock() - progChangedAt > STALL_SEC then
            ResetProgressWatch()
            return false
        end
        return true
    end
    lastProgress = nil
    return os.clock() - questTakenAt < 80
end

local function NpcPart(m)
    return m:FindFirstChild("HumanoidRootPart") or m.PrimaryPart or m:FindFirstChildWhichIsA("BasePart", true)
end

local function FindNpcByName(name, nearPos)
    if not name then return nil end
    local folder = workspace:FindFirstChild("NPCs")
    if not folder then return nil end
    local best, bd = nil, math.huge
    for _, m in ipairs(folder:GetChildren()) do
        if m.Name == name then
            local p = NpcPart(m)
            if p then
                local d = nearPos and (p.Position - nearPos).Magnitude or 0
                if d < bd then best, bd = p, d end
            end
        end
    end
    return best
end

local resolveNpcName = nil
local lastNpcFinal = nil
local function ResolveNpc(nominal)
    local best = FindNpcByName(resolveNpcName, nominal)
    if not best then
        local bd = 90
        local folder = workspace:FindFirstChild("NPCs")
        if folder then
            for _, m in ipairs(folder:GetChildren()) do
                local p = NpcPart(m)
                if p then
                    local d = (p.Position - nominal).Magnitude
                    if d < bd then best, bd = p, d end
                end
            end
        end
    end

    local pos
    if best then
        pos = best.Position + Vector3.new(0, 3, 0)
    else
        local rp = RaycastParams.new()
        rp.FilterType = Enum.RaycastFilterType.Exclude
        local ex = {}
        if LocalPlayer.Character then table.insert(ex, LocalPlayer.Character) end
        local en = workspace:FindFirstChild("Enemies")
        if en then table.insert(ex, en) end
        rp.FilterDescendantsInstances = ex
        local hit = workspace:Raycast(Vector3.new(nominal.X, nominal.Y + 25, nominal.Z), Vector3.new(0, -300, 0), rp)
        if not hit then
            hit = workspace:Raycast(Vector3.new(nominal.X, nominal.Y + 200, nominal.Z), Vector3.new(0, -500, 0), rp)
        end
        pos = hit and (hit.Position + Vector3.new(0, 4, 0)) or nominal
    end
    lastNpcFinal = pos
    return pos
end

local function ResolveGround(nominal)
    local rp = RaycastParams.new()
    rp.FilterType = Enum.RaycastFilterType.Exclude
    local ex = {}
    if LocalPlayer.Character then table.insert(ex, LocalPlayer.Character) end
    local en = workspace:FindFirstChild("Enemies")
    if en then table.insert(ex, en) end
    local npcs = workspace:FindFirstChild("NPCs")
    if npcs then table.insert(ex, npcs) end
    rp.FilterDescendantsInstances = ex

    local hit = workspace:Raycast(Vector3.new(nominal.X, nominal.Y + 25, nominal.Z), Vector3.new(0, -300, 0), rp)
    if not hit then
        hit = workspace:Raycast(Vector3.new(nominal.X, nominal.Y + 200, nominal.Z), Vector3.new(0, -500, 0), rp)
    end
    if hit and hit.Position.Y >= nominal.Y - 30 then
        return hit.Position + Vector3.new(0, 4, 0)
    end
    return nominal + Vector3.new(0, 4, 0)
end

-- ==================== ПОЛЁТ / NOCLIP ====================
local flying = false
local flightBV = nil
local currentTween = nil
local flightId = 0
local flySpeed = 260
local rollbackCount = 0

local function EnsureHold()
    local char = LocalPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    if not flightBV or flightBV.Parent ~= hrp then
        if flightBV then flightBV:Destroy() end
        flightBV = Instance.new("BodyVelocity")
        flightBV.Name = "HoldBV"
        flightBV.MaxForce = Vector3.new(1e6, 1e6, 1e6)
        flightBV.Velocity = Vector3.zero
        flightBV.Parent = hrp
    end
end

local function RemoveHold()
    if flightBV then
        flightBV:Destroy()
        flightBV = nil
    end
end

local function CancelFlight()
    flightId = flightId + 1
    if currentTween then
        currentTween:Cancel()
        currentTween = nil
    end
    flying = false
end

local function LinearFly(hrp, targetPos, speed, id)
    local dist = (hrp.Position - targetPos).Magnitude
    if dist < 4 then
        hrp.CFrame = CFrame.new(targetPos)
        return true
    end

    local dur = dist / speed
    local tween = TweenService:Create(hrp, TweenInfo.new(dur, Enum.EasingStyle.Linear), {CFrame = CFrame.new(targetPos)})
    currentTween = tween
    flying = true

    local done = false
    local c1 = tween.Completed:Connect(function() done = true end)
    local c2 = RunService.Heartbeat:Connect(function()
        if hrp.Parent then
            hrp.AssemblyLinearVelocity = Vector3.zero
            hrp.AssemblyAngularVelocity = Vector3.zero
        end
    end)
    tween:Play()

    local deadline = os.clock() + dur + 3
    local t0, startPos, pushed = os.clock(), hrp.Position, false
    while alive and not done and os.clock() < deadline and id == flightId and hrp.Parent do
        task.wait()
        local frac = math.clamp((os.clock() - t0) / dur, 0, 1)
        if hrp.Parent and (hrp.Position - startPos:Lerp(targetPos, frac)).Magnitude > 150 then
            pushed = true
            break
        end
    end
    if pushed then
        flySpeed = math.max(120, math.floor(flySpeed * 0.75))
        rollbackCount = rollbackCount + 1
    end

    c1:Disconnect()
    c2:Disconnect()
    tween:Cancel()
    if currentTween == tween then currentTween = nil end
    return done and id == flightId
end

local function SafeFlyTo(targetPos, resolver, cruiseAtTarget, quick)
    local char = LocalPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return false end

    local dist = (hrp.Position - targetPos).Magnitude
    if dist < 6 then
        hrp.CFrame = CFrame.new(targetPos)
        EnsureHold()
        return true
    end

    CancelFlight()
    local id = flightId
    RemoveHold()

    if targetPos.X > 50000 and hrp.Position.X < 50000 then
        Invoke("requestEntrance", Vector3.new(61163.85, 5.34, 1819.78))
        task.wait(1)
        char = LocalPlayer.Character
        hrp = char and char:FindFirstChild("HumanoidRootPart")
        if not hrp then return false end
    end

    local speed = flySpeed
    local cur = hrp.Position

    if dist > 350 then
        local cruiseY = cruiseAtTarget and (targetPos.Y + 10) or (math.max(cur.Y, targetPos.Y) + 40)
        if cruiseY - cur.Y > 8 then
            if not LinearFly(hrp, Vector3.new(cur.X, cruiseY, cur.Z), speed, id) then return false end
        end
        if not LinearFly(hrp, Vector3.new(targetPos.X, cruiseY, targetPos.Z), speed, id) then return false end
    elseif resolver and dist > 40 then
        if not LinearFly(hrp, Vector3.new(targetPos.X, targetPos.Y + 20, targetPos.Z), speed, id) then return false end
    end

    if resolver then
        task.wait(0.3)
        targetPos = resolver(targetPos)
    end

    if not LinearFly(hrp, targetPos, quick and speed or math.min(speed, 190), id) then return false end

    hrp.CFrame = CFrame.new(targetPos)
    flying = false
    EnsureHold()

    if quick then return true end
    task.wait(0.4)
    local c2 = LocalPlayer.Character
    local h2 = c2 and c2:FindFirstChild("HumanoidRootPart")
    if h2 and (h2.Position - targetPos).Magnitude > 40 then
        flySpeed = math.max(120, math.floor(flySpeed * 0.7))
        rollbackCount = rollbackCount + 1
        return false
    end
    flySpeed = math.min(260, flySpeed + 8)
    return true
end

local noclipWasOn = false
Connect(RunService.Stepped, function()
    local char = LocalPlayer.Character
    if not char then return end
    local need = State.Farm or State.Chests or flying
    if need then
        noclipWasOn = true
        for _, p in ipairs(char:GetDescendants()) do
            if p:IsA("BasePart") then p.CanCollide = false end
        end
    elseif noclipWasOn then
        noclipWasOn = false
        for _, n in ipairs({"Head", "UpperTorso", "LowerTorso", "Torso"}) do
            local p = char:FindFirstChild(n)
            if p and p:IsA("BasePart") then p.CanCollide = true end
        end
    end
end)

Connect(LocalPlayer.CharacterAdded, function()
    flightBV = nil
    CancelFlight()
end)

-- ==================== БОЙ ====================
local function EnsureBuso()
    if not State.Buso then return end
    local char = LocalPlayer.Character
    if char and not char:FindFirstChild("HasBuso") then
        Invoke("Buso")
    end
end

local function IsWeaponTip(tip)
    return tip == "Blox Fruit" or tip == "Sword" or tip == "Melee" or tip == "Gun"
end

local function WantedTip()
    if State.Weapon ~= "Mixed" then return State.Weapon end
    local have = {}
    for _, holder in ipairs({LocalPlayer.Character, LocalPlayer:FindFirstChild("Backpack")}) do
        if holder then
            for _, it in ipairs(holder:GetChildren()) do
                if it:IsA("Tool") and IsWeaponTip(it.ToolTip) then have[it.ToolTip] = true end
            end
        end
    end
    local list = {}
    for _, tip in ipairs({"Blox Fruit", "Melee", "Sword", "Gun"}) do
        if have[tip] then list[#list + 1] = tip end
    end
    if #list == 0 then return "Any" end
    return list[math.floor(os.clock() / 6) % #list + 1]
end

local function EnsureWeaponEquipped()
    local char = LocalPlayer.Character
    local bp = LocalPlayer:FindFirstChild("Backpack")
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if not char or not bp or not hum then return end
    local want = WantedTip()

    local equipped = char:FindFirstChildOfClass("Tool")
    if equipped then
        if want == "Any" and IsWeaponTip(equipped.ToolTip) then return end
        if equipped.ToolTip == want then return end
    end

    if want ~= "Any" then
        for _, item in ipairs(bp:GetChildren()) do
            if item:IsA("Tool") and item.ToolTip == want then
                hum:EquipTool(item)
                return
            end
        end
        if State.Weapon == "Mixed" and equipped and IsWeaponTip(equipped.ToolTip) then return end
    end

    if not equipped or not IsWeaponTip(equipped.ToolTip) then
        for _, item in ipairs(bp:GetChildren()) do
            if item:IsA("Tool") and IsWeaponTip(item.ToolTip) then
                hum:EquipTool(item)
                break
            end
        end
    end
end

-- Стягивание мобов
local bringTarget, gatherCF = nil, nil
local lastSimRadius = 0

local function Owned(part)
    if isnetworkowner then
        local ok, r = pcall(isnetworkowner, part)
        return ok and r == true
    end
    return true
end

local function SetBringTarget(target)
    if bringTarget ~= target then
        bringTarget = target
        local h = target and target:FindFirstChild("HumanoidRootPart")
        gatherCF = h and h.CFrame or nil
    end
end

local function ClearBring()
    bringTarget, gatherCF = nil, nil
end

local function BringTick()
    if not State.Bring or not State.Farm or not bringTarget or not gatherCF then return end
    local pHrp = bringTarget:FindFirstChild("HumanoidRootPart")
    local pHum = bringTarget:FindFirstChildOfClass("Humanoid")
    if not pHrp or not pHum or pHum.Health <= 0 then
        ClearBring()
        return
    end

    if os.clock() - lastSimRadius > 1 then
        lastSimRadius = os.clock()
        pcall(function()
            if sethiddenproperty then
                sethiddenproperty(LocalPlayer, "SimulationRadius", 1e9)
                sethiddenproperty(LocalPlayer, "MaximumSimulationRadius", 1e9)
            end
        end)
    end

    local enemies = workspace:FindFirstChild("Enemies")
    if not enemies then return end
    local base = BaseName(bringTarget.Name)

    for _, mob in ipairs(enemies:GetChildren()) do
        if BaseName(mob.Name) == base then
            local hum = mob:FindFirstChildOfClass("Humanoid")
            local mHrp = mob:FindFirstChild("HumanoidRootPart")
            if hum and mHrp and hum.Health > 0
                and (mHrp.Position - gatherCF.Position).Magnitude < 250
                and Owned(mHrp) then
                mHrp.CanCollide = false
                hum.WalkSpeed = 0
                mHrp.AssemblyLinearVelocity = Vector3.zero
                mHrp.AssemblyAngularVelocity = Vector3.zero
                mHrp.CFrame = gatherCF
            end
        end
    end
end

Connect(RunService.Heartbeat, function()
    if alive then pcall(BringTick) end
end)

-- [v22.14] Исправленный InputAllowed: блокирует клики ТОЛЬКО если фокус в чате
local function InputAllowed()
    if UserInputService:GetFocusedTextBox() then return false end
    return true
end

local function AimMouseAt(worldPos)
local vp = Camera.ViewportSize
    local pt = Vector2.new(vp.X * 0.5, vp.Y * 0.5)
    local v, on = Camera:WorldToViewportPoint(worldPos)
    if on and v.Z > 0 then
        pt = Vector2.new(v.X, v.Y)
    end
    pcall(function() VIM:SendMouseMoveEvent(pt.X, pt.Y, game) end)
    return pt
end
-- ==================== ЧИСТЫЙ СЕТЕВОЙ FAST ATTACK (БЕЗ КЛИКОВ И БЕЗ АНИМАЦИЙ) ====================
local NetModules = ReplicatedStorage:WaitForChild("Modules", 5) and ReplicatedStorage.Modules:WaitForChild("Net", 5)
local RegisterAttack = NetModules and NetModules:FindFirstChild("RE/RegisterAttack")
local RegisterHit = NetModules and NetModules:FindFirstChild("RE/RegisterHit")

local function FastClickAura(radius)
    local char = LocalPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    local tool = char and char:FindFirstChildOfClass("Tool")
    if not hrp or not tool then return end

    local enemies = workspace:FindFirstChild("Enemies")
    if not enemies then return end

    local hitList = {}
    local primaryPart = nil

    for _, mob in ipairs(enemies:GetChildren()) do
        local hum = mob:FindFirstChildOfClass("Humanoid")
        local mHrp = mob:FindFirstChild("HumanoidRootPart")
        if hum and mHrp and hum.Health > 0 then
            if (mHrp.Position - hrp.Position).Magnitude <= (radius or 55) then
                if not primaryPart then
                    primaryPart = mHrp
                end
                table.insert(hitList, {mob, mHrp})
            end
        end
    end

    if primaryPart and #hitList > 0 then
        if RegisterAttack then
            pcall(function() RegisterAttack:FireServer(0) end)
        end
        if RegisterHit then
            pcall(function() RegisterHit:FireServer(primaryPart, hitList) end)
        end
    end
end

local function PerformAttack(targetPos)
    if targetPos then
        Camera.CFrame = CFrame.lookAt(Camera.CFrame.Position, targetPos)
    end
    FastClickAura(55)
end

-- ==================== ИНТЕРФЕЙС ====================
local COL = {
    card = Color3.fromRGB(21, 23, 30),
    stroke = Color3.fromRGB(30, 33, 44),
    accent = Color3.fromRGB(47, 107, 255),
    off = Color3.fromRGB(34, 38, 50),
    text = Color3.fromRGB(240, 242, 248),
    sub = Color3.fromRGB(110, 115, 130),
}

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "XenoModernHub"
ScreenGui.ResetOnSpawn = false
ScreenGui.Parent = TargetParent

local function Round(obj, r)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, r)
    c.Parent = obj
end

local function Stroke(obj, color, th)
    local s = Instance.new("UIStroke")
    s.Thickness = th or 1
    s.Color = color
    s.Parent = obj
end

local function Label(parent, text, pos, size, font, color, tsize)
    local l = Instance.new("TextLabel")
    l.Parent = parent
    l.Position = pos
    l.Size = size
    l.BackgroundTransparency = 1
    l.Font = font
    l.Text = text
    l.TextColor3 = color
    l.TextSize = tsize
    l.TextXAlignment = Enum.TextXAlignment.Left
    return l
end

local OpenBtn = Instance.new("TextButton")
OpenBtn.Name = "OpenBtn"
OpenBtn.Parent = ScreenGui
OpenBtn.Size = UDim2.new(0, 38, 0, 38)
OpenBtn.Position = UDim2.new(0, 15, 0, 140)
OpenBtn.BackgroundColor3 = Color3.fromRGB(15, 16, 22)
OpenBtn.Text = "⚡"
OpenBtn.TextColor3 = Color3.fromRGB(56, 136, 255)
OpenBtn.TextSize = 18
OpenBtn.Font = Enum.Font.GothamBold
OpenBtn.Visible = false
OpenBtn.Active = true
OpenBtn.Draggable = true
Round(OpenBtn, 10)
Stroke(OpenBtn, Color3.fromRGB(45, 50, 68), 1.2)

local Main = Instance.new("Frame")
Main.Name = "Main"
Main.Parent = ScreenGui
Main.Size = UDim2.new(0, 560, 0, 330)
Main.Position = UDim2.new(0.5, -280, 0.5, -165)
Main.BackgroundColor3 = Color3.fromRGB(15, 16, 21)
Main.BorderSizePixel = 0
Round(Main, 10)
Stroke(Main, Color3.fromRGB(32, 35, 46), 1)

OpenBtn.MouseButton1Click:Connect(function()
    OpenBtn.Visible = false
    Main.Visible = true
end)

local Sidebar = Instance.new("Frame")
Sidebar.Name = "Sidebar"
Sidebar.Parent = Main
Sidebar.Size = UDim2.new(0, 155, 1, 0)
Sidebar.BackgroundColor3 = Color3.fromRGB(12, 13, 17)
Sidebar.BorderSizePixel = 0
Round(Sidebar, 10)

local SideList = Instance.new("UIListLayout")
SideList.Parent = Sidebar
SideList.SortOrder = Enum.SortOrder.LayoutOrder
SideList.Padding = UDim.new(0, 4)

local SidePad = Instance.new("UIPadding")
SidePad.Parent = Sidebar
SidePad.PaddingTop = UDim.new(0, 12)
SidePad.PaddingLeft = UDim.new(0, 8)
SidePad.PaddingRight = UDim.new(0, 8)

local TopHeader = Instance.new("Frame")
TopHeader.Name = "TopHeader"
TopHeader.Parent = Main
TopHeader.Position = UDim2.new(0, 155, 0, 0)
TopHeader.Size = UDim2.new(1, -155, 0, 50)
TopHeader.BackgroundTransparency = 1

local HeaderTitle = Label(TopHeader, "Main Farm", UDim2.new(0, 14, 0, 8), UDim2.new(0, 180, 0, 20),
    Enum.Font.GothamBold, Color3.fromRGB(245, 246, 250), 16)
local StatusLabel = Label(TopHeader, "v22.14 | idle", UDim2.new(0, 14, 0, 28), UDim2.new(0, 280, 0, 14),
    Enum.Font.Gotham, COL.sub, 11)
local lastStatus = ""
local function SetStatus(s)
    if s ~= lastStatus then
        lastStatus = s
        StatusLabel.Text = "v22.14 | " .. s
        local st = Diag.status
        st[#st + 1] = string.format("[%s] %s", os.date("%H:%M:%S"), s)
        if #st > 60 then table.remove(st, 1) end
    end
end

local MinimizeBtn = Instance.new("TextButton")
MinimizeBtn.Parent = TopHeader
MinimizeBtn.Position = UDim2.new(1, -40, 0, 14)
MinimizeBtn.Size = UDim2.new(0, 26, 0, 22)
MinimizeBtn.BackgroundColor3 = Color3.fromRGB(22, 25, 34)
MinimizeBtn.BorderSizePixel = 0
MinimizeBtn.Font = Enum.Font.GothamBold
MinimizeBtn.Text = "—"
MinimizeBtn.TextColor3 = Color3.fromRGB(180, 186, 205)
MinimizeBtn.TextSize = 13
Round(MinimizeBtn, 6)
Stroke(MinimizeBtn, Color3.fromRGB(38, 43, 58), 1)
MinimizeBtn.MouseButton1Click:Connect(function()
    Main.Visible = false
    OpenBtn.Visible = true
end)

local dragging, dragStart, startPos = false, nil, nil
local function IsPointer(t)
    return t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch
end
TopHeader.InputBegan:Connect(function(input)
    if IsPointer(input.UserInputType) then
        dragging = true
        dragStart = input.Position
        startPos = Main.Position
        input.Changed:Connect(function()
            if input.UserInputState == Enum.UserInputState.End then dragging = false end
        end)
    end
end)
Connect(UserInputService.InputChanged, function(input)
    if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
        or input.UserInputType == Enum.UserInputType.Touch) then
        local d = input.Position - dragStart
        Main.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
    end
end)

local Container = Instance.new("Frame")
Container.Name = "Container"
Container.Parent = Main
Container.Position = UDim2.new(0, 155, 0, 52)
Container.Size = UDim2.new(1, -155, 1, -52)
Container.BackgroundTransparency = 1

local Tabs = {}

local function SelectTab(name)
    for n, t in pairs(Tabs) do
        local on = (n == name)
        t.Page.Visible = on
        t.Btn.BackgroundTransparency = on and 0 or 1
        t.Btn.BackgroundColor3 = Color3.fromRGB(24, 26, 34)
        t.Label.TextColor3 = on and Color3.fromRGB(245, 246, 250) or Color3.fromRGB(120, 125, 140)
        t.Indicator.Visible = on
    end
    HeaderTitle.Text = name
end

local function CreateTab(name, icon)
    local Page = Instance.new("ScrollingFrame")
    Page.Name = name .. "Page"
    Page.Parent = Container
    Page.Size = UDim2.new(1, -14, 1, -10)
    Page.Position = UDim2.new(0, 8, 0, 0)
    Page.BackgroundTransparency = 1
    Page.BorderSizePixel = 0
    Page.ScrollBarThickness = 3
    Page.ScrollBarImageColor3 = Color3.fromRGB(45, 48, 62)
    Page.Visible = false
    Page.AutomaticCanvasSize = Enum.AutomaticSize.Y
    Page.CanvasSize = UDim2.new(0, 0, 0, 0)

    local PageList = Instance.new("UIListLayout")
    PageList.Parent = Page
    PageList.SortOrder = Enum.SortOrder.LayoutOrder
    PageList.Padding = UDim.new(0, 7)

    local TabBtn = Instance.new("TextButton")
    TabBtn.Name = name .. "Btn"
    TabBtn.Parent = Sidebar
    TabBtn.Size = UDim2.new(1, 0, 0, 34)
    TabBtn.BackgroundTransparency = 1
    TabBtn.AutoButtonColor = false
    TabBtn.Text = ""
    Round(TabBtn, 6)

    local Indicator = Instance.new("Frame")
    Indicator.Parent = TabBtn
    Indicator.Position = UDim2.new(0, 0, 0.22, 0)
    Indicator.Size = UDim2.new(0, 3, 0.56, 0)
    Indicator.BackgroundColor3 = COL.accent
    Indicator.BorderSizePixel = 0
    Indicator.Visible = false
    Round(Indicator, 2)

    local Lbl = Label(TabBtn, icon .. "   " .. name, UDim2.new(0, 12, 0, 0), UDim2.new(1, -12, 1, 0),
        Enum.Font.GothamMedium, Color3.fromRGB(120, 125, 140), 12)

    Tabs[name] = {Page = Page, Btn = TabBtn, Label = Lbl, Indicator = Indicator}
    TabBtn.MouseButton1Click:Connect(function() SelectTab(name) end)
    return Page
end

local function AddSection(page, text)
    return Label(page, text, UDim2.new(), UDim2.new(1, -4, 0, 22), Enum.Font.GothamBold,
        Color3.fromRGB(180, 185, 200), 13)
end

local function MakeCard(page, h, asButton)
    local Card = Instance.new(asButton and "TextButton" or "Frame")
    Card.Size = UDim2.new(1, -6, 0, h)
    Card.BackgroundColor3 = COL.card
    Card.BorderSizePixel = 0
    if asButton then
        Card.AutoButtonColor = false
        Card.Text = ""
    end
    Card.Parent = page
    Round(Card, 7)
    Stroke(Card, COL.stroke, 1)
    return Card
end

local function AddToggle(page, title, subtitle, default, callback)
    local Card = MakeCard(page, 48, false)
    Label(Card, title, UDim2.new(0, 12, 0, 7), UDim2.new(1, -65, 0, 16), Enum.Font.GothamMedium, COL.text, 12)
    Label(Card, subtitle or "", UDim2.new(0, 12, 0, 25), UDim2.new(1, -65, 0, 14), Enum.Font.Gotham, COL.sub, 10)

    local Switch = Instance.new("TextButton")
    Switch.Parent = Card
    Switch.Position = UDim2.new(1, -46, 0.5, -10)
    Switch.Size = UDim2.new(0, 36, 0, 20)
    Switch.BorderSizePixel = 0
    Switch.Text = ""
    Switch.AutoButtonColor = false
    Round(Switch, 10)

    local Knob = Instance.new("Frame")
    Knob.Parent = Switch
    Knob.Size = UDim2.new(0, 14, 0, 14)
    Knob.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    Knob.BorderSizePixel = 0
    Round(Knob, 7)

    local cfgKey = "t:" .. title
    local initial = Cfg(cfgKey, default)
    local state = initial
    local function Apply(animate)
        local pos = state and UDim2.new(1, -17, 0.5, -7) or UDim2.new(0, 3, 0.5, -7)
        local col = state and COL.accent or COL.off
        if animate then
            TweenService:Create(Knob, TweenInfo.new(0.16), {Position = pos}):Play()
            TweenService:Create(Switch, TweenInfo.new(0.16), {BackgroundColor3 = col}):Play()
        else
            Knob.Position = pos
            Switch.BackgroundColor3 = col
        end
    end
    Apply(false)

    local obj = {}
    function obj:Set(v, fire)
        if v == state then return end
        state = v
        CfgSet(cfgKey, state)
        Apply(true)
        if fire then task.spawn(callback, state) end
    end
    local function Click() obj:Set(not state, true) end

    Switch.MouseButton1Click:Connect(Click)
    local Hit = Instance.new("TextButton")
    Hit.Parent = Card
    Hit.Size = UDim2.new(1, -50, 1, 0)
    Hit.BackgroundTransparency = 1
    Hit.Text = ""
    Hit.MouseButton1Click:Connect(Click)

    if initial ~= default then
        table.insert(PendingToggles, function() callback(initial) end)
    end
    return obj
end

local function AddAction(page, title, subtitle, callback)
    local Card = MakeCard(page, 44, true)
    Label(Card, title, UDim2.new(0, 12, 0, 6), UDim2.new(1, -40, 0, 16), Enum.Font.GothamMedium, COL.text, 12)
    Label(Card, subtitle or "", UDim2.new(0, 12, 0, 23), UDim2.new(1, -40, 0, 14), Enum.Font.Gotham, COL.sub, 10)
    local Arrow = Label(Card, ">", UDim2.new(1, -26, 0.5, -8), UDim2.new(0, 16, 0, 16), Enum.Font.GothamBold,
        Color3.fromRGB(90, 95, 110), 13)
    Arrow.TextXAlignment = Enum.TextXAlignment.Center

    Card.MouseButton1Click:Connect(function()
        TweenService:Create(Card, TweenInfo.new(0.08), {BackgroundColor3 = Color3.fromRGB(28, 31, 40)}):Play()
        task.delay(0.08, function()
            TweenService:Create(Card, TweenInfo.new(0.15), {BackgroundColor3 = COL.card}):Play()
        end)
        task.spawn(callback)
    end)
end

local function AddCycle(page, title, subtitle, options, cfgKey, onChange)
    local idx = 1
    local saved = Cfg(cfgKey, options[1])
    for i, o in ipairs(options) do if o == saved then idx = i end end

    local Card = MakeCard(page, 44, true)
    Label(Card, title, UDim2.new(0, 12, 0, 6), UDim2.new(1, -130, 0, 16), Enum.Font.GothamMedium, COL.text, 12)
    Label(Card, subtitle or "", UDim2.new(0, 12, 0, 23), UDim2.new(1, -130, 0, 14), Enum.Font.Gotham, COL.sub, 10)
    local Val = Label(Card, options[idx], UDim2.new(1, -118, 0.5, -8), UDim2.new(0, 106, 0, 16),
        Enum.Font.GothamBold, COL.accent, 12)
    Val.TextXAlignment = Enum.TextXAlignment.Right

    task.defer(onChange, options[idx])
    Card.MouseButton1Click:Connect(function()
        idx = idx % #options + 1
        Val.Text = options[idx]
        CfgSet(cfgKey, options[idx])
        task.spawn(onChange, options[idx])
        Notify(title .. ": " .. options[idx])
    end)
end

-- ==================== ВКЛАДКИ ====================
local FarmPage = CreateTab("Main Farm", "🌾")
local CombatPage = CreateTab("Combat", "⚔️")
local FruitPage = CreateTab("Fruits", "🍓")
local TeleportPage = CreateTab("Teleports", "📍")
local WorldPage = CreateTab("World", "🌍")
local SettingsPage = CreateTab("Settings", "⚙️")
local AdminPage = CreateTab("Adm Perms", "🛠️")
SelectTab("Main Farm")

-- ==================== ОСНОВНОЙ АВТОФАРМ ====================
local spawnSetFor = nil
local activeQ = nil
local FarmToggle, ChestToggle

local pvpIgnoreUntil = 0
local friendCache = {}
local function IsFriend(pl)
    if friendCache[pl.UserId] == nil then
        local ok, r = pcall(function() return LocalPlayer:IsFriendsWith(pl.UserId) end)
        friendCache[pl.UserId] = (ok and r) and true or false
    end
    return friendCache[pl.UserId]
end

local function NearestThreat(pos, radius)
    local best, bd = nil, radius
    for _, pl in ipairs(Players:GetPlayers()) do
        if pl ~= LocalPlayer and pl.Character then
            local h = pl.Character:FindFirstChild("HumanoidRootPart")
            if h then
                local d = (h.Position - pos).Magnitude
                if d < bd and not IsFriend(pl) then best, bd = pl, d end
            end
        end
    end
    return best, bd
end

local deaths = 0
local respawnedAt = 0
Connect(LocalPlayer.CharacterAdded, function()
    respawnedAt = os.clock()
    if State.Farm then
        deaths = deaths + 1
        Notify("Респавн #" .. deaths .. ", возвращаюсь к фарму")
    end
end)

local hoverMin, hoverMax = 7.3, 20
local hoverNow = hoverMin
local retreatCooldown = 0
local hpTrack = {mob = nil, hp = 0, t = 0}

local frontLock = {mob = nil, dir = nil}
local FRONT_DIST = {["Близко"] = {5, 3}, ["Средне"] = {8, 4}, ["Далеко"] = {12, 5}}
local function FrontPosition(target, tHrp, fromPos)
    local mobPos = tHrp.Position
    if frontLock.mob ~= target then
        local look = tHrp.CFrame.LookVector
        local flat = Vector3.new(look.X, 0, look.Z)
        if flat.Magnitude < 0.1 then
            flat = Vector3.new(fromPos.X - mobPos.X, 0, fromPos.Z - mobPos.Z)
        end
        if flat.Magnitude < 0.1 then flat = Vector3.new(0, 0, 1) end
        frontLock = {mob = target, dir = flat.Unit}
    end
    local char = LocalPlayer.Character
    local tool = char and char:FindFirstChildOfClass("Tool")
    local fd = FRONT_DIST[State.FrontDist or "Близко"] or FRONT_DIST["Близко"]
    local dist = (tool and tool.ToolTip == "Blox Fruit") and fd[1] or fd[2]
    local yOff = 2 + (hoverNow - hoverMin)
    return mobPos + frontLock.dir * dist + Vector3.new(0, yOff, 0)
end

local function HookHealth(char)
    local hum = char:WaitForChild("Humanoid", 10)
    if not hum then return end
    local last = hum.Health
    hum.HealthChanged:Connect(function(hp)
        if alive and State.Farm and hp < last - 0.5 then
            hoverNow = math.min(hoverMax, hoverNow + 2.5)
        end
        last = hp
    end)
end
if LocalPlayer.Character then task.spawn(HookHealth, LocalPlayer.Character) end
Connect(LocalPlayer.CharacterAdded, function(c)
    hoverNow = hoverMin
    task.spawn(HookHealth, c)
end)

local remoteQuestOK, remoteFails = nil, 0
local function TryStartQuest(qd)
    local a0, b0 = ReadProgress()
    local before = a0 and (a0 .. "/" .. b0) or nil
    Invoke("StartQuest", qd.Quest, qd.Id)
    questTakenAt = os.clock()
    questTakenFor = qd.Mob
    takenKey = QuestKey(qd)
    ResetProgressWatch()
    task.wait(0.5)
    local a, b = ReadProgress()
    local now = a and (a .. "/" .. b) or nil
    return now ~= nil and (a == 0 or now ~= before)
end

local lastStepT = os.clock()
local function StepToward(hrp, goal, lookAt, maxSpeed)
    local now = os.clock()
    local dt = math.clamp(now - lastStepT, 0.016, 0.2)
    lastStepT = now
    local delta = goal - hrp.Position
    local d = delta.Magnitude
    local maxStep = maxSpeed * dt
    local pos = (d <= maxStep) and goal or (hrp.Position + delta.Unit * maxStep)
    if (pos - lookAt).Magnitude < 0.5 then
        hrp.CFrame = CFrame.new(pos)
    else
        hrp.CFrame = CFrame.lookAt(pos, lookAt)
    end
end

local function RiseBy(hrp, dy)
    CancelFlight()
    local id = flightId
    RemoveHold()
    LinearFly(hrp, hrp.Position + Vector3.new(0, dy, 0), 150, id)
    flying = false
    EnsureHold()
end

local lastFarmPos, lastFarmPosT, acRollbacks = nil, 0, 0

local function GetLearnedNpc(q)
    local t = Cfg("npc:" .. q.Quest, nil)
    if type(t) == "table" and type(t[1]) == "number" and type(t[2]) == "number" and type(t[3]) == "number" then
        return Vector3.new(t[1], t[2], t[3])
    end
    return nil
end
local function SetLearnedNpc(q, pos)
    CfgSet("npc:" .. q.Quest, {pos.X, pos.Y, pos.Z})
end

local function FarmStep(run)
    local char = LocalPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if not hrp or not hum or hum.Health <= 0 then
        SetStatus("умер, жду респавн (смертей: " .. deaths .. ")")
        task.wait(0.5)
        return
    end
    if os.clock() - respawnedAt < 1.5 then
        SetStatus("респавн, загружаюсь...")
        task.wait(0.3)
        return
    end

    if lastFarmPos and not flying and os.clock() - lastFarmPosT < 0.5
        and (hrp.Position - lastFarmPos).Magnitude > 70 then
        acRollbacks = acRollbacks + 1
        flySpeed = math.max(120, math.floor(flySpeed * 0.8))
        SetStatus("сервер откатил позицию #" .. acRollbacks .. ", скорость " .. flySpeed)
        CancelFlight()
        task.wait(0.4)
    end

    EnsureBuso()
    Diag.camTarget = nil

    local retreatAt = (os.clock() < retreatCooldown) and 0.15 or 0.30
    if hum.Health < hum.MaxHealth * retreatAt then
        RiseBy(hrp, 80)
        local t0 = os.clock()
        while alive and State.Farm and run == farmRun and hum.Health > 0
            and hum.Health < hum.MaxHealth * 0.60 and os.clock() - t0 < 12 do
            SetStatus(string.format("восстанавливаю ХП %d%%", math.floor(hum.Health / hum.MaxHealth * 100)))
            task.wait(0.5)
        end
        retreatCooldown = os.clock() + 25
        return
    end

    if State.AntiPvP and os.clock() > pvpIgnoreUntil then
        local pl = NearestThreat(hrp.Position, 120)
        if pl then
            local groundPos = hrp.Position
            RiseBy(hrp, 150)
            Notify("Анти-PvP: рядом игрок " .. pl.Name, 3)
            local t0, left = os.clock(), false
            while alive and State.Farm and run == farmRun and hum.Health > 0 and os.clock() - t0 < 20 do
                SetStatus("анти-PvP: жду, пока уйдёт " .. pl.Name)
                if not NearestThreat(groundPos, 160) then left = true break end
                task.wait(0.5)
            end
            if not left then
                pvpIgnoreUntil = os.clock() + 30
                Notify("Анти-PvP: игрок не уходит, продолжаю фарм", 3)
            end
            return
        end
    end

    local q = GetCurrentQuest()
    if activeQ and activeQ ~= q and IsQuestActive(activeQ) then
        q = activeQ
    end

    -- ШАГ 1: квест
    if not IsQuestActive(q) then
        local key = QuestKey(q)
        if lastQuestKey ~= key then
            lastQuestKey = key
            if AnyQuestShown() then
                SetStatus("сбрасываю старый квест")
                Invoke("AbandonQuest")
                task.wait(0.4)
            end
        end

        if remoteQuestOK ~= false and (hrp.Position - (GetLearnedNpc(q) or q.NpcPos)).Magnitude > 150 then
            SetStatus("квест: пробую взять издалека " .. q.Quest)
            if TryStartQuest(q) then
                remoteQuestOK = true
                remoteFails = 0
                activeQ = q
                return
            end
            takenKey = nil
            remoteFails = remoteFails + 1
            if remoteQuestOK == nil or remoteFails >= 2 then remoteQuestOK = false end
        end

        local learned = GetLearnedNpc(q)
        resolveNpcName = q.NpcName
        local live = FindNpcByName(q.NpcName, hrp.Position)
        local npcNom = (live and live.Position) or learned or q.NpcPos
        local npc = npcNom + Vector3.new(0, 1.5, 0)
        SetStatus("квест: лечу к NPC (" .. q.Quest .. ") v=" .. flySpeed)
        lastNpcFinal = nil
        if not SafeFlyTo(npc, ResolveNpc, true) then
            task.wait(0.5)
            return
        end
        if run ~= farmRun then return end
        npc = lastNpcFinal or npc

        local tookQuest = false
        for attempt = 1, 8 do
            if not (alive and State.Farm and run == farmRun) then return end
            local c = LocalPlayer.Character
            local h = c and c:FindFirstChild("HumanoidRootPart")
            if not h then return end
            if (h.Position - npc).Magnitude > 30 then
                SetStatus("отбросило от NPC, лечу снова")
                return
            end
            SetStatus("квест: беру " .. q.Quest .. " (" .. attempt .. "/8)")
            Invoke("StartQuest", q.Quest, q.Id)
            questTakenAt = os.clock()
            questTakenFor = q.Mob
            takenKey = QuestKey(q)
            ResetProgressWatch()
            task.wait(0.3)
            if IsQuestActive(q) then
                tookQuest = true
                activeQ = q
                local pn = GetQuestPanel()
                if pn and pn.Visible then panelVisOK = true end
                SetLearnedNpc(q, h.Position)
                if spawnSetFor ~= q.Quest then
                    spawnSetFor = q.Quest
                    Invoke("SetSpawnPoint")
                end
                break
            end
        end
        if not tookQuest then
            local lv = 1
            pcall(function() lv = LocalPlayer.Data.Level.Value end)
            questFail[QuestKey(q)] = lv
            takenKey = nil
            lastQuestKey = nil
            Notify("Квест " .. q.Quest .. " не берётся на ур. " .. lv .. ", беру предыдущий", 3)
        end
        return
    end

    -- ШАГ 2: ближайший живой моб
    local target = GetLiveMob(q.Mob, hrp.Position)
    local tHrp = target and target:FindFirstChild("HumanoidRootPart")
    if tHrp then
        SetBringTarget(target)
        local mobPos = tHrp.Position
        lastMobSeen[q.Mob] = mobPos
        Diag.camTarget = mobPos

        local hoverPos = State.Front and FrontPosition(target, tHrp, hrp.Position)
            or (mobPos + Vector3.new(0, hoverNow, 0))

        local approach = (hrp.Position - hoverPos).Magnitude
        if approach > 25 then
            SetStatus("лечу к мобу " .. q.Mob .. " [" .. tostring(lastProgress) .. "]")
            if approach <= 150 then
                StepToward(hrp, hoverPos, mobPos, 220)
                EnsureHold()
            else
                SafeFlyTo(hoverPos, nil, nil, true)
            end
        else
            local th = target:FindFirstChildOfClass("Humanoid")
            if hpTrack.mob ~= target then
                hpTrack = {mob = target, hp = th and th.Health or 0, t = os.clock()}
            elseif th then
                if th.Health < hpTrack.hp - 0.5 then
                    hpTrack.hp = th.Health
                    hpTrack.t = os.clock()
                    progChangedAt = os.clock()
                elseif os.clock() - hpTrack.t > 3.5 and hoverNow > hoverMin then
                    hoverNow = math.max(hoverMin, hoverNow - 1.5)
                    hpTrack.t = os.clock()
                end
            end

            SetStatus(string.format("Fast Click: %s [%s]", q.Mob, tostring(lastProgress)))
            StepToward(hrp, hoverPos, mobPos, 140)
            EnsureHold()
            EnsureWeaponEquipped()
            PerformAttack(mobPos)
        end
    else
        -- ШАГ 3: мобов нет
        ClearBring()
        local sp, src = GetDynamicSpawn(q.Mob, q.MobPos, hrp.Position)
        SetStatus("ищу " .. q.Mob .. " (" .. src .. ")")
        SafeFlyTo(sp + Vector3.new(0, 10, 0), src == "table" and ResolveGround or nil)
        task.wait(0.4)
    end
end

local function StartFarm()
    farmRun = farmRun + 1
    local run = farmRun
    task.spawn(function()
        while alive and State.Farm and run == farmRun do
            task.wait(0.04)
            local ok, err = pcall(FarmStep, run)
            if not ok then
                local e = Diag.errors
                e[#e + 1] = string.format("[%s] FarmStep: %s", os.date("%H:%M:%S"), tostring(err))
                if #e > 30 then table.remove(e, 1) end
            end
            local c = LocalPlayer.Character
            local h = c and c:FindFirstChild("HumanoidRootPart")
            lastFarmPos = h and h.Position or nil
            lastFarmPosT = os.clock()
        end
        if run == farmRun then
            CancelFlight()
            RemoveHold()
        end
    end)
end

-- ==================== СТАТИСТИКА СЕССИИ ====================
local function Num(n)
    n = math.floor(n + 0.5)
    local sign = n < 0 and "-" or ""
    local s = tostring(math.abs(n))
    s = string.reverse(s)
    s = string.gsub(s, "(%d%d%d)", "%1,")
    s = string.reverse(s)
    s = string.gsub(s, "^,", "")
    return sign .. s
end

local function ReadData(name)
    local ok, v = pcall(function() return LocalPlayer.Data[name].Value end)
    return ok and v or nil
end

local sess = {lvl0 = ReadData("Level"), beli0 = ReadData("Beli"), active = 0}

AddSection(FarmPage, "Session")
local SessCard = MakeCard(FarmPage, 64, false)
local SessLbl = Label(SessCard, "", UDim2.new(0, 12, 0, 6), UDim2.new(1, -24, 1, -12),
    Enum.Font.Gotham, COL.text, 11)
SessLbl.TextWrapped = true
SessLbl.TextYAlignment = Enum.TextYAlignment.Top

task.spawn(function()
    while alive do
        task.wait(1)
        if State.Farm then sess.active = sess.active + 1 end
        local lvl, beli = ReadData("Level"), ReadData("Beli")
        local dl = (lvl and sess.lvl0) and (lvl - sess.lvl0) or 0
        local db = (beli and sess.beli0) and (beli - sess.beli0) or 0
        local a = sess.active
        SessLbl.Text = string.format(
            "Время фарма: %02d:%02d:%02d  |  Откатов: %d\nУровней за сессию: +%d\nBeli: %s%s  |  Смертей: %d",
            math.floor(a / 3600), math.floor(a % 3600 / 60), a % 60, acRollbacks,
            math.floor(dl), db >= 0 and "+" or "", Num(db), deaths)
    end
end)

AddSection(FarmPage, "Level Farming")
FarmToggle = AddToggle(FarmPage, "Auto Farm Level", "Авто-квест + Fast Click по мобам", false, function(val)
    State.Farm = val
    if val then
        if State.Chests and ChestToggle then ChestToggle:Set(false, true) end
        StartFarm()
    else
        farmRun = farmRun + 1
        CancelFlight()
        RemoveHold()
    end
end)

AddToggle(FarmPage, "Bring Mobs (Стягивать пачкой)", "Стягивает всех мобов к цели", true, function(val)
    State.Bring = val
end)

AddToggle(FarmPage, "Anti-PvP (взлёт при игроке рядом)", "Уходит в небо, пока чужой игрок рядом", false, function(val)
    State.AntiPvP = val
end)

-- ФАРМ СУНДУКОВ
local function FindClosestChest(fromPos)
    local best, bestDist = nil, math.huge
    local function Consider(container)
        for _, obj in ipairs(container:GetChildren()) do
            if string.sub(obj.Name, 1, 5) == "Chest" then
                local part = obj:IsA("BasePart") and obj or obj:FindFirstChildWhichIsA("BasePart", true)
                if part then
                    local d = (fromPos - part.Position).Magnitude
                    if d < bestDist then best, bestDist = part, d end
                end
            end
        end
    end
    Consider(workspace)
    local models = workspace:FindFirstChild("ChestModels")
    if models then Consider(models) end
    return best
end

AddSection(FarmPage, "Chest Farming")
ChestToggle = AddToggle(FarmPage, "Auto Chest Farm", "Авто-сбор сундуков (ближайший)", false, function(val)
    State.Chests = val
    if val then
        if State.Farm and FarmToggle then FarmToggle:Set(false, true) end
        task.spawn(function()
            while alive and State.Chests do
                local ok = pcall(function()
                    local char = LocalPlayer.Character
                    local hrp = char and char:FindFirstChild("HumanoidRootPart")
                    if not hrp then task.wait(0.5) return end
                    local chest = FindClosestChest(hrp.Position)
                    if chest then
                        SafeFlyTo(chest.Position + Vector3.new(0, 2, 0))
                        task.wait(0.4)
                    else
                        task.wait(2)
                    end
                end)
                if not ok then task.wait(1) end
                task.wait(0.1)
            end
            if not State.Farm then
                CancelFlight()
                RemoveHold()
            end
        end)
    else
        CancelFlight()
        if not State.Farm then RemoveHold() end
    end
end)

-- ==================== COMBAT ====================
AddSection(CombatPage, "Combat")

AddCycle(CombatPage, "Оружие", "Mixed = по очереди фрукт / стиль / меч (каждые 6с)", {"Any", "Blox Fruit", "Sword", "Melee", "Mixed"}, "Weapon", function(v)
    State.Weapon = v
    pcall(EnsureWeaponEquipped)
end)

local fastClickStandalone = false
AddToggle(CombatPage, "Fast Click (AoE Aura)", "Мгновенно уничтожает всех мобов вокруг текущим оружием", false, function(val)
    fastClickStandalone = val
    if val then
        task.spawn(function()
            while alive and fastClickStandalone do
                task.wait(0.08)
                pcall(function() FastClickAura(55) end)
            end
        end)
    end
end)

AddToggle(CombatPage, "Auto Buso Haki", "Держать Хаки включённым", true, function(val)
    State.Buso = val
end)

AddToggle(CombatPage, "Бить перед мобом", "Встаёт перед мобом, а не над ним", true, function(val)
    State.Front = val
end)

AddCycle(CombatPage, "Дистанция до моба", "Клик переключает: Близко / Средне / Далеко", {"Близко", "Средне", "Далеко"}, "FrontDist", function(v)
    State.FrontDist = v
end)

local SkillKeys = {Enum.KeyCode.Z, Enum.KeyCode.X, Enum.KeyCode.C, Enum.KeyCode.V}
AddToggle(CombatPage, "Fruit Skills (Z X C V)", "Жмёт Z X C V текущего оружия во время фарма", false, function(val)
    State.Skills = val
end)
task.spawn(function()
    local i = 0
    while alive do
        task.wait(0.4)
        if State.Farm and State.Skills and bringTarget then
            pcall(function()
                local char = LocalPlayer.Character
                local tool = char and char:FindFirstChildOfClass("Tool")
                if tool and IsWeaponTip(tool.ToolTip) and InputAllowed() then
                    local th = bringTarget:FindFirstChild("HumanoidRootPart")
                    local myH = char:FindFirstChild("HumanoidRootPart")
                    if not th or not myH or (th.Position - myH.Position).Magnitude > 60 then return end
                    AimMouseAt(th.Position)
                    i = i % #SkillKeys + 1
                    VIM:SendKeyEvent(true, SkillKeys[i], false, game)
                    task.wait(0.05)
                    VIM:SendKeyEvent(false, SkillKeys[i], false, game)
                end
            end)
        end
    end
end)

AddToggle(CombatPage, "Камера на мобе", "Наводит камеру на моба", true, function(val)
    State.CamLock = val
end)
pcall(function() RunService:UnbindFromRenderStep("XenoFarmCam") end)
RunService:BindToRenderStep("XenoFarmCam", Enum.RenderPriority.Camera.Value + 1, function()
    if not alive then return end
    local t = Diag.camTarget
    local char = LocalPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if State.Farm and State.CamLock and t and hrp then
        if Camera.CameraType ~= Enum.CameraType.Scriptable then
            if not Diag.camOwned then
                Diag.camZoom = math.clamp((Camera.CFrame.Position - Camera.Focus.Position).Magnitude, 6, 120)
            end
            Camera.CameraType = Enum.CameraType.Scriptable
        end
        Diag.camOwned = true
        local zoom = Diag.camZoom or 14
        local away = hrp.Position - t
        local flat = Vector3.new(away.X, 0, away.Z)
        if flat.Magnitude < 0.5 then flat = Vector3.new(0, 0, 1) end
        Camera.CFrame = CFrame.lookAt(hrp.Position + flat.Unit * (zoom * 0.94) + Vector3.new(0, zoom * 0.34, 0), t)
    elseif Diag.camOwned then
        Diag.camOwned = false
        Camera.CameraType = Enum.CameraType.Custom
    end
end)

AddToggle(CombatPage, "Auto Stats", "Очки: половина в Защиту, половина в выбранный стат", false, function(val)
    State.Stats = val
    if not val then return end
    task.spawn(function()
        while alive and State.Stats do
            task.wait(1.5)
            pcall(function()
                local points = LocalPlayer.Data.Points.Value
                if points and points > 0 then
                    local half = math.floor(points / 2)
                    if half > 0 then
                        Invoke("AddPoint", "Defense", half)
                        local stat = State.StatMode == "Fruit" and "Demon Fruit" or State.StatMode
                        Invoke("AddPoint", stat, points - half)
                    else
                        Invoke("AddPoint", "Defense", 1)
                    end
                end
            end)
        end
    end)
end)

AddCycle(CombatPage, "Стат для Auto Stats", "Вторая половина очков идёт сюда", {"Fruit", "Melee", "Sword"}, "StatMode", function(v)
    State.StatMode = v
end)

-- ==================== FRUITS / ESP ====================
AddSection(FruitPage, "Fruit Utilities & ESP")

local function IsGroundFruit(obj)
    return obj:IsA("Tool") and obj:FindFirstChild("Handle") ~= nil and string.find(string.lower(obj.Name), "fruit", 1, true) ~= nil
end

local fruitESPActive = false
local espTags = {}

local function ClearESP()
    for _, tag in pairs(espTags) do
        if tag then tag:Destroy() end
    end
    espTags = {}
end

AddToggle(FruitPage, "Fruit ESP", "Показывает лежащие фрукты на карте", false, function(val)
    fruitESPActive = val
    if not val then ClearESP() end
end)

task.spawn(function()
    while alive do
        task.wait(1)
        if fruitESPActive then
            pcall(function()
                for obj, tag in pairs(espTags) do
                    if not obj.Parent or obj.Parent ~= workspace then
                        tag:Destroy()
                        espTags[obj] = nil
                    end
                end
                for _, obj in ipairs(workspace:GetChildren()) do
                    if IsGroundFruit(obj) and not espTags[obj] then
                        local bill = Instance.new("BillboardGui")
                        bill.Name = "FruitTag"
                        bill.Adornee = obj.Handle
                        bill.Size = UDim2.new(0, 120, 0, 30)
                        bill.AlwaysOnTop = true
                        bill.Parent = ScreenGui

                        local lbl = Instance.new("TextLabel")
                        lbl.Size = UDim2.new(1, 0, 1, 0)
                        lbl.BackgroundTransparency = 1
                        lbl.TextColor3 = Color3.fromRGB(255, 60, 60)
                        lbl.TextStrokeTransparency = 0.2
                        lbl.Font = Enum.Font.GothamBold
                        lbl.TextSize = 13
                        lbl.Text = "🍓 " .. obj.Name
                        lbl.Parent = bill
                        espTags[obj] = bill
                    end
                end
            end)
        end
    end
end)

local fruitNotify = true
local seenFruits = {}
AddToggle(FruitPage, "Fruit Notifier", "Уведомление, когда на карте появляется фрукт", true, function(val)
    fruitNotify = val
end)

task.spawn(function()
    while alive do
        task.wait(1.5)
        if fruitNotify then
            pcall(function()
                local char = LocalPlayer.Character
                local hrp = char and char:FindFirstChild("HumanoidRootPart")
                for _, obj in ipairs(workspace:GetChildren()) do
                    if IsGroundFruit(obj) and not seenFruits[obj] then
                        seenFruits[obj] = true
                        local d = hrp and math.floor((obj.Handle.Position - hrp.Position).Magnitude) or 0
                        Notify("🍓 Появился фрукт: " .. obj.Name .. " (" .. d .. " studs)", 6)
                    end
                end
                for obj in pairs(seenFruits) do
                    if not obj.Parent then seenFruits[obj] = nil end
                end
            end)
        end
    end
end)

AddAction(FruitPage, "Teleport to Fruit", "Лететь к ближайшему лежащему фрукту", function()
    local char = LocalPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    local best, bestDist = nil, math.huge
    for _, obj in ipairs(workspace:GetChildren()) do
        if IsGroundFruit(obj) then
            local d = (obj.Handle.Position - hrp.Position).Magnitude
            if d < bestDist then best, bestDist = obj, d end
        end
    end
    if best then
        Notify("Летим к: " .. best.Name)
        SafeFlyTo(best.Handle.Position + Vector3.new(0, 3, 0))
        if not State.Farm and not State.Chests then RemoveHold() end
    else
        Notify("Фруктов на земле нет!")
    end
end)

-- ==================== TELEPORTS ====================
local function TP(pos)
    return function()
        if State.Farm and FarmToggle then FarmToggle:Set(false, true) end
        if State.Chests and ChestToggle then ChestToggle:Set(false, true) end
        local target = pos + Vector3.new(0, 14, 0)
        local ok = false
        for attempt = 1, 3 do
            ok = SafeFlyTo(target)
            if ok then break end
            Notify("Телепорт: попытка " .. attempt .. "/3")
            task.wait(0.6)
        end
        CancelFlight()
        RemoveHold()
        if not ok then Notify("Телепорт не удался после 3 попыток") end
    end
end

AddSection(TeleportPage, "All Islands (Sea 1)")
AddAction(TeleportPage, "Pirate Starter", "Стартовый остров пиратов (Lv. 1)", TP(Vector3.new(1013, 17, 1420)))
AddAction(TeleportPage, "Marine Starter", "Стартовый остров дозорных (Lv. 1)", TP(Vector3.new(-2570, 7, 2045)))
AddAction(TeleportPage, "Jungle", "Остров джунглей (Lv. 10)", TP(Vector3.new(-1612, 37, 149)))
AddAction(TeleportPage, "Pirate Village", "Деревня пиратов (Lv. 30)", TP(Vector3.new(-1141, 5, 3824)))
AddAction(TeleportPage, "Desert", "Пустыня (Lv. 60)", TP(Vector3.new(894, 7, 4390)))
AddAction(TeleportPage, "Frozen Village", "Снежная деревня (Lv. 90)", TP(Vector3.new(1385, 87, -1298)))
AddAction(TeleportPage, "Marine Fortress", "Морская крепость (Lv. 120)", TP(Vector3.new(-5036, 29, 4325)))
AddAction(TeleportPage, "Skylands (Lower)", "Нижние Небеса (Lv. 150)", TP(Vector3.new(-4842, 718, -2622)))
AddAction(TeleportPage, "Skylands (Upper)", "Верхние Небеса (Lv. 450)", TP(Vector3.new(-7894, 5547, -380)))
AddAction(TeleportPage, "Prison", "Тюрьма (Lv. 190)", TP(Vector3.new(4854, 6, 743)))
AddAction(TeleportPage, "Colosseum", "Колизей (Lv. 225)", TP(Vector3.new(-1580, 8, -2980)))
AddAction(TeleportPage, "Magma Village", "Остров магмы (Lv. 300)", TP(Vector3.new(-5315, 12, 8515)))
AddAction(TeleportPage, "Underwater City", "Подводный город (Lv. 375)", TP(Vector3.new(61122, 19, 1568)))
AddAction(TeleportPage, "Fountain City", "Город фонтанов (Lv. 625)", TP(Vector3.new(5259, 39, 4050)))

-- ==================== WORLD ====================
AddSection(WorldPage, "Character Movement & Visuals")

local infJump = false
AddToggle(WorldPage, "Infinite Jump", "Бесконечный прыжок в воздухе", false, function(val) infJump = val end)
Connect(UserInputService.JumpRequest, function()
    if infJump and LocalPlayer.Character then
        local hum = LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
        if hum then hum:ChangeState(Enum.HumanoidStateType.Jumping) end
    end
end)

local fastSpeed = false
AddToggle(WorldPage, "Fast Speed", "Увеличенная скорость бега (120)", false, function(val)
    fastSpeed = val
    if not val and LocalPlayer.Character then
        local hum = LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
        if hum then hum.WalkSpeed = 16 end
    end
end)
Connect(RunService.RenderStepped, function()
    if fastSpeed and LocalPlayer.Character then
        local hum = LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
        if hum and hum.WalkSpeed ~= 120 then hum.WalkSpeed = 120 end
    end
end)

local fullBright = false
local origLight = {
    Brightness = Lighting.Brightness,
    ClockTime = Lighting.ClockTime,
    FogEnd = Lighting.FogEnd,
    GlobalShadows = Lighting.GlobalShadows,
}
local function ApplyFullBright()
    Lighting.Brightness = 2
    Lighting.ClockTime = 14
    Lighting.FogEnd = 100000
    Lighting.GlobalShadows = false
end
local function RestoreLighting()
    for k, v in pairs(origLight) do Lighting[k] = v end
end
AddToggle(WorldPage, "FullBright", "Убирает туман и темноту", false, function(val)
    fullBright = val
    if val then
        origLight = {
            Brightness = Lighting.Brightness,
            ClockTime = Lighting.ClockTime,
            FogEnd = Lighting.FogEnd,
            GlobalShadows = Lighting.GlobalShadows,
        }
        ApplyFullBright()
        task.spawn(function()
            while alive and fullBright do
                task.wait(1)
                ApplyFullBright()
            end
        end)
    else
        RestoreLighting()
    end
end)

-- ==================== ЭКСПОРТ И ОБЛЁТ (ADM PERMS) ====================
local function SetupMapExport()
    local SeenNpcs = {}
    local SeenSpawns = {}
    local collectOn = true

    local function R1(n) return math.floor(n + 0.5) end
    local function Fmt(v) return string.format("%d,%d,%d", R1(v.X), R1(v.Y), R1(v.Z)) end

    local function CollectMapData()
        local npcs = workspace:FindFirstChild("NPCs")
        if npcs then
            for _, m in ipairs(npcs:GetChildren()) do
                local part = NpcPart(m)
                if part then
                    local pos = part.Position
                    local key = m.Name .. ":" .. R1(pos.X / 5) .. ":" .. R1(pos.Y / 5) .. ":" .. R1(pos.Z / 5)
                    if not SeenNpcs[key] then SeenNpcs[key] = {name = m.Name, pos = pos} end
                end
            end
        end
        local origin = workspace:FindFirstChild("_WorldOrigin")
        local spawns = origin and origin:FindFirstChild("EnemySpawns")
        if spawns then
            for _, sp in ipairs(spawns:GetChildren()) do
                if sp:IsA("BasePart") then
                    local n = Norm(sp.Name)
                    local rec = SeenSpawns[n]
                    if not rec then
                        rec = {raw = sp.Name, list = {}, keys = {}}
                        SeenSpawns[n] = rec
                    end
                    local pos = sp.Position
                    local key = R1(pos.X / 4) .. ":" .. R1(pos.Y / 4) .. ":" .. R1(pos.Z / 4)
                    if not rec.keys[key] and #rec.list < 300 then
                        rec.keys[key] = true
                        table.insert(rec.list, pos)
                    end
                end
            end
        end
    end

    task.spawn(function()
        while alive do
            if collectOn then pcall(CollectMapData) end
            task.wait(3)
        end
    end)

    local function NearestSeenNpc(pos)
        local best, bd = nil, math.huge
        for _, r in pairs(SeenNpcs) do
            local d = (r.pos - pos).Magnitude
            if d < bd then best, bd = r, d end
        end
        return best, bd
    end

    local function Centroid(list)
        local sum = Vector3.zero
        for _, p in ipairs(list) do sum = sum + p end
        return sum / #list
    end

    local function Clusters(list, radius)
        local cl = {}
        for _, p in ipairs(list) do
            local placed = false
            for _, c in ipairs(cl) do
                if (c.sum / c.n - p).Magnitude < radius then
                    c.sum = c.sum + p
                    c.n = c.n + 1
                    placed = true
                    break
                end
            end
            if not placed then cl[#cl + 1] = {sum = p, n = 1} end
        end
        return cl
    end

    local function BuildExport()
        pcall(CollectMapData)
        local L = {}
        local function add(t) L[#L + 1] = t end

        local team = "?"
        pcall(function() team = LocalPlayer.Team and LocalPlayer.Team.Name or "none" end)
        add("# XenoHub export | PlaceId=" .. game.PlaceId .. " | Level=" .. tostring(ReadData("Level")) .. " | Team=" .. team)
        add("# Данные только по тому, что игра подгрузила рядом с тобой.")

        add("")
        add("## QUESTS (из таблицы скрипта -> что реально найдено)")
        local all = {MarineStartQuest}
        for _, qd in ipairs(QuestsData) do all[#all + 1] = qd end
        for _, qd in ipairs(all) do
            local parts = {string.format("Lv%d %s #%d mob=%s", qd.Level, qd.Quest, qd.Id, qd.Mob)}
            parts[#parts + 1] = "tableNPC=" .. Fmt(qd.NpcPos)
            parts[#parts + 1] = "tableMob=" .. Fmt(qd.MobPos)
            if qd.NpcName then parts[#parts + 1] = "npcName=" .. qd.NpcName end
            local learned = GetLearnedNpc(qd)
            if learned then parts[#parts + 1] = "LEARNED_NPC=" .. Fmt(learned) end
            local cen
            local rec = SeenSpawns[Norm(qd.Mob)]
            if rec and #rec.list > 0 then
                cen = Centroid(rec.list)
                local nd = math.huge
                for _, p in ipairs(rec.list) do nd = math.min(nd, (p - qd.MobPos).Magnitude) end
                parts[#parts + 1] = string.format("realSpawns=%d centroid=%s nearestToTableMob=%d", #rec.list, Fmt(cen), R1(nd))
            else
                parts[#parts + 1] = "realSpawns=none"
            end
            local n1, d1 = NearestSeenNpc(qd.NpcPos)
            if n1 then
                parts[#parts + 1] = string.format("seenNpcNearTable=%s@%s d=%d", n1.name, Fmt(n1.pos), R1(d1))
            end
            if cen then
                local n2, d2 = NearestSeenNpc(cen)
                if n2 then
                    parts[#parts + 1] = string.format("seenNpcNearMobs=%s@%s d=%d", n2.name, Fmt(n2.pos), R1(d2))
                end
            end
            add(table.concat(parts, " | "))
        end

        add("")
        add("## NPCS (все, что видел сборщик): имя | x,y,z")
        local npcList = {}
        for _, r in pairs(SeenNpcs) do npcList[#npcList + 1] = r end
        table.sort(npcList, function(a, b)
            if a.name ~= b.name then return a.name < b.name end
            return a.pos.X < b.pos.X
        end)
        for _, r in ipairs(npcList) do add(r.name .. " | " .. Fmt(r.pos)) end

        add("")
        add("## SPAWNS (имя спавна | точек всего | кластеры центр xN)")
        local names = {}
        for n in pairs(SeenSpawns) do names[#names + 1] = n end
        table.sort(names)
        for _, n in ipairs(names) do
            local rec = SeenSpawns[n]
            local cl = Clusters(rec.list, 150)
            local cs = {}
            for _, c in ipairs(cl) do cs[#cs + 1] = "(" .. Fmt(c.sum / c.n) .. ")x" .. c.n end
            add(string.format("%s | %d | %s", rec.raw, #rec.list, table.concat(cs, " ")))
        end
        return L
    end

    local function DoExport()
        local L = BuildExport()
        local text = table.concat(L, "\n")
        local fileOk, clipOk = false, false
        if writefile then fileOk = pcall(writefile, "XenoHub_Export.txt", text) end
        if setclipboard then clipOk = pcall(setclipboard, text) end
        for _, line in ipairs(L) do print(line) end
        local nNpc, nSp = 0, 0
        for _ in pairs(SeenNpcs) do nNpc = nNpc + 1 end
        for _ in pairs(SeenSpawns) do nSp = nSp + 1 end
        Notify(string.format("Экспорт: NPC %d, спавнов %d", nNpc, nSp), 4)
    end

    local function BuildReport()
        local L = {}
        local function add(t) L[#L + 1] = t end
        local function Cap(name, v) return name .. "=" .. tostring(v ~= nil) end
        local function Clean(t) return (string.gsub(tostring(t), "[\r\n]+", " ")) end

        add("# XenoHub REPORT v22.14 | " .. os.date("%Y-%m-%d %H:%M:%S"))
        local team = "?"
        pcall(function() team = LocalPlayer.Team and LocalPlayer.Team.Name or "none" end)
        add("PlaceId=" .. game.PlaceId .. " | Level=" .. tostring(ReadData("Level")) .. " | Beli=" .. tostring(ReadData("Beli"))
            .. " | Fragments=" .. tostring(ReadData("Fragments")) .. " | Points=" .. tostring(ReadData("Points"))
            .. " | Team=" .. team .. " | Players=" .. #Players:GetPlayers())

        add("")
        add("## EXECUTOR")
        local exName, exVer = "?", "?"
        pcall(function() if identifyexecutor then exName, exVer = identifyexecutor() end end)
        add(tostring(exName) .. " " .. tostring(exVer))
        add(table.concat({Cap("isnetworkowner", isnetworkowner), Cap("sethiddenproperty", sethiddenproperty),
            Cap("RegisterAttack", RegisterAttack), Cap("RegisterHit", RegisterHit),
            Cap("writefile", writefile), Cap("readfile", readfile), Cap("setclipboard", setclipboard)}, " | "))

        add("")
        add("## QUEST STATE")
        local q = GetCurrentQuest()
        add(string.format("current=%s #%s mob=%s npcName=%s npcPos=%s", q.Quest, tostring(q.Id), q.Mob, tostring(q.NpcName), Fmt(q.NpcPos)))
        add("activeQ=" .. (activeQ and (activeQ.Quest .. ":" .. activeQ.Id) or "nil") .. " | takenKey=" .. tostring(takenKey))
        local pa, pb = ReadProgress()
        add("progress=" .. (pa and (pa .. "/" .. pb) or "nil"))

        add("")
        add("## MOVEMENT / COMBAT")
        local c = LocalPlayer.Character
        local hrp = c and c:FindFirstChild("HumanoidRootPart")
        local hum = c and c:FindFirstChildOfClass("Humanoid")
        add("pos=" .. (hrp and Fmt(hrp.Position) or "-") .. " | hp=" .. (hum and (math.floor(hum.Health) .. "/" .. math.floor(hum.MaxHealth)) or "-"))

        add("")
        add("## EXPORT (NPC / спавны)")
        for _, line in ipairs(BuildExport()) do add(line) end
        return L
    end

    local function DoReport()
        local ok, L = pcall(BuildReport)
        if not ok then
            Notify("Ошибка отчёта: " .. tostring(L), 5)
            return
        end
        local text = table.concat(L, "\n")
        if writefile then pcall(writefile, "XenoHub_Report.txt", text) end
        if setclipboard then pcall(setclipboard, text) end
        for _, line in ipairs(L) do print(line) end
        Notify("Отчёт скопирован в буфер обмена и консоль F9", 4)
    end

    local scanRun = 0
    local scanning = false
    local SCAN_POINTS = {
        Vector3.new(1013, 17, 1420), Vector3.new(-2570, 7, 2045), Vector3.new(-1612, 37, 149),
        Vector3.new(-1141, 5, 3824), Vector3.new(894, 7, 4390), Vector3.new(1385, 87, -1298),
        Vector3.new(-5036, 29, 4325), Vector3.new(-4842, 718, -2622), Vector3.new(-7894, 5547, -380),
        Vector3.new(4854, 6, 743), Vector3.new(-1580, 8, -2980), Vector3.new(-5315, 12, 8515),
        Vector3.new(61122, 19, 1568), Vector3.new(5259, 39, 4050),
    }

    local function SaveScanFile()
        if not writefile then return end
        pcall(function() writefile("XenoHub_Export.txt", table.concat(BuildExport(), "\n")) end)
    end

    local function VisitPoint(pos, run)
        for _ = 1, 2 do
            if not (alive and run == scanRun) then return false end
            local char = LocalPlayer.Character
            local hrp = char and char:FindFirstChild("HumanoidRootPart")
            local hum = char and char:FindFirstChildOfClass("Humanoid")
            if not hrp or not hum or hum.Health <= 0 then
                task.wait(2)
            else
                if SafeFlyTo(pos + Vector3.new(0, 30, 0)) then
                    task.wait(1.5)
                    return true
                end
                task.wait(0.5)
            end
        end
        return false
    end

    local function RunMapScan()
        if scanning then Notify("Облёт уже идёт") return end
        scanRun = scanRun + 1
        local run = scanRun
        scanning = true
        if State.Farm and FarmToggle then FarmToggle:Set(false, true) end
        if State.Chests and ChestToggle then ChestToggle:Set(false, true) end
        Notify("Облёт карты запущен", 4)

        task.spawn(function()
            for i, p in ipairs(SCAN_POINTS) do
                if not (alive and run == scanRun) then break end
                SetStatus(string.format("скан: %d/%d", i, #SCAN_POINTS))
                VisitPoint(p, run)
                SaveScanFile()
            end
            if run == scanRun then
                scanning = false
                RemoveHold()
                CancelFlight()
                SetStatus("скан завершён")
                DoExport()
            end
        end)
    end

    local function StopMapScan()
        if not scanning then Notify("Облёт не запущен") return end
        scanRun = scanRun + 1
        scanning = false
        CancelFlight()
        RemoveHold()
        SaveScanFile()
        SetStatus("скан остановлен")
        Notify("Облёт остановлен")
    end

    AddSection(AdminPage, "Отчёт для анализа")
    AddAction(AdminPage, "Полный отчёт", "Все данные квестов, логи, NPC -> буфер + F9", DoReport)
    AddSection(AdminPage, "Map Data Export")
    AddToggle(AdminPage, "Сбор данных карты", "Запоминает NPC и спавны мобов", true, function(val) collectOn = val end)
    AddAction(AdminPage, "Экспорт NPC и спавнов", "Записать данные в консоль и буфер", DoExport)
    AddSection(AdminPage, "Авто-облёт карты")
    AddAction(AdminPage, "Старт: облёт всех островов", "Летает по карте и собирает данные", RunMapScan)
    AddAction(AdminPage, "Стоп облёта", "Остановить облёт", StopMapScan)
end
SetupMapExport()

-- ==================== SETTINGS ====================
AddSection(SettingsPage, "Client & Utility")
AddAction(SettingsPage, "Rejoin Server", "Перезайти на этот же сервер", function()
    pcall(function() TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, LocalPlayer) end)
end)

AddAction(SettingsPage, "Close GUI", "Полностью выгрузить скрипт", function()
    alive = false
    State.Farm, State.Chests, State.Stats = false, false, false
    CfgSet("t:Auto Farm Level", false)
    CfgSet("t:Auto Chest Farm", false)
    CfgSet("t:Auto Stats", false)
    farmRun = farmRun + 1
    infJump, fastSpeed, fruitESPActive = false, false, false
    if fullBright then fullBright = false; RestoreLighting() end
    ClearESP()
    CancelFlight()
    RemoveHold()
    pcall(function() RunService:UnbindFromRenderStep("XenoFarmCam") end)
    if Diag.camOwned then Diag.camOwned = false Camera.CameraType = Enum.CameraType.Custom end
    for _, c in ipairs(Connections) do pcall(function() c:Disconnect() end) end
    Connections = {}
    ScreenGui:Destroy()
end)

AddAction(SettingsPage, "Reset Settings", "Сбросить настройки", function()
    Config = {}
    SaveConfig()
    Notify("Настройки сброшены")
end)

task.delay(2, function()
    if not alive then return end
    for _, fn in ipairs(PendingToggles) do
        task.spawn(function() pcall(fn) end)
    end
    PendingToggles = {}
end)

Notify("Xeno Hub v22.14 загружен! Fast Click активен.")
