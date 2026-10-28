-- STEAL AN EGG | AUTO FARM V2 | DELTA ANDROID
-- Arquivo independente. NAO carrega o script antigo, NAO muda WalkSpeed.
-- Pega dados do snapshot de ovos reais (nao escolhe prompts decorativos do lobby).
-- TP direto depende das validacoes do servidor; falhas sao exibidas no menu.

if not game:IsLoaded() then game.Loaded:Wait() end
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local UIS = game:GetService("UserInputService")
local LP = Players.LocalPlayer
local env = (type(getgenv) == "function" and getgenv()) or _G
if env.__SAE_FARM_V2 and type(env.__SAE_FARM_V2.Destroy) == "function" then
    pcall(env.__SAE_FARM_V2.Destroy)
end
-- Fecha o menu antigo sem deixar dois farms concorrendo.
if env.__SAE_DELTA_ANDROID and type(env.__SAE_DELTA_ANDROID.Destroy) == "function" then
    pcall(env.__SAE_DELTA_ANDROID.Destroy)
end

local S = {
    alive = true, running = false, busy = false, generation = 0,
    safe = nil, safeType = nil, carrying = nil, carryingKnown = false,
    attempts = 0, accepted = 0, escaped = 0, errors = 0,
    status = "Carregado. Defina um local seguro.", lastError = "",
    lastList = {}, catalog = {}, mutations = nil,
    connections = {}, ignored = {}, lastSnapshotError = "",
}
local gui, panel, info, farmButton, bestButton
local function notify(msg)
    S.status = tostring(msg)
    print("[Egg V2] " .. S.status)
end
local function fail(msg)
    S.errors = S.errors + 1
    S.lastError = tostring(msg)
    warn("[Egg V2] " .. S.lastError)
    notify(msg)
end
local function bind(signal, fn)
    local con = signal:Connect(fn)
    table.insert(S.connections, con)
    return con
end
local function character()
    local c = LP.Character
    local root = c and c:FindFirstChild("HumanoidRootPart")
    local hum = c and c:FindFirstChildOfClass("Humanoid")
    if not root or not hum or hum.Health <= 0 then return nil, nil end
    return root, hum
end
local function remote(names, className)
    local packages = RS:FindFirstChild("Packages")
    local roots = {}
    local current = packages and packages:FindFirstChild("Networking")
    if current then table.insert(roots, current) end
    local legacy = RS:FindFirstChild("Network")
    if legacy then table.insert(roots, legacy) end
    for _, container in ipairs(roots) do
        if container then
            for _, name in ipairs(names) do
                local obj = container:FindFirstChild(name, true)
                if obj and (not className or obj:IsA(className)) then return obj end
            end
        end
    end
    return nil
end
local function invoke(names, arg, timeout)
    local obj = remote(names, "RemoteFunction")
    if not obj then return false, "RemoteFunction nao encontrado" end
    local done, good, result, extra = false, false, nil, nil
    task.spawn(function()
        local ok, a, b = pcall(function()
            if arg == nil then return obj:InvokeServer() end
            return obj:InvokeServer(arg)
        end)
        good, result, extra, done = ok, a, b, true
    end)
    local deadline = os.clock() + (timeout or 5)
    while not done and os.clock() < deadline and S.alive do task.wait(0.04) end
    if not done then return false, "tempo esgotado em " .. obj.Name end
    if not good then return false, tostring(result) end
    return true, result, extra
end
local SNAPSHOT = { "RF/EggWorld/AskFieldEggSnapshot", "Eggs: RequestAreaEggSnapshot" }
local CARRY = { "RF/EggWorld/AskFieldEggCarry", "Eggs: RequestAreaEggCarry" }
local PLOT = { "RF/Homestead/AskState", "Plots: RequestState" }

local function moduleTable(parent, name)
    local mod = parent and parent:FindFirstChild(name)
    if not (mod and mod:IsA("ModuleScript")) then return nil end
    local ok, obj = pcall(require, mod)
    if ok and type(obj) == "table" then return obj.Directory or obj end
    return nil
end
local function loadDefinitions()
    local data = RS:FindFirstChild("Data") or RS:FindFirstChild("Directory")
    S.catalog = moduleTable(data, "Assets") or {}
    local shared = RS:FindFirstChild("Shared")
    local legacy = RS:FindFirstChild("Library")
    S.mutations = moduleTable(shared and shared:FindFirstChild("Modules"), "Mutations")
        or moduleTable(legacy and legacy:FindFirstChild("Modules"), "Mutations")
end
local function multiplier(rec)
    local muts = rec.Mutations
    if type(muts) ~= "table" or next(muts) == nil then return 1 end
    local mod = S.mutations
    local fn = mod and (mod.EarningsFor or mod.GetTotalMutationsEarningMulti)
    if type(fn) == "function" then
        local ok, value = pcall(fn, muts)
        if ok and type(value) == "number" and value > 0 then return value end
    end
    -- Sem modulo de mutacoes: valor conservador, nao inventa bonus.
    return 1
end
local function numberShort(n)
    if n >= 1e12 then return string.format("%.2fT", n / 1e12) end
    if n >= 1e9 then return string.format("%.2fB", n / 1e9) end
    if n >= 1e6 then return string.format("%.2fM", n / 1e6) end
    if n >= 1e3 then return string.format("%.2fK", n / 1e3) end
    return string.format("%.0f", n)
end
local function candidates()
    local ok, snapshot = invoke(SNAPSHOT, nil, 6)
    if not ok or type(snapshot) ~= "table" or type(snapshot.Records) ~= "table" then
        S.lastSnapshotError = ok and "Snapshot sem Records" or tostring(snapshot)
        S.lastList = {}
        return {}, S.lastSnapshotError
    end
    S.lastSnapshotError = ""
    local root = character()
    local list = {}
    for _, rec in pairs(snapshot.Records) do
        if type(rec) == "table" and rec.State == "Slot" and rec.Uid ~= nil
            and typeof(rec.BottomCFrame) == "CFrame" and not S.ignored[tostring(rec.Uid)] then
            local def = S.catalog[rec.AssetCategory]
            local base = def and tonumber(def.EarningRate)
            if base then
                local scale = math.max(0.01, tonumber(rec.AssetScale or rec.Scale) or 1)
                local value = base * (scale ^ 1.85) * multiplier(rec)
                local pos = rec.BottomCFrame.Position
                local dist = root and (root.Position - pos).Magnitude or math.huge
                local name = (def and def.Egg and def.Egg.DisplayName)
                    or (def and def.DisplayName) or tostring(rec.AssetCategory)
                table.insert(list, { record = rec, uid = tostring(rec.Uid),
                    pos = pos, value = value, dist = dist,
                    category = tostring(rec.AssetCategory), name = tostring(name),
                    area = tostring(rec.AreaId or "-") })
            end
        end
    end
    table.sort(list, function(a, b)
        if a.value ~= b.value then return a.value > b.value end
        return a.dist < b.dist
    end)
    S.lastList = list
    return list, nil
end

local function detectOwnPlot()
    local plots = workspace:FindFirstChild("Plots")
    if not plots then return false, "Pasta Plots ausente" end
    local ok, state = invoke(PLOT, nil, 4)
    local plot = nil
    if ok and type(state) == "table" and type(state.OwnersBySlot) == "table" then
        for slot, owner in pairs(state.OwnersBySlot) do
            if tonumber(owner) == LP.UserId then
                plot = plots:FindFirstChild(tostring(slot))
                break
            end
        end
    end
    if not plot then
        for _, p in ipairs(plots:GetChildren()) do
            local sign = p:FindFirstChild("PlotSign", true)
            if sign then
                for _, item in ipairs(sign:GetDescendants()) do
                    if item:IsA("TextLabel") and (item.Text == LP.Name or item.Text == LP.DisplayName) then
                        plot = p
                        break
                    end
                end
            end
            if plot then break end
        end
    end
    if not plot then return false, "Sua base nao foi identificada" end
    local area = plot:FindFirstChild("PetArea", true) or plot:FindFirstChild("CenterPoint", true)
    if not (area and area:IsA("BasePart")) then return false, "PetArea nao encontrada" end
    S.safe = CFrame.new(area.Position + Vector3.new(0, 3.5, 0))
    S.safeType = "base"
    notify("Local seguro automatico: sua base (PetArea)")
    return true
end
local function markSafe()
    local root = character()
    if not root then fail("Personagem indisponivel") return end
    S.safe = root.CFrame
    S.safeType = "manual"
    notify("Local seguro marcado onde voce esta")
end

local function teleport(pos, tolerance)
    local root, hum = character()
    if not root then return false, "Personagem indisponivel" end
    if typeof(pos) ~= "Vector3" then return false, "Posicao invalida" end
    local before = root.Position
    local destination = pos + Vector3.new(0, 2, 0)
    local success, msg = pcall(function()
        root.CFrame = CFrame.new(destination, destination + root.CFrame.LookVector)
        root.AssemblyLinearVelocity = Vector3.zero
    end)
    if not success then return false, tostring(msg) end
    task.wait(0.32)
    root, hum = character()
    if not root then return false, "Personagem morreu ou desconectou" end
    if (root.Position - destination).Magnitude > (tolerance or 10) then
        return false, "TP rejeitado ou posicao corrigida pelo jogo"
    end
    -- Evita reportar sucesso se o personagem nem saiu do lugar.
    if (before - destination).Magnitude > (tolerance or 10) and
       (root.Position - before).Magnitude < 1 then
        return false, "TP nao alterou a posicao"
    end
    return true
end

local function nearestPrompt(pos)
    local best, distance = nil, math.huge
    for _, obj in ipairs(workspace:GetDescendants()) do
        if obj:IsA("ProximityPrompt") and obj.Name == "CarryAreaEgg" then
            local part = obj.Parent
            local p = part and (part:IsA("BasePart") and part.Position
                or part:IsA("Attachment") and part.WorldPosition)
            if typeof(p) == "Vector3" then
                local d = (p - pos).Magnitude
                if d < distance then best, distance = obj, d end
            end
        end
    end
    if distance <= 13 then return best end
    return nil
end
local function requestInstantPickup(egg)
    local ok, response, detail = invoke(CARRY, {Uid = egg.record.Uid}, 4)
    if ok and response == true then return true, "remote confirmou" end
    if ok and type(response) == "table" and response.Success == true then
        return true, "remote confirmou"
    end
    -- Apenas como alternativa: o prompt perto da posicao REAL do snapshot.
    local prompt = nearestPrompt(egg.pos)
    if prompt and type(fireproximityprompt) == "function" then
        pcall(function() prompt.HoldDuration = 0 end)
        local worked, reason = pcall(function() fireproximityprompt(prompt, 1) end)
        if worked then return nil, "prompt acionado; aguardando confirmacao" end
        return false, tostring(reason)
    end
    return false, "coleta recusada: " .. tostring(detail or response or (ok and "sem resposta" or "remote indisponivel"))
end
local function waitCarry(accepted, token, previousVersion)
    local deadline = os.clock() + 1.5
    while S.alive and token == S.generation and os.clock() < deadline do
        if S.carryVersion > previousVersion and S.carrying then return true end
        task.wait(0.07)
    end
    if S.carryVersion > previousVersion then return S.carrying == true end
    -- Sem evento NOVO: usa confirmacao da RemoteFunction.
    return accepted == true
end
local function runCycle(token)
    S.attempts = S.attempts + 1
    local list, reason = candidates()
    if reason then return false, "Nao foi possivel consultar ovos reais: " .. reason end
    if #list == 0 then return false, "Nenhum ovo real com valor conhecido disponivel" end
    local egg = list[1]
    notify("Melhor ovo: " .. egg.name .. " [" .. numberShort(egg.value) .. "/s] " .. egg.area)
    local ok, why = teleport(egg.pos, 11)
    if not ok then return false, "TP ate o ovo: " .. tostring(why) end
    if not S.alive or token ~= S.generation then return false, "interrompido" end
    task.wait(0.12)
    notify("Pegando instantaneamente " .. egg.name)
    local previousVersion = S.carryVersion
    local accepted, info = requestInstantPickup(egg)
    if accepted == false then
        S.ignored[egg.uid] = true
        return false, tostring(info)
    end
    if not waitCarry(accepted, token, previousVersion) then
        S.ignored[egg.uid] = true
        return false, "Coleta nao confirmada; nao vou fingir que pegou"
    end
    S.accepted = S.accepted + 1
    notify("Ovo coletado: fugindo para o local seguro")
    if not S.safe then return false, "Local seguro perdido" end
    local escaped, escapeError = teleport(S.safe.Position, 12)
    if not escaped then return false, "Fuga falhou: " .. tostring(escapeError) end
    S.escaped = S.escaped + 1
    if S.safeType == "manual" then
        notify("Fuga realizada. Local manual pode NAO depositar o ovo; farm pausado")
        return true, "pausar"
    end
    task.wait(1.1)
    if S.carryingKnown and S.carrying then
        notify("Ainda carregando: chegada ao PetArea nao confirmou deposito")
        return true, "pausar"
    end
    notify("Retornou a area segura; pronto para novo ciclo")
    return true, "continuar"
end
local function setRunning(on)
    S.generation = S.generation + 1
    S.running = on
    if not on then notify("Auto farm parado") return end
    if S.busy then S.running = false notify("Aguarde o ciclo manual terminar") return end
    if not S.safe then
        local ok, why = detectOwnPlot()
        if not ok then S.running = false fail("Marque um local seguro primeiro: " .. tostring(why)) return end
    end
    local generation = S.generation
    S.ignored = {}
    notify("Auto farm ligado | priorizando valor real do ovo")
    task.spawn(function()
        while S.alive and S.running and generation == S.generation do
            local ran, worked, nextAction = pcall(runCycle, generation)
            if not ran then
                S.running = false
                fail("Erro Lua no ciclo: " .. tostring(worked))
                break
            end
            if not worked then
                fail(tostring(nextAction))
                -- Erro de rede/teleporte: parar em vez de repetir TP e arriscar a conta.
                if tostring(nextAction):find("TP") or tostring(nextAction):find("snapshot")
                    or tostring(nextAction):find("consultar") then
                    S.running = false
                    break
                end
            elseif nextAction == "pausar" then
                S.running = false
                break
            else
                S.ignored = {}
            end
            task.wait(0.85)
        end
        S.running = false
    end)
end
local function diagnostics()
    local list, reason = candidates()
    local lines = {
        "STEAL AN EGG V2 - DIAGNOSTICO",
        "PlaceId=" .. tostring(game.PlaceId),
        "AssetsCatalog=" .. tostring((function() local n=0 for _ in pairs(S.catalog) do n=n+1 end return n end)()),
        "Snapshot=" .. tostring(remote(SNAPSHOT, "RemoteFunction") and "OK" or "AUSENTE"),
        "CarryRemote=" .. tostring(remote(CARRY, "RemoteFunction") and "OK" or "AUSENTE"),
        "OvosReais=" .. tostring(#list),
        "LocalSeguro=" .. tostring(S.safeType or "nao marcado"),
        "CapturasConfirmadas=" .. tostring(S.accepted),
        "FugasRealizadas=" .. tostring(S.escaped),
        "CarryEvent=" .. tostring(S.carryingKnown),
        "UltimoErro=" .. tostring(S.lastError),
        "SnapshotErro=" .. tostring(reason or "nenhum"),
    }
    for i = 1, math.min(#list, 12) do
        local e = list[i]
        lines[#lines + 1] = string.format("%d: %s | categoria=%s | area=%s | renda=%.2f | distancia=%.0f | Uid=%s",
            i, e.name, e.category, e.area, e.value, e.dist, e.uid)
    end
    local report = table.concat(lines, "\n")
    print(report)
    if type(setclipboard) == "function" then
        local ok = pcall(setclipboard, report)
        notify(ok and "Diagnostico copiado" or "Diagnostico no console")
    else notify("Diagnostico no console (sem clipboard)") end
end

local function listenCarry()
    local names = { "Eggs: AreaEggCarryState", "RE/EggWorld/FieldEggCarryState",
        "RE/EggWorld/AreaEggCarryState" }
    local obj = remote(names, "RemoteEvent")
    if not obj then
        local pkg = RS:FindFirstChild("Packages")
        local net = (pkg and pkg:FindFirstChild("Networking")) or RS:FindFirstChild("Network")
        if net then
            for _, d in ipairs(net:GetDescendants()) do
                if d:IsA("RemoteEvent") then
                    local n = string.lower(d.Name)
                    if n:find("carry", 1, true) and n:find("state", 1, true) then
                        obj = d
                        break
                    end
                end
            end
        end
    end
    if obj then
        bind(obj.OnClientEvent, function(state)
            if type(state) == "table" and state.IsCarrying ~= nil then
                S.carrying = state.IsCarrying == true
                S.carryingKnown = true
                S.carryVersion = S.carryVersion + 1
            end
        end)
    end
end
local function uiButton(parent, text, action)
    local b = Instance.new("TextButton")
    b.Size = UDim2.new(1, -12, 0, 41)
    b.BackgroundColor3 = Color3.fromRGB(37, 79, 130)
    b.TextColor3 = Color3.fromRGB(255,255,255)
    b.Font = Enum.Font.GothamSemibold
    b.TextSize = 13
    b.Text = text
    b.Parent = parent
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 8)
    corner.Parent = b
    bind(b.Activated, action)
    return b
end
local function createUI()
    gui = Instance.new("ScreenGui")
    gui.Name = "StealAnEgg_FarmV2"
    gui.ResetOnSpawn = false
    gui.DisplayOrder = 90
    gui.Parent = LP:WaitForChild("PlayerGui")
    local toggle = uiButton(gui, "🥚 AUTO FARM V2", function()
        panel.Visible = not panel.Visible
    end)
    toggle.Size = UDim2.fromOffset(130, 42)
    toggle.Position = UDim2.fromOffset(10, 70)
    panel = Instance.new("Frame")
    panel.Size = UDim2.fromOffset(326, 452)
    panel.Position = UDim2.new(0.5, -163, 0.5, -226)
    panel.BackgroundColor3 = Color3.fromRGB(18, 29, 46)
    panel.Parent = gui
    local round = Instance.new("UICorner")
    round.CornerRadius = UDim.new(0, 12)
    round.Parent = panel
    local top = Instance.new("TextButton")
    top.Size = UDim2.new(1, 0, 0, 38)
    top.BackgroundColor3 = Color3.fromRGB(29, 48, 73)
    top.Text = "STEAL AN EGG | AUTO FARM V2"
    top.Font = Enum.Font.GothamBold
    top.TextColor3 = Color3.new(1,1,1)
    top.TextSize = 13
    top.Parent = panel
    local scroll = Instance.new("ScrollingFrame")
    scroll.Position = UDim2.fromOffset(6, 44)
    scroll.Size = UDim2.new(1, -12, 1, -50)
    scroll.BackgroundTransparency = 1
    scroll.ScrollBarThickness = 3
    scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
    scroll.CanvasSize = UDim2.new()
    scroll.Parent = panel
    local layout = Instance.new("UIListLayout")
    layout.Padding = UDim.new(0, 6)
    layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
    layout.Parent = scroll
    info = Instance.new("TextLabel")
    info.Size = UDim2.new(1, -10, 0, 115)
    info.BackgroundTransparency = 1
    info.Font = Enum.Font.Code
    info.TextSize = 12
    info.TextWrapped = true
    info.TextXAlignment = Enum.TextXAlignment.Left
    info.TextYAlignment = Enum.TextYAlignment.Top
    info.TextColor3 = Color3.fromRGB(239, 230, 193)
    info.Parent = scroll
    farmButton = uiButton(scroll, "AUTO FARM: OFF", function()
        if S.running then setRunning(false) else setRunning(true) end
    end)
    bestButton = uiButton(scroll, "PEGAR MELHOR OVO UMA VEZ", function()
        if S.running or S.busy then notify("Ja existe um ciclo em execucao") return end
        if not S.safe then
            local ok, why = detectOwnPlot()
            if not ok then fail("Defina local seguro: " .. tostring(why)) return end
        end
        S.busy = true
        S.generation = S.generation + 1
        local token = S.generation
        task.spawn(function()
            local ran, good, msg = pcall(runCycle, token)
            if not ran then fail("Erro Lua: " .. tostring(good))
            elseif not good then fail(tostring(msg)) end
            S.busy = false
        end)
    end)
    uiButton(scroll, "DETECTAR MINHA BASE SEGURA", function()
        local ok, why = detectOwnPlot()
        if not ok then fail(tostring(why)) end
    end)
    uiButton(scroll, "MARCAR LOCAL SEGURO AQUI", markSafe)
    uiButton(scroll, "TESTAR TP PARA LOCAL SEGURO", function()
        if S.running then notify("Desligue o farm antes do teste") return end
        if not S.safe then notify("Marque ou detecte um local seguro") return end
        task.spawn(function()
            local ok, why = teleport(S.safe.Position, 12)
            notify(ok and "Teste: TP alterou a posicao local" or "Teste falhou: " .. tostring(why))
        end)
    end)
    uiButton(scroll, "VERIFICAR MELHOR OVO", function()
        task.spawn(function()
            local list, reason = candidates()
            if #list > 0 then
                local e = list[1]
                notify("MELHOR: " .. e.name .. " | " .. numberShort(e.value) .. "/s | " .. e.area)
            else notify("Sem ovos validos: " .. tostring(reason or "sem spawn")) end
        end)
    end)
    uiButton(scroll, "DIAGNOSTICO / COPIAR", function() task.spawn(diagnostics) end)
    uiButton(scroll, "PARAR FARM", function() setRunning(false) end)
    uiButton(scroll, "ESCONDER MENU", function() panel.Visible = false end)
    -- Arraste pelo titulo (toque e mouse).
    local dragging, start, startingPos, dragInput = false, nil, nil, nil
    bind(top.InputBegan, function(input)
        if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = true
            dragInput = input
            start = input.Position
            startingPos = panel.Position
        end
    end)
    bind(UIS.InputChanged, function(input)
        if dragging and (input == dragInput or input.UserInputType == Enum.UserInputType.MouseMovement) then
            local delta = input.Position - start
            panel.Position = UDim2.new(startingPos.X.Scale, startingPos.X.Offset + delta.X,
                startingPos.Y.Scale, startingPos.Y.Offset + delta.Y)
        end
    end)
    bind(UIS.InputEnded, function(input)
        if input == dragInput or input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = false
        end
    end)
    task.spawn(function()
        while S.alive do
            local safeStr = S.safeType or "nao definido"
            info.Text = string.format("Farm: %s | Seguro: %s\nOvos: %d | Aceitos: %d | Fugas: %d\n%s%s",
                S.running and "ON" or "OFF", safeStr,
                #S.lastList, S.accepted, S.escaped,
                S.status, S.lastError ~= "" and ("\nErro: " .. S.lastError) or "")
            farmButton.Text = "AUTO FARM: " .. (S.running and "ON" or "OFF")
            task.wait(0.35)
        end
    end)
end
function S.Destroy()
    S.alive = false
    S.running = false
    S.generation = S.generation + 1
    for _, c in ipairs(S.connections) do pcall(function() c:Disconnect() end) end
    if gui then gui:Destroy() end
    if env.__SAE_FARM_V2 == S then env.__SAE_FARM_V2 = nil end
end
env.__SAE_FARM_V2 = S
loadDefinitions()
listenCarry()
createUI()
notify("V2 pronto. Snapshot real + coleta direta + fuga por TP.")
return S