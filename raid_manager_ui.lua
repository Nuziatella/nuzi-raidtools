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

local FLOATING_ICON_MIN_SIZE = 32
local FLOATING_ICON_MAX_SIZE = 96
local FLOATING_ICON_ASPECT = 1.5
local RAID_MANAGER_SKIN_WIDTH = 900
local RAID_MANAGER_FALLBACK_HEIGHT = 395
local RAID_SORT_OPTIONS = {
    "Tanks > Healers > DPS",
    "Healers > Tanks > DPS",
    "Gearscore High > Low",
    "Gearscore Low > High"
}
local RAID_GROUP_OPTIONS = {
    "Any",
    "Group 1",
    "Group 2",
    "Group 3",
    "Group 4",
    "Group 5",
    "Group 6",
    "Group 7",
    "Group 8",
    "Group 9",
    "Group 10"
}
local RAID_ROLE_ORDER_OPTIONS = {
    "Tank",
    "Healer",
    "DPS",
    "Undecided"
}
local RAID_SLOT_ROLE_OPTIONS = {
    "Any",
    "Tank",
    "Heal",
    "DPS",
    "Und"
}
local RAID_GEAR_ORDER_OPTIONS = {
    "Gearscore High > Low",
    "Gearscore Low > High",
    "Ignore Gearscore"
}
local RAID_NAME_ORDER_OPTIONS = {
    "Name A > Z",
    "Name Z > A",
    "Ignore Name"
}
local FLOATING_BUTTON_POSITION_MAPPINGS = {
    floating_button = {
        x = "floating_button_x",
        y = "floating_button_y"
    }
}

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
            mappings = FLOATING_BUTTON_POSITION_MAPPINGS,
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

local function normalizeUnitId(unitId)
    local valueType = type(unitId)
    if valueType == "string" then
        local text = trimText(unitId)
        if text ~= "" and text ~= "0" then
            return text
        end
    elseif valueType == "number" and unitId ~= 0 then
        return tostring(unitId)
    end
    return nil
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

local function safeSetExtent(widget, width, height)
    if widget == nil or widget.SetExtent == nil then
        return
    end
    widget:SetExtent(width, height)
end

local function safeSetTexture(drawable, path)
    if drawable == nil or drawable.SetTexture == nil or type(path) ~= "string" or path == "" then
        return
    end
    if drawable.__nuzi_texture == path then
        return
    end
    drawable.__nuzi_texture = path
    drawable:SetTexture(path)
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

local function assetPath(relativePath)
    local baseDir = type(api) == "table" and type(api.baseDir) == "string" and api.baseDir or ""
    baseDir = string.gsub(baseDir, "\\", "/")
    if baseDir ~= "" then
        return string.gsub(baseDir .. "/" .. tostring(relativePath or ""), "/+", "/")
    end
    return tostring(relativePath or "")
end

local function createImageDrawable(widget, id, path, layer, width, height)
    if widget == nil then
        return nil
    end
    local drawable = nil
    if widget.CreateImageDrawable ~= nil then
        drawable = widget:CreateImageDrawable(id, layer or "artwork")
    elseif widget.CreateDrawable ~= nil then
        drawable = widget:CreateDrawable(id, layer or "artwork")
    end
    if drawable == nil then
        return nil
    end
    safeSetTexture(drawable, path)
    if drawable.Clickable ~= nil then
        drawable:Clickable(false)
    end
    if drawable.EnablePick ~= nil then
        drawable:EnablePick(false)
    end
    if drawable.AddAnchor ~= nil then
        drawable:AddAnchor("TOPLEFT", widget, 0, 0)
    end
    safeSetExtent(drawable, width, height)
    safeShow(drawable, true)
    return drawable
end

local function clampNumber(value, minValue, maxValue, fallback)
    local number = tonumber(value)
    if number == nil then
        return fallback
    end
    if number < minValue then
        return minValue
    elseif number > maxValue then
        return maxValue
    end
    return number
end

local function getFloatingIconSize(settings)
    return math.floor(clampNumber(
        settings ~= nil and settings.floating_icon_size or nil,
        FLOATING_ICON_MIN_SIZE,
        FLOATING_ICON_MAX_SIZE,
        Shared.DEFAULT_SETTINGS.floating_icon_size or 40
    ) + 0.5)
end

local function createSlider(parent, id, width, minValue, maxValue)
    local slider = nil
    if Core ~= nil and Core.UI ~= nil and Core.UI.CreateSlider ~= nil then
        slider = Core.UI.CreateSlider(id, parent)
    end
    if slider == nil and api._Library ~= nil and api._Library.UI ~= nil and api._Library.UI.CreateSlider ~= nil then
        slider = api._Library.UI.CreateSlider(id, parent)
    end
    if slider == nil then
        return nil
    end
    safeSetExtent(slider, width, 26)
    if slider.SetMinMaxValues ~= nil then
        slider:SetMinMaxValues(minValue, maxValue)
    end
    if slider.SetStep ~= nil then
        slider:SetStep(1)
    elseif slider.SetValueStep ~= nil then
        slider:SetValueStep(1)
    end
    safeShow(slider, true)
    return slider
end

local function safeSetSliderValue(slider, value)
    if slider == nil or slider.SetValue == nil then
        return
    end
    slider:SetValue(value, false)
end

local function safeSelectDropdown(dropdown, index)
    if dropdown ~= nil and dropdown.Select ~= nil then
        dropdown:Select(index)
    end
end

local function getGroupDropdownIndex(group)
    return math.floor(clampNumber(group, 0, #RAID_GROUP_OPTIONS - 1, 0) + 0.5) + 1
end

local function getGroupDropdownValue(dropdown)
    if dropdown == nil or dropdown.GetSelectedIndex == nil then
        return 0
    end
    return math.floor(clampNumber((dropdown:GetSelectedIndex() or 1) - 1, 0, #RAID_GROUP_OPTIONS - 1, 0) + 0.5)
end

local function getSlotRoleDropdownIndex(role)
    return math.floor(clampNumber(role, 0, #RAID_SLOT_ROLE_OPTIONS - 1, 0) + 0.5) + 1
end

local function getSlotRoleDropdownValue(dropdown)
    if dropdown == nil or dropdown.GetSelectedIndex == nil then
        return 0
    end
    return math.floor(clampNumber((dropdown:GetSelectedIndex() or 1) - 1, 0, #RAID_SLOT_ROLE_OPTIONS - 1, 0) + 0.5)
end

local function getCustomSortEntries(settings)
    local entries = {}
    if type(settings) == "table" and type(settings.raid_custom_sort_presets) == "table" then
        for key, preset in pairs(settings.raid_custom_sort_presets) do
            if type(preset) == "table" then
                local name = trimText(preset.name or key)
                if name ~= "" then
                    entries[#entries + 1] = {
                        key = key,
                        name = name,
                        preset = preset
                    }
                end
            end
        end
    end
    table.sort(entries, function(a, b)
        return string.lower(a.name) < string.lower(b.name)
    end)
    return entries
end

local function buildRaidSortDropdownItems(settings)
    local items = {}
    local ids = {}
    for index, label in ipairs(RAID_SORT_OPTIONS) do
        items[#items + 1] = label
        ids[#ids + 1] = "builtin:" .. tostring(index)
    end
    for _, entry in ipairs(getCustomSortEntries(settings)) do
        items[#items + 1] = "Custom: " .. entry.name
        ids[#ids + 1] = "custom:" .. entry.key
    end
    return items, ids
end

local function getRaidSortSelectionIndex(settings, ids)
    local selected = trimText(settings ~= nil and settings.raid_sort_preset or "")
    if selected == "" then
        local fallbackMode = settings ~= nil and tonumber(settings.raid_sort_mode) or 1
        selected = "builtin:" .. tostring(fallbackMode or 1)
    end
    for index, id in ipairs(ids or {}) do
        if id == selected then
            return index
        end
    end
    return 1
end

local function refreshRaidSortDropdown()
    local dropdown = State.widgets.raid_sort_mode_dropdown
    if dropdown == nil then
        return
    end
    local settings = getSettings()
    local items, ids = buildRaidSortDropdownItems(settings)
    dropdown.dropdownItem = items
    State.raid_sort_preset_ids = ids
    dropdown.__nuzi_syncing_sort = true
    safeSelectDropdown(dropdown, getRaidSortSelectionIndex(settings, ids))
    dropdown.__nuzi_syncing_sort = false
end

local function refreshRaidSortBuilderPresetDropdown()
    local dropdown = State.widgets.raid_sort_builder_preset_dropdown
    if dropdown == nil then
        return
    end
    local items = { "New Preset" }
    local ids = { "" }
    for _, entry in ipairs(getCustomSortEntries(getSettings())) do
        items[#items + 1] = entry.name
        ids[#ids + 1] = entry.key
    end
    dropdown.dropdownItem = items
    State.raid_sort_builder_preset_ids = ids
    local selectedIndex = 1
    local selectedKey = State.raid_sort_builder_key or ""
    for index, key in ipairs(ids) do
        if key == selectedKey then
            selectedIndex = index
            break
        end
    end
    dropdown.__nuzi_syncing_builder = true
    safeSelectDropdown(dropdown, selectedIndex)
    dropdown.__nuzi_syncing_builder = false
end

local function getCustomSortPreset(key)
    local settings = getSettings()
    if key ~= nil and key ~= "" and type(settings.raid_custom_sort_presets) == "table" then
        return settings.raid_custom_sort_presets[key]
    end
    return nil
end

local function getBuilderRoleDropdown(index)
    return State.widgets["raid_sort_builder_role_" .. tostring(index)]
end

local function getBuilderRoleGroupDropdown(role)
    return State.widgets["raid_sort_builder_group_" .. tostring(role)]
end

local function getBuilderSlotRoleDropdown(slot)
    return State.widgets["raid_sort_builder_slot_" .. tostring(slot)]
end

local function normalizeBuilderSlotRoles(value)
    local out = {}
    if type(value) == "table" then
        for slot = 1, Shared.CONSTANTS.RAID_MAX_MEMBERS do
            local role = math.floor((tonumber(value[slot] or value[tostring(slot)]) or 0) + 0.5)
            if role >= 1 and role <= 4 then
                out[slot] = role
            end
        end
    end
    return out
end

local function syncSlotLayoutDropdowns()
    local slotRoles = normalizeBuilderSlotRoles(State.raid_sort_builder_slot_roles)
    for slot = 1, Shared.CONSTANTS.RAID_MAX_MEMBERS do
        safeSelectDropdown(getBuilderSlotRoleDropdown(slot), getSlotRoleDropdownIndex(slotRoles[slot] or 0))
    end
end

local function getWidgetText(widget)
    if widget ~= nil and widget.GetText ~= nil then
        return tostring(widget:GetText() or "")
    end
    return ""
end

local function readBuilderRoleOrder()
    local out = {}
    local seen = {}
    for index = 1, 4 do
        local dropdown = getBuilderRoleDropdown(index)
        local role = dropdown ~= nil and dropdown.GetSelectedIndex ~= nil and tonumber(dropdown:GetSelectedIndex()) or index
        if role ~= nil and role >= 1 and role <= 4 and not seen[role] then
            seen[role] = true
            out[#out + 1] = role
        end
    end
    for role = 1, 4 do
        if not seen[role] then
            out[#out + 1] = role
        end
    end
    return out
end

local function readBuilderRoleGroups()
    local out = {}
    for role = 1, 4 do
        out[role] = getGroupDropdownValue(getBuilderRoleGroupDropdown(role))
    end
    return out
end

local function readBuilderSlotRoles()
    return normalizeBuilderSlotRoles(State.raid_sort_builder_slot_roles)
end

local function readRaidSortBuilderPresetFromWidgets()
    local name = string.sub(trimText(getWidgetText(State.widgets.raid_sort_builder_name_input)), 1, 32)
    local gearDropdown = State.widgets.raid_sort_builder_gear_dropdown
    local nameDropdown = State.widgets.raid_sort_builder_name_dropdown
    return {
        name = name,
        role_order = readBuilderRoleOrder(),
        role_groups = readBuilderRoleGroups(),
        slot_roles = readBuilderSlotRoles(),
        gear_order = gearDropdown ~= nil and gearDropdown.GetSelectedIndex ~= nil and gearDropdown:GetSelectedIndex() or 1,
        name_order = nameDropdown ~= nil and nameDropdown.GetSelectedIndex ~= nil and nameDropdown:GetSelectedIndex() or 1
    }
end

local function setRaidSortBuilderFields(key, clearDraft)
    State.raid_sort_builder_key = key or ""
    local settings = getSettings()
    local draft = type(settings.raid_sort_builder_draft) == "table" and settings.raid_sort_builder_draft or nil
    local preset = getCustomSortPreset(State.raid_sort_builder_key)
    if preset == nil and not clearDraft then
        preset = draft
    end
    preset = preset or {
        name = "",
        role_order = { 1, 2, 3, 4 },
        role_groups = { 0, 0, 0, 0 },
        slot_roles = {},
        gear_order = 1,
        name_order = 1
    }
    if State.widgets.raid_sort_builder_name_input ~= nil then
        State.widgets.raid_sort_builder_name_input:SetText(tostring(preset.name or ""))
    end
    for index = 1, 4 do
        local dropdown = getBuilderRoleDropdown(index)
        local role = tonumber(type(preset.role_order) == "table" and preset.role_order[index]) or index
        safeSelectDropdown(dropdown, math.floor(clampNumber(role, 1, 4, index) + 0.5))
    end
    for role = 1, 4 do
        local roleGroups = type(preset.role_groups) == "table" and preset.role_groups or nil
        safeSelectDropdown(getBuilderRoleGroupDropdown(role), getGroupDropdownIndex(roleGroups ~= nil and roleGroups[role] or 0))
    end
    State.raid_sort_builder_slot_roles = normalizeBuilderSlotRoles(preset.slot_roles)
    syncSlotLayoutDropdowns()
    safeSelectDropdown(State.widgets.raid_sort_builder_gear_dropdown, math.floor(clampNumber(preset.gear_order, 1, 3, 1) + 0.5))
    safeSelectDropdown(State.widgets.raid_sort_builder_name_dropdown, math.floor(clampNumber(preset.name_order, 1, 3, 1) + 0.5))
    refreshRaidSortBuilderPresetDropdown()
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

local function hideRaidSortSlotLayoutWindow()
    if State.widgets.raid_sort_slot_layout_window ~= nil then
        safeShow(State.widgets.raid_sort_slot_layout_window, false)
    end
end

local function buildRaidSortSlotLayoutWindow()
    if State.widgets.raid_sort_slot_layout_window ~= nil then
        return State.widgets.raid_sort_slot_layout_window
    end
    if api.Interface == nil then
        return nil
    end

    local window = nil
    if api.Interface.CreateEmptyWindow ~= nil then
        window = api.Interface:CreateEmptyWindow("nuziRaidtoolsSortSlotLayoutWindow", "UIParent")
    elseif api.Interface.CreateWindow ~= nil then
        window = api.Interface:CreateWindow("nuziRaidtoolsSortSlotLayoutWindow", "Slot Layout", 0, 0)
    end
    if window == nil then
        return nil
    end
    window:SetExtent(430, 520)
    if State.widgets.raid_sort_builder_window ~= nil then
        safeAddAnchor(window, "TOPLEFT", State.widgets.raid_sort_builder_window, "TOPRIGHT", 12, 0)
    elseif State.widgets.settings_window ~= nil then
        safeAddAnchor(window, "TOPLEFT", State.widgets.settings_window, "TOPRIGHT", 12, 0)
    else
        safeAddAnchor(window, "CENTER", "UIParent", nil, 0, 0)
    end
    applyPanelBackground(window, 0.94)
    applyPanelAccent(window, 36, 0.10)
    applyPanelDivider(window, 36, 12, -12, 0.14)
    safeShow(window, false)
    State.widgets.raid_sort_slot_layout_window = window

    local title = createThemedLabel(window, "nuziRaidtoolsSortSlotLayoutTitle", "Slot Layout", 15, 260, 18, "title")
    if title ~= nil then
        title:AddAnchor("TOPLEFT", window, 14, 8)
    end

    local closeButton = Utils.CreateButton(window, "nuziRaidtoolsSortSlotLayoutClose", "X", 26, 22)
    if closeButton ~= nil then
        closeButton:AddAnchor("TOPRIGHT", window, -10, 6)
        closeButton:SetHandler("OnClick", function()
            hideRaidSortSlotLayoutWindow()
        end)
    end

    for partySlot = 1, Shared.CONSTANTS.RAID_GROUP_SIZE do
        local label = createThemedLabel(window, "nuziRaidtoolsSortSlotLayoutHeader" .. tostring(partySlot), "S" .. tostring(partySlot), 10, 58, 16, "hint")
        if label ~= nil then
            label:AddAnchor("TOPLEFT", window, 58 + ((partySlot - 1) * 70), 48)
        end
    end

    for group = 1, Shared.CONSTANTS.RAID_GROUP_COUNT do
        local rowY = 70 + ((group - 1) * 36)
        local groupLabel = createThemedLabel(window, "nuziRaidtoolsSortSlotLayoutGroup" .. tostring(group), "G" .. tostring(group), 11, 32, 18, "hint")
        if groupLabel ~= nil then
            groupLabel:AddAnchor("TOPLEFT", window, 18, rowY + 6)
        end
        for partySlot = 1, Shared.CONSTANTS.RAID_GROUP_SIZE do
            local slot = ((group - 1) * Shared.CONSTANTS.RAID_GROUP_SIZE) + partySlot
            local dropdown = Utils.CreateComboBox(window, RAID_SLOT_ROLE_OPTIONS, 64, 28)
            dropdown:AddAnchor("TOPLEFT", window, 50 + ((partySlot - 1) * 70), rowY)
            dropdown.__nuzi_slot = slot
            function dropdown:SelectedProc()
                local slotRoles = normalizeBuilderSlotRoles(State.raid_sort_builder_slot_roles)
                local role = getSlotRoleDropdownValue(self)
                if role > 0 then
                    slotRoles[self.__nuzi_slot] = role
                else
                    slotRoles[self.__nuzi_slot] = nil
                end
                State.raid_sort_builder_slot_roles = slotRoles
            end
            State.widgets["raid_sort_builder_slot_" .. tostring(slot)] = dropdown
        end
    end

    local clearButton = Utils.CreateButton(window, "nuziRaidtoolsSortSlotLayoutClear", "Clear", 92, 30)
    clearButton:AddAnchor("TOPLEFT", window, 18, 478)
    clearButton:SetHandler("OnClick", function()
        State.raid_sort_builder_slot_roles = {}
        syncSlotLayoutDropdowns()
    end)

    local copyButton = Utils.CreateButton(window, "nuziRaidtoolsSortSlotLayoutCopy", "Copy G1", 92, 30)
    copyButton:AddAnchor("TOPLEFT", window, 122, 478)
    copyButton:SetHandler("OnClick", function()
        local slotRoles = normalizeBuilderSlotRoles(State.raid_sort_builder_slot_roles)
        local template = {}
        for partySlot = 1, Shared.CONSTANTS.RAID_GROUP_SIZE do
            template[partySlot] = slotRoles[partySlot] or 0
        end
        local out = {}
        for group = 1, Shared.CONSTANTS.RAID_GROUP_COUNT do
            for partySlot = 1, Shared.CONSTANTS.RAID_GROUP_SIZE do
                local role = template[partySlot]
                if role > 0 then
                    out[((group - 1) * Shared.CONSTANTS.RAID_GROUP_SIZE) + partySlot] = role
                end
            end
        end
        State.raid_sort_builder_slot_roles = out
        syncSlotLayoutDropdowns()
    end)

    local doneButton = Utils.CreateButton(window, "nuziRaidtoolsSortSlotLayoutDone", "Done", 92, 30)
    doneButton:AddAnchor("TOPLEFT", window, 320, 478)
    doneButton:SetHandler("OnClick", function()
        hideRaidSortSlotLayoutWindow()
    end)

    syncSlotLayoutDropdowns()
    return window
end

local function toggleRaidSortSlotLayout()
    local window = buildRaidSortSlotLayoutWindow()
    if window == nil then
        return
    end
    local visible = false
    if window.IsVisible ~= nil then
        pcall(function()
            visible = window:IsVisible() and true or false
        end)
    end
    if not visible then
        syncSlotLayoutDropdowns()
    end
    safeShow(window, not visible)
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

local function createFloatingButtonWindow(width, height)
    local window = nil
    if api.Interface ~= nil and api.Interface.CreateEmptyWindow ~= nil then
        window = api.Interface:CreateEmptyWindow("nuziRaidtoolsFloatingRecruit", "UIParent")
    elseif api.Interface ~= nil and api.Interface.CreateWidget ~= nil then
        window = api.Interface:CreateWidget("button", "nuziRaidtoolsFloatingRecruit", "UIParent")
    end
    if window == nil then
        return nil
    end
    safeSetExtent(window, width, height)
    safeSetText(window, "")
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
    addAllowed(memberFrame.eventWindow, 0)
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

    if depth <= 0 then
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
        unitId = normalizeUnitId(unitId)
    end
    if unitId ~= nil and api.Unit ~= nil and api.Unit.GetUnitInfoById ~= nil then
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
    local gsWidth = 42
    local classWidth = math.max(36, math.min(48, math.floor(rowWidth * 0.22)))
    local nameWidth = math.max(48, rowWidth - gsWidth - classWidth - 22)
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
        configureStockLabel(gsLabel, gsWidth, ALIGN.RIGHT, { 0.95, 0.84, 0.46, 1 }, 11, 18)
        safeRemoveAllAnchors(gsLabel)
        safeAddAnchor(gsLabel, "TOPRIGHT", memberFrame, nil, -4, 0)
        safeShow(gsLabel, true)
    end

    if classTextLabel ~= nil then
        configureStockLabel(classTextLabel, classWidth, ALIGN.CENTER, classColor, 11, 18)
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
        local party = memberFrame.__nuzi_raidtools_party or memberFrame.party or 0
        local slot = memberFrame.__nuzi_raidtools_slot or memberFrame.memberIndex or memberFrame.slot or 0
        label = memberFrame:CreateChildWidget(
            "label",
            prefix .. tostring(party) .. "_" .. tostring(slot),
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

local function getRaidUnitDisplayName(unitToken, unitId, info, infoById)
    if api.Unit ~= nil and api.Unit.UnitName ~= nil and unitToken ~= nil and unitToken ~= "" then
        local ok, value = pcall(function()
            return api.Unit:UnitName(unitToken)
        end)
        value = trimText(value)
        if ok and value ~= "" then
            return value
        end
    end

    unitId = normalizeUnitId(unitId)
    if api.Unit ~= nil and api.Unit.GetUnitNameById ~= nil and unitId ~= nil then
        local ok, value = pcall(function()
            return api.Unit:GetUnitNameById(unitId)
        end)
        value = trimText(value)
        if ok and value ~= "" then
            return value
        end
    end

    local displayName = trimText(
        (type(info) == "table" and (info.name or info.unitName or info.family_name))
        or (type(infoById) == "table" and (infoById.name or infoById.unitName or infoById.family_name))
        or ""
    )
    if displayName ~= "" then
        return displayName
    end

    return ""
end

local function clearStockMemberText(memberFrame)
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
end

local function applyStockMemberText(memberFrame)
    if type(memberFrame) ~= "table" then
        return
    end
    local unitToken = trimText(memberFrame.__nuzi_raidtools_unit_token or memberFrame.target)
    if unitToken == "" then
        clearStockMemberText(memberFrame)
        return
    end

    local info, unitId, infoById = getRaidUnitContext(unitToken)
    local displayName = getRaidUnitDisplayName(unitToken, unitId, info, infoById)
    if displayName == "" then
        clearStockMemberText(memberFrame)
        return
    end
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

    local columns = 5
    local leftPad = 12
    local topPad = 38
    local colGap = 8
    local rowGap = 12
    local headerHeight = 18
    local rowHeight = 18
    local rowSpacing = 1
    local columnWidth = math.max(150, math.floor((stockWidth - leftPad * 2 - colGap * (columns - 1)) / columns))
    local partyHeight = headerHeight + 4 + rowHeight * 5 + rowSpacing * 4
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
            memberFrame.__nuzi_raidtools_unit_token = "team" .. tostring((partyIndex - 1) * 5 + slot)
            memberFrame.__nuzi_raidtools_party = partyIndex
            memberFrame.__nuzi_raidtools_slot = slot
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
            local stockWidth = tonumber(self.__nuzi_raidtools_stock_width) or RAID_MANAGER_SKIN_WIDTH
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
    local stockWidth = tonumber(raidManager.__nuzi_raidtools_stock_width) or RAID_MANAGER_SKIN_WIDTH
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

local function getFloatingIconPath(isRecruiting)
    if isRecruiting then
        return assetPath("nuzi-raidtools/auto_on.png")
    end
    return assetPath("nuzi-raidtools/auto_off.png")
end

local function getFloatingIconExtent(settings)
    local height = getFloatingIconSize(settings)
    return math.floor((height * FLOATING_ICON_ASPECT) + 0.5), height
end

local function applyFloatingButtonLayout()
    if State.floating_button == nil then
        return
    end
    local width, height = getFloatingIconExtent(getSettings())
    safeSetExtent(State.floating_button, width, height)
    safeSetText(State.floating_button, "")
    if State.floating_button_icon ~= nil then
        safeSetExtent(State.floating_button_icon, width, height)
    end
end

local function syncFloatingButtonIcon()
    if State.floating_button == nil then
        return
    end
    local settings = getSettings()
    local width, height = getFloatingIconExtent(settings)
    if State.floating_button_icon == nil then
        State.floating_button_icon = createImageDrawable(
            State.floating_button,
            "nuziRaidtoolsFloatingRecruitIcon",
            getFloatingIconPath(settings.is_recruiting),
            "artwork",
            width,
            height
        )
    end
    safeSetTexture(State.floating_button_icon, getFloatingIconPath(settings.is_recruiting))
    safeSetExtent(State.floating_button_icon, width, height)
    safeShow(State.floating_button_icon, true)
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
    local settings = getSettings()
    local isRecruiting = settings.is_recruiting and true or false
    local text = Runtime.GetRecruitButtonText()
    if State.widgets.recruit_button ~= nil then
        State.widgets.recruit_button:SetText(text)
    end
    if State.widgets.floating_icon_size_value ~= nil then
        safeSetText(State.widgets.floating_icon_size_value, tostring(getFloatingIconSize(settings)))
    end
    if State.widgets.floating_icon_size_slider ~= nil then
        safeSetSliderValue(State.widgets.floating_icon_size_slider, getFloatingIconSize(settings))
    end
    if State.widgets.always_visible_checkbox ~= nil then
        State.widgets.always_visible_checkbox:SetChecked(settings.always_visible and true or false)
    end
    if State.floating_button ~= nil then
        applyFloatingButtonLayout()
        syncFloatingButtonIcon()
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
    if State.widgets.remote_auto_invite_controls_checkbox ~= nil then
        State.widgets.remote_auto_invite_controls_checkbox:SetChecked(settings.remote_auto_invite_controls and true or false)
    end
    if State.widgets.guild_auto_learn_checkbox ~= nil then
        State.widgets.guild_auto_learn_checkbox:SetChecked(settings.guild_auto_learn and true or false)
    end
    if State.widgets.expedition_sync_checkbox ~= nil then
        State.widgets.expedition_sync_checkbox:SetChecked(settings.expedition_sync_enabled and true or false)
    end
    if State.widgets.expedition_sync_name_input ~= nil and State.widgets.expedition_sync_name_input.SetText ~= nil then
        State.widgets.expedition_sync_name_input:SetText(tostring(settings.expedition_sync_name or "macro"))
    end
end

function RaidManagerUi.SyncRaidSortWidgets()
    refreshRaidSortDropdown()
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
    RaidManagerUi.CaptureSettingsInputs()
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
    RaidManagerUi.SyncRaidSortWidgets()
    RaidManagerUi.SyncLeadWidgets()
    RaidManagerUi.SyncRoleDropdownSelection()
    RaidManagerUi.SyncRecruitWidgets()
    RaidManagerUi.SyncSettingsPanelVisibility()
end

function RaidManagerUi.CaptureSettingsInputs()
    if Shared == nil or State == nil or type(State.widgets) ~= "table" then
        return
    end
    local settings = getSettings()

    if State.widgets.recruit_textfield ~= nil then
        settings.last_recruit_message = string.lower(getWidgetText(State.widgets.recruit_textfield))
    end

    if State.widgets.filter_dropdown ~= nil and State.widgets.filter_dropdown.GetSelectedIndex ~= nil then
        settings.filter_selection = State.widgets.filter_dropdown:GetSelectedIndex()
    end
    if State.widgets.chat_filter_dropdown ~= nil and State.widgets.chat_filter_dropdown.GetSelectedIndex ~= nil then
        settings.dms_selection = State.widgets.chat_filter_dropdown:GetSelectedIndex()
    end
    if State.widgets.active_whitelist_dropdown ~= nil and State.widgets.active_whitelist_dropdown.GetSelectedIndex ~= nil then
        local index = State.widgets.active_whitelist_dropdown:GetSelectedIndex()
        local selected = State.widgets.active_whitelist_dropdown.dropdownItem ~= nil and State.widgets.active_whitelist_dropdown.dropdownItem[index] or nil
        if selected ~= nil then
            settings.active_whitelist = tostring(selected)
        end
    end

    if State.widgets.expedition_sync_name_input ~= nil then
        settings.expedition_sync_name = trimText(getWidgetText(State.widgets.expedition_sync_name_input))
    end
    if State.widgets.lead_code_word_input ~= nil then
        settings.lead_code_word = trimText(getWidgetText(State.widgets.lead_code_word_input))
        if settings.lead_code_word == "" then
            settings.lead_code_word = "give lead"
        end
    end
    if State.widgets.give_lead_whitelist_input ~= nil then
        settings.give_lead_whitelist = Shared.ParseCommaList(getWidgetText(State.widgets.give_lead_whitelist_input), Utils.FormatName)
        if Runtime ~= nil and Runtime.RebuildGiveLeadWhitelistLookup ~= nil then
            Runtime.RebuildGiveLeadWhitelistLookup()
        end
    end

    if State.widgets.raid_sort_mode_dropdown ~= nil and State.widgets.raid_sort_mode_dropdown.GetSelectedIndex ~= nil then
        local ids = State.raid_sort_preset_ids or {}
        local selected = ids[State.widgets.raid_sort_mode_dropdown:GetSelectedIndex()]
        if selected ~= nil then
            settings.raid_sort_preset = selected
            local builtinMode = tonumber(string.match(selected, "^builtin:(%d+)$"))
            if builtinMode ~= nil then
                settings.raid_sort_mode = builtinMode
            end
        end
    end
    if State.widgets.raid_sort_builder_name_input ~= nil then
        local draft = readRaidSortBuilderPresetFromWidgets()
        settings.raid_sort_builder_draft = draft
        local key = normalizeKey(draft.name)
        if key ~= "" then
            if type(settings.raid_custom_sort_presets) ~= "table" then
                settings.raid_custom_sort_presets = {}
            end
            local oldKey = State.raid_sort_builder_key or ""
            if oldKey ~= "" and oldKey ~= key then
                settings.raid_custom_sort_presets[oldKey] = nil
            end
            settings.raid_custom_sort_presets[key] = draft
            settings.raid_sort_preset = "custom:" .. key
            State.raid_sort_builder_key = key
        end
    end

    Shared.NormalizeAutoInviteSettings(settings)
    Shared.NormalizeRaidSortSettings(settings)
end

local function buildRaidSortBuilderWindow()
    if State.widgets.raid_sort_builder_window ~= nil then
        return State.widgets.raid_sort_builder_window
    end

    local window = nil
    if api.Interface ~= nil and api.Interface.CreateEmptyWindow ~= nil then
        window = api.Interface:CreateEmptyWindow("nuziRaidtoolsSortBuilderWindow", "UIParent")
    elseif api.Interface ~= nil and api.Interface.CreateWindow ~= nil then
        window = api.Interface:CreateWindow("nuziRaidtoolsSortBuilderWindow", "Raid Sort Presets", 0, 0)
    end
    if window == nil then
        return nil
    end

    window:SetExtent(430, 430)
    if State.widgets.settings_window ~= nil then
        safeAddAnchor(window, "TOPLEFT", State.widgets.settings_window, "TOPRIGHT", 12, 0)
    else
        safeAddAnchor(window, "CENTER", "UIParent", nil, 0, 0)
    end
    applyPanelBackground(window, 0.94)
    applyPanelAccent(window, 36, 0.10)
    applyPanelDivider(window, 36, 12, -12, 0.14)
    safeShow(window, false)
    State.widgets.raid_sort_builder_window = window

    local title = createThemedLabel(window, "nuziRaidtoolsSortBuilderTitle", "Raid Sort Presets", 15, 260, 18, "title")
    if title ~= nil then
        title:AddAnchor("TOPLEFT", window, 14, 8)
    end

    local closeButton = Utils.CreateButton(window, "nuziRaidtoolsSortBuilderClose", "X", 26, 22)
    if closeButton ~= nil then
        closeButton:AddAnchor("TOPRIGHT", window, -10, 6)
        closeButton:SetHandler("OnClick", function()
            RaidManagerUi.CaptureSettingsInputs()
            Shared.SaveSettings()
            refreshRaidSortDropdown()
            hideRaidSortSlotLayoutWindow()
            safeShow(State.widgets.raid_sort_builder_window, false)
        end)
    end

    local presetLabel = createThemedLabel(window, "nuziRaidtoolsSortBuilderPresetLabel", "Preset", 12, 170, 18, "text")
    if presetLabel ~= nil then
        presetLabel:AddAnchor("TOPLEFT", window, 18, 52)
    end
    local presetDropdown = Utils.CreateComboBox(window, { "New Preset" }, 190, 30)
    presetDropdown:AddAnchor("TOPLEFT", window, 18, 72)
    function presetDropdown:SelectedProc()
        if self.__nuzi_syncing_builder then
            return
        end
        local ids = State.raid_sort_builder_preset_ids or {}
        setRaidSortBuilderFields(ids[self:GetSelectedIndex()] or "")
    end
    State.widgets.raid_sort_builder_preset_dropdown = presetDropdown

    local nameLabel = createThemedLabel(window, "nuziRaidtoolsSortBuilderNameLabel", "Name", 12, 170, 18, "text")
    if nameLabel ~= nil then
        nameLabel:AddAnchor("TOPLEFT", window, 226, 52)
    end
    local nameInput = Utils.CreateEditBox(window, "nuziRaidtoolsSortBuilderNameInput", "Preset name", 186, 30, 32)
    nameInput:AddAnchor("TOPLEFT", window, 226, 72)
    State.widgets.raid_sort_builder_name_input = nameInput

    local roleHeader = createThemedLabel(window, "nuziRaidtoolsSortBuilderRoleHeader", "Role Priority", 12, 200, 18, "text")
    if roleHeader ~= nil then
        roleHeader:AddAnchor("TOPLEFT", window, 18, 116)
    end

    for index = 1, 4 do
        local x = index <= 2 and 18 or 226
        local y = (index == 1 or index == 3) and 136 or 174
        local label = createThemedLabel(window, "nuziRaidtoolsSortBuilderRole" .. tostring(index) .. "Label", tostring(index), 11, 34, 18, "hint")
        if label ~= nil then
            label:AddAnchor("TOPLEFT", window, x, y + 6)
        end
        local dropdown = Utils.CreateComboBox(window, RAID_ROLE_ORDER_OPTIONS, 158, 30)
        dropdown:AddAnchor("TOPLEFT", window, x + 34, y)
        dropdown:Select(index)
        State.widgets["raid_sort_builder_role_" .. tostring(index)] = dropdown
    end

    local gearLabel = createThemedLabel(window, "nuziRaidtoolsSortBuilderGearLabel", "Gearscore", 12, 170, 18, "text")
    if gearLabel ~= nil then
        gearLabel:AddAnchor("TOPLEFT", window, 18, 214)
    end
    local gearDropdown = Utils.CreateComboBox(window, RAID_GEAR_ORDER_OPTIONS, 190, 30)
    gearDropdown:AddAnchor("TOPLEFT", window, 18, 234)
    State.widgets.raid_sort_builder_gear_dropdown = gearDropdown

    local nameOrderLabel = createThemedLabel(window, "nuziRaidtoolsSortBuilderNameOrderLabel", "Tie Breaker", 12, 170, 18, "text")
    if nameOrderLabel ~= nil then
        nameOrderLabel:AddAnchor("TOPLEFT", window, 226, 214)
    end
    local nameOrderDropdown = Utils.CreateComboBox(window, RAID_NAME_ORDER_OPTIONS, 186, 30)
    nameOrderDropdown:AddAnchor("TOPLEFT", window, 226, 234)
    State.widgets.raid_sort_builder_name_dropdown = nameOrderDropdown

    local groupHeader = createThemedLabel(window, "nuziRaidtoolsSortBuilderGroupHeader", "Role Groups", 12, 200, 18, "text")
    if groupHeader ~= nil then
        groupHeader:AddAnchor("TOPLEFT", window, 18, 276)
    end
    local slotLayoutButton = Utils.CreateButton(window, "nuziRaidtoolsSortBuilderSlotLayout", "Slot Layout", 112, 24)
    if slotLayoutButton ~= nil then
        slotLayoutButton:AddAnchor("TOPRIGHT", window, -18, 270)
        slotLayoutButton:SetHandler("OnClick", function()
            toggleRaidSortSlotLayout()
        end)
    end
    for role = 1, 4 do
        local x = role <= 2 and 18 or 226
        local y = (role == 1 or role == 3) and 296 or 334
        local label = createThemedLabel(window, "nuziRaidtoolsSortBuilderGroup" .. tostring(role) .. "Label", RAID_ROLE_ORDER_OPTIONS[role], 11, 74, 18, "hint")
        if label ~= nil then
            label:AddAnchor("TOPLEFT", window, x, y + 6)
        end
        local dropdown = Utils.CreateComboBox(window, RAID_GROUP_OPTIONS, 118, 30)
        dropdown:AddAnchor("TOPLEFT", window, x + 74, y)
        State.widgets["raid_sort_builder_group_" .. tostring(role)] = dropdown
    end

    local newButton = Utils.CreateButton(window, "nuziRaidtoolsSortBuilderNew", "New", 82, 30)
    newButton:AddAnchor("TOPLEFT", window, 18, 384)
    newButton:SetHandler("OnClick", function()
        getSettings().raid_sort_builder_draft = {
            name = "",
            role_order = { 1, 2, 3, 4 },
            role_groups = { 0, 0, 0, 0 },
            slot_roles = {},
            gear_order = 1,
            name_order = 1
        }
        setRaidSortBuilderFields("", true)
        Shared.SaveSettings()
    end)

    local saveButton = Utils.CreateButton(window, "nuziRaidtoolsSortBuilderSave", "Save", 92, 30)
    saveButton:AddAnchor("TOPLEFT", window, 110, 384)
    saveButton:SetHandler("OnClick", function()
        local settings = getSettings()
        local draft = readRaidSortBuilderPresetFromWidgets()
        local name = draft.name
        if name == "" then
            Shared.logger:Err("Preset name required.")
            return
        end
        local key = normalizeKey(name)
        if key == "" then
            Shared.logger:Err("Preset name required.")
            return
        end
        if type(settings.raid_custom_sort_presets) ~= "table" then
            settings.raid_custom_sort_presets = {}
        end
        local oldKey = State.raid_sort_builder_key or ""
        if oldKey ~= "" and oldKey ~= key then
            settings.raid_custom_sort_presets[oldKey] = nil
        end
        settings.raid_sort_builder_draft = draft
        settings.raid_custom_sort_presets[key] = draft
        settings.raid_sort_preset = "custom:" .. key
        Shared.NormalizeRaidSortSettings(settings)
        Shared.SaveSettings()
        State.raid_sort_builder_key = key
        refreshRaidSortDropdown()
        setRaidSortBuilderFields(key)
        Shared.logger:Info("Saved raid sort preset: " .. name .. ".")
    end)

    local deleteButton = Utils.CreateButton(window, "nuziRaidtoolsSortBuilderDelete", "Delete", 92, 30)
    deleteButton:AddAnchor("TOPLEFT", window, 212, 384)
    deleteButton:SetHandler("OnClick", function()
        local settings = getSettings()
        local key = State.raid_sort_builder_key or ""
        if key == "" or type(settings.raid_custom_sort_presets) ~= "table" or settings.raid_custom_sort_presets[key] == nil then
            setRaidSortBuilderFields("")
            return
        end
        local name = tostring(settings.raid_custom_sort_presets[key].name or key)
        settings.raid_custom_sort_presets[key] = nil
        if settings.raid_sort_preset == "custom:" .. key then
            settings.raid_sort_preset = "builtin:" .. tostring(tonumber(settings.raid_sort_mode) or 1)
        end
        Shared.NormalizeRaidSortSettings(settings)
        Shared.SaveSettings()
        State.raid_sort_builder_key = ""
        refreshRaidSortDropdown()
        setRaidSortBuilderFields("")
        Shared.logger:Info("Deleted raid sort preset: " .. name .. ".")
    end)

    local closeFooterButton = Utils.CreateButton(window, "nuziRaidtoolsSortBuilderDone", "Done", 92, 30)
    closeFooterButton:AddAnchor("TOPLEFT", window, 320, 384)
    closeFooterButton:SetHandler("OnClick", function()
        RaidManagerUi.CaptureSettingsInputs()
        Shared.SaveSettings()
        refreshRaidSortDropdown()
        hideRaidSortSlotLayoutWindow()
        safeShow(State.widgets.raid_sort_builder_window, false)
    end)

    setRaidSortBuilderFields("")
    return window
end

function RaidManagerUi.ToggleRaidSortBuilder()
    local window = buildRaidSortBuilderWindow()
    if window == nil then
        return
    end
    local show = not isWidgetVisible(window)
    if show then
        refreshRaidSortDropdown()
        local selected = trimText(getSettings().raid_sort_preset)
        local customKey = string.match(selected, "^custom:(.+)$")
        setRaidSortBuilderFields(customKey or State.raid_sort_builder_key or "")
    end
    safeShow(window, show)
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
                RaidManagerUi.CaptureSettingsInputs()
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
        "Raid Setup",
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
        "Recruiting, lists, automation, roles, and lead handoff.",
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
    local function runRaidAction(action)
        RaidManagerUi.CaptureSettingsInputs()
        Shared.SaveSettings()
        local ok, message = action()
        if ok then
            Shared.logger:Info(message)
        else
            Shared.logger:Err(message)
        end
    end

    local autoInviteCard = createSectionCard(
        content,
        "nuziRaidtoolsAutoInviteCard",
        "Recruiting",
        "Phrase, chat scope, and start/stop.",
        sectionY,
        cardWidth,
        218
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

    end
    sectionY = sectionY + 230

    local listCard = createSectionCard(
        content,
        "nuziRaidtoolsListCard",
        "Lists",
        "Pick who automation trusts.",
        sectionY,
        cardWidth,
        274
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
    end
    sectionY = sectionY + 286

    local automationCard = createSectionCard(
        content,
        "nuziRaidtoolsAutomationCard",
        "Roster Automation",
        "Automatic invites and list updates.",
        sectionY,
        cardWidth,
        336
    )
    if automationCard ~= nil then
        local whitelistAutoInviteCheckbox = createCheckboxRow(
            automationCard,
            "nuziRaidtoolsWhitelistAutoInvite",
            "Invite enabled list members without phrase match",
            14,
            68,
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
            automationCard,
            "nuziRaidtoolsWhitelistAutoInviteOnLogin",
            "Invite enabled list members on login",
            14,
            96,
            286
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
            automationCard,
            "nuziRaidtoolsWhitelistAutoInviteOnCadence",
            "Invite enabled list members every 60s",
            14,
            124,
            286
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

        local guildAutoLearnCheckbox = createCheckboxRow(
            automationCard,
            "nuziRaidtoolsGuildAutoLearn",
            "Add guild-chat recruit speakers to Guild Members",
            14,
            152,
            286
        )
        guildAutoLearnCheckbox:SetChecked(settings.guild_auto_learn and true or false)
        function guildAutoLearnCheckbox:OnCheckChanged()
            settings.guild_auto_learn = self:GetChecked() and true or false
            Shared.SaveSettings()
            RaidManagerUi.SyncAutoInviteWidgets()
        end
        guildAutoLearnCheckbox:SetHandler("OnCheckChanged", guildAutoLearnCheckbox.OnCheckChanged)
        State.widgets.guild_auto_learn_checkbox = guildAutoLearnCheckbox

        local expeditionSyncCheckbox = createCheckboxRow(
            automationCard,
            "nuziRaidtoolsExpeditionSync",
            "Add current raid guildies to Guild Members",
            14,
            180,
            286
        )
        expeditionSyncCheckbox:SetChecked(settings.expedition_sync_enabled and true or false)
        function expeditionSyncCheckbox:OnCheckChanged()
            settings.expedition_sync_enabled = self:GetChecked() and true or false
            Runtime.ResetExpeditionSyncTicker()
            Shared.SaveSettings()
            RaidManagerUi.SyncAutoInviteWidgets()
        end
        expeditionSyncCheckbox:SetHandler("OnCheckChanged", expeditionSyncCheckbox.OnCheckChanged)
        State.widgets.expedition_sync_checkbox = expeditionSyncCheckbox

        local expeditionNameLabel = createThemedLabel(automationCard, "nuziRaidtoolsExpeditionNameLabel", "Expedition", 12, 220, 18, "text")
        if expeditionNameLabel ~= nil then
            expeditionNameLabel:AddAnchor("TOPLEFT", automationCard, 14, 210)
        end

        local expeditionNameInput = Utils.CreateEditBox(automationCard, "nuziRaidtoolsExpeditionNameInput", "macro", 214, 30, 64)
        expeditionNameInput:AddAnchor("TOPLEFT", automationCard, 14, 232)
        expeditionNameInput:SetText(tostring(settings.expedition_sync_name or "macro"))
        State.widgets.expedition_sync_name_input = expeditionNameInput

        local expeditionNameSave = Utils.CreateButton(automationCard, "nuziRaidtoolsExpeditionNameSave", "Save", 80, 30)
        expeditionNameSave:AddAnchor("TOPLEFT", automationCard, 236, 232)
        expeditionNameSave:SetHandler("OnClick", function()
            expeditionNameInput:SetText(Runtime.SaveExpeditionSyncName(expeditionNameInput:GetText()))
            Runtime.ResetExpeditionSyncTicker()
        end)
        State.widgets.expedition_sync_name_save = expeditionNameSave

        local remoteControlsCheckbox = createCheckboxRow(
            automationCard,
            "nuziRaidtoolsRemoteAutoInviteControls",
            "Allow chat stop/start commands",
            14,
            276,
            286
        )
        remoteControlsCheckbox:SetChecked(settings.remote_auto_invite_controls and true or false)
        function remoteControlsCheckbox:OnCheckChanged()
            settings.remote_auto_invite_controls = self:GetChecked() and true or false
            Shared.SaveSettings()
            RaidManagerUi.SyncAutoInviteWidgets()
        end
        remoteControlsCheckbox:SetHandler("OnCheckChanged", remoteControlsCheckbox.OnCheckChanged)
        State.widgets.remote_auto_invite_controls_checkbox = remoteControlsCheckbox
    end
    sectionY = sectionY + 348

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

    local raidSortCard = createSectionCard(
        content,
        "nuziRaidtoolsRaidSortCard",
        "Raid Sort",
        "Arrange raid roles and custom group layouts.",
        sectionY,
        cardWidth,
        176
    )
    if raidSortCard ~= nil then
        local sortModeLabel = createThemedLabel(raidSortCard, "nuziRaidtoolsRaidSortModeLabel", "Sort Mode", 12, 220, 18, "text")
        if sortModeLabel ~= nil then
            sortModeLabel:AddAnchor("TOPLEFT", raidSortCard, 14, 68)
        end

        local presetButton = Utils.CreateButton(raidSortCard, "nuziRaidtoolsSortPresetButton", "Presets", 86, 24)
        presetButton:AddAnchor("TOPRIGHT", raidSortCard, -14, 62)
        presetButton:SetHandler("OnClick", function()
            RaidManagerUi.ToggleRaidSortBuilder()
        end)
        State.widgets.raid_sort_preset_button = presetButton

        local sortItems, sortIds = buildRaidSortDropdownItems(settings)
        State.raid_sort_preset_ids = sortIds
        local sortModeDropdown = Utils.CreateComboBox(raidSortCard, sortItems, cardWidth - 28, 30)
        sortModeDropdown:AddAnchor("TOPLEFT", raidSortCard, 14, 88)
        sortModeDropdown:Select(getRaidSortSelectionIndex(settings, sortIds))
        function sortModeDropdown:SelectedProc()
            if self.__nuzi_syncing_sort then
                return
            end
            local ids = State.raid_sort_preset_ids or {}
            local selected = ids[self:GetSelectedIndex()] or "builtin:1"
            settings.raid_sort_preset = selected
            local builtinMode = tonumber(string.match(selected, "^builtin:(%d+)$"))
            if builtinMode ~= nil then
                settings.raid_sort_mode = builtinMode
            end
            Shared.NormalizeRaidSortSettings(settings)
            Shared.SaveSettings()
            refreshRaidSortDropdown()
        end
        State.widgets.raid_sort_mode_dropdown = sortModeDropdown

        local sortButton = Utils.CreateButton(raidSortCard, "nuziRaidtoolsSortRaidButton", "Sort", 94, 30)
        sortButton:AddAnchor("TOPLEFT", raidSortCard, 14, 126)
        sortButton:SetHandler("OnClick", function()
            runRaidAction(function()
                return Runtime.SortRaidBySettings()
            end)
        end)
        State.widgets.raid_sort_button = sortButton

    end
    sectionY = sectionY + 188

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

    local iconCard = createSectionCard(
        content,
        "nuziRaidtoolsFloatingIconCard",
        "Display",
        "Floating launcher preferences.",
        sectionY,
        cardWidth,
        164
    )
    if iconCard ~= nil then
        local alwaysVisibleCheckbox = createCheckboxRow(
            iconCard,
            "nuziRaidtoolsAlwaysVisible",
            "Always show the floating auto-invite icon",
            14,
            68,
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

        local iconSizeLabel = createThemedLabel(iconCard, "nuziRaidtoolsFloatingIconSizeLabel", "Icon Size", 12, 120, 18, "text")
        if iconSizeLabel ~= nil then
            iconSizeLabel:AddAnchor("TOPLEFT", iconCard, 14, 104)
        end

        local iconSizeValue = createThemedLabel(
            iconCard,
            "nuziRaidtoolsFloatingIconSizeValue",
            tostring(getFloatingIconSize(settings)),
            12,
            42,
            18,
            "hint"
        )
        if iconSizeValue ~= nil then
            iconSizeValue:AddAnchor("TOPRIGHT", iconCard, -14, 104)
        end
        State.widgets.floating_icon_size_value = iconSizeValue

        local iconSizeSlider = createSlider(
            iconCard,
            "nuziRaidtoolsFloatingIconSizeSlider",
            cardWidth - 122,
            FLOATING_ICON_MIN_SIZE,
            FLOATING_ICON_MAX_SIZE
        )
        if iconSizeSlider ~= nil then
            iconSizeSlider:AddAnchor("TOPLEFT", iconCard, 88, 100)
            safeSetSliderValue(iconSizeSlider, getFloatingIconSize(settings))
            iconSizeSlider:SetHandler("OnSliderChanged", function(_, raw)
                local size = math.floor(clampNumber(raw, FLOATING_ICON_MIN_SIZE, FLOATING_ICON_MAX_SIZE, 40) + 0.5)
                settings.floating_icon_size = size
                safeSetText(State.widgets.floating_icon_size_value, tostring(size))
                Shared.SaveSettings()
                applyFloatingButtonLayout()
                syncFloatingButtonIcon()
            end)
            State.widgets.floating_icon_size_slider = iconSizeSlider
        end
    end
    sectionY = sectionY + 176

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
    local width, height = getFloatingIconExtent(getSettings())
    local button = createFloatingButtonWindow(width, height)
    if button == nil then
        return
    end
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
    syncFloatingButtonIcon()
    RaidManagerUi.SyncRecruitWidgets()
end

function RaidManagerUi.CaptureFloatingButtonPosition()
    if State == nil or State.floating_button == nil then
        return false
    end
    local ok = Positioning.SaveFromWidget(
        getSettings(),
        "floating_button",
        State.floating_button,
        FLOATING_BUTTON_POSITION_MAPPINGS
    )
    return ok and true or false
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
    local targetHeight = tonumber(State.raid_manager_original_height) or RAID_MANAGER_FALLBACK_HEIGHT
    pcall(function()
        raidManager:SetExtent(RAID_MANAGER_SKIN_WIDTH, targetHeight)
    end)
    raidManager.__nuzi_raidtools_stock_width = RAID_MANAGER_SKIN_WIDTH
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
        State.floating_button_icon = nil
    end
end

return RaidManagerUi
