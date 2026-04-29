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
    if api.Unit ~= nil and api.Unit.UnitInfo ~= nil then
        pcall(function()
            info = api.Unit:UnitInfo("player")
        end)
    end
    if type(info) == "table" then
        name = tostring(info.name or info.unitName or "")
    end
    if name == "" and api.Unit ~= nil and api.Unit.GetUnitName ~= nil then
        pcall(function()
            name = api.Unit:GetUnitName("player") or ""
        end)
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

function Runtime.GetCurrentCharacterKey()
    if type(State.current_character_key) == "string"
        and State.current_character_key ~= ""
        and State.current_character_key ~= "unknown" then
        return State.current_character_key
    end

    local function resolveUnitName(methodName, unitToken)
        if api.Unit == nil or type(api.Unit[methodName]) ~= "function" then
            return ""
        end
        local ok, value = pcall(function()
            return api.Unit[methodName](api.Unit, unitToken)
        end)
        value = trimText(value)
        if ok and value ~= "" then
            return value
        end
        ok, value = pcall(function()
            return api.Unit[methodName](unitToken)
        end)
        value = trimText(value)
        if ok and value ~= "" then
            return value
        end
        return ""
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
    if name == "" then
        for _, methodName in ipairs({ "UnitName", "GetUnitName" }) do
            name = resolveUnitName(methodName, "player")
            if name ~= "" then
                break
            end
        end
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

function Runtime.ResetAutoInviteCadenceTicker()
    if State.auto_invite_cadence_ticker ~= nil and State.auto_invite_cadence_ticker.Reset ~= nil then
        State.auto_invite_cadence_ticker:Reset()
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
    if not Runtime.IsRecruitSpeakerAllowed(channelId, formattedSpeaker) then
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
    State.recruit_message = string.lower(tostring(settings.last_recruit_message or ""))
    Runtime.ResetAutoInviteCadenceTicker()
end

return Runtime
