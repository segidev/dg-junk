--[[ DGs Junk -------------------------------------------------------
  Standalone bag-cleanup helper. No dependencies (Auctionator optional for AH).

  Junk = Blizzard gray (Poor) quality + our own marks (DB.marks).

  Two icons:
    * JUNK  (gray border)   - cheapest junk item in your bags.
    * CHEAP (orange border) - cheapest NON-junk item whose value is <= the
                              cheapest junk (worth less than your trash). Hidden
                              when nothing qualifies.
  Shift-click an icon to delete; shift-right-click to ignore; right-click for a
  menu (delete / mark / ignore / settings). In the loot window, hovering an item
  shows a "worth clearing junk to make room?" verdict; shift-click loot with full
  bags clears a junk item (with a confirm dialog) and loots the slot.
----------------------------------------------------------------------------]]

-- API shims (Classic + newer clients)
local GetItemInfo            = C_Item and C_Item.GetItemInfo            or _G.GetItemInfo
local GetContainerNumSlots   = C_Container and C_Container.GetContainerNumSlots   or _G.GetContainerNumSlots
local GetContainerItemID     = C_Container and C_Container.GetContainerItemID     or _G.GetContainerItemID
local PickupContainerItem    = C_Container and C_Container.PickupContainerItem    or _G.PickupContainerItem
local GetContainerItemInfo   = C_Container and C_Container.GetContainerItemInfo   or _G.GetContainerItemInfo
local GetContainerNumFreeSlots = C_Container and C_Container.GetContainerNumFreeSlots or _G.GetContainerNumFreeSlots
local UseContainerItem       = C_Container and C_Container.UseContainerItem       or _G.UseContainerItem
local BACKPACK_CONTAINER     = _G.BACKPACK_CONTAINER or 0
local NUM_BAG_FRAMES         = _G.NUM_BAG_FRAMES or 4
local POOR                   = (Enum and Enum.ItemQuality and Enum.ItemQuality.Poor) or 0
local COMMON                 = (Enum and Enum.ItemQuality and Enum.ItemQuality.Common) or 1
-- green and up: deleting one of these always costs a second confirmation
local UNCOMMON               = (Enum and Enum.ItemQuality and
                               (Enum.ItemQuality.Uncommon or Enum.ItemQuality.Good)) or 2

local DB                                       -- saved vars (pos + ignore list); set on ADDON_LOADED
local Update, BuildConfig, RefreshConfig       -- fwd decls
local RefreshBagOverlays                       -- fwd decl (bag junk-coin overlay)
local RefreshJunkList                          -- fwd decl (Junk-clear tab)
local LootClearCandidates                      -- fwd decl (defined in the loot-assist section)
local config                                   -- settings frame (built lazily)

-- While a frame of ours is being dragged the cursor sweeps across the other
-- frames, and each OnEnter would pop its tooltip mid-drag. Every OnEnter checks
-- this flag, and starting a drag hides whatever is already showing.
local dragging = false
local function BeginDrag() dragging = true; GameTooltip:Hide() end
local function EndDrag()   dragging = false end

-- Preview mode (Debug tab > "Show comparison dialog"). Previews go through the
-- SAME code path the game uses, with real bag items and the real ranking, so what
-- you see can never drift from the live behaviour. The only difference is this
-- flag: while it is set every acting path bails out, deletes and ignores alike.
-- It is armed right before a preview dialog is shown and cleared on that dialog's
-- OnHide, so it can never outlive the dialog it belongs to.
local previewMode = false
local PreviewBtnSync    -- fwd decl: keeps the Debug tab's toggle label in sync

-- Items we never delete (protection list), e.g. Hearthstone.
local exclusions = { [6948] = true, [184871] = true, [260221] = true }

-- Junk test (Blizzard quality + our own marks):
--   our marks (DB.marks) override everything; else Blizzard gray (Poor) quality.
--   DB.marks[id] = true (force junk) / false (force keep).
local function IsJunk(id)
    if not id or exclusions[id] then return false end
    if DB and DB.marks and DB.marks[id] ~= nil then return DB.marks[id] end
    local _, _, quality = GetItemInfo(id)
    return quality == POOR or false
end

local QUESTCLASS = (Enum and Enum.ItemClass and Enum.ItemClass.Questitem) or 12
local function IsQuestItem(id)
    return select(12, GetItemInfo(id)) == QUESTCLASS
end

local function SlotCount(bag, slot)
    local t, count = GetContainerItemInfo(bag, slot)
    if type(t) == "table" then return t.stackCount or 1 end
    return count or 1
end

-- Auctionator is optional. Everything AH-related degrades to vendor prices when
-- it is missing; the "Suggest by AH" checkbox greys itself out (see Check()).
local function HasAuctionator()
    return (Auctionator and Auctionator.API and Auctionator.API.v1) and true or false
end

local function AHPrice(itemID)
    if HasAuctionator() then
        return Auctionator.API.v1.GetAuctionPriceByItemID("DGsJunk", itemID)
    end
end

-- Real worth for ranking/compare. worthEach = per-item value (AH when "Suggest
-- by AH" is on and data exists, else vendor sell price). Returns:
--   totalValue - worthEach * count (rank/sort by this: least valuable stack first)
--   vendorEach - per-item vendor sell price (for the icon's Vendor line)
--   worthEach  - per-item value actually used (AH each, or vendor each)
local function Worth(id, count)
    local stackMax, _, _, price = select(8, GetItemInfo(id))   -- 8=stackMax .. 11=sellPrice
    if not stackMax then return nil end                        -- item info not cached yet
    local vendorEach = price or 0
    local worthEach = vendorEach
    if DB and DB.ahSuggest then
        local ah = AHPrice(id)
        if ah and ah > 0 then worthEach = ah end
    end
    return worthEach * (count or 1), vendorEach, worthEach
end

-- Single bag scan -> cheapest junk item, and cheapest qualifying non-junk item.
-- A non-junk candidate must have a vendor value (>0), not be excluded, and end
-- Cheapest junk item and cheapest non-junk item (each shown on its own icon,
-- independently). Non-junk must have vendor value and not be a quest item.
local function ScanBags()
    local junk, cheap
    for bag = BACKPACK_CONTAINER, NUM_BAG_FRAMES do
        for slot = 1, (GetContainerNumSlots(bag) or 0) do
            local id = GetContainerItemID(bag, slot)
            -- quest items are never suggested, even if marked as junk
            if id and not exclusions[id] and not IsQuestItem(id)
               and not (DB and DB.ignore and DB.ignore[id]) then
                local value, each, worthEach = Worth(id, SlotCount(bag, slot))
                if value then
                    local rec = { bag = bag, slot = slot, id = id, value = value,
                                  each = each, worthEach = worthEach, count = SlotCount(bag, slot) }
                    if IsJunk(id) then
                        rec.junk = true
                        if not junk or value < junk.value then junk = rec end
                    elseif each > 0 then
                        if not cheap or value < cheap.value then cheap = rec end
                    end
                end
            end
        end
    end
    return junk, cheap
end

-------------------------------------------------------------------- formatting
local GREEN, RED, GREY, GOLD = "|cff33ff99", "|cffff4040", "|cff888888", "|cffffcc55"

-- debug logging: prints to chat AND appends to DB.log (saved to disk on /reload,
-- so it can be read from WTF\...\SavedVariables\DGsJunk.lua). Toggle: Log tab.
local function Log(line)
    if not DB then return end
    DB.log = DB.log or {}
    DB.log[#DB.log + 1] = (date and date("%H:%M:%S") or "") .. "  " .. line
    while #DB.log > 400 do table.remove(DB.log, 1) end
end
local function join(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
    return table.concat(parts, " ")
end
local function dbg(...)
    if not (DB and DB.debug) then return end
    Log(join(...))           -- log-only; view in the Log tab (no chat spam)
end
local function err(where, e)  -- always logged; swallowed post-call errors would be invisible otherwise
    local line = "ERROR (" .. where .. "): " .. tostring(e)
    print(RED .. "DGsJunk|r " .. line)
    Log(line)
end

local function Coin(c)
    if not c or c == 0 then return "0c" end
    local g = math.floor(c / 10000)
    local s = math.floor((c % 10000) / 100)
    local cp = c % 100
    local out = ""
    if g > 0 then out = out .. "|cffffd700" .. g .. "g|r " end
    if s > 0 then out = out .. "|cffc7c7cf" .. s .. "s|r " end
    return out .. "|cffeda55f" .. cp .. "c|r"
end

-- Every user action funnels through act() so the Log tab shows what was done,
-- to which item, and what the stored state became.
local function act(what, id, detail)
    local name = id and (select(1, GetItemInfo(id)) or ("item " .. id)) or nil
    dbg("action:", what, name and ("[" .. name .. " id=" .. id .. "]") or "", detail or "")
end

-------------------------------------------------------------------- delete op
-- Deleting anything green or better is a decision you should have to make twice,
-- so it gets our own Yes/No on top of whatever the caller already asked (and on
-- top of Blizzard's own type-DELETE box, which only appears for non-gray items).
StaticPopupDialogs["DGSJUNK_CONFIRM_DELETE_RARE"] = {
    text = "|cffffcc55DGs Junk|r\n\nReally delete this %s item?\n\n%s",
    button1 = YES,
    button2 = NO,
    OnAccept = function(self) if type(self.data) == "function" then self.data() end end,
    timeout = 0, whileDead = true, hideOnEscape = true, showAlert = true, preferredIndex = 3,
}

local function DeleteRecord(rec, tag, confirmed)
    if not rec or not rec.bag then return end
    -- Hardcore: a delete cannot be undone, so the preview guard sits on the
    -- delete itself, not only on the buttons that reach it.
    if previewMode then dbg("preview: delete suppressed for item " .. tostring(rec.id)); return end
    if GetCursorInfo() then return end                 -- something already on cursor
    local link = select(2, GetItemInfo(rec.id or 0))
    local quality = select(3, GetItemInfo(rec.id or 0))
    if not confirmed and quality and quality >= UNCOMMON then
        local qname = _G["ITEM_QUALITY" .. quality .. "_DESC"] or "rare"
        local col = (ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
                     and ITEM_QUALITY_COLORS[quality].hex) or "|cffffffff"
        local what = (link or "this item") .. ((rec.count or 1) > 1 and (" x" .. rec.count) or "")
        act("delete blocked", rec.id, "quality " .. quality .. " - asking to confirm")
        StaticPopup_Show("DGSJUNK_CONFIRM_DELETE_RARE", col .. qname .. "|r", what,
            function() DeleteRecord(rec, tag, true) end)
        return
    end
    act("delete", rec.id, (tag or "deleted") .. " bag " .. tostring(rec.bag) .. " slot " .. tostring(rec.slot))
    PickupContainerItem(rec.bag, rec.slot)
    DeleteCursorItem()                                 -- non-gray -> Blizzard raises a confirm popup
    print(GREEN .. "DGs Junk|r " .. (tag or "deleted") .. " " .. (link or "item"))
end

local function IgnoreRecord(rec)
    if not rec then return end
    DB.ignore = DB.ignore or {}
    DB.ignore[rec.id] = rec.junk and "junk" or "normal"
    act("ignore", rec.id, "category=" .. DB.ignore[rec.id])
    local link = select(2, GetItemInfo(rec.id))
    print(GOLD .. "DGs Junk|r ignoring " .. (link or "item") .. " |cff888888(/dgjunk to manage)|r")
end

local function OpenSettings()
    if not config then BuildConfig() end
    RefreshConfig()
    config:Show()
end

--------------------------------------------------------- right-click menu
-- 1.15.9 (July 2026) removed EasyMenu/UIDropDownMenu in favour of MenuUtil.
-- Prefer the new API, fall back to the old one, else just print.
local legacyMenuFrame
-- rec may be nil (empty placeholder frame) -> Settings-only menu
local function OpenMenu(rec, owner)
    local link = rec and (select(2, GetItemInfo(rec.id)) or "this item")
    local marked = rec and IsJunk(rec.id)
    local function doDelete() DeleteRecord(rec, "deleted"); if C_Timer then C_Timer.After(0.15, Update) end end
    local function doIgnore() IgnoreRecord(rec); Update() end
    -- true = force junk, false = force keep (a real decision, not "no opinion";
    -- only the Junk tab's X clears the mark back to nil)
    local function doMark()   DB.marks[rec.id] = true;  act("mark", rec.id, "marks=true (force junk)");  Update() end
    local function doUnmark() DB.marks[rec.id] = false; act("unmark", rec.id, "marks=false (force keep)"); Update() end

    if MenuUtil and MenuUtil.CreateContextMenu then          -- modern (retail 11.0 / classic 1.15.9)
        MenuUtil.CreateContextMenu(owner or UIParent, function(_, root)
            root:CreateTitle("DGs Junk")
            -- Safe actions first, Delete fenced off by dividers so it is never
            -- the neighbour of a harmless click.
            if rec then
                root:CreateButton("Ignore " .. link, doIgnore)
                root:CreateButton(marked and "Unmark as junk" or "Mark as junk", marked and doUnmark or doMark)
                root:CreateDivider()
                root:CreateButton("Delete " .. link, doDelete)
                root:CreateDivider()
            end
            root:CreateButton("Settings", OpenSettings)
        end)
    elseif EasyMenu then                                     -- legacy fallback
        local menu = { { text = "DGs Junk", isTitle = true, notCheckable = true } }
        if rec then
            menu[#menu + 1] = { text = "Ignore " .. link, notCheckable = true, func = doIgnore }
            menu[#menu + 1] = { text = marked and "Unmark as junk" or "Mark as junk",
                                notCheckable = true, func = marked and doUnmark or doMark }
            menu[#menu + 1] = { text = "", notCheckable = true, disabled = true }   -- divider
            menu[#menu + 1] = { text = "Delete " .. link, notCheckable = true, func = doDelete }
            menu[#menu + 1] = { text = "", notCheckable = true, disabled = true }   -- divider
        end
        menu[#menu + 1] = { text = "Settings", notCheckable = true, func = OpenSettings }
        menu[#menu + 1] = { text = "Cancel", notCheckable = true, func = function() end }
        if not legacyMenuFrame then
            legacyMenuFrame = CreateFrame("Frame", "DGsJunkContextMenu", UIParent, "UIDropDownMenuTemplate")
        end
        EasyMenu(menu, legacyMenuFrame, "cursor", 0, 0, "MENU")
    else
        print(GOLD .. "DGs Junk|r no menu API; use shift-left = delete, shift-right = ignore, /dgjunk = settings")
    end
end

--------------------------------------------------------------- icon factory
local function MakeIcon(name, borderColor, labelText, labelColor)
    local b = CreateFrame("Button", "DGsJunk_" .. name, UIParent)
    b:SetSize(38, 38)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    b.bg = b:CreateTexture(nil, "BACKGROUND")
    b.bg:SetPoint("TOPLEFT", -1, 1)
    b.bg:SetPoint("BOTTOMRIGHT", 1, -1)
    b.bg:SetColorTexture(borderColor[1], borderColor[2], borderColor[3], 1)

    -- transparent bordered placeholder shown in "Always show" mode when empty
    b.empty = CreateFrame("Frame", nil, b, "BackdropTemplate")
    b.empty:SetPoint("TOPLEFT", -2, 2)
    b.empty:SetPoint("BOTTOMRIGHT", 2, -2)
    b.empty:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    b.empty:SetBackdropColor(0, 0, 0, 0.15)                         -- barely-there fill
    b.empty:SetBackdropBorderColor(borderColor[1], borderColor[2], borderColor[3], 0.9)
    b.empty:Hide()

    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetPoint("TOPLEFT", 1, -1)
    b.icon:SetPoint("BOTTOMRIGHT", -1, 1)
    b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    b.label = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    b.label:SetPoint("BOTTOM", b, "TOP", 0, 1)
    b.label:SetText(labelColor .. labelText .. "|r")

    b.count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    b.count:SetPoint("BOTTOMRIGHT", -1, 1)

    b.vendor = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    b.vendor:SetPoint("TOP", b, "BOTTOM", 0, -2)

    b.ah = b:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    b.ah:SetPoint("TOP", b.vendor, "BOTTOM", 0, -1)

    b:SetScript("OnEnter", function(self)
        if dragging then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if self.rec then
            GameTooltip:SetItemByID(self.rec.id)
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("|cff33ff99Shift-left-click|r|cff888888 delete|r")
            GameTooltip:AddLine("|cffff8800Shift-right-click|r|cff888888 ignore|r")
            GameTooltip:AddLine("|cffffcc55Right-click|r|cff888888 for menu (delete / ignore / settings)|r")
        else
            GameTooltip:AddLine("DGs Junk")
            GameTooltip:AddLine("|cff888888Nothing to clear right now.|r")
            GameTooltip:AddLine("|cffffcc55Right-click|r|cff888888 for settings|r")
        end
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", GameTooltip_Hide)

    b:SetScript("OnClick", function(self, button)
        if not self.rec then
            if button == "RightButton" then OpenMenu(nil, self) end   -- empty frame -> settings menu
            return
        end
        if button == "LeftButton" and IsShiftKeyDown() then
            DeleteRecord(self.rec, "deleted")
            if C_Timer then C_Timer.After(0.15, Update) end
        elseif button == "RightButton" then
            if IsShiftKeyDown() then
                IgnoreRecord(self.rec)
                Update()
            else
                OpenMenu(self.rec, self)
            end
        end
    end)

    function b:SetRecord(rec)
        self.rec = rec
        if not rec then
            if DB and DB.alwaysShow then          -- transparent bordered placeholder
                self.icon:Hide()
                self.bg:Hide()
                self.empty:Show()
                self.count:SetText("")
                self.vendor:SetText("")
                self.ah:SetText("")
                self:Show()
            else
                self:Hide()
            end
            return
        end
        self.empty:Hide()
        self.bg:Show()
        self.icon:Show()
        local _, _, _, _, _, _, _, _, _, tex = GetItemInfo(rec.id)
        self.icon:SetTexture(tex)
        self.count:SetText(rec.count > 1 and rec.count or "")
        self.vendor:SetText(Coin((rec.each or 0) * rec.count))
        local ah = AHPrice(rec.id)
        self.ah:SetText(ah and ("AH " .. Coin(ah)) or GREY .. "AH --|r")
        self:Show()
    end

    return b
end

local junkIcon  = MakeIcon("Junk",  {0.55, 0.55, 0.55}, "Junk",  GREY)
local cheapIcon = MakeIcon("Cheap", {0.90, 0.55, 0.15}, "Cheap!", GOLD)

-- A small grip handle to the left is the mover (icons themselves aren't draggable,
-- so clicks never get mistaken for drags). The cheap icon rides to the right.
junkIcon:SetMovable(true)
local drag = CreateFrame("Button", "DGsJunkDragHandle", junkIcon)
drag:SetSize(12, 38)
drag:SetPoint("RIGHT", junkIcon, "LEFT", -2, 0)
drag:EnableMouse(true)
drag:RegisterForDrag("LeftButton")
drag:RegisterForClicks("RightButtonUp")
drag:SetScript("OnClick", function(self, button)
    if button == "RightButton" then OpenMenu(nil, self) end   -- grip -> menu (settings)
end)
drag.bg = drag:CreateTexture(nil, "BACKGROUND")
drag.bg:SetAllPoints()
drag.bg:SetColorTexture(0.15, 0.15, 0.15, 0.55)
for i = -1, 1 do                                   -- three grip dots
    local d = drag:CreateTexture(nil, "OVERLAY")
    d:SetSize(3, 3)
    d:SetColorTexture(0.85, 0.85, 0.85, 0.8)
    d:SetPoint("CENTER", drag, "CENTER", 0, i * 6)
end
drag:SetScript("OnDragStart", function() BeginDrag(); junkIcon:StartMoving() end)
drag:SetScript("OnDragStop", function()
    junkIcon:StopMovingOrSizing()
    EndDrag()
    local p, _, rp, x, y = junkIcon:GetPoint()
    DB.pos = { p, rp, x, y }
end)
drag:SetScript("OnEnter", function(self)
    if dragging then return end
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine("DGs Junk")
    GameTooltip:AddLine("|cff888888Drag to move|r")
    GameTooltip:AddLine("|cffffcc55Right-click|r|cff888888 for menu|r")
    GameTooltip:Show()
end)
drag:SetScript("OnLeave", GameTooltip_Hide)
cheapIcon:SetPoint("LEFT", junkIcon, "RIGHT", 10, 0)

local function ApplyScale()
    local s = (DB and DB.scale) or 1
    junkIcon:SetScale(s)      -- drag handle is a child, scales with it
    cheapIcon:SetScale(s)
end

----------------------------------------------------------- minimap button
-- Self-contained (no LibDBIcon dependency). Draggable around the minimap ring.
local ADDON_ICON = "Interface\\Icons\\INV_Misc_Bag_10"
local minimapBtn

local function UpdateMinimapPos()
    if not minimapBtn then return end
    local angle = math.rad((DB and DB.minimapAngle) or 200)
    minimapBtn:ClearAllPoints()
    minimapBtn:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * 80, math.sin(angle) * 80)
end

local function BuildMinimapButton()
    local b = CreateFrame("Button", "DGsJunkMinimapButton", Minimap)
    b:SetSize(31, 31)
    b:SetFrameStrata("MEDIUM")
    b:SetFrameLevel(8)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:RegisterForDrag("LeftButton")
    b:SetMovable(true)

    local icon = b:CreateTexture(nil, "BACKGROUND")
    icon:SetSize(20, 20)
    icon:SetPoint("CENTER", -1, 1)
    icon:SetTexture(ADDON_ICON)
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    local border = b:CreateTexture(nil, "OVERLAY")
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

    local function dragUpdate()
        local mx, my = Minimap:GetCenter()
        local scale = Minimap:GetEffectiveScale()
        local px, py = GetCursorPosition()
        px, py = px / scale, py / scale
        DB.minimapAngle = math.deg(math.atan2(py - my, px - mx))
        UpdateMinimapPos()
    end
    b:SetScript("OnDragStart", function(self) BeginDrag(); self:SetScript("OnUpdate", dragUpdate) end)
    b:SetScript("OnDragStop",  function(self) self:SetScript("OnUpdate", nil); EndDrag() end)

    b:SetScript("OnClick", function(self, button)
        if button == "RightButton" then                 -- settings
            if config and config:IsShown() then config:Hide() else OpenSettings() end
        else                                            -- left: show/hide the item frames
            DB.showFrames = (DB.showFrames == false)
            Update()
            if config and config:IsShown() then RefreshConfig() end   -- keep the checkbox in sync
        end
    end)
    b:SetScript("OnEnter", function(self)
        if dragging then return end
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("DGs Junk")
        GameTooltip:AddLine("|cff888888Left-click:|r show/hide frames")
        GameTooltip:AddLine("|cff888888Right-click:|r settings")
        GameTooltip:AddLine("|cff888888Drag:|r move around minimap")
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", GameTooltip_Hide)

    minimapBtn = b
    return b
end

local function ApplyMinimap()
    if DB and DB.minimap == false then
        if minimapBtn then minimapBtn:Hide() end
        return
    end
    if not minimapBtn then BuildMinimapButton() end
    UpdateMinimapPos()
    minimapBtn:Show()
end

-------------------------------------------------------------------- refresh
Update = function()
    if DB and DB.showFrames == false then      -- master hide (minimap left-click / settings)
        junkIcon:Hide()
        cheapIcon:Hide()
        return
    end
    local junk, cheap = ScanBags()
    junkIcon:SetRecord(junk)
    cheapIcon:SetRecord(cheap)
    if RefreshBagOverlays then RefreshBagOverlays() end
    -- Keep an open settings window honest: ignoring an item or marking it as
    -- junk must show up immediately in the tab the user is looking at. Only the
    -- visible panel is rebuilt; the others refresh when ShowTab switches to them.
    if config and config:IsShown() and config.panels then
        if RefreshJunkList and config.panels.junk:IsShown() then RefreshJunkList() end
        if RefreshConfig and config.panels.ignored:IsShown() then RefreshConfig() end
    end
end

------------------------------------------------------ bag junk-coin overlay
-- Items WE marked as junk (DB.marks[id] == true) get a small coin in the
-- top-left of their bag slot, so the mark is visible in the bags and not only
-- in our own icons/menu.
--
-- Works with whatever bag UI is loaded:
--   * Bagnon/BagBrother - its item buttons are a class (Bagnon.Item) built on
--     ContainerFrameItemButtonTemplate; hooking the CLASS method Update covers
--     every instance (they inherit through __index).
--   * Default bags - ContainerFrame_Update / ContainerFrameItemButton_OnUpdate.
-- We only ADD a texture; we never touch the border, quality colour or Blizzard's
-- own JunkIcon, so nothing another bag addon draws gets overwritten.
local coinOwners = setmetatable({}, { __mode = "k" })   -- button -> texture (weak: buttons may be recycled)

local function CoinTexture(button)
    local t = coinOwners[button]
    if t then return t end
    local ok, tex = pcall(function()
        local x = button:CreateTexture(nil, "OVERLAY", nil, 7)
        x:SetSize(13, 13)
        x:SetPoint("TOPLEFT", 1, -1)
        if x.SetAtlas then pcall(x.SetAtlas, x, "bags-junkcoin", true) end
        if not x:GetTexture() then x:SetTexture("Interface\\Buttons\\UI-GroupLoot-Coin-Up") end
        x:Hide()
        return x
    end)
    if not ok then return nil end
    coinOwners[button] = tex
    return tex
end

-- true only for our OWN marks - plain gray items are not flagged (they already
-- read as junk by colour, and flagging them all would be noise).
local function IsMarkedJunk(id)
    return id and DB and DB.marks and DB.marks[id] == true or false
end

local function ApplyCoin(button, bag, slot)
    if not button then return end
    local id
    if button.info and button.info.itemID then
        id = button.info.itemID                         -- Bagnon caches it
    elseif bag and slot then
        id = GetContainerItemID(bag, slot)
    end
    local show = IsMarkedJunk(id)
    local tex = coinOwners[button]
    if not show and not tex then return end             -- nothing to draw, nothing to hide
    tex = tex or CoinTexture(button)
    if tex then tex:SetShown(show) end
end

-- Refresh every button we've ever drawn on (called after a mark changes).
RefreshBagOverlays = function()
    for button in pairs(coinOwners) do
        local okBag, bag = pcall(function() return button.GetBag and button:GetBag() end)
        local slot = button.GetID and button:GetID()
        ApplyCoin(button, okBag and bag or nil, slot)
    end
end

local overlayHooked = false
local function HookBagButtons()
    if overlayHooked then return end
    overlayHooked = true

    -- Bagnon / BagBrother (class-level hook -> all current and future buttons)
    local ok = pcall(function()
        local Item = Bagnon and Bagnon.Item
        if Item and Item.Update then
            hooksecurefunc(Item, "Update", function(self)
                local okc = pcall(ApplyCoin, self, self.GetBag and self:GetBag(), self:GetID())
                if not okc then err("bagnon-coin", "ApplyCoin failed") end
            end)
            dbg("bag overlay: hooked Bagnon.Item:Update")
            return true
        end
        dbg("bag overlay: Bagnon.Item not found")
    end)
    if not ok then dbg("bag overlay: Bagnon hook failed") end

    -- Default Blizzard bags
    if _G.ContainerFrame_Update then
        hooksecurefunc("ContainerFrame_Update", function(frame)
            pcall(function()
                local bag = frame:GetID()
                local name = frame:GetName()
                for i = 1, (frame.size or 0) do
                    local button = _G[name .. "Item" .. i]
                    if button then ApplyCoin(button, bag, button:GetID()) end
                end
            end)
        end)
        dbg("bag overlay: hooked ContainerFrame_Update")
    end
end

------------------------------------------------------------ merchant autosell
-- Auto-sell at a vendor, deliberately narrow so it can never fight another
-- gray-seller: we ONLY sell items we marked ourselves that are above Poor
-- quality. Plain grays are left to whoever else wants them - if no other addon
-- sells them, Blizzard's own "sell all junk" still does.
-- DB.marks[id] == false (Ignore) and the exclusion list are never sold.
local function AutoSellMarked()
    if not (DB and DB.autoSell) then return end
    local sold, value, delay = 0, 0, 0
    for bag = BACKPACK_CONTAINER, NUM_BAG_FRAMES do
        for slot = 1, (GetContainerNumSlots(bag) or 0) do
            local id = GetContainerItemID(bag, slot)
            if id and not exclusions[id] and DB.marks[id] == true and not IsQuestItem(id) then
                local _, _, quality = GetItemInfo(id)
                if quality and quality > POOR then      -- grays: not ours to sell
                    local count = SlotCount(bag, slot)
                    local _, vendorEach = Worth(id, count)
                    if (vendorEach or 0) > 0 then
                        local b, s = bag, slot
                        C_Timer.After(delay, function()
                            if MerchantFrame and MerchantFrame:IsShown() then
                                pcall(function() UseContainerItem(b, s) end)
                            end
                        end)
                        delay = delay + 0.25            -- one item per 0.25s: no "too fast" throttling
                        sold, value = sold + 1, value + vendorEach * count
                    end
                end
            end
        end
    end
    if sold > 0 then
        print("|cffffd200DGs Junk|r sold " .. sold .. " marked item(s) for " .. Coin(value) .. ".")
        dbg("autosell: " .. sold .. " stacks, " .. value .. "c")
        if C_Timer then C_Timer.After(delay + 0.3, Update) end
    end
end

------------------------------------------------ stackability
-- Full bags do NOT mean an item is unlootable: anything that stacks onto a
-- partial stack you already carry costs no slot at all. Returns how many more of
-- `id` fit into existing stacks.
local function StackRoom(id)
    if not id then return 0 end
    local maxStack = select(8, GetItemInfo(id))
    if not maxStack or maxStack <= 1 then return 0 end
    local room = 0
    for bag = BACKPACK_CONTAINER, NUM_BAG_FRAMES do
        for slot = 1, (GetContainerNumSlots(bag) or 0) do
            if GetContainerItemID(bag, slot) == id then
                room = room + (maxStack - (SlotCount(bag, slot) or 1))
            end
        end
    end
    return room
end

------------------------------------------------ tooltip keep/trash verdict
local function IsLootTooltip(tip)
    local info = tip.info or tip.processingInfo          -- most reliable: how it was populated
    if info and info.getterName == "GetLootItem" then return true end
    local owner = tip:GetOwner()
    local nm = owner and owner.GetName and owner:GetName()
    return nm and nm:find("LootButton") and _G.LootFrame and _G.LootFrame:IsShown() and true or false
end

local function linkID(link) return link and tonumber(link:match("item:(%d+)")) end

-- 1.15.9 removed tip:GetItem(); the modern getter is TooltipUtil.GetDisplayedItem
-- (this is what BagBrother/Auctionator use, and it works for loot tooltips too).
local function TipItemID(tip, data)
    if data and data.id then return data.id end
    if TooltipUtil and TooltipUtil.GetDisplayedItem then
        local _, link = TooltipUtil.GetDisplayedItem(tip)
        local id = linkID(link)
        if id then return id end
    end
    -- getterName path (loot slot, when the link isn't resolved yet)
    local info = tip.info or tip.processingInfo
    if info and info.getterName and info.getterArgs then
        local g = info.getterName
        if g == "GetLootItem" and GetLootSlotLink then
            return linkID(GetLootSlotLink(info.getterArgs[1]))
        elseif g == "GetLootRollItem" and GetLootRollItemLink then
            return linkID(GetLootRollItemLink(info.getterArgs[1]))
        end
    end
    if tip.GetItem then local _, link = tip:GetItem(); return linkID(link) end  -- legacy
end

local function AddVerdict(tip, id)
    if not id then dbg("no itemID from tooltip"); return end
    if tip.dgsjID == id then return end
    tip.dgsjID = id
    local _, _, hoverWorth = Worth(id, 1)
    if not hoverWorth then dbg("no value for id", id, "(info not cached)"); return end
    if not IsLootTooltip(tip) then return end          -- verdict only in the loot window, not bags
    if IsQuestItem(id) then                            -- always worth taking, never compared on value
        dbg("quest item", id, "- take it")
        tip:AddLine(GREEN .. "Quest item: Take it!|r")
        return tip:Show()
    end
    if StackRoom(id) > 0 then                          -- stacks onto what you carry: free
        dbg("stackable", id, "- room in an existing stack")
        tip:AddLine(GREEN .. "Loot it|r " .. GREY .. "(stacks, costs no bag slot)|r")
        return tip:Show()
    end

    -- Compare against what would actually be discarded: cheapest junk OR non-junk,
    -- the same candidates the loot-clear dialog offers, using the same numbers.
    -- TOTAL stack value, exactly like the dialog: deleting a slot
    -- costs you the whole stack, so a 3x stack of 1c items costs 3c, not 1c.
    local junk, other = LootClearCandidates()
    local worths = {}
    if junk  then worths[#worths + 1] = junk.value  or 0 end
    if other then worths[#worths + 1] = other.value or 0 end
    dbg("loot verdict id=" .. id, "hover=" .. hoverWorth,
        "junk=" .. (junk and (junk.id .. "@" .. (junk.value or 0) .. " x" .. (junk.count or 1)) or "none"),
        "other=" .. (other and (other.id .. "@" .. (other.value or 0) .. " x" .. (other.count or 1)) or "none"))

    if #worths == 0 then
        tip:AddLine(GREY .. "Nothing to clear a slot|r")
    else
        -- Only the cheapest candidate matters: it is the one the dialog
        -- recommends, so that is what looting this item would actually cost.
        local lo = math.min(unpack(worths))
        if hoverWorth > lo then
            tip:AddLine(GREEN .. "Loot it|r " .. GREY .. "(cheapest to discard " .. Coin(lo) .. ")|r")
        else
            tip:AddLine(RED .. "Skip|r " .. GREY .. "(cheapest to discard " .. Coin(lo) .. ")|r")
        end
    end
    tip:Show()
end

local function clearGuard(tip) tip.dgsjID = nil end

-- run AddVerdict safely so swallowed post-call errors become visible
local function SafeVerdict(tip, id)
    local ok, e = pcall(AddVerdict, tip, id)
    if not ok then err("AddVerdict", e) end
end

if C_TooltipInfo and TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall then
    -- modern path (1.15.9 / retail): one post-call per populate
    dbg("using modern TooltipDataProcessor path")
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tip, data)
        if tip == GameTooltip or tip == ItemRefTooltip then
            local ok, id = pcall(TipItemID, tip, data)
            if ok then SafeVerdict(tip, id) else err("TipItemID", id) end
        end
    end)
    GameTooltip:HookScript("OnTooltipCleared", clearGuard)
    if ItemRefTooltip then ItemRefTooltip:HookScript("OnTooltipCleared", clearGuard) end
else
    -- legacy path
    dbg("using legacy OnTooltipSetItem path")
    local function hook(tip) SafeVerdict(tip, TipItemID(tip)) end
    GameTooltip:HookScript("OnTooltipSetItem", hook)
    GameTooltip:HookScript("OnTooltipCleared", clearGuard)
    if ItemRefTooltip then
        ItemRefTooltip:HookScript("OnTooltipSetItem", hook)
        ItemRefTooltip:HookScript("OnTooltipCleared", clearGuard)
    end
end

------------------------------------------------ loot assist (shift-click)
-- Shift-click a loot item with full bags -> delete cheapest GRAY junk (instant,
-- no confirm popup) and re-loot the slot. Hooks LootSlot so it is UI-agnostic.
-- Toggle in the Settings tab.
local function BagsFull()
    for bag = BACKPACK_CONTAINER, NUM_BAG_FRAMES do
        local free, bagType = GetContainerNumFreeSlots(bag)
        if free and free > 0 and (not bagType or bagType == 0) then return false end
    end
    return true
end

-- Deletable JUNK and deletable NON-JUNK candidates for making room, cheapest
-- first. "Deletable" = quality <= Common (instant delete, no confirm popup), so
-- cycling through the lists can never walk into your greens.
-- Returns the cheapest of each (what the tooltip verdict and the row tinting
-- use, unchanged) plus the full ranked lists the dialog cycles through.
local MAX_CANDIDATES = 10       -- deep enough to find an alternative, short enough to page through
LootClearCandidates = function()
    local junkList, otherList = {}, {}
    for bag = BACKPACK_CONTAINER, NUM_BAG_FRAMES do
        for slot = 1, (GetContainerNumSlots(bag) or 0) do
            local id = GetContainerItemID(bag, slot)
            -- quest items are never offered for deletion, even if marked as junk
            if id and not exclusions[id] and not IsQuestItem(id)
               and not (DB and DB.ignore and DB.ignore[id]) then
                local _, _, q = GetItemInfo(id)
                if q and q <= COMMON then
                    local value, each, worthEach = Worth(id, SlotCount(bag, slot))
                    if value then
                        local rec = { bag = bag, slot = slot, id = id, value = value, each = each,
                                      worthEach = worthEach, count = SlotCount(bag, slot) }
                        if IsJunk(id) then
                            rec.junk = true
                            junkList[#junkList + 1] = rec
                        elseif each > 0 then
                            otherList[#otherList + 1] = rec
                        end
                    end
                end
            end
        end
    end
    -- Cheapest first, and only the cheapest MAX_CANDIDATES are offered: past that
    -- you are picking through things you actually want to keep.
    -- table.sort is not stable, so equal records (three clams, all count 1) would
    -- survive in an arbitrary order and the dialog would pick a different one
    -- each time it opened. Bag/slot makes the choice reproducible.
    local function byValue(a, b)
        if a.value ~= b.value then return a.value < b.value end
        if (a.count or 1) ~= (b.count or 1) then return (a.count or 1) < (b.count or 1) end
        if a.bag ~= b.bag then return a.bag < b.bag end
        return a.slot < b.slot
    end
    -- One entry per ITEM, not per bag slot. Several slots holding the same thing
    -- are the same decision - each frees exactly one slot - and every one after
    -- the cheapest is a strictly worse version of a choice you already made, so
    -- they would only waste pages. Sorting first means the survivor is the
    -- cheapest slot holding that item: of an 18/19/20 stack of cloth you are
    -- offered the 18, and the other two are untouched. Deleting still only ever
    -- takes the one slot on show.
    local function byItem(list)
        table.sort(list, byValue)
        local out, seen = {}, {}
        for _, rec in ipairs(list) do
            if not seen[rec.id] then
                seen[rec.id] = true
                out[#out + 1] = rec
                if #out >= MAX_CANDIDATES then break end   -- ten distinct items, not ten records
            end
        end
        return out
    end
    junkList, otherList = byItem(junkList), byItem(otherList)
    return junkList[1], otherList[1], junkList, otherList
end

local function DoLootClear(rec, slot)
    if not rec then return end
    if previewMode then dbg("preview: loot-clear suppressed"); return end
    -- Never trade an item for nothing: if the loot went away between opening the
    -- dialog and clicking (ran off, corpse despawned, someone else looted it),
    -- abort instead of deleting.
    local gone = (GetNumLootItems and GetNumLootItems() == 0)
        or (slot and GetLootSlotLink and not GetLootSlotLink(slot))
    if gone then
        dbg("loot-clear aborted: loot slot", slot, "no longer available")
        print(GOLD .. "DGs Junk|r loot is gone - nothing deleted.")
        return
    end
    DeleteRecord(rec, "cleared for loot:")
    pcall(LootSlot, slot)
    if C_Timer then C_Timer.After(0.15, Update) end
end

-- Custom confirm dialog: loot item on the left, the two cheapest replace
-- candidates (junk + non-junk) on the right. Click a candidate to delete it and
-- loot; hover any icon to compare; price shown under each icon.
local confirmFrame
-- The dialog only makes sense while the loot window is open: its whole promise is
-- "delete this, then loot that". If the loot closes (you ran away, the corpse
-- despawned, someone else took it) the slot is gone, so the dialog must go too -
-- otherwise a click deletes an item and loots nothing.
local function CloseLootConfirm()
    if confirmFrame and confirmFrame:IsShown() then confirmFrame:Hide() end
end
local function BuildConfirm()
    local f = CreateFrame("Frame", "DGsJunkConfirm", UIParent, "BasicFrameTemplateWithInset")
    f:SetSize(440, 250)   -- vendor + AH row under each icon, plus the bottom hint line
    f:SetPoint("CENTER")
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    local title = f.TitleText or _G["DGsJunkConfirmTitleText"]
    if title then title:SetText("DGs Junk") end
    tinsert(UISpecialFrames, "DGsJunkConfirm")
    local closeBtn = f.CloseButton or _G["DGsJunkConfirmCloseButton"]
    if closeBtn then closeBtn:SetScript("OnClick", function() f:Hide() end) end

    local head = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    head:SetPoint("TOP", 0, -26)
    head:SetText("Bags full - click a junk/item to delete and loot:")
    f.head = head
    -- Preview banner: hidden in normal use, so the live dialog is unchanged.
    local banner = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    -- below the "tag" line under the icons; the frame grows by the same amount
    -- in preview so it never collides with the Cancel button.
    banner:SetPoint("TOP", 0, -186)
    banner:Hide()
    f.banner = banner

    local function Slot(cap, x)
        local b = CreateFrame("Button", nil, f)
        b:SetSize(40, 40)
        b:SetPoint("TOPLEFT", x, -66)
        -- Four thin edges rather than one filled rectangle behind the icon. For a
        -- filled slot they look identical (the icon covered the middle anyway),
        -- but an EMPTY slot then keeps the same border with nothing painted
        -- inside it, so the frame background shows through instead of a grey box.
        b.edges = {}
        for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
            local t = b:CreateTexture(nil, "BACKGROUND")
            if side == "TOP" or side == "BOTTOM" then
                t:SetPoint("LEFT",  b, "LEFT",  -2, 0)
                t:SetPoint("RIGHT", b, "RIGHT",  2, 0)
                t:SetHeight(2)
                t:SetPoint(side, b, side, 0, side == "TOP" and 2 or -2)
            else
                t:SetPoint("TOP",    b, "TOP",     0,  2)
                t:SetPoint("BOTTOM", b, "BOTTOM",  0, -2)
                t:SetWidth(2)
                t:SetPoint(side, b, side, side == "LEFT" and -2 or 2, 0)
            end
            b.edges[#b.edges + 1] = t
        end
        b.SetBorder = function(r, g, bl)
            for _, t in ipairs(b.edges) do t:SetColorTexture(r, g, bl, 1) end
        end
        b.SetBorder(0.3, 0.3, 0.3)
        b.icon = b:CreateTexture(nil, "ARTWORK")
        b.icon:SetAllPoints(); b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        b.cap = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        b.cap:SetPoint("BOTTOM", b, "TOP", 0, 3); b.cap:SetText(cap)
        b.capBase = cap                     -- the paging counter is appended to this
        b.name = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        b.name:SetPoint("TOP", b, "BOTTOM", 0, -3); b.name:SetWidth(104); b.name:SetJustifyH("CENTER"); b.name:SetHeight(24)
        b.price = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        b.price:SetPoint("TOP", b.name, "BOTTOM", 0, -1)
        -- Second price line: the AH value, shown whenever Auctionator has one, no
        -- matter which basis "Suggest by AH" is ranking on. The setting picks what
        -- the recommendation is computed from; it should not hide the other number.
        b.ah = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        b.ah:SetPoint("TOP", b.price, "BOTTOM", 0, -1)
        b.tag = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        b.tag:SetPoint("TOP", b.ah, "BOTTOM", 0, -1)
        return b
    end

    -- Paging arrows, one pair per candidate slot: left of the icon steps back
    -- towards the cheapest, right steps up towards the dearest. No wrap-around -
    -- wrapping from the most expensive straight back to the cheapest is exactly
    -- the misclick that cannot be undone. The end of a list greys its arrow out.
    local function Pager(b, which)
        local function Arrow(dir, texture, myPoint, itsPoint, xOff)
            local a = CreateFrame("Button", nil, f)
            a:SetSize(22, 22)
            a:SetPoint(myPoint, b, itsPoint, xOff, 0)
            a:SetNormalTexture("Interface\\Buttons\\UI-SpellbookIcon-" .. texture .. "Page-Up")
            a:SetPushedTexture("Interface\\Buttons\\UI-SpellbookIcon-" .. texture .. "Page-Down")
            a:SetDisabledTexture("Interface\\Buttons\\UI-SpellbookIcon-" .. texture .. "Page-Disabled")
            a:SetScript("OnClick", function() f.Step(which, dir) end)
            return a
        end
        b.prev = Arrow(-1, "Prev", "RIGHT", "LEFT",  -4)
        b.next = Arrow( 1, "Next", "LEFT",  "RIGHT",  4)
        -- Same movement on the wheel: faster once you know it is there, and the
        -- arrows stay as the discoverable version of it.
        b:EnableMouseWheel(true)
        b:SetScript("OnMouseWheel", function(_, delta) f.Step(which, delta > 0 and -1 or 1) end)
    end

    local function hover(anchor) return function(self)
        if self.link then GameTooltip:SetOwner(self, anchor); GameTooltip:SetHyperlink(self.link); GameTooltip:Show()
        elseif self.itemID then GameTooltip:SetOwner(self, anchor); GameTooltip:SetItemByID(self.itemID); GameTooltip:Show() end
    end end

    f.lootBtn = Slot("|cff33ff99Loot|r", 40)
    f.lootBtn:SetScript("OnEnter", hover("ANCHOR_LEFT"))
    f.lootBtn:SetScript("OnLeave", GameTooltip_Hide)
    local arrow = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    arrow:SetPoint("LEFT", f.lootBtn, "RIGHT", 26, 0); arrow:SetText("|cffaaaaaa>|r")

    f.junkBtn  = Slot("|cffcfcfcfJunk|r", 220)
    f.otherBtn = Slot("|cffffcc55Non-junk|r", 320)
    Pager(f.junkBtn,  "junk")
    Pager(f.otherBtn, "other")
    for _, b in ipairs({ f.junkBtn, f.otherBtn }) do
        b:SetScript("OnEnter", hover("ANCHOR_RIGHT"))
        b:SetScript("OnLeave", GameTooltip_Hide)
        b:SetScript("OnClick", function(self)
            if f.preview then
                print(GOLD .. "DGs Junk|r preview mode - nothing was deleted.")
                return                                   -- dialog stays open so you can keep poking at it
            end
            if not self.rec then return end
            -- The record names a bag slot, and bags can shuffle while the dialog
            -- sits open (another delete, a stack merging, an addon moving things).
            -- Deleting by stale coordinates would destroy whatever landed there
            -- instead, so re-check the slot still holds what was picked.
            if GetContainerItemID(self.rec.bag, self.rec.slot) ~= self.rec.id then
                dbg("clear aborted: bag " .. tostring(self.rec.bag) .. " slot " ..
                    tostring(self.rec.slot) .. " no longer holds item " .. tostring(self.rec.id))
                print(GOLD .. "DGs Junk|r your bags changed - nothing deleted, pick again.")
                if f.SyncLists then f.SyncLists() end
                return
            end
            f:Hide(); DoLootClear(self.rec, f.slot)
        end)
    end

    local cancel = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    cancel:SetSize(120, 24); cancel:SetPoint("BOTTOM", 0, 12); cancel:SetText(CANCEL or "Cancel")
    cancel:SetScript("OnClick", function() f:Hide() end)

    -- Paging state and rendering live on the frame, so the arrows, the wheel and
    -- a bag update can all re-render without going back through ShowLootConfirm.
    local function listFor(which) return ((which == "junk") and f.junkList or f.otherList) or {} end
    local function idxFor(which)  return ((which == "junk") and f.junkIdx  or f.otherIdx) or 1 end

    -- Both slots are ALWAYS drawn. An empty one showing nothing at all reads as a
    -- broken dialog, so it says why it is empty. `empty` is the wording.
    local function fill(b, rec, empty)
        b:Show()
        if not rec then
            b.rec, b.itemID, b.link = nil, nil, nil     -- no tooltip, and OnClick finds no record
            b.icon:SetTexture(nil)          -- nothing painted inside: the frame shows through
            -- The reason goes on the NAME line, where an item's name would be. On
            -- the price line it reads as if the item cost "no junk".
            b.name:SetText(GREY .. empty .. "|r")
            b.price:SetText("")
            b.ah:SetText("")
            b.tag:SetText("")
            b.SetBorder(0.3, 0.3, 0.3)      -- same neutral border as a filled slot
            return
        end
        local n, _, _, _, _, _, _, _, _, tex = GetItemInfo(rec.id)
        b.rec = rec; b.itemID = rec.id; b.link = nil
        b.icon:SetTexture(tex)
        b.name:SetText(n or ("item " .. rec.id))
        -- Total first, stack size after it ("3c (x3)"): the recommendation compares
        -- total stack value, so the total has to be the number you actually see.
        -- Both rows are stack totals, so vendor and AH are directly comparable.
        -- The count is shown even at x1. Hiding it there made the line jump
        -- between "5c" and "36c (x9)" as you paged, and you could not tell at a
        -- glance whether a price was for one item or for a stack.
        local cnt = rec.count or 1
        b.price:SetText("|cffffffff" .. Coin((rec.each or 0) * cnt) .. "|r" ..
            " " .. GREY .. "(x" .. cnt .. ")|r")
        local ahEach = AHPrice(rec.id)
        b.ah:SetText((ahEach and ahEach > 0) and (GREY .. "AH:|r " .. Coin(ahEach * cnt)) or "")
        b.tag:SetText("")
        b.SetBorder(0.3, 0.3, 0.3)
    end

    -- Arrows are hidden outright when there is nothing to page through, and
    -- disabled (greyed by the template's disabled texture) at each end.
    local function pager(b, which)
        local n, i = #listFor(which), idxFor(which)
        b.prev:SetShown(n > 1); b.next:SetShown(n > 1)
        b.prev:SetEnabled(i > 1)
        b.next:SetEnabled(i < n)
        b.cap:SetText(b.capBase .. ((n > 1) and (" " .. GREY .. i .. "/" .. n .. "|r") or ""))
    end

    f.RenderCandidates = function()
        local jl, ol = listFor("junk"), listFor("other")
        fill(f.junkBtn,  jl[idxFor("junk")],  "no junk")
        fill(f.otherBtn, ol[idxFor("other")], "no other item")
        pager(f.junkBtn, "junk"); pager(f.otherBtn, "other")
        -- the paging hint is noise when there is nothing to page through
        if not f.preview then
            f.banner:SetText((#jl > 1 or #ol > 1)
                and (GREY .. "Arrows or mouse wheel over an icon: pick a different item|r") or "")
        end

        -- The recommendation still means "the cheapest thing you could destroy",
        -- so it is anchored to the head of each list, never to whatever you have
        -- paged to. Page away from it and the tag simply goes - you made a
        -- deliberate choice, the dialog should not keep calling it recommended.
        local rj = jl[1] and jl[1].value or math.huge
        local ro = ol[1] and ol[1].value or math.huge
        local best = (rj <= ro) and f.junkBtn or f.otherBtn
        for _, b in ipairs({ f.junkBtn, f.otherBtn }) do
            local rec = b.rec
            if rec then
                if f.lworth and rec.value >= f.lworth then
                    -- paged up past the point where the trade pays off
                    b.SetBorder(0.85, 0.15, 0.15)
                    b.tag:SetText(RED .. "costs more than the loot|r")
                elseif b == best and rec == ((b == f.junkBtn) and jl[1] or ol[1]) then
                    b.SetBorder(0.1, 0.85, 0.2)
                    b.tag:SetText(GREEN .. "recommended|r")
                end
            end
        end

        -- Verdict on the loot item: same rule as the loot tooltip, so the two can
        -- never disagree - the looted item's worth against the TOTAL value of the
        -- CHEAPEST stack you would have to destroy. Paging does not move it, or
        -- the dialog and the tooltip would start contradicting each other.
        local lo = math.min(rj, ro)
        if f.lid and IsQuestItem(f.lid) then
            f.lootBtn.SetBorder(0.1, 0.85, 0.2)
            f.lootBtn.tag:SetText(GREEN .. "quest - take it|r")
        elseif f.lworth and lo < math.huge then
            if f.lworth > lo then
                f.lootBtn.SetBorder(0.1, 0.85, 0.2)
                f.lootBtn.tag:SetText(GREEN .. "worth it|r")
            else
                f.lootBtn.SetBorder(0.85, 0.15, 0.15)
                f.lootBtn.tag:SetText(RED .. "not worth it|r")
            end
        else
            f.lootBtn.SetBorder(0.3, 0.3, 0.3)
            f.lootBtn.tag:SetText("")
        end
    end

    f.Step = function(which, dir)
        local i = idxFor(which) + dir
        if i < 1 or i > #listFor(which) then return end      -- hard stops, no wrap-around
        if which == "junk" then f.junkIdx = i else f.otherIdx = i end
        f.RenderCandidates()
    end

    -- Bags changed under an open dialog: rebuild both lists so the records cannot
    -- go stale, keeping your position where it still exists.
    f.SyncLists = function()
        if f.preview then return end                          -- a preview is a deliberate snapshot
        local _, _, jl, ol = LootClearCandidates()
        f.junkList, f.otherList = jl or {}, ol or {}
        f.junkIdx  = math.max(1, math.min(f.junkIdx  or 1, #f.junkList))
        f.otherIdx = math.max(1, math.min(f.otherIdx or 1, #f.otherList))
        f.RenderCandidates()
    end

    -- Disarming on OnHide (rather than at the end of the preview call) means the
    -- flag is tied to the dialog's lifetime: Escape, the X, Cancel and
    -- CloseLootConfirm all clear it.
    f:SetScript("OnHide", function(self)
        self.preview = nil
        previewMode = false
        if PreviewBtnSync then PreviewBtnSync() end   -- closing it flips the Debug tab button back
    end)

    f:Hide()
    confirmFrame = f
    return f
end

-- `preview` is the ONLY thing a preview passes differently: everything below
-- (prices, ranking, recommendation, verdict) runs exactly as it does in a real
-- full-bags situation, so the preview keeps testing the live implementation.
local function ShowLootConfirm(lootLink, junkRec, otherRec, slot, preview, junkList, otherList)
    local f = confirmFrame or BuildConfirm()
    f.slot = slot
    f.preview = preview and true or false
    previewMode = f.preview
    -- One height for both modes: the bottom line now carries either the preview
    -- warning or the paging hint, so the frame no longer changes size.
    f:SetHeight(250)
    if f.preview then
        f.head:SetText(GOLD .. "DEBUG PREVIEW|r - real items, real ranking:")
        f.banner:SetText(RED .. "Preview Mode: All actions are only for testing, nothing will be deleted or ignored.|r")
    else
        f.head:SetText("Bags full - click a junk/item to delete and loot:")
        f.banner:SetText(GREY .. "Arrows or mouse wheel over an icon: pick a different item|r")
    end
    f.banner:Show()

    local lname, _, _, _, _, _, _, _, _, ltex = GetItemInfo(lootLink)
    f.lootBtn.link = lootLink; f.lootBtn.itemID = nil
    f.lootBtn.icon:SetTexture(ltex)
    f.lootBtn.name:SetText(lname or "?")
    local lid = tonumber((lootLink or ""):match("item:(%d+)"))
    -- NB: `lid and Worth(lid, 1)` would truncate the multiple returns to one,
    -- so the worth has to be pulled inside the branch.
    local lworth, lvendor
    if lid then
        local _, vend, each = Worth(lid, 1)
        lworth, lvendor = each, vend
        if not lworth then                                   -- item info not cached yet
            lworth = select(11, GetItemInfo(lootLink)) or 0   -- 11 = sellPrice
            lvendor = lworth
        end
    end
    -- Vendor on top, AH underneath when Auctionator has a price. The verdict below
    -- still uses lworth (whichever basis the setting ranks on), so what decides and
    -- what is displayed stay independent.
    f.lootBtn.price:SetText(lvendor and ("|cffffffff" .. Coin(lvendor) .. "|r") or "")
    local lah = lid and AHPrice(lid)
    f.lootBtn.ah:SetText((lah and lah > 0) and (GREY .. "AH:|r " .. Coin(lah)) or "")

    -- Callers that have the ranked lists pass them; the single records stay the
    -- fallback, so a one-item list behaves exactly as before (arrows hidden).
    f.lid, f.lworth = lid, lworth
    f.junkList  = junkList  or (junkRec  and { junkRec })  or {}
    f.otherList = otherList or (otherRec and { otherRec }) or {}
    f.junkIdx, f.otherIdx = 1, 1        -- every dialog opens on the cheapest
    f.RenderCandidates()
    f:Show()
end

------------------------------------------------ dialog preview (debug)
-- Opens the real comparison dialog with real items out of the player's bags, so
-- the layout, the prices, the recommendation and the verdict are all produced by
-- the live code. Nothing here mocks a record: the two replace candidates come
-- from LootClearCandidates() (the same call the loot assist makes) and every
-- price goes through Worth().
local function PreviewRecords()
    local list = {}
    for bag = BACKPACK_CONTAINER, NUM_BAG_FRAMES do
        for slot = 1, (GetContainerNumSlots(bag) or 0) do
            local id = GetContainerItemID(bag, slot)
            if id and not exclusions[id] and not IsQuestItem(id) then
                local count = SlotCount(bag, slot)
                local value, each, worthEach = Worth(id, count)
                if value then
                    list[#list + 1] = { bag = bag, slot = slot, id = id, count = count,
                                        value = value, each = each, worthEach = worthEach,
                                        junk = IsJunk(id) }
                end
            end
        end
    end
    return list
end

local function PreviewLootConfirm()
    -- the real candidate scan first - that is what we actually want to look at
    local junkRec, otherRec, junkList, otherList = LootClearCandidates()
    local all = PreviewRecords()
    if #all == 0 then
        print(GOLD .. "DGs Junk|r preview: no usable items in your bags.")
        return
    end
    -- No substitutes for missing candidates: an empty slot now renders as
    -- "no junk" / "no other item", which IS what the live dialog does, so the
    -- preview shows it rather than inventing a record to fill the gap.
    if not junkRec then dbg("preview: no junk candidate - the slot renders empty") end
    if not otherRec then dbg("preview: no non-junk candidate - the slot renders empty") end

    local lo = math.min(junkRec and junkRec.value or math.huge,
                        otherRec and otherRec.value or math.huge)
    -- Prefer an item that is worth MORE than either candidate, so the dialog
    -- shows its "worth it" verdict; if the bags hold nothing that beats them,
    -- any item will do (the red "not worth it" verdict is just as valid a thing
    -- to look at).
    -- LootClearCandidates() builds its own record tables, so identity comparison
    -- would never match - the same bag slot has to be excluded by bag/slot.
    local function same(c, r) return c and c.bag == r.bag and c.slot == r.slot end
    local function isCandidate(r) return same(junkRec, r) or same(otherRec, r) end
    local better, rest = {}, {}
    for _, r in ipairs(all) do
        if not isCandidate(r) then
            rest[#rest + 1] = r
            if (r.worthEach or 0) > lo then better[#better + 1] = r end
        end
    end
    local pool = better
    if #pool == 0 then
        pool = (#rest > 0) and rest or all
        dbg("preview: nothing in bags beats the candidates, showing a plain item")
    end
    local pick = pool[math.random(#pool)]

    local link = select(2, GetItemInfo(pick.id))
    dbg("preview: loot=" .. tostring(pick.id), "junk=" .. (junkRec and junkRec.id or "-"),
        "other=" .. (otherRec and otherRec.id or "-"))
    ShowLootConfirm(link or ("item:" .. pick.id), junkRec, otherRec, nil, true, junkList, otherList)
end

-- Is a PREVIEW dialog currently up? A real full-bags dialog does not count - the
-- Debug button must never offer to close a live one.
local function PreviewShown()
    return (confirmFrame and confirmFrame:IsShown() and confirmFrame.preview) and true or false
end

local function PreviewToggle()
    if PreviewShown() then
        confirmFrame:Hide()          -- OnHide disarms the flag and syncs the button
    else
        PreviewLootConfirm()
        if PreviewBtnSync then PreviewBtnSync() end
    end
end

local hookedButtons = {}
local function LootAssistClick(self)
    if DB and DB.lootAssist == false then return end
    if not IsShiftKeyDown() then return end
    local slot = self.slot or (self.GetID and self:GetID())
    if not slot then return end
    if not (LootSlotHasItem and LootSlotHasItem(slot)) then return end
    if not BagsFull() then return end
    -- stacks into a partial stack you already carry -> no slot needed, no dialog
    local lid = GetLootSlotLink and linkID(GetLootSlotLink(slot))
    if lid and StackRoom(lid) >= ((GetLootSlotInfo and select(3, GetLootSlotInfo(slot))) or 1) then
        dbg("loot-assist: item stacks into existing stack, no clear needed")
        return
    end
    local junkRec, otherRec, junkList, otherList = LootClearCandidates()
    if not junkRec and not otherRec then dbg("loot-assist: bags full, nothing deletable to clear"); return end
    local lootLink = (GetLootSlotLink and GetLootSlotLink(slot)) or "this item"
    dbg("loot-assist: junk=" .. (junkRec and junkRec.id or "-"), "other=" .. (otherRec and otherRec.id or "-"), "slot", slot)
    -- the pick-an-item dialog IS the confirm (choose which to delete, or Cancel)
    ShowLootConfirm(lootLink, junkRec, otherRec, slot, nil, junkList, otherList)
end
local function HookLootButtons()
    local n = (GetNumLootItems and GetNumLootItems()) or 0
    for i = 1, math.max(n, 4) do
        local btn = _G["LootButton" .. i]
        if btn and not hookedButtons[btn] then
            hookedButtons[btn] = true
            btn:HookScript("OnClick", LootAssistClick)
            dbg("hooked LootButton" .. i)
        end
    end
    if n > 0 and not _G["LootButton1"] then
        dbg("loot-assist: LootButtonN not found (loot frame changed?)")
    end
end

------------------------------------------------ loot row tinting
-- Same verdict as the tooltip, but painted straight onto Blizzard's loot rows so
-- it is readable without hovering: a coloured border around the icon - green = worth more than the cheapest stack you
-- would have to destroy, red = not worth a bag slot, no tint = no price data.
-- Own texture per row (never recolour Blizzard's own art or the quality-coloured
-- item name, which would destroy the quality information).
-- Four thin edges rather than a border art file: works at any button size and
-- stays crisp, and it sits outside the icon so nothing of the item art is hidden.
local BORDER = 2       -- edge thickness
local OUT    = 2       -- how far outside the icon the frame sits
local function RowTint(btn)
    if not btn.dgsjTint then
        local edges = {}
        for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
            local t = btn:CreateTexture(nil, "OVERLAY")
            if side == "TOP" or side == "BOTTOM" then
                t:SetPoint("LEFT",  btn, "LEFT",  -OUT, 0)
                t:SetPoint("RIGHT", btn, "RIGHT",  OUT, 0)
                t:SetHeight(BORDER)
                t:SetPoint(side, btn, side, 0, side == "TOP" and OUT or -OUT)
            else
                t:SetPoint("TOP",    btn, "TOP",     0,  OUT)
                t:SetPoint("BOTTOM", btn, "BOTTOM",  0, -OUT)
                t:SetWidth(BORDER)
                t:SetPoint(side, btn, side, side == "LEFT" and -OUT or OUT, 0)
            end
            edges[#edges + 1] = t
        end
        btn.dgsjTint = {
            SetColorTexture = function(_, r, g, b, a)
                for _, t in ipairs(edges) do t:SetColorTexture(r, g, b, a) end
            end,
            Show = function() for _, t in ipairs(edges) do t:Show() end end,
            Hide = function() for _, t in ipairs(edges) do t:Hide() end end,
        }
    end
    return btn.dgsjTint
end

local function ColorLootRows()
    if not (LootFrame and LootFrame:IsShown()) then return end
    local n = (GetNumLootItems and GetNumLootItems()) or 0
    -- With a free bag slot there is no trade-off - everything is simply lootable,
    -- so a red "skip" border would be a lie. Only judge when looting would
    -- actually cost you an item.
    local junk, other
    if BagsFull() then junk, other = LootClearCandidates() end
    local lo = math.min(junk and junk.value or math.huge, other and other.value or math.huge)
    for i = 1, math.max(n, 4) do
        local btn = _G["LootButton" .. i]
        if btn then
            local tint = RowTint(btn)
            tint:Hide()
            -- slot index is the button's ID, which already accounts for paging
            local slot = (btn.slot) or (btn.GetID and btn:GetID())
            if DB and DB.lootColor ~= false and lo < math.huge and btn:IsShown() and slot
               and LootSlotHasItem and LootSlotHasItem(slot) then
                local id = GetLootSlotLink and linkID(GetLootSlotLink(slot))
                local qty = (GetLootSlotInfo and select(3, GetLootSlotInfo(slot))) or 1
                if id and StackRoom(id) >= qty then
                    -- stacks onto what you already carry: costs no slot, no verdict
                    id = nil
                end
                if id and IsQuestItem(id) then
                    tint:SetColorTexture(0.15, 0.95, 0.25, 1); tint:Show()
                elseif id then
                    local _, _, worthEach = Worth(id, 1)
                    if worthEach then
                        if worthEach > lo then tint:SetColorTexture(0.15, 0.95, 0.25, 1)
                        else                   tint:SetColorTexture(1.00, 0.20, 0.15, 1) end
                        tint:Show()
                    end
                end
            end
        end
    end
    dbg("loot rows tinted, cheapest to discard =",
        lo < math.huge and lo or "none (bags not full / nothing deletable)")
end

local function ColorLootRowsSoon()
    if C_Timer then C_Timer.After(0, ColorLootRows) else ColorLootRows() end
end

local lootUpdateHooked
local function HookLootUpdate()
    if lootUpdateHooked then return end
    lootUpdateHooked = true
    -- paging / slots being taken rebuild the rows, so re-tint after Blizzard's update
    if type(_G.LootFrame_Update) == "function" then
        hooksecurefunc("LootFrame_Update", ColorLootRowsSoon)
    elseif LootFrame and LootFrame.Update then
        hooksecurefunc(LootFrame, "Update", ColorLootRowsSoon)
    else
        dbg("loot tint: no LootFrame update hook found")
    end
end

------------------------------------------------------------------ profiles
-- Each character uses either the shared profile (stored as "Main", shown in the
-- UI as "Default") or its own
-- (character-named) profile. Only the ignore list + junk marks are scoped;
-- settings are account-wide. DB.ignore / DB.marks are rebound to the active
-- profile's tables, so the rest of the addon keeps using them unchanged.
local function CharKey()
    return (UnitName("player") or "?") .. " - " .. (GetRealmName() or "?")
end

local function ActiveProfileName()
    local k = CharKey()
    local name = DB and DB.chars and DB.chars[k]
    if not name or not (DB.profiles and DB.profiles[name]) then name = "Main" end
    return name, k
end

-- Exactly two profiles are reachable: the shared one (stored as "Main", shown as
-- "Default") and this character's own. The own profile is created on login so it
-- always exists and the picker can always offer both.
local function EnsureOwnProfile()
    if not (DB and DB.profiles) then return end
    local k = CharKey()
    DB.profiles[k] = DB.profiles[k] or { ignore = {}, marks = {} }
    return k
end

local function BindProfile()
    if not DB then return end
    EnsureOwnProfile()
    local name = ActiveProfileName()
    local p = DB.profiles[name] or DB.profiles.Main
    p.ignore = p.ignore or {}
    p.marks  = p.marks  or {}
    DB.ignore = p.ignore
    DB.marks  = p.marks
end

local function AfterProfileSwitch()
    BindProfile()
    if RefreshConfig then RefreshConfig() end
    if RefreshJunkList then RefreshJunkList() end
    if Update then Update() end
end

-- Overwrite dst's ignore + marks with a copy of src's (never swaps the tables:
-- DB.ignore / DB.marks may still be pointing at them).
local function CopyLists(src, dst)
    wipe(dst.ignore); wipe(dst.marks)
    for id, v in pairs(src.ignore) do dst.ignore[id] = v end
    for id, v in pairs(src.marks)  do dst.marks[id]  = v end
end

-- Default -> this character. Only offered while the own profile is active.
local function ProfileCopyFromMain()
    local k = EnsureOwnProfile()
    CopyLists(DB.profiles.Main, DB.profiles[k])
    act("profile copy", nil, "Default -> " .. k)
    AfterProfileSwitch()
    print(GOLD .. "DGs Junk|r copied |cffffffffDefault|r into this character's profile.")
end

-- This character -> Default. Stays on the character profile afterwards.
local function ProfileCopyToMain()
    local k = EnsureOwnProfile()
    CopyLists(DB.profiles[k], DB.profiles.Main)
    act("profile copy", nil, k .. " -> Default")
    AfterProfileSwitch()
    print(GOLD .. "DGs Junk|r copied this character's profile into |cffffffffDefault|r.")
end

-- Bind this character to a profile by name ("Main" or its own key).
local function ProfileSwitchTo(name)
    local k = EnsureOwnProfile()
    DB.chars[k] = (name == "Main") and "Main" or k
    act("profile switch", nil, "now on " .. DB.chars[k])
    AfterProfileSwitch()
    print(GOLD .. "DGs Junk|r now using the " ..
        (name == "Main" and "|cffffffffDefault|r" or "|cffffffff" .. (UnitName("player") or k) .. "|r") .. " profile.")
end

StaticPopupDialogs["DGSJUNK_PROFILE_ACTION"] = {
    text = "|cffffcc55DGs Junk|r\n\nThis will %s.\n\nContinue?",
    button1 = YES,
    button2 = NO,
    OnAccept = function(self) if type(self.data) == "function" then self.data() end end,
    timeout = 0, whileDead = true, hideOnEscape = true, showAlert = true, preferredIndex = 3,
}

-------------------------------------------------------------------- events
local ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:RegisterEvent("BAG_UPDATE_DELAYED")
ev:RegisterEvent("MERCHANT_CLOSED")
ev:RegisterEvent("MERCHANT_SHOW")
ev:RegisterEvent("LOOT_OPENED")
ev:RegisterEvent("LOOT_SLOT_CLEARED")
ev:RegisterEvent("LOOT_CLOSED")
ev:SetScript("OnEvent", function(_, event, arg1)
    if event == "LOOT_OPENED" then
        HookLootButtons()
        HookLootUpdate()
        ColorLootRowsSoon()           -- after Blizzard has laid the rows out
        return
    end
    if event == "LOOT_SLOT_CLEARED" then
        ColorLootRowsSoon()           -- a slot went away; rows shift
        return
    end
    if event == "LOOT_CLOSED" then
        CloseLootConfirm()            -- the loot slot is gone; the dialog would lie
        return
    end
    if event == "MERCHANT_SHOW" then
        if C_Timer then C_Timer.After(0.5, AutoSellMarked) else AutoSellMarked() end   -- let gray-sellers go first
        return
    end
    if event == "BAG_UPDATE_DELAYED" and LootFrame and LootFrame:IsShown() then
        ColorLootRowsSoon()           -- bags just filled up / freed up: re-judge
    end
    if event == "BAG_UPDATE_DELAYED" and confirmFrame and confirmFrame:IsShown() then
        if confirmFrame.SyncLists then confirmFrame.SyncLists() end   -- keep candidates off stale bag slots
    end
    if event == "PLAYER_LOGIN" then
        BindProfile()                 -- now that the character name is known
        return
    end
    if event == "PLAYER_ENTERING_WORLD" then
        HookBagButtons()
    end
    if event == "ADDON_LOADED" then
        -- Auctionator may load after us (or on demand): re-evaluate the AH
        -- checkbox and re-rank with real AH prices.
        if arg1 == "Auctionator" then
            if RefreshConfig then RefreshConfig() end
            if Update then Update() end
            return
        end
        if arg1 ~= "DGsJunk" then return end
        DGsJunkDB = DGsJunkDB or {}
        DB = DGsJunkDB
        DB.log = DB.log or {}
        -- Profiles scope only the DATA (ignore list + junk marks). Settings stay
        -- flat on DB and are therefore account-wide ("Main Settings"), shared by
        -- every character regardless of which data profile it uses.
        DB.profiles = DB.profiles or {}
        DB.profiles.Main = DB.profiles.Main or {}
        DB.profiles.Main.ignore = DB.profiles.Main.ignore or {}
        DB.profiles.Main.marks  = DB.profiles.Main.marks  or {}
        DB.chars = DB.chars or {}                                -- charKey -> profile name
        -- migrate legacy account-wide lists into the Main profile (one-time)
        if DB.ignore then for k, v in pairs(DB.ignore) do DB.profiles.Main.ignore[k] = v end; DB.ignore = nil end
        if DB.marks  then for k, v in pairs(DB.marks)  do DB.profiles.Main.marks[k]  = v end; DB.marks  = nil end
        -- safe default bind; the real per-character bind happens on PLAYER_LOGIN
        DB.ignore = DB.profiles.Main.ignore
        DB.marks  = DB.profiles.Main.marks
        if DB.alwaysShow == nil then DB.alwaysShow = true end   -- default ON
        if DB.autoSell == nil then DB.autoSell = false end       -- vendor auto-sell of marked items (opt-in)
        DB.scale = DB.scale or 1
        if DB.minimap == nil then DB.minimap = true end          -- minimap button on by default
        if DB.showFrames == nil then DB.showFrames = true end    -- master frame visibility
        DB.minimapAngle = DB.minimapAngle or 200
        ApplyScale()
        ApplyMinimap()
        junkIcon:ClearAllPoints()
        if DB.pos then
            junkIcon:SetPoint(DB.pos[1], UIParent, DB.pos[2], DB.pos[3], DB.pos[4])
        else
            junkIcon:SetPoint("CENTER", 0, -140)
        end
        return
    end
    if C_Timer then C_Timer.After(0.1, Update) else Update() end
end)

-------------------------------------------------------------- settings menu
local function ItemName(id)
    local name, link, quality = GetItemInfo(id)
    if not name then return "|cff999999Item #" .. id .. "|r", nil end
    local hex = (ITEM_QUALITY_COLORS[quality or 0] or {}).hex or "|cffffffff"
    return hex .. name .. "|r", select(10, GetItemInfo(id))
end

local function ResetIgnores(category)
    if not (DB and DB.ignore) then return end
    local n = 0
    if not category then
        for _ in pairs(DB.ignore) do n = n + 1 end
        wipe(DB.ignore)
    else
        for id, cat in pairs(DB.ignore) do
            if cat == category then DB.ignore[id] = nil; n = n + 1 end
        end
    end
    act("reset ignores", nil, (category or "all") .. ": " .. n .. " removed")
    RefreshConfig()
    Update()
end

-- Reset buttons are destructive -> always confirm first.
StaticPopupDialogs["DGSJUNK_CONFIRM_RESET"] = {
    text = "|cffffcc55DGs Junk|r\n\n%s\n\nThis cannot be undone.",
    button1 = YES,
    button2 = NO,
    OnAccept = function(self)
        local cat = self.data
        ResetIgnores(cat ~= "all" and cat or nil)
    end,
    timeout = 0, whileDead = true, hideOnEscape = true, showAlert = true, preferredIndex = 3,
}

local function CountIgnores(category)
    local n = 0
    if DB and DB.ignore then
        for _, cat in pairs(DB.ignore) do
            if not category or cat == category then n = n + 1 end
        end
    end
    return n
end

local function ConfirmReset(category, label)
    local n = CountIgnores(category ~= "all" and category or nil)
    if n == 0 then
        print(GOLD .. "DGs Junk|r nothing to reset for " .. label)
        return
    end
    StaticPopup_Show("DGSJUNK_CONFIRM_RESET",
        "Remove " .. n .. " item" .. (n == 1 and "" or "s") .. " from " .. label .. "?",
        nil, category)
end

-- ---- Junk-clear tab: items YOU marked as junk that are sitting in your bags,
-- aggregated by item id so you can delete them (always behind a confirm). ----
local function MarkedJunkList()
    local byId = {}
    for bag = BACKPACK_CONTAINER, NUM_BAG_FRAMES do
        for slot = 1, (GetContainerNumSlots(bag) or 0) do
            local id = GetContainerItemID(bag, slot)
            if id and not exclusions[id] and DB and DB.marks and DB.marks[id] == true then
                local e = byId[id]
                if not e then e = { id = id, count = 0, slots = {} }; byId[id] = e end
                e.count = e.count + SlotCount(bag, slot)
                e.slots[#e.slots + 1] = { bag = bag, slot = slot }
            end
        end
    end
    local list = {}
    for _, e in pairs(byId) do
        local total, _, each = Worth(e.id, e.count)
        e.worthEach, e.totalValue = each or 0, total or 0
        list[#list + 1] = e
    end
    table.sort(list, function(a, b) return a.totalValue < b.totalValue end)
    return list
end

-- The Junk tab only edits the mark list; it never touches the bags.
StaticPopupDialogs["DGSJUNK_CONFIRM_UNMARK"] = {
    text = "|cffffcc55DGs Junk|r\n\nUnmark %s as junk?",
    button1 = YES,
    button2 = NO,
    OnAccept = function(self) if type(self.data) == "function" then self.data() end end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

StaticPopupDialogs["DGSJUNK_CONFIRM_UNMARK_ALL"] = {
    text = "|cffffcc55DGs Junk|r\n\n%s\n\nYour items are not touched, only the marks.",
    button1 = YES,
    button2 = NO,
    OnAccept = function(self) if type(self.data) == "function" then self.data() end end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

-- Drop every "force junk" mark. DB.marks[id] == false ("force keep") is a
-- different decision and is deliberately left alone.
local function ClearAllMarks()
    if not (DB and DB.marks) then return end
    local n = 0
    for id, v in pairs(DB.marks) do
        if v == true then DB.marks[id] = nil; n = n + 1 end
    end
    act("clear all junk", nil, n .. " unmarked")
    if RefreshJunkList then RefreshJunkList() end
    Update()
    print(GREEN .. "DGs Junk|r unmarked " .. n .. " item" .. (n == 1 and "" or "s"))
end

local function CountMarks()
    local n = 0
    if DB and DB.marks then
        for _, v in pairs(DB.marks) do if v == true then n = n + 1 end end
    end
    return n
end

local function ConfirmClearAll()
    local n = CountMarks()
    if n == 0 then print(GOLD .. "DGs Junk|r nothing marked as junk"); return end
    StaticPopup_Show("DGSJUNK_CONFIRM_UNMARK_ALL",
        "Unmark all " .. n .. " item" .. (n == 1 and "" or "s") .. " marked as junk?",
        nil, ClearAllMarks)
end

StaticPopupDialogs["DGSJUNK_CONFIRM_UNIGNORE"] = {
    text = "|cffffcc55DGs Junk|r\n\nRemove %s from the ignore list?",
    button1 = YES,
    button2 = NO,
    OnAccept = function(self) if type(self.data) == "function" then self.data() end end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

-- Attach a plain hover tooltip to a button (used to advertise the shift-skip).
local function BtnHint(frame, title, sub)
    frame:SetScript("OnEnter", function(self)
        if dragging then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(title, 1, 1, 1)
        if sub then GameTooltip:AddLine(sub, 0.6, 0.6, 0.6, true) end
        GameTooltip:Show()
    end)
    frame:SetScript("OnLeave", GameTooltip_Hide)
end

-- Show the item's own tooltip on hover (for the little X buttons in the lists).
local function ItemHint(frame, id, action)
    frame:SetScript("OnEnter", function(self)
        if dragging then return end
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        local link = select(2, GetItemInfo(id))
        if link then GameTooltip:SetHyperlink(link)
        else GameTooltip:SetText(select(1, ItemName(id)) or ("item " .. id)) end
        GameTooltip:AddLine(GREY .. action .. " |cff888888(shift-click: no confirm)|r", 0.6, 0.6, 0.6, true)
        GameTooltip:Show()
    end)
    frame:SetScript("OnLeave", GameTooltip_Hide)
end

local function ConfigBtn(parent, text, w, onClick)
    local btn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    btn:SetSize(w or 90, 22)
    btn:SetText(text)
    btn:SetScript("OnClick", onClick)
    return btn
end

local RefreshLog  -- fwd

BuildConfig = function()
    config = CreateFrame("Frame", "DGsJunkConfig", UIParent, "BasicFrameTemplateWithInset")
    config:SetSize(480, 740)     -- room for the extra Settings row (loot-row colouring)
    config:SetPoint("CENTER")
    config:SetMovable(true)
    config:EnableMouse(true)
    config:RegisterForDrag("LeftButton")
    config:SetScript("OnDragStart", function(self) BeginDrag(); self:StartMoving() end)
    config:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); EndDrag() end)
    config:SetFrameStrata("HIGH")
    local title = config.TitleText or _G["DGsJunkConfigTitleText"]
    if title then title:SetText("DGs Junk") end
    tinsert(UISpecialFrames, "DGsJunkConfig")   -- closable with Escape
    -- The template's X routes through HideUIPanel, which is blocked in combat.
    -- Hide directly so it works mid-fight.
    local closeBtn = config.CloseButton or _G["DGsJunkConfigCloseButton"]
    if closeBtn then closeBtn:SetScript("OnClick", function() config:Hide() end) end
    -- A preview belongs to the Debug tab: closing the settings window takes it
    -- with it, and its OnHide resets the toggle back to "Show". A real full-bags
    -- dialog is untouched - it has nothing to do with this window.
    config:SetScript("OnHide", function()
        if confirmFrame and confirmFrame:IsShown() and confirmFrame.preview then confirmFrame:Hide() end
    end)

    -- panels
    local function Panel()
        local p = CreateFrame("Frame", nil, config)
        p:SetPoint("TOPLEFT", 8, -78)
        p:SetPoint("BOTTOMRIGHT", -8, 12)
        p:Hide()
        return p
    end
    config.panels = { ignored = Panel(), junk = Panel(), settings = Panel(), debug = Panel(), log = Panel() }

    local function ShowTab(name)
        for k, p in pairs(config.panels) do p:SetShown(k == name) end
        for k, b in pairs(config.tabBtns) do
            local active = (k == name)
            b:SetEnabled(not active)         -- active tab is not clickable
            -- Disabled alone just greys the button, which reads as "unavailable"
            -- rather than "selected", so mark the active one: gold wash, gold
            -- underline, white label. Colour is re-applied every call because the
            -- template resets the font string on enable/disable.
            b.sel:SetShown(active)
            b.selBar:SetShown(active)
            if active then
                b:GetFontString():SetTextColor(1, 1, 1)
            else
                b:GetFontString():SetTextColor(1, 0.82, 0)
            end
        end
        if name == "log" then
            if config.checks and config.checks.debug then config.checks.debug.Refresh() end
            if config.ApplyLogVis then config.ApplyLogVis() end
        end
        if name == "debug" and PreviewBtnSync then PreviewBtnSync() end
        if name == "ignored" then RefreshConfig() end
        if name == "junk" and RefreshJunkList then RefreshJunkList() end
    end
    config.ShowTab = ShowTab

    -- always-visible profile status line (above the tabs, all tabs)
    local ptop = config:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    ptop:SetPoint("TOPLEFT", 12, -30)
    ptop:SetPoint("RIGHT", config, "RIGHT", -12, 0)
    ptop:SetJustifyH("LEFT")
    config.profileTop = ptop

    -- tab buttons
    config.tabBtns = {}
    local order = { { "settings", "Settings" }, { "ignored", "Ignored" }, { "junk", "Junk" },
                    { "debug", "Debug" }, { "log", "Log" } }
    -- Derive the tab width from the count so adding a tab never overflows the
    -- 480px frame (8px margin each side, 4px gutters).
    local tabW = math.floor((480 - 16 - (#order - 1) * 4) / #order)
    for i, t in ipairs(order) do
        local b = ConfigBtn(config, t[2], tabW, function() ShowTab(t[1]) end)
        b:SetPoint("TOPLEFT", 8 + (i - 1) * (tabW + 4), -52)
        -- selection art, hidden until ShowTab marks this tab active
        b.sel = b:CreateTexture(nil, "OVERLAY")
        b.sel:SetAllPoints()
        b.sel:SetColorTexture(1, 0.82, 0, 0.16)
        b.sel:Hide()
        b.selBar = b:CreateTexture(nil, "OVERLAY")
        b.selBar:SetPoint("BOTTOMLEFT", 3, 2)
        b.selBar:SetPoint("BOTTOMRIGHT", -3, 2)
        b.selBar:SetHeight(2)
        b.selBar:SetColorTexture(1, 0.82, 0, 0.9)
        b.selBar:Hide()
        config.tabBtns[t[1]] = b
    end

    --====================== IGNORED panel ======================--
    local ip = config.panels.ignored
    local hint = ip:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", 4, -2)
    hint:SetText("Ignored items - add via shift-right-click or right-click > Ignore")

    local scroll = CreateFrame("ScrollFrame", "DGsJunkConfigScroll", ip, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 4, -20)
    scroll:SetPoint("BOTTOMRIGHT", -26, 64)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(290, 1)
    scroll:SetScrollChild(content)
    config.content = content
    config.rows = {}

    local rj = ConfigBtn(ip, "Reset Junk",   100, function()
        if IsShiftKeyDown() then ResetIgnores("junk") else ConfirmReset("junk", "ignored Junk") end
    end)
    rj:SetPoint("BOTTOMLEFT", 4, 4)
    BtnHint(rj, "Reset ignored Junk", "Shift-click to skip the confirm.")
    local rn = ConfigBtn(ip, "Reset Normal", 104, function()
        if IsShiftKeyDown() then ResetIgnores("normal") else ConfirmReset("normal", "ignored Normal") end
    end)
    rn:SetPoint("LEFT", rj, "RIGHT", 4, 0)
    BtnHint(rn, "Reset ignored Normal", "Shift-click to skip the confirm.")
    local ra = ConfigBtn(ip, "Reset All",    100, function()
        if IsShiftKeyDown() then ResetIgnores(nil) else ConfirmReset("all", "the whole ignore list") end
    end)
    ra:SetPoint("LEFT", rn, "RIGHT", 4, 0)
    BtnHint(ra, "Reset the whole ignore list", "Shift-click to skip the confirm.")

    --====================== JUNK panel ======================--
    local jp = config.panels.junk
    local jhint = jp:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    jhint:SetPoint("TOPLEFT", 4, -2)
    jhint:SetText("Items you marked as junk that are in your bags - X unmarks them, nothing is deleted")

    local jscroll = CreateFrame("ScrollFrame", "DGsJunkClearScroll", jp, "UIPanelScrollFrameTemplate")
    jscroll:SetPoint("TOPLEFT", 4, -20)
    jscroll:SetPoint("BOTTOMRIGHT", -26, 36)
    local jcontent = CreateFrame("Frame", nil, jscroll)
    jcontent:SetSize(410, 1)
    jscroll:SetScrollChild(jcontent)
    config.junkContent = jcontent
    config.junkRows = {}

    local jempty = jp:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    jempty:SetPoint("TOPLEFT", 8, -24)
    jempty:SetText(GREY .. "No marked junk in your bags.|r")
    config.junkEmpty = jempty

    local jca = ConfigBtn(jp, "Clear all junk", 130, function()
        if IsShiftKeyDown() then ClearAllMarks() else ConfirmClearAll() end
    end)
    jca:SetPoint("BOTTOMLEFT", 4, 4)
    BtnHint(jca, "Unmark everything you marked as junk", "Shift-click to skip the confirm.")
    config.junkClearAll = jca

    --====================== SETTINGS panel ======================--
    local sp = config.panels.settings
    -- enableFn (optional) is re-evaluated on every Refresh, so a checkbox can go
    -- live when its dependency loads after us. offTip shows while disabled.
    local function Check(label, y, getFn, setFn, tip, enableFn, offTip)
        local cb = CreateFrame("CheckButton", nil, sp, "UICheckButtonTemplate")
        cb:SetPoint("TOPLEFT", 4, y)
        local fs = cb:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        fs:SetPoint("LEFT", cb, "RIGHT", 2, 0)
        fs:SetText(label)
        cb:SetScript("OnClick", function(self)
            local v = self:GetChecked() and true or false
            setFn(v)
            act("setting", nil, label .. " = " .. tostring(v))
        end)
        local d
        if tip then
            d = sp:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
            d:SetPoint("TOPLEFT", cb, "BOTTOMLEFT", 4, 2)
            d:SetPoint("RIGHT", sp, "RIGHT", -8, 0)   -- constrain width so it wraps
            d:SetJustifyH("LEFT")
            d:SetWordWrap(true)
            d:SetText(tip)
        end
        cb.Refresh = function()
            cb:SetChecked(getFn())
            if not enableFn then return end
            if enableFn() then
                cb:Enable()
                fs:SetTextColor(1, 0.82, 0)                    -- GameFontNormal yellow
                if d then d:SetText(tip); d:SetTextColor(0.5, 0.5, 0.5) end
            else
                cb:Disable()
                fs:SetTextColor(0.5, 0.5, 0.5)
                if d then d:SetText(offTip or tip); d:SetTextColor(0.9, 0.35, 0.35) end
            end
        end
        return cb
    end
    config.checks = {}
    config.checks.loot = Check("Loot-assist", -6,
        function() return DB.lootAssist ~= false end,
        function(v) DB.lootAssist = v end,
        "Shift-click a loot item with full bags to clear a junk item and loot it")
    config.checks.lootColor = Check("Colour loot rows", -54,
        function() return DB.lootColor ~= false end,
        function(v) DB.lootColor = v; ColorLootRows() end,
        "Tints the loot window green (worth more than your cheapest junk) or red (skip it)")
    config.checks.ah = Check("Suggest by AH prices", -102,
        function() return DB.ahSuggest end,
        function(v) DB.ahSuggest = v; Update() end,
        "Rank by Auctionator AH value instead of vendor (falls back to vendor)",
        HasAuctionator,
        "Requires Auctionator (not installed / not detected) - ranking uses vendor prices")
    config.checks.show = Check("Show item frames", -152,
        function() return DB.showFrames ~= false end,
        function(v) DB.showFrames = v; Update() end,
        "Master toggle - same as left-clicking the minimap icon")
    config.checks.always = Check("Always show item frames", -196,
        function() return DB.alwaysShow end,
        function(v) DB.alwaysShow = v; Update() end,
        "Keep the icons visible even when there is nothing to delete")
    config.checks.minimap = Check("Show minimap icon", -240,
        function() return DB.minimap ~= false end,
        function(v) DB.minimap = v; ApplyMinimap() end,
        "Minimap button: left-click show/hide frames, right-click settings")
    config.checks.autosell = Check("Auto-sell marked items at vendors", -284,
        function() return DB.autoSell end,
        function(v) DB.autoSell = v end,
        "Sells only items YOU marked as junk and only above gray quality - grays are left to sell-all-junk")
    local rp = ConfigBtn(sp, "Reset icon position", 160, function()
        if DB then DB.pos = nil end
        junkIcon:ClearAllPoints()
        junkIcon:SetPoint("CENTER", 0, -140)
    end)
    rp:SetPoint("TOPLEFT", 8, -340)

    -- frame scale slider (50%..200%)
    local slider = CreateFrame("Slider", "DGsJunkScaleSlider", sp, "OptionsSliderTemplate")
    slider:SetPoint("TOPLEFT", 14, -390)
    slider:SetWidth(200)
    slider:SetMinMaxValues(0.5, 2.0)
    slider:SetValueStep(0.05)
    slider:SetObeyStepOnDrag(true)
    _G[slider:GetName() .. "Low"]:SetText("50%")
    _G[slider:GetName() .. "High"]:SetText("200%")
    local slabel = _G[slider:GetName() .. "Text"]
    slider:SetScript("OnValueChanged", function(self, v)
        v = math.floor(v * 20 + 0.5) / 20                 -- snap to 0.05
        DB.scale = v
        ApplyScale()
        if slabel then slabel:SetText(string.format("Frame scale: %d%%", v * 100)) end
    end)
    slider.Refresh = function()
        slider:SetValue(DB.scale or 1)
        if slabel then slabel:SetText(string.format("Frame scale: %d%%", (DB.scale or 1) * 100)) end
    end
    config.scaleSlider = slider

    -- character data profile (scopes the ignore list + junk marks only)
    local phdr = sp:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    phdr:SetPoint("TOPLEFT", 4, -458)
    phdr:SetText("Character profile")
    local pstat = sp:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    pstat:SetPoint("TOPLEFT", 4, -478)
    pstat:SetPoint("RIGHT", sp, "RIGHT", -8, 0); pstat:SetJustifyH("LEFT")
    config.profileStatus = pstat

    -- Profile picker. 1.15.9 ships Blizzard's new dropdown widget
    -- (DropdownButton + WowStyle1DropdownTemplate + SetupMenu); the old
    -- UIDropDownMenuTemplate is gone. Fall back to a plain button + context menu
    -- if the template is ever missing.
    local function BuildProfileMenu(_, root)
        local k = CharKey()
        local me = UnitName("player") or k
        root:CreateRadio("Default (shared)",
            function() return ActiveProfileName() == "Main" end,
            function() ProfileSwitchTo("Main") end)
        root:CreateRadio(me,
            function() return ActiveProfileName() ~= "Main" end,
            function() ProfileSwitchTo(k) end)
    end

    local bSwitch
    local ok, dd = pcall(CreateFrame, "DropdownButton", nil, sp, "WowStyle1DropdownTemplate")
    if ok and dd and dd.SetupMenu then
        dd:SetSize(190, 24)
        dd:SetupMenu(BuildProfileMenu)
        bSwitch = dd
        config.profileIsDropdown = true
    else
        bSwitch = ConfigBtn(sp, "Profile: Default", 190, function(self)
            if MenuUtil and MenuUtil.CreateContextMenu then
                MenuUtil.CreateContextMenu(self, BuildProfileMenu)
            else
                ProfileSwitchTo(ActiveProfileName() == "Main" and CharKey() or "Main")
            end
        end)
    end
    bSwitch:SetPoint("TOPLEFT", 6, -498)
    BtnHint(bSwitch, "Switch profile", "Default is shared by every character on it; the character profile is private. Both always exist, switching never deletes either.")
    config.profileSwitch = bSwitch

    -- Copy buttons only make sense on the character profile: on Default there is
    -- no second list to copy from or to, so they are hidden entirely.
    local bFrom = ConfigBtn(sp, "Copy from Default", 150, function()
        if IsShiftKeyDown() then ProfileCopyFromMain()
        else StaticPopup_Show("DGSJUNK_PROFILE_ACTION",
            "replace this character's list with a copy of Default", nil, ProfileCopyFromMain) end
    end)
    bFrom:SetPoint("TOPLEFT", 6, -526)
    BtnHint(bFrom, "Pull Default into this character", "Overwrites this character's ignore list + junk marks. Shift-click skips confirm.")
    config.profileCopyFrom = bFrom

    local bTo = ConfigBtn(sp, "Copy to Default", 150, function()
        if IsShiftKeyDown() then ProfileCopyToMain()
        else StaticPopup_Show("DGSJUNK_PROFILE_ACTION",
            "overwrite Default with this character's list", nil, ProfileCopyToMain) end
    end)
    bTo:SetPoint("LEFT", bFrom, "RIGHT", 4, 0)
    BtnHint(bTo, "Push this character into Default", "Overwrites the shared Default list for every character on it. Shift-click skips confirm.")
    config.profileCopyTo = bTo

    local pdesc = sp:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    pdesc:SetPoint("TOPLEFT", 6, -554)
    pdesc:SetPoint("RIGHT", sp, "RIGHT", -8, 0)
    pdesc:SetJustifyH("LEFT"); pdesc:SetWordWrap(true)
    pdesc:SetText("Profiles scope only the ignore list and junk marks; every setting above is shared across your characters. \"Default\" is the shared list, every character on it sees the same entries.")

    config.RefreshProfile = function()
        local name = ActiveProfileName()
        local onDefault = (name == "Main")
        -- Character name only, not the "Name - Realm" storage key: every profile
        -- you can pick here is on this realm, so the suffix is just noise.
        local me = UnitName("player") or name
        local text
        if onDefault then
            text = "This character uses: " .. GREEN .. "Default|r |cff888888(shared list)|r"
        else
            text = "This character uses: " .. GOLD .. me .. "|r |cff888888(own list)|r"
        end
        if config.profileStatus then config.profileStatus:SetText(text) end
        if config.profileTop then config.profileTop:SetText(text) end
        if config.profileSwitch then
            local label = onDefault and "Default (shared)" or me
            if config.profileIsDropdown then
                -- the widget derives its text from the selected radio entry
                config.profileSwitch:SetDefaultText(label)
                if config.profileSwitch.GenerateMenu then config.profileSwitch:GenerateMenu() end
            else
                config.profileSwitch:SetText("Profile: " .. label)
            end
        end
        -- nothing to copy from/to while Default itself is the active list
        if config.profileCopyFrom then config.profileCopyFrom:SetShown(not onDefault) end
        if config.profileCopyTo   then config.profileCopyTo:SetShown(not onDefault) end
    end

    --====================== DEBUG panel ======================--
    -- Testing aids. Every dialog here is opened through its real code path with
    -- real bag items, so what you see is what the game shows - only the actions
    -- are suppressed.
    local dp = config.panels.debug
    local dhint = dp:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    dhint:SetPoint("TOPLEFT", 4, -2)
    dhint:SetPoint("RIGHT", dp, "RIGHT", -8, 0)
    dhint:SetJustifyH("LEFT"); dhint:SetWordWrap(true)
    dhint:SetText("Open the addon's dialogs on demand, without having to fill your bags first. They use your real items and the real ranking; clicking anything in them does nothing - " .. RED .. "nothing is ever deleted|r.")

    local pv = ConfigBtn(dp, "Show comparison dialog", 220, PreviewToggle)
    pv:SetPoint("TOPLEFT", 8, -56)
    BtnHint(pv, "Full-bags comparison dialog",
        "Picks a random bag item worth more than your two cheapest, so the \"worth it\" verdict shows. Also available as /dgjunk preview.")
    config.previewBtn = pv

    -- Single source of truth for the label: the dialog's own visibility. Closing
    -- it any way at all (X, Escape, Cancel) runs its OnHide, which calls this.
    PreviewBtnSync = function()
        if not (config and config.previewBtn) then return end
        config.previewBtn:SetText(PreviewShown() and "Hide comparison dialog" or "Show comparison dialog")
    end
    PreviewBtnSync()

    --====================== LOG panel ======================--
    local lp = config.panels.log

    -- Debug toggle lives here; everything below only shows while it is on.
    local dchk = CreateFrame("CheckButton", nil, lp, "UICheckButtonTemplate")
    dchk:SetPoint("TOPLEFT", 4, -2)
    local dlbl = dchk:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    dlbl:SetPoint("LEFT", dchk, "RIGHT", 2, 0)
    dlbl:SetText("Debug logging")
    local ddesc = lp:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    ddesc:SetPoint("TOPLEFT", dchk, "BOTTOMLEFT", 4, 2)
    ddesc:SetPoint("RIGHT", lp, "RIGHT", -8, 0)
    ddesc:SetJustifyH("LEFT"); ddesc:SetWordWrap(true)
    ddesc:SetText("Record diagnostic messages here (never printed to chat)")
    dchk.Refresh = function() dchk:SetChecked(DB and DB.debug) end
    config.checks.debug = dchk

    local lscroll = CreateFrame("ScrollFrame", "DGsJunkLogScroll", lp, "UIPanelScrollFrameTemplate")
    lscroll:SetPoint("TOPLEFT", 4, -48)
    lscroll:SetPoint("BOTTOMRIGHT", -26, 34)
    local edit = CreateFrame("EditBox", nil, lscroll)
    edit:SetMultiLine(true)
    edit:SetAutoFocus(false)
    edit:SetFontObject(ChatFontNormal)
    edit:SetWidth(300)
    edit:SetScript("OnEscapePressed", function(s) s:ClearFocus() end)
    lscroll:SetScrollChild(edit)
    config.logEdit = edit
    local lclr = ConfigBtn(lp, "Clear", 90, function() DB.log = {}; RefreshLog() end)
    lclr:SetPoint("BOTTOMLEFT", 4, 4)
    local lref = ConfigBtn(lp, "Refresh", 90, function() RefreshLog() end)
    lref:SetPoint("LEFT", lclr, "RIGHT", 4, 0)

    -- only show the log view + buttons while debug logging is enabled
    local function ApplyLogVis()
        local on = DB and DB.debug and true or false
        lscroll:SetShown(on); lclr:SetShown(on); lref:SetShown(on)
        if on then RefreshLog() end
    end
    config.ApplyLogVis = ApplyLogVis
    dchk:SetScript("OnClick", function(self)
        DB.debug = self:GetChecked() and true or false
        ApplyLogVis()
    end)

    for _, cb in pairs(config.checks) do cb.Refresh() end
    config.scaleSlider.Refresh()
    ApplyLogVis()
    ShowTab("settings")
end

RefreshLog = function()
    if not (config and config.logEdit) then return end
    local lines = DB and DB.log or {}
    config.logEdit:SetText(#lines > 0 and table.concat(lines, "\n") or "(log empty - enable Debug logging)")
    config.logEdit:SetCursorPosition(0)
end

RefreshConfig = function()
    if not config then return end
    if config.checks then for _, cb in pairs(config.checks) do cb.Refresh() end end
    if PreviewBtnSync then PreviewBtnSync() end
    if config.scaleSlider then config.scaleSlider.Refresh() end
    if config.RefreshProfile then config.RefreshProfile() end
    if not config.rows then return end
    for _, r in ipairs(config.rows) do r:Hide() end
    if not (DB and DB.ignore) then return end

    -- stable order: junk first, then normal, each by id
    local list = {}
    for id, cat in pairs(DB.ignore) do list[#list + 1] = { id = id, cat = cat } end
    table.sort(list, function(a, b)
        if a.cat ~= b.cat then return a.cat == "junk" end
        return a.id < b.id
    end)

    local y = 0
    for i, entry in ipairs(list) do
        local r = config.rows[i]
        if not r then
            r = CreateFrame("Frame", nil, config.content)
            r:SetSize(288, 20)
            r.icon = r:CreateTexture(nil, "ARTWORK")
            r.icon:SetSize(16, 16); r.icon:SetPoint("LEFT", 2, 0)
            r.tag = r:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
            r.tag:SetPoint("LEFT", 22, 0); r.tag:SetWidth(52); r.tag:SetJustifyH("LEFT")
            r.text = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            r.text:SetPoint("LEFT", 76, 0); r.text:SetWidth(180); r.text:SetJustifyH("LEFT")
            r.x = CreateFrame("Button", nil, r, "UIPanelCloseButton")
            r.x:SetSize(20, 20); r.x:SetPoint("RIGHT", 2, 0)
            config.rows[i] = r
        end
        local name, tex = ItemName(entry.id)
        r.icon:SetTexture(tex or 134400)
        r.tag:SetText(entry.cat == "junk" and GREY .. "Junk|r" or GOLD .. "Normal|r")
        r.text:SetText(name)
        r.x:SetScript("OnClick", function()
            local function doRemove()
                DB.ignore[entry.id] = nil
                act("unignore", entry.id, "removed from ignore list")
                RefreshConfig(); Update()
            end
            if IsShiftKeyDown() then doRemove()
            else StaticPopup_Show("DGSJUNK_CONFIRM_UNIGNORE", (select(1, ItemName(entry.id))), nil, doRemove) end
        end)
        ItemHint(r.x, entry.id, "Remove from ignore list.")
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", 0, -y)
        r:Show()
        y = y + 20
    end
    config.content:SetHeight(math.max(y, 1))
end

RefreshJunkList = function()
    if not (config and config.junkContent) then return end
    for _, r in ipairs(config.junkRows) do r:Hide() end
    local list = MarkedJunkList()
    if config.junkEmpty then config.junkEmpty:SetShown(#list == 0) end
    -- gated on all marks, not just the ones in your bags: "Clear all junk" wipes
    -- the whole mark list, so it must stay usable when nothing is carried
    if config.junkClearAll then config.junkClearAll:SetEnabled(CountMarks() > 0) end

    local y = 0
    for i, entry in ipairs(list) do
        local r = config.junkRows[i]
        if not r then
            r = CreateFrame("Frame", nil, config.junkContent)
            r:SetSize(408, 20)
            r.icon = r:CreateTexture(nil, "ARTWORK")
            r.icon:SetSize(16, 16); r.icon:SetPoint("LEFT", 2, 0)
            r.text = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            r.text:SetPoint("LEFT", 22, 0); r.text:SetWidth(250); r.text:SetJustifyH("LEFT")
            r.price = r:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
            r.price:SetPoint("LEFT", 276, 0); r.price:SetWidth(88); r.price:SetJustifyH("RIGHT")
            r.x = CreateFrame("Button", nil, r, "UIPanelCloseButton")
            r.x:SetSize(20, 20); r.x:SetPoint("RIGHT", 2, 0)
            config.junkRows[i] = r
        end
        local name, tex = ItemName(entry.id)
        r.icon:SetTexture(tex or 134400)
        r.text:SetText(name .. (entry.count > 1 and (GREY .. " x" .. entry.count .. "|r") or ""))
        r.price:SetText("|cffffffff" .. Coin(entry.totalValue or 0) .. "|r")
        -- X unmarks, exactly like the X on the Ignored tab: it edits the list and
        -- never touches your bags. Confirm unless Shift.
        r.x:SetScript("OnClick", function()
            local function doUnmark()
                if DB and DB.marks then DB.marks[entry.id] = nil end
                act("unmark", entry.id, "marks=nil (cleared from Junk tab)")
                RefreshJunkList()
                Update()
            end
            if IsShiftKeyDown() then doUnmark()
            else StaticPopup_Show("DGSJUNK_CONFIRM_UNMARK", (select(1, ItemName(entry.id))), nil, doUnmark) end
        end)
        ItemHint(r.x, entry.id, "Unmark as junk. Shift-click to skip the confirm.")
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", 0, -y)
        r:Show()
        y = y + 20
    end
    config.junkContent:SetHeight(math.max(y, 1))
end

-------------------------------------------------------------------- slash
SLASH_DGSJUNK1 = "/dgjunk"
SlashCmdList.DGSJUNK = function(msg)
    local cmd = (msg or ""):lower():match("^%s*(%S*)")
    if cmd == "preview" then
        if not config then BuildConfig() end     -- the Debug tab owns the label sync
        PreviewToggle()
        return
    end
    if not config then BuildConfig() end
    if config:IsShown() then
        config:Hide()
    else
        RefreshConfig()
        config:Show()
    end
end
