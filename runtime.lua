local api = require("api")

local Runtime = {}

local Shared = nil
local Utils = nil
local State = nil

function Runtime.Init(shared, utils)
    Shared = shared
    Utils = utils
    State = shared ~= nil and shared.state or nil
end

local function getSettings()
    return Shared.GetSettings()
end

local function trimText(value)
    return Shared.TrimText(value)
end

local function normalizeUnitId(unitId)
    local valueType = type(unitId)
    if valueType == "string" then
        local text = tostring(unitId):gsub("^%s+", ""):gsub("%s+$", "")
        if text ~= "" and text ~= "0" then
            return text
        end
    elseif valueType == "number" and unitId ~= 0 then
        return tostring(unitId)
    end
    return nil
end

local function normalizeKey(value)
    return Shared.NormalizeKey(value)
end

local function tableHasEntries(value)
    return Shared.TableHasEntries(value)
end

local function readPlayerTeamIndex()
    if api.Team == nil or api.Team.GetTeamPlayerIndex == nil then
        return nil
    end
    local index = nil
    pcall(function()
        index = api.Team:GetTeamPlayerIndex()
    end)
    index = tonumber(index)
    if index ~= nil and index > 0 then
        return index
    end
    return nil
end

local function readPlayerTeamAuthority()
    if api.Unit == nil or api.Unit.UnitTeamAuthority == nil then
        return ""
    end
    local authority = ""
    pcall(function()
        authority = api.Unit:UnitTeamAuthority("player") or ""
    end)
    return normalizeKey(authority)
end

function Runtime.GetCurrentPlayerName()
    local name = ""
    local info = nil
    if api.Unit ~= nil and api.Unit.UnitName ~= nil then
        pcall(function()
            name = api.Unit:UnitName("player") or ""
        end)
    end
    if api.Unit ~= nil and api.Unit.UnitInfo ~= nil then
        pcall(function()
            info = api.Unit:UnitInfo("player")
        end)
    end
    if name == "" and type(info) == "table" then
        name = tostring(info.name or info.unitName or "")
    end
    return Utils.FormatName(name)
end

local function isNameAlreadyInRaid(name)
    local formatted = Utils.FormatName(name)
    if formatted == "" or api.Team == nil or api.Team.GetMemberIndexByName == nil then
        return false
    end

    local raidIndex = nil
    pcall(function()
        raidIndex = api.Team:GetMemberIndexByName(formatted)
    end)
    return raidIndex ~= nil
end

function Runtime.InviteNamesToRaid(names, options)
    if type(names) ~= "table" then
        return 0
    end
    if not Runtime.CanSendRaidInvites() then
        return 0
    end

    options = type(options) == "table" and options or {}
    local skipPlayer = options.skip_player and true or false
    local skipInRaid = options.skip_in_raid and true or false
    local respectCooldown = options.respect_cooldown and true or false
    local playerName = skipPlayer and Runtime.GetCurrentPlayerName() or ""
    local invited = 0
    local seen = {}
    for _, name in ipairs(names) do
        local formatted = Utils.FormatName(name)
        if formatted ~= "" and not State.blacklist_lookup[formatted] and not seen[formatted] then
            seen[formatted] = true
            if not (skipPlayer and playerName ~= "" and normalizeKey(formatted) == normalizeKey(playerName))
                and not (skipInRaid and isNameAlreadyInRaid(formatted))
                and (not respectCooldown or Runtime.CanInviteSpeaker(formatted)) then
                pcall(function()
                    api.Team:InviteToTeam(formatted, false)
                end)
                invited = invited + 1
            end
        end
    end
    return invited
end

function Runtime.CollectEnabledWhitelistMembers(settings)
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

local function listContainsName(list, name)
    if type(list) ~= "table" then
        return false
    end
    local key = normalizeKey(name)
    if key == "" then
        return false
    end
    for _, entry in ipairs(list) do
        if normalizeKey(entry) == key then
            return true
        end
    end
    return false
end

local function addNameToList(list, name)
    local formatted = Utils.FormatName(name)
    if formatted == "" or listContainsName(list, formatted) then
        return false
    end
    table.insert(list, formatted)
    return true
end

local function resolveNamedWhitelist(settings, listName, create)
    if type(settings) ~= "table" then
        return nil, nil, false
    end
    local changed = false
    if type(settings.whitelists) ~= "table" then
        settings.whitelists = {}
        changed = true
    end
    listName = trimText(listName)
    if listName == "" or listName == "Select Whitelist" then
        listName = Shared.CONSTANTS.DEFAULT_AUTOMATION_WHITELIST
    end
    if type(settings.whitelists[listName]) ~= "table" then
        if not create then
            return listName, nil, changed
        end
        settings.whitelists[listName] = {}
        changed = true
    end
    if type(settings.enabled_whitelists) ~= "table" then
        settings.enabled_whitelists = {}
        changed = true
    end
    local listKey = normalizeKey(listName)
    if listKey ~= "" and settings.enabled_whitelists[listKey] ~= true then
        settings.enabled_whitelists[listKey] = true
        changed = true
    end
    return listName, settings.whitelists[listName], changed
end

local function resolveGuildAutomationWhitelist(settings, create)
    return resolveNamedWhitelist(settings, Shared.CONSTANTS.DEFAULT_AUTOMATION_WHITELIST, create)
end

function Runtime.AddNameToAutomationWhitelist(name)
    local settings = getSettings()
    local listName, list = resolveGuildAutomationWhitelist(settings, true)
    if type(list) ~= "table" then
        return false
    end
    local added = addNameToList(list, name)
    Shared.SaveSettings()
    Runtime.RebuildEnabledWhitelistLookup()
    if added then
        Shared.logger:Info("Added " .. Utils.FormatName(name) .. " to " .. tostring(listName) .. ".")
    end
    return added
end

function Runtime.GetCurrentCharacterKey()
    if type(State.current_character_key) == "string"
        and State.current_character_key ~= ""
        and State.current_character_key ~= "unknown" then
        return State.current_character_key
    end

    local unitId = nil
    local info = nil
    local name = ""
    if api.Unit ~= nil and api.Unit.GetUnitId ~= nil then
        pcall(function()
            unitId = api.Unit:GetUnitId("player")
        end)
        unitId = normalizeUnitId(unitId)
    end
    if api.Unit ~= nil and api.Unit.UnitName ~= nil then
        pcall(function()
            name = api.Unit:UnitName("player") or ""
        end)
        name = trimText(name)
    end
    if name == "" and unitId ~= nil and api.Unit ~= nil and api.Unit.GetUnitNameById ~= nil then
        pcall(function()
            name = api.Unit:GetUnitNameById(unitId) or ""
        end)
    end
    if name == "" and unitId ~= nil and api.Unit ~= nil and api.Unit.GetUnitInfoById ~= nil then
        pcall(function()
            info = api.Unit:GetUnitInfoById(unitId)
        end)
        name = type(info) == "table" and tostring(info.name or "") or ""
    end
    name = normalizeKey(name)
    if name == "" then
        if type(State.current_character_key) == "string" and State.current_character_key ~= "" then
            return State.current_character_key
        end
        return "unknown"
    end
    State.current_character_key = name
    return name
end

function Runtime.NormalizeRoleSelection(role, options)
    local numeric = tonumber(role)
    if numeric == 1 or numeric == 2 or numeric == 3 or numeric == 4 then
        return numeric
    end
    if type(options) == "table" and options.allow_zero_undecided and numeric == 0 then
        return Shared.CONSTANTS.DEFAULT_AUTO_ROLE_SELECTION
    end
    return nil
end

function Runtime.GetSavedRole()
    local settings = getSettings()
    local key = Runtime.GetCurrentCharacterKey()
    if key ~= "" and key ~= "unknown" then
        local savedRole = Runtime.NormalizeRoleSelection(settings.char_roles[key], { allow_zero_undecided = true })
        if savedRole ~= nil then
            return savedRole
        end
    end
    return Runtime.NormalizeRoleSelection(settings.last_auto_role_selection, { allow_zero_undecided = true })
end

function Runtime.SaveRole(role)
    local normalizedRole = Runtime.NormalizeRoleSelection(role, { allow_zero_undecided = true })
    if normalizedRole == nil then
        return false
    end
    local settings = getSettings()
    settings.last_auto_role_selection = normalizedRole
    local key = Runtime.GetCurrentCharacterKey()
    if key ~= "" and key ~= "unknown" then
        settings.char_roles[key] = normalizedRole
    end
    Shared.SaveSettings()
    return true
end

function Runtime.ApplySavedRole()
    local role = Runtime.GetSavedRole()
    local settings = getSettings()
    local key = Runtime.GetCurrentCharacterKey()
    if role ~= nil and key ~= "" and key ~= "unknown" then
        local savedRole = Runtime.NormalizeRoleSelection(settings.char_roles[key], { allow_zero_undecided = true })
        if savedRole == nil then
            settings.char_roles[key] = role
            Shared.SaveSettings()
        end
    end
    if role ~= nil and api.Team ~= nil and api.Team.SetRole ~= nil then
        pcall(function()
            api.Team:SetRole(role)
        end)
    end
    return role
end

function Runtime.RebuildBlacklistLookup()
    State.blacklist_lookup = {}
    for _, name in ipairs(getSettings().blacklist or {}) do
        State.blacklist_lookup[Utils.FormatName(name)] = true
    end
end

function Runtime.RebuildGiveLeadWhitelistLookup()
    State.give_lead_whitelist_lookup = {}
    for _, name in ipairs(getSettings().give_lead_whitelist or {}) do
        local formatted = Utils.FormatName(name)
        if formatted ~= "" then
            State.give_lead_whitelist_lookup[normalizeKey(formatted)] = true
        end
    end
end

function Runtime.RebuildEnabledWhitelistLookup()
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

function Runtime.IsSpeakerInEnabledWhitelist(speakerName)
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

local function queueLoginInvite(name)
    local formatted = Utils.FormatName(name)
    if formatted == "" then
        return false
    end
    local key = normalizeKey(formatted)
    local nowMs = getNowMs()
    for _, queued in ipairs(State.login_invite_queue) do
        if type(queued) == "table" and queued.key == key then
            queued.due_ms = nowMs + Shared.CONSTANTS.WHITELIST_LOGIN_INVITE_DELAY_MS
            return true
        end
    end
    table.insert(State.login_invite_queue, {
        key = key,
        name = formatted,
        due_ms = nowMs + Shared.CONSTANTS.WHITELIST_LOGIN_INVITE_DELAY_MS
    })
    return true
end

local function readUnitTokenUnitId(unitToken)
    if unitToken == nil or unitToken == "" or api.Unit == nil or api.Unit.GetUnitId == nil then
        return nil
    end
    local unitId = nil
    pcall(function()
        unitId = api.Unit:GetUnitId(unitToken)
    end)
    return normalizeUnitId(unitId)
end

local function readTeamMemberUnitId(index)
    return readUnitTokenUnitId("team" .. tostring(index))
end

local function readTeamMemberInfo(index)
    local unitId = readTeamMemberUnitId(index)
    if unitId == nil or api.Unit == nil or api.Unit.GetUnitInfoById == nil then
        return nil
    end
    local info = nil
    pcall(function()
        info = api.Unit:GetUnitInfoById(unitId)
    end)
    if type(info) == "table" then
        return info
    end
    return nil
end

function Runtime.CanInviteSpeaker(formattedSpeaker)
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

function Runtime.IsRaidGeneral()
    return readPlayerTeamAuthority() == "leader"
end

function Runtime.CanSendRaidInvites()
    if api.Team == nil or api.Team.InviteToTeam == nil then
        return false
    end
    local authority = readPlayerTeamAuthority()
    if authority ~= "" then
        return authority == "leader"
    end
    if readPlayerTeamIndex() == nil then
        return true
    end
    return false
end

local function readTeamMemberRole(index)
    if api.Team == nil or api.Team.GetRole == nil then
        return 4
    end
    local role = nil
    pcall(function()
        role = api.Team:GetRole(index)
    end)
    role = tonumber(role)
    if role == 1 or role == 2 or role == 3 or role == 4 then
        return role
    end
    return 4
end

local function readUnitInfo(unitToken, unitId)
    local info = nil
    local infoById = nil
    if api.Unit ~= nil and api.Unit.UnitInfo ~= nil then
        pcall(function()
            info = api.Unit:UnitInfo(unitToken)
        end)
    end
    if unitId ~= nil and api.Unit ~= nil and api.Unit.GetUnitInfoById ~= nil then
        pcall(function()
            infoById = api.Unit:GetUnitInfoById(unitId)
        end)
    end
    return info, infoById
end

local function readUnitName(unitToken, unitId, info, infoById)
    local name = trimText(
        (type(info) == "table" and (info.name or info.unitName or info.unit_name))
        or (type(infoById) == "table" and (infoById.name or infoById.unitName or infoById.unit_name))
        or ""
    )
    if name ~= "" then
        return Utils.FormatName(name)
    end
    if api.Unit ~= nil and api.Unit.UnitName ~= nil then
        pcall(function()
            name = api.Unit:UnitName(unitToken) or ""
        end)
        name = trimText(name)
        if name ~= "" then
            return Utils.FormatName(name)
        end
    end
    if unitId ~= nil and api.Unit ~= nil and api.Unit.GetUnitNameById ~= nil then
        pcall(function()
            name = api.Unit:GetUnitNameById(unitId) or ""
        end)
        name = trimText(name)
        if name ~= "" then
            return Utils.FormatName(name)
        end
    end
    return ""
end

local function readUnitClassName(unitToken, info, infoById)
    local className = ""
    if api.Ability ~= nil and api.Ability.GetUnitClassName ~= nil then
        local ok, value = pcall(function()
            return api.Ability:GetUnitClassName(unitToken)
        end)
        value = trimText(value)
        if ok and value ~= "" then
            return value
        end
    end
    className = trimText(
        (type(info) == "table" and (info.className or info.class_name or info.unitClass or info.unit_class or info.jobName or info.job_name))
        or (type(infoById) == "table" and (infoById.className or infoById.class_name or infoById.unitClass or infoById.unit_class or infoById.jobName or infoById.job_name))
        or ""
    )
    if className ~= "" then
        return className
    end
    if api.Unit ~= nil and api.Unit.UnitClass ~= nil then
        local ok, value = pcall(function()
            return api.Unit:UnitClass(unitToken)
        end)
        value = trimText(value)
        if ok and value ~= "" then
            return value
        end
    end
    return ""
end

local function readUnitGearScore(unitToken, unitId)
    if api.Unit == nil or api.Unit.UnitGearScore == nil then
        return 0
    end
    for _, candidate in ipairs({ unitToken, unitId }) do
        if candidate ~= nil and candidate ~= "" then
            local ok, result = pcall(function()
                return api.Unit:UnitGearScore(candidate)
            end)
            result = tonumber(result)
            if ok and result ~= nil and result > 0 then
                return math.floor(result + 0.5)
            end
        end
    end
    return 0
end

local function collectRaidMembers()
    local members = {}
    for index = 1, Shared.CONSTANTS.RAID_MAX_MEMBERS do
        local unitToken = "team" .. tostring(index)
        local unitId = readTeamMemberUnitId(index)
        local info, infoById = readUnitInfo(unitToken, unitId)
        local name = readUnitName(unitToken, unitId, info, infoById)
        if unitId ~= nil or name ~= "" then
            table.insert(members, {
                index = index,
                key = unitId or normalizeKey(name) or tostring(index),
                unit_token = unitToken,
                unit_id = unitId,
                name = name,
                class_name = readUnitClassName(unitToken, info, infoById),
                role = readTeamMemberRole(index),
                gear_score = readUnitGearScore(unitToken, unitId)
            })
        end
    end
    return members
end

local function getBuiltinSortPreset(sortMode)
    sortMode = tonumber(sortMode) or 1
    if sortMode == 2 then
        return {
            name = "Healers > Tanks > DPS",
            role_order = { 2, 1, 3, 4 },
            gear_order = 1,
            name_order = 1
        }
    end
    if sortMode == 3 then
        return {
            name = "Gearscore High > Low",
            gear_order = 1,
            name_order = 1
        }
    end
    if sortMode == 4 then
        return {
            name = "Gearscore Low > High",
            gear_order = 2,
            name_order = 1
        }
    end
    return {
        name = "Tanks > Healers > DPS",
        role_order = { 1, 2, 3, 4 },
        gear_order = 1,
        name_order = 1
    }
end

local function getSelectedSortPreset()
    local settings = getSettings()
    local selectedPreset = trimText(settings.raid_sort_preset or "")
    local customKey = string.match(selectedPreset, "^custom:(.+)$")
    if customKey ~= nil
        and type(settings.raid_custom_sort_presets) == "table"
        and type(settings.raid_custom_sort_presets[customKey]) == "table" then
        return settings.raid_custom_sort_presets[customKey]
    end
    local builtinMode = tonumber(string.match(selectedPreset, "^builtin:(%d+)$")) or tonumber(settings.raid_sort_mode) or 1
    return getBuiltinSortPreset(builtinMode)
end

local function getRoleOrderRank(role, roleOrder)
    if type(roleOrder) ~= "table" then
        return nil
    end
    for index, candidate in ipairs(roleOrder) do
        if tonumber(candidate) == role then
            return index
        end
    end
    return 99
end

local function sortRaidMembers(members, preset)
    preset = type(preset) == "table" and preset or getBuiltinSortPreset(1)
    local gearOrder = tonumber(preset.gear_order) or 1
    local nameOrder = tonumber(preset.name_order) or 1
    table.sort(members, function(a, b)
        local aRank = getRoleOrderRank(a.role, preset.role_order)
        local bRank = getRoleOrderRank(b.role, preset.role_order)
        if aRank ~= nil and bRank ~= nil and aRank ~= bRank then
            return aRank < bRank
        end

        if gearOrder == 1 then
            if a.gear_score ~= b.gear_score then
                return a.gear_score > b.gear_score
            end
        elseif gearOrder == 2 then
            if a.gear_score ~= b.gear_score then
                return a.gear_score < b.gear_score
            end
        end

        if nameOrder == 2 and a.name ~= b.name then
            return a.name > b.name
        elseif nameOrder ~= 3 and a.name ~= b.name then
            return a.name < b.name
        end
        return a.index < b.index
    end)
end

local function getPresetRoleGroup(preset, role)
    local roleGroups = type(preset) == "table" and type(preset.role_groups) == "table" and preset.role_groups or nil
    if roleGroups == nil then
        return 0
    end
    return math.floor((tonumber(roleGroups[role] or roleGroups[tostring(role)]) or 0) + 0.5)
end

local function presetHasGroupTargets(preset)
    for role = 1, 4 do
        local group = getPresetRoleGroup(preset, role)
        if group >= 1 and group <= Shared.CONSTANTS.RAID_GROUP_COUNT then
            return true
        end
    end
    return false
end

local function getPresetSlotRole(preset, slot)
    local slotRoles = type(preset) == "table" and type(preset.slot_roles) == "table" and preset.slot_roles or nil
    if slotRoles == nil then
        return 0
    end
    local role = math.floor((tonumber(slotRoles[slot] or slotRoles[tostring(slot)]) or 0) + 0.5)
    if role >= 1 and role <= 4 then
        return role
    end
    return 0
end

local function presetHasSlotTargets(preset)
    for slot = 1, Shared.CONSTANTS.RAID_MAX_MEMBERS do
        if getPresetSlotRole(preset, slot) > 0 then
            return true
        end
    end
    return false
end

local function takeNextSortedMember(sortedMembers, used, role)
    for _, member in ipairs(sortedMembers) do
        if not used[member.key] and (role == nil or member.role == role) then
            used[member.key] = true
            return member
        end
    end
    return nil
end

local function buildPresetSlotTargetSlots(sortedMembers, preset)
    local desiredBySlot = {}
    local used = {}
    local maxSlot = Shared.CONSTANTS.RAID_MAX_MEMBERS
    for slot = 1, maxSlot do
        local role = getPresetSlotRole(preset, slot)
        if role > 0 then
            desiredBySlot[slot] = takeNextSortedMember(sortedMembers, used, role)
        end
    end

    for slot = 1, maxSlot do
        if desiredBySlot[slot] == nil then
            desiredBySlot[slot] = takeNextSortedMember(sortedMembers, used)
        end
    end
    return desiredBySlot
end

local function buildPresetTargetSlots(sortedMembers, preset)
    local roleGroups = type(preset) == "table" and type(preset.role_groups) == "table" and preset.role_groups or nil
    if roleGroups == nil then
        return nil
    end

    local desiredBySlot = {}
    local used = {}
    local hasTarget = false
    local maxSlot = Shared.CONSTANTS.RAID_MAX_MEMBERS
    for _, member in ipairs(sortedMembers) do
        local group = getPresetRoleGroup(preset, member.role)
        if group >= 1 and group <= Shared.CONSTANTS.RAID_GROUP_COUNT then
            local startSlot = ((group - 1) * Shared.CONSTANTS.RAID_GROUP_SIZE) + 1
            local endSlot = math.min(startSlot + Shared.CONSTANTS.RAID_GROUP_SIZE - 1, maxSlot)
            for slot = startSlot, endSlot do
                if desiredBySlot[slot] == nil then
                    desiredBySlot[slot] = member
                    used[member.key] = true
                    hasTarget = true
                    break
                end
            end
        end
    end
    if not hasTarget then
        return nil
    end

    local fillSlot = 1
    for _, member in ipairs(sortedMembers) do
        if not used[member.key] then
            while fillSlot <= maxSlot and desiredBySlot[fillSlot] ~= nil do
                fillSlot = fillSlot + 1
            end
            if fillSlot <= maxSlot then
                desiredBySlot[fillSlot] = member
            end
        end
    end

    return desiredBySlot
end

local function moveTeamMemberToSlot(fromSlot, toSlot)
    if fromSlot == nil or toSlot == nil then
        return false
    end
    if api.Team ~= nil and api.Team.MoveTeamMember ~= nil then
        local ok, result = pcall(function()
            return api.Team:MoveTeamMember(fromSlot, toSlot)
        end)
        if ok and result ~= false then
            return true
        end
    end
    return false
end

local function buildMemberSlotLookup(members)
    local out = {}
    for _, member in ipairs(members) do
        out[member.key] = member.index
    end
    return out
end

local function applyRaidSlotOrder(desiredBySlot)
    local moved = 0
    local failed = 0
    local currentMembers = collectRaidMembers()
    local currentSlots = buildMemberSlotLookup(currentMembers)
    for targetSlot = 1, Shared.CONSTANTS.RAID_MAX_MEMBERS do
        local desired = desiredBySlot[targetSlot]
        if desired ~= nil then
            local currentSlot = currentSlots[desired.key]
            if currentSlot ~= nil and currentSlot ~= targetSlot then
                local ok = moveTeamMemberToSlot(currentSlot, targetSlot)
                if ok then
                    moved = moved + 1
                    currentMembers = collectRaidMembers()
                    currentSlots = buildMemberSlotLookup(currentMembers)
                else
                    failed = failed + 1
                end
            end
        end
    end
    return moved, failed
end

local function findMemberPosition(members, key)
    for index, member in ipairs(members) do
        if member.key == key then
            return index
        end
    end
    return nil
end

local function applyRaidOrder(currentMembers, desiredMembers)
    local moved = 0
    local failed = 0
    for targetIndex, desired in ipairs(desiredMembers) do
        local currentIndex = findMemberPosition(currentMembers, desired.key)
        if currentIndex ~= nil and currentIndex ~= targetIndex then
            local ok, result = pcall(function()
                return api.Team:MoveTeamMember(currentIndex, targetIndex)
            end)
            if ok and result ~= false then
                local member = table.remove(currentMembers, currentIndex)
                table.insert(currentMembers, targetIndex, member)
                moved = moved + 1
            else
                failed = failed + 1
            end
        end
    end
    return moved, failed
end

function Runtime.SortRaidBySettings()
    if api.Team == nil or api.Team.MoveTeamMember == nil then
        return false, "Raid sorting API is unavailable."
    end
    if not Runtime.IsRaidGeneral() then
        return false, "Only raid lead can sort the raid."
    end

    local currentMembers = collectRaidMembers()
    if #currentMembers < 2 then
        return false, "Not enough raid members found to sort."
    end

    local desiredMembers = {}
    for index, member in ipairs(currentMembers) do
        desiredMembers[index] = member
    end
    local preset = getSelectedSortPreset()
    sortRaidMembers(desiredMembers, preset)

    local moved, failed = 0, 0
    if presetHasSlotTargets(preset) then
        moved, failed = applyRaidSlotOrder(buildPresetSlotTargetSlots(desiredMembers, preset))
    elseif presetHasGroupTargets(preset) then
        local desiredBySlot = buildPresetTargetSlots(desiredMembers, preset)
        if desiredBySlot ~= nil then
            moved, failed = applyRaidSlotOrder(desiredBySlot)
        end
    else
        moved, failed = applyRaidOrder(currentMembers, desiredMembers)
    end
    if failed > 0 then
        return moved > 0, "Sorted raid with " .. tostring(moved) .. " move(s); " .. tostring(failed) .. " move(s) failed."
    end
    if moved == 0 then
        return true, "Raid already matches the selected sort."
    end
    return true, "Sorted raid with " .. tostring(moved) .. " move(s)."
end

local function extractWhitelistLoginInviteTarget(speakerName, message)
    local formattedSpeaker = Utils.FormatName(speakerName)
    local normalizedMessage = normalizeKey(message)
    if normalizedMessage == "" then
        return nil
    end

    if formattedSpeaker ~= ""
        and Runtime.IsSpeakerInEnabledWhitelist(formattedSpeaker)
        and (
            string.find(normalizedMessage, "logged in", 1, true) ~= nil
            or string.find(normalizedMessage, "come online", 1, true) ~= nil
            or string.find(normalizedMessage, "now online", 1, true) ~= nil
        ) then
        return formattedSpeaker
    end

    for _, pattern in ipairs(Shared.LOGIN_ANNOUNCEMENT_PATTERNS) do
        local matchedName = normalizedMessage:match(pattern)
        local formattedName = Utils.FormatName(matchedName)
        if formattedName ~= "" and Runtime.IsSpeakerInEnabledWhitelist(formattedName) then
            return formattedName
        end
    end

    return nil
end

function Runtime.HandleWhitelistLoginAnnouncement(speakerName, message)
    local settings = getSettings()
    if not settings.is_recruiting
        or not settings.whitelist_auto_invite_on_login
        or not tableHasEntries(State.enabled_whitelist_lookup) then
        return
    end

    local targetName = extractWhitelistLoginInviteTarget(speakerName, message)
    if targetName == nil or targetName == "" then
        return
    end

    Runtime.InviteNamesToRaid({ targetName }, {
        skip_player = true,
        skip_in_raid = true,
        respect_cooldown = true
    })
end

function Runtime.HandleAcquaintanceLogin(characterName)
    local settings = getSettings()
    local formatted = Utils.FormatName(characterName)
    if formatted == ""
        or not settings.is_recruiting
        or not settings.whitelist_auto_invite_on_login
        or not Runtime.IsSpeakerInEnabledWhitelist(formatted)
        or not Runtime.CanSendRaidInvites() then
        return false
    end
    return queueLoginInvite(formatted)
end

function Runtime.ProcessLoginInviteQueue()
    local nowMs = getNowMs()
    for index = #State.login_invite_queue, 1, -1 do
        local queued = State.login_invite_queue[index]
        if type(queued) ~= "table" or tonumber(queued.due_ms) == nil then
            table.remove(State.login_invite_queue, index)
        elseif nowMs >= queued.due_ms then
            Runtime.InviteNamesToRaid({ queued.name }, {
                skip_player = true,
                skip_in_raid = true,
                respect_cooldown = true
            })
            table.remove(State.login_invite_queue, index)
        end
    end
end

function Runtime.RunWhitelistAutoInviteCadence()
    local settings = getSettings()
    if not settings.is_recruiting
        or not settings.whitelist_auto_invite_on_cadence
        or not tableHasEntries(State.enabled_whitelist_lookup) then
        return
    end

    local names = Runtime.CollectEnabledWhitelistMembers(settings)
    if #names == 0 then
        return
    end

    Runtime.InviteNamesToRaid(names, {
        skip_player = true,
        skip_in_raid = true,
        respect_cooldown = true
    })
end

function Runtime.RunExpeditionWhitelistSync()
    local settings = getSettings()
    if not settings.expedition_sync_enabled or readPlayerTeamIndex() == nil then
        return
    end

    local expeditionName = normalizeKey(settings.expedition_sync_name)
    if expeditionName == "" then
        return
    end

    local listName, list, listChanged = resolveGuildAutomationWhitelist(settings, true)
    if type(list) ~= "table" then
        return
    end

    local changed = listChanged
    for index = 1, 50 do
        local info = readTeamMemberInfo(index)
        if type(info) == "table" then
            local name = Utils.FormatName(info.name or info.unitName or "")
            if name ~= "" and normalizeKey(info.expeditionName or info.expedition_name) == expeditionName then
                changed = addNameToList(list, name) or changed
            end
        end
    end

    if changed then
        Shared.SaveSettings()
        Runtime.RebuildEnabledWhitelistLookup()
        Shared.logger:Info("Updated " .. tostring(listName) .. " from guild " .. tostring(settings.expedition_sync_name) .. ".")
    end
end

function Runtime.ResetAutoInviteCadenceTicker()
    if State.auto_invite_cadence_ticker ~= nil and State.auto_invite_cadence_ticker.Reset ~= nil then
        State.auto_invite_cadence_ticker:Reset()
    end
end

function Runtime.ResetExpeditionSyncTicker()
    if State.expedition_sync_ticker ~= nil and State.expedition_sync_ticker.Reset ~= nil then
        State.expedition_sync_ticker:Reset()
    end
end

function Runtime.GetRecruitButtonText()
    return getSettings().is_recruiting and "Stop Auto-Invite" or "Start Auto-Invite"
end

function Runtime.SetRecruiting(enabled, recruitText)
    local settings = getSettings()
    settings.is_recruiting = enabled and true or false
    Runtime.ResetAutoInviteCadenceTicker()
    if settings.is_recruiting then
        local raw = tostring(recruitText or settings.last_recruit_message or "")
        State.recruit_message = string.lower(raw)
        settings.last_recruit_message = State.recruit_message
    else
        State.recruit_message = string.lower(tostring(settings.last_recruit_message or ""))
    end
    Shared.SaveSettings()
    return true
end

function Runtime.ToggleRecruiting(recruitText)
    local settings = getSettings()
    if settings.is_recruiting then
        Runtime.SetRecruiting(false)
        return true
    end
    local text = tostring(recruitText or "")
    if text == "" then
        return false
    end
    Runtime.SetRecruiting(true, text)
    return true
end

function Runtime.GetActiveWhitelistStatusText()
    local settings = getSettings()
    local selected = tostring(settings.active_whitelist or "")
    if selected == "" or selected == "Select Whitelist" then
        return "Selected list: none selected."
    end
    local key = normalizeKey(selected)
    local isEnabled = key ~= ""
        and type(settings.enabled_whitelists) == "table"
        and settings.enabled_whitelists[key] == true
    if isEnabled then
        return "Selected list: automation enabled."
    end
    return "Selected list: automation disabled."
end

function Runtime.SaveLeadCodeWord(value)
    local settings = getSettings()
    settings.lead_code_word = trimText(value or "")
    if settings.lead_code_word == "" then
        settings.lead_code_word = "give lead"
    end
    Shared.SaveSettings()
    return settings.lead_code_word
end

function Runtime.SaveExpeditionSyncName(value)
    local settings = getSettings()
    settings.expedition_sync_name = trimText(value or "")
    if settings.expedition_sync_name == "" then
        settings.expedition_sync_name = "macro"
    end
    Shared.SaveSettings()
    return settings.expedition_sync_name
end

function Runtime.SaveGiveLeadWhitelist(text)
    local settings = getSettings()
    settings.give_lead_whitelist = Shared.ParseCommaList(text, Utils.FormatName)
    Shared.SaveSettings()
    Runtime.RebuildGiveLeadWhitelistLookup()
    return Shared.JoinCommaList(settings.give_lead_whitelist)
end

function Runtime.IsRecruitSpeakerAllowed(channelId, speakerName)
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
    if hasCustomWhitelists and Runtime.IsSpeakerInEnabledWhitelist(formattedSpeaker) then
        return true
    end
    return false
end

function Runtime.IsGiveLeadSpeakerAllowed(speakerName)
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

function Runtime.HandleRemoteAutoInviteCommand(channelId, speakerName, message)
    if channelId == Shared.CONSTANTS.RAID_CHAT_CHANNEL_ID
        and message == Shared.CONSTANTS.RAID_STOP_AUTO_INVITE_COMMAND then
        local settings = getSettings()
        if settings.is_recruiting then
            Runtime.SetRecruiting(false)
            Shared.logger:Info("Auto-invite stopped by " .. Utils.FormatName(speakerName) .. ".")
            return true
        end
        return false
    end

    local settings = getSettings()
    if not settings.remote_auto_invite_controls then
        return false
    end
    local normalizedMessage = normalizeKey(message)
    if normalizedMessage ~= "stop auto-invite" and normalizedMessage ~= "start auto-invite" then
        return false
    end
    if not Runtime.CanSendRaidInvites() or not Runtime.IsRecruitSpeakerAllowed(channelId, speakerName) then
        return false
    end
    if normalizedMessage == "stop auto-invite" then
        if settings.is_recruiting then
            Runtime.SetRecruiting(false)
            Shared.logger:Info("Auto-invite stopped by " .. Utils.FormatName(speakerName) .. ".")
        end
        return true
    end
    if settings.is_recruiting or trimText(settings.last_recruit_message) == "" then
        return false
    end
    Runtime.SetRecruiting(true, settings.last_recruit_message)
    Shared.logger:Info("Auto-invite started by " .. Utils.FormatName(speakerName) .. ".")
    return true
end

function Runtime.HandleLeadSniffing(channel, speakerName, message)
    local settings = getSettings()
    local formattedSpeaker = Utils.FormatName(speakerName)
    local normalizedMessage = normalizeKey(message)
    local playerName = ""
    if api.Unit ~= nil and api.Unit.GetUnitNameById ~= nil and api.Unit.GetUnitId ~= nil then
        pcall(function()
            local playerId = normalizeUnitId(api.Unit:GetUnitId("player"))
            if playerId ~= nil then
                playerName = api.Unit:GetUnitNameById(playerId) or ""
            end
        end)
    end
    if formattedSpeaker == playerName then
        if normalizedMessage == "start lead sniffing" then
            settings.lead_sniffing = true
            Shared.SaveSettings()
            return true
        end
        if normalizedMessage == "stop lead sniffing" then
            settings.lead_sniffing = false
            Shared.SaveSettings()
            return true
        end
        return false
    end
    if not settings.lead_sniffing then
        return false
    end
    local configuredCodeWord = normalizeKey(settings.lead_code_word or "give lead")
    if configuredCodeWord == "" then
        configuredCodeWord = "give lead"
    end
    if normalizedMessage ~= configuredCodeWord then
        return false
    end
    if channel ~= 5 and channel ~= -3 and channel ~= 7 then
        return false
    end
    if not Runtime.IsGiveLeadSpeakerAllowed(formattedSpeaker) then
        return false
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
    return false
end

function Runtime.HandleRecruitMessage(channelId, speakerName, message)
    local settings = getSettings()
    if (type(speakerName) ~= "string" or speakerName == "" or State.recruit_message == "")
        and not settings.whitelist_auto_invite then
        return
    end
    local formattedSpeaker = Utils.FormatName(speakerName)
    if State.blacklist_lookup[formattedSpeaker] then
        return
    end
    if not settings.is_recruiting then
        return
    end

    local isWhitelistAutoInvite = settings.whitelist_auto_invite
        and tableHasEntries(State.enabled_whitelist_lookup)
        and Runtime.IsSpeakerInEnabledWhitelist(formattedSpeaker)

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

    local learnedGuildSpeaker = false
    if settings.guild_auto_learn and channelId == 7 and matchesRecruitMessage then
        Runtime.AddNameToAutomationWhitelist(formattedSpeaker)
        learnedGuildSpeaker = true
    end

    if not learnedGuildSpeaker and not Runtime.IsRecruitSpeakerAllowed(channelId, formattedSpeaker) then
        return
    end

    if not matchesRecruitMessage and not isWhitelistAutoInvite then
        return
    end

    Runtime.InviteNamesToRaid({ formattedSpeaker }, {
        skip_player = true,
        skip_in_raid = true,
        respect_cooldown = true
    })
end

function Runtime.OnRoleChanged(role)
    local normalizedRole = Runtime.NormalizeRoleSelection(role)
    if normalizedRole ~= nil then
        Runtime.SaveRole(normalizedRole)
    end
    return normalizedRole
end

function Runtime.OnLoad()
    local settings = getSettings()
    Runtime.RebuildBlacklistLookup()
    Runtime.RebuildEnabledWhitelistLookup()
    Runtime.RebuildGiveLeadWhitelistLookup()
    State.login_invite_queue = {}
    State.recruit_message = string.lower(tostring(settings.last_recruit_message or ""))
    Runtime.ResetAutoInviteCadenceTicker()
    Runtime.ResetExpeditionSyncTicker()
end

return Runtime
