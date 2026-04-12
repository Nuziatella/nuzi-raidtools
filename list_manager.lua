local api = require("api")

local function loadModule(name)
    local ok, mod = pcall(require, "nuzi-raidtools/" .. name)
    if ok then
        return mod
    end
    ok, mod = pcall(require, "nuzi-raidtools." .. name)
    if ok then
        return mod
    end
    return nil
end

local Utils = loadModule("utils")

local ListManager = {
    canvas = nil,
    settings = nil,
    callbacks = nil,
    widgets = {},
    scroll_children = {},
    refresh_counter = 0
}

local RESERVED_BLACKLIST = "Blacklist"
local RESERVED_GIVE_LEAD_WHITELIST = "Give Lead Whitelist"

local function normalizeKey(value)
    local text = tostring(value or ""):gsub("^%s*(.-)%s*$", "%1")
    if text == "" then
        return ""
    end
    return string.lower(text)
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
    if listName == RESERVED_GIVE_LEAD_WHITELIST then
        toggleLabel:SetText("Use this list for give lead")
    else
        toggleLabel:SetText("Use this whitelist for auto-invite")
    end
    if isSelectedListEnabled(listName) then
        toggleButton:SetText("Enabled")
    else
        toggleButton:SetText("Disabled")
    end
    toggleButton:Show(true)
    toggleLabel:Show(true)
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
            if unitId ~= nil and unitId ~= "" then
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

    if api.Unit ~= nil and api.Unit.GetUnitName ~= nil then
        for idx = 1, 50 do
            local name = nil
            pcall(function()
                name = api.Unit:GetUnitName("team" .. tostring(idx))
            end)
            addName(name or "")
        end
    end

    return out
end

local function refreshManagerDropdown()
    if ListManager.widgets.whitelist_dropdown == nil or ListManager.settings == nil then
        return
    end
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
end

local function updateDisplay(listName)
    if ListManager.canvas == nil or ListManager.widgets.member_scroll_wnd == nil or listName == nil or listName == "" then
        return
    end
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
    memberScroll.scroll.vs:SetValue(0)
    memberScroll.content:ChangeChildAnchorByScrollValue("vert", 0)

    clearScrollChildren()
    ListManager.refresh_counter = ListManager.refresh_counter + 1

    local currentList = getListByName(listName) or {}
    local content = memberScroll.content
    local itemHeight = 45
    for i, name in ipairs(currentList) do
        local yOffset = (i - 1) * itemHeight
        local uniqueId = tostring(i) .. "_" .. tostring(ListManager.refresh_counter)

        local label = Utils.CreateLabel(content, "nrtLmLabel_" .. uniqueId, name, 16, ALIGN.LEFT, 1, 1, 1, 1)
        label:SetExtent(360, 24)
        label:AddAnchor("TOPLEFT", content, 12, yOffset + 12)
        label:Show(true)
        table.insert(ListManager.scroll_children, label)

        local deleteButton = Utils.CreateButton(content, "nrtLmDelete_" .. uniqueId, "Remove", 72, 24)
        deleteButton:AddAnchor("TOPRIGHT", content, -16, yOffset + 10)
        deleteButton:Show(true)
        table.insert(ListManager.scroll_children, deleteButton)
        deleteButton:SetHandler("OnClick", function()
            table.remove(currentList, i)
            if ListManager.callbacks ~= nil and ListManager.callbacks.SaveSettings ~= nil then
                ListManager.callbacks.SaveSettings()
            end
            notifyListChanged(listName)
            updateDisplay(listName)
        end)
    end

    local totalHeight = #currentList * itemHeight
    memberScroll:ResetScroll(totalHeight)
    local _, maxValue = memberScroll.scroll.vs:GetMinMaxValues()
    if oldScroll > maxValue then
        oldScroll = maxValue
    end
    memberScroll.scroll.vs:SetValue(oldScroll)
    memberScroll.content:ChangeChildAnchorByScrollValue("vert", oldScroll)
end

function ListManager.Init(settings, callbacks)
    ListManager.settings = settings
    ListManager.callbacks = callbacks or {}
    if ListManager.canvas ~= nil then
        refreshManagerDropdown()
        return
    end

    local canvas = api.Interface:CreateEmptyWindow("nuziRaidtoolsListManager")
    canvas:AddAnchor("CENTER", "UIParent", 0, 0)
    canvas:SetExtent(820, 430)
    canvas:Show(false)
    ListManager.canvas = canvas

    canvas.bg = canvas:CreateNinePartDrawable(TEXTURE_PATH.HUD, "background")
    canvas.bg:SetTextureInfo("bg_quest")
    canvas.bg:SetColor(0, 0, 0, 0.9)
    canvas.bg:AddAnchor("TOPLEFT", canvas, 0, 0)
    canvas.bg:AddAnchor("BOTTOMRIGHT", canvas, 0, 0)

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

    local closeButton = Utils.CreateButton(canvas, "nuziRaidtoolsListManagerClose", "X", 28, 24)
    closeButton:AddAnchor("TOPRIGHT", canvas, -10, 5)
    closeButton:SetHandler("OnClick", function()
        canvas:Show(false)
    end)

    local title = Utils.CreateLabel(canvas, "nuziRaidtoolsListManagerTitle", "List Manager", 16, ALIGN.LEFT, 1, 1, 1, 1)
    title:AddAnchor("TOPLEFT", canvas, 20, 12)

    local manageHeader = Utils.CreateLabel(canvas, "nuziRaidtoolsManageHeader", "Manage Lists", 13, ALIGN.LEFT, 0.92, 0.82, 0.35, 1)
    manageHeader:AddAnchor("TOPLEFT", canvas, 20, 42)

    local listNameInput = Utils.CreateEditBox(canvas, "nuziRaidtoolsNewListName", "New List Name", 165, 30)
    listNameInput:AddAnchor("TOPLEFT", canvas, 20, 66)

    local createListButton = Utils.CreateButton(canvas, "nuziRaidtoolsCreateList", "Create", 90, 30)
    createListButton:AddAnchor("LEFT", listNameInput, "RIGHT", 8, 0)

    local currentListHeader = Utils.CreateLabel(canvas, "nuziRaidtoolsCurrentListHeader", "Current List", 13, ALIGN.LEFT, 0.92, 0.82, 0.35, 1)
    currentListHeader:AddAnchor("TOPLEFT", canvas, 20, 114)

    local whitelistDropdown = Utils.CreateComboBox(canvas, nil, 263, 30)
    whitelistDropdown:AddAnchor("TOPLEFT", canvas, 20, 138)
    ListManager.widgets.whitelist_dropdown = whitelistDropdown

    local deleteListButton = Utils.CreateButton(canvas, "nuziRaidtoolsDeleteList", "Delete List", 110, 30)
    deleteListButton:AddAnchor("TOPLEFT", canvas, 20, 176)

    local listToggleLabel = Utils.CreateLabel(
        canvas,
        "nuziRaidtoolsListToggleLabel",
        "Use this whitelist for auto-invite",
        11,
        ALIGN.LEFT,
        0.78,
        0.78,
        0.78,
        1
    )
    listToggleLabel:SetExtent(190, 34)
    listToggleLabel:AddAnchor("TOPLEFT", canvas, 20, 218)
    listToggleLabel:Show(false)
    ListManager.widgets.list_toggle_label = listToggleLabel

    local listToggleButton = Utils.CreateButton(canvas, "nuziRaidtoolsListToggleButton", "Disabled", 110, 28)
    listToggleButton:AddAnchor("TOPLEFT", canvas, 20, 252)
    listToggleButton:Show(false)
    ListManager.widgets.list_toggle_button = listToggleButton

    local blacklistWarning = Utils.CreateLabel(
        canvas,
        "nuziRaidtoolsBlacklistWarn",
        "You are currently editing your blacklist",
        11,
        ALIGN.LEFT,
        1,
        0.45,
        0.3,
        1
    )
    blacklistWarning:SetExtent(263, 34)
    blacklistWarning:AddAnchor("TOPLEFT", canvas, 20, 288)
    blacklistWarning:Show(false)
    ListManager.widgets.blacklist_warning = blacklistWarning

    local entriesHeader = Utils.CreateLabel(canvas, "nuziRaidtoolsEntriesHeader", "Add Entries", 13, ALIGN.LEFT, 0.92, 0.82, 0.35, 1)
    entriesHeader:AddAnchor("TOPLEFT", canvas, 320, 42)

    local memberInput = Utils.CreateEditBox(canvas, "nuziRaidtoolsMemberInput", "Paste names here", 330, 30, 100000)
    memberInput:AddAnchor("TOPLEFT", canvas, 320, 66)

    local addMemberButton = Utils.CreateButton(canvas, "nuziRaidtoolsAddMember", "Add Names", 110, 30)
    addMemberButton:AddAnchor("LEFT", memberInput, "RIGHT", 8, 0)

    local addRaidButton = Utils.CreateButton(canvas, "nuziRaidtoolsAddRaidMembers", "Add Current Raid", 140, 30)
    addRaidButton:AddAnchor("TOPLEFT", canvas, 320, 104)

    local addRaidHint = Utils.CreateLabel(
        canvas,
        "nuziRaidtoolsAddRaidHint",
        "Only adds nearby raid members.",
        11,
        ALIGN.LEFT,
        0.78,
        0.78,
        0.78,
        1
    )
    addRaidHint:SetExtent(300, 34)
    addRaidHint:AddAnchor("LEFT", addRaidButton, "RIGHT", 10, 0)

    local contentsHeader = Utils.CreateLabel(canvas, "nuziRaidtoolsContentsHeader", "List Contents", 13, ALIGN.LEFT, 0.92, 0.82, 0.35, 1)
    contentsHeader:AddAnchor("TOPLEFT", canvas, 320, 148)

    local memberScroll = Utils.CreateScrollWindow(canvas, "nuziRaidtoolsMemberScroll", 0)
    memberScroll:Show(true)
    memberScroll:RemoveAllAnchors()
    memberScroll:AddAnchor("TOPLEFT", canvas, 320, 172)
    memberScroll:SetExtent(470, 220)
    ListManager.widgets.member_scroll_wnd = memberScroll

    local scrollBg = memberScroll:CreateNinePartDrawable(TEXTURE_PATH.HUD, "background")
    scrollBg:SetTextureInfo("bg_quest")
    scrollBg:SetColor(0, 0, 0, 0.5)
    scrollBg:AddAnchor("TOPLEFT", memberScroll, 0, 0)
    scrollBg:AddAnchor("BOTTOMRIGHT", memberScroll, 0, 0)

    function whitelistDropdown:SelectedProc()
        local idx = whitelistDropdown:GetSelectedIndex()
        local names = whitelistDropdown.dropdownItem or {}
        if idx > 0 and names[idx] ~= nil then
            updateDisplay(names[idx])
        end
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
        refreshManagerDropdown()
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
        refreshManagerDropdown()
        clearScrollChildren()
        blacklistWarning:Show(false)
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

    refreshManagerDropdown()
end

function ListManager.Toggle()
    if ListManager.canvas == nil then
        return
    end
    ListManager.canvas:Show(not ListManager.canvas:IsVisible())
    if ListManager.canvas:IsVisible() then
        refreshManagerDropdown()
        if ListManager.widgets.whitelist_dropdown ~= nil and ListManager.widgets.whitelist_dropdown.SelectedProc ~= nil then
            ListManager.widgets.whitelist_dropdown:SelectedProc()
        end
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
    refreshManagerDropdown()
end

return ListManager
