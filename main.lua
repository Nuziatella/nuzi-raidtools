local api = require("api")
local Core = api._NuziCore or require("nuzi-core/core")
local Require = Core.Require
local Log = Core.Log
local Events = Core.Events
local Settings = Core.Settings
local Positioning = Core.UI.Positioning

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

local Utils = loadModule("utils")
local ListManager = loadModule("list_manager")

local addon = {
    name = "Nuzi Raidtools",
    author = "Nuzi",
    version = "1.0.1",
    desc = "Raid recruitment, auto roles, and lead handoff"
}

local SETTINGS_PATH = "nuzi-raidtools/.data/settings.txt"
local LEGACY_SETTINGS_PATH = "nuzi-raidtools/settings.txt"
local WHITELISTS_PATH = "nuzi-raidtools/.data/whitelists.txt"
local LEGACY_WHITELISTS_PATH = "nuzi-raidtools/whitelists.txt"
local LEGACY_EXPEDITION_WHITELIST_PATH = "nuzi-raidtools/expedition_whitelist.txt"
local BLACKLIST_PATH = "nuzi-raidtools/.data/blacklist.txt"
local LEGACY_BLACKLIST_PATH = "nuzi-raidtools/blacklist.txt"
local GIVE_LEAD_WHITELIST_PATH = "nuzi-raidtools/.data/give_lead_whitelist.txt"
local LEGACY_GIVE_LEAD_WHITELIST_PATH = "nuzi-raidtools/give_lead_whitelist.txt"

local DEFAULT_SETTINGS = {
    char_roles = {},
    active_whitelist = "Select Whitelist",
    enabled_whitelists = {},
    recruit_whitelist_enabled = true,
    whitelist_auto_invite = false,
    give_lead_whitelist_enabled = true,
    always_visible = true,
    floating_button_x = 100,
    floating_button_y = 100,
    filter_selection = 1,
    dms_selection = 1,
    is_recruiting = false,
    last_recruit_message = "",
    lead_sniffing = true,
    lead_code_word = "give lead"
}

local DEFAULT_WHITELISTS = {}
local DEFAULT_BLACKLIST = {}
local DEFAULT_GIVE_LEAD_WHITELIST = {}

local State = {
    settings = nil,
    events = nil,
    blacklist_lookup = {},
    enabled_whitelist_lookup = {},
    give_lead_whitelist_lookup = {},
    invite_cooldown_by_name = {},
    recruit_message = "",
    raid_manager = nil,
    raid_manager_original_width = nil,
    raid_manager_original_height = nil,
    patched_party_frames = {},
    patched_member_frames = {},
    widgets = {},
    floating_button = nil
}

local function trimText(value)
    return tostring(value or ""):gsub("^%s*(.-)%s*$", "%1")
end

local function normalizeKey(value)
    local text = trimText(value)
    if text == "" then
        return ""
    end
    return string.lower(text)
end

local function deepCopy(value, visited)
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
        out[deepCopy(key, visited)] = deepCopy(entry, visited)
    end
    return out
end

local function tableHasEntries(tbl)
    if type(tbl) ~= "table" then
        return false
    end
    for _, _ in pairs(tbl) do
        return true
    end
    return false
end

local function ensureDefaults(dst, defaults)
    for key, value in pairs(defaults) do
        if type(value) == "table" then
            if type(dst[key]) ~= "table" then
                dst[key] = deepCopy(value)
            else
                ensureDefaults(dst[key], value)
            end
        elseif dst[key] == nil then
            dst[key] = value
        end
    end
end

local function normalizeNameList(value)
    if type(value) ~= "table" then
        return nil
    end
    local out = {}
    local seen = {}
    for _, entry in ipairs(value) do
        local formatted = Utils.FormatName(entry)
        local key = normalizeKey(formatted)
        if key ~= "" and not seen[key] then
            seen[key] = true
            table.insert(out, formatted)
        end
    end
    return out
end

local function normalizeWhitelistsTable(value)
    if type(value) ~= "table" then
        return nil
    end
    local out = {}
    for key, list in pairs(value) do
        local listName = trimText(key)
        if listName ~= "" then
            out[listName] = normalizeNameList(list) or {}
        end
    end
    return out
end

local function replaceTableContents(target, replacement)
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
    local legacyList = normalizeNameList(readLegacyTable(LEGACY_EXPEDITION_WHITELIST_PATH))
    if type(legacyList) ~= "table" or #legacyList == 0 then
        return false
    end
    local existing = normalizeNameList(settings.expedition)
    if type(existing) == "table" and #existing > 0 then
        return false
    end
    settings.expedition = legacyList
    return true
end

local MainStore = Settings.CreateAddonStore({
    ADDON_ID = "nuzi-raidtools",
    ADDON_NAME = addon.name,
    SETTINGS_FILE_PATH = SETTINGS_PATH,
    LEGACY_SETTINGS_FILE_PATH = LEGACY_SETTINGS_PATH,
    DEFAULT_SETTINGS = DEFAULT_SETTINGS
}, {
    prune_unknown = true,
    read_mode = "serialized_then_flat",
    write_mode = "serialized_then_flat",
    read_raw_text_fallback = true,
    write_mirror_paths = { LEGACY_SETTINGS_PATH },
    normalize = function(settings)
        ensureDefaults(settings, DEFAULT_SETTINGS)
        if type(settings.char_roles) ~= "table" then
            settings.char_roles = {}
        end
        if type(settings.enabled_whitelists) ~= "table" then
            settings.enabled_whitelists = {}
        end
        settings.lead_code_word = trimText(settings.lead_code_word or "give lead")
        if settings.lead_code_word == "" then
            settings.lead_code_word = "give lead"
        end
        if not tableHasEntries(settings.enabled_whitelists) then
            local selected = tostring(settings.active_whitelist or "")
            if selected ~= "" and selected ~= "Select Whitelist" then
                settings.enabled_whitelists[normalizeKey(selected)] = true
            end
        end
    end
})

local function createSidecarStore(path, legacyPath, defaults, label, normalize)
    return Settings.CreateSidecarStore({
        settings_file_path = path,
        legacy_settings_file_path = legacyPath,
        defaults = deepCopy(defaults or {}),
        log_name = addon.name .. "/" .. tostring(label or "Data"),
        use_api_settings = false,
        save_global_settings = false,
        read_mode = "serialized_then_flat",
        write_mode = "serialized_then_flat",
        read_raw_text_fallback = true,
        write_mirror_paths = { legacyPath },
        normalize = normalize
    })
end

local WhitelistStore = createSidecarStore(
    WHITELISTS_PATH,
    LEGACY_WHITELISTS_PATH,
    DEFAULT_WHITELISTS,
    "Whitelists",
    function(settings)
        replaceTableContents(settings, normalizeWhitelistsTable(settings) or {})
    end
)

local BlacklistStore = createSidecarStore(
    BLACKLIST_PATH,
    LEGACY_BLACKLIST_PATH,
    DEFAULT_BLACKLIST,
    "Blacklist",
    function(settings)
        replaceTableContents(settings, normalizeNameList(settings) or {})
    end
)

local GiveLeadWhitelistStore = createSidecarStore(
    GIVE_LEAD_WHITELIST_PATH,
    LEGACY_GIVE_LEAD_WHITELIST_PATH,
    DEFAULT_GIVE_LEAD_WHITELIST,
    "GiveLeadWhitelist",
    function(settings)
        replaceTableContents(settings, normalizeNameList(settings) or {})
    end
)

local function buildSettingsPayload(settings)
    return {
        char_roles = deepCopy(settings.char_roles or {}),
        active_whitelist = tostring(settings.active_whitelist or "Select Whitelist"),
        enabled_whitelists = deepCopy(settings.enabled_whitelists or {}),
        recruit_whitelist_enabled = settings.recruit_whitelist_enabled and true or false,
        whitelist_auto_invite = settings.whitelist_auto_invite and true or false,
        give_lead_whitelist_enabled = settings.give_lead_whitelist_enabled and true or false,
        always_visible = settings.always_visible and true or false,
        floating_button_x = tonumber(settings.floating_button_x) or 100,
        floating_button_y = tonumber(settings.floating_button_y) or 100,
        filter_selection = tonumber(settings.filter_selection) or 1,
        dms_selection = tonumber(settings.dms_selection) or 1,
        is_recruiting = settings.is_recruiting and true or false,
        last_recruit_message = tostring(settings.last_recruit_message or ""),
        lead_sniffing = settings.lead_sniffing and true or false,
        lead_code_word = trimText(settings.lead_code_word or "give lead")
    }
end

local function saveSettings()
    if State.settings == nil then
        return
    end
    State.settings.whitelists = normalizeWhitelistsTable(State.settings.whitelists) or {}
    State.settings.blacklist = normalizeNameList(State.settings.blacklist) or {}
    State.settings.give_lead_whitelist = normalizeNameList(State.settings.give_lead_whitelist) or {}

    MainStore.settings = buildSettingsPayload(State.settings)
    WhitelistStore.settings = State.settings.whitelists
    BlacklistStore.settings = State.settings.blacklist
    GiveLeadWhitelistStore.settings = State.settings.give_lead_whitelist

    MainStore:Save()
    WhitelistStore:Save()
    BlacklistStore:Save()
    GiveLeadWhitelistStore:Save()
end

local function getSettings()
    if type(State.settings) ~= "table" then
        local migrated = false
        local mainSettings, mainMeta = MainStore:Ensure()
        local whitelists, whitelistsMeta = WhitelistStore:Ensure()
        local blacklist, blacklistMeta = BlacklistStore:Ensure()
        local giveLeadWhitelist, giveLeadWhitelistMeta = GiveLeadWhitelistStore:Ensure()

        State.settings = deepCopy(mainSettings or {})
        ensureDefaults(State.settings, DEFAULT_SETTINGS)
        if type(State.settings.char_roles) ~= "table" then
            State.settings.char_roles = {}
        end
        if type(State.settings.enabled_whitelists) ~= "table" then
            State.settings.enabled_whitelists = {}
        end
        State.settings.whitelists = normalizeWhitelistsTable(whitelists) or deepCopy(DEFAULT_WHITELISTS)
        State.settings.blacklist = normalizeNameList(blacklist) or deepCopy(DEFAULT_BLACKLIST)
        State.settings.give_lead_whitelist = normalizeNameList(giveLeadWhitelist) or deepCopy(DEFAULT_GIVE_LEAD_WHITELIST)
        State.settings.lead_code_word = trimText(State.settings.lead_code_word or "give lead")
        if State.settings.lead_code_word == "" then
            State.settings.lead_code_word = "give lead"
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
        if importLegacyExpeditionWhitelist(State.settings.whitelists) then
            migrated = true
        end
        if not tableHasEntries(State.settings.enabled_whitelists) then
            local selected = tostring(State.settings.active_whitelist or "")
            if selected ~= "" and selected ~= "Select Whitelist" then
                State.settings.enabled_whitelists[normalizeKey(selected)] = true
            end
        end
        if migrated then
            saveSettings()
        end
        return State.settings
    end
    ensureDefaults(State.settings, DEFAULT_SETTINGS)
    if type(State.settings.char_roles) ~= "table" then
        State.settings.char_roles = {}
    end
    if type(State.settings.enabled_whitelists) ~= "table" then
        State.settings.enabled_whitelists = {}
    end
    State.settings.whitelists = normalizeWhitelistsTable(State.settings.whitelists) or deepCopy(DEFAULT_WHITELISTS)
    State.settings.blacklist = normalizeNameList(State.settings.blacklist) or deepCopy(DEFAULT_BLACKLIST)
    State.settings.give_lead_whitelist = normalizeNameList(State.settings.give_lead_whitelist) or deepCopy(DEFAULT_GIVE_LEAD_WHITELIST)
    State.settings.lead_code_word = trimText(State.settings.lead_code_word or "give lead")
    if State.settings.lead_code_word == "" then
        State.settings.lead_code_word = "give lead"
    end
    if not tableHasEntries(State.settings.enabled_whitelists) then
        local selected = tostring(State.settings.active_whitelist or "")
        if selected ~= "" and selected ~= "Select Whitelist" then
            State.settings.enabled_whitelists[normalizeKey(selected)] = true
        end
    end
    return State.settings
end

local function parseCommaList(text, formatter)
    local out = {}
    local seen = {}
    for entry in string.gmatch(tostring(text or ""), "([^,]+)") do
        local value = trimText(entry)
        if formatter ~= nil then
            value = formatter(value)
        end
        if value ~= "" then
            local key = normalizeKey(value)
            if key ~= "" and not seen[key] then
                seen[key] = true
                table.insert(out, value)
            end
        end
    end
    return out
end

local function joinCommaList(items)
    if type(items) ~= "table" then
        return ""
    end
    return table.concat(items, ", ")
end

local function safeSetText(widget, text)
    if widget == nil or widget.SetText == nil then
        return
    end
    widget:SetText(tostring(text or ""))
end

local function safeShow(widget, visible)
    if widget ~= nil and widget.Show ~= nil then
        widget:Show(visible and true or false)
    end
end

local function safeRemoveAllAnchors(widget)
    if widget ~= nil and widget.RemoveAllAnchors ~= nil then
        widget:RemoveAllAnchors()
    end
end

local function safeAddAnchor(widget, anchor, target, relativeAnchor, x, y)
    if widget == nil or widget.AddAnchor == nil then
        return
    end
    if relativeAnchor ~= nil then
        widget:AddAnchor(anchor, target, relativeAnchor, x or 0, y or 0)
    else
        widget:AddAnchor(anchor, target, x or 0, y or 0)
    end
end

local function extractGearScoreFromInfo(info)
    if type(info) ~= "table" then
        return nil
    end
    local value = tonumber(
        info.gearScore
        or info.gearscore
        or info.gear_score
        or info.gs
        or info.unitGearScore
        or info.unit_gear_score
    )
    if value == nil or value <= 0 then
        return nil
    end
    return math.floor(value + 0.5)
end

local function getRaidUnitContext(unitToken)
    local info = nil
    local unitId = nil
    local infoById = nil

    if api.Unit ~= nil and api.Unit.UnitInfo ~= nil then
        pcall(function()
            info = api.Unit:UnitInfo(unitToken)
        end)
    end
    if api.Unit ~= nil and api.Unit.GetUnitId ~= nil then
        pcall(function()
            unitId = api.Unit:GetUnitId(unitToken)
        end)
    end
    if unitId ~= nil and unitId ~= "" and api.Unit ~= nil and api.Unit.GetUnitInfoById ~= nil then
        pcall(function()
            infoById = api.Unit:GetUnitInfoById(unitId)
        end)
    end
    return info, unitId, infoById
end

local function getRaidUnitClass(unitToken, info, infoById)
    local className = trimText(
        (type(info) == "table" and (info.className or info.class_name or info.unitClass or info.unit_class or info.jobName or info.job_name))
        or (type(infoById) == "table" and (infoById.className or infoById.class_name or infoById.unitClass or infoById.unit_class or infoById.jobName or infoById.job_name))
        or ""
    )
    if className ~= "" then
        return className
    end

    if api.Unit ~= nil and api.Unit.GetUnitClassName ~= nil then
        local ok, value = pcall(function()
            return api.Unit:GetUnitClassName(unitToken)
        end)
        value = trimText(value)
        if ok and value ~= "" then
            return value
        end
    end

    if api.Ability ~= nil and api.Ability.GetUnitClassName ~= nil then
        local ok, value = pcall(function()
            return api.Ability:GetUnitClassName(unitToken)
        end)
        value = trimText(value)
        if ok and value ~= "" then
            return value
        end
    end

    if api.Unit ~= nil and api.Unit.UnitClass ~= nil then
        local okClass, classId = pcall(function()
            return api.Unit:UnitClass(unitToken)
        end)
        if okClass and classId ~= nil and api.Unit.GetUnitClassName ~= nil then
            local okName, value = pcall(function()
                return api.Unit:GetUnitClassName(classId)
            end)
            value = trimText(value)
            if okName and value ~= "" then
                return value
            end
        end
        if okClass then
            return trimText(classId)
        end
    end

    return ""
end

local function getRaidUnitGearScore(unitToken, info, infoById)
    local value = extractGearScoreFromInfo(info) or extractGearScoreFromInfo(infoById)
    if value ~= nil then
        return value
    end
    if api.Unit ~= nil and api.Unit.UnitGearScore ~= nil then
        local ok, result = pcall(function()
            return api.Unit:UnitGearScore(unitToken)
        end)
        result = tonumber(result)
        if ok and result ~= nil and result > 0 then
            return math.floor(result + 0.5)
        end
    end
    return nil
end

local CLASS_ABBREVIATIONS = {
    Abolisher = "Abol",
    Archery = "Arch",
    Assassin = "Asn",
    Battlerage = "Batt",
    Bloodreaver = "Blood",
    Cleric = "Clrc",
    Darkrunner = "DR",
    Daggerspell = "DSp",
    Defiler = "Def",
    Doombringer = "Doom",
    Ebonsong = "Ebon",
    Enigmatist = "Enig",
    Executioner = "Exec",
    Fanatic = "Fan",
    Hierophant = "Hier",
    Primeval = "Prm",
    Skullknight = "Skul",
    Shadowblade = "SBl",
    Spellsinger = "Sng",
    Stonearrow = "Stn",
}

local function abbreviateClassName(className)
    className = trimText(className)
    if className == "" then
        return "-"
    end
    local mapped = CLASS_ABBREVIATIONS[className]
    if mapped ~= nil then
        return mapped
    end
    if #className <= 5 then
        return className
    end
    local initials = {}
    for part in string.gmatch(className, "[A-Z]?[a-z]+") do
        initials[#initials + 1] = string.sub(part, 1, 1)
        if #initials >= 3 then
            break
        end
    end
    if #initials >= 2 then
        return table.concat(initials, "")
    end
    return string.sub(className, 1, 4)
end

local function configureStockLabel(label, width, align, rgba)
    if type(label) ~= "table" then
        return
    end
    if label.SetAutoResize ~= nil then
        label:SetAutoResize(false)
    end
    if label.SetExtent ~= nil then
        label:SetExtent(width, 16)
    elseif label.SetWidth ~= nil then
        label:SetWidth(width)
    end
    if label.SetLimitWidth ~= nil then
        label:SetLimitWidth(width)
    end
    if label.style ~= nil then
        if label.style.SetAlign ~= nil then
            label.style:SetAlign(align)
        end
        if label.style.SetFontSize ~= nil then
            label.style:SetFontSize(11)
        end
        if rgba ~= nil and label.style.SetColor ~= nil then
            label.style:SetColor(rgba[1], rgba[2], rgba[3], rgba[4])
        end
    end
end

local function layoutStockMemberLabels(memberFrame, classLabel)
    if type(memberFrame) ~= "table" then
        return
    end
    local rowWidth = 140
    if memberFrame.GetWidth ~= nil then
        rowWidth = tonumber(memberFrame:GetWidth()) or rowWidth
    end
    rowWidth = math.max(120, rowWidth)
    local gsWidth = 42
    local classWidth = math.max(34, math.min(58, math.floor(rowWidth * 0.26)))
    local nameWidth = math.max(48, rowWidth - gsWidth - classWidth - 18)
    local nameLabel = type(memberFrame.name) == "table" and memberFrame.name or nil
    local gsLabel = type(memberFrame.levelLabel) == "table" and memberFrame.levelLabel or nil
    local classTextLabel = type(classLabel) == "table" and classLabel or nil

    if nameLabel ~= nil then
        configureStockLabel(nameLabel, nameWidth, ALIGN.LEFT, { 1, 1, 1, 1 })
        safeRemoveAllAnchors(nameLabel)
        safeAddAnchor(nameLabel, "TOPLEFT", memberFrame, nil, 4, 0)
        safeShow(nameLabel, true)
    end

    if gsLabel ~= nil then
        configureStockLabel(gsLabel, gsWidth, ALIGN.RIGHT, { 0.95, 0.84, 0.46, 1 })
        safeRemoveAllAnchors(gsLabel)
        safeAddAnchor(gsLabel, "TOPRIGHT", memberFrame, nil, -2, 0)
        safeShow(gsLabel, true)
    end

    if classTextLabel ~= nil then
        configureStockLabel(classTextLabel, classWidth, ALIGN.CENTER, { 0.84, 0.9, 1, 1 })
        safeRemoveAllAnchors(classTextLabel)
        if gsLabel ~= nil then
            safeAddAnchor(classTextLabel, "RIGHT", gsLabel, "LEFT", -4, 0)
        else
            safeAddAnchor(classTextLabel, "TOPRIGHT", memberFrame, nil, -(gsWidth + 6), 0)
        end
        safeShow(classTextLabel, true)
    end

    if type(memberFrame.offlineLabel) == "table" then
        configureStockLabel(memberFrame.offlineLabel, nameWidth, ALIGN.LEFT, { 1, 0.45, 0.45, 1 })
        safeRemoveAllAnchors(memberFrame.offlineLabel)
        safeAddAnchor(memberFrame.offlineLabel, "TOPLEFT", memberFrame, nil, 4, 0)
    end
end

local function ensureStockMemberClassLabel(memberFrame)
    local label = nil
    if type(memberFrame.ability) == "table" then
        label = memberFrame.ability
    elseif memberFrame.__nuzi_class_label ~= nil then
        label = memberFrame.__nuzi_class_label
    else
        label = memberFrame:CreateChildWidget(
            "label",
            "nuziRaidtoolsClassLabel" .. tostring(memberFrame.party or 0) .. "_" .. tostring(memberFrame.memberIndex or memberFrame.slot or 0),
            0,
            true
        )
        memberFrame.__nuzi_class_label = label
    end
    layoutStockMemberLabels(memberFrame, label)
    return label
end

local function applyStockMemberText(memberFrame)
    if type(memberFrame) ~= "table" then
        return
    end
    local unitToken = trimText(memberFrame.target)
    if unitToken == "" then
        return
    end

    local info, _, infoById = getRaidUnitContext(unitToken)
    local className = getRaidUnitClass(unitToken, info, infoById)
    local gearscore = getRaidUnitGearScore(unitToken, info, infoById)

    local classLabel = ensureStockMemberClassLabel(memberFrame)
    if classLabel ~= nil then
        safeSetText(classLabel, abbreviateClassName(className))
        safeShow(classLabel, true)
    end

    if type(memberFrame.levelLabel) == "table" then
        safeSetText(memberFrame.levelLabel, gearscore ~= nil and tostring(gearscore) or "-")
        safeShow(memberFrame.levelLabel, true)
    end
    layoutStockMemberLabels(memberFrame, classLabel)
end

local function patchStockMemberFrame(memberFrame)
    if type(memberFrame) ~= "table" or memberFrame.__nuzi_raidtools_patched then
        return
    end
    memberFrame.__nuzi_raidtools_patched = true
    State.patched_member_frames[#State.patched_member_frames + 1] = memberFrame

    local function wrap(methodName)
        local original = memberFrame[methodName]
        if type(original) ~= "function" then
            return
        end
        memberFrame["__nuzi_raidtools_original_" .. methodName] = original
        memberFrame[methodName] = function(self, ...)
            pcall(original, self, ...)
            applyStockMemberText(self)
        end
    end

    wrap("Refresh")
    wrap("UpdateName")
    wrap("UpdateAbility")
    wrap("UpdateLevel")
    wrap("OnShow")
    applyStockMemberText(memberFrame)
end

local function layoutRaidManagerPartyFrame(raidManager, partyFrame, partyIndex, stockWidth)
    if type(raidManager) ~= "table" or type(partyFrame) ~= "table" then
        return
    end

    local columns = 4
    local leftPad = 12
    local topPad = 38
    local colGap = 12
    local rowGap = 20
    local headerHeight = 18
    local rowHeight = 16
    local rowSpacing = 2
    local columnWidth = math.max(170, math.floor((stockWidth - leftPad * 2 - colGap * (columns - 1)) / columns))
    local partyHeight = headerHeight + 6 + (rowHeight + rowSpacing) * 5
    local col = (partyIndex - 1) % columns
    local row = math.floor((partyIndex - 1) / columns)
    local x = leftPad + col * (columnWidth + colGap)
    local y = topPad + row * (partyHeight + rowGap)

    safeRemoveAllAnchors(partyFrame)
    if partyFrame.SetExtent ~= nil then
        partyFrame:SetExtent(columnWidth, partyHeight)
    end
    safeAddAnchor(partyFrame, "TOPLEFT", raidManager, nil, x, y)

    if type(partyFrame.bg) == "table" then
        safeRemoveAllAnchors(partyFrame.bg)
        safeAddAnchor(partyFrame.bg, "TOPLEFT", partyFrame, nil, 0, 0)
        safeAddAnchor(partyFrame.bg, "BOTTOMRIGHT", partyFrame, nil, 0, 0)
    end

    if type(partyFrame.numberLabel) == "table" then
        configureStockLabel(partyFrame.numberLabel, columnWidth - 30, ALIGN.LEFT, { 0.72, 0.72, 0.72, 1 })
        safeRemoveAllAnchors(partyFrame.numberLabel)
        safeAddAnchor(partyFrame.numberLabel, "TOPLEFT", partyFrame, nil, 0, -2)
        safeShow(partyFrame.numberLabel, true)
    end

    if type(partyFrame.visiblePartyBtn) == "table" then
        safeRemoveAllAnchors(partyFrame.visiblePartyBtn)
        safeAddAnchor(partyFrame.visiblePartyBtn, "TOPRIGHT", partyFrame, nil, -2, -1)
        safeShow(partyFrame.visiblePartyBtn, true)
    end

    if type(partyFrame.member) ~= "table" then
        return
    end

    for slot = 1, 5 do
        local memberFrame = partyFrame.member[slot]
        if type(memberFrame) == "table" then
            safeRemoveAllAnchors(memberFrame)
            if memberFrame.SetExtent ~= nil then
                memberFrame:SetExtent(columnWidth, rowHeight)
            end
            safeAddAnchor(memberFrame, "TOPLEFT", partyFrame, nil, 0, headerHeight + 4 + (slot - 1) * (rowHeight + rowSpacing))
            if type(memberFrame.eventWindow) == "table" then
                safeRemoveAllAnchors(memberFrame.eventWindow)
                if memberFrame.eventWindow.SetExtent ~= nil then
                    memberFrame.eventWindow:SetExtent(columnWidth, rowHeight)
                end
                safeAddAnchor(memberFrame.eventWindow, "TOPLEFT", memberFrame, nil, 0, 0)
            end
            applyStockMemberText(memberFrame)
        end
    end
end

local function patchRaidManagerPartyFrame(raidManager, partyFrame)
    if type(partyFrame) ~= "table" or partyFrame.__nuzi_raidtools_party_patched then
        return
    end
    partyFrame.__nuzi_raidtools_party_patched = true
    State.patched_party_frames[#State.patched_party_frames + 1] = partyFrame

    local function wrap(methodName)
        local original = partyFrame[methodName]
        if type(original) ~= "function" then
            return
        end
        partyFrame["__nuzi_raidtools_original_" .. methodName] = original
        partyFrame[methodName] = function(self, ...)
            pcall(original, self, ...)
            local stockWidth = tonumber(self.__nuzi_raidtools_stock_width) or 920
            layoutRaidManagerPartyFrame(raidManager, self, tonumber(self.party) or 1, stockWidth)
        end
    end

    wrap("Refresh")
    wrap("OnShow")
    wrap("OnBoundChanged")
end

local function restorePatchedMemberFrames()
    for _, memberFrame in ipairs(State.patched_member_frames) do
        if type(memberFrame) == "table" then
            for _, methodName in ipairs({ "Refresh", "UpdateName", "UpdateAbility", "UpdateLevel", "OnShow" }) do
                local original = memberFrame["__nuzi_raidtools_original_" .. methodName]
                if type(original) == "function" then
                    memberFrame[methodName] = original
                    memberFrame["__nuzi_raidtools_original_" .. methodName] = nil
                end
            end
            memberFrame.__nuzi_raidtools_patched = nil
            if memberFrame.__nuzi_class_label ~= nil then
                Utils.SafeFree(memberFrame.__nuzi_class_label)
                memberFrame.__nuzi_class_label = nil
            end
        end
    end
    State.patched_member_frames = {}
end

local function restorePatchedPartyFrames()
    for _, partyFrame in ipairs(State.patched_party_frames) do
        if type(partyFrame) == "table" then
            for _, methodName in ipairs({ "Refresh", "OnShow", "OnBoundChanged" }) do
                local original = partyFrame["__nuzi_raidtools_original_" .. methodName]
                if type(original) == "function" then
                    partyFrame[methodName] = original
                    partyFrame["__nuzi_raidtools_original_" .. methodName] = nil
                end
            end
            partyFrame.__nuzi_raidtools_party_patched = nil
            partyFrame.__nuzi_raidtools_stock_width = nil
        end
    end
    State.patched_party_frames = {}
end

local function patchRaidManagerMembers(raidManager)
    if type(raidManager) ~= "table" or type(raidManager.party) ~= "table" then
        return
    end
    local stockWidth = tonumber(raidManager.__nuzi_raidtools_stock_width) or 920
    for partyIndex = 1, 10 do
        local partyFrame = raidManager.party[partyIndex]
        if type(partyFrame) == "table" then
            partyFrame.__nuzi_raidtools_stock_width = stockWidth
            patchRaidManagerPartyFrame(raidManager, partyFrame)
            layoutRaidManagerPartyFrame(raidManager, partyFrame, partyIndex, stockWidth)
        end
        if type(partyFrame) == "table" and type(partyFrame.member) == "table" then
            for slot = 1, 5 do
                local memberFrame = partyFrame.member[slot]
                if type(memberFrame) == "table" then
                    patchStockMemberFrame(memberFrame)
                end
            end
        end
    end
end

local function inviteNamesToRaid(names)
    if type(names) ~= "table" then
        return 0
    end

    local invited = 0
    local seen = {}
    for _, name in ipairs(names) do
        local formatted = Utils.FormatName(name)
        if formatted ~= "" and not State.blacklist_lookup[formatted] and not seen[formatted] then
            seen[formatted] = true
            pcall(function()
                api.Team:InviteToTeam(formatted, false)
            end)
            invited = invited + 1
        end
    end
    return invited
end

local function collectEnabledWhitelistMembers(settings)
    local out = {}
    local seen = {}
    if type(settings) ~= "table" or type(settings.whitelists) ~= "table" or type(settings.enabled_whitelists) ~= "table" then
        return out
    end

    for listName, members in pairs(settings.whitelists) do
        local key = normalizeKey(listName)
        if key ~= "" and settings.enabled_whitelists[key] == true and type(members) == "table" then
            for _, name in ipairs(members) do
                local formatted = Utils.FormatName(name)
                if formatted ~= "" and not seen[formatted] then
                    seen[formatted] = true
                    table.insert(out, formatted)
                end
            end
        end
    end

    return out
end

local function getCurrentCharacterKey()
    local unitId = nil
    local info = nil
    pcall(function()
        unitId = api.Unit:GetUnitId("player")
    end)
    if unitId ~= nil and api.Unit ~= nil and api.Unit.GetUnitInfoById ~= nil then
        pcall(function()
            info = api.Unit:GetUnitInfoById(unitId)
        end)
    end
    local name = type(info) == "table" and tostring(info.name or "") or ""
    if name == "" and api.Unit ~= nil and api.Unit.GetUnitName ~= nil then
        pcall(function()
            name = api.Unit:GetUnitName("player") or ""
        end)
    end
    name = string.lower(tostring(name or ""))
    if name == "" then
        return "unknown"
    end
    return name
end

local function getSavedRole()
    return tonumber(getSettings().char_roles[getCurrentCharacterKey()])
end

local function saveRole(role)
    getSettings().char_roles[getCurrentCharacterKey()] = tonumber(role)
    saveSettings()
end

local function applySavedRole()
    local role = getSavedRole()
    if role ~= nil and api.Team ~= nil and api.Team.SetRole ~= nil then
        pcall(function()
            api.Team:SetRole(role)
        end)
    end
end

local function rebuildBlacklistLookup()
    State.blacklist_lookup = {}
    for _, name in ipairs(getSettings().blacklist or {}) do
        State.blacklist_lookup[Utils.FormatName(name)] = true
    end
end

local function rebuildGiveLeadWhitelistLookup()
    State.give_lead_whitelist_lookup = {}
    for _, name in ipairs(getSettings().give_lead_whitelist or {}) do
        local formatted = Utils.FormatName(name)
        if formatted ~= "" then
            State.give_lead_whitelist_lookup[normalizeKey(formatted)] = true
        end
    end
end

local function rebuildEnabledWhitelistLookup()
    State.enabled_whitelist_lookup = {}
    local settings = getSettings()
    if type(settings.whitelists) ~= "table" or type(settings.enabled_whitelists) ~= "table" then
        return
    end
    for listName, members in pairs(settings.whitelists) do
        local key = normalizeKey(listName)
        if key ~= "" and settings.enabled_whitelists[key] == true and type(members) == "table" then
            for _, name in ipairs(members) do
                local formatted = Utils.FormatName(name)
                if formatted ~= "" then
                    State.enabled_whitelist_lookup[normalizeKey(formatted)] = true
                end
            end
        end
    end
end

local function isSpeakerInEnabledWhitelist(speakerName)
    local formattedSpeaker = Utils.FormatName(speakerName)
    local key = normalizeKey(formattedSpeaker)
    return key ~= "" and State.enabled_whitelist_lookup[key] == true
end

local function doesChatScopeMatch(settings, channelId)
    local recruitMethod = tonumber(settings.dms_selection) or 1
    return recruitMethod == 1
        or (recruitMethod == 2 and channelId == -3)
        or (recruitMethod == 3 and channelId == 7)
end

local function getNowMs()
    if api.Time == nil or api.Time.GetUiMsec == nil then
        return 0
    end
    local nowMs = 0
    pcall(function()
        nowMs = api.Time:GetUiMsec() or 0
    end)
    return tonumber(nowMs) or 0
end

local function canInviteSpeaker(formattedSpeaker)
    local key = normalizeKey(formattedSpeaker)
    if key == "" then
        return false
    end
    local nowMs = getNowMs()
    local lastInviteMs = tonumber(State.invite_cooldown_by_name[key]) or 0
    if lastInviteMs > 0 and (nowMs - lastInviteMs) < 15000 then
        return false
    end
    State.invite_cooldown_by_name[key] = nowMs
    return true
end

local function updateFloatingButtonVisibility()
    if State.floating_button == nil then
        return
    end
    local settings = getSettings()
    if settings.is_recruiting then
        State.floating_button:Show(true)
    else
        State.floating_button:Show(settings.always_visible and true or false)
    end
end

local function syncRecruitWidgets()
    local settings = getSettings()
    local isRecruiting = settings.is_recruiting and true or false
    local text = isRecruiting and "Stop Auto-Invite" or "Start Auto-Invite"
    if State.widgets.recruit_button ~= nil then
        State.widgets.recruit_button:SetText(text)
    end
    if State.floating_button ~= nil then
        State.floating_button:SetText(text)
    end
    if State.widgets.recruit_textfield ~= nil and State.widgets.recruit_textfield.Enable ~= nil then
        State.widgets.recruit_textfield:Enable(not isRecruiting)
    end
    updateFloatingButtonVisibility()
end

local function syncWhitelistWidgets()
    local settings = getSettings()
    if State.widgets.recruit_whitelist_toggle ~= nil then
        if settings.recruit_whitelist_enabled then
            State.widgets.recruit_whitelist_toggle:SetText("Enabled")
        else
            State.widgets.recruit_whitelist_toggle:SetText("Disabled")
        end
    end
    if State.widgets.give_lead_whitelist_toggle ~= nil then
        if settings.give_lead_whitelist_enabled then
            State.widgets.give_lead_whitelist_toggle:SetText("Enabled")
        else
            State.widgets.give_lead_whitelist_toggle:SetText("Disabled")
        end
    end
end

local function syncListBackedInputs()
    local settings = getSettings()
    if State.widgets.give_lead_whitelist_input ~= nil and State.widgets.give_lead_whitelist_input.SetText ~= nil then
        State.widgets.give_lead_whitelist_input:SetText(joinCommaList(settings.give_lead_whitelist))
    end
    if State.widgets.lead_code_word_input ~= nil and State.widgets.lead_code_word_input.SetText ~= nil then
        State.widgets.lead_code_word_input:SetText(tostring(settings.lead_code_word or "give lead"))
    end
end

local function setRecruiting(enabled)
    local settings = getSettings()
    settings.is_recruiting = enabled and true or false
    if settings.is_recruiting then
        local raw = tostring(settings.last_recruit_message or "")
        if State.widgets.recruit_textfield ~= nil and State.widgets.recruit_textfield.GetText ~= nil then
            raw = tostring(State.widgets.recruit_textfield:GetText() or "")
        end
        State.recruit_message = string.lower(raw)
        settings.last_recruit_message = State.recruit_message
    else
        State.recruit_message = string.lower(tostring(settings.last_recruit_message or ""))
    end
    saveSettings()
    syncRecruitWidgets()
end

local function toggleRecruiting()
    local settings = getSettings()
    if settings.is_recruiting then
        setRecruiting(false)
        return
    end
    local text = ""
    if State.widgets.recruit_textfield ~= nil and State.widgets.recruit_textfield.GetText ~= nil then
        text = tostring(State.widgets.recruit_textfield:GetText() or "")
    end
    if text == "" then
        return
    end
    setRecruiting(true)
end

local function clearRaidManagerWidgets()
    restorePatchedPartyFrames()
    restorePatchedMemberFrames()
    for _, widget in pairs(State.widgets) do
        Utils.SafeFree(widget)
    end
    State.widgets = {}
    if State.raid_manager ~= nil and State.raid_manager_original_width ~= nil and State.raid_manager_original_height ~= nil then
        pcall(function()
            State.raid_manager:SetExtent(State.raid_manager_original_width, State.raid_manager_original_height)
        end)
    end
    State.raid_manager = nil
    State.raid_manager_original_width = nil
    State.raid_manager_original_height = nil
end

local FloatingButtonPositions = Positioning.CreateNamedPositionManager({
    get_settings = function()
        return getSettings()
    end,
    save_settings = function()
        saveSettings()
    end,
    mappings = {
        floating_button = {
            x = "floating_button_x",
            y = "floating_button_y"
        }
    },
    require_shift = false
})

local function createFloatingButton()
    if State.floating_button ~= nil then
        return
    end
    local button = Utils.CreateButton("UIParent", "nuziRaidtoolsFloatingRecruit", "Start Auto-Invite", 140, 30)
    FloatingButtonPositions:ApplyAndBind(button, nil, "floating_button", {
        anchor = "TOPLEFT",
        relative_to = "UIParent",
        target_anchor = "TOPLEFT"
    })
    button:SetHandler("OnClick", toggleRecruiting)
    State.floating_button = button
    syncRecruitWidgets()
end

local function refreshActiveWhitelistDropdown()
    local settings = getSettings()
    if State.widgets.active_whitelist_dropdown == nil then
        return
    end
    local items = { "Select Whitelist" }
    for key, _ in pairs(settings.whitelists or {}) do
        table.insert(items, key)
    end
    table.sort(items, function(a, b)
        if a == "Select Whitelist" then
            return true
        end
        if b == "Select Whitelist" then
            return false
        end
        return tostring(a) < tostring(b)
    end)
    State.widgets.active_whitelist_dropdown.dropdownItem = items
    local targetIndex = 1
    for index, value in ipairs(items) do
        if value == settings.active_whitelist then
            targetIndex = index
            break
        end
    end
    if State.widgets.active_whitelist_dropdown.Select ~= nil then
        State.widgets.active_whitelist_dropdown:Select(targetIndex)
    end
    rebuildEnabledWhitelistLookup()
end

local function isRecruitSpeakerAllowed(channelId, speakerName)
    local formattedSpeaker = Utils.FormatName(speakerName)
    if formattedSpeaker == "" then
        return false
    end
    if not getSettings().recruit_whitelist_enabled then
        return true
    end
    local hasCustomWhitelists = tableHasEntries(State.enabled_whitelist_lookup)
    if not hasCustomWhitelists then
        return true
    end
    if hasCustomWhitelists and isSpeakerInEnabledWhitelist(formattedSpeaker) then
        return true
    end
    return false
end

local function isGiveLeadSpeakerAllowed(speakerName)
    if not getSettings().give_lead_whitelist_enabled then
        return true
    end
    local hasLeadWhitelist = tableHasEntries(State.give_lead_whitelist_lookup)
    if not hasLeadWhitelist then
        return true
    end
    local key = normalizeKey(Utils.FormatName(speakerName))
    return key ~= "" and State.give_lead_whitelist_lookup[key] == true
end

local function buildRaidManagerUi()
    local settings = getSettings()
    local raidManager = nil
    pcall(function()
        raidManager = ADDON:GetContent(UIC.RAID_MANAGER)
    end)
    if raidManager == nil then
        return
    end
    clearRaidManagerWidgets()
    State.raid_manager = raidManager
    pcall(function()
        State.raid_manager_original_width, State.raid_manager_original_height = raidManager:GetExtent()
    end)
    local currentWidth = raidManager:GetWidth()
    if type(currentWidth) ~= "number" or currentWidth <= 0 then
        currentWidth = tonumber(State.raid_manager_original_width) or 760
    end
    local panelWidth = 360
    local stockExtraWidth = 260
    local totalWidth = currentWidth + stockExtraWidth + panelWidth + 24
    pcall(function()
        raidManager:SetExtent(totalWidth, 710)
    end)
    raidManager.__nuzi_raidtools_stock_width = currentWidth + stockExtraWidth
    patchRaidManagerMembers(raidManager)

    local sidePanel = raidManager:CreateChildWidget("emptywidget", "nuziRaidtoolsSidePanel", 0, true)
    sidePanel:SetExtent(panelWidth, 620)
    sidePanel:AddAnchor("TOPRIGHT", raidManager, -18, 40)
    sidePanel:Show(true)
    if sidePanel.CreateNinePartDrawable ~= nil and TEXTURE_PATH ~= nil and TEXTURE_PATH.HUD ~= nil then
        sidePanel.bg = sidePanel:CreateNinePartDrawable(TEXTURE_PATH.HUD, "background")
        if sidePanel.bg ~= nil then
            sidePanel.bg:SetTextureInfo("bg_quest")
            sidePanel.bg:SetColor(0, 0, 0, 0.82)
            sidePanel.bg:AddAnchor("TOPLEFT", sidePanel, 0, 0)
            sidePanel.bg:AddAnchor("BOTTOMRIGHT", sidePanel, 0, 0)
        end
    elseif sidePanel.CreateColorDrawable ~= nil then
        sidePanel.bg = sidePanel:CreateColorDrawable(0.04, 0.04, 0.04, 0.82, "background")
        if sidePanel.bg ~= nil then
            sidePanel.bg:AddAnchor("TOPLEFT", sidePanel, 0, 0)
            sidePanel.bg:AddAnchor("BOTTOMRIGHT", sidePanel, 0, 0)
        end
    end
    State.widgets.side_panel = sidePanel

    local panelTitle = Utils.CreateLabel(
        sidePanel,
        "nuziRaidtoolsPanelTitle",
        "Nuzi Raidtools",
        15,
        ALIGN.LEFT,
        1,
        1,
        1,
        1
    )
    panelTitle:AddAnchor("TOPLEFT", sidePanel, 16, 14)
    State.widgets.panel_title = panelTitle

    local recruitingHeader = Utils.CreateLabel(
        sidePanel,
        "nuziRaidtoolsRecruitingHeader",
        "Auto-Invite",
        13,
        ALIGN.LEFT,
        0.92,
        0.82,
        0.35,
        1
    )
    recruitingHeader:AddAnchor("TOPLEFT", sidePanel, 16, 38)
    State.widgets.recruiting_header = recruitingHeader

    local recruitButton = Utils.CreateButton(sidePanel, "nuziRaidtoolsRecruitButton", "Start Auto-Invite", 328, 34)
    recruitButton:AddAnchor("TOPLEFT", sidePanel, 16, 58)
    recruitButton:SetHandler("OnClick", toggleRecruiting)
    State.widgets.recruit_button = recruitButton

    local recruitTextfield = Utils.CreateEditBox(sidePanel, "nuziRaidtoolsRecruitText", "Recruit message", 328, 30, 64)
    recruitTextfield:AddAnchor("TOPLEFT", sidePanel, 16, 96)
    recruitTextfield:Show(true)
    recruitTextfield:SetText(tostring(settings.last_recruit_message or ""))
    State.widgets.recruit_textfield = recruitTextfield

    local filterDropdown = Utils.CreateComboBox(sidePanel, { "Equals", "Contains", "Starts With" }, 160, 30)
    filterDropdown:AddAnchor("TOPLEFT", sidePanel, 16, 132)
    filterDropdown:Select(tonumber(settings.filter_selection) or 1)
    function filterDropdown:SelectedProc()
        settings.filter_selection = self:GetSelectedIndex()
        saveSettings()
    end
    State.widgets.filter_dropdown = filterDropdown

    local scopeDropdown = Utils.CreateComboBox(sidePanel, { "All Chats", "Whispers", "Guild" }, 160, 30)
    scopeDropdown:AddAnchor("LEFT", filterDropdown, "RIGHT", 8, 0)
    scopeDropdown:Select(tonumber(settings.dms_selection) or 1)
    function scopeDropdown:SelectedProc()
        settings.dms_selection = self:GetSelectedIndex()
        saveSettings()
    end
    State.widgets.chat_filter_dropdown = scopeDropdown

    local listsHeader = Utils.CreateLabel(
        sidePanel,
        "nuziRaidtoolsListsHeader",
        "Lists",
        13,
        ALIGN.LEFT,
        0.92,
        0.82,
        0.35,
        1
    )
    listsHeader:AddAnchor("TOPLEFT", sidePanel, 16, 168)
    State.widgets.lists_header = listsHeader

    local recruitWhitelistToggle = Utils.CreateButton(sidePanel, "nuziRaidtoolsRecruitWhitelistToggle", "", 116, 24)
    recruitWhitelistToggle:AddAnchor("TOPRIGHT", sidePanel, -16, 164)
    recruitWhitelistToggle:SetHandler("OnClick", function()
        settings.recruit_whitelist_enabled = not settings.recruit_whitelist_enabled
        saveSettings()
        syncWhitelistWidgets()
    end)
    State.widgets.recruit_whitelist_toggle = recruitWhitelistToggle

    local listManagerButton = Utils.CreateButton(sidePanel, "nuziRaidtoolsListManagerButton", "List Manager", 160, 30)
    listManagerButton:AddAnchor("TOPLEFT", sidePanel, 16, 188)
    listManagerButton:SetHandler("OnClick", function()
        ListManager.Toggle()
    end)
    State.widgets.open_manager_btn = listManagerButton

    local inviteWhitelistButton = Utils.CreateButton(sidePanel, "nuziRaidtoolsInviteWhitelistButton", "Invite Selected", 160, 30)
    inviteWhitelistButton:AddAnchor("LEFT", listManagerButton, "RIGHT", 8, 0)
    State.widgets.invite_whitelist_btn = inviteWhitelistButton

    local inviteEnabledButton = Utils.CreateButton(sidePanel, "nuziRaidtoolsInviteEnabledButton", "Invite Enabled Lists", 328, 30)
    inviteEnabledButton:AddAnchor("TOPLEFT", sidePanel, 16, 224)
    State.widgets.invite_enabled_btn = inviteEnabledButton

    local activeWhitelistDropdown = Utils.CreateComboBox(sidePanel, nil, 328, 30)
    activeWhitelistDropdown:AddAnchor("TOPLEFT", sidePanel, 16, 260)
    function activeWhitelistDropdown:SelectedProc()
        local idx = self:GetSelectedIndex()
        local selected = self.dropdownItem ~= nil and self.dropdownItem[idx] or "Select Whitelist"
        settings.active_whitelist = tostring(selected or "Select Whitelist")
        saveSettings()
    end
    State.widgets.active_whitelist_dropdown = activeWhitelistDropdown

    inviteWhitelistButton:SetHandler("OnClick", function()
        local idx = activeWhitelistDropdown:GetSelectedIndex()
        local selected = activeWhitelistDropdown.dropdownItem ~= nil and activeWhitelistDropdown.dropdownItem[idx] or nil
        if selected == nil or selected == "Select Whitelist" then
            logger:Err("No whitelist selected.")
            return
        end
        local sourceList = settings.whitelists[selected]
        if type(sourceList) ~= "table" or #sourceList == 0 then
            logger:Err("Selected whitelist is empty.")
            return
        end
        local invited = inviteNamesToRaid(sourceList)
        logger:Info("Invited " .. tostring(invited) .. " selected whitelist member(s).")
    end)

    inviteEnabledButton:SetHandler("OnClick", function()
        local names = collectEnabledWhitelistMembers(settings)
        if #names == 0 then
            logger:Err("No enabled whitelist members found.")
            return
        end
        local invited = inviteNamesToRaid(names)
        logger:Info("Invited " .. tostring(invited) .. " enabled whitelist member(s).")
    end)

    local whitelistAutoInviteCheckbox = Utils.CreateCheckbox(sidePanel, "nuziRaidtoolsWhitelistAutoInvite")
    whitelistAutoInviteCheckbox:AddAnchor("TOPLEFT", sidePanel, 16, 296)
    whitelistAutoInviteCheckbox:SetChecked(settings.whitelist_auto_invite and true or false)
    function whitelistAutoInviteCheckbox:OnCheckChanged()
        settings.whitelist_auto_invite = self:GetChecked() and true or false
        saveSettings()
    end
    whitelistAutoInviteCheckbox:SetHandler("OnCheckChanged", whitelistAutoInviteCheckbox.OnCheckChanged)
    State.widgets.whitelist_auto_invite_checkbox = whitelistAutoInviteCheckbox

    local whitelistAutoInviteLabel = Utils.CreateLabel(
        sidePanel,
        "nuziRaidtoolsWhitelistAutoInviteLabel",
        "Auto-invite enabled whitelist names",
        11,
        ALIGN.LEFT,
        1,
        1,
        1,
        1
    )
    whitelistAutoInviteLabel:AddAnchor("LEFT", whitelistAutoInviteCheckbox, "RIGHT", 6, 0)
    State.widgets.whitelist_auto_invite_label = whitelistAutoInviteLabel

    local alwaysVisibleCheckbox = Utils.CreateCheckbox(sidePanel, "nuziRaidtoolsAlwaysVisible")
    alwaysVisibleCheckbox:AddAnchor("TOPLEFT", sidePanel, 16, 322)
    alwaysVisibleCheckbox:SetChecked(settings.always_visible and true or false)
    function alwaysVisibleCheckbox:OnCheckChanged()
        settings.always_visible = self:GetChecked() and true or false
        saveSettings()
        updateFloatingButtonVisibility()
    end
    alwaysVisibleCheckbox:SetHandler("OnCheckChanged", alwaysVisibleCheckbox.OnCheckChanged)
    State.widgets.always_visible_checkbox = alwaysVisibleCheckbox

    local alwaysVisibleLabel = Utils.CreateLabel(
        sidePanel,
        "nuziRaidtoolsAlwaysVisibleLabel",
        "Always visible recruit button",
        11,
        ALIGN.LEFT,
        1,
        1,
        1,
        1
    )
    alwaysVisibleLabel:AddAnchor("LEFT", alwaysVisibleCheckbox, "RIGHT", 6, 0)
    State.widgets.always_visible_label = alwaysVisibleLabel

    local rolesHeader = Utils.CreateLabel(
        sidePanel,
        "nuziRaidtoolsRolesHeader",
        "Roles",
        13,
        ALIGN.LEFT,
        0.92,
        0.82,
        0.35,
        1
    )
    rolesHeader:AddAnchor("TOPLEFT", sidePanel, 16, 354)
    State.widgets.roles_header = rolesHeader

    local roleLabel = Utils.CreateLabel(
        sidePanel,
        "nuziRaidtoolsRoleLabel",
        "Auto Role",
        13,
        ALIGN.LEFT,
        1,
        1,
        1,
        1
    )
    roleLabel:AddAnchor("TOPLEFT", sidePanel, 16, 370)
    State.widgets.role_label = roleLabel

    local roleDropdown = Utils.CreateComboBox(sidePanel, { "Tank (Green)", "Healer (Pink)", "DPS (Red)", "Undecided (Blue)" }, 328, 30)
    roleDropdown:AddAnchor("TOPLEFT", sidePanel, 16, 388)
    roleDropdown:Select(tonumber(getSavedRole()) or 4)
    function roleDropdown:SelectedProc()
        local selectedRole = tonumber(self:GetSelectedIndex())
        if selectedRole ~= nil then
            saveRole(selectedRole)
            if api.Team ~= nil and api.Team.SetRole ~= nil then
                pcall(function()
                    api.Team:SetRole(selectedRole)
                end)
            end
        end
    end
    State.widgets.role_dropdown = roleDropdown

    local leadHeader = Utils.CreateLabel(
        sidePanel,
        "nuziRaidtoolsLeadHeader",
        "Lead Handoff",
        13,
        ALIGN.LEFT,
        0.92,
        0.82,
        0.35,
        1
    )
    leadHeader:AddAnchor("TOPLEFT", sidePanel, 16, 430)
    State.widgets.lead_header = leadHeader

    local giveLeadWhitelistToggle = Utils.CreateButton(sidePanel, "nuziRaidtoolsGiveLeadWhitelistToggle", "", 116, 24)
    giveLeadWhitelistToggle:AddAnchor("TOPRIGHT", sidePanel, -16, 426)
    giveLeadWhitelistToggle:SetHandler("OnClick", function()
        settings.give_lead_whitelist_enabled = not settings.give_lead_whitelist_enabled
        saveSettings()
        syncWhitelistWidgets()
    end)
    State.widgets.give_lead_whitelist_toggle = giveLeadWhitelistToggle

    local leadSniffingCheckbox = Utils.CreateCheckbox(sidePanel, "nuziRaidtoolsLeadSniffing")
    leadSniffingCheckbox:AddAnchor("TOPLEFT", sidePanel, 16, 452)
    leadSniffingCheckbox:SetChecked(settings.lead_sniffing and true or false)
    function leadSniffingCheckbox:OnCheckChanged()
        settings.lead_sniffing = self:GetChecked() and true or false
        saveSettings()
    end
    leadSniffingCheckbox:SetHandler("OnCheckChanged", leadSniffingCheckbox.OnCheckChanged)
    State.widgets.lead_sniffing_checkbox = leadSniffingCheckbox

    local leadSniffingLabel = Utils.CreateLabel(
        sidePanel,
        "nuziRaidtoolsLeadSniffingLabel",
        "Allow chat-based lead handoff",
        11,
        ALIGN.LEFT,
        1,
        1,
        1,
        1
    )
    leadSniffingLabel:AddAnchor("LEFT", leadSniffingCheckbox, "RIGHT", 6, 0)
    State.widgets.lead_sniffing_label = leadSniffingLabel

    local leadCodeWordLabel = Utils.CreateLabel(
        sidePanel,
        "nuziRaidtoolsLeadCodeWordLabel",
        "Lead code word",
        12,
        ALIGN.LEFT,
        1,
        1,
        1,
        1
    )
    leadCodeWordLabel:AddAnchor("TOPLEFT", sidePanel, 16, 492)
    State.widgets.lead_code_word_label = leadCodeWordLabel

    local leadCodeWordInput = Utils.CreateEditBox(sidePanel, "nuziRaidtoolsLeadCodeWordInput", "give lead", 258, 30, 64)
    leadCodeWordInput:AddAnchor("TOPLEFT", sidePanel, 16, 512)
    leadCodeWordInput:SetText(tostring(settings.lead_code_word or "give lead"))
    State.widgets.lead_code_word_input = leadCodeWordInput

    local leadCodeWordSave = Utils.CreateButton(sidePanel, "nuziRaidtoolsLeadCodeWordSave", "Save", 60, 30)
    leadCodeWordSave:AddAnchor("LEFT", leadCodeWordInput, "RIGHT", 8, 0)
    leadCodeWordSave:SetHandler("OnClick", function()
        settings.lead_code_word = trimText(leadCodeWordInput:GetText() or "")
        if settings.lead_code_word == "" then
            settings.lead_code_word = "give lead"
        end
        saveSettings()
        if leadCodeWordInput.SetText ~= nil then
            leadCodeWordInput:SetText(settings.lead_code_word)
        end
    end)
    State.widgets.lead_code_word_save = leadCodeWordSave

    local giveLeadWhitelistLabel = Utils.CreateLabel(
        sidePanel,
        "nuziRaidtoolsGiveLeadWhitelistLabel",
        "Give lead whitelist",
        12,
        ALIGN.LEFT,
        1,
        1,
        1,
        1
    )
    giveLeadWhitelistLabel:AddAnchor("TOPLEFT", sidePanel, 16, 548)
    State.widgets.give_lead_whitelist_label = giveLeadWhitelistLabel

    local giveLeadWhitelistInput = Utils.CreateEditBox(sidePanel, "nuziRaidtoolsGiveLeadWhitelistInput", "Character names", 258, 30, 512)
    giveLeadWhitelistInput:AddAnchor("TOPLEFT", sidePanel, 16, 568)
    giveLeadWhitelistInput:SetText(joinCommaList(settings.give_lead_whitelist))
    State.widgets.give_lead_whitelist_input = giveLeadWhitelistInput

    local giveLeadWhitelistSave = Utils.CreateButton(sidePanel, "nuziRaidtoolsGiveLeadWhitelistSave", "Save", 60, 30)
    giveLeadWhitelistSave:AddAnchor("LEFT", giveLeadWhitelistInput, "RIGHT", 8, 0)
    giveLeadWhitelistSave:SetHandler("OnClick", function()
        settings.give_lead_whitelist = parseCommaList(giveLeadWhitelistInput:GetText(), Utils.FormatName)
        saveSettings()
        rebuildGiveLeadWhitelistLookup()
        giveLeadWhitelistInput:SetText(joinCommaList(settings.give_lead_whitelist))
    end)
    State.widgets.give_lead_whitelist_save = giveLeadWhitelistSave

    local whitelistInviteHelp = Utils.CreateLabel(
        sidePanel,
        "nuziRaidtoolsWhitelistInviteHelp",
        "Enabled whitelists can gate recruit replies and can also auto-invite approved names.",
        10,
        ALIGN.LEFT,
        0.82,
        0.82,
        0.82,
        1
    )
    whitelistInviteHelp:AddAnchor("TOPLEFT", sidePanel, 16, 602)
    State.widgets.whitelist_invite_help = whitelistInviteHelp

    ListManager.Init(settings, {
        SaveSettings = saveSettings,
        OnBlacklistUpdate = rebuildBlacklistLookup,
        OnWhitelistUpdate = refreshActiveWhitelistDropdown,
        OnListChanged = function(listName)
            if listName == "Give Lead Whitelist" then
                rebuildGiveLeadWhitelistLookup()
            end
            syncListBackedInputs()
        end
    })
    refreshActiveWhitelistDropdown()
    syncListBackedInputs()
    syncWhitelistWidgets()
    syncRecruitWidgets()
end

local function onRoleChanged(role)
    if role ~= nil then
        saveRole(role)
    end
end

local function onTeamChanged()
    applySavedRole()
    patchRaidManagerMembers(State.raid_manager)
end

local function handleLeadSniffing(channel, speakerName, message)
    local settings = getSettings()
    local formattedSpeaker = Utils.FormatName(speakerName)
    local normalizedMessage = normalizeKey(message)
    local playerName = ""
    if api.Unit ~= nil and api.Unit.GetUnitNameById ~= nil and api.Unit.GetUnitId ~= nil then
        pcall(function()
            playerName = api.Unit:GetUnitNameById(api.Unit:GetUnitId("player")) or ""
        end)
    end
    if formattedSpeaker == playerName then
        if normalizedMessage == "start lead sniffing" then
            settings.lead_sniffing = true
            saveSettings()
            if State.widgets.lead_sniffing_checkbox ~= nil then
                State.widgets.lead_sniffing_checkbox:SetChecked(true)
            end
        elseif normalizedMessage == "stop lead sniffing" then
            settings.lead_sniffing = false
            saveSettings()
            if State.widgets.lead_sniffing_checkbox ~= nil then
                State.widgets.lead_sniffing_checkbox:SetChecked(false)
            end
        end
        return
    end
    if not settings.lead_sniffing then
        return
    end
    local configuredCodeWord = normalizeKey(settings.lead_code_word or "give lead")
    if configuredCodeWord == "" then
        configuredCodeWord = "give lead"
    end
    if normalizedMessage ~= configuredCodeWord then
        return
    end
    if channel ~= 5 and channel ~= -3 and channel ~= 7 then
        return
    end
    if not isGiveLeadSpeakerAllowed(formattedSpeaker) then
        return
    end
    local raidNum = nil
    pcall(function()
        raidNum = api.Team:GetMemberIndexByName(formattedSpeaker)
    end)
    if raidNum ~= nil then
        pcall(function()
            api.Team:MakeTeamOwner("team" .. tostring(raidNum))
        end)
    end
end

local function handleRecruitMessage(channelId, speakerName, message)
    local settings = getSettings()
    if type(speakerName) ~= "string" or speakerName == "" or State.recruit_message == "" then
        if not settings.whitelist_auto_invite then
            return
        end
    end
    local formattedSpeaker = Utils.FormatName(speakerName)
    if State.blacklist_lookup[formattedSpeaker] then
        return
    end
    if not settings.is_recruiting then
        return
    end
    if not isRecruitSpeakerAllowed(channelId, formattedSpeaker) then
        return
    end

    local isWhitelistAutoInvite = settings.whitelist_auto_invite
        and tableHasEntries(State.enabled_whitelist_lookup)
        and isSpeakerInEnabledWhitelist(formattedSpeaker)

    local matchesRecruitMessage = false
    if State.recruit_message ~= "" then
        local filterSelection = tonumber(settings.filter_selection) or 1
        if filterSelection == 1 and message == State.recruit_message then
            matchesRecruitMessage = true
        elseif filterSelection == 2 and string.find(message, State.recruit_message, 1, true) ~= nil then
            matchesRecruitMessage = true
        elseif filterSelection == 3 and string.sub(message, 1, #State.recruit_message) == State.recruit_message then
            matchesRecruitMessage = true
        end
    end

    if not doesChatScopeMatch(settings, channelId) then
        return
    end

    if not matchesRecruitMessage and not isWhitelistAutoInvite then
        return
    end

    if canInviteSpeaker(formattedSpeaker) then
        pcall(function()
            api.Team:InviteToTeam(formattedSpeaker, false)
        end)
    end
end

local function onChatMessage(channelId, speakerId, _, speakerName, message)
    local loweredMessage = string.lower(tostring(message or ""))
    handleLeadSniffing(channelId, tostring(speakerName or ""), loweredMessage)
    handleRecruitMessage(channelId, tostring(speakerName or ""), loweredMessage)
end

local function onUiReloaded()
    createFloatingButton()
    buildRaidManagerUi()
end

local function onLoad()
    local settings = getSettings()
    rebuildBlacklistLookup()
    rebuildEnabledWhitelistLookup()
    rebuildGiveLeadWhitelistLookup()
    State.recruit_message = string.lower(tostring(settings.last_recruit_message or ""))
    createFloatingButton()
    buildRaidManagerUi()
    applySavedRole()
    State.events = Events.Create({
        logger = logger
    })
    State.events:OnSafe("raid_role_changed", "raid_role_changed", onRoleChanged)
    State.events:OnSafe("TEAM_MEMBERS_CHANGED", "TEAM_MEMBERS_CHANGED", onTeamChanged)
    State.events:OnSafe("CHAT_MESSAGE", "CHAT_MESSAGE", onChatMessage)
    State.events:OnSafe("UI_RELOADED", "UI_RELOADED", onUiReloaded)
end

local function onUnload()
    if State.events ~= nil then
        State.events:ClearAll()
        State.events = nil
    end
    clearRaidManagerWidgets()
    ListManager.Free()
    if State.floating_button ~= nil then
        Utils.SafeFree(State.floating_button)
        State.floating_button = nil
    end
end

addon.OnLoad = onLoad
addon.OnUnload = onUnload
addon.OnSettingToggle = function()
    ListManager.Toggle()
end

return addon
