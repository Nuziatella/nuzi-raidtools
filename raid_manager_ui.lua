local api = require("api")
local Core = api._NuziCore or require("nuzi-core/core")

local Positioning = Core.UI.Positioning

local RaidManagerUi = {}

local Shared = nil
local Utils = nil
local ListManager = nil
local Runtime = nil
local State = nil
local FloatingButtonPositions = nil

function RaidManagerUi.Init(shared, utils, listManager, runtime)
    Shared = shared
    Utils = utils
    ListManager = listManager
    Runtime = runtime
    State = shared ~= nil and shared.state or nil
    if FloatingButtonPositions == nil then
        FloatingButtonPositions = Positioning.CreateNamedPositionManager({
            get_settings = function()
                return Shared.GetSettings()
            end,
            save_settings = function()
                Shared.SaveSettings()
            end,
            mappings = {
                floating_button = {
                    x = "floating_button_x",
                    y = "floating_button_y"
                }
            },
            require_shift = false
        })
    end
end

local function getSettings()
    return Shared.GetSettings()
end

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

local function safeEnable(widget, enabled)
    if widget ~= nil and widget.Enable ~= nil then
        widget:Enable(enabled and true or false)
    end
end

local function safeSetAlpha(widget, alpha)
    if widget ~= nil and widget.SetAlpha ~= nil then
        widget:SetAlpha(alpha)
    end
end

local function createEmptyChild(parent, id)
    if parent == nil or parent.CreateChildWidget == nil then
        return nil
    end
    local widget = parent:CreateChildWidget("emptywidget", id, 0, true)
    if widget ~= nil and widget.Show ~= nil then
        widget:Show(true)
    end
    return widget
end

local function applyPanelBackground(widget, alpha)
    if widget == nil then
        return nil
    end
    local background = nil
    if widget.CreateNinePartDrawable ~= nil and TEXTURE_PATH ~= nil and TEXTURE_PATH.HUD ~= nil then
        background = widget:CreateNinePartDrawable(TEXTURE_PATH.HUD, "background")
        if background ~= nil and background.SetTextureInfo ~= nil then
            background:SetTextureInfo("bg_quest")
        end
    elseif widget.CreateColorDrawable ~= nil then
        background = widget:CreateColorDrawable(0.08, 0.07, 0.05, alpha or 0.86, "background")
    end
    if background ~= nil then
        if background.SetColor ~= nil then
            background:SetColor(0.08, 0.07, 0.05, tonumber(alpha) or 0.86)
        end
        background:AddAnchor("TOPLEFT", widget, 0, 0)
        background:AddAnchor("BOTTOMRIGHT", widget, 0, 0)
    end
    return background
end

local function applyPanelAccent(widget, height, alpha)
    if widget == nil or widget.CreateColorDrawable == nil then
        return nil
    end
    local accent = widget:CreateColorDrawable(0.94, 0.80, 0.48, alpha or 0.12, "overlay")
    accent:AddAnchor("TOPLEFT", widget, 0, 0)
    accent:AddAnchor("TOPRIGHT", widget, 0, 0)
    if accent.SetHeight ~= nil then
        accent:SetHeight(height or 44)
    else
        accent:SetExtent(1, height or 44)
    end
    return accent
end

local function applyPanelDivider(widget, topInset, leftInset, rightInset, alpha)
    if widget == nil or widget.CreateColorDrawable == nil then
        return nil
    end
    local divider = widget:CreateColorDrawable(0.88, 0.76, 0.46, alpha or 0.16, "overlay")
    divider:AddAnchor("TOPLEFT", widget, leftInset or 18, topInset or 58)
    divider:AddAnchor("TOPRIGHT", widget, rightInset or -18, topInset or 58)
    if divider.SetHeight ~= nil then
        divider:SetHeight(1)
    else
        divider:SetExtent(1, 1)
    end
    return divider
end

local function getThemeColor(tone)
    return Shared.SETTINGS_WINDOW_THEME[tone or "text"] or Shared.SETTINGS_WINDOW_THEME.text
end

local function estimateCharsPerLine(width, fontSize)
    local safeWidth = math.max(80, tonumber(width) or 520)
    local safeFont = math.max(10, tonumber(fontSize) or 12)
    return math.max(14, math.floor(safeWidth / math.max(6, safeFont * 0.55)))
end

local function wrapTextToWidth(text, width, fontSize)
    local content = tostring(text or "")
    local charsPerLine = estimateCharsPerLine(width, fontSize)
    local lines = {}

    local function pushLine(value)
        lines[#lines + 1] = value or ""
    end

    local function wrapParagraph(segment)
        if segment == "" then
            pushLine("")
            return
        end

        local current = ""
        for word in string.gmatch(segment, "%S+") do
            local wordLen = string.len(word)
            if wordLen > charsPerLine then
                if current ~= "" then
                    pushLine(current)
                    current = ""
                end
                local index = 1
                while index <= wordLen do
                    local chunk = string.sub(word, index, index + charsPerLine - 1)
                    index = index + charsPerLine
                    if string.len(chunk) >= charsPerLine then
                        pushLine(chunk)
                    else
                        current = chunk
                    end
                end
            elseif current == "" then
                current = word
            elseif (string.len(current) + 1 + wordLen) <= charsPerLine then
                current = current .. " " .. word
            else
                pushLine(current)
                current = word
            end
        end

        if current ~= "" then
            pushLine(current)
        end
    end

    for segment in string.gmatch(content .. "\n", "(.-)\n") do
        wrapParagraph(segment)
    end

    if #lines == 0 then
        lines[1] = ""
    end

    return table.concat(lines, "\n"), #lines
end

local function estimateWrappedTextHeight(text, width, fontSize, lineHeight, minLines)
    local safeFont = math.max(10, tonumber(fontSize) or 12)
    local _, totalLines = wrapTextToWidth(text, width, safeFont)
    totalLines = math.max(tonumber(minLines) or 1, totalLines)
    return totalLines * math.max(safeFont + 4, tonumber(lineHeight) or (safeFont + 4))
end

local function createThemedLabel(parent, id, text, fontSize, width, height, tone)
    local color = getThemeColor(tone)
    local label = Utils.CreateLabel(
        parent,
        id,
        text,
        fontSize or 12,
        ALIGN.LEFT,
        color[1],
        color[2],
        color[3],
        color[4]
    )
    if label == nil then
        return nil
    end
    if label.SetExtent ~= nil then
        label:SetExtent(width or 220, height or math.max(18, (tonumber(fontSize) or 12) + 6))
    end
    if label.SetAutoResize ~= nil then
        label:SetAutoResize(false)
    end
    if label.SetLimitWidth ~= nil then
        local ok = pcall(function()
            label:SetLimitWidth(width or 220)
        end)
        if not ok then
            label:SetLimitWidth(true)
        end
    end
    if label.style ~= nil then
        if label.style.SetShadow ~= nil then
            label.style:SetShadow(true)
        end
        if label.style.SetEllipsis ~= nil then
            label.style:SetEllipsis(false)
        end
    end
    safeShow(label, true)
    return label
end

local function createWrappedThemedLabel(parent, id, text, fontSize, width, tone, minLines, lineHeight)
    local safeWidth = math.max(80, tonumber(width) or 220)
    local safeFont = math.max(10, tonumber(fontSize) or 12)
    local wrappedText = wrapTextToWidth(text, safeWidth, safeFont)
    local height = estimateWrappedTextHeight(text, safeWidth, safeFont, lineHeight, minLines)
    local label = createThemedLabel(parent, id, wrappedText, safeFont, safeWidth, height, tone)
    if label ~= nil and label.SetExtent ~= nil then
        label:SetExtent(safeWidth, height)
    end
    return label
end

local function createSectionCard(parent, id, title, hint, y, width, height)
    local card = createEmptyChild(parent, id)
    if card == nil then
        return nil
    end
    card:SetExtent(width, height)
    card:AddAnchor("TOPLEFT", parent, 0, y)
    applyPanelBackground(card, 0.82)
    applyPanelAccent(card, 34, 0.10)
    applyPanelDivider(card, 42, 14, -14, 0.10)
    local titleLabel = createThemedLabel(card, id .. "Title", title, 14, width - 28, 18, "heading")
    if titleLabel ~= nil then
        titleLabel:AddAnchor("TOPLEFT", card, 14, 12)
    end
    if type(hint) == "string" and hint ~= "" then
        local hintLabel = createWrappedThemedLabel(card, id .. "Hint", hint, 11, width - 28, "hint", 2, 15)
        if hintLabel ~= nil then
            hintLabel:AddAnchor("TOPLEFT", card, 14, 30)
        end
    end
    return card
end

local function createCheckboxRow(parent, id, text, x, y, width)
    local checkbox = Utils.CreateCheckbox(parent, id)
    if checkbox ~= nil then
        checkbox:AddAnchor("TOPLEFT", parent, x, y)
        safeShow(checkbox, true)
    end
    local label = createWrappedThemedLabel(parent, id .. "Label", text, 11, width or 280, "text", 1, 15)
    if label ~= nil then
        if checkbox ~= nil then
            label:AddAnchor("TOPLEFT", parent, x + 26, y - 2)
        else
            label:AddAnchor("TOPLEFT", parent, x, y)
        end
    end
    return checkbox, label
end

local function createAttachedSettingsWindow()
    local window = nil
    if api.Interface ~= nil and api.Interface.CreateEmptyWindow ~= nil then
        window = api.Interface:CreateEmptyWindow("nuziRaidtoolsSettingsWindow", "UIParent")
    elseif api.Interface ~= nil and api.Interface.CreateWindow ~= nil then
        window = api.Interface:CreateWindow("nuziRaidtoolsSettingsWindow", "Nuzi Raidtools Settings", 0, 0)
    end
    if window == nil then
        return nil
    end
    if window.EnableHidingIsRemove ~= nil then
        window:EnableHidingIsRemove(false)
    end
    if window.SetCloseOnEscape ~= nil then
        window:SetCloseOnEscape(false)
    end
    if window.SetUILayer ~= nil then
        window:SetUILayer("game")
    end
    return window
end

local function isWidgetLike(value)
    return type(value) == "table"
        and (
            value.Show ~= nil
            or value.AddAnchor ~= nil
            or value.SetText ~= nil
            or value.SetExtent ~= nil
            or value.IsVisible ~= nil
        )
end

local function suppressStockMemberWidget(widget)
    if type(widget) ~= "table" then
        return
    end
    safeSetText(widget, "")
    safeSetAlpha(widget, 0)
    safeShow(widget, false)
end

local function buildAllowedMemberWidgetLookup(memberFrame)
    local allowed = {}
    if type(memberFrame) ~= "table" then
        return allowed
    end
    local seen = {}
    local function addAllowed(widget, depth)
        if type(widget) ~= "table" or seen[widget] then
            return
        end
        seen[widget] = true
        depth = tonumber(depth) or 0
        if isWidgetLike(widget) then
            allowed[widget] = true
        end
        if depth <= 0 then
            return
        end
        for _, child in pairs(widget) do
            if type(child) == "table" then
                addAllowed(child, depth - 1)
            end
        end
    end
    addAllowed(memberFrame.offlineLabel, 3)
    addAllowed(memberFrame.eventWindow, 3)
    addAllowed(memberFrame.__nuzi_name_label, 3)
    addAllowed(memberFrame.__nuzi_class_label, 3)
    addAllowed(memberFrame.__nuzi_gs_label, 3)
    return allowed
end

local function suppressStockMemberWidgetTree(widget, allowed, seen, depth)
    if not isWidgetLike(widget) then
        return
    end
    seen = seen or {}
    if seen[widget] then
        return
    end
    seen[widget] = true
    depth = tonumber(depth) or 0

    if not allowed[widget] then
        suppressStockMemberWidget(widget)
    end

    if depth <= 0 or allowed[widget] then
        return
    end

    for _, child in pairs(widget) do
        if type(child) == "table" then
            suppressStockMemberWidgetTree(child, allowed, seen, depth - 1)
        end
    end
end

local function suppressStockMemberArtifacts(memberFrame)
    if type(memberFrame) ~= "table" then
        return
    end
    local allowed = buildAllowedMemberWidgetLookup(memberFrame)
    local seen = {}

    for _, fieldName in ipairs(Shared.STOCK_MEMBER_ARTIFACT_FIELDS) do
        local widget = memberFrame[fieldName]
        if widget ~= nil then
            suppressStockMemberWidgetTree(widget, allowed, seen, 2)
        end
    end

    for _, widget in pairs(memberFrame) do
        if isWidgetLike(widget) and not allowed[widget] then
            suppressStockMemberWidgetTree(widget, allowed, seen, 2)
        end
    end
end

local function restoreStockMemberWidgetTree(widget, seen, depth)
    if not isWidgetLike(widget) then
        return
    end
    seen = seen or {}
    if seen[widget] then
        return
    end
    seen[widget] = true
    depth = tonumber(depth) or 0

    safeSetAlpha(widget, 1)
    safeShow(widget, true)

    if depth <= 0 then
        return
    end

    for _, child in pairs(widget) do
        if type(child) == "table" then
            restoreStockMemberWidgetTree(child, seen, depth - 1)
        end
    end
end

local function restoreStockMemberArtifacts(memberFrame)
    if type(memberFrame) ~= "table" then
        return
    end
    local seen = {}
    for _, widget in pairs(memberFrame) do
        if isWidgetLike(widget) then
            restoreStockMemberWidgetTree(widget, seen, 2)
        end
    end
end

local function isWidgetVisible(widget)
    if type(widget) ~= "table" or widget.IsVisible == nil then
        return false
    end
    local visible = false
    pcall(function()
        visible = widget:IsVisible() and true or false
    end)
    return visible
end

local function extractGearScoreFromInfo(info)
    if type(info) ~= "table" then
        return nil
    end

    local visited = {}
    local candidateKeys = {
        "gearScore",
        "gearscore",
        "gear_score",
        "gs",
        "unitGearScore",
        "unit_gear_score",
        "combatPower",
        "combat_power",
        "battlePower",
        "battle_power",
        "itemScore",
        "item_score",
    }

    local function findRecursive(node, depth)
        depth = tonumber(depth) or 0
        if depth > 2 or type(node) ~= "table" or visited[node] then
            return nil
        end
        visited[node] = true

        for _, key in ipairs(candidateKeys) do
            local value = tonumber(node[key])
            if value ~= nil and value > 0 then
                return value
            end
        end

        for _, value in pairs(node) do
            if type(value) == "table" then
                local nested = findRecursive(value, depth + 1)
                if nested ~= nil then
                    return nested
                end
            end
        end

        return nil
    end

    local value = findRecursive(info, 0)
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

local function getRaidUnitGearScore(unitToken, unitId, info, infoById)
    local value = extractGearScoreFromInfo(info) or extractGearScoreFromInfo(infoById)
    if value ~= nil then
        return value
    end
    if api.Unit ~= nil and api.Unit.UnitGearScore ~= nil then
        for _, candidate in ipairs({ unitToken, unitId }) do
            if candidate ~= nil and candidate ~= "" then
                local ok, result = pcall(function()
                    return api.Unit:UnitGearScore(candidate)
                end)
                result = tonumber(result)
                if ok and result ~= nil and result > 0 then
                    return math.floor(result + 0.5)
                end

                ok, result = pcall(function()
                    return api.Unit.UnitGearScore(api.Unit, candidate)
                end)
                result = tonumber(result)
                if ok and result ~= nil and result > 0 then
                    return math.floor(result + 0.5)
                end
            end
        end
    end
    return nil
end

local function mapRaidRoleId(roleId)
    if tonumber(roleId) == 1 then
        return "defender"
    end
    if tonumber(roleId) == 2 then
        return "healer"
    end
    if tonumber(roleId) == 3 then
        return "attacker"
    end
    return "undecided"
end

local function getRaidUnitRoleKey(unitToken, displayName)
    if api.Team == nil or api.Team.GetRole == nil then
        return nil
    end

    local memberIndex = tonumber(tostring(unitToken or ""):match("^team(%d+)$"))
    if memberIndex ~= nil then
        local ok, roleId = pcall(function()
            return api.Team:GetRole(memberIndex)
        end)
        if ok then
            return mapRaidRoleId(roleId)
        end
    end

    if displayName ~= "" and api.Team.GetMemberIndexByName ~= nil then
        local okIndex, fallbackIndex = pcall(function()
            return api.Team:GetMemberIndexByName(displayName)
        end)
        if okIndex and tonumber(fallbackIndex) ~= nil then
            local okRole, roleId = pcall(function()
                return api.Team:GetRole(fallbackIndex)
            end)
            if okRole then
                return mapRaidRoleId(roleId)
            end
        end
    end

    return nil
end

local function normalizeClassRoleKey(value)
    local text = string.lower(trimText(value))
    return text:gsub("[%s%p_]+", "")
end

local function makeClassTypeLookup(list)
    local lookup = {}
    for _, name in ipairs(list or {}) do
        local key = normalizeClassRoleKey(name)
        if key ~= "" then
            lookup[key] = true
        end
    end
    return lookup
end

local CLASS_TYPE_LOOKUP = {
    tank = makeClassTypeLookup({
        "Abolisher",
        "Doomlord",
        "Nightcloak",
        "Skullknight",
        "Templar"
    }),
    healer = makeClassTypeLookup({
        "Cleric",
        "Confessor",
        "Doombringer",
        "Edgewalker",
        "Hierophant",
        "Soothsayer"
    }),
    dps = makeClassTypeLookup({
        "Arcanist",
        "Assassin",
        "Blade Dancer",
        "Blighter",
        "Bloodreaver",
        "Daggerspell",
        "Darkrunner",
        "Deathwish",
        "Demonologist",
        "Dreambreaker",
        "Ebonsong",
        "Enforcer",
        "Enigmatist",
        "Executioner",
        "Fanatic",
        "Gunslinger",
        "Hawksong",
        "Hexblade",
        "Infiltrator",
        "Outrider",
        "Primeval",
        "Ranger",
        "Ravager",
        "Reaper",
        "Revenant",
        "Shadehunter",
        "Shadowblade",
        "Shadowplay",
        "Shadowsong",
        "Sorrowsong",
        "Spellsinger",
        "Stone Arrow",
        "Stonearrow",
        "Trickster"
    })
}

local function getClassTypeKey(className)
    local key = normalizeClassRoleKey(className)
    if key == "" then
        return nil
    end
    if CLASS_TYPE_LOOKUP.tank[key] then
        return "tank"
    end
    if CLASS_TYPE_LOOKUP.healer[key] then
        return "healer"
    end
    if CLASS_TYPE_LOOKUP.dps[key] then
        return "dps"
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

local function configureStockLabel(label, width, align, rgba, fontSize, height)
    if type(label) ~= "table" then
        return
    end
    local labelHeight = tonumber(height) or 18
    if label.SetAutoResize ~= nil then
        label:SetAutoResize(false)
    end
    if label.SetExtent ~= nil then
        label:SetExtent(width, labelHeight)
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
        if fontSize ~= nil and label.style.SetFontSize ~= nil then
            label.style:SetFontSize(fontSize)
        end
        if rgba ~= nil and label.style.SetColor ~= nil then
            label.style:SetColor(rgba[1], rgba[2], rgba[3], rgba[4])
        end
    end
end

local function layoutStockMemberLabels(memberFrame)
    if type(memberFrame) ~= "table" then
        return
    end
    local rowWidth = 140
    if memberFrame.GetWidth ~= nil then
        rowWidth = tonumber(memberFrame:GetWidth()) or rowWidth
    end
    rowWidth = math.max(140, rowWidth)
    local gsWidth = 54
    local classWidth = math.max(40, math.min(64, math.floor(rowWidth * 0.24)))
    local nameWidth = math.max(72, rowWidth - gsWidth - classWidth - 24)
    local nameLabel = type(memberFrame.__nuzi_name_label) == "table" and memberFrame.__nuzi_name_label or nil
    local gsLabel = type(memberFrame.__nuzi_gs_label) == "table" and memberFrame.__nuzi_gs_label or nil
    local classTextLabel = type(memberFrame.__nuzi_class_label) == "table" and memberFrame.__nuzi_class_label or nil
    local nameColor = type(memberFrame.__nuzi_name_color) == "table" and memberFrame.__nuzi_name_color or { 1, 1, 1, 1 }
    local classColor = type(memberFrame.__nuzi_class_color) == "table" and memberFrame.__nuzi_class_color or { 0.84, 0.9, 1, 1 }

    if nameLabel ~= nil then
        configureStockLabel(nameLabel, nameWidth, ALIGN.LEFT, nameColor, 13, 18)
        safeRemoveAllAnchors(nameLabel)
        safeAddAnchor(nameLabel, "TOPLEFT", memberFrame, nil, 6, 0)
        safeShow(nameLabel, true)
    end

    if gsLabel ~= nil then
        configureStockLabel(gsLabel, gsWidth, ALIGN.RIGHT, { 0.95, 0.84, 0.46, 1 }, 12, 18)
        safeRemoveAllAnchors(gsLabel)
        safeAddAnchor(gsLabel, "TOPRIGHT", memberFrame, nil, -4, 0)
        safeShow(gsLabel, true)
    end

    if classTextLabel ~= nil then
        configureStockLabel(classTextLabel, classWidth, ALIGN.CENTER, classColor, 12, 18)
        safeRemoveAllAnchors(classTextLabel)
        if gsLabel ~= nil then
            safeAddAnchor(classTextLabel, "RIGHT", gsLabel, "LEFT", -6, 0)
        else
            safeAddAnchor(classTextLabel, "TOPRIGHT", memberFrame, nil, -(gsWidth + 10), 0)
        end
        safeShow(classTextLabel, true)
    end

    if type(memberFrame.offlineLabel) == "table" then
        configureStockLabel(memberFrame.offlineLabel, nameWidth, ALIGN.LEFT, { 1, 0.45, 0.45, 1 }, 13, 18)
        safeRemoveAllAnchors(memberFrame.offlineLabel)
        safeAddAnchor(memberFrame.offlineLabel, "TOPLEFT", memberFrame, nil, 6, 0)
    end

    suppressStockMemberArtifacts(memberFrame)
end

local function ensureStockMemberOverlayLabel(memberFrame, storageKey, prefix)
    if type(memberFrame) ~= "table" then
        return nil
    end
    local label = memberFrame[storageKey]
    if type(label) ~= "table" and memberFrame.CreateChildWidget ~= nil then
        label = memberFrame:CreateChildWidget(
            "label",
            prefix .. tostring(memberFrame.party or 0) .. "_" .. tostring(memberFrame.memberIndex or memberFrame.slot or 0),
            0,
            true
        )
        memberFrame[storageKey] = label
    end
    return label
end

local function ensureStockMemberClassLabel(memberFrame)
    return ensureStockMemberOverlayLabel(memberFrame, "__nuzi_class_label", "nuziRaidtoolsClassLabel")
end

local function ensureStockMemberGearScoreLabel(memberFrame)
    return ensureStockMemberOverlayLabel(memberFrame, "__nuzi_gs_label", "nuziRaidtoolsGsLabel")
end

local function ensureStockMemberNameLabel(memberFrame)
    return ensureStockMemberOverlayLabel(memberFrame, "__nuzi_name_label", "nuziRaidtoolsNameLabel")
end

local function getRaidUnitDisplayName(unitToken, unitId, info, infoById, memberFrame)
    local displayName = trimText(
        (type(info) == "table" and (info.name or info.unitName or info.family_name))
        or (type(infoById) == "table" and (infoById.name or infoById.unitName or infoById.family_name))
        or ""
    )
    if displayName ~= "" then
        return displayName
    end

    if api.Unit ~= nil and unitToken ~= nil and unitToken ~= "" then
        for _, methodName in ipairs({ "UnitName", "GetUnitName" }) do
            if type(api.Unit[methodName]) == "function" then
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
            end
        end
    end

    if api.Unit ~= nil and api.Unit.GetUnitNameById ~= nil and unitId ~= nil and unitId ~= "" then
        local ok, value = pcall(function()
            return api.Unit:GetUnitNameById(unitId)
        end)
        value = trimText(value)
        if ok and value ~= "" then
            return value
        end
    end

    if type(memberFrame) == "table" and type(memberFrame.name) == "table" and memberFrame.name.GetText ~= nil then
        local ok, value = pcall(function()
            return memberFrame.name:GetText()
        end)
        value = trimText(value)
        if ok and value ~= "" then
            return value
        end
    end

    return ""
end

local function applyStockMemberText(memberFrame)
    if type(memberFrame) ~= "table" then
        return
    end
    local unitToken = trimText(memberFrame.target)
    if unitToken == "" then
        memberFrame.__nuzi_name_color = nil
        memberFrame.__nuzi_class_color = nil
        if type(memberFrame.__nuzi_name_label) == "table" then
            safeSetText(memberFrame.__nuzi_name_label, "")
            safeShow(memberFrame.__nuzi_name_label, false)
        end
        if type(memberFrame.__nuzi_class_label) == "table" then
            safeSetText(memberFrame.__nuzi_class_label, "")
            safeShow(memberFrame.__nuzi_class_label, false)
        end
        if type(memberFrame.__nuzi_gs_label) == "table" then
            safeSetText(memberFrame.__nuzi_gs_label, "")
            safeShow(memberFrame.__nuzi_gs_label, false)
        end
        suppressStockMemberArtifacts(memberFrame)
        layoutStockMemberLabels(memberFrame)
        return
    end

    local info, unitId, infoById = getRaidUnitContext(unitToken)
    local displayName = getRaidUnitDisplayName(unitToken, unitId, info, infoById, memberFrame)
    local className = getRaidUnitClass(unitToken, info, infoById)
    local gearscore = getRaidUnitGearScore(unitToken, unitId, info, infoById)
    local roleKey = getRaidUnitRoleKey(unitToken, displayName)
    local classTypeKey = getClassTypeKey(className)
    memberFrame.__nuzi_name_color = Shared.TEAM_ROLE_COLORS[roleKey or ""] or { 1, 1, 1, 1 }
    memberFrame.__nuzi_class_color = Shared.CLASS_TYPE_COLORS[classTypeKey or ""] or { 0.84, 0.9, 1, 1 }

    local nameLabel = ensureStockMemberNameLabel(memberFrame)
    local classLabel = ensureStockMemberClassLabel(memberFrame)
    local gsLabel = ensureStockMemberGearScoreLabel(memberFrame)
    if nameLabel ~= nil then
        safeSetText(nameLabel, displayName ~= "" and displayName or "-")
        safeShow(nameLabel, true)
    end
    if classLabel ~= nil then
        safeSetText(classLabel, abbreviateClassName(className))
        safeShow(classLabel, true)
    end

    if gsLabel ~= nil then
        safeSetText(gsLabel, gearscore ~= nil and tostring(gearscore) or "-")
        safeShow(gsLabel, true)
    end
    suppressStockMemberArtifacts(memberFrame)
    layoutStockMemberLabels(memberFrame)
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
    wrap("UpdateOffline")
    wrap("UpdateState")
    wrap("SetUnit")
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
    local headerHeight = 20
    local rowHeight = 18
    local rowSpacing = 4
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
        configureStockLabel(partyFrame.numberLabel, columnWidth - 30, ALIGN.LEFT, { 0.72, 0.72, 0.72, 1 }, 12, 18)
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
            for _, methodName in ipairs({ "Refresh", "UpdateName", "UpdateAbility", "UpdateLevel", "UpdateOffline", "UpdateState", "SetUnit", "OnShow" }) do
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
            if memberFrame.__nuzi_gs_label ~= nil then
                Utils.SafeFree(memberFrame.__nuzi_gs_label)
                memberFrame.__nuzi_gs_label = nil
            end
            if memberFrame.__nuzi_name_label ~= nil then
                Utils.SafeFree(memberFrame.__nuzi_name_label)
                memberFrame.__nuzi_name_label = nil
            end
            restoreStockMemberArtifacts(memberFrame)
            if memberFrame.Refresh ~= nil then
                pcall(function()
                    memberFrame:Refresh()
                end)
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

function RaidManagerUi.PatchRaidManagerMembers(raidManager)
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

function RaidManagerUi.UpdateFloatingButtonVisibility()
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

function RaidManagerUi.SyncRecruitWidgets()
    local isRecruiting = getSettings().is_recruiting and true or false
    local text = Runtime.GetRecruitButtonText()
    if State.widgets.recruit_button ~= nil then
        State.widgets.recruit_button:SetText(text)
    end
    if State.floating_button ~= nil then
        State.floating_button:SetText(text)
    end
    safeEnable(State.widgets.recruit_textfield, not isRecruiting)
    RaidManagerUi.UpdateFloatingButtonVisibility()
end

function RaidManagerUi.SyncWhitelistWidgets()
    local settings = getSettings()
    if State.widgets.recruit_whitelist_checkbox ~= nil then
        State.widgets.recruit_whitelist_checkbox:SetChecked(settings.recruit_whitelist_enabled and true or false)
    end
    if State.widgets.give_lead_whitelist_checkbox ~= nil then
        State.widgets.give_lead_whitelist_checkbox:SetChecked(settings.give_lead_whitelist_enabled and true or false)
    end
    if State.widgets.active_whitelist_status_label ~= nil then
        safeSetText(State.widgets.active_whitelist_status_label, Runtime.GetActiveWhitelistStatusText())
    end
end

function RaidManagerUi.SyncAutoInviteWidgets()
    local settings = getSettings()
    if State.widgets.whitelist_auto_invite_checkbox ~= nil then
        State.widgets.whitelist_auto_invite_checkbox:SetChecked(settings.whitelist_auto_invite and true or false)
    end
    if State.widgets.whitelist_auto_invite_on_login_checkbox ~= nil then
        State.widgets.whitelist_auto_invite_on_login_checkbox:SetChecked(settings.whitelist_auto_invite_on_login and true or false)
    end
    if State.widgets.whitelist_auto_invite_on_cadence_checkbox ~= nil then
        State.widgets.whitelist_auto_invite_on_cadence_checkbox:SetChecked(settings.whitelist_auto_invite_on_cadence and true or false)
    end
end

function RaidManagerUi.SyncLeadWidgets()
    local settings = getSettings()
    if State.widgets.lead_sniffing_checkbox ~= nil then
        State.widgets.lead_sniffing_checkbox:SetChecked(settings.lead_sniffing and true or false)
    end
end

function RaidManagerUi.SyncListBackedInputs()
    local settings = getSettings()
    if State.widgets.give_lead_whitelist_input ~= nil and State.widgets.give_lead_whitelist_input.SetText ~= nil then
        State.widgets.give_lead_whitelist_input:SetText(Shared.JoinCommaList(settings.give_lead_whitelist))
    end
    if State.widgets.lead_code_word_input ~= nil and State.widgets.lead_code_word_input.SetText ~= nil then
        State.widgets.lead_code_word_input:SetText(tostring(settings.lead_code_word or "give lead"))
    end
end

function RaidManagerUi.SyncSettingsPanelVisibility()
    local shouldShow = getSettings().settings_panel_visible ~= false and isWidgetVisible(State.raid_manager)
    if State.widgets.settings_window ~= nil then
        safeShow(State.widgets.settings_window, shouldShow)
    end
    if State.widgets.settings_toggle_button ~= nil then
        State.widgets.settings_toggle_button:SetText(shouldShow and "Hide Settings" or "Show Settings")
    end
end

function RaidManagerUi.ToggleSettingsPanel()
    local settings = getSettings()
    settings.settings_panel_visible = settings.settings_panel_visible == false
    Shared.SaveSettings()
    RaidManagerUi.SyncSettingsPanelVisibility()
end

function RaidManagerUi.SyncRoleDropdownSelection(role)
    local dropdown = State.widgets.role_dropdown
    if dropdown == nil or dropdown.Select == nil then
        return
    end
    local targetRole = Runtime.NormalizeRoleSelection(role, { allow_zero_undecided = true })
        or Runtime.GetSavedRole()
        or Shared.CONSTANTS.DEFAULT_AUTO_ROLE_SELECTION
    dropdown.__nuzi_syncing_role = true
    pcall(function()
        dropdown:Select(targetRole)
    end)
    dropdown.__nuzi_syncing_role = nil
end

function RaidManagerUi.RefreshActiveWhitelistDropdown()
    local settings = getSettings()
    if State.widgets.active_whitelist_dropdown == nil then
        return
    end
    local items = { "Select Whitelist" }
    for key in pairs(settings.whitelists or {}) do
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
    Runtime.RebuildEnabledWhitelistLookup()
    RaidManagerUi.SyncWhitelistWidgets()
end

function RaidManagerUi.SyncAll()
    RaidManagerUi.RefreshActiveWhitelistDropdown()
    RaidManagerUi.SyncListBackedInputs()
    RaidManagerUi.SyncWhitelistWidgets()
    RaidManagerUi.SyncAutoInviteWidgets()
    RaidManagerUi.SyncLeadWidgets()
    RaidManagerUi.SyncRoleDropdownSelection()
    RaidManagerUi.SyncRecruitWidgets()
    RaidManagerUi.SyncSettingsPanelVisibility()
end

local function buildAttachedRaidManagerSettings(raidManager, settings)
    local settingsWindow = createAttachedSettingsWindow()
    if settingsWindow == nil then
        return
    end

    settingsWindow:SetExtent(Shared.CONSTANTS.ATTACHED_SETTINGS_WIDTH, Shared.CONSTANTS.ATTACHED_SETTINGS_HEIGHT)
    safeRemoveAllAnchors(settingsWindow)
    safeAddAnchor(settingsWindow, "TOPLEFT", raidManager, "TOPRIGHT", 12, 0)
    safeShow(settingsWindow, false)
    State.widgets.settings_window = settingsWindow

    local shell = createEmptyChild(settingsWindow, "nuziRaidtoolsSettingsShell")
    if shell ~= nil then
        shell:AddAnchor("TOPLEFT", settingsWindow, 0, 0)
        shell:AddAnchor("BOTTOMRIGHT", settingsWindow, 0, 0)
        applyPanelBackground(shell, 0.94)
        applyPanelAccent(shell, 44, 0.08)
        applyPanelDivider(shell, 44, 12, -12, 0.12)
    end

    local header = createEmptyChild(settingsWindow, "nuziRaidtoolsSettingsHeader")
    if header ~= nil then
        header:AddAnchor("TOPLEFT", settingsWindow, 0, 0)
        header:AddAnchor("TOPRIGHT", settingsWindow, 0, 0)
        if header.SetHeight ~= nil then
            header:SetHeight(24)
        else
            header:SetExtent(1, 24)
        end
        applyPanelBackground(header, 0.98)
        applyPanelAccent(header, 24, 0.10)
        applyPanelDivider(header, 24, 10, -10, 0.14)
        local windowTitle = createThemedLabel(
            header,
            "nuziRaidtoolsSettingsHeaderTitle",
            "Nuzi Raidtools Settings",
            15,
            280,
            18,
            "title"
        )
        if windowTitle ~= nil then
            windowTitle:AddAnchor("TOPLEFT", header, 14, 3)
        end
        local closeButton = Utils.CreateButton(header, "nuziRaidtoolsSettingsClose", "X", 26, 22)
        if closeButton ~= nil then
            closeButton:AddAnchor("TOPRIGHT", header, -10, 1)
            closeButton:SetHandler("OnClick", function()
                settings.settings_panel_visible = false
                Shared.SaveSettings()
                RaidManagerUi.SyncSettingsPanelVisibility()
            end)
        end
    end

    local contentPanel = createEmptyChild(settingsWindow, "nuziRaidtoolsSettingsContentPanel")
    if contentPanel ~= nil then
        contentPanel:AddAnchor("TOPLEFT", settingsWindow, 12, 38)
        contentPanel:AddAnchor("BOTTOMRIGHT", settingsWindow, -12, -12)
        applyPanelBackground(contentPanel, 0.86)
        applyPanelAccent(contentPanel, 54, 0.12)
        applyPanelDivider(contentPanel, 58, 18, -18, 0.18)
    else
        contentPanel = settingsWindow
    end

    local pageTitle = createThemedLabel(
        contentPanel,
        "nuziRaidtoolsSettingsPageTitle",
        "Raid Manager Controls",
        16,
        300,
        18,
        "title"
    )
    if pageTitle ~= nil then
        pageTitle:AddAnchor("TOPLEFT", contentPanel, 18, 12)
    end
    local pageSummary = createWrappedThemedLabel(
        contentPanel,
        "nuziRaidtoolsSettingsPageSummary",
        "Recruiting, list tools, roles, and lead handoff manager.",
        12,
        330,
        "hint",
        2,
        16
    )
    if pageSummary ~= nil then
        pageSummary:AddAnchor("TOPLEFT", contentPanel, 18, 38)
    end

    local scrollFrame = Utils.CreateScrollWindow(contentPanel, "nuziRaidtoolsSettingsScroll", 0)
    if scrollFrame == nil then
        return
    end
    scrollFrame:RemoveAllAnchors()
    scrollFrame:AddAnchor("TOPLEFT", contentPanel, 12, 86)
    scrollFrame:AddAnchor("BOTTOMRIGHT", contentPanel, -10, -12)
    scrollFrame:SetExtent(348, Shared.CONSTANTS.ATTACHED_SETTINGS_HEIGHT - 126)

    local content = scrollFrame.content
    local cardWidth = 330
    local sectionY = 10

    local autoInviteCard = createSectionCard(
        content,
        "nuziRaidtoolsAutoInviteCard",
        "Auto-Invite",
        "Run your recruit message here.",
        sectionY,
        cardWidth,
        246
    )
    if autoInviteCard ~= nil then
        local recruitButton = Utils.CreateButton(autoInviteCard, "nuziRaidtoolsRecruitButton", "Start Auto-Invite", cardWidth - 28, 32)
        recruitButton:AddAnchor("TOPLEFT", autoInviteCard, 14, 68)
        recruitButton:SetHandler("OnClick", function()
            local raw = State.widgets.recruit_textfield ~= nil and State.widgets.recruit_textfield:GetText() or ""
            if Runtime.ToggleRecruiting(raw) then
                RaidManagerUi.SyncRecruitWidgets()
            end
        end)
        State.widgets.recruit_button = recruitButton

        local recruitTextfield = Utils.CreateEditBox(autoInviteCard, "nuziRaidtoolsRecruitText", "Recruit message", cardWidth - 28, 30, 64)
        recruitTextfield:AddAnchor("TOPLEFT", autoInviteCard, 14, 108)
        recruitTextfield:Show(true)
        recruitTextfield:SetText(tostring(settings.last_recruit_message or ""))
        State.widgets.recruit_textfield = recruitTextfield

        local filterLabel = createThemedLabel(autoInviteCard, "nuziRaidtoolsFilterLabel", "Phrase Match", 11, 150, 18, "hint")
        if filterLabel ~= nil then
            filterLabel:AddAnchor("TOPLEFT", autoInviteCard, 14, 146)
        end
        local scopeLabel = createThemedLabel(autoInviteCard, "nuziRaidtoolsScopeLabel", "Chat Scope", 11, 150, 18, "hint")
        if scopeLabel ~= nil then
            scopeLabel:AddAnchor("TOPLEFT", autoInviteCard, 172, 146)
        end

        local filterDropdown = Utils.CreateComboBox(autoInviteCard, { "Equals", "Contains", "Starts With" }, 150, 30)
        filterDropdown:AddAnchor("TOPLEFT", autoInviteCard, 14, 166)
        filterDropdown:Select(tonumber(settings.filter_selection) or 1)
        function filterDropdown:SelectedProc()
            settings.filter_selection = self:GetSelectedIndex()
            Shared.SaveSettings()
        end
        State.widgets.filter_dropdown = filterDropdown

        local scopeDropdown = Utils.CreateComboBox(autoInviteCard, { "All Chats", "Whispers", "Guild" }, 150, 30)
        scopeDropdown:AddAnchor("TOPLEFT", autoInviteCard, 172, 166)
        scopeDropdown:Select(tonumber(settings.dms_selection) or 1)
        function scopeDropdown:SelectedProc()
            settings.dms_selection = self:GetSelectedIndex()
            Shared.SaveSettings()
        end
        State.widgets.chat_filter_dropdown = scopeDropdown

        local alwaysVisibleCheckbox = createCheckboxRow(
            autoInviteCard,
            "nuziRaidtoolsAlwaysVisible",
            "Always show the floating recruit button",
            14,
            210,
            286
        )
        alwaysVisibleCheckbox:SetChecked(settings.always_visible and true or false)
        function alwaysVisibleCheckbox:OnCheckChanged()
            settings.always_visible = self:GetChecked() and true or false
            Shared.SaveSettings()
            RaidManagerUi.UpdateFloatingButtonVisibility()
        end
        alwaysVisibleCheckbox:SetHandler("OnCheckChanged", alwaysVisibleCheckbox.OnCheckChanged)
        State.widgets.always_visible_checkbox = alwaysVisibleCheckbox
    end
    sectionY = sectionY + 258

    local listCard = createSectionCard(
        content,
        "nuziRaidtoolsListCard",
        "Lists",
        "Open the list manager to edit your lists.",
        sectionY,
        cardWidth,
        370
    )
    if listCard ~= nil then
        local activeListLabel = createThemedLabel(listCard, "nuziRaidtoolsActiveListLabel", "Active Whitelist", 12, 240, 18, "text")
        if activeListLabel ~= nil then
            activeListLabel:AddAnchor("TOPLEFT", listCard, 14, 68)
        end

        local activeWhitelistDropdown = Utils.CreateComboBox(listCard, nil, cardWidth - 28, 30)
        activeWhitelistDropdown:AddAnchor("TOPLEFT", listCard, 14, 88)
        function activeWhitelistDropdown:SelectedProc()
            local idx = self:GetSelectedIndex()
            local selected = self.dropdownItem ~= nil and self.dropdownItem[idx] or "Select Whitelist"
            settings.active_whitelist = tostring(selected or "Select Whitelist")
            Shared.SaveSettings()
            RaidManagerUi.SyncWhitelistWidgets()
        end
        State.widgets.active_whitelist_dropdown = activeWhitelistDropdown

        local listManagerButton = Utils.CreateButton(listCard, "nuziRaidtoolsListManagerButton", "Manage Lists", cardWidth - 28, 30)
        listManagerButton:AddAnchor("TOPLEFT", listCard, 14, 126)
        listManagerButton:SetHandler("OnClick", function()
            ListManager.Toggle()
        end)
        State.widgets.open_manager_btn = listManagerButton

        local inviteWhitelistButton = Utils.CreateButton(listCard, "nuziRaidtoolsInviteWhitelistButton", "Invite Active", 147, 30)
        inviteWhitelistButton:AddAnchor("TOPLEFT", listCard, 14, 164)
        State.widgets.invite_whitelist_btn = inviteWhitelistButton

        local inviteEnabledButton = Utils.CreateButton(listCard, "nuziRaidtoolsInviteEnabledButton", "Invite Enabled", 147, 30)
        inviteEnabledButton:AddAnchor("TOPLEFT", listCard, 169, 164)
        State.widgets.invite_enabled_btn = inviteEnabledButton

        inviteWhitelistButton:SetHandler("OnClick", function()
            local idx = activeWhitelistDropdown:GetSelectedIndex()
            local selected = activeWhitelistDropdown.dropdownItem ~= nil and activeWhitelistDropdown.dropdownItem[idx] or nil
            if selected == nil or selected == "Select Whitelist" then
                Shared.logger:Err("No whitelist selected.")
                return
            end
            local sourceList = settings.whitelists[selected]
            if type(sourceList) ~= "table" or #sourceList == 0 then
                Shared.logger:Err("Selected whitelist is empty.")
                return
            end
            local invited = Runtime.InviteNamesToRaid(sourceList)
            Shared.logger:Info("Invited " .. tostring(invited) .. " selected whitelist member(s).")
        end)

        inviteEnabledButton:SetHandler("OnClick", function()
            local names = Runtime.CollectEnabledWhitelistMembers(settings)
            if #names == 0 then
                Shared.logger:Err("No enabled whitelist members found.")
                return
            end
            local invited = Runtime.InviteNamesToRaid(names)
            Shared.logger:Info("Invited " .. tostring(invited) .. " enabled whitelist member(s).")
        end)

        local activeWhitelistStatusLabel = createWrappedThemedLabel(
            listCard,
            "nuziRaidtoolsActiveWhitelistStatus",
            Runtime.GetActiveWhitelistStatusText(),
            10,
            cardWidth - 28,
            "hint",
            1,
            14
        )
        if activeWhitelistStatusLabel ~= nil then
            activeWhitelistStatusLabel:AddAnchor("TOPLEFT", listCard, 14, 200)
        end
        State.widgets.active_whitelist_status_label = activeWhitelistStatusLabel

        local recruitWhitelistCheckbox = createCheckboxRow(
            listCard,
            "nuziRaidtoolsRecruitWhitelist",
            "Only auto-invite enabled-list speakers",
            14,
            232,
            286
        )
        recruitWhitelistCheckbox:SetChecked(settings.recruit_whitelist_enabled and true or false)
        function recruitWhitelistCheckbox:OnCheckChanged()
            settings.recruit_whitelist_enabled = self:GetChecked() and true or false
            Shared.SaveSettings()
            RaidManagerUi.SyncWhitelistWidgets()
        end
        recruitWhitelistCheckbox:SetHandler("OnCheckChanged", recruitWhitelistCheckbox.OnCheckChanged)
        State.widgets.recruit_whitelist_checkbox = recruitWhitelistCheckbox

        local whitelistAutoInviteCheckbox = createCheckboxRow(
            listCard,
            "nuziRaidtoolsWhitelistAutoInvite",
            "Auto-invite enabled speakers without phrase match",
            14,
            258,
            286
        )
        whitelistAutoInviteCheckbox:SetChecked(settings.whitelist_auto_invite and true or false)
        function whitelistAutoInviteCheckbox:OnCheckChanged()
            settings.whitelist_auto_invite = self:GetChecked() and true or false
            Shared.SaveSettings()
            RaidManagerUi.SyncAutoInviteWidgets()
        end
        whitelistAutoInviteCheckbox:SetHandler("OnCheckChanged", whitelistAutoInviteCheckbox.OnCheckChanged)
        State.widgets.whitelist_auto_invite_checkbox = whitelistAutoInviteCheckbox

        local whitelistAutoInviteOnLoginCheckbox = createCheckboxRow(
            listCard,
            "nuziRaidtoolsWhitelistAutoInviteOnLogin",
            "Invite enabled names on login",
            30,
            286,
            270
        )
        whitelistAutoInviteOnLoginCheckbox:SetChecked(settings.whitelist_auto_invite_on_login and true or false)
        function whitelistAutoInviteOnLoginCheckbox:OnCheckChanged()
            settings.whitelist_auto_invite_on_login = self:GetChecked() and true or false
            Shared.SaveSettings()
            RaidManagerUi.SyncAutoInviteWidgets()
        end
        whitelistAutoInviteOnLoginCheckbox:SetHandler("OnCheckChanged", whitelistAutoInviteOnLoginCheckbox.OnCheckChanged)
        State.widgets.whitelist_auto_invite_on_login_checkbox = whitelistAutoInviteOnLoginCheckbox

        local whitelistAutoInviteOnCadenceCheckbox = createCheckboxRow(
            listCard,
            "nuziRaidtoolsWhitelistAutoInviteOnCadence",
            "Invite enabled names every 60s",
            30,
            314,
            270
        )
        whitelistAutoInviteOnCadenceCheckbox:SetChecked(settings.whitelist_auto_invite_on_cadence and true or false)
        function whitelistAutoInviteOnCadenceCheckbox:OnCheckChanged()
            settings.whitelist_auto_invite_on_cadence = self:GetChecked() and true or false
            Runtime.ResetAutoInviteCadenceTicker()
            Shared.SaveSettings()
            RaidManagerUi.SyncAutoInviteWidgets()
        end
        whitelistAutoInviteOnCadenceCheckbox:SetHandler("OnCheckChanged", whitelistAutoInviteOnCadenceCheckbox.OnCheckChanged)
        State.widgets.whitelist_auto_invite_on_cadence_checkbox = whitelistAutoInviteOnCadenceCheckbox

        local whitelistHelp = createWrappedThemedLabel(
            listCard,
            "nuziRaidtoolsWhitelistInviteHelp",
            "Enabled lists also drive reply gating, login invites, and cadence invites.",
            10,
            cardWidth - 28,
            "hint",
            2,
            14
        )
        if whitelistHelp ~= nil then
            whitelistHelp:AddAnchor("TOPLEFT", listCard, 14, 342)
        end
    end
    sectionY = sectionY + 382

    local rolesCard = createSectionCard(
        content,
        "nuziRaidtoolsRolesCard",
        "Roles",
        "Keep your preferred role.",
        sectionY,
        cardWidth,
        132
    )
    if rolesCard ~= nil then
        local roleLabel = createThemedLabel(rolesCard, "nuziRaidtoolsRoleLabel", "Auto Role", 12, 220, 18, "text")
        if roleLabel ~= nil then
            roleLabel:AddAnchor("TOPLEFT", rolesCard, 14, 68)
        end

        local roleDropdown = Utils.CreateComboBox(rolesCard, { "Tank (Green)", "Healer (Pink)", "DPS (Red)", "Undecided (Blue)" }, cardWidth - 28, 30)
        roleDropdown:AddAnchor("TOPLEFT", rolesCard, 14, 88)
        function roleDropdown:SelectedProc()
            if self.__nuzi_syncing_role then
                return
            end
            local selectedRole = Runtime.NormalizeRoleSelection(self:GetSelectedIndex(), { allow_zero_undecided = true })
            if selectedRole ~= nil then
                Runtime.SaveRole(selectedRole)
                if api.Team ~= nil and api.Team.SetRole ~= nil then
                    pcall(function()
                        api.Team:SetRole(selectedRole)
                    end)
                end
            end
        end
        State.widgets.role_dropdown = roleDropdown
    end
    sectionY = sectionY + 144

    local leadCard = createSectionCard(
        content,
        "nuziRaidtoolsLeadCard",
        "Lead Handoff",
        "Swap lead between players.",
        sectionY,
        cardWidth,
        280
    )
    if leadCard ~= nil then
        local giveLeadWhitelistCheckbox = createCheckboxRow(
            leadCard,
            "nuziRaidtoolsGiveLeadWhitelist",
            "Only approved names can trigger give lead",
            14,
            68,
            286
        )
        giveLeadWhitelistCheckbox:SetChecked(settings.give_lead_whitelist_enabled and true or false)
        function giveLeadWhitelistCheckbox:OnCheckChanged()
            settings.give_lead_whitelist_enabled = self:GetChecked() and true or false
            Shared.SaveSettings()
            RaidManagerUi.SyncWhitelistWidgets()
        end
        giveLeadWhitelistCheckbox:SetHandler("OnCheckChanged", giveLeadWhitelistCheckbox.OnCheckChanged)
        State.widgets.give_lead_whitelist_checkbox = giveLeadWhitelistCheckbox

        local leadSniffingCheckbox = createCheckboxRow(
            leadCard,
            "nuziRaidtoolsLeadSniffing",
            "Allow chat-based lead handoff",
            14,
            94,
            286
        )
        leadSniffingCheckbox:SetChecked(settings.lead_sniffing and true or false)
        function leadSniffingCheckbox:OnCheckChanged()
            settings.lead_sniffing = self:GetChecked() and true or false
            Shared.SaveSettings()
            RaidManagerUi.SyncLeadWidgets()
        end
        leadSniffingCheckbox:SetHandler("OnCheckChanged", leadSniffingCheckbox.OnCheckChanged)
        State.widgets.lead_sniffing_checkbox = leadSniffingCheckbox

        local leadCodeWordLabel = createThemedLabel(leadCard, "nuziRaidtoolsLeadCodeWordLabel", "Lead Code Word", 12, 220, 18, "text")
        if leadCodeWordLabel ~= nil then
            leadCodeWordLabel:AddAnchor("TOPLEFT", leadCard, 14, 124)
        end

        local leadCodeWordInput = Utils.CreateEditBox(leadCard, "nuziRaidtoolsLeadCodeWordInput", "give lead", 244, 30, 64)
        leadCodeWordInput:AddAnchor("TOPLEFT", leadCard, 14, 144)
        leadCodeWordInput:SetText(tostring(settings.lead_code_word or "give lead"))
        State.widgets.lead_code_word_input = leadCodeWordInput

        local leadCodeWordSave = Utils.CreateButton(leadCard, "nuziRaidtoolsLeadCodeWordSave", "Save", 58, 30)
        leadCodeWordSave:AddAnchor("TOPLEFT", leadCard, 258, 144)
        leadCodeWordSave:SetHandler("OnClick", function()
            local saved = Runtime.SaveLeadCodeWord(leadCodeWordInput:GetText() or "")
            if leadCodeWordInput.SetText ~= nil then
                leadCodeWordInput:SetText(saved)
            end
        end)
        State.widgets.lead_code_word_save = leadCodeWordSave

        local giveLeadWhitelistLabel = createThemedLabel(leadCard, "nuziRaidtoolsGiveLeadWhitelistLabel", "Give Lead Whitelist", 12, 220, 18, "text")
        if giveLeadWhitelistLabel ~= nil then
            giveLeadWhitelistLabel:AddAnchor("TOPLEFT", leadCard, 14, 180)
        end

        local giveLeadWhitelistInput = Utils.CreateEditBox(leadCard, "nuziRaidtoolsGiveLeadWhitelistInput", "Character names", 244, 30, 512)
        giveLeadWhitelistInput:AddAnchor("TOPLEFT", leadCard, 14, 200)
        giveLeadWhitelistInput:SetText(Shared.JoinCommaList(settings.give_lead_whitelist))
        State.widgets.give_lead_whitelist_input = giveLeadWhitelistInput

        local giveLeadWhitelistSave = Utils.CreateButton(leadCard, "nuziRaidtoolsGiveLeadWhitelistSave", "Save", 58, 30)
        giveLeadWhitelistSave:AddAnchor("TOPLEFT", leadCard, 258, 200)
        giveLeadWhitelistSave:SetHandler("OnClick", function()
            giveLeadWhitelistInput:SetText(Runtime.SaveGiveLeadWhitelist(giveLeadWhitelistInput:GetText()))
        end)
        State.widgets.give_lead_whitelist_save = giveLeadWhitelistSave

        local leadHelp = createWrappedThemedLabel(
            leadCard,
            "nuziRaidtoolsLeadHelp",
            "The give lead list can be edited in the list manager.",
            10,
            cardWidth - 28,
            "hint",
            2,
            14
        )
        if leadHelp ~= nil then
            leadHelp:AddAnchor("TOPLEFT", leadCard, 14, 236)
        end
    end
    sectionY = sectionY + 292

    scrollFrame:ResetScroll(sectionY + 8)
end

function RaidManagerUi.ClearRaidManagerWidgets()
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

function RaidManagerUi.CreateFloatingButton()
    if State.floating_button ~= nil then
        return
    end
    local button = Utils.CreateButton("UIParent", "nuziRaidtoolsFloatingRecruit", Runtime.GetRecruitButtonText(), 140, 30)
    FloatingButtonPositions:ApplyAndBind(button, nil, "floating_button", {
        anchor = "TOPLEFT",
        relative_to = "UIParent",
        target_anchor = "TOPLEFT"
    })
    button:SetHandler("OnClick", function()
        local raw = State.widgets.recruit_textfield ~= nil and State.widgets.recruit_textfield:GetText() or getSettings().last_recruit_message
        if Runtime.ToggleRecruiting(raw) then
            RaidManagerUi.SyncRecruitWidgets()
        end
    end)
    State.floating_button = button
    RaidManagerUi.SyncRecruitWidgets()
end

function RaidManagerUi.BuildRaidManagerUi()
    local settings = getSettings()
    local raidManager = nil
    pcall(function()
        raidManager = ADDON:GetContent(UIC.RAID_MANAGER)
    end)
    if raidManager == nil then
        return
    end
    RaidManagerUi.ClearRaidManagerWidgets()
    State.raid_manager = raidManager
    pcall(function()
        State.raid_manager_original_width, State.raid_manager_original_height = raidManager:GetExtent()
    end)
    local currentWidth = raidManager:GetWidth()
    if type(currentWidth) ~= "number" or currentWidth <= 0 then
        currentWidth = tonumber(State.raid_manager_original_width) or 760
    end
    local stockExtraWidth = 260
    local totalWidth = currentWidth + stockExtraWidth
    pcall(function()
        raidManager:SetExtent(totalWidth, 760)
    end)
    raidManager.__nuzi_raidtools_stock_width = currentWidth + stockExtraWidth
    RaidManagerUi.PatchRaidManagerMembers(raidManager)

    local settingsToggleButton = Utils.CreateButton(raidManager, "nuziRaidtoolsSettingsToggle", "Show Settings", 110, 26)
    if settingsToggleButton ~= nil then
        settingsToggleButton:AddAnchor("TOPRIGHT", raidManager, -16, 8)
        settingsToggleButton:SetHandler("OnClick", function()
            RaidManagerUi.ToggleSettingsPanel()
        end)
        State.widgets.settings_toggle_button = settingsToggleButton
    end

    buildAttachedRaidManagerSettings(raidManager, settings)

    ListManager.Init(settings, {
        SaveSettings = function()
            Shared.SaveSettings()
        end,
        OnBlacklistUpdate = function()
            Runtime.RebuildBlacklistLookup()
        end,
        OnWhitelistUpdate = function()
            RaidManagerUi.RefreshActiveWhitelistDropdown()
        end,
        OnListChanged = function(listName)
            if listName == "Give Lead Whitelist" then
                Runtime.RebuildGiveLeadWhitelistLookup()
            end
            RaidManagerUi.SyncListBackedInputs()
            RaidManagerUi.SyncWhitelistWidgets()
        end
    })

    RaidManagerUi.SyncAll()
end

function RaidManagerUi.RefreshRaidInfoOverlay()
    if not isWidgetVisible(State.raid_manager) then
        return
    end
    for _, memberFrame in ipairs(State.patched_member_frames) do
        if type(memberFrame) == "table" then
            applyStockMemberText(memberFrame)
        end
    end
end

function RaidManagerUi.Unload()
    RaidManagerUi.ClearRaidManagerWidgets()
    if State.floating_button ~= nil then
        Utils.SafeFree(State.floating_button)
        State.floating_button = nil
    end
end

return RaidManagerUi
