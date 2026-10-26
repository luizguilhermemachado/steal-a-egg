-- STEAL AN EGG | DELTA ANDROID | HOTFIX LOADER
-- Mantem o script original no repositorio e aplica as correcoes em memoria.
-- Publique este arquivo com um NOVO nome no GitHub; nao substitua o arquivo remoto
-- que esta sendo baixado abaixo, para evitar recursao.

local SOURCE_URL = "https://raw.githubusercontent.com/luizguilhermemachado/steal-a-egg/main/StealAnEgg_Delta_Android.lua"
local WALK_SPEED = 5000 -- WalkSpeed padrao do Roblox costuma ser 16; 100 e muito mais rapido.

local okFetch, source = pcall(function()
    return game:HttpGet(SOURCE_URL)
end)
if not okFetch or type(source) ~= "string" or #source < 1000 then
    error("[SAE Hotfix] Nao foi possivel baixar o script original: " .. tostring(source))
end

local function replaceBetween(text, startToken, endToken, replacement)
    local first = string.find(text, startToken, 1, true)
    assert(first, "marcador inicial nao encontrado: " .. startToken)
    local afterFirst = first + #startToken
    local last = string.find(text, endToken, afterFirst, true)
    assert(last, "marcador final nao encontrado: " .. endToken)
    return string.sub(text, 1, first - 1) .. replacement .. string.sub(text, last)
end

local function replaceOnce(text, old, new)
    local first = string.find(text, old, 1, true)
    assert(first, "trecho nao encontrado: " .. old)
    return string.sub(text, 1, first - 1) .. new .. string.sub(text, first + #old)
end

-- Corrige a descoberta por metadados e aplica velocidade reforcada no cliente.
source = replaceBetween(source, "local function chr()", "local function norm(s)", [=[
local function chr()
    local char=LP.Character
    return char, char and char:FindFirstChild("HumanoidRootPart"), char and char:FindFirstChildOfClass("Humanoid")
end

local SAE_ORIGINAL_SPEEDS = setmetatable({}, {__mode="k"})
local SAE_WALK_SPEED = 100
local function applySAESpeed()
    local character=LP.Character
    local humanoid=character and character:FindFirstChildOfClass("Humanoid")
    if humanoid and humanoid.Health>0 then
        if SAE_ORIGINAL_SPEEDS[humanoid]==nil then
            SAE_ORIGINAL_SPEEDS[humanoid]=humanoid.WalkSpeed
        end
        if humanoid.WalkSpeed~=SAE_WALK_SPEED then
            pcall(function() humanoid.WalkSpeed=SAE_WALK_SPEED end)
        end
    end
end

task.spawn(function()
    while S.alive do
        applySAESpeed()
        task.wait(0.25)
    end
end)

]=])

source = replaceBetween(source, "local function getDef(name)", "local function refreshCatalog()", [=[
local function getDef(name)
    local data = RS:FindFirstChild("Data") or RS:FindFirstChild("Directory")
    local module = data and data:FindFirstChild("Assets")
    if not (module and module:IsA("ModuleScript")) then return nil end
    local ok, result = pcall(require, module)
    if not ok or type(result) ~= "table" then return nil end

    local directory = result.Directory or result
    local direct = directory[name]
    if direct then return direct end

    local wanted = norm(name)
    for key, def in pairs(directory) do
        if type(def) == "table" then
            local egg = type(def.Egg) == "table" and def.Egg or nil
            if norm(key) == wanted
                or norm(def.Name) == wanted
                or norm(def.DisplayName) == wanted
                or norm(egg and egg.DisplayName) == wanted then
                return def
            end
        elseif norm(key) == wanted then
            return def
        end
    end
    return nil
end

local function metadata(prompt)
    local name, rarity, value
    local node = prompt.Parent
    local count = 0
    local nameAttributes = {"EggName", "PetName", "Pet", "AssetName", "DisplayName", "Name"}

    while node and node ~= workspace and count < 8 do
        if not name then
            for _, key in ipairs(nameAttributes) do
                local attribute = node:GetAttribute(key)
                if (type(attribute) == "string" or type(attribute) == "number") and tostring(attribute) ~= "" then
                    name = tostring(attribute)
                    break
                end
            end
        end
        if not rarity then
            local attribute = node:GetAttribute("Rarity")
            if attribute ~= nil then rarity = tostring(attribute) end
        end
        node = node.Parent
        count += 1
    end

    if not name and prompt.ObjectText and prompt.ObjectText ~= "" then
        name = prompt.ObjectText
    end

    node = prompt.Parent
    count = 0
    while not name and node and node ~= workspace and count < 8 do
        local candidate = tostring(node.Name or "")
        local low = norm(candidate)
        local generic = low == "egg" or low == "ovo"
            or low == "carryareaegg" or low == "proximityprompt"
        if not generic and (low:find("egg", 1, true) or low:find("ovo", 1, true)) then
            name = candidate
        end
        node = node.Parent
        count += 1
    end
    name = name or "Ovo desconhecido"

    local def = getDef(name)
    if def then
        local eggDef = type(def.Egg) == "table" and def.Egg or nil
        rarity = rarity or tostring(def.Rarity or (eggDef and eggDef.Rarity) or "")
        value = tonumber(def.EarningRate or (eggDef and eggDef.EarningRate) or 0) or 0
        name = tostring((eggDef and eggDef.DisplayName) or def.DisplayName or name)
    end
    return name, rarity or "", value or 0
end

]=])

-- Junta prompts taggeados e encontrados pela varredura, em vez de usar a segunda
-- busca somente quando a primeira retorna zero. Exclui ovos do lobby/decoracoes.
source = replaceBetween(source, "local function getEggs()", "local function clearESP()", [=[
local function getEggs()
    local tagged = {}
    local source = {}

    local ok, items = pcall(function()
        return CS:GetTagged("CarryAreaEgg")
    end)
    if ok and type(items) == "table" then
        for _, obj in ipairs(items) do
            if obj:IsA("ProximityPrompt") and obj:IsDescendantOf(workspace) then
                tagged[obj] = true
                source[obj] = true
            end
        end
    end

    -- Descoberta complementar sempre executada, mesmo se houver prompts taggeados.
    for _, obj in ipairs(workspace:GetDescendants()) do
        if obj:IsA("ProximityPrompt") and obj:IsDescendantOf(workspace) then
            local node = obj.Parent
            local looksLikeEgg = false
            local depth = 0
            while node and node ~= workspace and depth < 8 do
                local low = norm(node.Name)
                if low:find("egg", 1, true) or low:find("ovo", 1, true) then
                    looksLikeEgg = true
                end
                for _, key in ipairs({"EggName", "PetName", "Pet", "Egg", "AssetName"}) do
                    if node:GetAttribute(key) ~= nil then
                        looksLikeEgg = true
                    end
                end
                node = node.Parent
                depth += 1
            end
            local promptText = norm((obj.Name or "") .. " " .. (obj.ActionText or "") .. " " .. (obj.ObjectText or ""))
            if promptText:find("egg", 1, true) or promptText:find("ovo", 1, true) then
                looksLikeEgg = true
            end
            if looksLikeEgg then source[obj] = true end
        end
    end

    local _, root = chr()
    local eggs = {}
    local rarityRanks = {
        common=1, uncommon=2, rare=3, epic=4, legendary=5,
        mythic=6, cosmic=7, divine=8, eternal=9, secret=10,
    }

    for prompt in pairs(source) do
        local path = ""
        local node = prompt.Parent
        local depth = 0
        local inLobby, decorative = false, false
        while node and node ~= workspace and depth < 10 do
            local part = norm(node.Name)
            path = path .. "/" .. part
            if part:find("lobby", 1, true) then inLobby = true end
            if part:find("preview", 1, true) or part:find("showcase", 1, true)
                or part:find("display", 1, true) or part:find("decorative", 1, true)
                or part:find("decoration", 1, true) then
                decorative = true
            end
            node = node.Parent
            depth += 1
        end

        if not decorative and not inLobby then
            local pos = promptPos(prompt)
            if pos then
                local name, rarity, value = metadata(prompt)
                if S.filter == "" or norm(name):find(norm(S.filter), 1, true)
                    or norm(rarity):find(norm(S.filter), 1, true) then
                    local rarityScore = 0
                    local rarityText = norm(rarity)
                    for key, rank in pairs(rarityRanks) do
                        if rarityText:find(key, 1, true) then
                            rarityScore = math.max(rarityScore, rank)
                        end
                    end
                    table.insert(eggs, {
                        prompt=prompt, pos=pos, name=name, rarity=rarity,
                        value=value, rarityScore=rarityScore,
                        dist=root and (root.Position-pos).Magnitude or math.huge,
                        tagged=tagged[prompt] == true, path=path,
                    })
                end
            end
        end
    end

    -- Melhor renda primeiro; raridade como desempate; distancia por ultimo.
    table.sort(eggs, function(a, b)
        if a.value ~= b.value then return a.value > b.value end
        if a.rarityScore ~= b.rarityScore then return a.rarityScore > b.rarityScore end
        return a.dist < b.dist
    end)

    S.eggs = eggs
    S.lastEggCount = #eggs
    return eggs
end

]=])

-- Faz a velocidade ser aplicada imediatamente durante a navegacao do Auto Farm.
source = replaceBetween(source, "local function walkTo(dest, token, radius)", "local function stopMove()", [=[
local function walkTo(dest, token, radius)
    radius=radius or 7
    local _, root, hum=chr()
    if not root or not hum then return false,"personagem indisponivel" end
    applySAESpeed()
    local started=os.clock()
    local points={dest}
    local ok, path=pcall(function()
        local p=PF:CreatePath({AgentRadius=2, AgentHeight=5, AgentCanJump=true, WaypointSpacing=6})
        p:ComputeAsync(root.Position, dest)
        return p
    end)
    if ok and path.Status==Enum.PathStatus.Success then
        points=path:GetWaypoints()
    end
    for _, waypoint in ipairs(points) do
        local p=(typeof(waypoint)=="Vector3") and waypoint or waypoint.Position
        local jumps=(typeof(waypoint)~="Vector3" and waypoint.Action==Enum.PathWaypointAction.Jump)
        if jumps then hum.Jump=true end
        applySAESpeed()
        hum:MoveTo(p)
        local wpStart=os.clock()
        while S.alive and token==S.token do
            _, root, hum=chr()
            if not root or not hum or hum.Health<=0 then return false,"personagem morto" end
            applySAESpeed()
            if (root.Position-p).Magnitude < 5 then break end
            if os.clock()-wpStart>9 or os.clock()-started>100 then
                return false,"caminho bloqueado/tempo excedido"
            end
            task.wait(0.1)
        end
        if not S.alive or token~=S.token then return false,"interrompido" end
    end
    _, root=chr()
    return root~=nil and (root.Position-dest).Magnitude<radius,
        "destino fora do alcance"
end

]=])

-- Melhora o diagnostico para confirmar renda, raridade, distancia e origem do prompt.
source = replaceOnce(source,
    'lines[#lines+1]=i..". "..eggs[i].name.."/"..eggs[i].rarity',
    'lines[#lines+1]=string.format("%d. %s | raridade=%s | renda=%s | distancia=%.1f | tag=%s | caminho=%s", i, eggs[i].name, eggs[i].rarity, tostring(eggs[i].value), eggs[i].dist, tostring(eggs[i].tagged), eggs[i].path or "?")'
)

-- Restaura a velocidade original quando o menu/script for destruido.
source = replaceOnce(source,
    'function S.Destroy()\n    S.alive=false',
    'function S.Destroy()\n    S.alive=false\n    for humanoid, originalSpeed in pairs(SAE_ORIGINAL_SPEEDS) do\n        if humanoid and humanoid.Parent then pcall(function() humanoid.WalkSpeed=originalSpeed end) end\n    end'
)

-- Mantem o valor configuravel no topo sincronizado com o codigo injetado.
source = replaceOnce(source, "local SAE_WALK_SPEED = 100", "local SAE_WALK_SPEED = " .. tostring(WALK_SPEED))

local compile, compileError = loadstring(source)
if not compile then
    error("[SAE Hotfix] O script modificado nao compilou; nenhum script foi iniciado: " .. tostring(compileError))
end
print("[SAE Hotfix] Correcao de ovos aplicada; WalkSpeed alvo = " .. tostring(WALK_SPEED))
compile()
