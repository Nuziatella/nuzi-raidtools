local api = require("api")
local Core = api._NuziCore or require("nuzi-core/core")
local Require = Core.Require

local function loadModule(name)
    local mod = Require.Addon("nuzi-raidtools", name)
    return mod
end

local Utils = loadModule("utils")

local ListManager = {
    canvas = nil,
    settings = nil,
    callbacks = nil,
    widgets = {},
    scroll_children = {},
    refresh_counter = 0,
    selected_list_name = nil
}

local RESERVED_BLACKLIST = "Blacklist"
local RESERVED_GIVE_LEAD_WHITELIST = "Give Lead Whitelist"
local THEME = {
    title = { 0.98, 0.90, 0.72, 1 },
    heading = { 0.96, 0.88, 0.70, 1 },
    text = { 0.95, 0.93, 0.90, 1 },
    hint = { 0.78, 0.74, 0.68, 1 },
    warning = { 1, 0.45, 0.32, 1 }
}
local updateDisplay

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

local function safeShow(widget, visible)
    if widget ~= nil and widget.Show ~= nil then
        widget:Show(visible and true or false)
    end
end

local function createEmptyChild(parent, id, x, y, width, height)
    if parent == nil or parent.CreateChildWidget == nil then
        return nil
    end
    local widget = parent:CreateChildWidget("emptywidget", id, 0, true)
    if widget == nil then
        return nil
    end
    if widget.AddAnchor ~= nil then
        widget:AddAnchor("TOPLEFT", parent, x or 0, y or 0)
    end
    if widget.SetExtent ~= nil then
        widget:SetExtent(width or 100, height or 100)
    end
    safeShow(widget, true)
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

local function createThemedLabel(parent, id, text, fontSize, x, y, width, tone)
    local color = THEME[tone or "text"] or THEME.text
    local label = Utils.CreateLabel(parent, id, text, fontSize or 12, ALIGN.LEFT, color[1], color[2], color[3], color[4])
    if label == nil then
        return nil
    end
    if label.SetExtent ~= nil then
        label:SetExtent(width or 220, math.max(18, (tonumber(fontSize) or 12) + 8))
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
    label:AddAnchor("TOPLEFT", parent, x or 0, y or 0)
    safeShow(label, true)
    return label
end

local function clearScrollChildren()
    for _, widget in ipairs(ListManager.scroll_children) do
        if widget ~= nil then
            if widget.Show ~= nil then
                widget:Show(false)
            end
            if widget.RemoveAllAnchors ~= nil then
                widget:RemoveAllAnchors()
            end
        end
    end
    ListManager.scroll_children = {}
end

local function getListByName(name)
    if ListManager.settings == nil then
        return nil
    end
    if name == RESERVED_BLACKLIST then
        return ListManager.settings.blacklist
    end
    if name == RESERVED_GIVE_LEAD_WHITELIST then
        return ListManager.settings.give_lead_whitelist
    end
    if type(ListManager.settings.whitelists) ~= "table" then
        ListManager.settings.whitelists = {}
    end
    return ListManager.settings.whitelists[name]
end

local function isProtectedList(name)
    return name == RESERVED_BLACKLIST or name == RESERVED_GIVE_LEAD_WHITELIST
end

local function isToggleableList(name)
    return name ~= RESERVED_BLACKLIST
end

local function isSelectedListEnabled(name)
    if ListManager.settings == nil then
        return false
    end
    if name == RESERVED_GIVE_LEAD_WHITELIST then
        return ListManager.settings.give_lead_whitelist_enabled and true or false
    end
    local key = normalizeKey(name)
    return key ~= "" and type(ListManager.settings.enabled_whitelists) == "table" and ListManager.settings.enabled_whitelists[key] == true
end

local function setSelectedListEnabled(name, enabled)
    if ListManager.settings == nil then
        return
    end
    if name == RESERVED_GIVE_LEAD_WHITELIST then
        ListManager.settings.give_lead_whitelist_enabled = enabled and true or false
        return
    end
    if type(ListManager.settings.enabled_whitelists) ~= "table" then
        ListManager.settings.enabled_whitelists = {}
    end
    local key = normalizeKey(name)
    if key == "" then
        return
    end
    if enabled then
        ListManager.settings.enabled_whitelists[key] = true
    else
        ListManager.settings.enabled_whitelists[key] = nil
    end
end

local function syncSelectionWidgets(listName)
    local toggleButton = ListManager.widgets.list_toggle_button
    local toggleLabel = ListManager.widgets.list_toggle_label
    if toggleButton == nil or toggleLabel == nil then
        return
    end
    if listName == nil or listName == "" or not isToggleableList(listName) then
        toggleButton:Show(false)
        toggleLabel:Show(false)
        return
    end
    local enabled = isSelectedListEnabled(listName)
    if listName == RESERVED_GIVE_LEAD_WHITELIST then
        if enabled then
            toggleLabel:SetText("Status: Give lead approval enabled")
            toggleButton:SetText("Disable Lead")
        else
            toggleLabel:SetText("Status: Give lead approval disabled")
            toggleButton:SetText("Enable Lead")
        end
    else
        if enabled then
            toggleLabel:SetText("Status: Whitelist automation enabled")
            toggleButton:SetText("Disable List")
        else
            toggleLabel:SetText("Status: Whitelist automation disabled")
            toggleButton:SetText("Enable List")
        end
    end
    toggleButton:Show(true)
    toggleLabel:Show(true)
end

local function clearSelectionDisplay()
    local blacklistWarning = ListManager.widgets.blacklist_warning
    if blacklistWarning ~= nil and blacklistWarning.Show ~= nil then
        blacklistWarning:Show(false)
    end
    syncSelectionWidgets(nil)
    clearScrollChildren()
end

local function notifyListChanged(listName)
    if ListManager.callbacks == nil then
        return
    end
    if listName == RESERVED_BLACKLIST and ListManager.callbacks.OnBlacklistUpdate ~= nil then
        ListManager.callbacks.OnBlacklistUpdate()
    end
    if ListManager.callbacks.OnWhitelistUpdate ~= nil then
        ListManager.callbacks.OnWhitelistUpdate()
    end
    if ListManager.callbacks.OnListChanged ~= nil then
        ListManager.callbacks.OnListChanged(listName)
    end
end

local function listContains(list, value)
    if type(list) ~= "table" then
        return false
    end
    for _, item in ipairs(list) do
        if item == value then
            return true
        end
    end
    return false
end

local function collectCurrentRaidMemberNames()
    local out = {}
    local seen = {}

    local function addName(rawName)
        local formatted = Utils.FormatName(rawName)
        if formatted == "" then
            return
        end
        local key = string.lower(formatted)
        if seen[key] then
            return
        end
        seen[key] = true
        table.insert(out, formatted)
    end

    if api.Unit ~= nil and api.Unit.UnitInfo ~= nil then
        for idx = 1, 50 do
            local info = nil
            pcall(function()
                info = api.Unit:UnitInfo("team" .. tostring(idx))
            end)
            if type(info) == "table" then
                addName(info.name or info.unitName or "")
            end
        end
    end

    if api.Unit ~= nil and api.Unit.GetUnitId ~= nil then
        for idx = 1, 50 do
            local unitToken = "team" .. tostring(idx)
            local unitId = nil
            pcall(function()
                unitId = api.Unit:GetUnitId(unitToken)
            end)
            unitId = normalizeUnitId(unitId)
            if unitId ~= nil then
                if api.Unit.GetUnitInfoById ~= nil then
                    local infoById = nil
                    pcall(function()
                        infoById = api.Unit:GetUnitInfoById(unitId)
                    end)
                    if type(infoById) == "table" then
                        addName(infoById.name or infoById.unitName or "")
                    end
                end
                if api.Unit.GetUnitNameById ~= nil then
                    local nameById = nil
                    pcall(function()
                        nameById = api.Unit:GetUnitNameById(unitId)
                    end)
                    addName(nameById or "")
                end
            end
        end
    end

    if api.Unit ~= nil and api.Unit.UnitName ~= nil then
        for idx = 1, 50 do
            local name = nil
            pcall(function()
                name = api.Unit:UnitName("team" .. tostring(idx))
            end)
            addName(name or "")
        end
    end

    return out
end

local function getDropdownNames()
    local dropdown = ListManager.widgets.whitelist_dropdown
    if dropdown == nil or type(dropdown.dropdownItem) ~= "table" then
        return {}
    end
    return dropdown.dropdownItem
end

local function getSelectedListName()
    local dropdown = ListManager.widgets.whitelist_dropdown
    local names = getDropdownNames()
    if dropdown ~= nil and dropdown.GetSelectedIndex ~= nil then
        local selectedIndex = tonumber(dropdown:GetSelectedIndex()) or 0
        if selectedIndex > 0 and names[selectedIndex] ~= nil then
            return names[selectedIndex]
        end
    end
    return ListManager.selected_list_name
end

local function selectListByName(listName)
    local dropdown = ListManager.widgets.whitelist_dropdown
    local names = getDropdownNames()
    local targetIndex = nil

    if type(listName) == "string" and listName ~= "" then
        for index, name in ipairs(names) do
            if name == listName then
                targetIndex = index
                break
            end
        end
    end

    if targetIndex == nil and #names > 0 then
        targetIndex = 1
    end

    local selectedName = targetIndex ~= nil and names[targetIndex] or nil
    ListManager.selected_list_name = selectedName

    if dropdown ~= nil and dropdown.Select ~= nil and targetIndex ~= nil then
        dropdown:Select(targetIndex)
    end

    if updateDisplay ~= nil then
        if selectedName ~= nil and selectedName ~= "" then
            updateDisplay(selectedName)
        else
            clearSelectionDisplay()
        end
    end

    return selectedName
end

local function refreshManagerDropdown(targetListName)
    if ListManager.widgets.whitelist_dropdown == nil or ListManager.settings == nil then
        return
    end
    local desiredListName = targetListName or getSelectedListName()
    local names = {
        RESERVED_BLACKLIST,
        RESERVED_GIVE_LEAD_WHITELIST
    }
    for key, _ in pairs(ListManager.settings.whitelists or {}) do
        table.insert(names, key)
    end
    table.sort(names, function(a, b)
        local priority = {
            [RESERVED_BLACKLIST] = 1,
            [RESERVED_GIVE_LEAD_WHITELIST] = 2
        }
        if priority[a] ~= nil or priority[b] ~= nil then
            local pa = priority[a] or 100
            local pb = priority[b] or 100
            if pa ~= pb then
                return pa < pb
            end
        end
        if a == RESERVED_BLACKLIST then
            return true
        end
        if b == RESERVED_BLACKLIST then
            return false
        end
        return tostring(a) < tostring(b)
    end)
    ListManager.widgets.whitelist_dropdown.dropdownItem = names
    if ListManager.callbacks ~= nil and ListManager.callbacks.OnWhitelistUpdate ~= nil then
        ListManager.callbacks.OnWhitelistUpdate()
    end
    selectListByName(desiredListName)
end

local function removeEntryFromList(listName, itemIndex, itemName)
    local targetListName = type(listName) == "string" and listName ~= "" and listName or getSelectedListName()
    local targetList = getListByName(targetListName)
    if type(targetList) ~= "table" then
        return false
    end

    local expectedName = tostring(itemName or "")
    local numericIndex = tonumber(itemIndex)
    if numericIndex ~= nil and targetList[numericIndex] == expectedName then
        table.remove(targetList, numericIndex)
        return true
    end

    for index, value in ipairs(targetList) do
        if tostring(value or "") == expectedName then
            table.remove(targetList, index)
            return true
        end
    end

    return false
end

updateDisplay = function(listName)
    if ListManager.canvas == nil or ListManager.widgets.member_scroll_wnd == nil then
        return
    end
    if listName == nil or listName == "" then
        clearSelectionDisplay()
        return
    end
    ListManager.selected_list_name = listName
    local blacklistWarning = ListManager.widgets.blacklist_warning
    if blacklistWarning ~= nil and blacklistWarning.Show ~= nil then
        blacklistWarning:Show(isProtectedList(listName))
        if blacklistWarning.SetText ~= nil then
            if listName == RESERVED_BLACKLIST then
                blacklistWarning:SetText("You are currently editing your blacklist")
            elseif listName == RESERVED_GIVE_LEAD_WHITELIST then
                blacklistWarning:SetText("This list controls who can trigger 'give lead'")
            end
        end
    end
    syncSelectionWidgets(listName)

    local memberScroll = ListManager.widgets.member_scroll_wnd
    local oldScroll = memberScroll.scroll.vs:GetValue()
    memberScroll.scroll.vs:SetValue(0, false)
    memberScroll.content:ChangeChildAnchorByScrollValue("vert", 0)

    clearScrollChildren()
    ListManager.refresh_counter = ListManager.refresh_counter + 1

    local currentList = getListByName(listName) or {}
    local content = memberScroll.content
    local itemHeight = 45
    for i, name in ipairs(currentList) do
        local itemIndex = i
        local itemName = tostring(name or "")
        local yOffset = (i - 1) * itemHeight
        local uniqueId = tostring(i) .. "_" .. tostring(ListManager.refresh_counter)

        local row = createEmptyChild(content, "nrtLmRow_" .. uniqueId, 0, yOffset, 440, itemHeight - 2)
        if row ~= nil then
            table.insert(ListManager.scroll_children, row)
        else
            row = content
        end

        local label = Utils.CreateLabel(row, "nrtLmLabel_" .. uniqueId, itemName, 16, ALIGN.LEFT, 1, 1, 1, 1)
        label:SetExtent(336, 24)
        label:AddAnchor("TOPLEFT", row, 12, 10)
        label:Show(true)
        table.insert(ListManager.scroll_children, label)

        local deleteButton = Utils.CreateButton(row, "nrtLmDelete_" .. uniqueId, "Remove", 72, 24)
        deleteButton:AddAnchor("TOPRIGHT", row, -16, 8)
        deleteButton:Show(true)
        table.insert(ListManager.scroll_children, deleteButton)
        deleteButton:SetHandler("OnClick", function()
            if not removeEntryFromList(listName, itemIndex, itemName) then
                api.Log:Info("[Nuzi Raidtools] Could not remove list entry: " .. tostring(itemName))
                return
            end
            if ListManager.callbacks ~= nil and ListManager.callbacks.SaveSettings ~= nil then
                ListManager.callbacks.SaveSettings()
            end
            notifyListChanged(listName)
            refreshManagerDropdown(listName)
        end)
    end

    local totalHeight = #currentList * itemHeight
    memberScroll:ResetScroll(totalHeight)
    local _, maxValue = memberScroll.scroll.vs:GetMinMaxValues()
    if oldScroll > maxValue then
        oldScroll = maxValue
    end
    memberScroll.scroll.vs:SetValue(oldScroll, false)
    memberScroll.content:ChangeChildAnchorByScrollValue("vert", oldScroll)
end

function ListManager.Init(settings, callbacks)
    ListManager.settings = settings
    ListManager.callbacks = callbacks or {}
    if ListManager.canvas ~= nil then
        refreshManagerDropdown(ListManager.selected_list_name)
        return
    end

    local canvas = api.Interface:CreateEmptyWindow("nuziRaidtoolsListManager")
    canvas:AddAnchor("CENTER", "UIParent", 0, 0)
    canvas:SetExtent(832, 446)
    if canvas.EnableHidingIsRemove ~= nil then
        canvas:EnableHidingIsRemove(false)
    end
    if canvas.SetCloseOnEscape ~= nil then
        canvas:SetCloseOnEscape(false)
    end
    canvas:Show(false)
    ListManager.canvas = canvas

    local shell = createEmptyChild(canvas, "nuziRaidtoolsListManagerShell", 0, 0, 832, 446)
    if shell ~= nil then
        shell:AddAnchor("BOTTOMRIGHT", canvas, 0, 0)
        applyPanelBackground(shell, 0.94)
        applyPanelAccent(shell, 44, 0.08)
        applyPanelDivider(shell, 44, 12, -12, 0.12)
    end

    local header = createEmptyChild(canvas, "nuziRaidtoolsListManagerHeader", 0, 0, 832, 24)
    if header ~= nil then
        header:AddAnchor("TOPRIGHT", canvas, 0, 0)
        applyPanelBackground(header, 0.98)
        applyPanelAccent(header, 24, 0.10)
        applyPanelDivider(header, 24, 10, -10, 0.14)
    end

    local listsPanel = createEmptyChild(canvas, "nuziRaidtoolsListManagerListsPanel", 12, 36, 288, 398)
    if listsPanel ~= nil then
        applyPanelBackground(listsPanel, 0.86)
        applyPanelAccent(listsPanel, 42, 0.12)
        applyPanelDivider(listsPanel, 48, 14, -14, 0.16)
    end

    local entriesPanel = createEmptyChild(canvas, "nuziRaidtoolsListManagerEntriesPanel", 312, 36, 508, 398)
    if entriesPanel ~= nil then
        applyPanelBackground(entriesPanel, 0.86)
        applyPanelAccent(entriesPanel, 42, 0.12)
        applyPanelDivider(entriesPanel, 48, 14, -14, 0.16)
    end

    function canvas:OnDragStart()
        if api.Input ~= nil and api.Input.IsShiftKeyDown ~= nil and api.Input:IsShiftKeyDown() then
            canvas:StartMoving()
            api.Cursor:ClearCursor()
            api.Cursor:SetCursorImage(CURSOR_PATH.MOVE, 0, 0)
        end
    end

    function canvas:OnDragStop()
        canvas:StopMovingOrSizing()
        api.Cursor:ClearCursor()
    end

    canvas:SetHandler("OnDragStart", canvas.OnDragStart)
    canvas:SetHandler("OnDragStop", canvas.OnDragStop)
    canvas:EnableDrag(true)

    local closeButton = Utils.CreateButton(header or canvas, "nuziRaidtoolsListManagerClose", "X", 28, 22)
    closeButton:AddAnchor("TOPRIGHT", header or canvas, -10, 1)
    closeButton:SetHandler("OnClick", function()
        canvas:Show(false)
    end)

    createThemedLabel(header or canvas, "nuziRaidtoolsListManagerTitle", "Raidtools List Manager", 15, 14, 3, 280, "title")

    createThemedLabel(canvas, "nuziRaidtoolsListManagerHint", "Shift-drag this window to move it.", 11, 560, 12, 220, "hint")

    createThemedLabel(canvas, "nuziRaidtoolsManageHeader", "Manage Lists", 14, 20, 48, 240, "heading")

    local listNameInput = Utils.CreateEditBox(canvas, "nuziRaidtoolsNewListName", "New List Name", 165, 30)
    listNameInput:AddAnchor("TOPLEFT", canvas, 20, 66)

    local createListButton = Utils.CreateButton(canvas, "nuziRaidtoolsCreateList", "Create", 90, 30)
    createListButton:AddAnchor("LEFT", listNameInput, "RIGHT", 8, 0)

    createThemedLabel(canvas, "nuziRaidtoolsCurrentListHeader", "Current List", 12, 20, 114, 240, "text")

    local whitelistDropdown = Utils.CreateComboBox(canvas, nil, 263, 30)
    whitelistDropdown:AddAnchor("TOPLEFT", canvas, 20, 138)
    ListManager.widgets.whitelist_dropdown = whitelistDropdown

    local deleteListButton = Utils.CreateButton(canvas, "nuziRaidtoolsDeleteList", "Delete List", 110, 30)
    deleteListButton:AddAnchor("TOPLEFT", canvas, 20, 176)

    local listToggleLabel = createThemedLabel(
        canvas,
        "nuziRaidtoolsListToggleLabel",
        "Whitelist automation is disabled for this list",
        11,
        20,
        218,
        248,
        "hint"
    )
    listToggleLabel:Show(false)
    ListManager.widgets.list_toggle_label = listToggleLabel

    local listToggleButton = Utils.CreateButton(canvas, "nuziRaidtoolsListToggleButton", "Enable List", 126, 28)
    listToggleButton:AddAnchor("TOPLEFT", canvas, 20, 252)
    listToggleButton:Show(false)
    ListManager.widgets.list_toggle_button = listToggleButton

    local blacklistWarning = createThemedLabel(
        canvas,
        "nuziRaidtoolsBlacklistWarn",
        "You are currently editing your blacklist",
        11,
        20,
        288,
        248,
        "warning"
    )
    blacklistWarning:Show(false)
    ListManager.widgets.blacklist_warning = blacklistWarning

    createThemedLabel(canvas, "nuziRaidtoolsEntriesHeader", "Add Entries", 14, 320, 48, 220, "heading")

    local memberInput = Utils.CreateEditBox(canvas, "nuziRaidtoolsMemberInput", "Paste names here", 330, 30, 100000)
    memberInput:AddAnchor("TOPLEFT", canvas, 320, 66)

    local addMemberButton = Utils.CreateButton(canvas, "nuziRaidtoolsAddMember", "Add Names", 110, 30)
    addMemberButton:AddAnchor("LEFT", memberInput, "RIGHT", 8, 0)

    local addRaidButton = Utils.CreateButton(canvas, "nuziRaidtoolsAddRaidMembers", "Add Current Raid", 140, 30)
    addRaidButton:AddAnchor("TOPLEFT", canvas, 320, 104)

    local addRaidHint = createThemedLabel(
        canvas,
        "nuziRaidtoolsAddRaidHint",
        "Only adds nearby raid members.",
        11,
        470,
        110,
        300,
        "hint"
    )

    createThemedLabel(canvas, "nuziRaidtoolsContentsHeader", "List Contents", 12, 320, 148, 220, "text")

    local memberScroll = Utils.CreateScrollWindow(canvas, "nuziRaidtoolsMemberScroll", 0)
    memberScroll:Show(true)
    memberScroll:RemoveAllAnchors()
    memberScroll:AddAnchor("TOPLEFT", canvas, 320, 172)
    memberScroll:SetExtent(482, 228)
    ListManager.widgets.member_scroll_wnd = memberScroll

    local scrollBg = memberScroll:CreateNinePartDrawable(TEXTURE_PATH.HUD, "background")
    scrollBg:SetTextureInfo("bg_quest")
    scrollBg:SetColor(0.05, 0.04, 0.03, 0.78)
    scrollBg:AddAnchor("TOPLEFT", memberScroll, 0, 0)
    scrollBg:AddAnchor("BOTTOMRIGHT", memberScroll, 0, 0)

    function whitelistDropdown:SelectedProc()
        local idx = whitelistDropdown:GetSelectedIndex()
        local names = whitelistDropdown.dropdownItem or {}
        local selected = idx > 0 and names[idx] or nil
        ListManager.selected_list_name = selected
        updateDisplay(selected)
    end

    listToggleButton:SetHandler("OnClick", function()
        local idx = whitelistDropdown:GetSelectedIndex()
        local names = whitelistDropdown.dropdownItem or {}
        if idx <= 0 or names[idx] == nil then
            return
        end
        local selected = names[idx]
        if not isToggleableList(selected) then
            return
        end
        setSelectedListEnabled(selected, not isSelectedListEnabled(selected))
        if ListManager.callbacks ~= nil and ListManager.callbacks.SaveSettings ~= nil then
            ListManager.callbacks.SaveSettings()
        end
        notifyListChanged(selected)
        syncSelectionWidgets(selected)
    end)

    createListButton:SetHandler("OnClick", function()
        local name = listNameInput:GetText()
        if type(name) ~= "string" or name == "" then
            return
        end
        if isProtectedList(name) then
            api.Log:Err("[Nuzi Raidtools] That list name is reserved.")
            return
        end
        if ListManager.settings.whitelists[name] ~= nil then
            api.Log:Info("[Nuzi Raidtools] List already exists: " .. name)
            return
        end
        ListManager.settings.whitelists[name] = {}
        setSelectedListEnabled(name, false)
        if ListManager.callbacks ~= nil and ListManager.callbacks.SaveSettings ~= nil then
            ListManager.callbacks.SaveSettings()
        end
        refreshManagerDropdown(name)
        listNameInput:SetText("")
        api.Log:Info("[Nuzi Raidtools] Created list: " .. name)
    end)

    deleteListButton:SetHandler("OnClick", function()
        local idx = whitelistDropdown:GetSelectedIndex()
        local names = whitelistDropdown.dropdownItem or {}
        if idx <= 0 or names[idx] == nil then
            return
        end
        local selected = names[idx]
        if isProtectedList(selected) then
            api.Log:Err("[Nuzi Raidtools] This built-in list cannot be deleted.")
            return
        end
        ListManager.settings.whitelists[selected] = nil
        setSelectedListEnabled(selected, false)
        if ListManager.settings.active_whitelist == selected then
            ListManager.settings.active_whitelist = "Select Whitelist"
        end
        if ListManager.callbacks ~= nil and ListManager.callbacks.SaveSettings ~= nil then
            ListManager.callbacks.SaveSettings()
        end
        refreshManagerDropdown(selected)
        api.Log:Info("[Nuzi Raidtools] Deleted list: " .. selected)
    end)

    addMemberButton:SetHandler("OnClick", function()
        local idx = whitelistDropdown:GetSelectedIndex()
        local names = whitelistDropdown.dropdownItem or {}
        if idx <= 0 or names[idx] == nil then
            api.Log:Err("[Nuzi Raidtools] Select a list first.")
            return
        end
        local selected = names[idx]
        local rawText = memberInput:GetText()
        if type(rawText) ~= "string" or rawText == "" then
            return
        end
        local currentList = getListByName(selected)
        if type(currentList) ~= "table" then
            return
        end

        for name in string.gmatch(rawText, "([^,]+)") do
            local trimmed = tostring(name or ""):match("^%s*(.-)%s*$")
            if trimmed ~= nil and trimmed ~= "" then
                local formatted = Utils.FormatName(trimmed)
                if formatted ~= "" and not listContains(currentList, formatted) then
                    table.insert(currentList, formatted)
                end
            end
        end

        if ListManager.callbacks ~= nil and ListManager.callbacks.SaveSettings ~= nil then
            ListManager.callbacks.SaveSettings()
        end
        memberInput:SetText("")
        updateDisplay(selected)
        notifyListChanged(selected)
    end)

    addRaidButton:SetHandler("OnClick", function()
        local idx = whitelistDropdown:GetSelectedIndex()
        local names = whitelistDropdown.dropdownItem or {}
        if idx <= 0 or names[idx] == nil then
            api.Log:Err("[Nuzi Raidtools] Select a list first.")
            return
        end
        local selected = names[idx]
        if selected == RESERVED_BLACKLIST then
            api.Log:Err("[Nuzi Raidtools] Add Raid only works with character-name whitelists.")
            return
        end
        local currentList = getListByName(selected)
        if type(currentList) ~= "table" then
            return
        end

        local raidNames = collectCurrentRaidMemberNames()
        if #raidNames == 0 then
            api.Log:Err("[Nuzi Raidtools] No current raid members could be resolved.")
            return
        end
        local addedCount = 0
        for _, raidName in ipairs(raidNames) do
            if not listContains(currentList, raidName) then
                table.insert(currentList, raidName)
                addedCount = addedCount + 1
            end
        end

        if ListManager.callbacks ~= nil and ListManager.callbacks.SaveSettings ~= nil then
            ListManager.callbacks.SaveSettings()
        end
        updateDisplay(selected)
        notifyListChanged(selected)
        api.Log:Info("[Nuzi Raidtools] Added " .. tostring(addedCount) .. " current raid members to " .. tostring(selected) .. ".")
    end)

    refreshManagerDropdown(ListManager.selected_list_name)
end

function ListManager.Toggle()
    if ListManager.canvas == nil then
        return
    end
    ListManager.canvas:Show(not ListManager.canvas:IsVisible())
    if ListManager.canvas:IsVisible() then
        refreshManagerDropdown(ListManager.selected_list_name)
    end
end

function ListManager.Free()
    clearScrollChildren()
    if ListManager.canvas ~= nil then
        Utils.SafeFree(ListManager.canvas)
    end
    ListManager.canvas = nil
    ListManager.widgets = {}
end

function ListManager.Refresh()
    refreshManagerDropdown(ListManager.selected_list_name)
end

return ListManager
