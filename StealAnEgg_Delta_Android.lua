-- STEAL AN EGG | DELTA ANDROID | arquivo unico (26/10/2026)
-- Nao usa readfile, loadfile, UI externa nem plugins exclusivos do Potassium.
-- Um arquivo remoto pode ser carregado com loadstring(game:HttpGet(URL))().
-- Auto Farm/ESP identificam ovos pelos prompts/tag CarryAreaEgg do cliente.
-- Mudancas de tags, remotes ou validacoes no servidor podem exigir atualizacao.

if not game:IsLoaded() then game.Loaded:Wait() end

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local CS = game:GetService("CollectionService")
local UIS = game:GetService("UserInputService")
local PF = game:GetService("PathfindingService")
local LP = Players.LocalPlayer
local env = (type(getgenv) == "function" and getgenv()) or _G
if env.__SAE_DELTA_ANDROID and type(env.__SAE_DELTA_ANDROID.Destroy) == "function" then
    pcall(env.__SAE_DELTA_ANDROID.Destroy)
end

local S = {
    alive=true, farm=false, esp=false, base=nil, token=0,
    filter="", eggs={}, highlights={}, connections={}, success=0, failures=0,
    action="Aguardando", lastError="", eventNames={}, petCount=0, areaCount=0, lastEggCount=0,
}
local gui, main, output, farmBtn, espBtn, filterBox, eggInfo
local function trace(msg)
    S.action=tostring(msg)
    print("[SAE Delta] "..S.action)
end
local function errlog(msg)
    S.lastError=tostring(msg)
    warn("[SAE Delta] "..S.lastError)
end
local function connected(signal, fn)
    local con=signal:Connect(fn)
    table.insert(S.connections, con)
    return con
end
local function chr()
    local char=LP.Character
    return char, char and char:FindFirstChild("HumanoidRootPart"), char and char:FindFirstChildOfClass("Humanoid")
end
local function norm(s)
    return string.lower(tostring(s or ""))
end
local function posOf(obj)
    if not obj then return nil end
    if obj:IsA("BasePart") then return obj.Position end
    if obj:IsA("Attachment") then return obj.WorldPosition end
    if obj:IsA("Model") then return obj:GetPivot().Position end
    return nil
end
local function promptPos(prompt)
    local node=prompt.Parent
    while node and node~=workspace do
        local p=posOf(node)
        if p then return p end
        node=node.Parent
    end
    return nil
end
local function getDef(name)
    local dir=RS:FindFirstChild("Data") or RS:FindFirstChild("Directory")
    local m=dir and dir:FindFirstChild("Assets")
    if not (m and m:IsA("ModuleScript")) then return nil end
    local ok, mod=pcall(require, m)
    if not ok or type(mod)~="table" then return nil end
    return (mod.Directory or mod)[name]
end
local function metadata(prompt)
    local attrNames={"AssetCategory", "Pet", "PetName", "EggName", "Category", "Rarity"}
    local name, rarity, value
    local node=prompt.Parent
    local count=0
    while node and node~=workspace and count<5 do
        for _, k in ipairs(attrNames) do
            local a=node:GetAttribute(k)
            if a~=nil then
                if k=="Rarity" then rarity=tostring(a)
                elseif not name then name=tostring(a) end
            end
        end
        if not name and (norm(node.Name):find("egg",1,true) or norm(node.Name):find("ovo",1,true)) then
            name=node.Name
        end
        node=node.Parent
        count+=1
    end
    name=name or "Ovo"
    local def=getDef(name)
    if def then
        rarity=rarity or tostring(def.Rarity or (def.Egg and def.Egg.Rarity) or "")
        value=tonumber(def.EarningRate or 0) or 0
        name=tostring((def.Egg and def.Egg.DisplayName) or def.DisplayName or name)
    end
    return name, rarity or "", value or 0
end

local function refreshCatalog()
    local data=RS:FindFirstChild("Data") or RS:FindFirstChild("Directory")
    local pets, areas=0,0
    local function countModule(name)
        local module=data and data:FindFirstChild(name)
        if not (module and module:IsA("ModuleScript")) then return 0 end
        local ok, result=pcall(require,module)
        if not ok or type(result)~="table" then return 0 end
        local directory=result.Directory or result
        local n=0
        if type(directory)=="table" then for _ in pairs(directory) do n+=1 end end
        return n
    end
    pets=countModule("Assets")
    areas=countModule("Areas")
    S.petCount=pets
    S.areaCount=areas
end

local function getEggs()
    local source={}
    -- Tag de prompts usada nos clientes conhecidos do Steal An Egg.
    local ok, tagged=pcall(CS.GetTagged, CS, "CarryAreaEgg")
    if ok and type(tagged)=="table" then
        for _, o in ipairs(tagged) do
            if o:IsA("ProximityPrompt") and o:IsDescendantOf(workspace) then
                source[o]=true
            end
        end
    end
    -- Fallback caso a tag seja removida ou renomeada pelo jogo.
    if not next(source) then
        for _, o in ipairs(workspace:GetDescendants()) do
            if o:IsA("ProximityPrompt") and
                (norm(o.Name):find("egg",1,true) or
                 norm(o.Name):find("carry",1,true) or
                 (o.Parent and norm(o.Parent.Name):find("egg",1,true))) then
                source[o]=true
            end
        end
    end
    local _, root=chr()
    local eggs={}
    for prompt in pairs(source) do
        local pos=promptPos(prompt)
        if pos then
            local name, rarity, value=metadata(prompt)
            if S.filter=="" or norm(name):find(norm(S.filter),1,true) or norm(rarity):find(norm(S.filter),1,true) then
                table.insert(eggs, {
                    prompt=prompt, pos=pos, name=name, rarity=rarity,
                    value=value, dist=root and (root.Position-pos).Magnitude or math.huge,
                })
            end
        end
    end
    table.sort(eggs, function(a,b)
        if a.value~=b.value then return a.value>b.value end
        return a.dist<b.dist
    end)
    S.eggs=eggs
    S.lastEggCount=#eggs
    return eggs
end

local function clearESP()
    for obj, ui in pairs(S.highlights) do
        pcall(function() ui:Destroy() end)
        S.highlights[obj]=nil
    end
end
local function updateESP()
    if not S.esp then clearESP() return end
    local eggs=getEggs()
    local keep={}
    for i, egg in ipairs(eggs) do
        if i>80 then break end
        local prompt=egg.prompt
        local adornee=prompt.Parent
        if adornee and adornee:IsA("Attachment") then adornee=adornee.Parent end
        if adornee and adornee:IsA("BasePart") then
            keep[prompt]=true
            local b=S.highlights[prompt]
            if not b or not b.Parent then
                b=Instance.new("BillboardGui")
                b.Name="SAE_Delta_ESP"
                b.Adornee=adornee
                b.Size=UDim2.fromOffset(180,38)
                b.StudsOffsetWorldSpace=Vector3.new(0,3,0)
                b.AlwaysOnTop=true
                b.MaxDistance=1500
                local label=Instance.new("TextLabel")
                label.Size=UDim2.fromScale(1,1)
                label.BackgroundColor3=Color3.fromRGB(16,24,38)
                label.BackgroundTransparency=0.28
                label.TextColor3=Color3.fromRGB(255,226,118)
                label.Font=Enum.Font.GothamBold
                label.TextScaled=true
                label.TextWrapped=true
                label.Parent=b
                b.Parent=LP:WaitForChild("PlayerGui")
                S.highlights[prompt]=b
            end
            local lbl=b:FindFirstChildOfClass("TextLabel")
            if lbl then
                lbl.Text=egg.name.."  ["..math.floor(egg.dist).."m]"..(egg.rarity~="" and "\n"..egg.rarity or "")
            end
        end
    end
    for prompt, b in pairs(S.highlights) do
        if not keep[prompt] then b:Destroy() S.highlights[prompt]=nil end
    end
end

-- Movimento deliberadamente normal: teleporte instantaneo e rejeitado por muitos servidores.
local function walkTo(dest, token, radius)
    radius=radius or 7
    local _, root, hum=chr()
    if not root or not hum then return false,"personagem indisponivel" end
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
        hum:MoveTo(p)
        local wpStart=os.clock()
        while S.alive and token==S.token do
            _, root, hum=chr()
            if not root or not hum or hum.Health<=0 then return false,"personagem morto" end
            if (root.Position-p).Magnitude < 5 then break end
            if os.clock()-wpStart>9 or os.clock()-started>100 then
                return false,"caminho bloqueado/tempo excedido"
            end
            task.wait(0.2)
        end
        if not S.alive or token~=S.token then return false,"interrompido" end
    end
    _, root=chr()
    return root~=nil and (root.Position-dest).Magnitude<radius,
        "destino fora do alcance"
end
local function stopMove()
    S.token+=1
    local _, root, hum=chr()
    if root and hum then hum:MoveTo(root.Position) end
end
local function requestPickup(egg)
    if not egg.prompt or not egg.prompt.Parent then return false,"ovo desapareceu" end
    if type(fireproximityprompt)~="function" then
        return false,"Delta nao disponibilizou fireproximityprompt"
    end
    local ok, message=pcall(function() fireproximityprompt(egg.prompt) end)
    if not ok then return false,tostring(message) end
    -- A chamada ter sido aceita no cliente NAO confirma coleta no servidor.
    return true,"interacao solicitada"
end
local function goEgg()
    local eggs=getEggs()
    if #eggs==0 then trace("Nenhum ovo encontrado (ver Diagnostico)") return end
    S.farm=false
    stopMove()
    local token=S.token
    local egg=eggs[1]
    trace("Indo ate "..egg.name)
    task.spawn(function()
        local ok, reason=walkTo(egg.pos, token, 9)
        if token==S.token then trace(ok and "Proximo ao ovo" or "Movimento: "..tostring(reason)) end
    end)
end
local function toggleFarm()
    if S.farm then
        S.farm=false
        stopMove()
        trace("Auto Farm desligado")
        return
    end
    if not S.base then trace("Primeiro defina sua base pelo botao") return end
    if type(fireproximityprompt)~="function" then
        errlog("Auto Farm: Delta sem fireproximityprompt")
        return
    end
    S.farm=true
    stopMove()
    trace("Auto Farm iniciado")
    local token=S.token
    task.spawn(function()
        while S.alive and S.farm and token==S.token do
            local eggs=getEggs()
            local egg=eggs[1]
            if not egg then
                trace("Aguardando ovos visiveis no cliente")
                task.wait(2)
            else
                trace("A caminho: "..egg.name)
                local reached, reason=walkTo(egg.pos, token, 9)
                if not reached then
                    S.failures+=1
                    errlog("Ir ao ovo: "..tostring(reason))
                else
                    local yes, info=requestPickup(egg)
                    if not yes then S.failures+=1 errlog(info)
                    else
                        trace("Coleta solicitada; voltando para base")
                        task.wait(1.1)
                        local home, why=walkTo(S.base, token, 9)
                        if home then
                            S.success+=1 -- conta ciclo executado, NAO deposicao confirmada
                            trace("Ciclo concluido; deposito nao verificado")
                        else
                            S.failures+=1
                            errlog("Volta: "..tostring(why))
                        end
                    end
                end
                task.wait(1.5)
            end
        end
    end)
end

local function paintUI()
    gui=Instance.new("ScreenGui")
    gui.Name="StealAnEgg_Delta_Android"
    gui.ResetOnSpawn=false
    gui.DisplayOrder=50
    gui.Parent=LP:WaitForChild("PlayerGui")
    local function round(obj)
        local co=Instance.new("UICorner")
        co.CornerRadius=UDim.new(0,10)
        co.Parent=obj
        return obj
    end
    local bubble=round(Instance.new("TextButton"))
    bubble.Name="AbrirMenu"
    bubble.Size=UDim2.fromOffset(110,44)
    bubble.Position=UDim2.fromOffset(12,65)
    bubble.Text="🥚 EGG MENU"
    bubble.TextSize=13
    bubble.TextColor3=Color3.new(1,1,1)
    bubble.Font=Enum.Font.GothamBold
    bubble.BackgroundColor3=Color3.fromRGB(30,95,180)
    bubble.Parent=gui

    main=round(Instance.new("Frame"))
    main.AnchorPoint=Vector2.new(0.5,0.5)
    main.Position=UDim2.fromScale(0.5,0.5)
    main.Size=UDim2.fromOffset(330,430)
    main.BackgroundColor3=Color3.fromRGB(19,29,46)
    main.Parent=gui

    local title=round(Instance.new("TextButton"))
    title.Size=UDim2.new(1,0,0,45)
    title.Text="STEAL AN EGG · DELTA MOBILE"
    title.TextColor3=Color3.new(1,1,1)
    title.TextSize=14
    title.Font=Enum.Font.GothamBold
    title.BackgroundColor3=Color3.fromRGB(38,57,87)
    title.Parent=main
    local scroll=Instance.new("ScrollingFrame")
    scroll.Size=UDim2.new(1,-14,1,-56)
    scroll.Position=UDim2.fromOffset(7,50)
    scroll.BackgroundTransparency=1
    scroll.ScrollBarThickness=4
    scroll.AutomaticCanvasSize=Enum.AutomaticSize.Y
    scroll.CanvasSize=UDim2.new()
    scroll.Parent=main
    local layout=Instance.new("UIListLayout")
    layout.Padding=UDim.new(0,7)
    layout.HorizontalAlignment=Enum.HorizontalAlignment.Center
    layout.Parent=scroll
    local pad=Instance.new("UIPadding")
    pad.PaddingBottom=UDim.new(0,12)
    pad.Parent=scroll
    local function btn(text, cb)
        local b=round(Instance.new("TextButton"))
        b.Size=UDim2.new(1,-10,0,43)
        b.BackgroundColor3=Color3.fromRGB(42,67,104)
        b.Font=Enum.Font.GothamMedium
        b.TextSize=13
        b.TextColor3=Color3.new(1,1,1)
        b.Text=text
        b.Parent=scroll
        connected(b.Activated,cb)
        return b
    end
    output=Instance.new("TextLabel")
    output.Size=UDim2.new(1,-10,0,98)
    output.TextColor3=Color3.fromRGB(237,235,194)
    output.TextSize=12
    output.Font=Enum.Font.Code
    output.TextWrapped=true
    output.TextXAlignment=Enum.TextXAlignment.Left
    output.TextYAlignment=Enum.TextYAlignment.Top
    output.BackgroundTransparency=1
    output.Parent=scroll

    farmBtn=btn("AUTO FARM: OFF",toggleFarm)
    espBtn=btn("ESP: OFF",function() S.esp=not S.esp updateESP() end)
    btn("IR ATE O MELHOR OVO",goEgg)
    btn("PARAR MOVIMENTO",function() S.farm=false stopMove() trace("Movimento cancelado") end)
    btn("MARCAR BASE ONDE ESTOU",function()
        local _,root=chr()
        if root then S.base=root.Position trace("Base marcada na posicao atual")
        else errlog("Personagem nao encontrado") end
    end)
    btn("ATUALIZAR OVOS/PETS/EVENTO",function()
        refreshCatalog()
        local eggs=getEggs()
        updateESP()
        trace("Ovos: "..#eggs.." | Pets: "..S.petCount.." | Areas: "..S.areaCount)
    end)
    filterBox=round(Instance.new("TextBox"))
    filterBox.Size=UDim2.new(1,-10,0,42)
    filterBox.BackgroundColor3=Color3.fromRGB(240,242,249)
    filterBox.TextColor3=Color3.fromRGB(20,30,43)
    filterBox.TextSize=13
    filterBox.Font=Enum.Font.Gotham
    filterBox.PlaceholderText="Filtrar pet/raridade (vazio=todos)"
    filterBox.ClearTextOnFocus=false
    filterBox.Text=""
    filterBox.Parent=scroll
    connected(filterBox.FocusLost,function()
        S.filter=filterBox.Text:gsub("^%s+",""):gsub("%s+$","")
        trace(S.filter=="" and "Filtro removido" or "Filtro: "..S.filter)
        updateESP()
    end)
    btn("DIAGNOSTICO / COPIAR",function()
        local eggs=getEggs()
        local lines={
            "STEAL AN EGG DELTA MOBILE 2026-10-26",
            "PlaceId="..tostring(game.PlaceId),
            "Ovos encontrados="..tostring(#eggs),
            "Pets no catalogo="..tostring(S.petCount),
            "Areas/eventos no catalogo="..tostring(S.areaCount),
            "Prompt API="..tostring(type(fireproximityprompt)),
            "ESP="..tostring(S.esp),
            "Farm="..tostring(S.farm),
            "Base="..tostring(S.base),
            "Ciclos tentados="..tostring(S.success),
            "Falhas="..tostring(S.failures),
            "Status="..S.action,
            "Erro="..S.lastError,
        }
        for i=1,math.min(#eggs,15) do
            lines[#lines+1]=i..". "..eggs[i].name.."/"..eggs[i].rarity
        end
        local report=table.concat(lines,"\n")
        print(report)
        if type(setclipboard)=="function" then
            local ok=pcall(setclipboard,report)
            trace(ok and "Diagnostico copiado" or "Falha ao copiar; veja o console")
        else trace("Console: relatorio impresso (sem clipboard)") end
    end)
    btn("FECHAR MENU",function() main.Visible=false end)
    connected(bubble.Activated,function() main.Visible=not main.Visible end)
    -- Arrastar pela barra superior; funciona com toque.
    local drag, dragInput, origin, initial
    connected(title.InputBegan,function(input)
        if input.UserInputType==Enum.UserInputType.Touch or input.UserInputType==Enum.UserInputType.MouseButton1 then
            drag=true
            dragInput=input
            origin=Vector2.new(input.Position.X,input.Position.Y)
            initial=main.Position
        end
    end)
    connected(UIS.InputChanged,function(input)
        if drag and ((dragInput and input==dragInput) or input.UserInputType==Enum.UserInputType.MouseMovement) then
            local delta=Vector2.new(input.Position.X,input.Position.Y)-origin
            main.Position=UDim2.new(initial.X.Scale,initial.X.Offset+delta.X, initial.Y.Scale,initial.Y.Offset+delta.Y)
        end
    end)
    connected(UIS.InputEnded,function(input)
        if input==dragInput or input.UserInputType==Enum.UserInputType.MouseButton1 then drag=false dragInput=nil end
    end)
    local function resize()
        local c=workspace.CurrentCamera
        local view=c and c.ViewportSize or Vector2.new(360,700)
        main.Size=UDim2.fromOffset(math.max(200,math.min(330,view.X-20)), math.max(220,math.min(430,view.Y-65)))
    end
    resize()
    if workspace.CurrentCamera then
        connected(workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"),resize)
    end
end

function S.Destroy()
    S.alive=false
    S.farm=false
    stopMove()
    clearESP()
    for _, c in ipairs(S.connections) do pcall(function() c:Disconnect() end) end
    if gui then gui:Destroy() end
    if env.__SAE_DELTA_ANDROID==S then env.__SAE_DELTA_ANDROID=nil end
end

env.__SAE_DELTA_ANDROID=S
paintUI()
refreshCatalog()
trace("Menu pronto. Defina sua base antes de ligar Auto Farm")
task.spawn(function()
    while S.alive do
        local ok, msg=pcall(function()
            if S.esp then updateESP() end
            if output then
                output.Text=string.format("Ovos visiveis: %d | Ciclos: %d | Falhas: %d\nFarm: %s | ESP: %s\nBase: %s\n%s%s",
                    S.lastEggCount,S.success,S.failures,
                    S.farm and "ON" or "OFF",S.esp and "ON" or "OFF",
                    S.base and "marcada" or "nao marcada",S.action,
                    S.lastError~="" and ("\nERRO: "..S.lastError) or "")
            end
            if farmBtn then farmBtn.Text="AUTO FARM: "..(S.farm and "ON" or "OFF") end
            if espBtn then espBtn.Text="ESP: "..(S.esp and "ON" or "OFF") end
        end)
        if not ok then errlog(msg) end
        task.wait(1.8)
    end
end)
return S
