local QBCore = exports['qb-core']:GetCoreObject()
local chamado = false
local aguardandoDecisao = false
local veh, medic
local distanciaHUD = 0

local mensagensProximidade = {
    { dist = 100.0, msg = "📞 Central SAMU: chamado recebido, equipe deslocando." },
    { dist = 70.0,  msg = "🚑 Ambulância saiu da base, sirene ligada!" },
    { dist = 50.0,  msg = "🚦 SAMU no meio do caminho, segura aí..." },
    { dist = 30.0,  msg = "😬 Atenção! Ambulância se aproximando." },
    { dist = 10.0,  msg = "🏥 SAMU chegando no local!" }
}

-- Comando para chamar SAMU
RegisterCommand("call_samu", function()
    local PlayerData = QBCore.Functions.GetPlayerData()
    local estaMorto = PlayerData.metadata["isdead"] or PlayerData.metadata["inlaststand"]

    if not estaMorto then
        QBCore.Functions.Notify("Você só pode chamar o SAMU desacordado.", "error")
        return
    end

    if chamado then
        QBCore.Functions.Notify("O SAMU já foi acionado.", "error")
        return
    end

    TriggerServerEvent("samu:checkCooldown")
end)

-- Spawn seguro em estrada/rodovia
local function GetSafeSpawn(coords, minDist, maxDist)
    local spawnPos, spawnHeading
    local tentativas = 0
    repeat
        local ang = math.random() * math.pi * 2
        local dist = math.random(minDist, maxDist)
        local offset = vector3(math.cos(ang)*dist, math.sin(ang)*dist, 0.0)
        local found, outPos, outHeading = GetClosestVehicleNodeWithHeading(coords.x + offset.x, coords.y + offset.y, coords.z, 1, 3.0, 0)
        spawnPos = outPos
        spawnHeading = outHeading
        tentativas = tentativas + 1
        Wait(10)
    until spawnPos ~= nil or tentativas >= 10

    if not spawnPos then
        spawnPos = coords + vector3(10.0,10.0,0.0)
        spawnHeading = GetEntityHeading(PlayerPedId())
    end

    return spawnPos, spawnHeading
end

-- Spawn da ambulância e paramédico
local function SpawnAmbulancia(coords)
    local vehicleHash = GetHashKey("sprintersamu")
    local pedHash     = GetHashKey("s_m_m_paramedic_01")
    
    RequestModel(vehicleHash)
    RequestModel(pedHash)
    while not HasModelLoaded(vehicleHash) or not HasModelLoaded(pedHash) do Wait(0) end

    local spawnPos, spawnHeading = GetSafeSpawn(coords, 50, 80)

    local v = CreateVehicle(vehicleHash, spawnPos.x, spawnPos.y, spawnPos.z, spawnHeading, true, false)
    SetVehicleHasBeenOwnedByPlayer(v,true)
    SetEntityAsMissionEntity(v,true,true)
    SetVehicleEngineOn(v,true,true,true)
    SetVehicleSiren(v,true)
    SetVehicleLights(v,2)
    SetVehicleExtra(v,1,0)

    local p = CreatePedInsideVehicle(v,26,pedHash,-1,true,false)
    SetPedIntoVehicle(p,v,-1)
    SetBlockingOfNonTemporaryEvents(p,true)
    SetDriverAbility(p,1.0)
    SetDriverAggressiveness(p,1.0)

    return v, p
end

-- Chegada, descida e reanimação
-- Chegada, descida e reanimação
local function chegadaSAMU()
    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)

    -- Espera ambulância chegar perto (entre 5m e 12m)
    local chegou = false
    while not chegou do
        local vehCoords = GetEntityCoords(veh)
        local dist = #(vehCoords - coords)

        if dist <= 12.0 then
            chegou = true

            -- Para o veículo com segurança
            ClearPedTasksImmediately(medic)
            TaskVehicleTempAction(medic, veh, 27, 3000) -- freia por 3s
            SetVehicleForwardSpeed(veh, 0.0)
            Wait(3000)

            -- Paramédico desce
            TaskLeaveVehicle(medic, veh, 0)
            while IsPedInAnyVehicle(medic, false) do
                Wait(50)
            end

            Wait(300)

            -- Ele vai até você
            TaskGoToCoordAnyMeans(medic, coords.x, coords.y, coords.z, 2.0, 0, 0, 786603, 0.0)
        end

        Wait(200)
    end

    -- Espera paramédico chegar perto (~1.5m)
    while #(GetEntityCoords(medic) - coords) > 1.5 do Wait(50) end

    -- Reanimação
    FreezeEntityPosition(medic,true)
    RequestAnimDict("mini@cpr@char_a@cpr_str")
    while not HasAnimDictLoaded("mini@cpr@char_a@cpr_str") do Wait(0) end
    TaskPlayAnim(medic,"mini@cpr@char_a@cpr_str","cpr_pumpchest",8.0,8.0,8000,1,0,false,false,false)
    Wait(8000)
    FreezeEntityPosition(medic,false)

    -- Executa o Revive do QB-Core (Isso já vai te levantar e limpar o status de morto)
    TriggerEvent("hospital:client:Revive")
    
    -- Ajuste seguro de vida após o ciclo do Revive terminar
    CreateThread(function()
        Wait(500) -- Pequena pausa para o qb-hospital processar o revive antes
        local maxHealth = GetEntityMaxHealth(PlayerPedId())
        SetEntityHealth(PlayerPedId(), math.floor(maxHealth * 0.3))
    end)

    QBCore.Functions.Notify("❤️ Você foi reanimado pelo SAMU.", "success")

    -- Pergunta tratamento completo
    aguardandoDecisao = true
    QBCore.Functions.Notify("💉 Deseja tratamento completo por R$1.000? [Y] Sim | [N] Não", "primary", 10000)
end

-- Tratamento completo ou recusa
CreateThread(function()
    while true do
        Wait(0)
        if aguardandoDecisao then
            if IsControlJustPressed(0,246) then -- Y
                aguardandoDecisao = false
                TriggerServerEvent("samu:tratar", 1000)
            end

            if IsControlJustPressed(0,249) then -- N
                aguardandoDecisao = false
                QBCore.Functions.Notify("🚑 Tratamento recusado. Vida parcial mantida.", "error")
                TriggerServerEvent("samu:finaliza")
            end
        end
    end
end)

-- Evento principal do SAMU
RegisterNetEvent("samu:start")
AddEventHandler("samu:start", function()
    chamado = true
    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)
    QBCore.Functions.Notify("📞 Chamado enviado ao SAMU.", "success")
    Wait(800)

    veh, medic = SpawnAmbulancia(coords)
    TaskVehicleDriveToCoordLongrange(medic,veh,coords.x, coords.y, coords.z,28.0,786603,10.0)

    -- Thread HUD e mensagens
    CreateThread(function()
        local usadas = {}
        while chamado and DoesEntityExist(veh) do
            local posVeh = GetEntityCoords(veh)
            distanciaHUD = #(posVeh - coords)
            for i,v in ipairs(mensagensProximidade) do
                if distanciaHUD <= v.dist and not usadas[i] then
                    usadas[i] = true
                    QBCore.Functions.Notify(v.msg, "primary")
                end
            end
            Wait(700)
        end
    end)

    -- chegada, descida e reanimação
    chegadaSAMU()
end)

-- Finalização no client
RegisterNetEvent("samu:finalizaClient")
AddEventHandler("samu:finalizaClient", function()
    if DoesEntityExist(medic) then
        TaskEnterVehicle(medic,veh,8000,-1,2.0,1,0)
        Wait(1500)
        QBCore.Functions.Notify("📻 SAMU: Chamado finalizado, voltando à base!", "primary")

        local pedCoords = GetEntityCoords(medic)
        local destino = pedCoords + GetEntityForwardVector(medic)*10.0
        TaskVehicleDriveToCoordLongrange(medic,veh,destino.x,destino.y,destino.z,28.0,786603,10.0)
    end

    Wait(4000)
    if DoesEntityExist(medic) then DeleteEntity(medic) end
    if DoesEntityExist(veh) then DeleteEntity(veh) end
    chamado=false
end)

-- HUD
CreateThread(function()
    while true do
        Wait(0)
        if chamado and distanciaHUD then
            SetTextFont(0)
            SetTextProportional(1)
            SetTextScale(0.4,0.4)
            SetTextColour(255,255,255,255)
            SetTextDropshadow(0,0,0,0,255)
            SetTextEdge(1,0,0,0,255)
            SetTextOutline()
            SetTextEntry("STRING")
            AddTextComponentString(string.format("🚑 Distância SAMU: %.1f m",distanciaHUD))
            DrawText(0.85,0.05)
        end
    end
end)
