-- JarsNPCChat: Immersion-style quest/gossip text bubble UI
-- Replaces default QuestFrame and GossipFrame with a centered, auto-sized text bubble
-- Action buttons are positioned to the right of the bubble

---------------------------------------------------------------------------
-- Constants & Style
---------------------------------------------------------------------------
local BUBBLE_PADDING = 20
local BUBBLE_MIN_WIDTH = 350
local BUBBLE_MAX_WIDTH = 550
local BUTTON_WIDTH = 100
local BUTTON_HEIGHT = 28
local BUTTON_GAP = 6
local FONT = "Fonts\\FRIZQT__.TTF"

local STYLE = {
    bg        = { 0.10, 0.10, 0.12, 0.92 },
    border    = { 0.25, 0.25, 0.28, 1 },
    title     = { 1.0, 0.82, 0.0 },
    body      = { 0.95, 0.95, 0.95 },
    option    = { 0.6, 0.85, 1.0 },
    optHover  = { 1.0, 0.82, 0.0 },
}

---------------------------------------------------------------------------
-- State
---------------------------------------------------------------------------
local currentState = nil
local selectedReward = nil

---------------------------------------------------------------------------
-- Saved Variables defaults
---------------------------------------------------------------------------
local DEFAULTS = {
    fontSize = 15,
    titleFontSize = 18,
}

---------------------------------------------------------------------------
-- Option button pool
---------------------------------------------------------------------------
local optionButtonPool = {}
local activeOptionButtons = {}

---------------------------------------------------------------------------
-- Reward button pool
---------------------------------------------------------------------------
local rewardButtonPool = {}
local activeRewardButtons = {}

---------------------------------------------------------------------------
-- Main Frame (invisible anchor)
---------------------------------------------------------------------------
local mainFrame = CreateFrame("Frame", "JarsNPCChatFrame", UIParent)
mainFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
mainFrame:SetSize(1, 1)
mainFrame:SetFrameStrata("DIALOG")
mainFrame:Hide()

tinsert(UISpecialFrames, "JarsNPCChatFrame")

---------------------------------------------------------------------------
-- Text Bubble
---------------------------------------------------------------------------
local bubble = CreateFrame("Frame", "JarsNPCChatBubble", mainFrame, "BackdropTemplate")
bubble:SetPoint("CENTER", mainFrame, "CENTER", 0, 0)
bubble:SetBackdrop({
    bgFile   = "Interface\\Buttons\\WHITE8X8",
    edgeFile = "Interface\\Buttons\\WHITE8X8",
    edgeSize = 2,
    insets   = { left = 0, right = 0, top = 0, bottom = 0 },
})
bubble:SetBackdropColor(unpack(STYLE.bg))
bubble:SetBackdropBorderColor(unpack(STYLE.border))
bubble:EnableMouse(true)

-- Tooltip for inline hyperlinks (item/spell links) in quest/gossip text
bubble:SetScript("OnHyperlinkEnter", function(self, link)
    GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
    GameTooltip:SetHyperlink(link)
    GameTooltip:Show()
end)
bubble:SetScript("OnHyperlinkLeave", function()
    GameTooltip:Hide()
end)
bubble:SetScript("OnHyperlinkClick", function(self, link, _, button)
    if button == "LeftButton" then
        if IsShiftKeyDown() then
            ChatEdit_InsertLink(link)
        end
    end
end)

-- Title
local titleText = bubble:CreateFontString(nil, "OVERLAY")
titleText:SetFont(FONT, DEFAULTS.titleFontSize, "")
titleText:SetTextColor(unpack(STYLE.title))
titleText:SetJustifyH("LEFT")
titleText:SetPoint("TOPLEFT", bubble, "TOPLEFT", BUBBLE_PADDING, -BUBBLE_PADDING)
titleText:SetPoint("TOPRIGHT", bubble, "TOPRIGHT", -BUBBLE_PADDING, -BUBBLE_PADDING)

-- Body
local bodyText = bubble:CreateFontString(nil, "OVERLAY")
bodyText:SetFont(FONT, DEFAULTS.fontSize, "")
bodyText:SetTextColor(unpack(STYLE.body))
bodyText:SetJustifyH("LEFT")
bodyText:SetWordWrap(true)
bodyText:SetSpacing(3)
bodyText:SetPoint("TOPLEFT", titleText, "BOTTOMLEFT", 0, -10)

-- Options panel (RIGHT of bubble, above action buttons, for gossip/quest options)
local optionsPanel = CreateFrame("Frame", nil, mainFrame, "BackdropTemplate")
optionsPanel:SetBackdrop({
    bgFile   = "Interface\\Buttons\\WHITE8X8",
    edgeFile = "Interface\\Buttons\\WHITE8X8",
    edgeSize = 2,
    insets   = { left = 0, right = 0, top = 0, bottom = 0 },
})
optionsPanel:SetBackdropColor(unpack(STYLE.bg))
optionsPanel:SetBackdropBorderColor(unpack(STYLE.border))
optionsPanel:Hide()

local optionsList = CreateFrame("Frame", nil, optionsPanel)
optionsList:SetPoint("TOPLEFT", optionsPanel, "TOPLEFT", 10, -10)
optionsList:SetPoint("TOPRIGHT", optionsPanel, "TOPRIGHT", -10, -10)

-- Reward frame container
local rewardFrame = CreateFrame("Frame", nil, bubble)
rewardFrame:SetPoint("RIGHT", bubble, "RIGHT", -BUBBLE_PADDING, 0)
rewardFrame:EnableMouse(true)
rewardFrame:Hide()

local rewardLabel = rewardFrame:CreateFontString(nil, "OVERLAY")
rewardLabel:SetFont(FONT, 12, "")
rewardLabel:SetTextColor(unpack(STYLE.title))
rewardLabel:SetJustifyH("LEFT")
rewardLabel:SetPoint("TOPLEFT", rewardFrame, "TOPLEFT", 0, 0)

---------------------------------------------------------------------------
-- Button Panel (right of bubble, below options panel)
---------------------------------------------------------------------------
local buttonPanel = CreateFrame("Frame", nil, mainFrame)
buttonPanel:SetWidth(BUTTON_WIDTH)
buttonPanel:SetHeight(1)

-- buttonPanel position is set dynamically in PositionRightPanels

local MAX_ACTION_BUTTONS = 3
local actionButtons = {}
for i = 1, MAX_ACTION_BUTTONS do
    local btn = CreateFrame("Button", nil, buttonPanel, "UIPanelButtonTemplate")
    btn:SetSize(BUTTON_WIDTH, BUTTON_HEIGHT)
    btn:SetPoint("TOP", buttonPanel, "TOP", 0, -((i - 1) * (BUTTON_HEIGHT + BUTTON_GAP)))
    btn:Hide()
    actionButtons[i] = btn
end

---------------------------------------------------------------------------
-- Button configurations per state
---------------------------------------------------------------------------
local STATE_BUTTONS = {
    GOSSIP = {
        { text = "Close", action = function() C_GossipInfo.CloseGossip() end },
    },
    QUEST_OFFER = {
        { text = "Accept", action = function() AcceptQuest() end },
        { text = "Decline", action = function() DeclineQuest() end },
    },
    QUEST_GREETING = {
        { text = "Close", action = function() CloseQuest() end },
    },
    QUEST_PROGRESS = {
        { text = "Continue", action = function() CompleteQuest() end, condition = IsQuestCompletable },
        { text = "Close", action = function() CloseQuest() end },
    },
    QUEST_COMPLETE = {
        { text = "Complete", action = function() GetQuestReward(selectedReward) end },
    },
}

local function SetActionButtons(state)
    local config = STATE_BUTTONS[state]
    for i = 1, MAX_ACTION_BUTTONS do
        local btn = actionButtons[i]
        local cfg = config and config[i]
        if cfg then
            -- Check condition (e.g. IsQuestCompletable)
            if cfg.condition and not cfg.condition() then
                btn:Hide()
            else
                btn:SetText(cfg.text)
                btn:SetScript("OnClick", function() cfg.action() end)
                btn:Show()
            end
        else
            btn:Hide()
        end
    end
    -- Adjust panel height
    local visibleCount = 0
    for i = 1, MAX_ACTION_BUTTONS do
        if actionButtons[i]:IsShown() then visibleCount = visibleCount + 1 end
    end
    buttonPanel:SetHeight(math.max(visibleCount * (BUTTON_HEIGHT + BUTTON_GAP) - BUTTON_GAP, 1))
end

---------------------------------------------------------------------------
-- Bubble auto-sizing
---------------------------------------------------------------------------
local function ResizeBubble()
    -- Measure body text at max width
    bodyText:SetWidth(BUBBLE_MAX_WIDTH - (BUBBLE_PADDING * 2))
    bodyText:SetText(bodyText:GetText() or "")

    local rawWidth = bodyText:GetStringWidth()
    if rawWidth then rawWidth = tonumber(rawWidth) else rawWidth = 0 end
    local contentWidth = math.min(rawWidth + (BUBBLE_PADDING * 2) + 4, BUBBLE_MAX_WIDTH)
    contentWidth = math.max(contentWidth, BUBBLE_MIN_WIDTH)

    -- Re-wrap at chosen width
    bodyText:SetWidth(contentWidth - (BUBBLE_PADDING * 2))

    local titleHeight = titleText:GetStringHeight() or 0
    if titleHeight then titleHeight = tonumber(titleHeight) else titleHeight = 0 end
    titleHeight = titleHeight + 10

    local bodyHeight = bodyText:GetStringHeight() or 0
    if bodyHeight then bodyHeight = tonumber(bodyHeight) else bodyHeight = 0 end

    local rewardsHeight = rewardFrame:IsShown() and (rewardFrame:GetHeight() + 12) or 0

    local totalHeight = BUBBLE_PADDING + titleHeight + bodyHeight + rewardsHeight + BUBBLE_PADDING
    totalHeight = math.max(totalHeight, 80)

    bubble:SetSize(contentWidth, totalHeight)

    -- Position the reward frame below body
    rewardFrame:SetPoint("TOPLEFT", bodyText, "BOTTOMLEFT", 0, -12)
end

---------------------------------------------------------------------------
-- Option button helpers
---------------------------------------------------------------------------
local function GetOptionButton()
    local btn
    if #optionButtonPool > 0 then
        btn = table.remove(optionButtonPool)
    else
        btn = CreateFrame("Button", nil, optionsList)
        btn:SetHeight(26)
        btn:EnableMouse(true)
        btn:RegisterForClicks("LeftButtonUp")

        btn.icon = btn:CreateTexture(nil, "ARTWORK")
        btn.icon:SetSize(20, 20)
        btn.icon:SetPoint("LEFT", 4, 0)

        btn.label = btn:CreateFontString(nil, "OVERLAY")
        btn.label:SetFont(FONT, 14, "")
        btn.label:SetJustifyH("LEFT")
        btn.label:SetPoint("LEFT", btn.icon, "RIGHT", 6, 0)
        btn.label:SetPoint("RIGHT", btn, "RIGHT", 0, 0)

        btn.highlight = btn:CreateTexture(nil, "HIGHLIGHT")
        btn.highlight:SetAllPoints()
        btn.highlight:SetColorTexture(1, 1, 1, 0.08)

        btn:SetScript("OnEnter", function(self)
            self.label:SetTextColor(unpack(STYLE.optHover))
        end)
        btn:SetScript("OnLeave", function(self)
            self.label:SetTextColor(unpack(STYLE.option))
        end)
    end
    btn:Show()
    table.insert(activeOptionButtons, btn)
    return btn
end

local function ReleaseAllOptionButtons()
    for _, btn in ipairs(activeOptionButtons) do
        btn:Hide()
        btn:SetScript("OnClick", nil)
        table.insert(optionButtonPool, btn)
    end
    wipe(activeOptionButtons)
end

---------------------------------------------------------------------------
-- Reward button helpers
---------------------------------------------------------------------------
local function GetRewardButton()
    local btn
    if #rewardButtonPool > 0 then
        btn = table.remove(rewardButtonPool)
    else
        btn = CreateFrame("Button", nil, rewardFrame)
        btn:SetSize(36, 36)

        btn.icon = btn:CreateTexture(nil, "ARTWORK")
        btn.icon:SetSize(32, 32)
        btn.icon:SetPoint("CENTER")
        btn.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

        btn.border = btn:CreateTexture(nil, "OVERLAY")
        btn.border:SetSize(36, 36)
        btn.border:SetPoint("CENTER")
        btn.border:SetColorTexture(0.5, 0.5, 0.5, 0.6)
        btn.border:Hide()

        btn.selected = btn:CreateTexture(nil, "OVERLAY")
        btn.selected:SetSize(38, 38)
        btn.selected:SetPoint("CENTER")
        btn.selected:SetColorTexture(1, 0.82, 0, 0.4)
        btn.selected:Hide()

        btn:SetScript("OnEnter", function(self)
            if self.link then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetHyperlink(self.link)
                GameTooltip:Show()
            end
        end)
        btn:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)
    end
    btn:Show()
    table.insert(activeRewardButtons, btn)
    return btn
end

local function ReleaseAllRewardButtons()
    for _, btn in ipairs(activeRewardButtons) do
        btn:Hide()
        btn:SetScript("OnClick", nil)
        btn.selected:Hide()
        btn.link = nil
        table.insert(rewardButtonPool, btn)
    end
    wipe(activeRewardButtons)
end

local function UpdateRewardSelection()
    for _, btn in ipairs(activeRewardButtons) do
        if btn.isChoice then
            btn.selected:SetShown(btn.index == selectedReward)
        end
    end
end

---------------------------------------------------------------------------
-- UI State Handlers
---------------------------------------------------------------------------
local function PositionRightPanels()
    -- Position options panel and button panel on the right side of the bubble
    buttonPanel:ClearAllPoints()
    optionsPanel:ClearAllPoints()

    if #activeOptionButtons > 0 then
        -- Measure the widest option label
        local maxWidth = 0
        for _, btn in ipairs(activeOptionButtons) do
            local labelWidth = tonumber(btn.label:GetStringWidth()) or 0
            local iconWidth = btn.icon:IsShown() and 26 or 0
            local totalW = iconWidth + labelWidth
            if totalW > maxWidth then maxWidth = totalW end
        end
        local panelWidth = maxWidth + 20 + 8  -- 10 padding each side + buffer
        panelWidth = math.max(panelWidth, 180)
        panelWidth = math.min(panelWidth, 350)

        local panelHeight = (#activeOptionButtons * 28) + 20  -- 10 padding top/bottom
        optionsPanel:SetSize(panelWidth, panelHeight)
        optionsList:SetSize(panelWidth - 20, #activeOptionButtons * 28)

        -- Set explicit width on each option button so it's clickable
        for _, btn in ipairs(activeOptionButtons) do
            btn:SetWidth(panelWidth - 20)
        end

        optionsPanel:SetPoint("TOPLEFT", bubble, "TOPRIGHT", 10, 0)
        optionsPanel:Show()

        -- Button panel goes below the options panel
        buttonPanel:SetPoint("TOPLEFT", optionsPanel, "BOTTOMLEFT", 0, -6)
    else
        optionsPanel:Hide()
        -- Button panel anchors directly to bubble right
        buttonPanel:SetPoint("TOPLEFT", bubble, "TOPRIGHT", 10, 0)
    end
end

local function HideUI()
    mainFrame:Hide()
    currentState = nil
    ReleaseAllOptionButtons()
    ReleaseAllRewardButtons()
    optionsPanel:Hide()
    rewardFrame:Hide()
    selectedReward = nil
end

local function ShowGossip()
    currentState = "GOSSIP"

    titleText:SetText(UnitName("npc") or "NPC")

    local gossipText = C_GossipInfo.GetText and C_GossipInfo.GetText() or ""
    bodyText:SetText(gossipText)

    ReleaseAllOptionButtons()
    ReleaseAllRewardButtons()
    rewardFrame:Hide()

    local options = C_GossipInfo.GetOptions() or {}
    local availableQuests = C_GossipInfo.GetAvailableQuests() or {}
    local activeQuests = C_GossipInfo.GetActiveQuests() or {}

    local yOffset = 0

    -- Available quests
    for _, quest in ipairs(availableQuests) do
        local btn = GetOptionButton()
        btn:SetPoint("TOPLEFT", optionsList, "TOPLEFT", 0, -yOffset)
        btn:SetPoint("RIGHT", optionsList, "RIGHT", 0, 0)
        btn.label:SetText(quest.title)
        btn.label:SetTextColor(unpack(STYLE.option))
        btn.icon:SetTexture("Interface\\GossipFrame\\AvailableQuestIcon")
        btn.icon:Show()
        btn:SetScript("OnClick", function()
            C_GossipInfo.SelectAvailableQuest(quest.questID)
        end)
        yOffset = yOffset + 26
    end

    -- Active quests
    for _, quest in ipairs(activeQuests) do
        local btn = GetOptionButton()
        btn:SetPoint("TOPLEFT", optionsList, "TOPLEFT", 0, -yOffset)
        btn:SetPoint("RIGHT", optionsList, "RIGHT", 0, 0)
        btn.label:SetText(quest.title)
        btn.label:SetTextColor(unpack(STYLE.option))
        btn.icon:SetTexture("Interface\\GossipFrame\\ActiveQuestIcon")
        btn.icon:Show()
        btn:SetScript("OnClick", function()
            C_GossipInfo.SelectActiveQuest(quest.questID)
        end)
        yOffset = yOffset + 26
    end

    -- Gossip options
    for _, option in ipairs(options) do
        local btn = GetOptionButton()
        btn:SetPoint("TOPLEFT", optionsList, "TOPLEFT", 0, -yOffset)
        btn:SetPoint("RIGHT", optionsList, "RIGHT", 0, 0)
        btn.label:SetText(option.name)
        btn.label:SetTextColor(unpack(STYLE.option))
        btn.icon:SetTexture(option.icon or "Interface\\GossipFrame\\GossipGossipIcon")
        btn.icon:Show()
        btn:SetScript("OnClick", function()
            C_GossipInfo.SelectOption(option.gossipOptionID)
        end)
        yOffset = yOffset + 26
    end

    PositionRightPanels()

    SetActionButtons("GOSSIP")
    ResizeBubble()
    mainFrame:Show()
end

local function ShowQuestOffer()
    currentState = "QUEST_OFFER"

    titleText:SetText(GetTitleText())
    bodyText:SetText(GetQuestText())

    ReleaseAllOptionButtons()
    ReleaseAllRewardButtons()
    optionsPanel:Hide()
    rewardFrame:Hide()

    PositionRightPanels()
    SetActionButtons("QUEST_OFFER")
    ResizeBubble()
    mainFrame:Show()
end

local function ShowQuestGreeting()
    currentState = "QUEST_GREETING"

    titleText:SetText(UnitName("npc") or "NPC")
    bodyText:SetText(GetGreetingText())

    ReleaseAllOptionButtons()
    ReleaseAllRewardButtons()
    rewardFrame:Hide()

    local yOffset = 0

    -- Active quests
    local numActive = GetNumActiveQuests() or 0
    for i = 1, numActive do
        local title, isComplete = GetActiveTitle(i)
        local btn = GetOptionButton()
        btn:SetPoint("TOPLEFT", optionsList, "TOPLEFT", 0, -yOffset)
        btn:SetPoint("RIGHT", optionsList, "RIGHT", 0, 0)
        if isComplete then
            btn.label:SetText(title)
            btn.label:SetTextColor(unpack(STYLE.option))
        else
            btn.label:SetText(title)
            btn.label:SetTextColor(0.6, 0.6, 0.6)
        end
        btn.icon:SetTexture("Interface\\GossipFrame\\ActiveQuestIcon")
        btn.icon:Show()
        btn:SetScript("OnClick", function()
            SelectActiveQuest(i)
        end)
        yOffset = yOffset + 26
    end

    -- Available quests
    local numAvailable = GetNumAvailableQuests() or 0
    for i = 1, numAvailable do
        local title = GetAvailableTitle(i)
        local btn = GetOptionButton()
        btn:SetPoint("TOPLEFT", optionsList, "TOPLEFT", 0, -yOffset)
        btn:SetPoint("RIGHT", optionsList, "RIGHT", 0, 0)
        btn.label:SetText(title)
        btn.label:SetTextColor(unpack(STYLE.option))
        btn.icon:SetTexture("Interface\\GossipFrame\\AvailableQuestIcon")
        btn.icon:Show()
        btn:SetScript("OnClick", function()
            SelectAvailableQuest(i)
        end)
        yOffset = yOffset + 26
    end

    PositionRightPanels()

    SetActionButtons("QUEST_GREETING")
    ResizeBubble()
    mainFrame:Show()
end

local function ShowQuestProgress()
    currentState = "QUEST_PROGRESS"

    titleText:SetText(GetTitleText())
    bodyText:SetText(GetProgressText())

    ReleaseAllOptionButtons()
    ReleaseAllRewardButtons()
    optionsPanel:Hide()
    rewardFrame:Hide()

    PositionRightPanels()
    SetActionButtons("QUEST_PROGRESS")
    ResizeBubble()
    mainFrame:Show()
end

local function ShowQuestComplete()
    currentState = "QUEST_COMPLETE"

    titleText:SetText(GetTitleText())
    bodyText:SetText(GetRewardText())

    ReleaseAllOptionButtons()
    ReleaseAllRewardButtons()
    optionsPanel:Hide()

    local numChoices = GetNumQuestChoices() or 0
    local numRewards = GetNumQuestRewards() or 0

    if numChoices > 0 or numRewards > 0 then
        rewardFrame:Show()
        local xOffset = 0
        local rowHeight = 40

        if numChoices > 0 then
            rewardLabel:SetText("Choose a reward:")
            rewardLabel:Show()
            selectedReward = 1

            for i = 1, numChoices do
                local name, texture = GetQuestItemInfo("choice", i)
                local link = GetQuestItemLink("choice", i)
                local btn = GetRewardButton()
                btn:SetPoint("TOPLEFT", rewardFrame, "TOPLEFT", xOffset, -18)
                btn.icon:SetTexture(texture)
                btn.link = link
                btn.index = i
                btn.isChoice = true
                btn.selected:SetShown(i == selectedReward)
                btn:SetScript("OnClick", function(self)
                    selectedReward = self.index
                    UpdateRewardSelection()
                end)
                xOffset = xOffset + 40
            end
            rowHeight = 58
        elseif numRewards > 0 then
            rewardLabel:SetText("You will receive:")
            rewardLabel:Show()

            for i = 1, numRewards do
                local name, texture = GetQuestItemInfo("reward", i)
                local link = GetQuestItemLink("reward", i)
                local btn = GetRewardButton()
                btn:SetPoint("TOPLEFT", rewardFrame, "TOPLEFT", xOffset, -18)
                btn.icon:SetTexture(texture)
                btn.link = link
                btn.isChoice = false
                xOffset = xOffset + 40
            end
        end

        rewardFrame:SetSize(math.max(xOffset, 100), rowHeight)
    else
        rewardFrame:Hide()
        rewardLabel:Hide()
    end

    PositionRightPanels()
    SetActionButtons("QUEST_COMPLETE")
    ResizeBubble()
    mainFrame:Show()
end

---------------------------------------------------------------------------
-- Default frame suppression
---------------------------------------------------------------------------
local function SuppressDefaultFrames()
    -- Retail uses CustomGossipFrameManager for gossip (not GossipFrame)
    if CustomGossipFrameManager then
        CustomGossipFrameManager:UnregisterEvent("GOSSIP_SHOW")
        CustomGossipFrameManager:UnregisterEvent("GOSSIP_CLOSED")
    end

    -- Classic uses GossipFrame
    if GossipFrame then
        GossipFrame:UnregisterEvent("GOSSIP_SHOW")
        GossipFrame:UnregisterEvent("GOSSIP_CLOSED")
        GossipFrame:UnregisterEvent("QUEST_LOG_UPDATE")
    end

    -- Suppress the quest frame
    if QuestFrame then
        QuestFrame:UnregisterAllEvents()
    end
end

---------------------------------------------------------------------------
-- OnHide: close server-side interaction
---------------------------------------------------------------------------
mainFrame:SetScript("OnHide", function()
    if currentState == "GOSSIP" then
        C_GossipInfo.CloseGossip()
    elseif currentState then
        CloseQuest()
    end
    currentState = nil
end)

---------------------------------------------------------------------------
-- Event handler
---------------------------------------------------------------------------
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("GOSSIP_SHOW")
eventFrame:RegisterEvent("GOSSIP_CLOSED")
eventFrame:RegisterEvent("QUEST_DETAIL")
eventFrame:RegisterEvent("QUEST_GREETING")
eventFrame:RegisterEvent("QUEST_PROGRESS")
eventFrame:RegisterEvent("QUEST_COMPLETE")
eventFrame:RegisterEvent("QUEST_FINISHED")

eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_LOGIN" then
        JarsNPCChatDB = JarsNPCChatDB or {}
        for k, v in pairs(DEFAULTS) do
            if JarsNPCChatDB[k] == nil then
                JarsNPCChatDB[k] = v
            end
        end

        -- Apply saved font sizes
        titleText:SetFont(FONT, JarsNPCChatDB.titleFontSize, "")
        bodyText:SetFont(FONT, JarsNPCChatDB.fontSize, "")

        SuppressDefaultFrames()

        print("|cff00ccffJar's NPC Chat|r loaded. Type |cff00ff00/jnc|r for help.")

    elseif event == "GOSSIP_SHOW" then
        ShowGossip()

    elseif event == "QUEST_DETAIL" then
        ShowQuestOffer()

    elseif event == "QUEST_GREETING" then
        ShowQuestGreeting()

    elseif event == "QUEST_PROGRESS" then
        ShowQuestProgress()

    elseif event == "QUEST_COMPLETE" then
        ShowQuestComplete()

    elseif event == "GOSSIP_CLOSED" or event == "QUEST_FINISHED" then
        HideUI()
    end
end)

---------------------------------------------------------------------------
-- Slash command
---------------------------------------------------------------------------
SLASH_JARSNPCCHAT1 = "/jnc"
SLASH_JARSNPCCHAT2 = "/jarsnpcchat"
SlashCmdList["JARSNPCCHAT"] = function(msg)
    msg = (msg or ""):lower():trim()
    if msg == "fontsize" or msg == "font" then
        print("|cff00ccffJar's NPC Chat|r - Current font sizes:")
        print("  Body: " .. JarsNPCChatDB.fontSize .. "  Title: " .. JarsNPCChatDB.titleFontSize)
        print("  Usage: /jnc fontsize <body> <title>")
    elseif msg:match("^fontsize%s+%d") then
        local bodySize, titleSize = msg:match("^fontsize%s+(%d+)%s*(%d*)")
        bodySize = tonumber(bodySize)
        titleSize = tonumber(titleSize) or bodySize + 3
        if bodySize >= 10 and bodySize <= 30 then
            JarsNPCChatDB.fontSize = bodySize
            JarsNPCChatDB.titleFontSize = titleSize
            bodyText:SetFont(FONT, bodySize, "")
            titleText:SetFont(FONT, titleSize, "")
            print("|cff00ccffJar's NPC Chat|r - Font sizes set to body=" .. bodySize .. ", title=" .. titleSize)
        else
            print("|cff00ccffJar's NPC Chat|r - Font size must be between 10 and 30.")
        end
    else
        print("|cff00ccffJar's NPC Chat|r - Commands:")
        print("  |cff00ff00/jnc fontsize|r - Show current font sizes")
        print("  |cff00ff00/jnc fontsize <body> [title]|r - Set font sizes (10-30)")
    end
end
