local QBCore = exports['qb-core']:GetCoreObject()
local cooldown = {}

-- CHECAR COOLDOWN
RegisterServerEvent("samu:checkCooldown")
AddEventHandler("samu:checkCooldown", function()
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end

    local citizenid = Player.PlayerData.citizenid
    local now = os.time()
    if cooldown[citizenid] and now - cooldown[citizenid] < 300 then
        local tempoRestante = 300 - (now - cooldown[citizenid])
        TriggerClientEvent("QBCore:Notify", src, "⏱️ Aguarde "..tempoRestante.."s para chamar o SAMU novamente.", "error")
        return
    end

    cooldown[citizenid] = now
    TriggerClientEvent("samu:start", src)
end)

-- TRATAMENTO E COBRANÇA
RegisterServerEvent("samu:tratar")
AddEventHandler("samu:tratar", function(valor)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end

    -- Tenta cobrar do banco e depois da carteira
    if Player.Functions.RemoveMoney("bank", valor, "samu-npc-treatment") or Player.Functions.RemoveMoney("cash", valor, "samu-npc-treatment") then
        local ped = GetPlayerPed(src)
        local maxHealth = GetEntityMaxHealth(ped)
        SetEntityHealth(ped, maxHealth) -- Restaura 100% da vida no server-side

        TriggerClientEvent("QBCore:Notify", src, "💰 Você pagou R$"..valor.." pelo tratamento SAMU.", "success")
        TriggerClientEvent("QBCore:Notify", src, "💉 Tratamento completo aplicado! Vida restaurada.", "success")
        TriggerClientEvent("samu:finalizaClient", src)
    else
        TriggerClientEvent("QBCore:Notify", src, "❌ Você não tem dinheiro para o tratamento!", "error")
        TriggerClientEvent("samu:finalizaClient", src)
    end
end)

-- FINALIZAÇÃO DO CHAMADO
RegisterServerEvent("samu:finaliza")
AddEventHandler("samu:finaliza", function()
    local src = source
    TriggerClientEvent("samu:finalizaClient", src)
end)
