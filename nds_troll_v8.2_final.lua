--[[
    ╔═══════════════════════════════════════════════════════════════════════════╗
    ║                     NDS TROLL HUB v8.2 - FINAL                            ║
    ║                   Natural Disaster Survival                               ║
    ║              Compatível com Executores Mobile e PC                        ║
    ║                                                                           ║
    ║  CHANGELOG v8.2:                                                          ║
    ║  - CORRIGIDO: Eventos disparavam duas vezes (toggle duplo)                ║
    ║  - CORRIGIDO: Lista de players não aparecia                               ║
    ║  - CORRIGIDO: Minimizar não funcionava                                    ║
    ║  - SOLUÇÃO: Usar APENAS MouseButton1Click (funciona em mobile também)     ║
    ╚═══════════════════════════════════════════════════════════════════════════╝
--]]

-- ═══════════════════════════════════════════════════════════════════════════
-- VERIFICAÇÃO DE CARREGAMENTO
-- ═══════════════════════════════════════════════════════════════════════════

local function SafeGetGenv()
    if typeof(getgenv) == "function" then
        local ok, result = pcall(getgenv)
        if ok and result then return result end
    end
    if typeof(shared) == "table" then
        return shared
    end
    return _G
end

local genv = SafeGetGenv()
if genv.NDS_TROLL_HUB_LOADED then
    warn("[NDS v8.2] Script já está carregado!")
    return
end
genv.NDS_TROLL_HUB_LOADED = true

-- ═══════════════════════════════════════════════════════════════════════════
-- SERVIÇOS
-- ═══════════════════════════════════════════════════════════════════════════

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local StarterGui = game:GetService("StarterGui")

local LocalPlayer = Players.LocalPlayer
local Camera = Workspace.CurrentCamera

-- ═══════════════════════════════════════════════════════════════════════════
-- CONSTANTES
-- ═══════════════════════════════════════════════════════════════════════════

local CONSTANTS = {
    MAX_FORCE = 1e7,
    MAX_VELOCITY = 500,
    MAX_TORQUE = 1e6,
    RESPONSIVENESS = 200,
    ORBIT_MAX_FORCE = 2e7,
    ORBIT_MAX_VELOCITY = 750,
    ORBIT_RESPONSIVENESS = 400,
    SIM_RADIUS = 1e6,
    MIN_DENSITY = 0.1,
    MIN_FRICTION = 0.3,
    MIN_ELASTICITY = 0.5,
    MAX_PART_SIZE = 30,
    MIN_PART_SIZE = 0.5,
}

-- ═══════════════════════════════════════════════════════════════════════════
-- LISTAS DE FILTRO
-- ═══════════════════════════════════════════════════════════════════════════

local MAP_PART_BLACKLIST = {
    "grass", "ground", "floor", "terrain", "dirt", "sand", "rock", "stone",
    "mud", "soil", "earth", "gravel", "pebble", "boulder",
    "wall", "roof", "ceiling", "foundation", "base", "platform", "beam",
    "pillar", "column", "support", "frame", "structure",
    "road", "path", "sidewalk", "bridge", "ramp", "stairs", "step", "ladder",
    "water", "ocean", "lake", "river", "pool", "pond", "sea",
    "spawn", "barrier", "boundary", "border", "edge", "limit"
}

local MAP_CONTAINERS = {
    "Structure", "Map", "Terrain", "Environment", "Buildings", 
    "Ground", "Landscape", "World", "Level", "Arena", "Stage",
    "Decorations", "Props", "Static", "Fixed"
}

local TERRAIN_MATERIALS = {
    Enum.Material.Grass, Enum.Material.Ground, Enum.Material.Sand,
    Enum.Material.Rock, Enum.Material.Slate, Enum.Material.Concrete,
    Enum.Material.Brick, Enum.Material.Cobblestone, Enum.Material.Asphalt,
    Enum.Material.Pavement, Enum.Material.Wood, Enum.Material.WoodPlanks,
}

-- ═══════════════════════════════════════════════════════════════════════════
-- CONFIGURAÇÃO
-- ═══════════════════════════════════════════════════════════════════════════

local Config = {
    OrbitRadius = 25,
    OrbitSpeed = 2,
    OrbitHeight = 5,
    MagnetForce = 500,
    SpinRadius = 15,
    SpinSpeed = 4,
    FlySpeed = 60,
    SpeedMultiplier = 3,
}

-- ═══════════════════════════════════════════════════════════════════════════
-- ESTADO
-- ═══════════════════════════════════════════════════════════════════════════

local State = {
    SelectedPlayer = nil,
    Magnet = false,
    Orbit = false,
    Blackhole = false,
    PartRain = false,
    Cage = false,
    Spin = false,
    HatFling = false,
    BodyFling = false,
    Launch = false,
    SlowPlayer = false,
    GodMode = false,
    Fly = false,
    View = false,
    Noclip = false,
    Speed = false,
    ESP = false,
    Telekinesis = false,
    SkyLift = false,
    ServerMagnet = false,
}

local Connections = {}
local CreatedObjects = {}
local AnchorPart = nil
local MainAttachment = nil
local TelekinesisTarget = nil
local TelekinesisDistance = 15
local NetworkLoopActive = false

-- ═══════════════════════════════════════════════════════════════════════════
-- DETECÇÃO DE PLATAFORMA
-- ═══════════════════════════════════════════════════════════════════════════

local IsMobile = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled

local function GetExecutorName()
    local name = "Unknown"
    pcall(function()
        if typeof(identifyexecutor) == "function" then
            name = identifyexecutor()
        elseif typeof(getexecutorname) == "function" then
            name = getexecutorname()
        end
    end)
    return name
end

-- ═══════════════════════════════════════════════════════════════════════════
-- FUNÇÕES UTILITÁRIAS
-- ═══════════════════════════════════════════════════════════════════════════

local function GetCharacter()
    return LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
end

local function GetHRP()
    local char = GetCharacter()
    return char and char:FindFirstChild("HumanoidRootPart")
end

local function GetHumanoid()
    local char = GetCharacter()
    return char and char:FindFirstChildOfClass("Humanoid")
end

local function Notify(title, text, duration)
    pcall(function()
        StarterGui:SetCore("SendNotification", {
            Title = title,
            Text = text,
            Duration = duration or 3
        })
    end)
end

local function ClearConnections(prefix)
    for name, conn in pairs(Connections) do
        if prefix then
            if string.find(name, prefix) then
                pcall(function() conn:Disconnect() end)
                Connections[name] = nil
            end
        else
            pcall(function() conn:Disconnect() end)
        end
    end
    if not prefix then Connections = {} end
end

local function ClearCreatedObjects()
    for _, obj in pairs(CreatedObjects) do
        pcall(function() obj:Destroy() end)
    end
    CreatedObjects = {}
end

-- ═══════════════════════════════════════════════════════════════════════════
-- SIMULATIONRADIUS
-- ═══════════════════════════════════════════════════════════════════════════

local function SetSimulationRadius(value)
    pcall(function()
        if typeof(sethiddenproperty) == "function" then
            sethiddenproperty(LocalPlayer, "SimulationRadius", value)
        elseif typeof(setsimulationradius) == "function" then
            setsimulationradius(value, value)
        else
            LocalPlayer.SimulationRadius = value
        end
    end)
end

local function StartNetworkLoop()
    if NetworkLoopActive then return end
    NetworkLoopActive = true
    
    task.spawn(function()
        while NetworkLoopActive do
            SetSimulationRadius(CONSTANTS.SIM_RADIUS)
            task.wait(0.5)
        end
    end)
end

local function StopNetworkLoop()
    NetworkLoopActive = false
end

-- ═══════════════════════════════════════════════════════════════════════════
-- FILTRO DE PARTES DO MAPA
-- ═══════════════════════════════════════════════════════════════════════════

local function IsMapPart(part)
    if not part or not part:IsA("BasePart") then return true end
    if part:IsA("Terrain") then return true end
    
    local parent = part.Parent
    local depth = 0
    while parent and parent ~= Workspace and depth < 10 do
        local parentNameLower = parent.Name:lower()
        for _, container in ipairs(MAP_CONTAINERS) do
            if parentNameLower:find(container:lower()) then
                return true
            end
        end
        parent = parent.Parent
        depth = depth + 1
    end
    
    local nameL = part.Name:lower()
    for _, blacklisted in ipairs(MAP_PART_BLACKLIST) do
        if nameL:find(blacklisted) then return true end
    end
    
    local size = part.Size
    if size.X > CONSTANTS.MAX_PART_SIZE or size.Y > CONSTANTS.MAX_PART_SIZE or size.Z > CONSTANTS.MAX_PART_SIZE then
        return true
    end
    
    if size.Magnitude < CONSTANTS.MIN_PART_SIZE then return true end
    if part.Transparency >= 0.95 then return true end
    
    if size.Magnitude > 15 then
        for _, mat in ipairs(TERRAIN_MATERIALS) do
            if part.Material == mat then return true end
        end
    end
    
    return false
end

-- ═══════════════════════════════════════════════════════════════════════════
-- SISTEMA DE PARTES
-- ═══════════════════════════════════════════════════════════════════════════

local function GetUnanchoredParts()
    local parts = {}
    for _, obj in pairs(Workspace:GetDescendants()) do
        if obj:IsA("BasePart") and not obj.Anchored then
            local isValid = true
            if obj.Name:find("_NDS") then isValid = false end
            if isValid and IsMapPart(obj) then isValid = false end
            if isValid then
                for _, player in pairs(Players:GetPlayers()) do
                    if player.Character and obj:IsDescendantOf(player.Character) then
                        isValid = false
                        break
                    end
                end
            end
            if isValid then table.insert(parts, obj) end
        end
    end
    return parts
end

local function GetMyAccessories()
    local handles = {}
    local char = GetCharacter()
    if char then
        for _, acc in pairs(char:GetChildren()) do
            if acc:IsA("Accessory") then
                local handle = acc:FindFirstChild("Handle")
                if handle then table.insert(handles, handle) end
            end
        end
    end
    return handles
end

local function GetAvailableParts()
    local parts = GetUnanchoredParts()
    if #parts < 5 then
        for _, h in pairs(GetMyAccessories()) do
            table.insert(parts, h)
        end
    end
    return parts
end

-- ═══════════════════════════════════════════════════════════════════════════
-- CONTROLE DE PARTES
-- ═══════════════════════════════════════════════════════════════════════════

local function SetupPartControl(part, targetAttachment, mode)
    if not part or not part:IsA("BasePart") or part.Anchored then return nil, nil end
    if part.Name:find("_NDS") or IsMapPart(part) then return nil, nil end
    
    for _, player in pairs(Players:GetPlayers()) do
        if player.Character and part:IsDescendantOf(player.Character) then
            if player == LocalPlayer then return nil, nil end
        end
    end
    
    pcall(function()
        for _, child in pairs(part:GetChildren()) do
            if child:IsA("AlignPosition") or child:IsA("AlignOrientation") or
               child:IsA("BodyPosition") or child:IsA("BodyVelocity") or
               child:IsA("BodyForce") or child:IsA("BodyGyro") then
                if not child.Name:find("_NDS") then child:Destroy() end
            end
        end
    end)
    
    pcall(function()
        part.CanCollide = false
        part.CustomPhysicalProperties = PhysicalProperties.new(CONSTANTS.MIN_DENSITY, CONSTANTS.MIN_FRICTION, CONSTANTS.MIN_ELASTICITY, 1, 1)
    end)
    
    local attach = Instance.new("Attachment")
    attach.Name = "_NDSAttach"
    attach.Parent = part
    
    local align = Instance.new("AlignPosition")
    align.Name = "_NDSAlign"
    
    if mode == "orbit" then
        align.MaxForce = CONSTANTS.ORBIT_MAX_FORCE
        align.MaxVelocity = CONSTANTS.ORBIT_MAX_VELOCITY
        align.Responsiveness = CONSTANTS.ORBIT_RESPONSIVENESS
    else
        align.MaxForce = CONSTANTS.MAX_FORCE
        align.MaxVelocity = CONSTANTS.MAX_VELOCITY
        align.Responsiveness = CONSTANTS.RESPONSIVENESS
    end
    
    align.Attachment0 = attach
    align.Attachment1 = targetAttachment or MainAttachment
    align.Parent = part
    
    return attach, align
end

local function CleanPartControl(part)
    if not part then return end
    pcall(function()
        local align = part:FindFirstChild("_NDSAlign")
        local attach = part:FindFirstChild("_NDSAttach")
        local torque = part:FindFirstChild("_NDSTorque")
        if align then align:Destroy() end
        if attach then attach:Destroy() end
        if torque then torque:Destroy() end
        part.CanCollide = true
    end)
end

-- ═══════════════════════════════════════════════════════════════════════════
-- SISTEMA DE REDE
-- ═══════════════════════════════════════════════════════════════════════════

local function SetupNetworkControl()
    if AnchorPart then pcall(function() AnchorPart:Destroy() end) end
    
    AnchorPart = Instance.new("Part")
    AnchorPart.Name = "_NDSAnchor"
    AnchorPart.Size = Vector3.new(1, 1, 1)
    AnchorPart.Transparency = 1
    AnchorPart.CanCollide = false
    AnchorPart.Anchored = true
    AnchorPart.CFrame = CFrame.new(0, 10000, 0)
    AnchorPart.Parent = Workspace
    table.insert(CreatedObjects, AnchorPart)
    
    MainAttachment = Instance.new("Attachment")
    MainAttachment.Name = "MainAttach"
    MainAttachment.Parent = AnchorPart
    
    StartNetworkLoop()
end

-- ═══════════════════════════════════════════════════════════════════════════
-- DESABILITAR TODAS AS FUNÇÕES
-- ═══════════════════════════════════════════════════════════════════════════

local function DisableAllFunctions()
    StopNetworkLoop()
    for key, _ in pairs(State) do
        if key ~= "SelectedPlayer" then
            State[key] = false
        end
    end
    ClearConnections()
    ClearCreatedObjects()
    
    for _, obj in pairs(Workspace:GetDescendants()) do
        if obj:IsA("BasePart") then
            pcall(function()
                local align = obj:FindFirstChild("_NDSAlign")
                local attach = obj:FindFirstChild("_NDSAttach")
                if align then align:Destroy() end
                if attach then attach:Destroy() end
            end)
        end
    end
end


-- ═══════════════════════════════════════════════════════════════════════════
-- FUNÇÕES DE TROLAGEM
-- ═══════════════════════════════════════════════════════════════════════════

local function ToggleMagnet()
    State.Magnet = not State.Magnet
    
    if State.Magnet then
        if not State.SelectedPlayer or not State.SelectedPlayer.Character then
            State.Magnet = false
            return false, "Selecione um player!"
        end
        
        for _, part in pairs(GetAvailableParts()) do
            SetupPartControl(part, MainAttachment, "normal")
        end
        
        Connections.MagnetNew = Workspace.DescendantAdded:Connect(function(obj)
            if State.Magnet and obj:IsA("BasePart") and not obj.Anchored and not IsMapPart(obj) then
                task.defer(function() SetupPartControl(obj, MainAttachment, "normal") end)
            end
        end)
        
        Connections.MagnetLoop = RunService.Heartbeat:Connect(function()
            if not State.Magnet then return end
            local target = State.SelectedPlayer
            if not target or not target.Character then
                State.Magnet = false
                ClearConnections("Magnet")
                return
            end
            local targetHRP = target.Character:FindFirstChild("HumanoidRootPart")
            if targetHRP and AnchorPart then
                AnchorPart.CFrame = targetHRP.CFrame
            end
        end)
        
        return true, "Magnet ativado!"
    else
        ClearConnections("Magnet")
        for _, obj in pairs(Workspace:GetDescendants()) do
            if obj:IsA("BasePart") then CleanPartControl(obj) end
        end
        return true, "Magnet desativado!"
    end
end

local function ToggleOrbit()
    State.Orbit = not State.Orbit
    
    if State.Orbit then
        if not State.SelectedPlayer or not State.SelectedPlayer.Character then
            State.Orbit = false
            return false, "Selecione um player!"
        end
        
        local orbitAngle = 0
        local orbitAttachment = Instance.new("Attachment")
        orbitAttachment.Name = "_NDSOrbitAttach"
        orbitAttachment.Parent = AnchorPart
        table.insert(CreatedObjects, orbitAttachment)
        
        for _, part in pairs(GetAvailableParts()) do
            SetupPartControl(part, orbitAttachment, "orbit")
        end
        
        Connections.OrbitLoop = RunService.Heartbeat:Connect(function()
            if not State.Orbit then return end
            local target = State.SelectedPlayer
            if not target or not target.Character then
                State.Orbit = false
                ClearConnections("Orbit")
                return
            end
            local targetHRP = target.Character:FindFirstChild("HumanoidRootPart")
            if not targetHRP then return end
            
            orbitAngle = orbitAngle + Config.OrbitSpeed * 0.016
            local orbitX = math.cos(orbitAngle) * Config.OrbitRadius
            local orbitZ = math.sin(orbitAngle) * Config.OrbitRadius
            orbitAttachment.WorldPosition = targetHRP.Position + Vector3.new(orbitX, Config.OrbitHeight, orbitZ)
        end)
        
        return true, "Orbit ativado!"
    else
        ClearConnections("Orbit")
        for _, obj in pairs(Workspace:GetDescendants()) do
            if obj:IsA("BasePart") then CleanPartControl(obj) end
        end
        return true, "Orbit desativado!"
    end
end

local function ToggleBlackhole()
    State.Blackhole = not State.Blackhole
    
    if State.Blackhole then
        if not State.SelectedPlayer or not State.SelectedPlayer.Character then
            State.Blackhole = false
            return false, "Selecione um player!"
        end
        
        local bhAttachment = Instance.new("Attachment")
        bhAttachment.Name = "_NDSBHAttach"
        bhAttachment.Parent = AnchorPart
        table.insert(CreatedObjects, bhAttachment)
        
        for _, part in pairs(GetAvailableParts()) do
            local a, al = SetupPartControl(part, bhAttachment, "normal")
            if a then
                local torque = Instance.new("Torque")
                torque.Name = "_NDSTorque"
                torque.Torque = Vector3.new(math.random(-100, 100), math.random(-100, 100), math.random(-100, 100))
                torque.Parent = part
            end
        end
        
        Connections.BHLoop = RunService.Heartbeat:Connect(function()
            if not State.Blackhole then return end
            local target = State.SelectedPlayer
            if not target or not target.Character then
                State.Blackhole = false
                ClearConnections("BH")
                return
            end
            local targetHRP = target.Character:FindFirstChild("HumanoidRootPart")
            if targetHRP then bhAttachment.WorldPosition = targetHRP.Position end
        end)
        
        return true, "Blackhole ativado!"
    else
        ClearConnections("BH")
        for _, obj in pairs(Workspace:GetDescendants()) do
            if obj:IsA("BasePart") then CleanPartControl(obj) end
        end
        return true, "Blackhole desativado!"
    end
end

local function ToggleSpin()
    State.Spin = not State.Spin
    
    if State.Spin then
        if not State.SelectedPlayer or not State.SelectedPlayer.Character then
            State.Spin = false
            return false, "Selecione um player!"
        end
        
        local spinAngle = 0
        local spinAttachment = Instance.new("Attachment")
        spinAttachment.Name = "_NDSSpinAttach"
        spinAttachment.Parent = AnchorPart
        table.insert(CreatedObjects, spinAttachment)
        
        for _, part in pairs(GetAvailableParts()) do
            SetupPartControl(part, spinAttachment, "normal")
        end
        
        Connections.SpinLoop = RunService.Heartbeat:Connect(function()
            if not State.Spin then return end
            local target = State.SelectedPlayer
            if not target or not target.Character then
                State.Spin = false
                ClearConnections("Spin")
                return
            end
            local targetHRP = target.Character:FindFirstChild("HumanoidRootPart")
            if not targetHRP then return end
            
            spinAngle = spinAngle + Config.SpinSpeed * 0.016
            local spinX = math.cos(spinAngle) * Config.SpinRadius
            local spinZ = math.sin(spinAngle) * Config.SpinRadius
            spinAttachment.WorldPosition = targetHRP.Position + Vector3.new(spinX, 2, spinZ)
        end)
        
        return true, "Spin ativado!"
    else
        ClearConnections("Spin")
        for _, obj in pairs(Workspace:GetDescendants()) do
            if obj:IsA("BasePart") then CleanPartControl(obj) end
        end
        return true, "Spin desativado!"
    end
end

local function ToggleCage()
    State.Cage = not State.Cage
    
    if State.Cage then
        if not State.SelectedPlayer or not State.SelectedPlayer.Character then
            State.Cage = false
            return false, "Selecione um player!"
        end
        
        local cageAttachments = {}
        local cageRadius = 8
        
        for i = 1, 20 do
            local attachment = Instance.new("Attachment")
            attachment.Name = "_NDSCageAttach_" .. i
            attachment.Parent = AnchorPart
            table.insert(cageAttachments, {attach = attachment, angle = (i / 20) * math.pi * 2, height = (i % 5) * 2 - 4})
            table.insert(CreatedObjects, attachment)
        end
        
        local parts = GetAvailableParts()
        for i, cageData in ipairs(cageAttachments) do
            if parts[i] then SetupPartControl(parts[i], cageData.attach, "normal") end
        end
        
        Connections.CageLoop = RunService.Heartbeat:Connect(function()
            if not State.Cage then return end
            local target = State.SelectedPlayer
            if not target or not target.Character then
                State.Cage = false
                ClearConnections("Cage")
                return
            end
            local targetHRP = target.Character:FindFirstChild("HumanoidRootPart")
            if not targetHRP then return end
            
            for _, cageData in ipairs(cageAttachments) do
                local x = math.cos(cageData.angle) * cageRadius
                local z = math.sin(cageData.angle) * cageRadius
                cageData.attach.WorldPosition = targetHRP.Position + Vector3.new(x, cageData.height, z)
            end
        end)
        
        return true, "Cage ativado!"
    else
        ClearConnections("Cage")
        for _, obj in pairs(Workspace:GetDescendants()) do
            if obj:IsA("BasePart") then CleanPartControl(obj) end
        end
        return true, "Cage desativado!"
    end
end

local function TogglePartRain()
    State.PartRain = not State.PartRain
    
    if State.PartRain then
        if not State.SelectedPlayer or not State.SelectedPlayer.Character then
            State.PartRain = false
            return false, "Selecione um player!"
        end
        
        local rainAttachment = Instance.new("Attachment")
        rainAttachment.Name = "_NDSRainAttach"
        rainAttachment.Parent = AnchorPart
        table.insert(CreatedObjects, rainAttachment)
        
        for _, part in pairs(GetAvailableParts()) do
            SetupPartControl(part, rainAttachment, "normal")
        end
        
        local rainOffset = 0
        Connections.RainLoop = RunService.Heartbeat:Connect(function()
            if not State.PartRain then return end
            local target = State.SelectedPlayer
            if not target or not target.Character then
                State.PartRain = false
                ClearConnections("Rain")
                return
            end
            local targetHRP = target.Character:FindFirstChild("HumanoidRootPart")
            if not targetHRP then return end
            
            rainOffset = (rainOffset + 0.5) % 50
            rainAttachment.WorldPosition = targetHRP.Position + Vector3.new(0, 50 - rainOffset, 0)
        end)
        
        return true, "Part Rain ativado!"
    else
        ClearConnections("Rain")
        for _, obj in pairs(Workspace:GetDescendants()) do
            if obj:IsA("BasePart") then CleanPartControl(obj) end
        end
        return true, "Part Rain desativado!"
    end
end

local function ToggleHatFling()
    State.HatFling = not State.HatFling
    
    if State.HatFling then
        if not State.SelectedPlayer or not State.SelectedPlayer.Character then
            State.HatFling = false
            return false, "Selecione um player!"
        end
        
        local handles = GetMyAccessories()
        if #handles == 0 then
            State.HatFling = false
            return false, "Sem acessórios!"
        end
        
        local flingAttachment = Instance.new("Attachment")
        flingAttachment.Name = "_NDSFlingAttach"
        flingAttachment.Parent = AnchorPart
        table.insert(CreatedObjects, flingAttachment)
        
        for _, handle in pairs(handles) do
            SetupPartControl(handle, flingAttachment, "orbit")
        end
        
        local flingAngle = 0
        Connections.HatFlingLoop = RunService.Heartbeat:Connect(function()
            if not State.HatFling then return end
            local target = State.SelectedPlayer
            if not target or not target.Character then
                State.HatFling = false
                ClearConnections("HatFling")
                return
            end
            local targetHRP = target.Character:FindFirstChild("HumanoidRootPart")
            if not targetHRP then return end
            
            flingAngle = flingAngle + 15
            local x = math.cos(math.rad(flingAngle)) * 3
            local z = math.sin(math.rad(flingAngle)) * 3
            flingAttachment.WorldPosition = targetHRP.Position + Vector3.new(x, 0, z)
        end)
        
        return true, "Hat Fling ativado!"
    else
        ClearConnections("HatFling")
        for _, handle in pairs(GetMyAccessories()) do CleanPartControl(handle) end
        return true, "Hat Fling desativado!"
    end
end

local function ToggleBodyFling()
    State.BodyFling = not State.BodyFling
    
    if State.BodyFling then
        if not State.SelectedPlayer or not State.SelectedPlayer.Character then
            State.BodyFling = false
            return false, "Selecione um player!"
        end
        
        local flingAngle = 0
        Connections.BodyFlingLoop = RunService.Heartbeat:Connect(function()
            if not State.BodyFling then return end
            local target = State.SelectedPlayer
            if not target or not target.Character then
                State.BodyFling = false
                ClearConnections("BodyFling")
                return
            end
            local targetHRP = target.Character:FindFirstChild("HumanoidRootPart")
            local myHRP = GetHRP()
            if not targetHRP or not myHRP then return end
            
            flingAngle = flingAngle + 20
            local x = math.cos(math.rad(flingAngle)) * 2
            local z = math.sin(math.rad(flingAngle)) * 2
            myHRP.CFrame = targetHRP.CFrame * CFrame.new(x, 0, z)
            myHRP.Velocity = Vector3.new(math.random(-50, 50), math.random(-50, 50), math.random(-50, 50))
        end)
        
        return true, "Body Fling ativado!"
    else
        ClearConnections("BodyFling")
        return true, "Body Fling desativado!"
    end
end

local function ToggleLaunch()
    State.Launch = not State.Launch
    
    if State.Launch then
        if not State.SelectedPlayer or not State.SelectedPlayer.Character then
            State.Launch = false
            return false, "Selecione um player!"
        end
        
        local launchAttachment = Instance.new("Attachment")
        launchAttachment.Name = "_NDSLaunchAttach"
        launchAttachment.Parent = AnchorPart
        table.insert(CreatedObjects, launchAttachment)
        
        for _, part in pairs(GetAvailableParts()) do
            SetupPartControl(part, launchAttachment, "orbit")
        end
        
        local launchPhase, launchHeight = 0, 0
        Connections.LaunchLoop = RunService.Heartbeat:Connect(function()
            if not State.Launch then return end
            local target = State.SelectedPlayer
            if not target or not target.Character then
                State.Launch = false
                ClearConnections("Launch")
                return
            end
            local targetHRP = target.Character:FindFirstChild("HumanoidRootPart")
            if not targetHRP then return end
            
            launchPhase = launchPhase + 1
            if launchPhase < 60 then launchHeight = -10
            elseif launchPhase < 120 then launchHeight = launchHeight + 5
            else launchPhase, launchHeight = 0, 0 end
            
            launchAttachment.WorldPosition = targetHRP.Position + Vector3.new(0, launchHeight, 0)
        end)
        
        return true, "Launch ativado!"
    else
        ClearConnections("Launch")
        for _, obj in pairs(Workspace:GetDescendants()) do
            if obj:IsA("BasePart") then CleanPartControl(obj) end
        end
        return true, "Launch desativado!"
    end
end

local function ToggleSkyLift()
    State.SkyLift = not State.SkyLift
    
    if State.SkyLift then
        if not State.SelectedPlayer or not State.SelectedPlayer.Character then
            State.SkyLift = false
            return false, "Selecione um player!"
        end
        
        local skyAttachment = Instance.new("Attachment")
        skyAttachment.Name = "_NDSSkyAttach"
        skyAttachment.Parent = AnchorPart
        table.insert(CreatedObjects, skyAttachment)
        
        for _, part in pairs(GetAvailableParts()) do
            SetupPartControl(part, skyAttachment, "normal")
        end
        
        local skyHeight = 0
        Connections.SkyLiftLoop = RunService.Heartbeat:Connect(function()
            if not State.SkyLift then return end
            local target = State.SelectedPlayer
            if not target or not target.Character then
                State.SkyLift = false
                ClearConnections("SkyLift")
                return
            end
            local targetHRP = target.Character:FindFirstChild("HumanoidRootPart")
            if not targetHRP then return end
            
            skyHeight = math.min(skyHeight + 2, 500)
            skyAttachment.WorldPosition = targetHRP.Position + Vector3.new(0, skyHeight, 0)
        end)
        
        return true, "Sky Lift ativado!"
    else
        ClearConnections("SkyLift")
        for _, obj in pairs(Workspace:GetDescendants()) do
            if obj:IsA("BasePart") then CleanPartControl(obj) end
        end
        return true, "Sky Lift desativado!"
    end
end

local function ToggleSlowPlayer()
    State.SlowPlayer = not State.SlowPlayer
    
    if State.SlowPlayer then
        if not State.SelectedPlayer or not State.SelectedPlayer.Character then
            State.SlowPlayer = false
            return false, "Selecione um player!"
        end
        
        local slowAttachment = Instance.new("Attachment")
        slowAttachment.Name = "_NDSSlowAttach"
        slowAttachment.Parent = AnchorPart
        table.insert(CreatedObjects, slowAttachment)
        
        for _, part in pairs(GetAvailableParts()) do
            local a, al = SetupPartControl(part, slowAttachment, "normal")
            if al then al.Responsiveness, al.MaxVelocity = 50, 100 end
        end
        
        Connections.SlowLoop = RunService.Heartbeat:Connect(function()
            if not State.SlowPlayer then return end
            local target = State.SelectedPlayer
            if not target or not target.Character then
                State.SlowPlayer = false
                ClearConnections("Slow")
                return
            end
            local targetHRP = target.Character:FindFirstChild("HumanoidRootPart")
            if targetHRP then slowAttachment.WorldPosition = targetHRP.Position + Vector3.new(0, -1, 0) end
        end)
        
        return true, "Slow Player ativado!"
    else
        ClearConnections("Slow")
        for _, obj in pairs(Workspace:GetDescendants()) do
            if obj:IsA("BasePart") then CleanPartControl(obj) end
        end
        return true, "Slow Player desativado!"
    end
end

local function ToggleServerMagnet()
    State.ServerMagnet = not State.ServerMagnet
    
    if State.ServerMagnet then
        local serverAttachment = Instance.new("Attachment")
        serverAttachment.Name = "_NDSServerAttach"
        serverAttachment.Parent = AnchorPart
        table.insert(CreatedObjects, serverAttachment)
        
        for _, part in pairs(GetAvailableParts()) do
            SetupPartControl(part, serverAttachment, "normal")
        end
        
        Connections.ServerMagnetNew = Workspace.DescendantAdded:Connect(function(obj)
            if State.ServerMagnet and obj:IsA("BasePart") and not obj.Anchored and not IsMapPart(obj) then
                task.defer(function() SetupPartControl(obj, serverAttachment, "normal") end)
            end
        end)
        
        Connections.ServerMagnetLoop = RunService.Heartbeat:Connect(function()
            if not State.ServerMagnet then return end
            local myHRP = GetHRP()
            if myHRP then serverAttachment.WorldPosition = myHRP.Position end
        end)
        
        return true, "Server Magnet ativado!"
    else
        ClearConnections("ServerMagnet")
        for _, obj in pairs(Workspace:GetDescendants()) do
            if obj:IsA("BasePart") then CleanPartControl(obj) end
        end
        return true, "Server Magnet desativado!"
    end
end


-- ═══════════════════════════════════════════════════════════════════════════
-- FUNÇÕES DE PLAYER
-- ═══════════════════════════════════════════════════════════════════════════

local function ToggleGodMode()
    State.GodMode = not State.GodMode
    
    if State.GodMode then
        local humanoid = GetHumanoid()
        if not humanoid then
            State.GodMode = false
            return false, "Erro!"
        end
        
        Connections.GodModeLoop = RunService.Heartbeat:Connect(function()
            if not State.GodMode then return end
            local hum = GetHumanoid()
            if hum then hum.Health = hum.MaxHealth end
        end)
        
        return true, "God Mode ativado!"
    else
        ClearConnections("GodMode")
        return true, "God Mode desativado!"
    end
end

local function ToggleFly()
    State.Fly = not State.Fly
    
    if State.Fly then
        local hrp = GetHRP()
        if not hrp then
            State.Fly = false
            return false, "Erro!"
        end
        
        local bodyGyro = Instance.new("BodyGyro")
        bodyGyro.Name = "_NDSFlyGyro"
        bodyGyro.MaxTorque = Vector3.new(CONSTANTS.MAX_TORQUE, CONSTANTS.MAX_TORQUE, CONSTANTS.MAX_TORQUE)
        bodyGyro.P = 9e4
        bodyGyro.Parent = hrp
        table.insert(CreatedObjects, bodyGyro)
        
        local bodyVelocity = Instance.new("BodyVelocity")
        bodyVelocity.Name = "_NDSFlyVelocity"
        bodyVelocity.MaxForce = Vector3.new(CONSTANTS.MAX_FORCE, CONSTANTS.MAX_FORCE, CONSTANTS.MAX_FORCE)
        bodyVelocity.Velocity = Vector3.new(0, 0, 0)
        bodyVelocity.Parent = hrp
        table.insert(CreatedObjects, bodyVelocity)
        
        Connections.FlyLoop = RunService.Heartbeat:Connect(function()
            if not State.Fly then return end
            local myHRP = GetHRP()
            if not myHRP then return end
            
            local bg = myHRP:FindFirstChild("_NDSFlyGyro")
            local bv = myHRP:FindFirstChild("_NDSFlyVelocity")
            if not bg or not bv then return end
            
            bg.CFrame = Camera.CFrame
            
            local moveDir = Vector3.new(0, 0, 0)
            if UserInputService:IsKeyDown(Enum.KeyCode.W) then moveDir = moveDir + Camera.CFrame.LookVector end
            if UserInputService:IsKeyDown(Enum.KeyCode.S) then moveDir = moveDir - Camera.CFrame.LookVector end
            if UserInputService:IsKeyDown(Enum.KeyCode.A) then moveDir = moveDir - Camera.CFrame.RightVector end
            if UserInputService:IsKeyDown(Enum.KeyCode.D) then moveDir = moveDir + Camera.CFrame.RightVector end
            if UserInputService:IsKeyDown(Enum.KeyCode.Space) then moveDir = moveDir + Vector3.new(0, 1, 0) end
            if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then moveDir = moveDir - Vector3.new(0, 1, 0) end
            
            bv.Velocity = moveDir.Magnitude > 0 and moveDir.Unit * Config.FlySpeed or Vector3.new(0, 0, 0)
        end)
        
        return true, "Fly ativado!"
    else
        ClearConnections("Fly")
        local hrp = GetHRP()
        if hrp then
            local bg = hrp:FindFirstChild("_NDSFlyGyro")
            local bv = hrp:FindFirstChild("_NDSFlyVelocity")
            if bg then bg:Destroy() end
            if bv then bv:Destroy() end
        end
        return true, "Fly desativado!"
    end
end

local function ToggleNoclip()
    State.Noclip = not State.Noclip
    
    if State.Noclip then
        Connections.NoclipLoop = RunService.Stepped:Connect(function()
            if not State.Noclip then return end
            local char = GetCharacter()
            if char then
                for _, part in pairs(char:GetDescendants()) do
                    if part:IsA("BasePart") then part.CanCollide = false end
                end
            end
        end)
        return true, "Noclip ativado!"
    else
        ClearConnections("Noclip")
        local char = GetCharacter()
        if char then
            for _, part in pairs(char:GetDescendants()) do
                if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
                    part.CanCollide = true
                end
            end
        end
        return true, "Noclip desativado!"
    end
end

local function ToggleSpeed()
    State.Speed = not State.Speed
    
    if State.Speed then
        local humanoid = GetHumanoid()
        if not humanoid then
            State.Speed = false
            return false, "Erro!"
        end
        humanoid.WalkSpeed = humanoid.WalkSpeed * Config.SpeedMultiplier
        return true, "Speed ativado!"
    else
        local humanoid = GetHumanoid()
        if humanoid then humanoid.WalkSpeed = 16 end
        return true, "Speed desativado!"
    end
end

local function ToggleView()
    State.View = not State.View
    
    if State.View then
        if not State.SelectedPlayer or not State.SelectedPlayer.Character then
            State.View = false
            return false, "Selecione um player!"
        end
        local targetHumanoid = State.SelectedPlayer.Character:FindFirstChildOfClass("Humanoid")
        if targetHumanoid then Camera.CameraSubject = targetHumanoid end
        return true, "View ativado!"
    else
        local humanoid = GetHumanoid()
        if humanoid then Camera.CameraSubject = humanoid end
        return true, "View desativado!"
    end
end

local function ToggleESP()
    State.ESP = not State.ESP
    
    if State.ESP then
        for _, player in pairs(Players:GetPlayers()) do
            if player ~= LocalPlayer and player.Character then
                local highlight = Instance.new("Highlight")
                highlight.Name = "_NDSESP"
                highlight.FillColor = Color3.fromRGB(255, 0, 0)
                highlight.OutlineColor = Color3.fromRGB(255, 255, 255)
                highlight.FillTransparency = 0.5
                highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
                highlight.Adornee = player.Character
                highlight.Parent = player.Character
                table.insert(CreatedObjects, highlight)
            end
        end
        return true, "ESP ativado!"
    else
        for _, player in pairs(Players:GetPlayers()) do
            if player.Character then
                local h = player.Character:FindFirstChild("_NDSESP")
                if h then h:Destroy() end
            end
        end
        return true, "ESP desativado!"
    end
end

local function ToggleTelekinesis()
    State.Telekinesis = not State.Telekinesis
    
    if State.Telekinesis then
        local teleAttachment = Instance.new("Attachment")
        teleAttachment.Name = "_NDSTeleAttach"
        teleAttachment.Parent = AnchorPart
        table.insert(CreatedObjects, teleAttachment)
        
        Connections.TeleClick = UserInputService.InputBegan:Connect(function(input, gp)
            if gp or not State.Telekinesis then return end
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                local mouse = LocalPlayer:GetMouse()
                local target = mouse.Target
                if target and target:IsA("BasePart") and not target.Anchored and not IsMapPart(target) then
                    if TelekinesisTarget then CleanPartControl(TelekinesisTarget) end
                    TelekinesisTarget = target
                    SetupPartControl(target, teleAttachment, "normal")
                    Notify("Telekinesis", "Parte: " .. target.Name, 2)
                end
            end
        end)
        
        Connections.TeleLoop = RunService.Heartbeat:Connect(function()
            if not State.Telekinesis then return end
            local mouse = LocalPlayer:GetMouse()
            local ray = Camera:ScreenPointToRay(mouse.X, mouse.Y)
            teleAttachment.WorldPosition = ray.Origin + ray.Direction * TelekinesisDistance
        end)
        
        return true, "Telekinesis ativado!"
    else
        ClearConnections("Tele")
        if TelekinesisTarget then
            CleanPartControl(TelekinesisTarget)
            TelekinesisTarget = nil
        end
        return true, "Telekinesis desativado!"
    end
end


-- ═══════════════════════════════════════════════════════════════════════════
-- INTERFACE GRÁFICA (GUI) - v8.2 FINAL
-- CORREÇÃO: Usar APENAS MouseButton1Click (funciona em mobile também)
-- O problema era que MouseButton1Click + Activated disparavam 2x
-- ═══════════════════════════════════════════════════════════════════════════

local function CreateGUI()
    -- Tamanhos
    local buttonWidth = IsMobile and 130 or 115
    local buttonHeight = IsMobile and 45 or 38
    local fontSize = IsMobile and 13 or 11
    local mainWidth = IsMobile and 300 or 260
    local mainHeight = IsMobile and 450 or 400
    
    -- Destruir GUI existente
    local existingGui = LocalPlayer.PlayerGui:FindFirstChild("NDSTrollHub")
    if existingGui then existingGui:Destroy() end
    
    -- ScreenGui
    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "NDSTrollHub"
    screenGui.ResetOnSpawn = false
    screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    screenGui.Parent = LocalPlayer.PlayerGui
    
    -- Frame principal
    local mainFrame = Instance.new("Frame")
    mainFrame.Name = "MainFrame"
    mainFrame.Size = UDim2.new(0, mainWidth, 0, mainHeight)
    mainFrame.Position = UDim2.new(0.5, -mainWidth/2, 0.5, -mainHeight/2)
    mainFrame.BackgroundColor3 = Color3.fromRGB(30, 30, 40)
    mainFrame.BorderSizePixel = 0
    mainFrame.Active = true
    mainFrame.Parent = screenGui
    
    local mainCorner = Instance.new("UICorner")
    mainCorner.CornerRadius = UDim.new(0, 10)
    mainCorner.Parent = mainFrame
    
    local mainStroke = Instance.new("UIStroke")
    mainStroke.Color = Color3.fromRGB(80, 80, 100)
    mainStroke.Thickness = 2
    mainStroke.Parent = mainFrame
    
    -- Header
    local header = Instance.new("Frame")
    header.Name = "Header"
    header.Size = UDim2.new(1, 0, 0, 45)
    header.BackgroundColor3 = Color3.fromRGB(40, 40, 55)
    header.BorderSizePixel = 0
    header.Parent = mainFrame
    
    local headerCorner = Instance.new("UICorner")
    headerCorner.CornerRadius = UDim.new(0, 10)
    headerCorner.Parent = header
    
    -- Título
    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1, -90, 1, 0)
    title.Position = UDim2.new(0, 12, 0, 0)
    title.BackgroundTransparency = 1
    title.Text = "NDS TROLL v8.2"
    title.TextColor3 = Color3.fromRGB(255, 255, 255)
    title.TextSize = 16
    title.Font = Enum.Font.GothamBold
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.Parent = header
    
    -- Botão Minimizar
    local minimizeBtn = Instance.new("TextButton")
    minimizeBtn.Name = "MinimizeBtn"
    minimizeBtn.Size = UDim2.new(0, 35, 0, 35)
    minimizeBtn.Position = UDim2.new(1, -42, 0.5, -17)
    minimizeBtn.BackgroundColor3 = Color3.fromRGB(255, 80, 80)
    minimizeBtn.Text = "-"
    minimizeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    minimizeBtn.TextSize = 22
    minimizeBtn.Font = Enum.Font.GothamBold
    minimizeBtn.AutoButtonColor = true
    minimizeBtn.Parent = header
    
    local minimizeCorner = Instance.new("UICorner")
    minimizeCorner.CornerRadius = UDim.new(0, 8)
    minimizeCorner.Parent = minimizeBtn
    
    -- Content
    local contentFrame = Instance.new("Frame")
    contentFrame.Name = "Content"
    contentFrame.Size = UDim2.new(1, -16, 1, -55)
    contentFrame.Position = UDim2.new(0, 8, 0, 50)
    contentFrame.BackgroundTransparency = 1
    contentFrame.Parent = mainFrame
    
    -- Player Dropdown
    local playerDropdown = Instance.new("Frame")
    playerDropdown.Size = UDim2.new(1, 0, 0, 36)
    playerDropdown.BackgroundColor3 = Color3.fromRGB(45, 45, 60)
    playerDropdown.BorderSizePixel = 0
    playerDropdown.Parent = contentFrame
    
    local dropdownCorner = Instance.new("UICorner")
    dropdownCorner.CornerRadius = UDim.new(0, 8)
    dropdownCorner.Parent = playerDropdown
    
    local selectedLabel = Instance.new("TextLabel")
    selectedLabel.Size = UDim2.new(1, -45, 1, 0)
    selectedLabel.Position = UDim2.new(0, 10, 0, 0)
    selectedLabel.BackgroundTransparency = 1
    selectedLabel.Text = "Selecione um Player"
    selectedLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
    selectedLabel.TextSize = fontSize
    selectedLabel.Font = Enum.Font.Gotham
    selectedLabel.TextXAlignment = Enum.TextXAlignment.Left
    selectedLabel.Parent = playerDropdown
    
    local dropdownBtn = Instance.new("TextButton")
    dropdownBtn.Size = UDim2.new(0, 32, 0, 32)
    dropdownBtn.Position = UDim2.new(1, -36, 0.5, -16)
    dropdownBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 80)
    dropdownBtn.Text = "▼"
    dropdownBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    dropdownBtn.TextSize = 12
    dropdownBtn.Font = Enum.Font.GothamBold
    dropdownBtn.AutoButtonColor = true
    dropdownBtn.Parent = playerDropdown
    
    local dropdownBtnCorner = Instance.new("UICorner")
    dropdownBtnCorner.CornerRadius = UDim.new(0, 6)
    dropdownBtnCorner.Parent = dropdownBtn
    
    -- Player List
    local playerList = Instance.new("Frame")
    playerList.Size = UDim2.new(1, 0, 0, 130)
    playerList.Position = UDim2.new(0, 0, 0, 40)
    playerList.BackgroundColor3 = Color3.fromRGB(40, 40, 55)
    playerList.BorderSizePixel = 0
    playerList.Visible = false
    playerList.ZIndex = 50
    playerList.Parent = contentFrame
    
    local playerListCorner = Instance.new("UICorner")
    playerListCorner.CornerRadius = UDim.new(0, 8)
    playerListCorner.Parent = playerList
    
    local playerScroll = Instance.new("ScrollingFrame")
    playerScroll.Size = UDim2.new(1, -8, 1, -8)
    playerScroll.Position = UDim2.new(0, 4, 0, 4)
    playerScroll.BackgroundTransparency = 1
    playerScroll.ScrollBarThickness = 4
    playerScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
    playerScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
    playerScroll.ZIndex = 51
    playerScroll.Parent = playerList
    
    local playerListLayout = Instance.new("UIListLayout")
    playerListLayout.Padding = UDim.new(0, 3)
    playerListLayout.Parent = playerScroll
    
    -- Scroll Frame para botões
    local scrollFrame = Instance.new("ScrollingFrame")
    scrollFrame.Size = UDim2.new(1, 0, 1, -45)
    scrollFrame.Position = UDim2.new(0, 0, 0, 42)
    scrollFrame.BackgroundTransparency = 1
    scrollFrame.ScrollBarThickness = 5
    scrollFrame.ScrollBarImageColor3 = Color3.fromRGB(100, 100, 120)
    scrollFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
    scrollFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
    scrollFrame.Parent = contentFrame
    
    local gridLayout = Instance.new("UIGridLayout")
    gridLayout.CellSize = UDim2.new(0, buttonWidth, 0, buttonHeight)
    gridLayout.CellPadding = UDim2.new(0, 6, 0, 6)
    gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
    gridLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
    gridLayout.Parent = scrollFrame
    
    local gridPadding = Instance.new("UIPadding")
    gridPadding.PaddingTop = UDim.new(0, 4)
    gridPadding.Parent = scrollFrame
    
    -- ═══════════════════════════════════════════════════════════════════════
    -- SISTEMA DE DRAG
    -- ═══════════════════════════════════════════════════════════════════════
    
    local dragging = false
    local dragStart, startPos
    
    header.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPos = mainFrame.Position
        end
    end)
    
    header.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end)
    
    UserInputService.InputChanged:Connect(function(input)
        if dragging then
            if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
                local delta = input.Position - dragStart
                mainFrame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
            end
        end
    end)
    
    -- ═══════════════════════════════════════════════════════════════════════
    -- MINIMIZAR - USANDO APENAS MouseButton1Click
    -- ═══════════════════════════════════════════════════════════════════════
    
    local isMinimized = false
    local originalSize = mainFrame.Size
    
    minimizeBtn.MouseButton1Click:Connect(function()
        isMinimized = not isMinimized
        if isMinimized then
            mainFrame.Size = UDim2.new(0, mainWidth, 0, 45)
            contentFrame.Visible = false
            minimizeBtn.Text = "+"
        else
            mainFrame.Size = originalSize
            contentFrame.Visible = true
            minimizeBtn.Text = "-"
        end
    end)
    
    -- ═══════════════════════════════════════════════════════════════════════
    -- DROPDOWN - USANDO APENAS MouseButton1Click
    -- ═══════════════════════════════════════════════════════════════════════
    
    local function UpdatePlayerList()
        for _, child in pairs(playerScroll:GetChildren()) do
            if child:IsA("TextButton") then child:Destroy() end
        end
        
        for _, player in pairs(Players:GetPlayers()) do
            if player ~= LocalPlayer then
                local btn = Instance.new("TextButton")
                btn.Size = UDim2.new(1, -6, 0, 28)
                btn.BackgroundColor3 = Color3.fromRGB(55, 55, 75)
                btn.Text = player.Name
                btn.TextColor3 = Color3.fromRGB(255, 255, 255)
                btn.TextSize = fontSize
                btn.Font = Enum.Font.Gotham
                btn.ZIndex = 52
                btn.AutoButtonColor = true
                btn.Parent = playerScroll
                
                local btnCorner = Instance.new("UICorner")
                btnCorner.CornerRadius = UDim.new(0, 5)
                btnCorner.Parent = btn
                
                btn.MouseButton1Click:Connect(function()
                    State.SelectedPlayer = player
                    selectedLabel.Text = player.Name
                    playerList.Visible = false
                    Notify("NDS v8.2", "Player: " .. player.Name, 2)
                end)
            end
        end
    end
    
    dropdownBtn.MouseButton1Click:Connect(function()
        playerList.Visible = not playerList.Visible
        if playerList.Visible then UpdatePlayerList() end
    end)
    
    -- ═══════════════════════════════════════════════════════════════════════
    -- BOTÕES DE FUNÇÃO - USANDO APENAS MouseButton1Click
    -- ═══════════════════════════════════════════════════════════════════════
    
    local buttonRefs = {}
    
    local function CreateButton(name, displayName, callback, order)
        local btn = Instance.new("TextButton")
        btn.Name = name
        btn.LayoutOrder = order
        btn.BackgroundColor3 = Color3.fromRGB(55, 55, 75)
        btn.Text = displayName
        btn.TextColor3 = Color3.fromRGB(255, 255, 255)
        btn.TextSize = fontSize
        btn.Font = Enum.Font.Gotham
        btn.AutoButtonColor = true
        btn.Parent = scrollFrame
        
        local btnCorner = Instance.new("UICorner")
        btnCorner.CornerRadius = UDim.new(0, 8)
        btnCorner.Parent = btn
        
        -- APENAS MouseButton1Click - NÃO usar Activated junto
        btn.MouseButton1Click:Connect(function()
            local success, message = callback()
            if success then
                btn.BackgroundColor3 = State[name] and Color3.fromRGB(0, 150, 100) or Color3.fromRGB(55, 55, 75)
            end
            if message then Notify("NDS v8.2", message, 2) end
        end)
        
        buttonRefs[name] = btn
        return btn
    end
    
    -- Criar todos os botões
    local buttons = {
        {name = "Magnet", display = "Magnet", func = ToggleMagnet, order = 1},
        {name = "Orbit", display = "Orbit", func = ToggleOrbit, order = 2},
        {name = "Blackhole", display = "Blackhole", func = ToggleBlackhole, order = 3},
        {name = "Spin", display = "Spin", func = ToggleSpin, order = 4},
        {name = "Cage", display = "Cage", func = ToggleCage, order = 5},
        {name = "PartRain", display = "Part Rain", func = TogglePartRain, order = 6},
        {name = "HatFling", display = "Hat Fling", func = ToggleHatFling, order = 7},
        {name = "BodyFling", display = "Body Fling", func = ToggleBodyFling, order = 8},
        {name = "Launch", display = "Launch", func = ToggleLaunch, order = 9},
        {name = "SkyLift", display = "Sky Lift", func = ToggleSkyLift, order = 10},
        {name = "SlowPlayer", display = "Slow", func = ToggleSlowPlayer, order = 11},
        {name = "ServerMagnet", display = "Server Magnet", func = ToggleServerMagnet, order = 12},
        {name = "GodMode", display = "God Mode", func = ToggleGodMode, order = 13},
        {name = "Fly", display = "Fly", func = ToggleFly, order = 14},
        {name = "Noclip", display = "Noclip", func = ToggleNoclip, order = 15},
        {name = "Speed", display = "Speed", func = ToggleSpeed, order = 16},
        {name = "View", display = "View", func = ToggleView, order = 17},
        {name = "ESP", display = "ESP", func = ToggleESP, order = 18},
        {name = "Telekinesis", display = "Telekinesis", func = ToggleTelekinesis, order = 19},
    }
    
    for _, data in ipairs(buttons) do
        CreateButton(data.name, data.display, data.func, data.order)
    end
    
    -- Botão Desativar Tudo
    local disableBtn = Instance.new("TextButton")
    disableBtn.Name = "DisableAll"
    disableBtn.LayoutOrder = 100
    disableBtn.BackgroundColor3 = Color3.fromRGB(180, 50, 50)
    disableBtn.Text = "DESATIVAR"
    disableBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    disableBtn.TextSize = fontSize
    disableBtn.Font = Enum.Font.GothamBold
    disableBtn.AutoButtonColor = true
    disableBtn.Parent = scrollFrame
    
    local disableCorner = Instance.new("UICorner")
    disableCorner.CornerRadius = UDim.new(0, 8)
    disableCorner.Parent = disableBtn
    
    disableBtn.MouseButton1Click:Connect(function()
        DisableAllFunctions()
        SetupNetworkControl()
        for _, btn in pairs(buttonRefs) do
            btn.BackgroundColor3 = Color3.fromRGB(55, 55, 75)
        end
        Notify("NDS v8.2", "Tudo desativado!", 2)
    end)
    
    -- Eventos de players
    Players.PlayerRemoving:Connect(function(player)
        if State.SelectedPlayer == player then
            State.SelectedPlayer = nil
            selectedLabel.Text = "Selecione um Player"
            DisableAllFunctions()
            SetupNetworkControl()
            for _, btn in pairs(buttonRefs) do
                btn.BackgroundColor3 = Color3.fromRGB(55, 55, 75)
            end
        end
    end)
    
    return screenGui
end

-- ═══════════════════════════════════════════════════════════════════════════
-- INICIALIZAÇÃO
-- ═══════════════════════════════════════════════════════════════════════════

local function Initialize()
    SetupNetworkControl()
    CreateGUI()
    
    local platformText = IsMobile and "Mobile" or "PC"
    local executorText = GetExecutorName()
    
    Notify("NDS TROLL v8.2", "Carregado!\n" .. platformText .. " - " .. executorText, 5)
    
    print("═══════════════════════════════════════════════════")
    print("NDS TROLL HUB v8.2 - FINAL")
    print("Plataforma: " .. platformText)
    print("Executor: " .. executorText)
    print("═══════════════════════════════════════════════════")
end

Initialize()

-- Limpeza
LocalPlayer.CharacterRemoving:Connect(function()
    DisableAllFunctions()
    task.wait(0.5)
    SetupNetworkControl()
end)

game:BindToClose(function()
    DisableAllFunctions()
    genv.NDS_TROLL_HUB_LOADED = nil
end)
