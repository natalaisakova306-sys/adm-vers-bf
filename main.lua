-- [[ XENO BLOX FRUITS HUB v23.3 - AUTO RAIDS, ANTI-FAKE MOB & NO-SHAKE EDITION ]] --
-- v23.3: 1) Анти-Фейк НПС (черный список мобов без урона через 4.5с + фильтр приманок),
--        2) Убрана тряска экрана (ровное удержание CFrame + отключение CameraShaker),
--        3) Полностью невидимые хитбоксы (Transparency = 1, Massless = true),
--        4) Удаление огромных эффектов смерти/ударов (No VFX),
--        5) Полный сброс левитации (BodyVelocity) при выключении фарма,
--        6) Новая вкладка Raids: Auto Raid (Island 1-5 + Kill Aura) + Auto Buy/Start Chip.

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
    return LocalPlayer:WaitForChild("PlayerGui", 5) or LocalPlayer.PlayerGui
end

local TargetParent = GetGuiParent()
local old = TargetParent:FindFirstChild("XenoModernHub")
if old then old:Destroy() end

local Remotes = ReplicatedStorage:WaitForChild("Remotes", 5)
local CommF = Remotes and Remotes:WaitForChild("CommF_", 5)

-- Отключаем встроенную тряску камеры Blox Fruits
task.spawn(function()
    pcall(function()
        local util = ReplicatedStorage:WaitForChild("Util", 5)
        local shaker = util and util:FindFirstChild("CameraShaker")
        if shaker then
            local cs = require(shaker)
            if cs and cs.Stop then cs:Stop() end
        end
    end)
end)

-- Поиск сетевых ремоутов урона в фоне
local RegisterAttack, RegisterHit
task.spawn(function()
    pcall(function()
        local net = ReplicatedStorage:WaitForChild("Modules", 3)
        net = net and net:WaitForChild("Net", 3)
        if net then
            RegisterAttack = net:FindFirstChild("RE/RegisterAttack") or net:FindFirstChild("RegisterAttack")
            RegisterHit = net:FindFirstChild("RE/RegisterHit") or net:FindFirstChild("RegisterHit")
        end
    end)
    if not RegisterAttack or not RegisterHit then
        for _, d in ipairs(ReplicatedStorage:GetDescendants()) do
            if d:IsA("RemoteEvent") then
                if d.Name:find("RegisterAttack") then RegisterAttack = d end
                if d.Name:find("RegisterHit") then RegisterHit = d end
            end
        end
    end
end)

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
    AutoRaid = false,
    AutoChip = false,
    Chests = false,
    Stats = false,
    Bring = true,
    Hitbox = true,
    HitboxSize = 55,
    NoVFX = true,
    Buso = true,
    AntiPvP = false,
    Skills = false,
    AtkInterval = 0.08,
    ComboMode = "1-3",
    CamLock = false,
    SeaMode = Cfg("SeaMode", "Auto"),
    RaidChip = Cfg("RaidChip", "Ice"),
    Weapon = Cfg("Weapon", "Any"),
    StatMode = Cfg("StatMode", "Fruit"),
    Hover = 11.5,
}
local farmRun = 0
local raidRun = 0

local Diag = {
    status = {}, errors = {}, hiddenSince = nil,
    spawnCache = {},
    camTarget = nil, camOwned = false,
}

-- Анти-AFK
Connect(LocalPlayer.Idled, function()
    pcall(function()
        VirtualUser:CaptureController()
        VirtualUser:ClickButton2(Vector2.zero)
    end)
end)

-- ==================== УДАЛЕНИЕ ЭФФЕКТОВ СМЕРТИ И ВЗРЫВОВ (NO VFX) ====================
local function CleanEffectInstance(obj)
    if not State.NoVFX then return end
    pcall(function()
        if obj:IsA("ParticleEmitter") or obj:IsA("Trail") or obj:IsA("Beam") or obj:IsA("Smoke") or obj:IsA("Fire") or obj:IsA("Sparkles") then
            obj.Enabled = false
        elseif obj:IsA("Explosion") then
            obj.BlastPressure = 0
            obj.Visible = false
        end
    end)
end

task.spawn(function()
    while alive do
        task.wait(0.35)
        if State.NoVFX then
            pcall(function()
                local eff = workspace:FindFirstChild("Effects")
                if eff then
                    eff:ClearAllChildren()
                end
                local origin = workspace:FindFirstChild("_WorldOrigin")
                if origin then
                    for _, ch in ipairs(origin:GetChildren()) do
                        if ch.Name == "Foam" or ch.Name == "DamageCounter" or ch.Name:find("Effect") or ch.Name:find("Hit") then
                            ch:Destroy()
                        end
                    end
                end
            end)
        end
    end
end)

Connect(workspace.DescendantAdded, function(obj)
    if State.NoVFX then
        CleanEffectInstance(obj)
    end
end)

-- ==================== БАЗЫ КВЕСТОВ SEA 1 И SEA 2 ====================
local Sea1Quests = {
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

local Sea2Quests = {
    {Level = 700, Quest = "Area1Quest", Id = 1, Mob = "Raider", NpcName = "Quest Giver", NpcPos = Vector3.new(-426, 73, 1836), MobPos = Vector3.new(-736, 39, 2388)},
    {Level = 725, Quest = "Area1Quest", Id = 2, Mob = "Mercenary", NpcName = "Quest Giver", NpcPos = Vector3.new(-426, 73, 1836), MobPos = Vector3.new(-874, 141, 1313)},
    {Level = 775, Quest = "Area2Quest", Id = 1, Mob = "Swan Pirate", NpcName = "Quest Giver", NpcPos = Vector3.new(634, 73, 918), MobPos = Vector3.new(878, 122, 1229)},
    {Level = 800, Quest = "Area2Quest", Id = 2, Mob = "Factory Staff", NpcName = "Quest Giver", NpcPos = Vector3.new(634, 73, 918), MobPos = Vector3.new(295, 73, -56)},
    {Level = 875, Quest = "MarineQuest3", Id = 1, Mob = "Marine Lieutenant", NpcName = "Quest Giver", NpcPos = Vector3.new(-2443, 73, -3217), MobPos = Vector3.new(-2806, 73, -3038)},
    {Level = 900, Quest = "MarineQuest3", Id = 2, Mob = "Marine Captain", NpcName = "Quest Giver", NpcPos = Vector3.new(-2443, 73, -3217), MobPos = Vector3.new(-1867, 73, -3320)},
    {Level = 950, Quest = "ZombieQuest", Id = 1, Mob = "Zombie", NpcName = "Quest Giver", NpcPos = Vector3.new(-5495, 48, -794), MobPos = Vector3.new(-5657, 60, -735)},
    {Level = 975, Quest = "ZombieQuest", Id = 2, Mob = "Vampire", NpcName = "Quest Giver", NpcPos = Vector3.new(-5495, 48, -794), MobPos = Vector3.new(-6033, 7, -1317)},
    {Level = 1000, Quest = "SnowMountainQuest", Id = 1, Mob = "Snow Trooper", NpcName = "Quest Giver", NpcPos = Vector3.new(607, 401, -5371), MobPos = Vector3.new(507, 401, -5344)},
    {Level = 1050, Quest = "SnowMountainQuest", Id = 2, Mob = "Winter Warrior", NpcName = "Quest Giver", NpcPos = Vector3.new(607, 401, -5371), MobPos = Vector3.new(1157, 430, -5188)},
    {Level = 1100, Quest = "IceSideQuest", Id = 1, Mob = "Lab Subordinate", NpcName = "Quest Giver", NpcPos = Vector3.new(-6060, 15, -4905), MobPos = Vector3.new(-5775, 40, -4467)},
    {Level = 1125, Quest = "IceSideQuest", Id = 2, Mob = "Horned Warrior", NpcName = "Quest Giver", NpcPos = Vector3.new(-6060, 15, -4905), MobPos = Vector3.new(-6406, 24, -5816)},
    {Level = 1175, Quest = "FireSideQuest", Id = 1, Mob = "Magma Ninja", NpcName = "Quest Giver", NpcPos = Vector3.new(-5430, 15, -5295), MobPos = Vector3.new(-5428, 64, -5855)},
    {Level = 1200, Quest = "FireSideQuest", Id = 2, Mob = "Lava Pirate", NpcName = "Quest Giver", NpcPos = Vector3.new(-5430, 15, -5295), MobPos = Vector3.new(-5234, 42, -4720)},
    {Level = 1250, Quest = "ShipQuest1", Id = 1, Mob = "Ship Deckhand", NpcName = "Quest Giver", NpcPos = Vector3.new(1003, 125, 32969), MobPos = Vector3.new(1194, 125, 32987)},
    {Level = 1275, Quest = "ShipQuest1", Id = 2, Mob = "Ship Engineer", NpcName = "Quest Giver", NpcPos = Vector3.new(1003, 125, 32969), MobPos = Vector3.new(916, 44, 32782)},
    {Level = 1300, Quest = "ShipQuest2", Id = 1, Mob = "Ship Steward", NpcName = "Quest Giver", NpcPos = Vector3.new(969, 125, 33245), MobPos = Vector3.new(915, 130, 33419)},
    {Level = 1325, Quest = "ShipQuest2", Id = 2, Mob = "Ship Officer", NpcName = "Quest Giver", NpcPos = Vector3.new(969, 125, 33245), MobPos = Vector3.new(916, 180, 33340)},
    {Level = 1350, Quest = "FrostQuest", Id = 1, Mob = "Arctic Warrior", NpcName = "Quest Giver", NpcPos = Vector3.new(5567, 28, -6244), MobPos = Vector3.new(6040, 28, -6231)},
    {Level = 1375, Quest = "FrostQuest", Id = 2, Mob = "Snow Lurker", NpcName = "Quest Giver", NpcPos = Vector3.new(5567, 28, -6244), MobPos = Vector3.new(5560, 42, -6826)},
    {Level = 1425, Quest = "ForgottenQuest", Id = 1, Mob = "Sea Soldier", NpcName = "Quest Giver", NpcPos = Vector3.new(-3054, 237, -10142), MobPos = Vector3.new(-3022, 16, -9797)},
    {Level = 1450, Quest = "ForgottenQuest", Id = 2, Mob = "Water Fighter", NpcName = "Quest Giver", NpcPos = Vector3.new(-3054, 237, -10142), MobPos = Vector3.new(-3385, 239, -10542)},
}

local MarineStartQuest = {Level = 1, Quest = "MarineQuest", Id = 1, Mob = "Trainee", NpcName = "Marine Leader",
    NpcPos = Vector3.new(-2655, 31, 2114), MobPos = Vector3.new(-2730, 31, 2216)}

local function IsSea2()
    if State.SeaMode == "Sea 2" then return true end
    if State.SeaMode == "Sea 1" then return false end
    if game.PlaceId == 4442272183 then return true end
    local origin = workspace:FindFirstChild("_WorldOrigin")
    local spawns = origin and origin:FindFirstChild("EnemySpawns")
    if spawns then
        for _, sp in ipairs(spawns:GetChildren()) do
            local n = sp.Name
            if n:find("Raider") or n:find("Mercenary") or n:find("Swan Pirate") or n:find("Factory Staff") then
                return true
            end
        end
    end
    local lvl = 1
    pcall(function() lvl = LocalPlayer.Data.Level.Value end)
    return lvl >= 700
end

local questFail = {}

local function GetCurrentQuest()
    local lvl = 1
    pcall(function() lvl = LocalPlayer.Data.Level.Value end)
    local inSea2 = IsSea2()
    local activeTable = inSea2 and Sea2Quests or Sea1Quests

    if not inSea2 then
        local isMarine = false
        pcall(function() isMarine = LocalPlayer.Team and LocalPlayer.Team.Name == "Marines" end)
        if isMarine and lvl < 10 then return MarineStartQuest end
    end

    local q = activeTable[1]
    for _, item in ipairs(activeTable) do
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

-- ==================== ФИЛЬТР ФЕЙК-НПС (ANTI-DECOY) ====================
local badMobs = {}

local function IsValidMob(mob)
    if not mob or not mob.Parent then return false end
    if badMobs[mob] and badMobs[mob] > os.clock() then return false end
    local hum = mob:FindFirstChildOfClass("Humanoid")
    local hrp = mob:FindFirstChild("HumanoidRootPart")
    if not hum or not hrp then return false end
    if hum.Health <= 0 or hum.MaxHealth <= 10 then return false end
    -- Фейковые приманки античита часто заанкорены или висят глубоко под картой
    if hrp.Anchored or hrp.Position.Y < -100 then return false end
    if not mob:FindFirstChild("Head") and not mob:FindFirstChild("UpperTorso") and not mob:FindFirstChild("Torso") then
        return false
    end
    return true
end

local function GetLiveMob(mobName, fromPos)
    local enemies = workspace:FindFirstChild("Enemies")
    if not enemies then return nil end
    local best, bestDist = nil, math.huge
    local bestOwned, bestOwnedDist = nil, math.huge
    for _, mob in ipairs(enemies:GetChildren()) do
        if IsMobNamed(mob, mobName) and IsValidMob(mob) then
            local hrp = mob.HumanoidRootPart
            local d = fromPos and (hrp.Position - fromPos).Magnitude or 0
            if d < bestDist then
                best, bestDist = mob, d
            end
            if d < bestOwnedDist and GetLiveMobOwned(hrp) then
                bestOwned, bestOwnedDist = mob, d
            end
        end
    end
    return bestOwned or best
end

local function GetAnyRaidMob(fromPos)
    local enemies = workspace:FindFirstChild("Enemies")
    if not enemies then return nil end
    local best, bestDist = nil, math.huge
    for _, mob in ipairs(enemies:GetChildren()) do
        if IsValidMob(mob) then
            local hrp = mob.HumanoidRootPart
            local d = fromPos and (hrp.Position - fromPos).Magnitude or 0
            if d < 1200 and d < bestDist then
                best, bestDist = mob, d
            end
        end
    end
    return best
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
        if m.Name == name or m.Name:find(name, 1, true) then
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

-- ==================== ПОЛЁТ / NOCLIP / СБРОС ЛЕВИТАЦИИ ====================
local flying = false
local flightBV = nil
local currentTween = nil
local flightId = 0
local flySpeed = 260
local rollbackCount = 0

local function RemoveHold()
    if flightBV then
        flightBV:Destroy()
        flightBV = nil
    end
    local char = LocalPlayer.Character
    if char then
        local hrp = char:FindFirstChild("HumanoidRootPart")
        if hrp then
            for _, ch in ipairs(hrp:GetChildren()) do
                if ch:IsA("BodyMover") or ch.Name == "HoldBV" then
                    ch:Destroy()
                end
            end
        end
        local hum = char:FindFirstChildOfClass("Humanoid")
        if hum then
            hum.PlatformStand = false
            pcall(function() hum:ChangeState(Enum.HumanoidStateType.Freefall) end)
        end
        for _, n in ipairs({"Head", "UpperTorso", "LowerTorso", "Torso"}) do
            local p = char:FindFirstChild(n)
            if p and p:IsA("BasePart") then p.CanCollide = true end
        end
    end
end

local function EnsureHold()
    if not (State.Farm or State.AutoRaid or State.Chests or flying) then
        RemoveHold()
        return
    end
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
    hrp.AssemblyLinearVelocity = Vector3.zero
    hrp.AssemblyAngularVelocity = Vector3.zero
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
    if flightBV then flightBV:Destroy() flightBV = nil end

    if not IsSea2() and targetPos.X > 50000 and hrp.Position.X < 50000 then
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
    local need = State.Farm or State.AutoRaid or State.Chests or flying
    if need then
        noclipWasOn = true
        for _, p in ipairs(char:GetDescendants()) do
            if p:IsA("BasePart") then p.CanCollide = false end
        end
    elseif noclipWasOn then
        noclipWasOn = false
        RemoveHold()
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

-- ==================== СТЯГИВАНИЕ + НЕВИДИМЫЙ ХИТБОКС ====================
local bringTarget, gatherCF = nil, nil
local lastSimRadius = 0

local function ClearBring()
    bringTarget, gatherCF = nil, nil
end

local function SetBringTarget(target)
    if bringTarget ~= target then
        bringTarget = target
        local h = target and target:FindFirstChild("HumanoidRootPart")
        if h then
            gatherCF = CFrame.new(h.Position.X, h.Position.Y, h.Position.Z)
        else
            gatherCF = nil
        end
    end
end

local function ExpandMobHitbox(mob, mHrp, hum)
    if State.Hitbox then
        local sz = State.HitboxSize or 55
        mHrp.Size = Vector3.new(sz, sz, sz)
        mHrp.Transparency = 1 -- Полностью невидимый хитбокс
        mHrp.Massless = true  -- Не вызывает тряску физики
        mHrp.CanCollide = false
    end
    if hum then
        hum.WalkSpeed = 0
        hum.JumpPower = 0
        hum.AutoRotate = false
    end
end

local function BringTick()
    if not State.Farm and not State.AutoRaid and not State.Hitbox then return end

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

    local char = LocalPlayer.Character
    local myHrp = char and char:FindFirstChild("HumanoidRootPart")

    local base = nil
    if State.Bring and (State.Farm or State.AutoRaid) and bringTarget and gatherCF then
        if not IsValidMob(bringTarget) then
            ClearBring()
        else
            base = BaseName(bringTarget.Name)
        end
    end

    for _, mob in ipairs(enemies:GetChildren()) do
        if IsValidMob(mob) then
            local hum = mob:FindFirstChildOfClass("Humanoid")
            local mHrp = mob:FindFirstChild("HumanoidRootPart")
            if myHrp and (mHrp.Position - myHrp.Position).Magnitude < 120 then
                ExpandMobHitbox(mob, mHrp, hum)
            end
            if base and gatherCF and (State.AutoRaid or BaseName(mob.Name) == base) and (mHrp.Position - gatherCF.Position).Magnitude < 280 then
                for _, part in ipairs(mob:GetChildren()) do
                    if part:IsA("BasePart") then
                        part.CanCollide = false
                    end
                end
                ExpandMobHitbox(mob, mHrp, hum)
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

local function InputAllowed()
    if UserInputService:GetFocusedTextBox() then return false end
    return true
end

-- ==================== FAST ATTACK (БЕЗ ТРЯСКИ) ====================
local fruitCombo = 0
local lastFruitAtk = 0

local function FastClickAura(radius, targetPos)
    local char = LocalPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    local tool = char and char:FindFirstChildOfClass("Tool")
    if not hrp or not tool then return end

    local enemies = workspace:FindFirstChild("Enemies")
    if not enemies then return end

    local hitList1 = {}
    local hitList2 = {}
    local primaryPart = nil

    for _, mob in ipairs(enemies:GetChildren()) do
        if IsValidMob(mob) then
            local hum = mob:FindFirstChildOfClass("Humanoid")
            local mHrp = mob:FindFirstChild("HumanoidRootPart")
            if (mHrp.Position - hrp.Position).Magnitude <= (radius or 75) then
                ExpandMobHitbox(mob, mHrp, hum)
                if not primaryPart then
                    primaryPart = mHrp
                end
                table.insert(hitList1, {mob, mHrp})
                table.insert(hitList2, {mHrp, mob})
            end
        end
    end

    if primaryPart then
        targetPos = targetPos or primaryPart.Position

        -- 1. Физическая активация оружия в руках
        pcall(function() tool:Activate() end)

        -- 2. Фоновый клик VirtualUser
        pcall(function()
            VirtualUser:CaptureController()
            VirtualUser:ClickButton1(Vector2.new(0, 0))
        end)

        -- 3. Активация ремоутов фруктов
        if tool.ToolTip == "Blox Fruit" and targetPos then
            if os.clock() - lastFruitAtk >= (State.AtkInterval or 0.08) then
                lastFruitAtk = os.clock()
                local d = targetPos - hrp.Position
                local maxC = (State.ComboMode == "1-4") and 4 or ((State.ComboMode == "1") and 1 or 3)
                fruitCombo = fruitCombo % maxC + 1

                for _, rName in ipairs({"RemoteEvent", "LeftClickRemote", "Input", "Attack"}) do
                    local r = tool:FindFirstChild(rName)
                    if r and r:IsA("RemoteEvent") then
                        pcall(function() r:FireServer(d.Unit, fruitCombo) end)
                    end
                end
            end
        end

        -- 4. Прямые сетевые пакеты RegisterHit
        if RegisterAttack then pcall(function() RegisterAttack:FireServer(0) end) end
        if RegisterHit then
            pcall(function() RegisterHit:FireServer(primaryPart, hitList1) end)
            pcall(function() RegisterHit:FireServer(primaryPart, hitList2) end)
        end
    end
end

local function PerformAttack(targetPos)
    FastClickAura(75, targetPos)
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
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
ScreenGui.DisplayOrder = 999999
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
OpenBtn.Size = UDim2.new(0, 44, 0, 44)
OpenBtn.Position = UDim2.new(0, 15, 0, 140)
OpenBtn.BackgroundColor3 = Color3.fromRGB(15, 16, 22)
OpenBtn.Text = "⚡"
OpenBtn.TextColor3 = Color3.fromRGB(56, 136, 255)
OpenBtn.TextSize = 20
OpenBtn.Font = Enum.Font.GothamBold
OpenBtn.Visible = false
OpenBtn.Active = true
Round(OpenBtn, 10)
Stroke(OpenBtn, Color3.fromRGB(45, 50, 68), 1.5)

local Main = Instance.new("Frame")
Main.Name = "Main"
Main.Parent = ScreenGui
Main.Size = UDim2.new(0, 560, 0, 340)
Main.Position = UDim2.new(0.5, -280, 0.5, -170)
Main.BackgroundColor3 = Color3.fromRGB(15, 16, 21)
Main.BorderSizePixel = 0
Round(Main, 10)
Stroke(Main, Color3.fromRGB(32, 35, 46), 1)

local function ShowMainGui()
    OpenBtn.Visible = false
    Main.Visible = true
end

local function HideMainGui()
    Main.Visible = false
    OpenBtn.Visible = true
end

OpenBtn.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        ShowMainGui()
    end
end)
OpenBtn.MouseButton1Click:Connect(ShowMainGui)

Connect(UserInputService.InputBegan, function(input, gpe)
    if not gpe and (input.KeyCode == Enum.KeyCode.RightControl or input.KeyCode == Enum.KeyCode.Insert) then
        if Main.Visible then
            HideMainGui()
        else
            ShowMainGui()
        end
    end
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
SideList.Padding = UDim.new(0, 3)

local SidePad = Instance.new("UIPadding")
SidePad.Parent = Sidebar
SidePad.PaddingTop = UDim.new(0, 10)
SidePad.PaddingLeft = UDim.new(0, 8)
SidePad.PaddingRight = UDim.new(0, 8)

local TopHeader = Instance.new("Frame")
TopHeader.Name = "TopHeader"
TopHeader.Parent = Main
TopHeader.Position = UDim2.new(0, 155, 0, 0)
TopHeader.Size = UDim2.new(1, -155, 0, 50)
TopHeader.BackgroundTransparency = 1

local HeaderTitle = Label(TopHeader, "Main Farm", UDim2.new(0, 14, 0, 8), UDim2.new(0, 220, 0, 20),
    Enum.Font.GothamBold, Color3.fromRGB(245, 246, 250), 16)
local StatusLabel = Label(TopHeader, "v23.3 | RightCtrl - меню | idle", UDim2.new(0, 14, 0, 28), UDim2.new(0, 320, 0, 14),
    Enum.Font.Gotham, COL.sub, 11)
local lastStatus = ""
local function SetStatus(s)
    if s ~= lastStatus then
        lastStatus = s
        StatusLabel.Text = "v23.3 (Sea " .. (IsSea2() and "2" or "1") .. ") | " .. s
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
MinimizeBtn.MouseButton1Click:Connect(HideMainGui)

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
    TabBtn.Size = UDim2.new(1, 0, 0, 32)
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
local RaidPage = CreateTab("Raids", "⚡")
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
local FarmToggle, ChestToggle, RaidToggle

AddSection(FarmPage, "World Selection")
AddCycle(FarmPage, "Режим моря (Sea)", "Auto определяет море по карте и уровню", {"Auto", "Sea 2", "Sea 1"}, "SeaMode", function(v)
    State.SeaMode = v
    activeQ = nil
    takenKey = nil
    SetStatus("Режим моря: " .. v)
end)

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
    if State.Farm or State.AutoRaid then
        deaths = deaths + 1
        Notify("Респавн #" .. deaths .. ", продолжаю работу")
    end
end)

local retreatCooldown = 0
local hpTrack = {mob = nil, hp = 0, t = 0}

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

-- Плавный подлёт БЕЗ наклона персонажа вниз (убирает тряску экрана!)
local lastStepT = os.clock()
local function StepToward(hrp, goal, maxSpeed)
    local now = os.clock()
    local dt = math.clamp(now - lastStepT, 0.016, 0.2)
    lastStepT = now
    local delta = goal - hrp.Position
    local d = delta.Magnitude
    if d <= 1.2 then
        hrp.CFrame = CFrame.new(goal)
    else
        local maxStep = (maxSpeed or 180) * dt
        local pos = (d <= maxStep) and goal or (hrp.Position + delta.Unit * maxStep)
        hrp.CFrame = CFrame.new(pos)
    end
    hrp.AssemblyLinearVelocity = Vector3.zero
    hrp.AssemblyAngularVelocity = Vector3.zero
end

local function RiseBy(hrp, dy)
    CancelFlight()
    local id = flightId
    if flightBV then flightBV:Destroy() flightBV = nil end
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

    -- ШАГ 1: Взятие квеста
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

    -- ШАГ 2: Ближайший валидный живой моб
    local target = GetLiveMob(q.Mob, hrp.Position)
    local tHrp = target and target:FindFirstChild("HumanoidRootPart")
    if tHrp then
        SetBringTarget(target)
        local mobPos = tHrp.Position
        lastMobSeen[q.Mob] = mobPos
        Diag.camTarget = mobPos

        local stackPos = gatherCF and gatherCF.Position or mobPos
        local hoverPos = stackPos + Vector3.new(0, State.Hover, 0)

        local approach = (hrp.Position - hoverPos).Magnitude
        if approach > 25 then
            SetStatus("лечу к мобу " .. q.Mob .. " [" .. tostring(lastProgress) .. "]")
            if approach <= 150 then
                StepToward(hrp, hoverPos, 220)
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
                elseif os.clock() - hpTrack.t > 4.5 then
                    -- Моб не получает урон 4.5 сек -> Фейк НПС! Кидаем в черный список
                    badMobs[target] = os.clock() + 120
                    ClearBring()
                    SetStatus("пропуск фейк-моба " .. q.Mob)
                    return
                end
            end

            SetStatus(string.format("Атака: %s [%s]", q.Mob, tostring(lastProgress)))
            StepToward(hrp, hoverPos, 140)
            EnsureHold()
            EnsureWeaponEquipped()
            PerformAttack(stackPos)
        end
    else
        -- ШАГ 3: мобов нет
        ClearBring()
        local sp, src = GetDynamicSpawn(q.Mob, q.MobPos, hrp.Position)
        SetStatus("ищу " .. q.Mob .. " (" .. src .. ")")
        SafeFlyTo(sp + Vector3.new(0, State.Hover, 0), src == "table" and ResolveGround or nil)
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
            ClearBring()
            RemoveHold()
        end
    end)
end

-- ==================== АВТО-РЕЙДЫ (AUTO RAIDS) ====================
local function IsRaidTimerActive()
    local pGui = LocalPlayer:FindFirstChild("PlayerGui")
    local main = pGui and pGui:FindFirstChild("Main")
    local timer = main and (main:FindFirstChild("Timer") or main:FindFirstChild("RaidTimer"))
    return timer and timer.Visible == true
end

local function GetNextRaidIsland()
    local origin = workspace:FindFirstChild("_WorldOrigin")
    local locs = origin and origin:FindFirstChild("Locations")
    if not locs then return nil, nil end

    local char = LocalPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    local bestIsl, bestNum = nil, 0

    for i = 5, 1, -1 do
        local name = "Island " .. i
        for _, loc in ipairs(locs:GetChildren()) do
            if loc.Name == name and loc:IsA("BasePart") then
                if not hrp or (loc.Position - hrp.Position).Magnitude < 4500 then
                    if i > bestNum then
                        bestIsl = loc
                        bestNum = i
                    end
                end
            end
        end
    end
    return bestIsl, bestNum
end

local function BuyAndStartRaid()
    Invoke("RaidsNpc", "Select", State.RaidChip)
    task.wait(0.3)
    pcall(function()
        local island = workspace.Map:FindFirstChild("CircleIsland") or workspace.Map:FindFirstChild("RaidMap")
        if island then
            for _, d in ipairs(island:GetDescendants()) do
                if d:IsA("ClickDetector") and d.Parent and d.Parent.Name == "Button" then
                    if fireclickdetector then
                        fireclickdetector(d)
                    end
                end
            end
        end
    end)
end

local raidHpTrack = {mob = nil, hp = 0, t = 0}
local function RaidStep(run)
    local char = LocalPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if not hrp or not hum or hum.Health <= 0 then
        SetStatus("рейд: жду респавн...")
        task.wait(0.5)
        return
    end

    EnsureBuso()

    local isl, islNum = GetNextRaidIsland()
    local inDungeon = IsRaidTimerActive() or (isl ~= nil)

    if not inDungeon then
        ClearBring()
        if State.AutoChip then
            SetStatus("рейд: покупаю чип " .. State.RaidChip .. " и запускаю...")
            BuyAndStartRaid()
            task.wait(2.5)
        else
            SetStatus("рейд: ожидание старта рейда (Island 1 не найден)")
            task.wait(1)
        end
        return
    end

    -- Ищем любого живого моба в рейде
    local mob = GetAnyRaidMob(hrp.Position)
    local mHrp = mob and mob:FindFirstChild("HumanoidRootPart")
    if mHrp then
        SetBringTarget(mob)
        local stackPos = gatherCF and gatherCF.Position or mHrp.Position
        local hoverPos = stackPos + Vector3.new(0, State.Hover, 0)

        local d = (hrp.Position - hoverPos).Magnitude
        if d > 25 then
            SetStatus(string.format("рейд (Oстров %s): лечу к %s", tostring(islNum or "?"), mob.Name))
            if d <= 160 then
                StepToward(hrp, hoverPos, 230)
                EnsureHold()
            else
                SafeFlyTo(hoverPos, nil, nil, true)
            end
        else
            local th = mob:FindFirstChildOfClass("Humanoid")
            if raidHpTrack.mob ~= mob then
                raidHpTrack = {mob = mob, hp = th and th.Health or 0, t = os.clock()}
            elseif th then
                if th.Health < raidHpTrack.hp - 0.5 then
                    raidHpTrack.hp = th.Health
                    raidHpTrack.t = os.clock()
                elseif os.clock() - raidHpTrack.t > 5.0 then
                    badMobs[mob] = os.clock() + 60
                    ClearBring()
                    return
                end
            end

            SetStatus(string.format("рейд (Остров %s): бью %s", tostring(islNum or "?"), mob.Name))
            StepToward(hrp, hoverPos, 150)
            EnsureHold()
            EnsureWeaponEquipped()
            PerformAttack(stackPos)
        end
    elseif isl then
        ClearBring()
        local targetPos = isl.Position + Vector3.new(0, 25, 0)
        SetStatus("рейд: лечу на Island " .. tostring(islNum))
        SafeFlyTo(targetPos, ResolveGround, true, true)
        task.wait(0.4)
    end
end

local function StartAutoRaid()
    raidRun = raidRun + 1
    local run = raidRun
    task.spawn(function()
        while alive and State.AutoRaid and run == raidRun do
            task.wait(0.04)
            pcall(RaidStep, run)
        end
        if run == raidRun then
            CancelFlight()
            ClearBring()
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
        if State.Farm or State.AutoRaid then sess.active = sess.active + 1 end
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
FarmToggle = AddToggle(FarmPage, "Auto Farm Level", "Авто-квест + Анти-Фейк НПС + Невидимый Хитбокс", false, function(val)
    State.Farm = val
    if val then
        if State.Chests and ChestToggle then ChestToggle:Set(false, true) end
        if State.AutoRaid and RaidToggle then RaidToggle:Set(false, true) end
        StartFarm()
    else
        farmRun = farmRun + 1
        CancelFlight()
        ClearBring()
        RemoveHold()
    end
end)

AddToggle(FarmPage, "Bring Mobs (Стягивать пачкой)", "Стягивает всех мобов к цели", true, function(val)
    State.Bring = val
end)

AddToggle(FarmPage, "Hitbox Expander (Невидимый 55x55)", "Невидимый хитбокс мобов для 100% попадания сверху", true, function(val)
    State.Hitbox = val
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
        if State.AutoRaid and RaidToggle then RaidToggle:Set(false, true) end
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
            if not State.Farm and not State.AutoRaid then
                CancelFlight()
                RemoveHold()
            end
        end)
    else
        CancelFlight()
        if not State.Farm and not State.AutoRaid then RemoveHold() end
    end
end)

-- ==================== RAIDS PAGE ====================
AddSection(RaidPage, "Auto Raid (Dungeon)")
RaidToggle = AddToggle(RaidPage, "Auto Raid (Авто-прохождение)", "Авто-перелёт Island 1 -> 5 + зачистка всех волн и босса", false, function(val)
    State.AutoRaid = val
    if val then
        if State.Farm and FarmToggle then FarmToggle:Set(false, true) end
        if State.Chests and ChestToggle then ChestToggle:Set(false, true) end
        StartAutoRaid()
    else
        raidRun = raidRun + 1
        CancelFlight()
        ClearBring()
        RemoveHold()
    end
end)

local RAID_CHIPS = {"Ice", "Flame", "Light", "Dark", "Magma", "Buddha", "Quake", "Spider", "Rumble", "Sand"}
AddCycle(RaidPage, "Чип рейда (Fruit Chip)", "Выбери чип для покупки у Raid NPC", RAID_CHIPS, "RaidChip", function(v)
    State.RaidChip = v
end)

AddToggle(RaidPage, "Auto Buy Chip & Start Raid", "Авто-покупка чипа и нажатие кнопки запуска в лаборатории", false, function(val)
    State.AutoChip = val
end)

AddAction(RaidPage, "Купить чип сейчас", "Разовая покупка выбранного чипа через CommF_", function()
    Invoke("RaidsNpc", "Select", State.RaidChip)
    Notify("Запрос на покупку чипа: " .. State.RaidChip)
end)

AddAction(RaidPage, "Телепорт в Лабораторию Рейдов (Sea 2)", "Летит в комнату запуска рейдов на Hot and Cold", function()
    if State.Farm and FarmToggle then FarmToggle:Set(false, true) end
    SafeFlyTo(Vector3.new(-6438, 250, -4501))
    CancelFlight()
    RemoveHold()
end)

-- ==================== COMBAT ====================
AddSection(CombatPage, "Combat")

AddCycle(CombatPage, "Оружие", "Mixed = фрукт / стиль / меч каждые 6с", {"Any", "Blox Fruit", "Sword", "Melee", "Mixed"}, "Weapon", function(v)
    State.Weapon = v
    pcall(EnsureWeaponEquipped)
end)

local fastClickStandalone = false
AddToggle(CombatPage, "Fast Click + Hitbox Aura", "Расширяет невидимые хитбоксы вокруг и бьет всех мобов", false, function(val)
    fastClickStandalone = val
    if val then
        task.spawn(function()
            while alive and fastClickStandalone do
                task.wait(0.06)
                EnsureWeaponEquipped()
                pcall(function() FastClickAura(75) end)
            end
        end)
    end
end)

AddToggle(CombatPage, "Auto Buso Haki", "Держать Хаки включённым", true, function(val)
    State.Buso = val
end)

local SkillKeys = {Enum.KeyCode.Z, Enum.KeyCode.X, Enum.KeyCode.C, Enum.KeyCode.V}
AddToggle(CombatPage, "Fruit Skills (Z X C V)", "Жмёт Z X C V текущего оружия во время фарма/рейда", false, function(val)
    State.Skills = val
end)
task.spawn(function()
    local i = 0
    while alive do
        task.wait(0.4)
        if (State.Farm or State.AutoRaid or fastClickStandalone) and State.Skills then
            pcall(function()
                local char = LocalPlayer.Character
                local tool = char and char:FindFirstChildOfClass("Tool")
                if tool and IsWeaponTip(tool.ToolTip) and InputAllowed() then
                    i = i % #SkillKeys + 1
                    VIM:SendKeyEvent(true, SkillKeys[i], false, game)
                    task.wait(0.05)
                    VIM:SendKeyEvent(false, SkillKeys[i], false, game)
                end
            end)
        end
    end
end)

AddToggle(CombatPage, "Auto Stats", "Очки: 50% в Защиту, 50% в выбранный стат", false, function(val)
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

AddCycle(CombatPage, "Стат для Auto Stats", "Вторая половина очков", {"Fruit", "Melee", "Sword"}, "StatMode", function(v)
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
AddToggle(FruitPage, "Fruit Notifier", "Уведомление при появлении фрукта на карте", true, function(val)
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
        if not State.Farm and not State.AutoRaid and not State.Chests then RemoveHold() end
    else
        Notify("Фруктов на земле нет!")
    end
end)

-- ==================== TELEPORTS (SEA 2 + SEA 1) ====================
local function TP(pos)
    return function()
        if State.Farm and FarmToggle then FarmToggle:Set(false, true) end
        if State.AutoRaid and RaidToggle then RaidToggle:Set(false, true) end
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

AddSection(TeleportPage, "Sea 2 Islands")
AddAction(TeleportPage, "The Cafe (Кафе)", "Главный хаб Sea 2", TP(Vector3.new(-380, 73, 299)))
AddAction(TeleportPage, "Kingdom of Rose (Mansion)", "Особняк Дона Свана", TP(Vector3.new(-288, 306, 591)))
AddAction(TeleportPage, "Kingdom of Rose (Start)", "Старт 700 ур.", TP(Vector3.new(-426, 73, 1836)))
AddAction(TeleportPage, "Green Zone", "Зелёная зона (Lv. 875)", TP(Vector3.new(-2448, 73, -3210)))
AddAction(TeleportPage, "Graveyard", "Кладбище (Lv. 950)", TP(Vector3.new(-5495, 48, -794)))
AddAction(TeleportPage, "Snow Mountain", "Снежная гора (Lv. 1000)", TP(Vector3.new(607, 401, -5371)))
AddAction(TeleportPage, "Hot and Cold (Raid Lab)", "Остров огня и льда (Lv. 1100)", TP(Vector3.new(-5430, 15, -5295)))
AddAction(TeleportPage, "Cursed Ship", "Проклятый корабль (Lv. 1250)", TP(Vector3.new(923, 125, 32852)))
AddAction(TeleportPage, "Ice Castle", "Ледяной замок (Lv. 1350)", TP(Vector3.new(5567, 28, -6244)))
AddAction(TeleportPage, "Forgotten Island", "Забытый остров (Lv. 1425)", TP(Vector3.new(-3054, 237, -10142)))
AddAction(TeleportPage, "Dark Arena", "Арена Тьмы (Черная Борода)", TP(Vector3.new(3780, 15, -3499)))

AddSection(TeleportPage, "Sea 1 Islands")
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
AddSection(WorldPage, "Performance & Visuals")

AddToggle(WorldPage, "Remove Death/Hit VFX (Убрать эффекты)", "Убирает огромные эффекты после смерти НПС и вспышки ударов", true, function(val)
    State.NoVFX = val
end)

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

-- ==================== ЭКСПОРТ (ADM PERMS) ====================
local function SetupMapExport()
    local function BuildReport()
        local L = {}
        local function add(t) L[#L + 1] = t end
        local function Cap(name, v) return name .. "=" .. tostring(v ~= nil) end

        add("# XenoHub REPORT v23.3 | Sea2=" .. tostring(IsSea2()) .. " | " .. os.date("%Y-%m-%d %H:%M:%S"))
        local team = "?"
        pcall(function() team = LocalPlayer.Team and LocalPlayer.Team.Name or "none" end)
        add("PlaceId=" .. game.PlaceId .. " | Level=" .. tostring(ReadData("Level")) .. " | Beli=" .. tostring(ReadData("Beli"))
            .. " | Fragments=" .. tostring(ReadData("Fragments")) .. " | Points=" .. tostring(ReadData("Points"))
            .. " | Team=" .. team .. " | Players=" .. #Players:GetPlayers())

        add("")
        add("## EXECUTOR & REMOTES")
        local exName, exVer = "?", "?"
        pcall(function() if identifyexecutor then exName, exVer = identifyexecutor() end end)
        add(tostring(exName) .. " " .. tostring(exVer))
        add(table.concat({Cap("RegisterAttack", RegisterAttack), Cap("RegisterHit", RegisterHit),
            Cap("isnetworkowner", isnetworkowner), Cap("sethiddenproperty", sethiddenproperty)}, " | "))

        add("")
        add("## QUEST STATE")
        local q = GetCurrentQuest()
        add(string.format("current=%s #%s mob=%s npcName=%s", q.Quest, tostring(q.Id), q.Mob, tostring(q.NpcName)))
        local pa, pb = ReadProgress()
        add("progress=" .. (pa and (pa .. "/" .. pb) or "nil"))

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

    AddSection(AdminPage, "Диагностика")
    AddAction(AdminPage, "Полный отчёт", "Лог квестов, ремоутов и позиции -> F9 и буфер", DoReport)
end
SetupMapExport()

-- ==================== SETTINGS ====================
AddSection(SettingsPage, "Client & Utility")
AddAction(SettingsPage, "Rejoin Server", "Перезайти на этот же сервер", function()
    pcall(function() TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, LocalPlayer) end)
end)

AddAction(SettingsPage, "Close GUI", "Полностью выгрузить скрипт", function()
    alive = false
    State.Farm, State.AutoRaid, State.Chests, State.Stats = false, false, false, false
    CfgSet("t:Auto Farm Level", false)
    CfgSet("t:Auto Raid (Авто-прохождение)", false)
    CfgSet("t:Auto Chest Farm", false)
    CfgSet("t:Auto Stats", false)
    farmRun = farmRun + 1
    raidRun = raidRun + 1
    infJump, fastSpeed, fruitESPActive = false, false, false
    if fullBright then fullBright = false; RestoreLighting() end
    ClearESP()
    CancelFlight()
    ClearBring()
    RemoveHold()
    for _, c in ipairs(Connections) do pcall(function() c:Disconnect() end) end
    Connections = {}
    ScreenGui:Destroy()
end)

AddAction(SettingsPage, "Reset Settings", "Сбросить конфиг", function()
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

Notify("Xeno Hub v23.3 загружен! (Меню: RightCtrl)")
