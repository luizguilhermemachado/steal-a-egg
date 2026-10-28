-- STEAL AN EGG | DELTA ANDROID V3.6 | 28/10/2026
-- FARM POR BOTAO: melhor ovo > caminhar > coletar > TP para primeira fase > andar ate zona segura.
-- TP AO PEGAR OVO: vigilante independente, ativado por padrao; funciona tambem ao pegar manualmente.
-- O farm NUNCA inicia sozinho ao carregar o script.
-- TP de fuga para a PRIMEIRA FASE (Map1/SAE_ZoneId=1), depois CAMINHADA curta ate zona segura.
-- FIX: ovos de compra / loja / zona segura nao entram no ranking nem ESP.
-- Botao para ignorar a localizacao do alvo incorreto caso nao haja metadados suficientes.
-- Arquivo independente: NAO baixa outro Lua, NAO altera WalkSpeed.
-- Recursos: ranking por renda/tamanho/mutacoes, Egg ESP, coleta direta,
-- teleporte experimental, depositar, colocar, abrir, equipar, vender com protecoes,
-- treinamento e diagnostico. Remotes podem mudar e o servidor pode recusar acoes.
-- Nao execute junto da V2 ou de outros auto farms.

if not game:IsLoaded() then game.Loaded:Wait() end
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local UIS = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local LP = Players.LocalPlayer
local env = ((type(getgenv) == "function") and getgenv()) or _G
for _, key in ipairs({"__SAE_DELTA_V3", "__SAE_FARM_V2"}) do
    if env[key] and type(env[key].Destroy) == "function" then pcall(env[key].Destroy) end
end

local C = {
    interval = 1.25, espRefresh = 3, espCount = 12,
    allowWarp = false, allowWalkFallback = true, autoReturn = true, warpStep = 24,
    escapeWalkFallback = false, escapeStageFirst = true, trySegmentedWarp = true,
    tryTweenEscape = false, stageWarpStep = 38, tryPrompt = true, stopAfterEscape = true,
    minSellValue = 100, keepBest = 13, maxEquip = 13,
    ignoreShops = true, requireGuardian = true, blockRadius = 22,
    protectMutated = true, autoSellArmed = false,
    autoPlace = false, autoHatch = false, autoEquip = false,
    autoSell = false, autoTrain = false, autoFarm = false, eggESP = false,
}
local S = {
    alive = true, busy = false, token = 0, status = "Pronto: farm DESLIGADO. TP automatico ao pegar ovo LIGADO.",
    error = "", source = {}, eggList = {}, petList = {}, inventory = {},
    plot = nil, pen = nil, origin = nil, treadmill = nil,
    safe = nil, safeMode = "nao definido", refuge = nil, refugeMode = "nao identificado",
    stagePoint = nil, stageMode = "nao detectada", stageManual = nil,
    lastStageWarp = "nao testado", lastStageWalk = "nao testado",
    pickupSignalAt = -1000, pickupSignalSource = "", escapeCompleted = false, currentTarget = nil, carrying = false,
    carryingKnown = false, carryVersion = 0,
    returnPending = false, returning = false, manualReturnQueued = false, lastReturnAttempt = -1000,
    escapeRequested = false, escapeRequestedAt = -1000, escapeSource = "",
    lastCarrySeenAt = -1000, lastCarryAbsentAt = -1000, pendingEscapeReason = "",
    carryReady = false, carryAbsentSince = nil, carryPresentSince = nil,
    autoReturnAttempted = false, carryStateStable = false,
    pickupSignalWasManual = false,
    lastCarrySource = "nao detectado", lastReturnOutcome = "nao testado",
    attempts = 0, grabbed = 0, deposited = 0, failed = 0,
    locked = {}, remoteCache = {}, inflight = {},
    connections = {}, esp = {}, logs = {},
    blockedSpots = {}, rejectedEggs = {}, scanCount = 0,
    worldMarkers = {safe = {}, shops = {}, at = -1000},
}
local UI = {buttons = {}, indicators = {}, pages = {}, fields = {}}
local W = {}
local services = {
    snapshot = {"RF/EggWorld/AskFieldEggSnapshot", "Eggs: RequestAreaEggSnapshot"},
    carry = {"RF/EggWorld/AskFieldEggCarry", "Eggs: RequestAreaEggCarry"},
    ownedEggs = {"RF/EggWorld/AskLiveSnapshot", "Eggs: RequestRuntimeSnapshot"},
    place = {"RF/EggWorld/AskPlaceEgg", "Eggs: RequestPlaceEgg"},
    hatch = {"RF/EggWorld/AskHatch", "Eggs: RequestHatchEgg"},
    finish = {"RF/EggWorld/AskFinishHatch", "Eggs: RequestCompleteHatchEgg"},
    pets = {"RF/PenRoster/AskLiveSnapshot", "ActiveAssets: RequestRuntimeSnapshot"},
    wear = {"RF/PenRoster/AskWear", "ActiveAssets: RequestEquip"},
    limit = {"RF/PenRoster/AskWearLimit", "ActiveAssets: RequestEquipLimit"},
    sale = {"RF/PenRoster/AskSale", "ActiveAssets: RequestSell"},
    plot = {"RF/Homestead/AskState", "Plots: RequestState"},
    treadmill = {"RF/Treadmill/AskTierRaise", "Treadmills: RequestUpgrade"},
}

local function log(t)
    S.status = tostring(t)
    table.insert(S.logs, 1, os.date("%H:%M:%S") .. " " .. S.status)
    while #S.logs > 35 do table.remove(S.logs) end
    print("[StealAnEgg V3] " .. S.status)
end
local function fail(t)
    S.failed = S.failed + 1
    S.error = tostring(t)
    warn("[StealAnEgg V3] " .. S.error)
    log("ERRO: " .. S.error)
end
local function bind(signal, fn)
    local cn = signal:Connect(fn)
    table.insert(S.connections, cn)
    return cn
end
local function char()
    local c = LP.Character
    local root = c and c:FindFirstChild("HumanoidRootPart")
    local hum = c and c:FindFirstChildOfClass("Humanoid")
    if not (root and hum and hum.Health > 0) then return nil, nil end
    return root, hum
end
local function num(v)
    if type(v) == "number" then return v end
    return tonumber(v)
end
local function short(n)
    if type(n) ~= "number" then return "?" end
    for _, item in ipairs({{1e15,"Q"},{1e12,"T"},{1e9,"B"},{1e6,"M"},{1e3,"K"}}) do
        if math.abs(n) >= item[1] then return string.format("%.2f%s", n/item[1], item[2]) end
    end
    return string.format("%.1f", n)
end
local function keys(t)
    local a = {}
    if type(t) == "table" then
        for k in pairs(t) do table.insert(a, tostring(k)) end
    end
    table.sort(a)
    return table.concat(a, ", ")
end
local function rem(name)
    local saved = S.remoteCache[name]
    if saved and saved.Parent then return saved end
    local opts = services[name]
    if not opts then return nil end
    local pkg = RS:FindFirstChild("Packages")
    local net = pkg and pkg:FindFirstChild("Networking")
    local fallback = RS:FindFirstChild("Network")
    for _, root in ipairs({net or RS, fallback or RS}) do
        for _, x in ipairs(opts) do
            local node = root:FindFirstChild(x, true)
            if node and node:IsA("RemoteFunction") then
                S.remoteCache[name] = node
                return node
            end
        end
    end
    return nil
end
local function invoke(name, arg, timeout)
    local remote = rem(name)
    if not remote then return false, "RemoteFunction ausente: " .. tostring(name) end
    if S.inflight[name] then return false, "Consulta anterior ainda em andamento: " .. name end
    local completed, ok, a, b = false, false, nil, nil
    S.inflight[name] = true
    task.spawn(function()
        ok, a, b = pcall(function()
            if arg == nil then return remote:InvokeServer() end
            return remote:InvokeServer(arg)
        end)
        completed = true
        S.inflight[name] = nil
    end)
    local deadline = os.clock() + (timeout or 5)
    while S.alive and not completed and os.clock() < deadline do task.wait(.055) end
    if not completed then return false, "Tempo esgotado: " .. name end
    if not ok then return false, tostring(a) end
    return true, a, b
end
local function accepted(ok, response)
    if not ok or response == false then return false end
    if type(response) == "table" then
        if response.Success == false or response.Ok == false or response.Error then return false end
        if response.Success == true or response.Ok == true then return true end
    end
    return response == true and true or nil
end
local function records(response)
    if type(response) ~= "table" then return nil end
    local recs = response.Records or response.records or response.Items or response.Eggs or response.Pets
    if type(recs) == "table" then return recs end
    -- Retorno direto: apenas quando realmente contem registros estruturados.
    local count = 0
    for _, item in pairs(response) do
        if type(item) == "table" and (item.Uid or item.AssetCategory) then count = count + 1 end
    end
    return count > 0 and response or nil
end
local function dataModule(paths, field)
    for _, path in ipairs(paths) do
        local node = RS
        for part in string.gmatch(path, "[^.]+") do node = node and node:FindFirstChild(part) end
        if node and node:IsA("ModuleScript") then
            local ok, value = pcall(require, node)
            if ok and type(value) == "table" then
                local result = field and value[field] or value
                if type(result) == "table" then return result end
            end
        end
    end
    return {}
end
local defs = {Assets = {}, Mutations = {}, Guards = {}}
local function loadDefs()
    defs.Assets = dataModule({"Data.Assets", "Directory.Assets"}, "Directory")
    defs.Mutations = dataModule({"Shared.Modules.Mutations", "Library.Modules.Mutations"})
    defs.Guards = dataModule({"Data.Guards", "Directory.Guards"}, "Directory")
end
local mutFallback = {silver=1.2, golden=2.5, rainbow=3.5, bloom=1.25,
    spiritbloom=2.5, spectral=2.75, parasite=3, scrambled=2.75, fractured=2.75}
local function mutationsCount(muts)
    if type(muts) ~= "table" then return 0 end
    local n = 0
    for _, value in pairs(muts) do if value ~= false then n = n+1 end end
    return n
end
local function mutationMultiplier(muts)
    if type(muts) ~= "table" or next(muts) == nil then return 1, true end
    local fn = defs.Mutations.EarningsFor or defs.Mutations.GetTotalMutationsEarningMulti
    if type(fn) == "function" then
        local ok, m = pcall(fn, muts)
        if ok and type(m) == "number" and m > 0 then return m, true end
    end
    -- Estimativa quando modulo de mutacao nao esta disponivel; nao inventar bonus.
    local total, matched = 1, 0
    for k, v in pairs(muts) do
        local key = type(k) == "number" and tostring(v) or tostring(k)
        key = key:lower():gsub("[%s_%-]", "")
        if mutFallback[key] then total = total*mutFallback[key]; matched = matched+1 end
    end
    return total, matched == mutationsCount(muts)
end
local function valueFor(rec)
    local def = defs.Assets[rec.AssetCategory or rec.Category or rec.Type]
    if not def then return nil, false end
    local base = num(def.EarningRate or def.MoneyPerSecond)
    if not base then return nil, false end
    local scale = math.max(0.01, num(rec.AssetScale or rec.Scale) or 1)
    local multi, exact = mutationMultiplier(rec.Mutations)
    return base * (scale ^ 1.85) * multi, exact
end
local function displayName(rec)
    local cat = rec.AssetCategory or rec.Category or rec.Type
    local def = defs.Assets[cat]
    local egg = def and def.Egg
    return tostring((type(egg)=="table" and egg.DisplayName) or (def and def.DisplayName) or cat or "Desconhecido")
end
-- O snapshot de campo pode conter ovos sem coleta direta (loja / area segura).
-- Combinar evidencia de guardiao + geometria + metadados + exclusoes manuais.
-- Nao usar "Halloween" como criterio de exclusao: ovos reais do evento existem.
local function labelKey(s)
    return tostring(s or ""):lower():gsub("[%s_%-]", "")
end
local function shopField(rec)
    for _,name in ipairs({"IsShopEgg","IsStoreEgg","IsForSale","RequiresPurchase",
        "CanPurchase","IsPremiumEgg","IsRobuxEgg"}) do
        if rec[name] == true then return true, name end
    end
    for _,name in ipairs({"ProductId","DeveloperProductId","GamePassId",
        "ShopId","ShopItemId","RobuxCost","PriceRobux"}) do
        if rec[name] ~= nil and rec[name] ~= false and rec[name] ~= 0 and rec[name] ~= "" then
            return true,name
        end
    end
    local text=labelKey(rec.SourceType or rec.SpawnSource or rec.Source or rec.Origin)
    if text:find("shop",1,true) or text:find("store",1,true)
        or text:find("purchase",1,true) or text:find("robux",1,true) then
        return true,"Source="..text
    end
    return false,nil
end
local function shopPrompt(prompt)
    local text=labelKey((prompt.ActionText or "") .. " " .. (prompt.ObjectText or ""))
    for _,word in ipairs({"buy","purchase","comprar","loja","shop","store","robux",
        "product","adquirir","candycorn"}) do
        if text:find(word,1,true) then return true end
    end
    return false
end
local function worldPos(obj)
    local p=obj.Parent
    if not p then return nil end
    if p:IsA("BasePart") then return p.Position end
    if p:IsA("Attachment") then return p.WorldPosition end
    if p:IsA("Model") then
        local ok, pivot=pcall(function() return p:GetPivot() end)
        if ok then return pivot.Position end
    end
    local ancestor=p:FindFirstAncestorOfClass("Model")
    if ancestor then
        local ok, pivot=pcall(function() return ancestor:GetPivot() end)
        if ok then return pivot.Position end
    end
    return nil
end
local function markerContains(marker,pos)
    if not marker or not marker.Parent then return false end
    local cf,size
    if marker:IsA("BasePart") then
        cf=marker.CFrame;size=marker.Size
    elseif marker:IsA("Model") then
        local ok,c,s=pcall(function() return marker:GetBoundingBox() end)
        if not ok then return false end
        cf=c;size=s
    else return false end
    local q=cf:PointToObjectSpace(pos)
    return math.abs(q.X)<=size.X/2+2 and math.abs(q.Z)<=size.Z/2+2
        and math.abs(q.Y)<=size.Y/2+15
end
local function scanWorldMarkers()
    if os.clock()-S.worldMarkers.at<30 then return S.worldMarkers end
    local found={safe={},shops={},spawns={},at=os.clock()}
    for _,obj in ipairs(workspace:GetDescendants()) do
        if (obj:IsA("BasePart") or obj:IsA("Model")) then
            if obj:IsA("SpawnLocation") and obj.Enabled then
                table.insert(found.spawns,obj)
            end
            local k=labelKey(obj.Name)
            if k=="safezone" or k=="safearea" or k=="spawnsafezone"
                or k=="lobbysafezone" or k=="eventsafezone" or k=="protectedzone" then
                -- Evitar contar modelo e subparte de mesmo nome duplicadamente.
                table.insert(found.safe,obj)
            end
        elseif obj:IsA("ProximityPrompt") and shopPrompt(obj) then
            local p=worldPos(obj)
            if p then table.insert(found.shops,{point=p,desc=obj:GetFullName()}) end
        end
    end
    S.worldMarkers=found
    return found
end
local function guardedArea(areaId)
    if next(defs.Guards)==nil then return nil end -- Catalogo ausente: nao inventar.
    if defs.Guards[areaId] or defs.Guards[tostring(areaId)] then return true end
    for key,value in pairs(defs.Guards) do
        if tostring(key)==tostring(areaId) then return true end
        if type(value)=="table" and (tostring(value.AreaId or "")==tostring(areaId)
            or tostring(value.Id or "")==tostring(areaId)) then return true end
    end
    return false
end
local function eggReject(egg,p,markers)
    if C.ignoreShops then
        local isShop,field=shopField(egg)
        if isShop then return "metadado de compra: "..field end
        for _,point in ipairs(markers.safe) do
            if markerContains(point,p) then return "zona segura: "..point.Name end
        end
        -- Ovos de loja do lobby podem nao ter metadado de compra: excluir spawn imediato.
        for _,inst in ipairs(markers.spawns or {}) do
            if inst.Parent and (p-inst.Position).Magnitude<=32 then
                return "regiao de spawn / lobby"
            end
        end
        -- Prompts de compra estao na area da loja, nao no ninho do chefe.
        for _,mark in ipairs(markers.shops) do
            if (p-mark.point).Magnitude<=13 then return "proximo a prompt de compra" end
        end
    end
    for _,mark in ipairs(S.blockedSpots) do
        if (mark.position-p).Magnitude<=mark.radius then
            return "regiao bloqueada manualmente: "..mark.label
        end
    end
    if C.requireGuardian then
        local guard=guardedArea(egg.AreaId)
        if guard==false then return "sem guardiao cadastrado para area "..tostring(egg.AreaId) end
    end
    return nil
end
local function blockSpot(pos,label,radius)
    if typeof(pos)~="Vector3" then return false end
    table.insert(S.blockedSpots,{position=pos,label=label or "loja",radius=radius or C.blockRadius})
    S.eggList={}
    log("Bloqueada regiao ("..tostring(radius or C.blockRadius).." studs): "..tostring(label))
    return true
end

local function getField()
    local ok, data = invoke("snapshot", nil, 6)
    if not ok then return nil, data end
    local list = records(data)
    if not list then return nil, "Snapshot de campo sem formato reconhecido (" .. keys(data) .. ")" end
    local root = char()
    local out, rejected = {}, {}
    local markers=scanWorldMarkers()
    local count=0
    for _, egg in pairs(list) do
        if type(egg) == "table" and egg.Uid ~= nil and egg.AreaId ~= nil
            and typeof(egg.BottomCFrame) == "CFrame" then
            count=count+1
            local state=tostring(egg.State or "")
            local stateKey=state:lower()
            if stateKey=="slot" or stateKey=="available" or stateKey=="spawned"
                or stateKey=="field" then
                local p=egg.BottomCFrame.Position
                local reason=eggReject(egg,p,markers)
                local id=tostring(egg.Uid)
                if S.locked[id] and S.locked[id]>=os.clock() then
                    reason=reason or "aguardando nova tentativa de coleta"
                end
                if reason then
                    table.insert(rejected,{name=displayName(egg),area=tostring(egg.AreaId),
                        uid=id,reason=reason,position=p,fields=keys(egg)})
                else
                    local price,exact=valueFor(egg)
                    table.insert(out,{uid=id,rawUid=egg.Uid,rec=egg,
                        position=p,area=tostring(egg.AreaId),state=state,
                        category=tostring(egg.AssetCategory),name=displayName(egg),
                        price=price,exact=exact,scale=num(egg.AssetScale or egg.Scale) or 1,
                        muts=mutationsCount(egg.Mutations),
                        distance=root and (root.Position-p).Magnitude or math.huge})
                end
            else
                table.insert(rejected,{name=displayName(egg),area=tostring(egg.AreaId),
                    uid=tostring(egg.Uid),reason="estado nao coletavel: "..state,
                    position=egg.BottomCFrame.Position,fields=keys(egg)})
            end
        end
    end
    table.sort(out,function(a,b)
        if a.price and not b.price then return true end
        if b.price and not a.price then return false end
        if a.price and b.price and a.price ~= b.price then return a.price>b.price end
        if a.muts~=b.muts then return a.muts>b.muts end
        if a.scale~=b.scale then return a.scale>b.scale end
        return a.distance<b.distance
    end)
    S.scanCount=count
    S.rejectedEggs=rejected
    S.eggList=out
    return out
end
local function blockCurrentTarget()
    if #S.eggList==0 then
        local eggs,err=getField()
        if not eggs then return fail(tostring(err)) end
    end
    if #S.eggList==0 then return fail("Nenhum alvo no ranking para bloquear") end
    local top=S.eggList[1]
    if not blockSpot(top.position,top.name.." / "..top.area,C.blockRadius) then return false end
    local remaining,err=getField()
    if not remaining then return fail("Regiao bloqueada, mas consulta falhou: "..tostring(err)) end
    if remaining[1] then
        log("Alvo bloqueado. NOVO MELHOR: "..remaining[1].name.." | "..short(remaining[1].price).."/s | Area "..remaining[1].area)
    else
        log("Alvo bloqueado. Nenhum ovo elegivel no momento.")
    end
    return true
end


local function getOwned()
    local ok, response = invoke("ownedEggs", nil, 6)
    if not ok then return nil, response end
    local r = records(response)
    if not r then return nil, "Inventario: formato desconhecido (" .. keys(response) .. ")" end
    local out = {}
    for _, item in pairs(r) do
        if type(item) == "table" and item.Uid then table.insert(out, item) end
    end
    S.inventory = out
    return out
end
local function getPets()
    local ok, response = invoke("pets", nil, 6)
    if not ok then return nil, response end
    local r = records(response)
    if not r then return nil, "Pets: formato desconhecido (" .. keys(response) .. ")" end
    local out = {}
    for _, item in pairs(r) do
        if type(item) == "table" and item.Uid then
            local n = valueFor(item)
            -- Sempre utilizar rendimento replicado quando existir.
            n = num(item.MoneyPerSecond or item.EarningRate) or n
            table.insert(out, {rec=item, uid=item.Uid, price=n,
                name=displayName(item), muts=mutationsCount(item.Mutations),
                equipped=item.IsEquipped==true or item.Equipped==true or item.IsWearing==true,
                equipKnown=(item.IsEquipped~=nil or item.Equipped~=nil or item.IsWearing~=nil)})
        end
    end
    table.sort(out,function(a,b) return (a.price or -1) > (b.price or -1) end)
    S.petList = out
    return out
end
local function resolvePlot()
    local plots = workspace:FindFirstChild("Plots")
    if not plots then return false,"Plots nao carregados" end
    local ok, state = invoke("plot",nil,5)
    local found
    if ok and type(state)=="table" and type(state.OwnersBySlot)=="table" then
        for slot, owner in pairs(state.OwnersBySlot) do
            local ownerId = type(owner)=="table" and (owner.UserId or owner.Id) or owner
            if tonumber(ownerId)==LP.UserId then
                found=plots:FindFirstChild(tostring(slot)); break
            end
        end
    end
    if not found then
        for _, p in ipairs(plots:GetChildren()) do
            local sign=p:FindFirstChild("PlotSign",true)
            if sign then
                for _, t in ipairs(sign:GetDescendants()) do
                    if t:IsA("TextLabel") and (t.Text==LP.Name or t.Text==LP.DisplayName) then
                        found=p; break
                    end
                end
            end
            if found then break end
        end
    end
    if not found then return false,"Nao foi possivel identificar sua base" end
    local toUpdate=found:FindFirstChild("ToUpdate")
    S.plot=found
    S.origin=found:FindFirstChild("CenterPoint")
    S.pen=(toUpdate and toUpdate:FindFirstChild("PetArea")) or found:FindFirstChild("PetArea",true)
    S.treadmill=found:FindFirstChild("TreadmillBottom",true)
    if not (S.pen and S.pen:IsA("BasePart")) then return false,"PetArea nao encontrada" end
    if not (S.origin and S.origin:IsA("BasePart")) then return false,"CenterPoint nao encontrado" end
    S.safe=S.pen.Position + Vector3.new(0,2,0)
    S.safeMode="sua base"
    return true
end
local function markSafe()
    local root=char()
    if not root then return fail("Personagem indisponivel") end
    S.safe=root.Position
    S.safeMode="manual (sem deposito automatico)"
    log("Local seguro marcado. Em modo manual o farm pausa apos coletar.")
end
-- Refugio: primeiro uma zona explicitamente rotulada como segura, depois um SpawnLocation
-- do hub e, somente se nao houver essas referencias, a propria base. Nenhuma posicao fixa inventada.
local function refugePoint(part, yBase)
    local cf, size
    if part:IsA("BasePart") then cf, size = part.CFrame, part.Size
    elseif part:IsA("Model") then
        local ok, a, b = pcall(function() return part:GetBoundingBox() end)
        if not ok then return nil end
        cf, size = a, b
    else return nil end
    local p = cf.Position
    -- Evita usar o centro vertical de uma trigger gigante: alinha ao solo visivel.
    local origin = Vector3.new(p.X, math.max(p.Y+size.Y/2+15, yBase+60), p.Z)
    local rp = RaycastParams.new()
    rp.FilterType = Enum.RaycastFilterType.Exclude
    rp.FilterDescendantsInstances = LP.Character and {LP.Character,part} or {part}
    local hit = workspace:Raycast(origin, Vector3.new(0,-500,0), rp)
    local y = hit and (hit.Position.Y+3.5) or yBase+3
    return Vector3.new(p.X,y,p.Z)
end
local function selectRefuge()
    local root = char()
    if not root then return false,"Personagem indisponivel" end
    local y = root.Position.Y
    local markers = scanWorldMarkers()
    local candidates={}
    for _, item in ipairs(markers.safe) do
        if item.Parent then
            local p = refugePoint(item,y)
            if p then
                -- Jogador comecou dentro de zona marcada? Seu ponto inicial e mais confiavel.
                if markerContains(item,root.Position) then p=root.Position end
                table.insert(candidates,{position=p,mode="zona segura: "..item:GetFullName(),tier=1})
            end
        end
    end
    for _, item in ipairs(markers.spawns or {}) do
        if item.Parent and item.Enabled then
            local pos=item.Position+Vector3.new(0,item.Size.Y/2+3,0)
            table.insert(candidates,{position=pos,mode="SpawnLocation: "..item.Name,tier=2})
        end
    end
    -- A base NAO e uma zona segura garantida. Nao escolher uma base automaticamente
    -- se o mapa nao disponibilizar SafeZone ou SpawnLocation reconhecivel.
    table.sort(candidates,function(a,b)
        if a.tier~=b.tier then return a.tier<b.tier end
        return (a.position-root.Position).Magnitude<(b.position-root.Position).Magnitude
    end)
    if #candidates==0 then
        return false,"Nenhuma SafeZone/SpawnLocation confiavel. Use USAR MINHA POSICAO COMO REFUGIO na zona segura."
    end
    S.refuge = candidates[1].position
    S.refugeMode = candidates[1].mode
    log("Refugio escolhido: "..S.refugeMode)
    return true
end

-- Identifica a primeira fase pela GEOMETRIA REAL replicada no cliente.
-- Preferir piso Map1 / zona com SAE_ZoneId=1; nao inferir coordenadas fixas da internet.
local function firstStagePart()
    local best, score = nil, -math.huge
    for _,obj in ipairs(workspace:GetDescendants()) do
        if obj:IsA("BasePart") and obj.Size.X >= 30 and obj.Size.Z >= 25
            and obj.Size.Y <= 45 then
            local name=labelKey(obj.Name)
            local id=obj:GetAttribute("SAE_ZoneId") or obj:GetAttribute("ZoneId")
                or obj:GetAttribute("AreaId")
            local scoreNow=nil
            if name=="map1" then scoreNow=120
            elseif tostring(id)=="1" then scoreNow=90
            elseif name=="forest" or name=="floresta" or name=="firstzone"
                or name=="zone1" or name=="area1" then scoreNow=75 end
            if scoreNow then
                -- Piso grande e plano costuma ser referencia mais confiavel que ornamento.
                scoreNow=scoreNow + math.min(20, math.sqrt(obj.Size.X*obj.Size.Z)/15)
                if scoreNow>score then best,score=obj,scoreNow end
            end
        end
    end
    return best
end
local function stageSurfacePoint(part, safePos)
    local sz=part.Size
    local cf=part.CFrame
    local localSafe=cf:PointToObjectSpace(safePos)
    -- Ponto dentro do piso, proximo da borda voltada para a SafeZone.
    local pad=math.min(9,sz.X/5,sz.Z/5)
    local x=math.clamp(localSafe.X,-sz.X/2+pad,sz.X/2-pad)
    local z=math.clamp(localSafe.Z,-sz.Z/2+pad,sz.Z/2-pad)
    local guessed=cf:PointToWorldSpace(Vector3.new(x,sz.Y/2+5,z))
    local params=RaycastParams.new()
    params.FilterType=Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances=LP.Character and {LP.Character} or {}
    local hit=workspace:Raycast(guessed+Vector3.new(0,24,0),Vector3.new(0,-80,0),params)
    return Vector3.new(guessed.X,hit and hit.Position.Y+3.4 or guessed.Y,guessed.Z)
end
local function selectFirstStage()
    if S.stageManual and typeof(S.stageManual)=="Vector3" then
        S.stagePoint=S.stageManual
        S.stageMode="PRIMEIRA FASE MARCADA MANUALMENTE"
        return true
    end
    if not S.refuge then
        local ok,why=selectRefuge()
        if not ok then return false,why end
    end
    local first=firstStagePart()
    if not first then
        return false,"Map1/SAE_ZoneId=1 nao encontrado. Va a primeira fase e aperte MARCAR PRIMEIRA FASE."
    end
    S.stagePoint=stageSurfacePoint(first,S.refuge)
    S.stageMode="primeira fase: "..first:GetFullName()
    return true
end

local carryEvidence -- detector definido abaixo; usado para interromper caminhada quando o ovo for pego
local function moveWalk(pos, timeout, token, ignoreCarry)
    local root, hum=char()
    if not root then return false,"Sem personagem" end
    local deadline=os.clock()+(timeout or 20)
    local last=0
    while S.alive and (token==nil or token==S.token) and os.clock()<deadline do
        root, hum=char()
        if not root then return false,"Personagem morreu" end
        if not ignoreCarry and carryEvidence then
            local found = carryEvidence()
            if found then return false,"OVO_CARREGADO" end
        end
        if (root.Position-pos).Magnitude<=8 then return true,"caminhada" end
        if os.clock()-last>.8 then hum:MoveTo(pos); last=os.clock() end
        task.wait(.15)
    end
    return false,"Caminhada nao chegou ao destino"
end
local function warpTo(pos, token)
    local root=char()
    if not root then return false,"Sem personagem" end
    if typeof(pos)~="Vector3" then return false,"Posicao invalida" end
    local start=root.Position
    local delta=pos-start
    -- Tentativa de TP direto; pode ser revertido / rejeitado pelo servidor.
    local ok,err=pcall(function()
        root.CFrame=CFrame.new(pos+Vector3.new(0,3,0))
        root.AssemblyLinearVelocity=Vector3.zero
    end)
    if not ok then return false,tostring(err) end
    task.wait(.45)
    root=char()
    if not root then return false,"Personagem morreu apos TP" end
    local expected=pos+Vector3.new(0,3,0)
    if (root.Position-expected).Magnitude<=11 then return true,"TP local (validacao provisoria)" end
    if (root.Position-start).Magnitude<2 and delta.Magnitude>12 then
        return false,"TP nao saiu do lugar / revertido"
    end
    return false,"TP rejeitado pelo servidor"
end
-- Alternativa experimental: deslocamentos menores no lugar do grande salto.
-- Usa a mesma propriedade fisica CFrame. NAO contorna validacao de carry do servidor.
local function warpBySteps(pos, token)
    local root=char()
    if not root then return false,"Sem personagem" end
    if typeof(pos)~="Vector3" then return false,"Destino invalido" end
    local start=root.Position
    local distance=(start-pos).Magnitude
    local step=math.clamp(C.stageWarpStep or 22,10,48)
    local hops=math.ceil(distance/step)
    if hops>130 then return false,"Distancia muito grande para TP por etapas ("..hops.." saltos)" end
    if hops==0 then return true,"Ja chegou" end
    for i=1,hops do
        if not S.alive or (token and token~=S.token) then return false,"Cancelado" end
        root=char()
        if not root then return false,"Personagem perdido durante TP em etapas" end
        local remaining=pos-root.Position
        local n=remaining.Magnitude
        if n<=8 then break end
        local nextP=root.Position+remaining.Unit*math.min(step,n)
        local ok,err=pcall(function()
            root.CFrame=CFrame.new(nextP+Vector3.new(0,2,0))
            root.AssemblyLinearVelocity=Vector3.zero
        end)
        if not ok then return false,"Erro CFrame por etapas: "..tostring(err) end
        task.wait(.08)
        root=char()
        if not root then return false,"Morreu ao tentar TP em etapas" end
        if (root.Position-nextP).Magnitude>15 then
            return false,"Servidor reverteu etapa "..i.."/"..hops
        end
    end
    task.wait(.8)
    root=char()
    if not root then return false,"Personagem indisponivel apos etapas" end
    if (root.Position-pos).Magnitude<=12 then
        return true,"TP por etapas (posicao local; ovo nao confirmado)"
    end
    return false,"TP por etapas nao chegou ao destino / rollback"
end

-- Metodo adicional EXCLUSIVAMENTE experimental: Tween linear em trajetos curtos.
-- Nao ancora o personagem, nao troca Humanoid e nao mexe em WalkSpeed.
-- So tentar se voce habilitar o toggle; o servidor pode recusar da mesma maneira.
local function warpByTween(pos,token)
    if typeof(pos)~="Vector3" then return false,"Destino invalido" end
    local startClock=os.clock()
    local maxTime=40
    for _=1,180 do
        if not S.alive or (token and token~=S.token) then return false,"Cancelado" end
        local root=char()
        if not root then return false,"Personagem indisponivel no Tween" end
        local dist=(pos-root.Position).Magnitude
        if dist<=10 then
            task.wait(.75)
            root=char()
            if root and (pos-root.Position).Magnitude<=14 then
                return true,"Tween chegou (localmente; ovo nao confirmado)"
            end
            return false,"Tween revertido pelo servidor"
        end
        if os.clock()-startClock>maxTime then return false,"Tween excedeu 40 segundos" end
        local step=math.min(34,dist)
        local nextPos=root.Position+(pos-root.Position).Unit*step
        local duration=math.max(.07,step/220)
        local ok,why=pcall(function()
            local tween=TweenService:Create(root,TweenInfo.new(duration,Enum.EasingStyle.Linear),
                {CFrame=CFrame.new(nextPos)})
            tween:Play()
            task.wait(duration+.035)
            tween:Cancel()
        end)
        if not ok then return false,"Tween erro: "..tostring(why) end
        root=char()
        if not root then return false,"Personagem morreu no Tween" end
        if (root.Position-nextPos).Magnitude>15 then
            return false,"Tween revertido / bloqueado (etapa)"
        end
    end
    return false,"Tween nao concluiu etapas"
end

local function moveTo(pos, token)
    if C.allowWarp then
        local ok,reason=warpTo(pos,token)
        if ok then return true,reason end
        if not C.allowWalkFallback then return false,reason end
        log("TP recusado. Tentando caminhar como alternativa.")
    end
    return moveWalk(pos,75,token)
end
local function pickUp(egg)
    local ok,a,b=invoke("carry",{Uid=egg.rawUid},5)
    if accepted(ok,a)==true then return true,"coleta aceita pelo remote" end
    if not ok then return false, tostring(a) end
    if a==false or (type(a)=="table" and (a.Success==false or a.Error)) then
        return false,"Servidor recusou coleta (distancia/Speed/chefe ou UID). "..tostring(b or (type(a)=="table" and a.Error) or a)
    end
    return nil,"Remote nao retornou confirmacao explicita"
end
local function listenCarry()
    local pkg=RS:FindFirstChild("Packages")
    local root=(pkg and pkg:FindFirstChild("Networking")) or RS:FindFirstChild("Network")
    if not root then return end
    local known={"RE/EggWorld/FieldEggCarryState","RE/EggWorld/AreaEggCarryState","Eggs: AreaEggCarryState"}
    local found
    for _, n in ipairs(known) do
        local r=root:FindFirstChild(n,true)
        if r and r:IsA("RemoteEvent") then found=r;break end
    end
    if found then
        bind(found.OnClientEvent,function(x)
            if type(x)=="table" and x.IsCarrying~=nil then
                S.carrying=x.IsCarrying==true
                S.carryingKnown=true
                S.carryVersion=S.carryVersion+1
            end
        end)
    end
end
local function hasId(items, id)
    if not items then return false end
    for _,it in ipairs(items) do if tostring(it.Uid)==tostring(id) then return true end end
    return false
end
local function newId(before, after)
    local old={}
    for _,item in ipairs(before or {}) do old[tostring(item.Uid)]=true end
    for _,item in ipairs(after or {}) do if not old[tostring(item.Uid)] then return item.Uid end end
    return nil
end
local function hasEggTool()
    local c=LP.Character
    local backpack=LP:FindFirstChildOfClass("Backpack")
    for _,f in ipairs({c,backpack}) do
        if f then
            for _, x in ipairs(f:GetChildren()) do
                if x:IsA("Tool") and x.Name:lower():find("egg",1,true) then return true end
            end
        end
    end
    return false
end
-- Os ovos carregados do campo podem ser modelos anexados ao Character,
-- atributos de estado ou um sinal de rede; NAO necessariamente sao Tool.
-- Tool em Backpack frequentemente aparece apenas depois do deposito.
local EGG_CARRY_FLAGS = {"IsCarryingEgg","CarryingEgg","HoldingEgg","HasFieldEgg"}
local EGG_CARRY_IDS = {"CarryingEggUid","CarriedEggUid","CarriedEggId","HeldEggUid","CarryingUid"}
local function attributeCarry(inst)
    if not inst then return false end
    for _, key in ipairs(EGG_CARRY_FLAGS) do
        local value=inst:GetAttribute(key)
        if value==true then return true,"atributo "..inst.Name.."."..key end
    end
    for _, key in ipairs(EGG_CARRY_IDS) do
        local value=inst:GetAttribute(key)
        if (type(value)=="string" and value~="" and value~="0")
            or (type(value)=="number" and value>0) then
            return true,"atributo UID "..inst.Name.."."..key
        end
    end
    return false
end
carryEvidence=function()
    -- Preferir sinais de carregamento efetivo. Um prompt disparado e so um indicio:
    -- pode ter sido recusado por velocidade, guardiao ou servidor.
    if S.carryingKnown and S.carrying then
        S.lastCarrySource="evento de carregamento"
        return true,S.lastCarrySource
    end
    local c=LP.Character
    for _, obj in ipairs({LP,c}) do
        local yes,reason=attributeCarry(obj)
        if yes then S.lastCarrySource=reason; return true,reason end
    end
    if c then
        -- Busca apenas modelos com nome de carregamento, nao qualquer ovo decorativo.
        for _, obj in ipairs(c:GetDescendants()) do
            if obj:IsA("Model") or obj:IsA("Tool") or obj:IsA("BasePart") then
                local k=obj.Name:lower():gsub("[%s_%-]", "")
                if k:find("carriedegg",1,true) or k:find("carryegg",1,true)
                    or k:find("holdegg",1,true) then
                    local reason="modelo de ovo no personagem: "..obj.Name
                    S.lastCarrySource=reason
                    return true,reason
                end
            end
        end
    end
    -- Leitura somente de CAMPOS, sem chamar metodos desconhecidos do modulo.
    local mod=RS:FindFirstChild("Client")
    mod=mod and mod:FindFirstChild("EggState")
    if mod and mod:IsA("ModuleScript") then
        local ok, data=pcall(require,mod)
        if ok and type(data)=="table" then
            for _, key in ipairs({"IsCarrying","IsCarryingEgg","CarryingEgg","CarriedEgg"}) do
                local val=rawget(data,key)
                if val==true then
                    S.lastCarrySource="EggState."..key
                    return true,S.lastCarrySource
                end
            end
        end
    end
    -- NUNCA usar PromptTriggered como prova de carregamento.
    -- Pode ser acionado por um prompt recusado pelo servidor ou por interacao decorativa.
    S.lastCarrySource="nao detectado"
    return false,S.lastCarrySource
end

-- Pedido de fuga tem prioridade sobre caminhar ate outro ovo.
-- Interrompe o movimento em andamento, mas deixa a operacao encerrar antes
-- de agendar o TP: evita que outra rotina altere a posicao simultaneamente.
local function requestEscape(source)
    if not C.autoReturn or not S.alive or S.returning or S.manualReturnQueued then return end
    if S.escapeCompleted or S.escapeRequested then return end
    if os.clock()-S.lastReturnAttempt < 5 then return end
    S.escapeRequested = true
    S.autoReturnAttempted = true -- uma tentativa automatica por retirada real de ovo
    S.escapeRequestedAt = os.clock()
    S.escapeSource = tostring(source or "ovo detectado")
    S.returnPending = true
    C.autoFarm = false
    if S.busy then
        S.token = S.token + 1 -- faz moveWalk parar na proxima verificacao
        local root,hum = char()
        if hum then pcall(function() hum:Move(Vector3.zero, false) end) end
    end
    log("OVO DETECTADO: priorizando TP para zona segura (" .. S.escapeSource .. ")")
end

-- Botao manual tambem chama esta funcao. O parametro force serve quando o
-- servidor aceitou a coleta, mas nao expoe nenhum estado observavel.
local function returnHome(token,force,before)
    if S.returning then return false,"Retorno ja esta em andamento" end
    local carrying,source=carryEvidence()
    if not force and not carrying then
        return false,"Nao detectei o ovo. Use SAIR PARA ZONA SEGURA (MANUAL) se estiver com ele."
    end
    S.returning=true
    S.autoReturnAttempted=true
    S.lastReturnAttempt=os.clock()
    S.returnPending=false
    local function finish(ok,msg)
        S.returning=false
        S.escapeRequested=false
        S.returnPending=false
        S.lastReturnOutcome=tostring(msg)
        if ok then log(msg) end
        return ok,msg
    end
    local root=char()
    if not root then return finish(false,"Personagem indisponivel") end
    if not S.refuge then
        local ok,reason=selectRefuge()
        if not ok then return finish(false,reason) end
    end
    local safe=S.refuge
    if (root.Position-safe).Magnitude<=12 then
        S.escapeCompleted=true
        C.autoFarm=false
        return finish(true,"Ja esta na zona segura. Entrega do ovo nao confirmada.")
    end
    if not C.escapeStageFirst then
        -- Modo legado selecionavel: TP direto ao refugio, sem caminhada longa involuntaria.
        local ok,why=warpTo(safe,token)
        if not ok then return finish(false,"TP direto recusado: "..tostring(why)) end
        task.wait(.6)
        root=char()
        if not root or (root.Position-safe).Magnitude>15 then
            return finish(false,"TP direto foi revertido pelo servidor")
        end
        S.escapeCompleted=true
        C.autoFarm=false
        return finish(true,"Perto da zona segura localmente. Confira o ovo.")
    end

    -- Novo modo: ir para a borda da PRIMEIRA FASE e completar o trajeto andando.
    local found,reason=selectFirstStage()
    if not found then return finish(false,reason) end
    local stage=S.stagePoint
    if (stage-safe).Magnitude>220 then
        return finish(false,"Primeira fase muito longe do refugio detectado ("..math.floor((stage-safe).Magnitude).." studs); verifique os marcadores")
    end
    if (root.Position-stage).Magnitude>14 then
        log("OVO DETECTADO: TP para PRIMEIRA FASE e depois caminhada curta. "..S.stageMode)
        local ok,why=warpTo(stage,token)
        if not ok and C.trySegmentedWarp then
            log("TP direto para primeira fase falhou ("..tostring(why).."). Tentando TP por etapas...")
            ok,why=warpBySteps(stage,token)
        end
        if not ok and C.tryTweenEscape then
            log("TPs falharam; tentando Tween experimental, sem alterar WalkSpeed...")
            ok,why=warpByTween(stage,token)
        end
        S.lastStageWarp=(ok and "ACEITO LOCALMENTE: " or "FALHOU: ")..tostring(why)
        if not ok then
            -- Nao comecar corrida ate a base a partir da ultima fase.
            return finish(false,"Nao foi possivel chegar a primeira fase por TP: "..tostring(why)..". Sem corrida longa automatica.")
        end
        task.wait(.55)
        root=char()
        if not root or (root.Position-stage).Magnitude>18 then
            S.lastStageWarp="ROLLBACK apos teleporte"
            return finish(false,"Servidor reverteu TP da primeira fase. Sem corrida longa automatica.")
        end
    else
        S.lastStageWarp="JA ESTAVA NA PRIMEIRA FASE"
    end
    -- Andar apenas do limite da primeira fase ate o refugio detectado.
    log("TP primeira fase OK localmente. ANDANDO "..math.floor((stage-safe).Magnitude).." studs ate zona segura")
    local okWalk,walkWhy=moveWalk(safe,38,token,true)
    S.lastStageWalk=(okWalk and "CHEGOU: " or "FALHOU: ")..tostring(walkWhy)
    if not okWalk then
        return finish(false,"TP inicial feito; caminhada final nao concluida: "..tostring(walkWhy))
    end
    S.escapeCompleted=true
    C.autoFarm=false
    S.pickupSignalAt=-1000
    return finish(true,"ZONA SEGURA ALCANCADA localmente via primeira fase. Confirme se o ovo foi mantido; deposito NAO confirmado.")
end

local function findCarryPrompt(egg)
    local CS=game:GetService("CollectionService")
    local all={}
    for _,obj in ipairs(CS:GetTagged("CarryAreaEgg")) do
        if obj:IsA("ProximityPrompt") then table.insert(all,obj)
        else
            for _,d in ipairs(obj:GetDescendants()) do
                if d:IsA("ProximityPrompt") then table.insert(all,d) end
            end
        end
    end
    -- Fallback: tag pode nao existir no cliente atual.
    if #all==0 then
        for _,d in ipairs(workspace:GetDescendants()) do
            if d:IsA("ProximityPrompt") then table.insert(all,d) end
        end
    end
    local chosen,dist=nil,math.huge
    for _,prompt in ipairs(all) do
        if prompt.Enabled and not shopPrompt(prompt) then
            local p=worldPos(prompt)
            if p then
                local d=(p-egg.position).Magnitude
                if d<dist and d<=15 then chosen,dist=prompt,d end
            end
        end
    end
    return chosen
end
local function collectCycle(token)
    if carryEvidence() then return returnHome(token,false) end
    S.attempts=S.attempts+1
    local eggs,e=getField()
    if not eggs then return false,"Consulta de ovos: "..tostring(e) end
    if #eggs==0 then return false,"Nenhum ovo do chefao elegivel; confira o diagnostico" end
    local target=eggs[1]
    S.currentTarget=target
    if not S.refuge then
        local ok,reason=selectRefuge()
        if not ok then return false,reason end
    end
    log("MELHOR OVO: "..target.name.." | "..short(target.price).."/s | indo ANDANDO")
    local before=getOwned() -- apenas antes de coletar; nao bloquear fuga depois
    local reached,reason=moveWalk(target.position,90,token)
    if not reached then
        if reason=="OVO_CARREGADO" then return returnHome(token,false,before) end
        return false,"Nao cheguei ao ovo: "..tostring(reason)
    end
    if token~=S.token then return false,"Cancelado" end
    if carryEvidence() then return returnHome(token,false,before) end
    -- Tentativa 1: chamada de coleta do proprio jogo ao chegar perto.
    local acceptedPickup,why=pickUp(target)
    if acceptedPickup==true then
        S.grabbed=S.grabbed+1
        return returnHome(token,true,before)
    end
    -- Tentativa 2: prompt real, nunca um prompt de compra do lobby.
    local prompt=C.tryPrompt and findCarryPrompt(target) or nil
    if prompt then
        log("Coleta direta sem confirmacao. Tentando prompt: "..prompt:GetFullName())
        if type(fireproximityprompt)=="function" then
            local ok=pcall(fireproximityprompt,prompt)
            if ok then
                S.pickupSignalAt=os.clock()
                S.pickupSignalSource="fireproximityprompt"
            end
        else
            local ok=pcall(function() prompt:InputHoldBegin() end)
            if ok then
                task.wait(math.max(.1,prompt.HoldDuration+.05))
                pcall(function() prompt:InputHoldEnd() end)
                S.pickupSignalAt=os.clock()
                S.pickupSignalSource="InputHoldBegin/End"
            end
        end
    end
    -- Nao aguardar segundos exposto ao chefao; basta um indicador de coleta.
    task.wait(.07)
    local carrying=carryEvidence()
    if carrying then
        S.grabbed=S.grabbed+1
        return returnHome(token,true,before)
    end
    S.locked[target.uid]=os.clock()+12
    return false,"Coleta nao confirmada (remote/prompt). "..tostring(why)
end

-- AUTOMACOES DE OVOS / PETS --
local function localPlacement(i)
    -- CFrame RELATIVO ao CenterPoint, nao posicao global do mapa.
    local x=((i-1)%3-1)*6
    local z=math.floor((i-1)/3)*6+4
    return CFrame.new(x,0,z)
end
local function placeOne()
    local items,reason=getOwned()
    if not items then return false,reason end
    if not S.plot then
        local ok,msg=resolvePlot()
        if not ok then return false,msg end
    end
    local already=0
    for _, rec in ipairs(items) do
        if rec.LocalCFrame or tostring(rec.State)=="Placed" or tostring(rec.State)=="Hatching"
            or tostring(rec.State)=="Incubating" then already=already+1 end
    end
    for _,rec in ipairs(items) do
        local state=tostring(rec.State or "")
        local notPlaced=not rec.LocalCFrame and (state=="Inventory" or state=="Owned"
            or state=="Stored" or state=="Unplaced" or state=="Carried")
        if notPlaced then
            local ok,response=invoke("place",{Uid=rec.Uid,LocalCFrame=localPlacement((already%12)+1)},5)
            if accepted(ok,response)==false then return false,"Colocar ovo recusado: "..tostring(response) end
            log("Solicitada colocacao do ovo "..tostring(rec.Uid))
            return true
        end
    end
    return false,"Sem ovo nao colocado com State reconhecido"
end
local function hatchOne()
    local items,reason=getOwned()
    if not items then return false,reason end
    for _,rec in ipairs(items) do
        local state=tostring(rec.State or "")
        local placed=rec.LocalCFrame~=nil or state=="Placed" or state=="Incubating"
        local ready=rec.IsReady==true or rec.HatchReady==true or state=="Ready"
            or state=="ReadyToHatch" or state=="HatchReady"
        local t=num(rec.HatchAt or rec.HatchReadyAt or rec.FinishAt)
        if placed and t and t>1e9 and t<=os.time() then ready=true end
        if ready then
            local ok,response=invoke("finish",rec.Uid,5)
            if accepted(ok,response)==false then return false,"Finalizar hatch recusado: "..tostring(response) end
            log("Finalizacao de hatch solicitada: "..tostring(rec.Uid))
            return true
        end
    end
    for _,rec in ipairs(items) do
        local state=tostring(rec.State or "")
        if (rec.LocalCFrame or state=="Placed") and not rec.HatchAt and not rec.HatchReadyAt
            and (state=="Placed" or state=="Idle") then
            local ok,response=invoke("hatch",rec.Uid,5)
            if accepted(ok,response)==false then return false,"Iniciar hatch recusado: "..tostring(response) end
            log("Inicio de hatch solicitado: "..tostring(rec.Uid))
            return true
        end
    end
    return false,"Sem ovo pronto ou colocado em formato reconhecido"
end
local function equipOne()
    local pets,why=getPets()
    if not pets then return false,why end
    if #pets>0 and not pets[1].equipKnown then
        return false,"Snapshot nao informa quais pets estao equipados; equipar em pausa"
    end
    local eq=0
    for _,p in ipairs(pets) do if p.equipped then eq=eq+1 end end
    local limit=C.maxEquip
    local ok,value=invoke("limit",nil,3)
    if ok then
        limit=math.min(limit,num(value) or (type(value)=="table" and num(value.Limit or value.Max)) or limit)
    end
    if eq>=limit then return false,"Limite de pets equipados atingido" end
    for _,p in ipairs(pets) do
        if p.price and not p.equipped then
            local good,result=invoke("wear",p.uid,5)
            if accepted(good,result)==false then return false,"Equipar recusado: "..tostring(result) end
            log("Solicitado equipar "..p.name.." ("..short(p.price).."/s)")
            return true
        end
    end
    return false,"Nenhum pet com valor conhecido disponivel"
end
local function sellOne()
    if not C.autoSellArmed then return false,"Venda bloqueada. Arme explicitamente no menu." end
    local pets,why=getPets()
    if not pets then return false,why end
    if #pets<=C.keepBest then return false,"Quantidade abaixo da reserva protegida" end
    for _,p in ipairs(pets) do
        if not p.equipKnown then
            return false,"Venda bloqueada: snapshot nao informa equipados"
        end
    end
    local protected={}
    for i=1,math.min(C.keepBest,#pets) do protected[tostring(pets[i].uid)]=true end
    -- Venda so e permitida para pets COM renda conhecida, sem mutacao e fora do top.
    for i=#pets,1,-1 do
        local p=pets[i]
        if not protected[tostring(p.uid)] and p.price and p.price<=C.minSellValue
            and (not C.protectMutated or p.muts==0) and not p.equipped then
            local ok,response=invoke("sale",p.uid,5)
            if accepted(ok,response)==false then return false,"Venda recusada: "..tostring(response) end
            log("Venda solicitada: "..p.name.." | "..short(p.price).."/s")
            return true
        end
    end
    return false,"Nenhum pet atende aos criterios de venda segura"
end
local function trainStep(token)
    if not S.treadmill then
        local ok,err=resolvePlot()
        if not ok then return false,err end
    end
    if not S.treadmill then return false,"TreadmillBottom nao encontrado" end
    local root=char()
    if not root then return false,"Personagem indisponivel" end
    if (root.Position-S.treadmill.Position).Magnitude>7 then
        local ok,reason=moveTo(S.treadmill.Position+Vector3.new(0,2.5,0),token)
        if not ok then return false,reason end
    end
    -- O jogo incrementa Speed ao ficar na esteira. Nao editar WalkSpeed.
    return true
end

local function stopFarm()
    C.autoFarm=false
    S.token=S.token+1
    log("Farm parado")
end
local function runExclusive(name,fn)
    if S.busy then log("Aguarde a operacao atual terminar") return end
    S.busy=true
    local token=S.token
    task.spawn(function()
        local ok,a,b=pcall(fn,token)
        if not ok then fail(name..": "..tostring(a))
        elseif a==false then log(name..": "..tostring(b)) end
        S.busy=false
    end)
end
local function loopFarm()
    if not C.autoFarm then return end
    C.autoTrain=false
    if not S.refuge then
        local ok,reason=selectRefuge()
        if not ok then C.autoFarm=false;fail(reason);return end
    end
    S.token=S.token+1
    local token=S.token
    task.spawn(function()
        while S.alive and C.autoFarm and S.token==token do
            if not S.busy and not S.returning and not S.returnPending then
                S.busy=true
                local ok,worked,reason=pcall(collectCycle,token)
                S.busy=false
                if not ok then fail("Farm Lua: "..tostring(worked)); C.autoFarm=false;break end
                if worked and S.escapeCompleted then
                    C.autoFarm=false
                    log("CICLO FINALIZADO. Chegou a zona segura; verifique o ovo antes de iniciar outro.")
                    break
                end
                if not worked then
                    fail(reason)
                    -- Falha de teleporte/Speed/estado do servidor: nao insistir em loop.
                    if tostring(reason):find("TP") or tostring(reason):find("morreu")
                        or tostring(reason):find("recusou") or tostring(reason):find("distancia")
                        or tostring(reason):find("Nao foi possivel") or tostring(reason):find("inventario") then
                        C.autoFarm=false;break
                    end
                elseif tostring(reason):find("PAUSAR") then
                    C.autoFarm=false;log(reason);break
                end
            end
            task.wait(C.interval)
        end
        C.autoFarm=false
    end)
end
local function startMaintenance()
    task.spawn(function()
        local last={place=0,hatch=0,equip=0,sale=0,train=0}
        while S.alive do
            if not S.busy then
                if C.autoTrain and not C.autoFarm and os.clock()-last.train>3 then
                    last.train=os.clock()
                    runExclusive("Treinamento",trainStep)
                elseif C.autoHatch and os.clock()-last.hatch>5 then
                    last.hatch=os.clock()
                    runExclusive("Auto hatch",hatchOne)
                elseif C.autoPlace and os.clock()-last.place>5 then
                    last.place=os.clock()
                    runExclusive("Auto colocar",placeOne)
                elseif C.autoEquip and os.clock()-last.equip>7 then
                    last.equip=os.clock()
                    runExclusive("Auto equipar",equipOne)
                elseif C.autoSell and C.autoSellArmed and os.clock()-last.sale>9 then
                    last.sale=os.clock()
                    runExclusive("Auto vender",sellOne)
                end
            end
            task.wait(1)
        end
    end)
end

-- EGG ESP: somente ovos validados pelo snapshot de campo.
local function clearESP()
    for _,obj in ipairs(S.esp) do pcall(function() obj:Destroy() end) end
    S.esp={}
end
local function drawESP(list)
    clearESP()
    for i=1,math.min(#list,C.espCount) do
        local egg=list[i]
        local peg=Instance.new("Part")
        peg.Name="SAE_V3_EggESP"
        peg.Size=Vector3.new(.2,.2,.2)
        peg.CFrame=CFrame.new(egg.position+Vector3.new(0,4,0))
        peg.Anchored=true;peg.CanCollide=false;peg.CanTouch=false
        peg.Transparency=1;peg.Parent=workspace
        local b=Instance.new("BillboardGui")
        b.Name="EggESP_Label"
        b.Size=UDim2.fromOffset(184,60)
        b.AlwaysOnTop=true;b.MaxDistance=4000
        b.StudsOffsetWorldSpace=Vector3.new(0,1,0)
        b.Adornee=peg;b.Parent=peg
        local t=Instance.new("TextLabel")
        t.Size=UDim2.fromScale(1,1)
        t.BackgroundColor3=Color3.fromRGB(15,23,37)
        t.BackgroundTransparency=.16
        t.TextColor3=Color3.fromRGB(239,246,255)
        t.TextStrokeTransparency=.45
        t.TextSize=11;t.Font=Enum.Font.GothamBold
        t.TextWrapped=true
        t.Text=egg.name.."\n$"..short(egg.price).."/s | "..string.format("%.2fx",egg.scale)
            .." | M:"..egg.muts.."\n"..math.floor(egg.distance).." studs"
        t.Parent=b
        Instance.new("UICorner",t).CornerRadius=UDim.new(0,7)
        table.insert(S.esp,peg)
    end
end
-- Vigilante independente: permanece ligado mesmo com o FARM desligado.
-- Ao detectar um ovo, interrompe tarefas concorrentes e tenta o TP prioritario.
-- Se o jogo nao replica carry, PromptTriggered funciona como INDICIO, nao prova.
local function startReturnWatcher()
    task.spawn(function()
        while S.alive do
            if C.autoReturn and not S.manualReturnQueued then
                local carrying,source=carryEvidence()
                local root=char()
                if carrying then
                    S.lastCarrySeenAt=os.clock()
                    S.carryAbsentSince=nil
                    if not S.carryPresentSince then S.carryPresentSince=os.clock() end
                    -- Nunca disparar na inicializacao se ja houver um sinal persistente.
                    -- Exigimos ter visto um estado SEM ovo antes de armar a automacao.
                    local stable=(os.clock()-S.carryPresentSince)>=.35
                    if stable and S.carryReady and not S.autoReturnAttempted then
                        S.carryStateStable=true
                        if not S.refuge and not S.returning then pcall(selectRefuge) end
                        local distance=(root and S.refuge)
                            and (root.Position-S.refuge).Magnitude or math.huge
                        if distance>16 and not S.escapeCompleted and not S.returning then
                            requestEscape(source)
                        end
                    end
                else
                    S.lastCarryAbsentAt=os.clock()
                    S.carryPresentSince=nil
                    if not S.carryAbsentSince then S.carryAbsentSince=os.clock() end
                    -- Exigir ausencia estavel, nao uma falha isolada de leitura,
                    -- antes de habilitar a proxima coleta.
                    if os.clock()-S.carryAbsentSince >= 1.0 then
                        S.carryReady=true
                        S.carryStateStable=false
                        S.autoReturnAttempted=false
                        if S.escapeCompleted and not S.returning then
                            S.escapeCompleted=false
                        end
                    end
                end
                if S.escapeRequested and not S.busy and not S.returning
                    and os.clock()-S.lastReturnAttempt>4 then
                    local recent = os.clock()-S.escapeRequestedAt<7
                    if recent then
                        -- O sinal permanece pendente ate returnHome finalizar,
                        -- impedindo que o vigilante agende dois retornos.
                        runExclusive("TP automatico ao pegar ovo",function(token)
                            return returnHome(token,true)
                        end)
                    else
                        S.escapeRequested=false
                        S.returnPending=false
                        log("Sinal de ovo expirou: nao vou teleportar sem novo sinal")
                    end
                end
            elseif S.escapeRequested then
                S.escapeRequested=false
                S.returnPending=false
            end
            task.wait(.09)
        end
    end)
end

local function espLoop()
    task.spawn(function()
        while S.alive do
            if C.eggESP then
                if not S.busy and not S.inflight.snapshot then
                    local ok,list=pcall(getField)
                    if ok and list then drawESP(list) end
                end
            elseif #S.esp>0 then clearESP() end
            task.wait(C.espRefresh)
        end
    end)
end

local function diagnostic()
    local out={
        "STEAL AN EGG | V3.6 DIAGNOSTICO | "..os.date("%d/%m/%Y %H:%M"),
        "PlaceId="..tostring(game.PlaceId).." | PlaceVersion="..tostring(game.PlaceVersion),
        "Build esperado=107778070777162 | StreamingEnabled="..tostring(workspace.StreamingEnabled),
        "CatalogoAssets="..keys(defs.Assets):sub(1,150),
        "MutacoesModulo="..tostring(type(defs.Mutations.EarningsFor)),
        "Base="..tostring(S.plot and S.plot:GetFullName() or "NAO IDENTIFICADA"),
        "SafeBase="..S.safeMode.." | Refugio="..S.refugeMode.." | Destino="..tostring(S.refuge),
        "ModoFugaPrimeiraFase="..tostring(C.escapeStageFirst).." | TPporEtapas="..tostring(C.trySegmentedWarp).." | TweenExperimental="..tostring(C.tryTweenEscape),
        "Fase1="..S.stageMode.." | Ponto="..tostring(S.stagePoint),
        "UltimoTPFase1="..S.lastStageWarp.." | UltimaCaminhada="..S.lastStageWalk,
        "FarmAutomaticoNoLoader=NAO | FarmLigado="..tostring(C.autoFarm),
        "RetornoAoPegar="..tostring(C.autoReturn).." | FugaPendente="..tostring(S.escapeRequested).." | AndarSeFalhar="..tostring(C.escapeWalkFallback),
        "DetectorArmado="..tostring(S.carryReady).." | DeteccaoEstavel="..tostring(S.carryStateStable).." | FugaJaTentada="..tostring(S.autoReturnAttempted),
        "OrigemUltimaDeteccao="..tostring(S.escapeSource).." | UltimaVolta="..S.lastReturnOutcome,
        "OvoCarregado="..tostring(carryEvidence()).." | Fonte="..S.lastCarrySource,
        "Filtro de loja="..tostring(C.ignoreShops).." | Exigir area de chefao="..tostring(C.requireGuardian),
        "Catalogo de guardioes="..tostring((function() local n=0;for _ in pairs(defs.Guards) do n=n+1 end;return n end)()),
        "Bloqueios manuais="..#S.blockedSpots,
        "Tentativas="..S.attempts.." | ColetasAceitas="..S.grabbed.." | Depositos="..S.deposited,
    }
    for k in pairs(services) do
        local r=rem(k)
        table.insert(out,"Remote "..k.." = "..(r and (r.ClassName.." / "..r:GetFullName()) or "AUSENTE"))
    end
    local e,er=getField()
    table.insert(out,"Ovos elegiveis="..tostring(e and #e or "ERRO "..tostring(er))
        .." | Registros classificados="..tostring(S.scanCount)
        .." | Excluidos="..tostring(#S.rejectedEggs))
    table.insert(out,"Zonas seguras="..#S.worldMarkers.safe.." | Prompts de compra="..#S.worldMarkers.shops)
    for i=1,math.min(15,#S.rejectedEggs) do
        local r=S.rejectedEggs[i]
        table.insert(out,"IGNORADO "..r.name.." | Area="..r.area.." | Uid="..r.uid
            .." | Motivo="..r.reason.." | Pos="..tostring(r.position)
            .." | Campos="..r.fields:sub(1,240))
    end
    if e then
        for i=1,math.min(#e,10) do
            local x=e[i]
            table.insert(out,i.." "..x.name.." | "..short(x.price).."/s | Scale="..x.scale
                .." | Mut="..x.muts.." | Area="..x.area.." | Uid="..x.uid)
        end
    end
    local own,oe=getOwned()
    table.insert(out,"Ovos proprios="..tostring(own and #own or "ERRO "..tostring(oe)))
    if own and #own>0 then table.insert(out,"Campos ovo proprio: "..keys(own[1])) end
    local p,pe=getPets()
    table.insert(out,"Pets="..tostring(p and #p or "ERRO "..tostring(pe)))
    if p and #p>0 then table.insert(out,"Campos pet: "..keys(p[1].rec)) end
    local report=table.concat(out,"\n")
    print(report)
    if type(setclipboard)=="function" then
        local ok=pcall(setclipboard,report)
        log(ok and "Diagnostico copiado; envie para revisar remotes" or "Diagnostico no console")
    else log("Diagnostico no console (clipboard indisponivel)") end
end

-- UI: layout mobile, cabecalho fixo, abas, scroll e texto de estado.
local function make(class,parent,props)
    local object=Instance.new(class)
    for key,value in pairs(props or {}) do object[key]=value end
    object.Parent=parent
    return object
end
local COLORS={back=Color3.fromRGB(12,18,30), card=Color3.fromRGB(24,34,51),
    head=Color3.fromRGB(17,27,44), accent=Color3.fromRGB(63,128,232),
    enabled=Color3.fromRGB(20,123,98), text=Color3.fromRGB(235,241,250),
    muted=Color3.fromRGB(155,177,198), warn=Color3.fromRGB(175,82,72)}
local function round(o,r)
    make("UICorner",o,{CornerRadius=UDim.new(0,r or 9)})
end
local function label(parent,value,size,color,height)
    return make("TextLabel",parent,{Size=UDim2.new(1,-10,0,height or 28),
        Text=value,TextSize=size or 13,TextColor3=color or COLORS.text,
        TextXAlignment=Enum.TextXAlignment.Left,BackgroundTransparency=1,
        Font=Enum.Font.Gotham,TextWrapped=true})
end
local function pageSection(parent,txt)
    local l=label(parent,txt,12,COLORS.muted,28)
    l.Font=Enum.Font.GothamBold
    return l
end
local function button(parent,caption,func,color)
    local b=make("TextButton",parent,{Size=UDim2.new(1,-8,0,39),
        BackgroundColor3=color or COLORS.card,TextColor3=COLORS.text,
        Text=caption,TextSize=12,Font=Enum.Font.GothamSemibold,
        AutoButtonColor=true})
    round(b,8)
    bind(b.Activated,function()
        local ok,err=pcall(func)
        if not ok then fail("Botao: "..tostring(err)) end
    end)
    return b
end
local function toggle(parent,caption,key,onChange)
    local b=button(parent,caption.."  • OFF",function()
        C[key]=not C[key]
        if onChange then onChange(C[key]) end
    end)
    UI.buttons[key]={btn=b,caption=caption}
    return b
end
local function field(parent,text,starting,change)
    local f=make("Frame",parent,{Size=UDim2.new(1,-8,0,39),BackgroundColor3=COLORS.card})
    round(f,8)
    make("TextLabel",f,{Text=text,TextSize=12,Font=Enum.Font.Gotham,
        TextColor3=COLORS.text,TextXAlignment=Enum.TextXAlignment.Left,
        BackgroundTransparency=1,Position=UDim2.fromOffset(8,0),Size=UDim2.new(.62,-8,1,0)})
    local box=make("TextBox",f,{Text=tostring(starting),TextSize=13,
        ClearTextOnFocus=false,Font=Enum.Font.GothamBold,TextColor3=COLORS.text,
        BackgroundColor3=COLORS.head,Position=UDim2.new(.66,0,.12,0),
        Size=UDim2.new(.31,0,.76,0)})
    round(box,5)
    bind(box.FocusLost,function()
        local n=tonumber(box.Text)
        if not n then box.Text=tostring(starting);return end
        change(n);starting=n;box.Text=tostring(n)
    end)
end
local function buildUI()
    local parent=LP:WaitForChild("PlayerGui")
    local old=parent:FindFirstChild("SAE_Delta_V3")
    if old then old:Destroy() end
    local gui=make("ScreenGui",parent,{Name="SAE_Delta_V3",ResetOnSpawn=false,DisplayOrder=160})
    UI.gui=gui
    local opener=make("TextButton",gui,{Text="🥚 EGG V3.5",TextSize=13,Font=Enum.Font.GothamBold,
        TextColor3=Color3.new(1,1,1),BackgroundColor3=COLORS.accent,
        Size=UDim2.fromOffset(114,40),Position=UDim2.new(0,12,.16,0)})
    round(opener,11)
    local cam=workspace.CurrentCamera
    local screen=cam and cam.ViewportSize or Vector2.new(410,720)
    local width=math.max(282,math.min(395,screen.X-18))
    local height=math.max(360,math.min(570,screen.Y-26))
    local panel=make("Frame",gui,{Size=UDim2.fromOffset(width,height),
        Position=UDim2.new(.5,-width/2,.5,-height/2),BackgroundColor3=COLORS.back})
    round(panel,12)
    make("UIStroke",panel,{Color=Color3.fromRGB(49,70,98),Thickness=1})
    local head=make("Frame",panel,{Size=UDim2.new(1,0,0,75),BackgroundColor3=COLORS.head})
    round(head,11)
    label(head,"STEAL AN EGG  /  DELTA V3.5",15,COLORS.text,31).Position=UDim2.fromOffset(13,5)
    local meta=label(head,"FARM MANUAL  •  TP FASE 1  •  ANDAR ZONA SEGURA",10,COLORS.muted,23)
    meta.Position=UDim2.fromOffset(13,33)
    local close=make("TextButton",head,{Text="−",TextSize=25,Font=Enum.Font.GothamBold,
        TextColor3=COLORS.text,BackgroundTransparency=1,Size=UDim2.fromOffset(36,36),
        Position=UDim2.new(1,-42,0,0)})
    local stat=label(panel,"Verificando estado...",11,COLORS.muted,44)
    stat.Position=UDim2.fromOffset(13,79)
    stat.Size=UDim2.new(1,-26,0,43)
    UI.status=stat
    local tabs=make("Frame",panel,{Position=UDim2.fromOffset(8,124),
        Size=UDim2.new(1,-16,0,35),BackgroundTransparency=1})
    local tabLayout=make("UIListLayout",tabs,{FillDirection=Enum.FillDirection.Horizontal,
        HorizontalAlignment=Enum.HorizontalAlignment.Center,Padding=UDim.new(0,5)})
    local names={{"FARM","farm"},{"OVOS","eggs"},{"PETS","pets"},{"SISTEMA","system"}}
    for _,pair in ipairs(names) do
        local b=make("TextButton",tabs,{Text=pair[1],TextSize=10,Font=Enum.Font.GothamBold,
            TextColor3=COLORS.text,BackgroundColor3=COLORS.card,
            Size=UDim2.new(.25,-5,1,0)})
        round(b,7)
        UI.indicators[pair[2]]=b
        local scroll=make("ScrollingFrame",panel,{Position=UDim2.fromOffset(9,164),
            Size=UDim2.new(1,-18,1,-173),BackgroundTransparency=1,
            CanvasSize=UDim2.fromOffset(0,0),AutomaticCanvasSize=Enum.AutomaticSize.Y,
            ScrollBarThickness=3,Visible=false})
        make("UIPadding",scroll,{PaddingBottom=UDim.new(0,10)})
        make("UIListLayout",scroll,{Padding=UDim.new(0,7)})
        UI.pages[pair[2]]=scroll
        bind(b.Activated,function()
            for name,page in pairs(UI.pages) do
                page.Visible=name==pair[2]
                UI.indicators[name].BackgroundColor3=(name==pair[2]) and COLORS.accent or COLORS.card
            end
        end)
    end
    UI.pages.farm.Visible=true
    UI.indicators.farm.BackgroundColor3=COLORS.accent
    local farm=UI.pages.farm
    pageSection(farm,"AUTO FARM: INICIO APENAS PELO BOTAO")
    button(farm,"▶ INICIAR FARM: ANDAR > PEGAR > FUGIR",function()
        if S.busy then return log("Coleta ja em andamento") end
        S.escapeCompleted=false
        S.escapeRequested=false
        S.returnPending=false
        C.autoFarm=true
        log("Farm iniciado por voce: localizar > caminhar > coletar > fugir")
        loopFarm()
    end,COLORS.accent)
    button(farm,"■ PARAR FARM (TP AO PEGAR CONTINUA)",function()
        stopFarm()
    end,COLORS.warn)
    button(farm,"PEGAR MELHOR OVO (1 VEZ)",function() runExclusive("Coletar",collectCycle) end,COLORS.accent)
    button(farm,"VERIFICAR O MELHOR OVO",function() runExclusive("Ranking",function()
        local e,reason=getField()
        if e and e[1] then
            log(e[1].name.." | $"..short(e[1].price).."/s | Scale "..e[1].scale
                .." | "..e[1].muts.." mutacoes")
            return true
        end
        return false,reason or "Nenhum ovo reconhecido"
    end) end)
    pageSection(farm,"FILTROS: NINHOS DOS CHEFOES / SEM LOJA")
    toggle(farm,"EXCLUIR LOJAS / ZONAS SEGURAS","ignoreShops")
    toggle(farm,"SOMENTE AREAS COM CHEFAO","requireGuardian")
    button(farm,"BLOQUEAR OVO ATUAL DO RANKING",blockCurrentTarget,COLORS.warn)
    button(farm,"BLOQUEAR A REGIAO ONDE ESTOU",function()
        local root=char()
        if not root then return fail("Personagem indisponivel") end
        blockSpot(root.Position,"marcado pelo jogador",math.max(30,C.blockRadius))
    end)
    field(farm,"Raio de bloqueio (studs)",C.blockRadius,function(n)
        C.blockRadius=math.clamp(math.floor(n),5,100)
    end)
    button(farm,"DESFAZER ULTIMO BLOQUEIO",function()
        local last=table.remove(S.blockedSpots)
        if last then log("Bloqueio removido: "..last.label)
        else log("Nenhum bloqueio manual para remover") end
    end)
    pageSection(farm,"FUGA: PRIMEIRA FASE (TP) > ZONA SEGURA (ANDANDO)")
    toggle(farm,"FUGIR VIA PRIMEIRA FASE: TP + ANDAR", "escapeStageFirst")
    toggle(farm,"TP POR ETAPAS SE O DIRETO FALHAR", "trySegmentedWarp")
    toggle(farm,"TWEEN EXPERIMENTAL SE TP FALHAR (OFF)", "tryTweenEscape")
    button(farm,"DETECTAR PRIMEIRA FASE (MAP1)",function()
        runExclusive("Detectar fase 1",function()
            local ok,reason=selectFirstStage()
            if ok then log("Fase 1: "..S.stageMode.." | "..tostring(S.stagePoint)) end
            return ok,reason
        end)
    end)
    button(farm,"TESTAR TWEEN PARA PRIMEIRA FASE (SEM OVO)",function()
        runExclusive("Teste Tween fase 1",function(token)
            local ok,why=selectFirstStage()
            if not ok then return false,why end
            local success,reason=warpByTween(S.stagePoint,token)
            S.lastStageWarp=(success and "TWEEN TESTE OK LOCAL: " or "TWEEN TESTE FALHOU: ")..tostring(reason)
            return success,reason
        end)
    end)
    button(farm,"MARCAR PRIMEIRA FASE (ONDE ESTOU)",function()
        local root=char()
        if not root then return fail("Personagem indisponivel") end
        S.stageManual=root.Position
        S.stagePoint=root.Position
        S.stageMode="primeira fase marcada manualmente"
        log("Fase 1 marcada manualmente. Va para zona segura antes de testar TP.")
    end)
    button(farm,"TESTAR TP PRIMEIRA FASE (SEM OVO)",function()
        runExclusive("Teste primeira fase",function(token)
            local ok,why=selectFirstStage()
            if not ok then return false,why end
            local success,reason=warpTo(S.stagePoint,token)
            S.lastStageWarp=(success and "TESTE LOCAL OK: " or "TESTE FALHOU: ")..tostring(reason)
            return success,reason
        end)
    end)
    toggle(farm,"TP AUTOMATICO AO PEGAR OVO (INDEPENDENTE)","autoReturn",function(on)
        if not on then S.escapeRequested=false;S.returnPending=false end
        log(on and "TP automatico LIGADO: exige deteccao estavel; TP fase 1 + andar ate SafeZone" or
            "TP automatico DESLIGADO: o botao manual continua disponivel")
    end)
    toggle(farm,"TELEPORTE EM OUTRAS ROTINAS","allowWarp")
    -- Sem fallback de caminhada longa: se TP fase 1 falhar, PARAR.
    button(farm,"FUGIR VIA PRIMEIRA FASE (MANUAL)",function()
        if S.manualReturnQueued then log("Retorno manual ja solicitado");return end
        S.manualReturnQueued=true
        -- Interrompe caminhada/coleta automatica para que o botao funcione
        -- MESMO quando o Auto Farm ja esta ocupado com a ida.
        C.autoFarm=false
        S.escapeRequested=false
        S.returnPending=false
        S.token=S.token+1
        log("Retorno manual solicitado; interrompendo o movimento anterior...")
        task.spawn(function()
            local deadline=os.clock()+8
            while S.busy and S.alive and os.clock()<deadline do task.wait(.1) end
            if S.busy then
                log("Nao consegui parar a operacao anterior: tente novamente")
            elseif S.alive then
                runExclusive("Volta manual",function(token)
                    return returnHome(token,true)
                end)
            end
            S.manualReturnQueued=false
        end)
    end,COLORS.accent)
    button(farm,"VERIFICAR SE ESTOU COM O OVO",function()
        local yes,method=carryEvidence()
        log(yes and ("CARREGANDO ovo | "..method) or
            "Nenhum sinal de ovo. Se voce esta segurando, use VOLTAR MANUAL")
    end)
    button(farm,"DETECTAR REFUGIO AUTOMATICO",function()
        runExclusive("Base",function()
            return selectRefuge()
        end)
    end)
    button(farm,"USAR MINHA POSICAO COMO REFUGIO",function()
        local root=char()
        if not root then return fail("Sem personagem") end
        S.refuge=root.Position;S.refugeMode="posicao escolhida no jogo"
        log("Refugio alterado para posicao atual")
    end)
    button(farm,"TESTAR TP DIRETO PARA REFUGIO (SEM OVO)",function()
        runExclusive("Teste TP",function(token)
            if not S.refuge then
                local ok,err=selectRefuge();if not ok then return false,err end
            end
            return warpTo(S.refuge,token)
        end)
    end)
    pageSection(farm,"Importante: Speed e alcance podem ser validados pelo servidor.")

    local eggs=UI.pages.eggs
    pageSection(eggs,"OVOS DOS NINHOS  •  LOJA EXCLUIDA DO RANKING")
    toggle(eggs,"EGG ESP NO MAPA","eggESP",function(on) if not on then clearESP() end end)
    local ranking = label(eggs,"Ranking: use VERIFICAR MELHOR OVO na aba FARM ou ligue ESP",11,COLORS.text,92)
    ranking.TextYAlignment=Enum.TextYAlignment.Top
    ranking.BackgroundColor3=COLORS.card
    ranking.BackgroundTransparency=.13
    UI.ranking=ranking
    field(eggs,"Limite de ovos no ESP",C.espCount,function(n) C.espCount=math.clamp(math.floor(n),1,25) end)
    toggle(eggs,"AUTO COLOCAR OVOS","autoPlace")
    toggle(eggs,"AUTO HATCH","autoHatch")
    button(eggs,"COLOCAR UM OVO AGORA",function() runExclusive("Colocar",placeOne) end)
    button(eggs,"ABRIR / INICIAR UM OVO",function() runExclusive("Hatch",hatchOne) end)
    pageSection(eggs,"O auto hatch so atua em estados reconhecidos pelo snapshot.")

    local pets=UI.pages.pets
    pageSection(pets,"PETS  •  PRIORIZAR RENDA REAL")
    local petRanking=label(pets,"Top pets: aguardando consulta",11,COLORS.text,73)
    petRanking.TextYAlignment=Enum.TextYAlignment.Top
    petRanking.BackgroundColor3=COLORS.card
    petRanking.BackgroundTransparency=.13
    UI.petRanking=petRanking
    toggle(pets,"AUTO EQUIPAR MELHORES","autoEquip")
    button(pets,"EQUIPAR MELHOR DISPONIVEL",function() runExclusive("Equipar",equipOne) end)
    field(pets,"Maximo equipado",C.maxEquip,function(n) C.maxEquip=math.clamp(math.floor(n),1,25) end)
    pageSection(pets,"VENDA INTELIGENTE (PROTECOES)")
    field(pets,"Vender ate ($/s)",C.minSellValue,function(n) C.minSellValue=math.max(0,n) end)
    field(pets,"Proteger top N",C.keepBest,function(n) C.keepBest=math.max(1,math.floor(n)) end)
    toggle(pets,"PROTEGER MUTADOS","protectMutated")
    toggle(pets,"ARMAR VENDAS","autoSellArmed",function(on)
        if not on then C.autoSell=false end
    end)
    toggle(pets,"AUTO VENDER","autoSell",function(on)
        if on and not C.autoSellArmed then C.autoSell=false;log("Primeiro arme vendas no menu") end
    end)
    button(pets,"TESTAR VENDA DE UM PET",function() runExclusive("Venda",sellOne) end,COLORS.warn)
    pageSection(pets,"Nao vende pets equipados, mutados protegidos nem sem renda conhecida.")

    local system=UI.pages.system
    pageSection(system,"TREINAMENTO E ANALISE")
    toggle(system,"TREINO AUTOMATICO NA ESTEIRA","autoTrain",function(on)
        if on and C.autoFarm then stopFarm() end
    end)
    button(system,"LOCALIZAR ESTEIRA / BASE",function() runExclusive("Base",resolvePlot) end)
    button(system,"DIAGNOSTICO / COPIAR",function() runExclusive("Diagnostico",diagnostic) end,COLORS.accent)
    button(system,"PARAR TODAS AUTOMACOES",function()
        stopFarm()
        for _,key in ipairs({"autoReturn","autoPlace","autoHatch","autoEquip","autoSell","autoTrain"}) do C[key]=false end
        log("Automacoes paradas")
    end,COLORS.warn)
    button(system,"FECHAR SCRIPT",function() S.Destroy() end)
    pageSection(system,"Diagnostico tambem lista os ovos excluidos e o motivo de cada exclusao.")
    local dragging,begin,original,inputHeld=false,nil,nil,nil
    bind(head.InputBegan,function(input)
        if input.UserInputType==Enum.UserInputType.Touch or input.UserInputType==Enum.UserInputType.MouseButton1 then
            dragging=true;begin=input.Position;original=panel.Position;inputHeld=input
        end
    end)
    bind(UIS.InputChanged,function(input)
        if dragging and (input==inputHeld or input.UserInputType==Enum.UserInputType.MouseMovement) then
            local delta=input.Position-begin
            panel.Position=UDim2.new(original.X.Scale,original.X.Offset+delta.X,
                original.Y.Scale,original.Y.Offset+delta.Y)
        end
    end)
    bind(UIS.InputEnded,function(input)
        if input==inputHeld or input.UserInputType==Enum.UserInputType.MouseButton1 then dragging=false end
    end)
    bind(close.Activated,function() panel.Visible=false end)
    bind(opener.Activated,function() panel.Visible=not panel.Visible end)
    task.spawn(function()
        while S.alive do
            stat.Text="Ovos "..#S.eggList.."  •  ignorados "..#S.rejectedEggs.."  •  depositos "..S.deposited
                .."\n"..S.status:sub(1,125)
            if UI.ranking and #S.eggList>0 then
                local lines={"TOP OVOS REAIS  ($/s estimados)"}
                for i=1,math.min(3,#S.eggList) do
                    local e=S.eggList[i]
                    lines[#lines+1]=i..". "..e.name:sub(1,16).."  $"..short(e.price).."  Area "..e.area
                end
                UI.ranking.Text=table.concat(lines,"\n")
            elseif UI.ranking then
                UI.ranking.Text="Nenhum ovo elegivel no ultimo scan. Veja DIAGNOSTICO / COPIAR."
            end
            if UI.petRanking and #S.petList>0 then
                local lines={"MELHORES PETS  ($/s)"}
                for i=1,math.min(2,#S.petList) do
                    local p=S.petList[i]
                    lines[#lines+1]=i..". "..p.name:sub(1,16).."  $"..short(p.price)
                end
                UI.petRanking.Text=table.concat(lines,"\n")
            end
            for key,item in pairs(UI.buttons) do
                local on=C[key]
                item.btn.BackgroundColor3=on and COLORS.enabled or COLORS.card
                item.btn.Text=item.caption..(on and "  • ON" or "  • OFF")
            end
            task.wait(.3)
        end
    end)
end

function S.Destroy()
    if not S.alive then return end
    S.alive=false
    C.autoFarm=false;C.autoTrain=false;C.eggESP=false;C.autoReturn=false
    S.escapeRequested=false; S.returnPending=false
    S.autoReturnAttempted=false
    S.token=S.token+1
    clearESP()
    for _, cn in ipairs(S.connections) do pcall(function() cn:Disconnect() end) end
    if UI.gui then pcall(function() UI.gui:Destroy() end) end
    if env.__SAE_DELTA_V3==S then env.__SAE_DELTA_V3=nil end
end

env.__SAE_DELTA_V3=S
loadDefs()
listenCarry()
-- O prompt original pode ser o unico indicio de pickup replicado.
-- Escuta tambem ovos apanhados MANUALMENTE (sem alvo do auto farm).
local CS=game:GetService("CollectionService")
local function isFieldCarryPrompt(prompt)
    if not (prompt and prompt:IsA("ProximityPrompt")) or shopPrompt(prompt) then return false end
    local obj=prompt
    for _=1,5 do
        if obj and CS:HasTag(obj,"CarryAreaEgg") then return true end
        obj=obj and obj.Parent
    end
    -- Fallback para tags ausentes: palavras da acao mais contexto de ovo.
    local action=(tostring(prompt.ActionText or "")):lower()
    local label=(tostring(prompt.ObjectText or "").." "..tostring(prompt.Parent and prompt.Parent.Name or "")):lower()
    local actionCarry=action:find("steal",1,true) or action:find("carry",1,true)
        or action:find("grab",1,true) or action:find("pick",1,true)
        or action:find("pegar",1,true) or action:find("roubar",1,true)
    return (actionCarry and (label:find("egg",1,true) or label:find("ovo",1,true))) and true or false
end
bind(game:GetService("ProximityPromptService").PromptTriggered,function(prompt)
    if not S.alive or not isFieldCarryPrompt(prompt) then return end
    S.pickupSignalAt=os.clock()
    S.pickupSignalWasManual=not C.autoFarm
    S.pickupSignalSource="PromptTriggered: "..tostring(prompt.ActionText)
    -- A verificacao real de carry acontece no vigilante em seguida.
end)
buildUI()
startMaintenance()
startReturnWatcher()
espLoop()
log("V3.6 carregada: FARM OFF. FUGA ao pegar ovo = TP primeira fase + andar ate zona segura. Sem corrida longa se TP falhar.")
return S
