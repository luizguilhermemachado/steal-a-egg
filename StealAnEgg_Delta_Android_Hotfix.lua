-- STEAL AN EGG | DELTA ANDROID | HOTFIX LOADER
-- Mantem o script original no repositorio e aplica as correcoes em memoria.
-- Publique este arquivo com um NOVO nome no GitHub; nao substitua o arquivo remoto
-- que esta sendo baixado abaixo, para evitar recursao.

local SOURCE_URL = "https://raw.githubusercontent.com/luizguilhermemachado/steal-a-egg/main/StealAnEgg_Delta_Android.lua"
local WALK_SPEED = 100 -- WalkSpeed padrao do Roblox costuma ser 16; 100 e muito mais rapido.

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
