local api = require("api")
local Core = api._NuziCore or require("nuzi-core/core")

local Log = Core.Log
local Require = Core.Require
local Scheduler = Core.Scheduler
local Settings = Core.Settings

local Shared = {}

local logger = Log.Create("Nuzi Raidtools")

local function loadModule(name)
    local mod, _, errors = Require.Addon("nuzi-raidtools", name)
    if mod ~= nil then
        return mod
    end
    if type(errors) == "table" and #errors > 0 then
        logger:Err("module load failed [" .. tostring(name) .. "]: " .. Require.DescribeErrors(errors))
    end
    return nil
end

local Utils = loadModule("utils") or {}

if type(Utils.FormatName) ~= "function" then
    function Utils.FormatName(name)
        if type(name) ~= "string" then
            return ""
        end
        local text = tostring(name or ""):gsub("^%s*(.-)%s*$", "%1")
        if text == "" then
            return ""
        end
        return string.upper(string.sub(text, 1, 1)) .. string.lower(string.sub(text, 2))
    end
end

Shared.logger = logger

Shared.ADDON = {
    name = "Nuzi Raidtools",
    author = "Nuzi",
    version = "2.0.20",
    desc = "Raid recruitment, auto roles, and lead handoff"
}

Shared.CONSTANTS = {
    ADDON_ID = "nuzi-raidtools",
    TITLE = Shared.ADDON.name,
    VERSION = Shared.ADDON.version,
    SETTINGS_FILE_PATH = "nuzi-raidtools/.data/settings.txt",
    LEGACY_SETTINGS_FILE_PATH = "nuzi-raidtools/settings.txt",
    WHITELISTS_PATH = "nuzi-raidtools/.data/whitelists.txt",
    LEGACY_WHITELISTS_PATH = "nuzi-raidtools/whitelists.txt",
    LEGACY_EXPEDITION_WHITELIST_PATH = "nuzi-raidtools/expedition_whitelist.txt",
    BLACKLIST_PATH = "nuzi-raidtools/.data/blacklist.txt",
    LEGACY_BLACKLIST_PATH = "nuzi-raidtools/blacklist.txt",
    GIVE_LEAD_WHITELIST_PATH = "nuzi-raidtools/.data/give_lead_whitelist.txt",
    LEGACY_GIVE_LEAD_WHITELIST_PATH = "nuzi-raidtools/give_lead_whitelist.txt",
    WHITELIST_AUTO_INVITE_CADENCE_MS = 60000,
    WHITELIST_LOGIN_INVITE_DELAY_MS = 30000,
    LOGIN_INVITE_QUEUE_INTERVAL_MS = 1000,
    EXPEDITION_SYNC_INTERVAL_MS = 120000,
    RAID_INFO_REFRESH_INTERVAL_MS = 500,
    RAID_CHAT_CHANNEL_ID = 5,
    RAID_STOP_AUTO_INVITE_COMMAND = "stop x",
    RAID_MAX_MEMBERS = 50,
    RAID_BUILTIN_SORT_COUNT = 4,
    RAID_GROUP_COUNT = 10,
    RAID_GROUP_SIZE = 5,
    DEFAULT_AUTO_ROLE_SELECTION = 4,
    DEFAULT_AUTOMATION_WHITELIST = "Guild Members",
    LEGACY_EXPEDITION_AUTOMATION_WHITELIST = "Expedition Members",
    ATTACHED_SETTINGS_WIDTH = 392,
    ATTACHED_SETTINGS_HEIGHT = 708,
}

Shared.LOGIN_ANNOUNCEMENT_PATTERNS = {
    "^([%a][%w_%-]+)%s+has%s+logged%s+in%.?$",
    "^([%a][%w_%-]+)%s+logged%s+in%.?$",
    "^([%a][%w_%-]+)%s+has%s+come%s+online%.?$",
    "^([%a][%w_%-]+)%s+is%s+now%s+online%.?$",
}

Shared.DEFAULT_SETTINGS = {
    char_roles = {},
    last_auto_role_selection = false,
    active_whitelist = "Select Whitelist",
    enabled_whitelists = {},
    settings_panel_visible = true,
    recruit_whitelist_enabled = true,
    whitelist_auto_invite = false,
    whitelist_auto_invite_on_login = false,
    whitelist_auto_invite_on_cadence = false,
    guild_auto_learn = false,
    expedition_sync_enabled = false,
    expedition_sync_name = "macro",
    remote_auto_invite_controls = false,
    give_lead_whitelist_enabled = true,
    always_visible = true,
    floating_icon_size = 40,
    floating_button_x = 100,
    floating_button_y = 100,
    filter_selection = 1,
    dms_selection = 1,
    raid_sort_mode = 1,
    raid_sort_preset = "builtin:1",
    raid_custom_sort_presets = {},
    raid_sort_builder_draft = {
        name = "",
        role_order = { 1, 2, 3, 4 },
        role_groups = { 0, 0, 0, 0 },
        slot_roles = {},
        gear_order = 1,
        name_order = 1
    },
    is_recruiting = false,
    last_recruit_message = "",
    lead_sniffing = true,
    lead_code_word = "give lead"
}

Shared.DEFAULT_WHITELISTS = {}
Shared.DEFAULT_BLACKLIST = {}
Shared.DEFAULT_GIVE_LEAD_WHITELIST = {}

Shared.STOCK_MEMBER_ARTIFACT_FIELDS = {
    "ability",
    "levelLabel",
    "level",
    "subName",
    "detailName",
    "title",
    "actability",
    "actabilityLabel",
    "abilityIcon",
    "abilityImg",
    "gradeIcon",
    "ancestralIcon",
    "roleIcon",
    "expedIcon",
}

Shared.TEAM_ROLE_COLORS = {
    defender = { 0.25, 0.86, 0.34, 1 },
    healer = { 1, 0.43, 0.77, 1 },
    attacker = { 1, 0.35, 0.35, 1 },
    undecided = { 0.43, 0.67, 1, 1 }
}

Shared.CLASS_TYPE_COLORS = {
    tank = Shared.TEAM_ROLE_COLORS.defender,
    healer = Shared.TEAM_ROLE_COLORS.healer,
    dps = Shared.TEAM_ROLE_COLORS.attacker
}

Shared.SETTINGS_WINDOW_THEME = {
    title = { 0.98, 0.90, 0.72, 1 },
    heading = { 0.96, 0.88, 0.70, 1 },
    text = { 0.95, 0.93, 0.90, 1 },
    hint = { 0.78, 0.74, 0.68, 1 },
    warning = { 1, 0.45, 0.32, 1 }
}

Shared.state = {
    settings = nil,
    events = nil,
    private_events = nil,
    current_character_key = nil,
    blacklist_lookup = {},
    enabled_whitelist_lookup = {},
    give_lead_whitelist_lookup = {},
    invite_cooldown_by_name = {},
    login_invite_queue = {},
    recruit_message = "",
    raid_manager = nil,
    raid_manager_original_width = nil,
    raid_manager_original_height = nil,
    patched_party_frames = {},
    patched_member_frames = {},
    widgets = {},
    floating_button = nil,
    raid_info_refresh_ticker = Scheduler.CreateTicker({
        interval_ms = Shared.CONSTANTS.RAID_INFO_REFRESH_INTERVAL_MS,
        max_elapsed_ms = Shared.CONSTANTS.RAID_INFO_REFRESH_INTERVAL_MS * 3
    }),
    auto_invite_cadence_ticker = Scheduler.CreateTicker({
        interval_ms = Shared.CONSTANTS.WHITELIST_AUTO_INVITE_CADENCE_MS,
        max_elapsed_ms = Shared.CONSTANTS.WHITELIST_AUTO_INVITE_CADENCE_MS * 2
    }),
    login_invite_queue_ticker = Scheduler.CreateTicker({
        interval_ms = Shared.CONSTANTS.LOGIN_INVITE_QUEUE_INTERVAL_MS,
        max_elapsed_ms = Shared.CONSTANTS.LOGIN_INVITE_QUEUE_INTERVAL_MS * 3
    }),
    expedition_sync_ticker = Scheduler.CreateTicker({
        interval_ms = Shared.CONSTANTS.EXPEDITION_SYNC_INTERVAL_MS,
        max_elapsed_ms = Shared.CONSTANTS.EXPEDITION_SYNC_INTERVAL_MS * 2
    })
}

local saveCallback = nil

function Shared.SetSaveCallback(callback)
    saveCallback = callback
end

function Shared.TrimText(value)
    return tostring(value or ""):gsub("^%s*(.-)%s*$", "%1")
end

function Shared.NormalizeKey(value)
    local text = Shared.TrimText(value)
    if text == "" then
        return ""
    end
    return string.lower(text)
end

function Shared.DeepCopy(value, visited)
    if type(value) ~= "table" then
        return value
    end
    visited = visited or {}
    if visited[value] ~= nil then
        return visited[value]
    end
    local out = {}
    visited[value] = out
    for key, entry in pairs(value) do
        out[Shared.DeepCopy(key, visited)] = Shared.DeepCopy(entry, visited)
    end
    return out
end

function Shared.TableHasEntries(tbl)
    if type(tbl) ~= "table" then
        return false
    end
    for _ in pairs(tbl) do
        return true
    end
    return false
end

function Shared.EnsureDefaults(dst, defaults)
    for key, value in pairs(defaults) do
        if type(value) == "table" then
            if type(dst[key]) ~= "table" then
                dst[key] = Shared.DeepCopy(value)
            else
                Shared.EnsureDefaults(dst[key], value)
            end
        elseif dst[key] == nil then
            dst[key] = value
        end
    end
end

function Shared.NormalizeAutoInviteSettings(settings)
    if type(settings) ~= "table" then
        return
    end
    settings.whitelist_auto_invite = settings.whitelist_auto_invite and true or false
    settings.whitelist_auto_invite_on_login = settings.whitelist_auto_invite_on_login and true or false
    settings.whitelist_auto_invite_on_cadence = settings.whitelist_auto_invite_on_cadence and true or false
    settings.guild_auto_learn = settings.guild_auto_learn and true or false
    settings.expedition_sync_enabled = settings.expedition_sync_enabled and true or false
    settings.remote_auto_invite_controls = settings.remote_auto_invite_controls and true or false
    settings.expedition_sync_name = Shared.TrimText(settings.expedition_sync_name or "macro")
    if settings.expedition_sync_name == "" then
        settings.expedition_sync_name = "macro"
    end
    local iconSize = math.floor((tonumber(settings.floating_icon_size) or 40) + 0.5)
    if iconSize < 32 then
        iconSize = 32
    elseif iconSize > 96 then
        iconSize = 96
    end
    settings.floating_icon_size = iconSize
end

function Shared.NormalizeRaidSortSettings(settings)
    if type(settings) ~= "table" then
        return
    end
    local sortMode = math.floor((tonumber(settings.raid_sort_mode) or 1) + 0.5)
    if sortMode < 1 or sortMode > Shared.CONSTANTS.RAID_BUILTIN_SORT_COUNT then
        sortMode = 1
    end
    settings.raid_sort_mode = sortMode
    local customPresets = {}
    local customPresetCount = 0
    local function normalizeRoleOrder(value)
        local out = {}
        local seen = {}
        if type(value) == "table" then
            for _, role in ipairs(value) do
                role = tonumber(role)
                if role ~= nil and role >= 1 and role <= 4 and not seen[role] then
                    seen[role] = true
                    out[#out + 1] = role
                end
            end
        end
        for role = 1, 4 do
            if not seen[role] then
                out[#out + 1] = role
            end
        end
        return out
    end
    local function normalizeRoleGroups(value)
        local out = {}
        for role = 1, 4 do
            local raw = type(value) == "table" and (value[role] or value[tostring(role)]) or nil
            local group = math.floor((tonumber(raw) or 0) + 0.5)
            if group < 0 then
                group = 0
            elseif group > Shared.CONSTANTS.RAID_GROUP_COUNT then
                group = Shared.CONSTANTS.RAID_GROUP_COUNT
            end
            out[role] = group
        end
        return out
    end
    local function normalizeSlotRoles(value)
        local out = {}
        if type(value) ~= "table" then
            return out
        end
        for slot = 1, Shared.CONSTANTS.RAID_MAX_MEMBERS do
            local raw = value[slot] or value[tostring(slot)]
            local role = math.floor((tonumber(raw) or 0) + 0.5)
            if role >= 1 and role <= 4 then
                out[slot] = role
            end
        end
        return out
    end
    if type(settings.raid_custom_sort_presets) == "table" then
        for key, preset in pairs(settings.raid_custom_sort_presets) do
            if type(preset) == "table" and customPresetCount < 30 then
                local name = Shared.TrimText(preset.name or key)
                if name ~= "" then
                    name = string.sub(name, 1, 32)
                    local presetKey = Shared.NormalizeKey(name)
                    if presetKey ~= "" then
                        local gearOrder = math.floor((tonumber(preset.gear_order) or 1) + 0.5)
                        if gearOrder < 1 or gearOrder > 3 then
                            gearOrder = 1
                        end
                        local nameOrder = math.floor((tonumber(preset.name_order) or 1) + 0.5)
                        if nameOrder < 1 or nameOrder > 3 then
                            nameOrder = 1
                        end
                        customPresets[presetKey] = {
                            name = name,
                            role_order = normalizeRoleOrder(preset.role_order),
                            role_groups = normalizeRoleGroups(preset.role_groups),
                            slot_roles = normalizeSlotRoles(preset.slot_roles),
                            gear_order = gearOrder,
                            name_order = nameOrder
                        }
                        customPresetCount = customPresetCount + 1
                    end
                end
            end
        end
    end
    settings.raid_custom_sort_presets = customPresets
    local draft = type(settings.raid_sort_builder_draft) == "table" and settings.raid_sort_builder_draft or {}
    local draftGearOrder = math.floor((tonumber(draft.gear_order) or 1) + 0.5)
    if draftGearOrder < 1 or draftGearOrder > 3 then
        draftGearOrder = 1
    end
    local draftNameOrder = math.floor((tonumber(draft.name_order) or 1) + 0.5)
    if draftNameOrder < 1 or draftNameOrder > 3 then
        draftNameOrder = 1
    end
    settings.raid_sort_builder_draft = {
        name = string.sub(Shared.TrimText(draft.name or ""), 1, 32),
        role_order = normalizeRoleOrder(draft.role_order),
        role_groups = normalizeRoleGroups(draft.role_groups),
        slot_roles = normalizeSlotRoles(draft.slot_roles),
        gear_order = draftGearOrder,
        name_order = draftNameOrder
    }

    local selectedPreset = Shared.TrimText(settings.raid_sort_preset)
    local builtinMode = tonumber(string.match(selectedPreset, "^builtin:(%d+)$"))
    if builtinMode ~= nil and builtinMode >= 1 and builtinMode <= Shared.CONSTANTS.RAID_BUILTIN_SORT_COUNT then
        settings.raid_sort_mode = math.floor(builtinMode + 0.5)
        settings.raid_sort_preset = "builtin:" .. tostring(settings.raid_sort_mode)
    else
        local customKey = string.match(selectedPreset, "^custom:(.+)$")
        if customKey ~= nil and customPresets[customKey] ~= nil then
            settings.raid_sort_preset = "custom:" .. customKey
        else
            settings.raid_sort_preset = "builtin:" .. tostring(sortMode)
        end
    end

    settings.raid_auto_mark_highest_healer = nil
    settings.raid_auto_mark_tanks = nil
    settings.raid_mark_healer = nil
    settings.raid_mark_tank_1 = nil
    settings.raid_mark_tank_2 = nil
    settings.raid_leader_target_mark_enabled = nil
    settings.raid_leader_target_mark = nil
    settings.raid_assist_marker_enabled = nil
    settings.raid_assist_marker_source_mark = nil
    settings.raid_assist_marker_display_mark = nil
end

function Shared.NormalizeNameList(value)
    if type(value) ~= "table" then
        return nil
    end
    local out = {}
    local seen = {}
    for _, entry in ipairs(value) do
        local formatted = Utils.FormatName(entry)
        local key = Shared.NormalizeKey(formatted)
        if key ~= "" and not seen[key] then
            seen[key] = true
            table.insert(out, formatted)
        end
    end
    return out
end

function Shared.NormalizeWhitelistsTable(value)
    if type(value) ~= "table" then
        return nil
    end
    local out = {}
    local function appendList(listName, names)
        if out[listName] == nil then
            out[listName] = {}
        end
        local seen = {}
        for _, name in ipairs(out[listName]) do
            seen[Shared.NormalizeKey(name)] = true
        end
        for _, name in ipairs(names or {}) do
            local key = Shared.NormalizeKey(name)
            if key ~= "" and not seen[key] then
                seen[key] = true
                table.insert(out[listName], name)
            end
        end
    end
    for key, list in pairs(value) do
        local listName = Shared.TrimText(key)
        if listName ~= "" then
            if listName == Shared.CONSTANTS.LEGACY_EXPEDITION_AUTOMATION_WHITELIST then
                listName = Shared.CONSTANTS.DEFAULT_AUTOMATION_WHITELIST
            end
            appendList(listName, Shared.NormalizeNameList(list) or {})
        end
    end
    return out
end

function Shared.ReplaceTableContents(target, replacement)
    if type(target) ~= "table" then
        return
    end
    for key in pairs(target) do
        target[key] = nil
    end
    for key, value in pairs(replacement or {}) do
        target[key] = value
    end
end

function Shared.ParseCommaList(text, formatter)
    local out = {}
    local seen = {}
    for entry in string.gmatch(tostring(text or ""), "([^,]+)") do
        local value = Shared.TrimText(entry)
        if formatter ~= nil then
            value = formatter(value)
        end
        if value ~= "" then
            local key = Shared.NormalizeKey(value)
            if key ~= "" and not seen[key] then
                seen[key] = true
                table.insert(out, value)
            end
        end
    end
    return out
end

function Shared.JoinCommaList(items)
    if type(items) ~= "table" then
        return ""
    end
    return table.concat(items, ", ")
end

local function readLegacyTable(path)
    local parsed = Settings.ReadFlexibleTable(path, {
        mode = "serialized_then_flat",
        raw_text_fallback = true
    })
    if type(parsed) == "table" then
        return parsed
    end
    return nil
end

local function importLegacyExpeditionWhitelist(settings)
    if type(settings) ~= "table" then
        return false
    end
    local legacyList = Shared.NormalizeNameList(readLegacyTable(Shared.CONSTANTS.LEGACY_EXPEDITION_WHITELIST_PATH))
    if type(legacyList) ~= "table" or #legacyList == 0 then
        return false
    end
    local existing = Shared.NormalizeNameList(settings.expedition)
    if type(existing) == "table" and #existing > 0 then
        return false
    end
    settings.expedition = legacyList
    return true
end

local MainStore = Settings.CreateAddonStore({
    ADDON_ID = Shared.CONSTANTS.ADDON_ID,
    ADDON_NAME = Shared.ADDON.name,
    SETTINGS_FILE_PATH = Shared.CONSTANTS.SETTINGS_FILE_PATH,
    LEGACY_SETTINGS_FILE_PATH = Shared.CONSTANTS.LEGACY_SETTINGS_FILE_PATH,
    DEFAULT_SETTINGS = Shared.DEFAULT_SETTINGS
}, {
    prune_unknown = true,
    skip_empty_default_tables = true,
    read_mode = "serialized_then_flat",
    write_mode = "serialized_then_flat",
    read_raw_text_fallback = true,
    normalize = function(settings)
        Shared.EnsureDefaults(settings, Shared.DEFAULT_SETTINGS)
        if type(settings.char_roles) ~= "table" then
            settings.char_roles = {}
        end
        local lastAutoRoleSelection = tonumber(settings.last_auto_role_selection)
        if lastAutoRoleSelection == 0 then
            lastAutoRoleSelection = Shared.CONSTANTS.DEFAULT_AUTO_ROLE_SELECTION
        end
        if lastAutoRoleSelection == 1
            or lastAutoRoleSelection == 2
            or lastAutoRoleSelection == 3
            or lastAutoRoleSelection == 4 then
            settings.last_auto_role_selection = lastAutoRoleSelection
        else
            settings.last_auto_role_selection = false
        end
        if type(settings.enabled_whitelists) ~= "table" then
            settings.enabled_whitelists = {}
        end
        Shared.NormalizeAutoInviteSettings(settings)
        Shared.NormalizeRaidSortSettings(settings)
        settings.lead_code_word = Shared.TrimText(settings.lead_code_word or "give lead")
        if settings.lead_code_word == "" then
            settings.lead_code_word = "give lead"
        end
        if not Shared.TableHasEntries(settings.enabled_whitelists) then
            local selected = tostring(settings.active_whitelist or "")
            if selected ~= "" and selected ~= "Select Whitelist" then
                settings.enabled_whitelists[Shared.NormalizeKey(selected)] = true
            end
        end
    end
})

local function createSidecarStore(path, legacyPath, defaults, label, normalize)
    return Settings.CreateSidecarStore({
        settings_file_path = path,
        legacy_settings_file_path = legacyPath,
        defaults = Shared.DeepCopy(defaults or {}),
        log_name = Shared.ADDON.name .. "/" .. tostring(label or "Data"),
        use_api_settings = false,
        save_global_settings = false,
        read_mode = "serialized_then_flat",
        write_mode = "serialized_then_flat",
        read_raw_text_fallback = true,
        normalize = normalize
    })
end

local WhitelistStore = createSidecarStore(
    Shared.CONSTANTS.WHITELISTS_PATH,
    Shared.CONSTANTS.LEGACY_WHITELISTS_PATH,
    Shared.DEFAULT_WHITELISTS,
    "Whitelists",
    function(settings)
        Shared.ReplaceTableContents(settings, Shared.NormalizeWhitelistsTable(settings) or {})
    end
)

local BlacklistStore = createSidecarStore(
    Shared.CONSTANTS.BLACKLIST_PATH,
    Shared.CONSTANTS.LEGACY_BLACKLIST_PATH,
    Shared.DEFAULT_BLACKLIST,
    "Blacklist",
    function(settings)
        Shared.ReplaceTableContents(settings, Shared.NormalizeNameList(settings) or {})
    end
)

local GiveLeadWhitelistStore = createSidecarStore(
    Shared.CONSTANTS.GIVE_LEAD_WHITELIST_PATH,
    Shared.CONSTANTS.LEGACY_GIVE_LEAD_WHITELIST_PATH,
    Shared.DEFAULT_GIVE_LEAD_WHITELIST,
    "GiveLeadWhitelist",
    function(settings)
        Shared.ReplaceTableContents(settings, Shared.NormalizeNameList(settings) or {})
    end
)

local function buildSettingsPayload(settings)
    local lastAutoRoleSelection = tonumber(settings.last_auto_role_selection)
    if lastAutoRoleSelection == 0 then
        lastAutoRoleSelection = Shared.CONSTANTS.DEFAULT_AUTO_ROLE_SELECTION
    end
    if lastAutoRoleSelection ~= 1
        and lastAutoRoleSelection ~= 2
        and lastAutoRoleSelection ~= 3
        and lastAutoRoleSelection ~= 4 then
        lastAutoRoleSelection = false
    end
    return {
        char_roles = Shared.DeepCopy(settings.char_roles or {}),
        last_auto_role_selection = lastAutoRoleSelection,
        active_whitelist = tostring(settings.active_whitelist or "Select Whitelist"),
        enabled_whitelists = Shared.DeepCopy(settings.enabled_whitelists or {}),
        settings_panel_visible = settings.settings_panel_visible ~= false,
        recruit_whitelist_enabled = settings.recruit_whitelist_enabled and true or false,
        whitelist_auto_invite = settings.whitelist_auto_invite and true or false,
        whitelist_auto_invite_on_login = settings.whitelist_auto_invite_on_login and true or false,
        whitelist_auto_invite_on_cadence = settings.whitelist_auto_invite_on_cadence and true or false,
        guild_auto_learn = settings.guild_auto_learn and true or false,
        expedition_sync_enabled = settings.expedition_sync_enabled and true or false,
        expedition_sync_name = Shared.TrimText(settings.expedition_sync_name or "macro"),
        remote_auto_invite_controls = settings.remote_auto_invite_controls and true or false,
        give_lead_whitelist_enabled = settings.give_lead_whitelist_enabled and true or false,
        always_visible = settings.always_visible and true or false,
        floating_icon_size = tonumber(settings.floating_icon_size) or 40,
        floating_button_x = tonumber(settings.floating_button_x) or 100,
        floating_button_y = tonumber(settings.floating_button_y) or 100,
        filter_selection = tonumber(settings.filter_selection) or 1,
        dms_selection = tonumber(settings.dms_selection) or 1,
        raid_sort_mode = tonumber(settings.raid_sort_mode) or 1,
        raid_sort_preset = Shared.TrimText(settings.raid_sort_preset or "builtin:1"),
        raid_custom_sort_presets = Shared.DeepCopy(settings.raid_custom_sort_presets or {}),
        raid_sort_builder_draft = Shared.DeepCopy(settings.raid_sort_builder_draft or {}),
        is_recruiting = settings.is_recruiting and true or false,
        last_recruit_message = tostring(settings.last_recruit_message or ""),
        lead_sniffing = settings.lead_sniffing and true or false,
        lead_code_word = Shared.TrimText(settings.lead_code_word or "give lead")
    }
end

function Shared.SaveSettings()
    if Shared.state.settings == nil then
        return
    end
    Shared.state.settings.whitelists = Shared.NormalizeWhitelistsTable(Shared.state.settings.whitelists) or {}
    Shared.state.settings.blacklist = Shared.NormalizeNameList(Shared.state.settings.blacklist) or {}
    Shared.state.settings.give_lead_whitelist = Shared.NormalizeNameList(Shared.state.settings.give_lead_whitelist) or {}
    Shared.NormalizeAutoInviteSettings(Shared.state.settings)
    Shared.NormalizeRaidSortSettings(Shared.state.settings)

    MainStore.settings = buildSettingsPayload(Shared.state.settings)
    WhitelistStore.settings = Shared.state.settings.whitelists
    BlacklistStore.settings = Shared.state.settings.blacklist
    GiveLeadWhitelistStore.settings = Shared.state.settings.give_lead_whitelist

    local whitelistsOk = WhitelistStore:Save()
    local blacklistOk = BlacklistStore:Save()
    local giveLeadWhitelistOk = GiveLeadWhitelistStore:Save()
    local mainOk = MainStore:Save()

    if type(saveCallback) == "function" then
        saveCallback()
    end

    return whitelistsOk and blacklistOk and giveLeadWhitelistOk and mainOk
end

function Shared.GetSettings()
    if type(Shared.state.settings) ~= "table" then
        local migrated = false
        local mainSettings, mainMeta = MainStore:Ensure()
        local whitelists, whitelistsMeta = WhitelistStore:Ensure()
        local blacklist, blacklistMeta = BlacklistStore:Ensure()
        local giveLeadWhitelist, giveLeadWhitelistMeta = GiveLeadWhitelistStore:Ensure()

        Shared.state.settings = Shared.DeepCopy(mainSettings or {})
        Shared.EnsureDefaults(Shared.state.settings, Shared.DEFAULT_SETTINGS)
        if type(Shared.state.settings.char_roles) ~= "table" then
            Shared.state.settings.char_roles = {}
        end
        if type(Shared.state.settings.enabled_whitelists) ~= "table" then
            Shared.state.settings.enabled_whitelists = {}
        end
        Shared.NormalizeAutoInviteSettings(Shared.state.settings)
        Shared.NormalizeRaidSortSettings(Shared.state.settings)
        Shared.state.settings.whitelists = Shared.NormalizeWhitelistsTable(whitelists) or Shared.DeepCopy(Shared.DEFAULT_WHITELISTS)
        Shared.state.settings.blacklist = Shared.NormalizeNameList(blacklist) or Shared.DeepCopy(Shared.DEFAULT_BLACKLIST)
        Shared.state.settings.give_lead_whitelist = Shared.NormalizeNameList(giveLeadWhitelist) or Shared.DeepCopy(Shared.DEFAULT_GIVE_LEAD_WHITELIST)
        Shared.state.settings.lead_code_word = Shared.TrimText(Shared.state.settings.lead_code_word or "give lead")
        if Shared.state.settings.lead_code_word == "" then
            Shared.state.settings.lead_code_word = "give lead"
        end

        if type(mainMeta) == "table" and mainMeta.migrated then
            migrated = true
        end
        if type(whitelistsMeta) == "table" and whitelistsMeta.migrated then
            migrated = true
        end
        if type(blacklistMeta) == "table" and blacklistMeta.migrated then
            migrated = true
        end
        if type(giveLeadWhitelistMeta) == "table" and giveLeadWhitelistMeta.migrated then
            migrated = true
        end
        if importLegacyExpeditionWhitelist(Shared.state.settings.whitelists) then
            migrated = true
        end
        if not Shared.TableHasEntries(Shared.state.settings.enabled_whitelists) then
            local selected = tostring(Shared.state.settings.active_whitelist or "")
            if selected ~= "" and selected ~= "Select Whitelist" then
                Shared.state.settings.enabled_whitelists[Shared.NormalizeKey(selected)] = true
            end
        end
        if migrated then
            Shared.SaveSettings()
        end
        return Shared.state.settings
    end

    Shared.EnsureDefaults(Shared.state.settings, Shared.DEFAULT_SETTINGS)
    if type(Shared.state.settings.char_roles) ~= "table" then
        Shared.state.settings.char_roles = {}
    end
    if type(Shared.state.settings.enabled_whitelists) ~= "table" then
        Shared.state.settings.enabled_whitelists = {}
    end
    Shared.NormalizeAutoInviteSettings(Shared.state.settings)
    Shared.NormalizeRaidSortSettings(Shared.state.settings)
    Shared.state.settings.whitelists = Shared.NormalizeWhitelistsTable(Shared.state.settings.whitelists) or Shared.DeepCopy(Shared.DEFAULT_WHITELISTS)
    Shared.state.settings.blacklist = Shared.NormalizeNameList(Shared.state.settings.blacklist) or Shared.DeepCopy(Shared.DEFAULT_BLACKLIST)
    Shared.state.settings.give_lead_whitelist = Shared.NormalizeNameList(Shared.state.settings.give_lead_whitelist) or Shared.DeepCopy(Shared.DEFAULT_GIVE_LEAD_WHITELIST)
    Shared.state.settings.lead_code_word = Shared.TrimText(Shared.state.settings.lead_code_word or "give lead")
    if Shared.state.settings.lead_code_word == "" then
        Shared.state.settings.lead_code_word = "give lead"
    end
    if not Shared.TableHasEntries(Shared.state.settings.enabled_whitelists) then
        local selected = tostring(Shared.state.settings.active_whitelist or "")
        if selected ~= "" and selected ~= "Select Whitelist" then
            Shared.state.settings.enabled_whitelists[Shared.NormalizeKey(selected)] = true
        end
    end
    return Shared.state.settings
end

return Shared
