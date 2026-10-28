-- STEAL AN EGG | DELTA ANDROID V3 | 27/10/2026
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
local LP = Players.LocalPlayer
local env = ((type(getgenv) == "function") and getgenv()) or _G
for _, key in ipairs({"__SAE_DELTA_V3", "__SAE_FARM_V2"}) do
    if env[key] and type(env[key].Destroy) == "function" then pcall(env[key].Destroy) end
end

local C = {
    interval = 1.25, espRefresh = 3, espCount = 12,
    allowWarp = true, allowWalkFallback = false, warpStep = 24,
    minSellValue = 100, keepBest = 13, maxEquip = 13,
    protectMutated = true, autoSellArmed = false,
    autoPlace = false, autoHatch = false, autoEquip = false,
    autoSell = false, autoTrain = false, autoFarm = false, eggESP = false,
}
local S = {
    alive = true, busy = false, token = 0, status = "Pronto. Abra DIAGNOSTICO antes do farm.",
    error = "", source = {}, eggList = {}, petList = {}, inventory = {},
    plot = nil, pen = nil, origin = nil, treadmill = nil,
    safe = nil, safeMode = "nao definido", carrying = false,
    carryingKnown = false, carryVersion = 0,
    attempts = 0, grabbed = 0, deposited = 0, failed = 0,
    locked = {}, remoteCache = {}, inflight = {},
    connections = {}, esp = {}, logs = {},
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
local function getField()
    local ok, data = invoke("snapshot", nil, 6)
    if not ok then return nil, data end
    local list = records(data)
    if not list then return nil, "Snapshot de campo sem formato reconhecido (" .. keys(data) .. ")" end
    local root = char()
    local out = {}
    for _, egg in pairs(list) do
        if type(egg) == "table" and egg.Uid ~= nil and egg.AreaId ~= nil
            and typeof(egg.BottomCFrame) == "CFrame" then
            local state = tostring(egg.State or "")
            local stateKey = state:lower()
            -- AreaId + posicao + UID + state de campo: nao selecionar aderecos do lobby.
            if stateKey == "slot" or stateKey == "available" or stateKey == "spawned" or stateKey == "field" then
                local price, exact = valueFor(egg)
                local p = egg.BottomCFrame.Position
                local id = tostring(egg.Uid)
                if not S.locked[id] or S.locked[id] < os.clock() then
                    table.insert(out, { uid=id, rawUid=egg.Uid, rec=egg,
                        position=p, area=tostring(egg.AreaId), state=state,
                        category=tostring(egg.AssetCategory), name=displayName(egg),
                        price=price, exact=exact, scale=num(egg.AssetScale or egg.Scale) or 1,
                        muts=mutationsCount(egg.Mutations),
                        distance=root and (root.Position-p).Magnitude or math.huge })
                end
            end
        end
    end
    table.sort(out, function(a,b)
        if a.price and not b.price then return true end
        if b.price and not a.price then return false end
        if a.price and b.price and a.price ~= b.price then return a.price > b.price end
        if a.muts ~= b.muts then return a.muts > b.muts end
        if a.scale ~= b.scale then return a.scale > b.scale end
        return a.distance < b.distance
    end)
    S.eggList = out
    return out
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
local function moveWalk(pos, timeout, token)
    local root, hum=char()
    if not root then return false,"Sem personagem" end
    local deadline=os.clock()+(timeout or 20)
    local last=0
    while S.alive and (token==nil or token==S.token) and os.clock()<deadline do
        root, hum=char()
        if not root then return false,"Personagem morreu" end
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
local function moveTo(pos, token)
    if C.allowWarp then
        local ok,reason=warpTo(pos,token)
        if ok then return true,reason end
        if not C.allowWalkFallback then return false,reason end
        log("TP recusado. Tentando caminhar como alternativa.")
    end
    return moveWalk(pos,35,token)
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
local function collectCycle(token)
    S.attempts=S.attempts+1
    local eggs,e=getField()
    if not eggs then return false,"Consulta de ovos: "..tostring(e) end
    if #eggs==0 then return false,"Nenhum ovo de campo disponivel (ou formato mudou)" end
    local target=eggs[1]
    log("ALVO: "..target.name.." | "..short(target.price).."/s | area "..target.area)
    local before = getOwned() or {}
    local hadTool=hasEggTool()
    local oldVersion=S.carryVersion
    -- 1) Pedido direto: evita tempo do prompt e verifica se o servidor aceita de longe.
    local acceptedPickup, why=pickUp(target)
    if acceptedPickup~=true then
        if not C.allowWarp and not C.allowWalkFallback then
            return false,"Coleta a distancia recusada; ative TP ou caminhada"
        end
        -- 2) Se distancia e restricao, aproximar e tentar uma ultima vez.
        local reached,reason=moveTo(target.position,token)
        if not reached then return false,"Aproximacao falhou: "..tostring(reason) end
        if token~=S.token then return false,"Cancelado" end
        acceptedPickup,why=pickUp(target)
        if acceptedPickup~=true then
            S.locked[target.uid]=os.clock()+14
            return false,"Coleta nao aceita: "..tostring(why)
        end
    end
    task.wait(.18)
    local proof = (S.carryVersion>oldVersion and S.carrying) or (not hadTool and hasEggTool())
    if not proof and acceptedPickup==true then
        -- Chamada aceita, mas ainda nao foi verificado se esta carregando.
        for i=1,7 do
            if token~=S.token then return false,"Cancelado" end
            if (S.carryVersion>oldVersion and S.carrying) or (not hadTool and hasEggTool()) then proof=true;break end
            task.wait(.13)
        end
    end
    if not proof and acceptedPickup~=true then
        return false,"Nao ha evidencia de coleta"
    end
    if proof then S.grabbed=S.grabbed+1 end
    log(proof and "Ovo carregado (estado detectado). Fugindo..." or
        "Pedido aceito, carga ainda nao observavel. Tentando depositar...")
    if not S.safe then
        local located, reason=resolvePlot()
        if not located then return false,reason end
    end
    local arrived,reason=moveTo(S.safe,token)
    if not arrived then return false,"Fuga nao confirmada: "..tostring(reason) end
    if S.safeMode~="sua base" then
        return true,"PAUSAR: ponto manual nao deposita o ovo"
    end
    -- PetArea pode precisar de contato no chao para registrar a entrega.
    local root=char()
    if root and S.pen and root.Position.Y>S.pen.Position.Y+5 then
        pcall(function() root.CFrame=CFrame.new(S.pen.Position+Vector3.new(0,1.8,0)) end)
    end
    task.wait(.9)
    local after = getOwned()
    local added = newId(before,after)
    if added then
        if not proof then S.grabbed=S.grabbed+1 end
        S.deposited=S.deposited+1
        log("Deposito confirmado: novo ovo no inventario (UID "..tostring(added)..")")
        return true,"continua"
    end
    if S.carryingKnown and S.carrying then
        return false,"Ainda carregando. Entrar na PetArea nao confirmou deposito"
    end
    return false,"Chegou na base, mas inventario nao confirmou recebimento"
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
    if not S.safe then
        local ok,reason=resolvePlot()
        if not ok then C.autoFarm=false;fail(reason);return end
    end
    S.token=S.token+1
    local token=S.token
    task.spawn(function()
        while S.alive and C.autoFarm and S.token==token do
            if not S.busy then
                S.busy=true
                local ok,worked,reason=pcall(collectCycle,token)
                S.busy=false
                if not ok then fail("Farm Lua: "..tostring(worked)); C.autoFarm=false;break end
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
        "STEAL AN EGG | V3 DIAGNOSTICO | "..os.date("%d/%m/%Y %H:%M"),
        "PlaceId="..tostring(game.PlaceId).." | PlaceVersion="..tostring(game.PlaceVersion),
        "Build esperado=107778070777162 | StreamingEnabled="..tostring(workspace.StreamingEnabled),
        "CatalogoAssets="..keys(defs.Assets):sub(1,150),
        "MutacoesModulo="..tostring(type(defs.Mutations.EarningsFor)),
        "Base="..tostring(S.plot and S.plot:GetFullName() or "NAO IDENTIFICADA"),
        "LocalSeguro="..S.safeMode,
        "Tentativas="..S.attempts.." | ColetasAceitas="..S.grabbed.." | Depositos="..S.deposited,
    }
    for k in pairs(services) do
        local r=rem(k)
        table.insert(out,"Remote "..k.." = "..(r and (r.ClassName.." / "..r:GetFullName()) or "AUSENTE"))
    end
    local e,er=getField()
    table.insert(out,"Ovos campo="..tostring(e and #e or "ERRO "..tostring(er)))
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
    local opener=make("TextButton",gui,{Text="🥚 EGG V3",TextSize=13,Font=Enum.Font.GothamBold,
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
    label(head,"STEAL AN EGG  /  DELTA V3",15,COLORS.text,31).Position=UDim2.fromOffset(13,5)
    local meta=label(head,"INTELIGENTE  •  SEM WALKSPEED  •  ANDROID",10,COLORS.muted,23)
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
    pageSection(farm,"COLETA DE OVOS RAROS")
    toggle(farm,"AUTO FARM", "autoFarm",function(on)
        if on then loopFarm() else stopFarm() end
    end)
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
    pageSection(farm,"MOVIMENTO E FUGA")
    toggle(farm,"TELEPORTE EXPERIMENTAL","allowWarp")
    toggle(farm,"ANDAR SE TP FALHAR","allowWalkFallback")
    button(farm,"DETECTAR MINHA BASE",function()
        runExclusive("Base",function()
            local ok,err=resolvePlot()
            if ok then log("Base encontrada. PetArea sera o ponto de deposito.") end
            return ok,err
        end)
    end)
    button(farm,"MARCAR PONTO SEGURO AQUI",markSafe)
    button(farm,"TESTAR TELEPORTE PARA BASE",function()
        runExclusive("Teste TP",function(token)
            if not S.safe then
                local ok,err=resolvePlot();if not ok then return false,err end
            end
            return warpTo(S.safe,token)
        end)
    end)
    pageSection(farm,"Importante: Speed e alcance podem ser validados pelo servidor.")

    local eggs=UI.pages.eggs
    pageSection(eggs,"OVOS REAIS  •  RENDA + TAMANHO + MUTACOES")
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
        for _,key in ipairs({"autoPlace","autoHatch","autoEquip","autoSell","autoTrain"}) do C[key]=false end
        log("Automacoes paradas")
    end,COLORS.warn)
    button(system,"FECHAR SCRIPT",function() S.Destroy() end)
    pageSection(system,"Diagnostico informa quais remotes/classes existem nesta versao.")
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
            stat.Text="Coletas "..S.grabbed.."  •  depositos "..S.deposited.."  •  erros "..S.failed
                .."\n"..S.status:sub(1,125)
            if UI.ranking and #S.eggList>0 then
                local lines={"TOP OVOS REAIS  ($/s estimados)"}
                for i=1,math.min(3,#S.eggList) do
                    local e=S.eggList[i]
                    lines[#lines+1]=i..". "..e.name:sub(1,16).."  $"..short(e.price).."  Area "..e.area
                end
                UI.ranking.Text=table.concat(lines,"\n")
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
    C.autoFarm=false;C.autoTrain=false;C.eggESP=false
    S.token=S.token+1
    clearESP()
    for _, cn in ipairs(S.connections) do pcall(function() cn:Disconnect() end) end
    if UI.gui then pcall(function() UI.gui:Destroy() end) end
    if env.__SAE_DELTA_V3==S then env.__SAE_DELTA_V3=nil end
end

env.__SAE_DELTA_V3=S
loadDefs()
listenCarry()
buildUI()
startMaintenance()
espLoop()
log("V3 carregado. Valide DIAGNOSTICO e teste coleta uma vez.")
return S