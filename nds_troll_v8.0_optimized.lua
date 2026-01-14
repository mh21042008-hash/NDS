--[[
    ╔═══════════════════════════════════════════════════════════════════════════╗
    ║                     NDS TROLL HUB v8.0 - OPTIMIZED                        ║
    ║                   Natural Disaster Survival                               ║
    ║              Compatível com Executores Mobile e PC                        ║
    ║                                                                           ║
    ║  CHANGELOG v8.0:                                                          ║
    ║  - CORRIGIDO: Bug de arremesso ao pisar em áreas do mapa                  ║
    ║  - CORRIGIDO: Compatibilidade com executores mobile                       ║
    ║  - MELHORADO: Filtro de partes do mapa (grama, terreno, estruturas)       ║
    ║  - MELHORADO: Valores seguros em vez de math.huge                         ║
    ║  - MELHORADO: Propriedades físicas estáveis                               ║
    ║  - ADICIONADO: Detecção automática de plataforma                          ║
    ║  - ADICIONADO: Fallbacks para funções de executor                         ║
    ╚═══════════════════════════════════════════════════════════════════════════╝
--]]

-- ═══════════════════════════════════════════════════════════════════════════
-- VERIFICAÇÃO DE CARREGAMENTO (COMPATÍVEL COM MOBILE)
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
if genv.NDS_TROLL_HUB_V8_LOADED then
    warn("[NDS v8.0] Script já está carregado!")
    return
end
genv.NDS_TROLL_HUB_V8_LOADED = true

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
-- CONSTANTES SEGURAS (TESTADAS EM MOBILE)
-- ═══════════════════════════════════════════════════════════════════════════

local CONSTANTS = {
    -- Física (valores seguros, NÃO math.huge)
    MAX_FORCE = 1e7,           -- 10.000.000
    MAX_VELOCITY = 500,
    MAX_TORQUE = 1e6,
    RESPONSIVENESS = 200,
    
    -- Orbit (precisa de mais força para competir)
    ORBIT_MAX_FORCE = 2e7,     -- 20.000.000
    ORBIT_MAX_VELOCITY = 750,
    ORBIT_RESPONSIVENESS = 400,
    
    -- SimulationRadius (seguro para mobile)
    SIM_RADIUS = 1e6,          -- 1.000.000
    
    -- Física de partes (valores mínimos, NÃO zero)
    MIN_DENSITY = 0.1,
    MIN_FRICTION = 0.3,
    MIN_ELASTICITY = 0.5,
    
    -- Limites de tamanho
    MAX_PART_SIZE = 30,        -- Partes maiores são ignoradas (provavelmente do mapa)
    MIN_PART_SIZE = 0.5,       -- Partes menores são ignoradas (triggers)
}

-- ═══════════════════════════════════════════════════════════════════════════
-- LISTAS DE FILTRO PARA PARTES DO MAPA
-- ═══════════════════════════════════════════════════════════════════════════

-- Nomes de partes do mapa que NÃO devem ser capturadas
local MAP_PART_BLACKLIST = {
    -- Terreno natural
    "grass", "ground", "floor", "terrain", "dirt", "sand", "rock", "stone",
    "mud", "soil", "earth", "gravel", "pebble", "boulder",
    -- Estruturas
    "wall", "roof", "ceiling", "foundation", "base", "platform", "beam",
    "pillar", "column", "support", "frame", "structure",
    -- Caminhos
    "road", "path", "sidewalk", "bridge", "ramp", "stairs", "step", "ladder",
    -- Água
    "water", "ocean", "lake", "river", "pool", "pond", "sea",
    -- Outros
    "spawn", "barrier", "boundary", "border", "edge", "limit"
}

-- Containers do mapa que devem ser ignorados
local MAP_CONTAINERS = {
    "Structure", "Map", "Terrain", "Environment", "Buildings", 
    "Ground", "Landscape", "World", "Level", "Arena", "Stage",
    "Decorations", "Props", "Static", "Fixed"
}

-- Materiais de terreno (partes grandes com esses materiais são do mapa)
local TERRAIN_MATERIALS = {
    Enum.Material.Grass,
    Enum.Material.Ground,
    Enum.Material.Sand,
    Enum.Material.Rock,
    Enum.Material.Slate,
    Enum.Material.Concrete,
    Enum.Material.Brick,
    Enum.Material.Cobblestone,
    Enum.Material.Asphalt,
    Enum.Material.Pavement,
    Enum.Material.Wood,
    Enum.Material.WoodPlanks,
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
    
    -- Intervalos de atualização (otimizados)
    OrbitUpdateInterval = 0.05,
    BlackholeUpdateInterval = 0.05,
    SpinUpdateInterval = 0.05,
    
    -- Competição (Orbit)
    OrbitRecaptureInterval = 0.3,
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
local PlatformInfo = nil

-- ═══════════════════════════════════════════════════════════════════════════
-- DETECÇÃO DE PLATAFORMA
-- ═══════════════════════════════════════════════════════════════════════════

local function GetPlatformInfo()
    if PlatformInfo then return PlatformInfo end
    
    local info = {
        isMobile = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled,
        isPC = UserInputService.KeyboardEnabled,
        hasSetHiddenProperty = typeof(sethiddenproperty) == "function",
        hasSetSimRadius = typeof(setsimulationradius) == "function",
        hasGetGenv = typeof(getgenv) == "function",
        executorName = "Unknown"
    }
    
    -- Tentar identificar executor
    pcall(function()
        if typeof(identifyexecutor) == "function" then
            info.executorName = identifyexecutor()
        elseif typeof(getexecutorname) == "function" then
            info.executorName = getexecutorname()
        end
    end)
    
    PlatformInfo = info
    return info
end

-- Ajustar constantes para mobile
local function AdjustConstantsForPlatform()
    local platform = GetPlatformInfo()
    
    if platform.isMobile then
        -- Reduzir valores para mobile (mais estável)
        CONSTANTS.MAX_FORCE = 5e6
        CONSTANTS.MAX_VELOCITY = 300
        CONSTANTS.RESPONSIVENESS = 150
        CONSTANTS.ORBIT_MAX_FORCE = 1e7
        CONSTANTS.ORBIT_MAX_VELOCITY = 500
    end
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
-- SISTEMA DE SIMULATIONRADIUS COM FALLBACKS
-- ═══════════════════════════════════════════════════════════════════════════

local function SetSimulationRadius(value)
    local success = false
    
    -- Método 1: sethiddenproperty (executores PC)
    if typeof(sethiddenproperty) == "function" then
        local ok = pcall(function()
            sethiddenproperty(LocalPlayer, "SimulationRadius", value)
        end)
        if ok then success = true end
    end
    
    -- Método 2: setsimulationradius (Synapse)
    if not success and typeof(setsimulationradius) == "function" then
        local ok = pcall(function()
            setsimulationradius(value, value)
        end)
        if ok then success = true end
    end
    
    -- Método 3: Acesso direto (fallback)
    if not success then
        pcall(function()
            LocalPlayer.SimulationRadius = value
        end)
    end
    
    return success
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
-- FILTRO DE PARTES DO MAPA (CORRIGE BUG DE ARREMESSO)
-- ═══════════════════════════════════════════════════════════════════════════

local function IsMapPart(part)
    if not part or not part:IsA("BasePart") then
        return true -- Segurança: se não é BasePart, ignorar
    end
    
    -- 1. Verificar se é Terrain
    if part:IsA("Terrain") then
        return true
    end
    
    -- 2. Verificar hierarquia (está dentro de pasta do mapa?)
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
    
    -- 3. Verificar nome da parte
    local nameL = part.Name:lower()
    for _, blacklisted in ipairs(MAP_PART_BLACKLIST) do
        if nameL:find(blacklisted) then
            return true
        end
    end
    
    -- 4. Verificar tamanho (partes muito grandes são do mapa)
    local size = part.Size
    if size.X > CONSTANTS.MAX_PART_SIZE or 
       size.Y > CONSTANTS.MAX_PART_SIZE or 
       size.Z > CONSTANTS.MAX_PART_SIZE then
        return true
    end
    
    -- 5. Verificar se é muito pequena (triggers)
    if size.Magnitude < CONSTANTS.MIN_PART_SIZE then
        return true
    end
    
    -- 6. Verificar transparência (partes invisíveis são triggers)
    if part.Transparency >= 0.95 then
        return true
    end
    
    -- 7. Verificar material de terreno em partes grandes
    local sizeMag = size.Magnitude
    if sizeMag > 15 then
        for _, mat in ipairs(TERRAIN_MATERIALS) do
            if part.Material == mat then
                return true
            end
        end
    end
    
    -- 8. Verificar se está ancorada (partes do mapa geralmente são ancoradas)
    -- Nota: Esta verificação é feita separadamente em GetUnanchoredParts
    
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
            
            -- Filtro 1: Nossos objetos
            if obj.Name:find("_NDS") then 
                isValid = false 
            end
            
            -- Filtro 2: Partes do mapa (CORRIGE BUG DE ARREMESSO)
            if isValid and IsMapPart(obj) then
                isValid = false
            end
            
            -- Filtro 3: Partes de players
            if isValid then
                for _, player in pairs(Players:GetPlayers()) do
                    if player.Character and obj:IsDescendantOf(player.Character) then
                        isValid = false
                        break
                    end
                end
            end
            
            if isValid then
                table.insert(parts, obj)
            end
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
                if handle then
                    table.insert(handles, handle)
                end
            end
        end
    end
    return handles
end

local function GetAvailableParts()
    local parts = GetUnanchoredParts()
    if #parts < 5 then
        local handles = GetMyAccessories()
        for _, h in pairs(handles) do
            table.insert(parts, h)
        end
    end
    return parts
end

-- ═══════════════════════════════════════════════════════════════════════════
-- CONFIGURAÇÃO DE FÍSICA SEGURA
-- ═══════════════════════════════════════════════════════════════════════════

local function SetSafePhysicalProperties(part)
    pcall(function()
        part.CustomPhysicalProperties = PhysicalProperties.new(
            CONSTANTS.MIN_DENSITY,
            CONSTANTS.MIN_FRICTION,
            CONSTANTS.MIN_ELASTICITY,
            1,
            1
        )
    end)
end

local function SetPartCollision(part, enabled)
    -- Só modificar colisão de partes pequenas
    local size = part.Size
    if size.Magnitude < 15 then
        pcall(function()
            part.CanCollide = enabled
            part.CanQuery = enabled
            part.CanTouch = enabled
        end)
    end
end

-- ═══════════════════════════════════════════════════════════════════════════
-- CONTROLE DE PARTES (VERSÃO OTIMIZADA)
-- ═══════════════════════════════════════════════════════════════════════════

local function SetupPartControl(part, targetAttachment, mode)
    -- Validações
    if not part or not part:IsA("BasePart") then return nil, nil end
    if part.Anchored then return nil, nil end
    if part.Name:find("_NDS") then return nil, nil end
    
    -- CRÍTICO: Verificar se é parte do mapa
    if IsMapPart(part) then
        return nil, nil
    end
    
    -- Verificar se é parte de player (exceto LocalPlayer)
    for _, player in pairs(Players:GetPlayers()) do
        if player.Character and part:IsDescendantOf(player.Character) then
            if player == LocalPlayer then return nil, nil end
        end
    end
    
    pcall(function()
        -- Remover nossos controles antigos
        local oldAlign = part:FindFirstChild("_NDSAlign")
        local oldAttach = part:FindFirstChild("_NDSAttach")
        if oldAlign then oldAlign:Destroy() end
        if oldAttach then oldAttach:Destroy() end
        
        -- Remover controles de outros scripts
        for _, child in pairs(part:GetChildren()) do
            if child:IsA("AlignPosition") or child:IsA("AlignOrientation") or
               child:IsA("BodyPosition") or child:IsA("BodyVelocity") or
               child:IsA("BodyForce") or child:IsA("BodyGyro") or
               child:IsA("VectorForce") or child:IsA("LineForce") or
               child:IsA("BodyAngularVelocity") or child:IsA("BodyThrust") or
               child:IsA("RocketPropulsion") or child:IsA("Torque") then
                if not child.Name:find("_NDS") then
                    child:Destroy()
                end
            end
        end
        
        -- Remover Attachments de outros scripts
        for _, child in pairs(part:GetChildren()) do
            if child:IsA("Attachment") and not child.Name:find("_NDS") then
                child:Destroy()
            end
        end
    end)
    
    -- Configurar colisão inteligente
    SetPartCollision(part, false)
    
    -- Configurar física segura (NÃO zero!)
    SetSafePhysicalProperties(part)
    
    -- Criar attachment
    local attach = Instance.new("Attachment")
    attach.Name = "_NDSAttach"
    attach.Parent = part
    
    -- Criar AlignPosition com valores SEGUROS
    local align = Instance.new("AlignPosition")
    align.Name = "_NDSAlign"
    
    -- Configurar baseado no modo
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
        
        -- Restaurar colisão
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
    
    -- Iniciar loop de SimulationRadius
    StartNetworkLoop()
end

-- ═══════════════════════════════════════════════════════════════════════════
-- DESABILITAR TODAS AS FUNÇÕES
-- ═══════════════════════════════════════════════════════════════════════════

local function DisableAllFunctions()
    -- Parar loop de rede
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
                local torque = obj:FindFirstChild("_NDSTorque")
                if align then align:Destroy() end
                if attach then attach:Destroy() end
                if torque then torque:Destroy() end
            end)
        end
    end
    
    local hrp = GetHRP()
    if hrp then
        pcall(function()
            hrp.Velocity = Vector3.new(0, 0, 0)
            hrp.RotVelocity = Vector3.new(0, 0, 0)
        end)
    end
end


-- ═══════════════════════════════════════════════════════════════════════════
-- FUNÇÕES DE TROLAGEM
-- ═══════════════════════════════════════════════════════════════════════════

-- MAGNET
local function ToggleMagnet()
    State.Magnet = not State.Magnet
    
    if State.Magnet then
        if not State.SelectedPlayer or not State.SelectedPlayer.Character then
            State.Magnet = false
            return false, "Selecione um player!"
        end
        
        local controlledParts = {}
        
        -- Captura inicial
        for _, part in pairs(GetAvailableParts()) do
            SetupPartControl(part, MainAttachment, "normal")
            controlledParts[part] = true
        end
        
        -- Captura de novas partes
        Connections.MagnetNew = Workspace.DescendantAdded:Connect(function(obj)
            if State.Magnet and obj:IsA("BasePart") then
                task.defer(function()
                    if not obj.Anchored and not IsMapPart(obj) then
                        SetupPartControl(obj, MainAttachment, "normal")
                        controlledParts[obj] = true
                    end
                end)
            end
        end)
        
        -- Loop de atualização
        Connections.MagnetLoop = RunService.Heartbeat:Connect(function()
            if not State.Magnet then return end
            
            local target = State.SelectedPlayer
            if not target or not target.Character then
                State.Magnet = false
                ClearConnections("Magnet")
                return
            end
            
            local targetHRP = target.Character:FindFirstChild("HumanoidRootPart")
            if not targetHRP then return end
            
            -- Atualizar posição do anchor
            if AnchorPart and MainAttachment then
                AnchorPart.CFrame = targetHRP.CFrame
            end
        end)
        
        return true, "Magnet ativado!"
    else
        ClearConnections("Magnet")
        
        -- Limpar partes controladas
        for _, obj in pairs(Workspace:GetDescendants()) do
            if obj:IsA("BasePart") then
                CleanPartControl(obj)
            end
        end
        
        return true, "Magnet desativado!"
    end
end

-- ORBIT
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
        
        local controlledParts = {}
        
        -- Captura inicial
        for _, part in pairs(GetAvailableParts()) do
            local attach, align = SetupPartControl(part, orbitAttachment, "orbit")
            if attach and align then
                controlledParts[part] = true
            end
        end
        
        -- Captura de novas partes
        Connections.OrbitNew = Workspace.DescendantAdded:Connect(function(obj)
            if State.Orbit and obj:IsA("BasePart") then
                task.defer(function()
                    if not obj.Anchored and not IsMapPart(obj) then
                        local attach, align = SetupPartControl(obj, orbitAttachment, "orbit")
                        if attach and align then
                            controlledParts[obj] = true
                        end
                    end
                end)
            end
        end)
        
        -- Re-captura periódica (para competir com outros scripts)
        Connections.OrbitRecapture = task.spawn(function()
            while State.Orbit do
                for _, part in pairs(GetAvailableParts()) do
                    if not controlledParts[part] then
                        local attach, align = SetupPartControl(part, orbitAttachment, "orbit")
                        if attach and align then
                            controlledParts[part] = true
                        end
                    end
                end
                task.wait(Config.OrbitRecaptureInterval)
            end
        end)
        
        -- Loop de atualização
        local lastUpdate = 0
        Connections.OrbitLoop = RunService.Heartbeat:Connect(function()
            if not State.Orbit then return end
            
            local now = tick()
            if now - lastUpdate < Config.OrbitUpdateInterval then return end
            lastUpdate = now
            
            local target = State.SelectedPlayer
            if not target or not target.Character then
                State.Orbit = false
                ClearConnections("Orbit")
                return
            end
            
            local targetHRP = target.Character:FindFirstChild("HumanoidRootPart")
            if not targetHRP then return end
            
            orbitAngle = orbitAngle + Config.OrbitSpeed * Config.OrbitUpdateInterval
            
            local orbitX = math.cos(orbitAngle) * Config.OrbitRadius
            local orbitZ = math.sin(orbitAngle) * Config.OrbitRadius
            local orbitPos = targetHRP.Position + Vector3.new(orbitX, Config.OrbitHeight, orbitZ)
            
            if orbitAttachment then
                orbitAttachment.WorldPosition = orbitPos
            end
        end)
        
        return true, "Orbit ativado!"
    else
        ClearConnections("Orbit")
        
        for _, obj in pairs(Workspace:GetDescendants()) do
            if obj:IsA("BasePart") then
                CleanPartControl(obj)
            end
        end
        
        return true, "Orbit desativado!"
    end
end

-- BLACKHOLE
local function ToggleBlackhole()
    State.Blackhole = not State.Blackhole
    
    if State.Blackhole then
        if not State.SelectedPlayer or not State.SelectedPlayer.Character then
            State.Blackhole = false
            return false, "Selecione um player!"
        end
        
        local blackholeAttachment = Instance.new("Attachment")
        blackholeAttachment.Name = "_NDSBlackholeAttach"
        blackholeAttachment.Parent = AnchorPart
        table.insert(CreatedObjects, blackholeAttachment)
        
        local controlledParts = {}
        
        -- Captura inicial
        for _, part in pairs(GetAvailableParts()) do
            local attach, align = SetupPartControl(part, blackholeAttachment, "normal")
            if attach and align then
                controlledParts[part] = true
                
                -- Adicionar torque para rotação
                local torque = Instance.new("Torque")
                torque.Name = "_NDSTorque"
                torque.Torque = Vector3.new(
                    math.random(-100, 100),
                    math.random(-100, 100),
                    math.random(-100, 100)
                )
                torque.Parent = part
            end
        end
        
        -- Captura de novas partes
        Connections.BlackholeNew = Workspace.DescendantAdded:Connect(function(obj)
            if State.Blackhole and obj:IsA("BasePart") then
                task.defer(function()
                    if not obj.Anchored and not IsMapPart(obj) then
                        local attach, align = SetupPartControl(obj, blackholeAttachment, "normal")
                        if attach and align then
                            controlledParts[obj] = true
                            
                            local torque = Instance.new("Torque")
                            torque.Name = "_NDSTorque"
                            torque.Torque = Vector3.new(
                                math.random(-100, 100),
                                math.random(-100, 100),
                                math.random(-100, 100)
                            )
                            torque.Parent = obj
                        end
                    end
                end)
            end
        end)
        
        -- Loop de atualização
        local lastUpdate = 0
        Connections.BlackholeLoop = RunService.Heartbeat:Connect(function()
            if not State.Blackhole then return end
            
            local now = tick()
            if now - lastUpdate < Config.BlackholeUpdateInterval then return end
            lastUpdate = now
            
            local target = State.SelectedPlayer
            if not target or not target.Character then
                State.Blackhole = false
                ClearConnections("Blackhole")
                return
            end
            
            local targetHRP = target.Character:FindFirstChild("HumanoidRootPart")
            if not targetHRP then return end
            
            if blackholeAttachment then
                blackholeAttachment.WorldPosition = targetHRP.Position
            end
        end)
        
        return true, "Blackhole ativado!"
    else
        ClearConnections("Blackhole")
        
        for _, obj in pairs(Workspace:GetDescendants()) do
            if obj:IsA("BasePart") then
                CleanPartControl(obj)
            end
        end
        
        return true, "Blackhole desativado!"
    end
end

-- SPIN
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
        
        local controlledParts = {}
        
        -- Captura inicial
        for _, part in pairs(GetAvailableParts()) do
            local attach, align = SetupPartControl(part, spinAttachment, "normal")
            if attach and align then
                controlledParts[part] = true
            end
        end
        
        -- Captura de novas partes
        Connections.SpinNew = Workspace.DescendantAdded:Connect(function(obj)
            if State.Spin and obj:IsA("BasePart") then
                task.defer(function()
                    if not obj.Anchored and not IsMapPart(obj) then
                        local attach, align = SetupPartControl(obj, spinAttachment, "normal")
                        if attach and align then
                            controlledParts[obj] = true
                        end
                    end
                end)
            end
        end)
        
        -- Loop de atualização
        local lastUpdate = 0
        Connections.SpinLoop = RunService.Heartbeat:Connect(function()
            if not State.Spin then return end
            
            local now = tick()
            if now - lastUpdate < Config.SpinUpdateInterval then return end
            lastUpdate = now
            
            local target = State.SelectedPlayer
            if not target or not target.Character then
                State.Spin = false
                ClearConnections("Spin")
                return
            end
            
            local targetHRP = target.Character:FindFirstChild("HumanoidRootPart")
            if not targetHRP then return end
            
            spinAngle = spinAngle + Config.SpinSpeed * Config.SpinUpdateInterval
            
            local spinX = math.cos(spinAngle) * Config.SpinRadius
            local spinZ = math.sin(spinAngle) * Config.SpinRadius
            local spinPos = targetHRP.Position + Vector3.new(spinX, 2, spinZ)
            
            if spinAttachment then
                spinAttachment.WorldPosition = spinPos
            end
        end)
        
        return true, "Spin ativado!"
    else
        ClearConnections("Spin")
        
        for _, obj in pairs(Workspace:GetDescendants()) do
            if obj:IsA("BasePart") then
                CleanPartControl(obj)
            end
        end
        
        return true, "Spin desativado!"
    end
end

-- CAGE
local function ToggleCage()
    State.Cage = not State.Cage
    
    if State.Cage then
        if not State.SelectedPlayer or not State.SelectedPlayer.Character then
            State.Cage = false
            return false, "Selecione um player!"
        end
        
        local cageAttachments = {}
        local cageRadius = 8
        local cageHeight = 10
        local partsPerRing = 12
        local rings = 5
        
        -- Criar attachments para a gaiola
        for ring = 1, rings do
            local ringHeight = (ring - 1) * (cageHeight / (rings - 1)) - cageHeight / 2
            for i = 1, partsPerRing do
                local angle = (i / partsPerRing) * math.pi * 2
                local attachment = Instance.new("Attachment")
                attachment.Name = "_NDSCageAttach_" .. ring .. "_" .. i
                attachment.Parent = AnchorPart
                table.insert(cageAttachments, {
                    attach = attachment,
                    angle = angle,
                    height = ringHeight
                })
                table.insert(CreatedObjects, attachment)
            end
        end
        
        local parts = GetAvailableParts()
        local partIndex = 1
        
        -- Distribuir partes nos attachments
        for _, cageData in ipairs(cageAttachments) do
            if partIndex <= #parts then
                local part = parts[partIndex]
                SetupPartControl(part, cageData.attach, "normal")
                partIndex = partIndex + 1
            end
        end
        
        -- Loop de atualização
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
            
            local targetPos = targetHRP.Position
            
            for _, cageData in ipairs(cageAttachments) do
                local x = math.cos(cageData.angle) * cageRadius
                local z = math.sin(cageData.angle) * cageRadius
                cageData.attach.WorldPosition = targetPos + Vector3.new(x, cageData.height, z)
            end
        end)
        
        return true, "Cage ativado!"
    else
        ClearConnections("Cage")
        
        for _, obj in pairs(Workspace:GetDescendants()) do
            if obj:IsA("BasePart") then
                CleanPartControl(obj)
            end
        end
        
        return true, "Cage desativado!"
    end
end

-- PART RAIN
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
        
        local controlledParts = {}
        
        -- Captura inicial
        for _, part in pairs(GetAvailableParts()) do
            local attach, align = SetupPartControl(part, rainAttachment, "normal")
            if attach and align then
                controlledParts[part] = true
            end
        end
        
        -- Loop de atualização
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
            local rainHeight = 50 - rainOffset
            
            if rainAttachment then
                rainAttachment.WorldPosition = targetHRP.Position + Vector3.new(0, rainHeight, 0)
            end
        end)
        
        return true, "Part Rain ativado!"
    else
        ClearConnections("Rain")
        
        for _, obj in pairs(Workspace:GetDescendants()) do
            if obj:IsA("BasePart") then
                CleanPartControl(obj)
            end
        end
        
        return true, "Part Rain desativado!"
    end
end


-- HAT FLING
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
            return false, "Você não tem acessórios!"
        end
        
        local flingAttachment = Instance.new("Attachment")
        flingAttachment.Name = "_NDSFlingAttach"
        flingAttachment.Parent = AnchorPart
        table.insert(CreatedObjects, flingAttachment)
        
        -- Configurar handles para fling
        for _, handle in pairs(handles) do
            SetupPartControl(handle, flingAttachment, "orbit")
        end
        
        -- Loop de fling
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
            local flingRadius = 3
            local x = math.cos(math.rad(flingAngle)) * flingRadius
            local z = math.sin(math.rad(flingAngle)) * flingRadius
            
            if flingAttachment then
                flingAttachment.WorldPosition = targetHRP.Position + Vector3.new(x, 0, z)
            end
        end)
        
        return true, "Hat Fling ativado!"
    else
        ClearConnections("HatFling")
        
        local handles = GetMyAccessories()
        for _, handle in pairs(handles) do
            CleanPartControl(handle)
        end
        
        return true, "Hat Fling desativado!"
    end
end

-- BODY FLING
local function ToggleBodyFling()
    State.BodyFling = not State.BodyFling
    
    if State.BodyFling then
        if not State.SelectedPlayer or not State.SelectedPlayer.Character then
            State.BodyFling = false
            return false, "Selecione um player!"
        end
        
        local hrp = GetHRP()
        if not hrp then
            State.BodyFling = false
            return false, "Erro ao obter HumanoidRootPart!"
        end
        
        -- Loop de body fling
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
            if not targetHRP then return end
            
            local myHRP = GetHRP()
            if not myHRP then return end
            
            flingAngle = flingAngle + 20
            local flingRadius = 2
            local x = math.cos(math.rad(flingAngle)) * flingRadius
            local z = math.sin(math.rad(flingAngle)) * flingRadius
            
            myHRP.CFrame = targetHRP.CFrame * CFrame.new(x, 0, z)
            myHRP.Velocity = Vector3.new(
                math.random(-50, 50),
                math.random(-50, 50),
                math.random(-50, 50)
            )
        end)
        
        return true, "Body Fling ativado!"
    else
        ClearConnections("BodyFling")
        return true, "Body Fling desativado!"
    end
end

-- LAUNCH
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
        
        local controlledParts = {}
        
        -- Captura inicial
        for _, part in pairs(GetAvailableParts()) do
            local attach, align = SetupPartControl(part, launchAttachment, "orbit")
            if attach and align then
                controlledParts[part] = true
            end
        end
        
        -- Loop de launch
        local launchPhase = 0
        local launchHeight = 0
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
            
            if launchPhase < 60 then
                -- Fase de acumulação (abaixo do player)
                launchHeight = -10
            elseif launchPhase < 120 then
                -- Fase de lançamento (subindo rapidamente)
                launchHeight = launchHeight + 5
            else
                -- Reset
                launchPhase = 0
                launchHeight = 0
            end
            
            if launchAttachment then
                launchAttachment.WorldPosition = targetHRP.Position + Vector3.new(0, launchHeight, 0)
            end
        end)
        
        return true, "Launch ativado!"
    else
        ClearConnections("Launch")
        
        for _, obj in pairs(Workspace:GetDescendants()) do
            if obj:IsA("BasePart") then
                CleanPartControl(obj)
            end
        end
        
        return true, "Launch desativado!"
    end
end

-- SKY LIFT
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
        
        local controlledParts = {}
        
        -- Captura inicial
        for _, part in pairs(GetAvailableParts()) do
            local attach, align = SetupPartControl(part, skyAttachment, "normal")
            if attach and align then
                controlledParts[part] = true
            end
        end
        
        -- Loop de sky lift
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
            
            if skyAttachment then
                skyAttachment.WorldPosition = targetHRP.Position + Vector3.new(0, skyHeight, 0)
            end
        end)
        
        return true, "Sky Lift ativado!"
    else
        ClearConnections("SkyLift")
        
        for _, obj in pairs(Workspace:GetDescendants()) do
            if obj:IsA("BasePart") then
                CleanPartControl(obj)
            end
        end
        
        return true, "Sky Lift desativado!"
    end
end

-- SLOW PLAYER
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
        
        local controlledParts = {}
        
        -- Captura inicial
        for _, part in pairs(GetAvailableParts()) do
            local attach, align = SetupPartControl(part, slowAttachment, "normal")
            if attach and align then
                -- Reduzir responsiveness para movimento lento
                align.Responsiveness = 50
                align.MaxVelocity = 100
                controlledParts[part] = true
            end
        end
        
        -- Loop de slow
        Connections.SlowLoop = RunService.Heartbeat:Connect(function()
            if not State.SlowPlayer then return end
            
            local target = State.SelectedPlayer
            if not target or not target.Character then
                State.SlowPlayer = false
                ClearConnections("Slow")
                return
            end
            
            local targetHRP = target.Character:FindFirstChild("HumanoidRootPart")
            if not targetHRP then return end
            
            -- Partes seguem o player lentamente, criando arrasto
            if slowAttachment then
                slowAttachment.WorldPosition = targetHRP.Position + Vector3.new(0, -1, 0)
            end
        end)
        
        return true, "Slow Player ativado!"
    else
        ClearConnections("Slow")
        
        for _, obj in pairs(Workspace:GetDescendants()) do
            if obj:IsA("BasePart") then
                CleanPartControl(obj)
            end
        end
        
        return true, "Slow Player desativado!"
    end
end

-- SERVER MAGNET (atrai todas as partes para você)
local function ToggleServerMagnet()
    State.ServerMagnet = not State.ServerMagnet
    
    if State.ServerMagnet then
        local hrp = GetHRP()
        if not hrp then
            State.ServerMagnet = false
            return false, "Erro ao obter HumanoidRootPart!"
        end
        
        local serverAttachment = Instance.new("Attachment")
        serverAttachment.Name = "_NDSServerAttach"
        serverAttachment.Parent = AnchorPart
        table.insert(CreatedObjects, serverAttachment)
        
        local controlledParts = {}
        
        -- Captura inicial
        for _, part in pairs(GetAvailableParts()) do
            local attach, align = SetupPartControl(part, serverAttachment, "normal")
            if attach and align then
                controlledParts[part] = true
            end
        end
        
        -- Captura de novas partes
        Connections.ServerMagnetNew = Workspace.DescendantAdded:Connect(function(obj)
            if State.ServerMagnet and obj:IsA("BasePart") then
                task.defer(function()
                    if not obj.Anchored and not IsMapPart(obj) then
                        local attach, align = SetupPartControl(obj, serverAttachment, "normal")
                        if attach and align then
                            controlledParts[obj] = true
                        end
                    end
                end)
            end
        end)
        
        -- Loop de atualização
        Connections.ServerMagnetLoop = RunService.Heartbeat:Connect(function()
            if not State.ServerMagnet then return end
            
            local myHRP = GetHRP()
            if not myHRP then return end
            
            if serverAttachment then
                serverAttachment.WorldPosition = myHRP.Position
            end
        end)
        
        return true, "Server Magnet ativado!"
    else
        ClearConnections("ServerMagnet")
        
        for _, obj in pairs(Workspace:GetDescendants()) do
            if obj:IsA("BasePart") then
                CleanPartControl(obj)
            end
        end
        
        return true, "Server Magnet desativado!"
    end
end


-- ═══════════════════════════════════════════════════════════════════════════
-- FUNÇÕES DE PLAYER
-- ═══════════════════════════════════════════════════════════════════════════

-- GOD MODE
local function ToggleGodMode()
    State.GodMode = not State.GodMode
    
    if State.GodMode then
        local humanoid = GetHumanoid()
        if not humanoid then
            State.GodMode = false
            return false, "Erro ao obter Humanoid!"
        end
        
        -- Salvar valores originais
        local originalMaxHealth = humanoid.MaxHealth
        
        Connections.GodModeLoop = RunService.Heartbeat:Connect(function()
            if not State.GodMode then return end
            
            local hum = GetHumanoid()
            if hum then
                hum.Health = hum.MaxHealth
            end
        end)
        
        return true, "God Mode ativado!"
    else
        ClearConnections("GodMode")
        return true, "God Mode desativado!"
    end
end

-- FLY
local function ToggleFly()
    State.Fly = not State.Fly
    
    if State.Fly then
        local hrp = GetHRP()
        local humanoid = GetHumanoid()
        
        if not hrp or not humanoid then
            State.Fly = false
            return false, "Erro ao obter character!"
        end
        
        -- Criar BodyGyro e BodyVelocity para fly
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
        
        -- Loop de fly
        Connections.FlyLoop = RunService.Heartbeat:Connect(function()
            if not State.Fly then return end
            
            local myHRP = GetHRP()
            if not myHRP then return end
            
            local bg = myHRP:FindFirstChild("_NDSFlyGyro")
            local bv = myHRP:FindFirstChild("_NDSFlyVelocity")
            
            if not bg or not bv then return end
            
            -- Orientação baseada na câmera
            bg.CFrame = Camera.CFrame
            
            -- Movimento baseado em input
            local moveDirection = Vector3.new(0, 0, 0)
            
            if UserInputService:IsKeyDown(Enum.KeyCode.W) then
                moveDirection = moveDirection + Camera.CFrame.LookVector
            end
            if UserInputService:IsKeyDown(Enum.KeyCode.S) then
                moveDirection = moveDirection - Camera.CFrame.LookVector
            end
            if UserInputService:IsKeyDown(Enum.KeyCode.A) then
                moveDirection = moveDirection - Camera.CFrame.RightVector
            end
            if UserInputService:IsKeyDown(Enum.KeyCode.D) then
                moveDirection = moveDirection + Camera.CFrame.RightVector
            end
            if UserInputService:IsKeyDown(Enum.KeyCode.Space) then
                moveDirection = moveDirection + Vector3.new(0, 1, 0)
            end
            if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then
                moveDirection = moveDirection - Vector3.new(0, 1, 0)
            end
            
            -- Aplicar velocidade
            if moveDirection.Magnitude > 0 then
                bv.Velocity = moveDirection.Unit * Config.FlySpeed
            else
                bv.Velocity = Vector3.new(0, 0, 0)
            end
        end)
        
        return true, "Fly ativado! (WASD + Space/Ctrl)"
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

-- NOCLIP
local function ToggleNoclip()
    State.Noclip = not State.Noclip
    
    if State.Noclip then
        Connections.NoclipLoop = RunService.Stepped:Connect(function()
            if not State.Noclip then return end
            
            local char = GetCharacter()
            if char then
                for _, part in pairs(char:GetDescendants()) do
                    if part:IsA("BasePart") then
                        part.CanCollide = false
                    end
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

-- SPEED
local function ToggleSpeed()
    State.Speed = not State.Speed
    
    if State.Speed then
        local humanoid = GetHumanoid()
        if not humanoid then
            State.Speed = false
            return false, "Erro ao obter Humanoid!"
        end
        
        local originalSpeed = humanoid.WalkSpeed
        humanoid.WalkSpeed = originalSpeed * Config.SpeedMultiplier
        
        Connections.SpeedReset = humanoid.Died:Connect(function()
            State.Speed = false
        end)
        
        return true, "Speed ativado! (" .. humanoid.WalkSpeed .. ")"
    else
        ClearConnections("Speed")
        
        local humanoid = GetHumanoid()
        if humanoid then
            humanoid.WalkSpeed = 16 -- Valor padrão
        end
        
        return true, "Speed desativado!"
    end
end

-- VIEW PLAYER
local function ToggleView()
    State.View = not State.View
    
    if State.View then
        if not State.SelectedPlayer or not State.SelectedPlayer.Character then
            State.View = false
            return false, "Selecione um player!"
        end
        
        local targetHumanoid = State.SelectedPlayer.Character:FindFirstChildOfClass("Humanoid")
        if targetHumanoid then
            Camera.CameraSubject = targetHumanoid
        end
        
        return true, "Visualizando " .. State.SelectedPlayer.Name
    else
        local humanoid = GetHumanoid()
        if humanoid then
            Camera.CameraSubject = humanoid
        end
        
        return true, "View desativado!"
    end
end

-- ESP
local function ToggleESP()
    State.ESP = not State.ESP
    
    if State.ESP then
        local function CreateESP(player)
            if player == LocalPlayer then return end
            
            local highlight = Instance.new("Highlight")
            highlight.Name = "_NDSESP_" .. player.Name
            highlight.FillColor = Color3.fromRGB(255, 0, 0)
            highlight.OutlineColor = Color3.fromRGB(255, 255, 255)
            highlight.FillTransparency = 0.5
            highlight.OutlineTransparency = 0
            highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
            
            if player.Character then
                highlight.Adornee = player.Character
                highlight.Parent = player.Character
            end
            
            table.insert(CreatedObjects, highlight)
        end
        
        -- Criar ESP para players existentes
        for _, player in pairs(Players:GetPlayers()) do
            CreateESP(player)
        end
        
        -- ESP para novos players
        Connections.ESPNew = Players.PlayerAdded:Connect(function(player)
            if State.ESP then
                player.CharacterAdded:Connect(function()
                    task.wait(0.5)
                    CreateESP(player)
                end)
            end
        end)
        
        -- Atualizar ESP quando character spawna
        Connections.ESPCharacter = Players.PlayerAdded:Connect(function(player)
            player.CharacterAdded:Connect(function(char)
                if State.ESP then
                    task.wait(0.5)
                    local highlight = Instance.new("Highlight")
                    highlight.Name = "_NDSESP_" .. player.Name
                    highlight.FillColor = Color3.fromRGB(255, 0, 0)
                    highlight.OutlineColor = Color3.fromRGB(255, 255, 255)
                    highlight.FillTransparency = 0.5
                    highlight.OutlineTransparency = 0
                    highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
                    highlight.Adornee = char
                    highlight.Parent = char
                    table.insert(CreatedObjects, highlight)
                end
            end)
        end)
        
        return true, "ESP ativado!"
    else
        ClearConnections("ESP")
        
        -- Remover highlights
        for _, player in pairs(Players:GetPlayers()) do
            if player.Character then
                local highlight = player.Character:FindFirstChild("_NDSESP_" .. player.Name)
                if highlight then
                    highlight:Destroy()
                end
            end
        end
        
        return true, "ESP desativado!"
    end
end

-- TELEKINESIS
local function ToggleTelekinesis()
    State.Telekinesis = not State.Telekinesis
    
    if State.Telekinesis then
        local teleAttachment = Instance.new("Attachment")
        teleAttachment.Name = "_NDSTeleAttach"
        teleAttachment.Parent = AnchorPart
        table.insert(CreatedObjects, teleAttachment)
        
        -- Click para selecionar parte
        Connections.TeleClick = UserInputService.InputBegan:Connect(function(input)
            if not State.Telekinesis then return end
            
            if input.UserInputType == Enum.UserInputType.MouseButton1 then
                local mouse = LocalPlayer:GetMouse()
                local target = mouse.Target
                
                if target and target:IsA("BasePart") and not target.Anchored then
                    if not IsMapPart(target) then
                        -- Limpar parte anterior
                        if TelekinesisTarget then
                            CleanPartControl(TelekinesisTarget)
                        end
                        
                        TelekinesisTarget = target
                        SetupPartControl(target, teleAttachment, "normal")
                        Notify("Telekinesis", "Parte selecionada: " .. target.Name, 2)
                    end
                end
            end
        end)
        
        -- Scroll para ajustar distância
        Connections.TeleScroll = UserInputService.InputChanged:Connect(function(input)
            if not State.Telekinesis then return end
            
            if input.UserInputType == Enum.UserInputType.MouseWheel then
                TelekinesisDistance = math.clamp(TelekinesisDistance + input.Position.Z * 2, 5, 100)
            end
        end)
        
        -- Loop de atualização
        Connections.TeleLoop = RunService.Heartbeat:Connect(function()
            if not State.Telekinesis then return end
            
            local mouse = LocalPlayer:GetMouse()
            local ray = Camera:ScreenPointToRay(mouse.X, mouse.Y)
            local targetPos = ray.Origin + ray.Direction * TelekinesisDistance
            
            if teleAttachment then
                teleAttachment.WorldPosition = targetPos
            end
        end)
        
        return true, "Telekinesis ativado! (Click para selecionar, Scroll para distância)"
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
-- INTERFACE GRÁFICA (GUI) - OTIMIZADA PARA MOBILE
-- ═══════════════════════════════════════════════════════════════════════════

local function CreateGUI()
    local platform = GetPlatformInfo()
    
    -- Tamanhos adaptados para plataforma
    local buttonWidth = platform.isMobile and 130 or 110
    local buttonHeight = platform.isMobile and 45 or 35
    local fontSize = platform.isMobile and 14 or 12
    local padding = platform.isMobile and 8 or 5
    
    -- Destruir GUI existente
    local existingGui = LocalPlayer.PlayerGui:FindFirstChild("NDSTrollHub")
    if existingGui then
        existingGui:Destroy()
    end
    
    -- Criar ScreenGui
    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "NDSTrollHub"
    screenGui.ResetOnSpawn = false
    screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    screenGui.Parent = LocalPlayer.PlayerGui
    
    -- Frame principal
    local mainFrame = Instance.new("Frame")
    mainFrame.Name = "MainFrame"
    mainFrame.Size = UDim2.new(0, 350, 0, 450)
    mainFrame.Position = UDim2.new(0.5, -175, 0.5, -225)
    mainFrame.BackgroundColor3 = Color3.fromRGB(25, 25, 35)
    mainFrame.BorderSizePixel = 0
    mainFrame.Active = true
    mainFrame.Draggable = true
    mainFrame.Parent = screenGui
    
    -- Cantos arredondados
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 10)
    corner.Parent = mainFrame
    
    -- Sombra
    local shadow = Instance.new("ImageLabel")
    shadow.Name = "Shadow"
    shadow.Size = UDim2.new(1, 30, 1, 30)
    shadow.Position = UDim2.new(0, -15, 0, -15)
    shadow.BackgroundTransparency = 1
    shadow.Image = "rbxassetid://5554236805"
    shadow.ImageColor3 = Color3.fromRGB(0, 0, 0)
    shadow.ImageTransparency = 0.5
    shadow.ScaleType = Enum.ScaleType.Slice
    shadow.SliceCenter = Rect.new(23, 23, 277, 277)
    shadow.ZIndex = -1
    shadow.Parent = mainFrame
    
    -- Header
    local header = Instance.new("Frame")
    header.Name = "Header"
    header.Size = UDim2.new(1, 0, 0, 50)
    header.BackgroundColor3 = Color3.fromRGB(35, 35, 50)
    header.BorderSizePixel = 0
    header.Parent = mainFrame
    
    local headerCorner = Instance.new("UICorner")
    headerCorner.CornerRadius = UDim.new(0, 10)
    headerCorner.Parent = header
    
    -- Título
    local title = Instance.new("TextLabel")
    title.Name = "Title"
    title.Size = UDim2.new(1, -50, 1, 0)
    title.Position = UDim2.new(0, 10, 0, 0)
    title.BackgroundTransparency = 1
    title.Text = "NDS TROLL HUB v8.0"
    title.TextColor3 = Color3.fromRGB(255, 255, 255)
    title.TextSize = 18
    title.Font = Enum.Font.GothamBold
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.Parent = header
    
    -- Indicador de plataforma
    local platformLabel = Instance.new("TextLabel")
    platformLabel.Name = "Platform"
    platformLabel.Size = UDim2.new(0, 80, 0, 20)
    platformLabel.Position = UDim2.new(1, -90, 0.5, -10)
    platformLabel.BackgroundColor3 = platform.isMobile and Color3.fromRGB(0, 150, 255) or Color3.fromRGB(0, 200, 100)
    platformLabel.Text = platform.isMobile and "MOBILE" or "PC"
    platformLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    platformLabel.TextSize = 12
    platformLabel.Font = Enum.Font.GothamBold
    platformLabel.Parent = header
    
    local platformCorner = Instance.new("UICorner")
    platformCorner.CornerRadius = UDim.new(0, 5)
    platformCorner.Parent = platformLabel
    
    -- Botão de minimizar
    local minimizeBtn = Instance.new("TextButton")
    minimizeBtn.Name = "Minimize"
    minimizeBtn.Size = UDim2.new(0, 30, 0, 30)
    minimizeBtn.Position = UDim2.new(1, -40, 0.5, -15)
    minimizeBtn.BackgroundColor3 = Color3.fromRGB(255, 100, 100)
    minimizeBtn.Text = "-"
    minimizeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    minimizeBtn.TextSize = 20
    minimizeBtn.Font = Enum.Font.GothamBold
    minimizeBtn.Parent = header
    
    local minimizeCorner = Instance.new("UICorner")
    minimizeCorner.CornerRadius = UDim.new(0, 5)
    minimizeCorner.Parent = minimizeBtn
    
    -- Container de conteúdo
    local contentFrame = Instance.new("Frame")
    contentFrame.Name = "Content"
    contentFrame.Size = UDim2.new(1, -20, 1, -60)
    contentFrame.Position = UDim2.new(0, 10, 0, 55)
    contentFrame.BackgroundTransparency = 1
    contentFrame.Parent = mainFrame
    
    -- ScrollingFrame para botões
    local scrollFrame = Instance.new("ScrollingFrame")
    scrollFrame.Name = "ScrollFrame"
    scrollFrame.Size = UDim2.new(1, 0, 1, -50)
    scrollFrame.Position = UDim2.new(0, 0, 0, 50)
    scrollFrame.BackgroundTransparency = 1
    scrollFrame.ScrollBarThickness = 5
    scrollFrame.ScrollBarImageColor3 = Color3.fromRGB(100, 100, 100)
    scrollFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
    scrollFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
    scrollFrame.Parent = contentFrame
    
    -- Layout para botões
    local gridLayout = Instance.new("UIGridLayout")
    gridLayout.CellSize = UDim2.new(0, buttonWidth, 0, buttonHeight)
    gridLayout.CellPadding = UDim2.new(0, padding, 0, padding)
    gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
    gridLayout.Parent = scrollFrame
    
    -- Dropdown de seleção de player
    local playerDropdown = Instance.new("Frame")
    playerDropdown.Name = "PlayerDropdown"
    playerDropdown.Size = UDim2.new(1, 0, 0, 40)
    playerDropdown.BackgroundColor3 = Color3.fromRGB(40, 40, 55)
    playerDropdown.BorderSizePixel = 0
    playerDropdown.Parent = contentFrame
    
    local dropdownCorner = Instance.new("UICorner")
    dropdownCorner.CornerRadius = UDim.new(0, 8)
    dropdownCorner.Parent = playerDropdown
    
    local selectedLabel = Instance.new("TextLabel")
    selectedLabel.Name = "SelectedLabel"
    selectedLabel.Size = UDim2.new(1, -40, 1, 0)
    selectedLabel.Position = UDim2.new(0, 10, 0, 0)
    selectedLabel.BackgroundTransparency = 1
    selectedLabel.Text = "Selecione um Player"
    selectedLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
    selectedLabel.TextSize = fontSize
    selectedLabel.Font = Enum.Font.Gotham
    selectedLabel.TextXAlignment = Enum.TextXAlignment.Left
    selectedLabel.Parent = playerDropdown
    
    local dropdownBtn = Instance.new("TextButton")
    dropdownBtn.Name = "DropdownBtn"
    dropdownBtn.Size = UDim2.new(0, 30, 0, 30)
    dropdownBtn.Position = UDim2.new(1, -35, 0.5, -15)
    dropdownBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 80)
    dropdownBtn.Text = "▼"
    dropdownBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    dropdownBtn.TextSize = 14
    dropdownBtn.Font = Enum.Font.GothamBold
    dropdownBtn.Parent = playerDropdown
    
    local dropdownBtnCorner = Instance.new("UICorner")
    dropdownBtnCorner.CornerRadius = UDim.new(0, 5)
    dropdownBtnCorner.Parent = dropdownBtn
    
    -- Lista de players (inicialmente oculta)
    local playerList = Instance.new("Frame")
    playerList.Name = "PlayerList"
    playerList.Size = UDim2.new(1, 0, 0, 150)
    playerList.Position = UDim2.new(0, 0, 0, 45)
    playerList.BackgroundColor3 = Color3.fromRGB(35, 35, 50)
    playerList.BorderSizePixel = 0
    playerList.Visible = false
    playerList.ZIndex = 10
    playerList.Parent = contentFrame
    
    local playerListCorner = Instance.new("UICorner")
    playerListCorner.CornerRadius = UDim.new(0, 8)
    playerListCorner.Parent = playerList
    
    local playerScroll = Instance.new("ScrollingFrame")
    playerScroll.Name = "PlayerScroll"
    playerScroll.Size = UDim2.new(1, -10, 1, -10)
    playerScroll.Position = UDim2.new(0, 5, 0, 5)
    playerScroll.BackgroundTransparency = 1
    playerScroll.ScrollBarThickness = 4
    playerScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
    playerScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
    playerScroll.ZIndex = 11
    playerScroll.Parent = playerList
    
    local playerListLayout = Instance.new("UIListLayout")
    playerListLayout.SortOrder = Enum.SortOrder.Name
    playerListLayout.Padding = UDim.new(0, 3)
    playerListLayout.Parent = playerScroll
    
    -- Função para criar botão de player
    local function CreatePlayerButton(player)
        local btn = Instance.new("TextButton")
        btn.Name = player.Name
        btn.Size = UDim2.new(1, -5, 0, 30)
        btn.BackgroundColor3 = Color3.fromRGB(50, 50, 70)
        btn.Text = player.Name
        btn.TextColor3 = Color3.fromRGB(255, 255, 255)
        btn.TextSize = fontSize
        btn.Font = Enum.Font.Gotham
        btn.ZIndex = 12
        btn.Parent = playerScroll
        
        local btnCorner = Instance.new("UICorner")
        btnCorner.CornerRadius = UDim.new(0, 5)
        btnCorner.Parent = btn
        
        btn.MouseButton1Click:Connect(function()
            State.SelectedPlayer = player
            selectedLabel.Text = player.Name
            playerList.Visible = false
            Notify("NDS v8.0", "Player selecionado: " .. player.Name, 2)
        end)
        
        -- Suporte a touch
        btn.TouchTap:Connect(function()
            State.SelectedPlayer = player
            selectedLabel.Text = player.Name
            playerList.Visible = false
            Notify("NDS v8.0", "Player selecionado: " .. player.Name, 2)
        end)
        
        return btn
    end
    
    -- Atualizar lista de players
    local function UpdatePlayerList()
        for _, child in pairs(playerScroll:GetChildren()) do
            if child:IsA("TextButton") then
                child:Destroy()
            end
        end
        
        for _, player in pairs(Players:GetPlayers()) do
            if player ~= LocalPlayer then
                CreatePlayerButton(player)
            end
        end
    end
    
    -- Toggle dropdown
    dropdownBtn.MouseButton1Click:Connect(function()
        playerList.Visible = not playerList.Visible
        if playerList.Visible then
            UpdatePlayerList()
        end
    end)
    
    dropdownBtn.TouchTap:Connect(function()
        playerList.Visible = not playerList.Visible
        if playerList.Visible then
            UpdatePlayerList()
        end
    end)
    
    -- Função para criar botão de função
    local function CreateFunctionButton(name, displayName, callback, layoutOrder)
        local btn = Instance.new("TextButton")
        btn.Name = name
        btn.LayoutOrder = layoutOrder or 0
        btn.BackgroundColor3 = Color3.fromRGB(50, 50, 70)
        btn.Text = displayName
        btn.TextColor3 = Color3.fromRGB(255, 255, 255)
        btn.TextSize = fontSize
        btn.Font = Enum.Font.Gotham
        btn.AutoButtonColor = true
        btn.Parent = scrollFrame
        
        local btnCorner = Instance.new("UICorner")
        btnCorner.CornerRadius = UDim.new(0, 8)
        btnCorner.Parent = btn
        
        local function OnClick()
            local success, message = callback()
            if success then
                if State[name] then
                    btn.BackgroundColor3 = Color3.fromRGB(0, 150, 100)
                else
                    btn.BackgroundColor3 = Color3.fromRGB(50, 50, 70)
                end
            end
            if message then
                Notify("NDS v8.0", message, 2)
            end
        end
        
        btn.MouseButton1Click:Connect(OnClick)
        btn.TouchTap:Connect(OnClick)
        
        return btn
    end
    
    -- Criar botões de funções
    local buttons = {
        {name = "Magnet", display = "🧲 Magnet", func = ToggleMagnet, order = 1},
        {name = "Orbit", display = "🌀 Orbit", func = ToggleOrbit, order = 2},
        {name = "Blackhole", display = "⚫ Blackhole", func = ToggleBlackhole, order = 3},
        {name = "Spin", display = "🔄 Spin", func = ToggleSpin, order = 4},
        {name = "Cage", display = "🔒 Cage", func = ToggleCage, order = 5},
        {name = "PartRain", display = "🌧️ Part Rain", func = TogglePartRain, order = 6},
        {name = "HatFling", display = "🎩 Hat Fling", func = ToggleHatFling, order = 7},
        {name = "BodyFling", display = "💥 Body Fling", func = ToggleBodyFling, order = 8},
        {name = "Launch", display = "🚀 Launch", func = ToggleLaunch, order = 9},
        {name = "SkyLift", display = "☁️ Sky Lift", func = ToggleSkyLift, order = 10},
        {name = "SlowPlayer", display = "🐢 Slow", func = ToggleSlowPlayer, order = 11},
        {name = "ServerMagnet", display = "🌐 Server Magnet", func = ToggleServerMagnet, order = 12},
        {name = "GodMode", display = "❤️ God Mode", func = ToggleGodMode, order = 13},
        {name = "Fly", display = "✈️ Fly", func = ToggleFly, order = 14},
        {name = "Noclip", display = "👻 Noclip", func = ToggleNoclip, order = 15},
        {name = "Speed", display = "⚡ Speed", func = ToggleSpeed, order = 16},
        {name = "View", display = "👁️ View", func = ToggleView, order = 17},
        {name = "ESP", display = "🔍 ESP", func = ToggleESP, order = 18},
        {name = "Telekinesis", display = "🖐️ Telekinesis", func = ToggleTelekinesis, order = 19},
    }
    
    for _, btnData in ipairs(buttons) do
        CreateFunctionButton(btnData.name, btnData.display, btnData.func, btnData.order)
    end
    
    -- Botão de desativar tudo
    local disableAllBtn = Instance.new("TextButton")
    disableAllBtn.Name = "DisableAll"
    disableAllBtn.LayoutOrder = 100
    disableAllBtn.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
    disableAllBtn.Text = "❌ Desativar Tudo"
    disableAllBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    disableAllBtn.TextSize = fontSize
    disableAllBtn.Font = Enum.Font.GothamBold
    disableAllBtn.Parent = scrollFrame
    
    local disableCorner = Instance.new("UICorner")
    disableCorner.CornerRadius = UDim.new(0, 8)
    disableCorner.Parent = disableAllBtn
    
    local function OnDisableAll()
        DisableAllFunctions()
        
        -- Resetar cores dos botões
        for _, child in pairs(scrollFrame:GetChildren()) do
            if child:IsA("TextButton") and child.Name ~= "DisableAll" then
                child.BackgroundColor3 = Color3.fromRGB(50, 50, 70)
            end
        end
        
        Notify("NDS v8.0", "Todas as funções desativadas!", 2)
    end
    
    disableAllBtn.MouseButton1Click:Connect(OnDisableAll)
    disableAllBtn.TouchTap:Connect(OnDisableAll)
    
    -- Minimizar/Maximizar
    local isMinimized = false
    local originalSize = mainFrame.Size
    
    minimizeBtn.MouseButton1Click:Connect(function()
        isMinimized = not isMinimized
        if isMinimized then
            mainFrame.Size = UDim2.new(0, 350, 0, 50)
            contentFrame.Visible = false
            minimizeBtn.Text = "+"
        else
            mainFrame.Size = originalSize
            contentFrame.Visible = true
            minimizeBtn.Text = "-"
        end
    end)
    
    minimizeBtn.TouchTap:Connect(function()
        isMinimized = not isMinimized
        if isMinimized then
            mainFrame.Size = UDim2.new(0, 350, 0, 50)
            contentFrame.Visible = false
            minimizeBtn.Text = "+"
        else
            mainFrame.Size = originalSize
            contentFrame.Visible = true
            minimizeBtn.Text = "-"
        end
    end)
    
    -- Atualizar lista quando players entram/saem
    Players.PlayerAdded:Connect(function()
        if playerList.Visible then
            UpdatePlayerList()
        end
    end)
    
    Players.PlayerRemoving:Connect(function(player)
        if State.SelectedPlayer == player then
            State.SelectedPlayer = nil
            selectedLabel.Text = "Selecione um Player"
            DisableAllFunctions()
            Notify("NDS v8.0", "Player selecionado saiu do jogo!", 3)
        end
        if playerList.Visible then
            UpdatePlayerList()
        end
    end)
    
    return screenGui
end


-- ═══════════════════════════════════════════════════════════════════════════
-- INICIALIZAÇÃO
-- ═══════════════════════════════════════════════════════════════════════════

local function Initialize()
    -- Ajustar constantes para plataforma
    AdjustConstantsForPlatform()
    
    -- Configurar controle de rede
    SetupNetworkControl()
    
    -- Criar GUI
    CreateGUI()
    
    -- Mensagem de boas-vindas
    local platform = GetPlatformInfo()
    local platformText = platform.isMobile and "Mobile" or "PC"
    local executorText = platform.executorName ~= "Unknown" and (" (" .. platform.executorName .. ")") or ""
    
    Notify("NDS TROLL HUB v8.0", "Carregado com sucesso!\nPlataforma: " .. platformText .. executorText, 5)
    
    -- Avisos de compatibilidade
    if not platform.hasSetHiddenProperty and not platform.hasSetSimRadius then
        task.wait(1)
        Notify("Aviso", "SimulationRadius limitado neste executor. Algumas funções podem ter alcance reduzido.", 5)
    end
    
    -- Log de debug
    print("═══════════════════════════════════════════════════")
    print("NDS TROLL HUB v8.0 - OPTIMIZED")
    print("═══════════════════════════════════════════════════")
    print("Plataforma: " .. platformText)
    print("Executor: " .. platform.executorName)
    print("sethiddenproperty: " .. tostring(platform.hasSetHiddenProperty))
    print("setsimulationradius: " .. tostring(platform.hasSetSimRadius))
    print("getgenv: " .. tostring(platform.hasGetGenv))
    print("═══════════════════════════════════════════════════")
    print("")
    print("CHANGELOG v8.0:")
    print("- CORRIGIDO: Bug de arremesso ao pisar em áreas do mapa")
    print("- CORRIGIDO: Compatibilidade com executores mobile")
    print("- MELHORADO: Filtro de partes do mapa")
    print("- MELHORADO: Valores seguros (sem math.huge)")
    print("- ADICIONADO: Detecção automática de plataforma")
    print("═══════════════════════════════════════════════════")
end

-- Executar inicialização
Initialize()

-- ═══════════════════════════════════════════════════════════════════════════
-- LIMPEZA AO SAIR
-- ═══════════════════════════════════════════════════════════════════════════

LocalPlayer.CharacterRemoving:Connect(function()
    -- Limpar ao morrer/respawnar
    DisableAllFunctions()
end)

game:BindToClose(function()
    -- Limpar ao fechar o jogo
    DisableAllFunctions()
    genv.NDS_TROLL_HUB_V8_LOADED = nil
end)

-- ═══════════════════════════════════════════════════════════════════════════
-- FIM DO SCRIPT
-- ═══════════════════════════════════════════════════════════════════════════
