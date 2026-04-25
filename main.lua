local api = require("api")
local Core = api._NuziCore or require("nuzi-core/core")

local Events = Core.Events
local Log = Core.Log
local Require = Core.Require

local moduleErrors = {}

local function appendModuleErrors(name, errors)
    if type(errors) ~= "table" or #errors == 0 then
        moduleErrors[#moduleErrors + 1] = string.format("%s: unknown load failure", tostring(name))
        return
    end
    moduleErrors[#moduleErrors + 1] = string.format(
        "%s: %s",
        tostring(name),
        Require.DescribeErrors(errors)
    )
end

local modules, failures = Require.AddonSet("nuzi-raidtools", {
    "shared",
    "utils",
    "runtime",
    "raid_manager_ui",
    "list_manager"
})

for name, failure in pairs(failures or {}) do
    appendModuleErrors(name, failure.errors)
end

local Shared = modules.shared
local Utils = modules.utils
local Runtime = modules.runtime
local RaidManagerUi = modules.raid_manager_ui
local ListManager = modules.list_manager

local addon = Shared ~= nil and Shared.ADDON or {
    name = "Nuzi Raidtools",
    author = "Nuzi",
    version = "2.0.0",
    desc = "Raid recruitment, auto roles, and lead handoff"
}

local logger = Log.Create(addon.name)
local modulesInitialized = false

local function modulesReady()
    return Shared ~= nil
        and Utils ~= nil
        and Runtime ~= nil
        and RaidManagerUi ~= nil
        and ListManager ~= nil
end

local function logModuleErrors()
    if #moduleErrors == 0 then
        return
    end
    for _, detail in ipairs(moduleErrors) do
        logger:Err("Module load error: " .. tostring(detail))
    end
end

local function initModules()
    if modulesInitialized or not modulesReady() then
        return modulesInitialized
    end
    Runtime.Init(Shared, Utils)
    RaidManagerUi.Init(Shared, Utils, ListManager, Runtime)
    Shared.SetSaveCallback(function()
        if ListManager.Refresh ~= nil then
            ListManager.Refresh()
        end
    end)
    modulesInitialized = true
    return true
end

local function onRoleChanged(role)
    local normalizedRole = Runtime.OnRoleChanged(role)
    if normalizedRole ~= nil then
        RaidManagerUi.SyncRoleDropdownSelection(normalizedRole)
    end
end

local function onTeamChanged()
    Runtime.ApplySavedRole()
    RaidManagerUi.SyncRoleDropdownSelection()
    RaidManagerUi.PatchRaidManagerMembers(Shared.state.raid_manager)
end

local function onChatMessage(channelId, speakerId, _, speakerName, message)
    local resolvedSpeakerName = tostring(speakerName or "")
    local resolvedMessage = tostring(message or "")
    local loweredMessage = string.lower(resolvedMessage)
    local leadSettingsChanged = Runtime.HandleLeadSniffing(channelId, resolvedSpeakerName, loweredMessage)
    Runtime.HandleWhitelistLoginAnnouncement(resolvedSpeakerName, resolvedMessage)
    Runtime.HandleRecruitMessage(channelId, resolvedSpeakerName, loweredMessage)
    if leadSettingsChanged then
        RaidManagerUi.SyncLeadWidgets()
    end
end

local function onUpdate(dt)
    if Shared.state.raid_info_refresh_ticker ~= nil and Shared.state.raid_info_refresh_ticker.Run ~= nil then
        Shared.state.raid_info_refresh_ticker:Run(dt, nil, function()
            RaidManagerUi.RefreshRaidInfoOverlay()
        end)
    end
    if Shared.state.auto_invite_cadence_ticker ~= nil and Shared.state.auto_invite_cadence_ticker.Run ~= nil then
        Shared.state.auto_invite_cadence_ticker:Run(dt, nil, function()
            Runtime.RunWhitelistAutoInviteCadence()
        end)
    end
    RaidManagerUi.SyncSettingsPanelVisibility()
end

local function onUiReloaded()
    if not initModules() then
        return
    end
    RaidManagerUi.CreateFloatingButton()
    RaidManagerUi.BuildRaidManagerUi()
end

local function onLoad()
    logModuleErrors()
    if not initModules() then
        return
    end

    Runtime.OnLoad()
    RaidManagerUi.CreateFloatingButton()
    RaidManagerUi.BuildRaidManagerUi()
    Runtime.ApplySavedRole()
    RaidManagerUi.SyncRoleDropdownSelection()

    Shared.state.events = Events.Create({
        logger = logger
    })
    Shared.state.events:OnSafe("raid_role_changed", "raid_role_changed", onRoleChanged)
    Shared.state.events:OnSafe("TEAM_MEMBERS_CHANGED", "TEAM_MEMBERS_CHANGED", onTeamChanged)
    Shared.state.events:OnSafe("CHAT_MESSAGE", "CHAT_MESSAGE", onChatMessage)
    Shared.state.events:OptionalOnSafe("COMMUNITY_CHAT_MESSAGE", "COMMUNITY_CHAT_MESSAGE", onChatMessage)
    Shared.state.events:OnSafe("UPDATE", "UPDATE", onUpdate)
    Shared.state.events:OnSafe("UI_RELOADED", "UI_RELOADED", onUiReloaded)
end

local function onUnload()
    if Shared ~= nil and Shared.state.events ~= nil then
        Shared.state.events:ClearAll()
        Shared.state.events = nil
    end
    if ListManager ~= nil and ListManager.Free ~= nil then
        ListManager.Free()
    end
    if RaidManagerUi ~= nil and RaidManagerUi.Unload ~= nil then
        RaidManagerUi.Unload()
    end
end

addon.OnLoad = onLoad
addon.OnUnload = onUnload
addon.OnSettingToggle = function()
    if not initModules() then
        return
    end
    if Shared.state.widgets.settings_window == nil then
        RaidManagerUi.BuildRaidManagerUi()
    end
    if Shared.state.raid_manager ~= nil then
        RaidManagerUi.ToggleSettingsPanel()
    end
end

return addon
