local api = require("api")

local Utils = {}

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

function Utils.CreateButton(parent, id, text, width, height)
    local button = nil
    if type(parent) == "string" then
        button = api.Interface:CreateWidget("button", id, parent)
    elseif parent ~= nil and parent.CreateChildWidget ~= nil then
        button = parent:CreateChildWidget("button", id, 0, true)
    else
        button = api.Interface:CreateWidget("button", id, "UIParent")
    end
    if button ~= nil then
        button:SetText(text or "")
        if width ~= nil and height ~= nil and button.SetExtent ~= nil then
            button:SetExtent(width, height)
        end
        pcall(function()
            api.Interface:ApplyButtonSkin(button, BUTTON_BASIC.DEFAULT)
        end)
    end
    return button
end

function Utils.CreateCheckbox(parent, id)
    local cb = api.Interface:CreateWidget("checkbutton", id, parent)
    if cb == nil then
        return nil
    end
    cb:SetExtent(18, 17)

    local function setBackground(state, x, y)
        local bg = cb:CreateImageDrawable("ui/button/check_button.dds", "background")
        if bg == nil then
            return
        end
        bg:SetExtent(18, 17)
        bg:AddAnchor("CENTER", cb, 0, 0)
        bg:SetCoords(x, y, 18, 17)
        if state == "normal" then
            cb:SetNormalBackground(bg)
        elseif state == "highlight" then
            cb:SetHighlightBackground(bg)
        elseif state == "pushed" then
            cb:SetPushedBackground(bg)
        elseif state == "disabled" then
            cb:SetDisabledBackground(bg)
        elseif state == "checked" then
            cb:SetCheckedBackground(bg)
        elseif state == "disabledChecked" then
            cb:SetDisabledCheckedBackground(bg)
        end
    end

    setBackground("normal", 0, 0)
    setBackground("highlight", 0, 0)
    setBackground("pushed", 0, 0)
    setBackground("disabled", 0, 17)
    setBackground("checked", 18, 0)
    setBackground("disabledChecked", 18, 17)
    return cb
end

function Utils.CreateLabel(parent, id, text, fontSize, align, r, g, b, a)
    local label = parent:CreateChildWidget("label", id, 0, true)
    if label == nil then
        return nil
    end
    label:SetText(text or "")
    if fontSize ~= nil and label.style ~= nil and label.style.SetFontSize ~= nil then
        label.style:SetFontSize(fontSize)
    end
    if align ~= nil and label.style ~= nil and label.style.SetAlign ~= nil then
        label.style:SetAlign(align)
    end
    if r ~= nil and g ~= nil and b ~= nil and a ~= nil and label.style ~= nil and label.style.SetColor ~= nil then
        label.style:SetColor(r, g, b, a)
    end
    return label
end

function Utils.CreateEditBox(parent, id, guideText, width, height, maxLen)
    local edit = W_CTRL.CreateEdit(id, parent)
    if edit == nil then
        return nil
    end
    if width ~= nil and height ~= nil and edit.SetExtent ~= nil then
        edit:SetExtent(width, height)
    end
    if maxLen ~= nil and edit.SetMaxTextLength ~= nil then
        edit:SetMaxTextLength(maxLen)
    end
    if guideText ~= nil and edit.CreateGuideText ~= nil then
        edit:CreateGuideText(guideText)
    end
    return edit
end

function Utils.CreateComboBox(parent, items, width, height)
    local combo = nil
    pcall(function()
        combo = api.Interface:CreateComboBox(parent)
    end)
    if combo == nil and W_CTRL ~= nil and W_CTRL.CreateComboBox ~= nil then
        combo = W_CTRL.CreateComboBox(parent)
    end
    if combo ~= nil then
        if width ~= nil and height ~= nil and combo.SetExtent ~= nil then
            combo:SetExtent(width, height)
        end
        combo.dropdownItem = items or {}
    end
    return combo
end

function Utils.CreateScrollWindow(parent, ownId, index)
    local frame = parent:CreateChildWidget("emptywidget", ownId, index or 0, true)
    frame:Show(true)

    local content = frame:CreateChildWidget("emptywidget", "content", 0, true)
    content:EnableScroll(true)
    content:Show(true)
    frame.content = content

    local scroll = W_CTRL.CreateScroll("scroll", frame)
    scroll:AddAnchor("TOPRIGHT", frame, 0, 0)
    scroll:AddAnchor("BOTTOMRIGHT", frame, 0, 0)
    scroll:AlwaysScrollShow()
    frame.scroll = scroll

    content:AddAnchor("TOPLEFT", frame, 0, 0)
    content:AddAnchor("BOTTOM", frame, 0, 0)
    content:AddAnchor("RIGHT", scroll, "LEFT", -5, 0)

    function scroll.vs:OnSliderChanged(value)
        frame.content:ChangeChildAnchorByScrollValue("vert", value)
        if frame.SliderChangedProc ~= nil then
            frame:SliderChangedProc(value)
        end
    end
    scroll.vs:SetHandler("OnSliderChanged", scroll.vs.OnSliderChanged)

    function frame:SetEnable(enable)
        self:Enable(enable)
        scroll:SetEnable(enable)
    end

    function frame:ResetScroll(totalHeight)
        scroll.vs:SetMinMaxValues(0, totalHeight)
        local height = frame:GetHeight()
        if totalHeight <= height then
            scroll:SetEnable(false)
        else
            scroll:SetEnable(true)
        end
    end

    return frame
end

function Utils.SafeFree(widget)
    if widget == nil or api.Interface == nil or api.Interface.Free == nil then
        return
    end
    pcall(function()
        api.Interface:Free(widget)
    end)
end

return Utils
