--[[ DGs Junk -------------------------------------------------------
  Standalone bag-cleanup helper. No dependencies (Auctionator optional for AH).

  Junk = Blizzard gray (Poor) quality + our own marks (DB.marks).

  Two icons:
    * JUNK   (gray border)   - cheapest junk item in your bags.
    * NORMAL (orange border) - cheapest non-junk item whose value is <= the
                               cheapest junk (worth less than your trash). Hidden
                               when nothing qualifies.
  "Junk" and "Normal" are the addon's two categories and are named that way
  everywhere the player sees them: the icons, the comparison dialog, the ignore
  list and its reset buttons. The internal frame is still DGsJunk_Cheap.
  Shift-click an icon to delete; shift-right-click to ignore; right-click for a
  menu (delete / mark / ignore / settings). In the loot window, hovering an item
  shows a "worth clearing junk to make room?" verdict; shift-click loot with full
  bags opens the comparison dialog, where you pick which item to delete, and
  clicking that candidate deletes it and loots the slot.
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

--[[ localization -----------------------------------------------------------
  The English string IS the key. An untranslated entry falls through the
  metatable and renders as English, so a missing translation is never a blank
  label or a nil error - the worst case is an English line in a German client.

  Only what the player reads in normal use is wrapped. Deliberately NOT wrapped:
  the debug log (dbg/act - it gets pasted into a conversation for analysis, and
  translating it makes that harder), the slash command and its subcommands, the
  addon name, frame names and the SavedVariables key.

  Colour codes stay OUTSIDE the keys wherever the string is coloured as a whole,
  so a translator never has to copy |cff... sequences correctly.
----------------------------------------------------------------------------]]
local fmt = string.format
local L = setmetatable({}, { __index = function(_, k) return k end })

local locales = {}

locales.deDE = {
    -- chat output
    ["deleted"]                          = "gelöscht",
    ["cleared for loot:"]                = "für Beute entsorgt:",
    ["item"]                             = "Gegenstand",
    ["item %d"]                          = "Gegenstand %d",
    ["Item #%d"]                         = "Gegenstand #%d",
    ["this item"]                        = "dieser Gegenstand",
    ["rare"]                             = "selten",
    ["ignoring %s"]                      = "ignoriere %s",
    ["/dgjunk to manage"]                = "/dgjunk zum Verwalten",
    ["sold %d marked item(s) for %s."]   = "%d markierte Gegenstände für %s verkauft.",
    ["loot is gone - nothing deleted."]  = "Beute ist weg, nichts gelöscht.",
    ["your bags changed - nothing deleted, pick again."] =
        "Deine Taschen haben sich geändert, nichts gelöscht, wähle erneut.",
    ["that item is still being rolled for - nothing to clear yet."] =
        "Auf diesen Gegenstand wird noch gewürfelt, noch nichts zu entsorgen.",
    ["preview mode - nothing was deleted."] = "Vorschaumodus, es wurde nichts gelöscht.",
    ["preview mode - nothing was ignored."] = "Vorschaumodus, es wurde nichts ignoriert.",
    ["preview: no usable items in your bags."] =
        "Vorschau: keine brauchbaren Gegenstände in deinen Taschen.",
    ["no menu API; use shift-left = delete, shift-right = ignore, /dgjunk = settings"] =
        "keine Menü-API; Umschalt-links = löschen, Umschalt-rechts = ignorieren, /dgjunk = Einstellungen",
    ["development mode %s"]              = "Entwicklermodus %s",
    ["development mode is off (/dgjunk dev)."] = "Entwicklermodus ist aus (/dgjunk dev).",
    ["on"]                               = "an",
    ["off"]                              = "aus",
    ["- the Debug tab is available"]     = "- der Debug-Reiter ist verfügbar",

    -- context menu
    ["Ignore %s"]                        = "%s ignorieren",
    ["Delete %s"]                        = "%s löschen",
    ["Mark as junk"]                     = "Als Plunder markieren",
    ["Unmark as junk"]                   = "Plundermarkierung aufheben",
    ["Settings"]                         = "Einstellungen",
    ["Cancel"]                           = "Abbrechen",

    -- icons and their tooltips
    ["Junk"]                             = "Plunder",
    ["Normal"]                           = "Normal",
    ["AH"]                               = "AH",
    ["AH:"]                              = "AH:",
    ["Shift-left-click"]                 = "Umschalt-Linksklick",
    ["Shift-right-click"]                = "Umschalt-Rechtsklick",
    ["Left-click"]                       = "Linksklick",
    ["Right-click"]                      = "Rechtsklick",
    ["Left-click:"]                      = "Linksklick:",
    ["Right-click:"]                     = "Rechtsklick:",
    ["Drag:"]                            = "Ziehen:",
    ["Drag to move"]                     = "Ziehen zum Verschieben",
    ["delete"]                           = "löschen",
    ["ignore"]                           = "ignorieren",
    ["settings"]                         = "Einstellungen",
    ["for menu"]                         = "für das Menü",
    ["for settings"]                     = "für die Einstellungen",
    ["for menu (delete / ignore / settings)"] = "für das Menü (löschen / ignorieren / Einstellungen)",
    ["show/hide frames"]                 = "Fenster ein-/ausblenden",
    ["move around minimap"]              = "um die Minikarte bewegen",
    ["Nothing to clear right now."]      = "Im Moment nichts zu entsorgen.",

    -- loot verdicts
    ["Loot"]                             = "Beute",
    ["Loot it"]                          = "Mitnehmen",
    ["Skip"]                             = "Liegen lassen",
    ["Quest item: Take it!"]             = "Questgegenstand: mitnehmen!",
    ["quest - take it"]                  = "Quest, mitnehmen",
    ["worth it"]                         = "lohnt sich",
    ["not worth it"]                     = "lohnt sich nicht",
    ["recommended"]                      = "empfohlen",
    ["costs more than the loot"]         = "teurer als die Beute",
    ["stacks, costs no bag slot"]        = "stapelbar, kostet keinen Taschenplatz",
    ["cheapest to discard %s"]           = "günstigster Verlust %s",
    ["Nothing to clear a slot"]          = "Nichts, um Platz zu schaffen",
    ["Being rolled for - not yours to take yet"] = "Wird noch ausgewürfelt, noch nicht deiner",

    -- comparison dialog
    ["Bags full - click a junk/item to delete and loot:"] =
        "Taschen voll, klicke einen Gegenstand zum Löschen und Plündern:",
    ["Arrows or mouse wheel over an icon: pick a different item"] =
        "Pfeile oder Mausrad über einem Symbol: anderen Gegenstand wählen",
    ["Arrows / mouse wheel:"]            = "Pfeile / Mausrad:",
    ["pick another item"]                = "anderen Gegenstand wählen",
    ["delete this and loot"]             = "dies löschen und plündern",
    ["no junk"]                          = "kein Plunder",
    ["no normal item"]                   = "kein normaler Gegenstand",

    -- container assist
    ["Bags full - click a junk/item to delete, then it opens:"] =
        "Taschen voll, klicke einen Gegenstand zum Löschen, dann wird geöffnet:",
    ["delete this and open"]             = "dies löschen und öffnen",
    ["contents unknown"]                 = "Inhalt unbekannt",
    ["cleared to open:"]                 = "gelöscht zum Öffnen:",
    ["that container is gone - nothing was opened."] =
        "dieser Behälter ist nicht mehr da, es wurde nichts geöffnet.",
    ["your bags are full and there is nothing cheap enough to delete."] =
        "deine Taschen sind voll und es gibt nichts Günstiges genug zum Löschen.",
    ["no slot was freed - the container was not opened."] =
        "es wurde kein Platz frei, der Behälter wurde nicht geöffnet.",
    ["opened: %s"]                       = "geöffnet: %s",

    -- settings window: tabs
    ["Ignored"]                          = "Ignoriert",
    ["Debug"]                            = "Debug",
    ["Log"]                              = "Log",

    -- settings window: Ignored tab
    ["Ignored items - add via shift-right-click or right-click > Ignore"] =
        "Ignorierte Gegenstände, hinzufügen per Umschalt-Rechtsklick oder Rechtsklick > Ignorieren",
    ["Reset Junk"]                       = "Plunder zurücksetzen",
    ["Reset Normal"]                     = "Normal zurücksetzen",
    ["Reset All"]                        = "Alle zurücksetzen",
    ["Reset ignored Junk"]               = "Ignorierten Plunder zurücksetzen",
    ["Reset ignored Normal"]             = "Ignorierte Normale zurücksetzen",
    ["Reset the whole ignore list"]      = "Die gesamte Ignorierliste zurücksetzen",
    -- These three only ever appear after "aus" / "bei", so they are in the dative.
    ["ignored Junk"]                     = "dem ignorierten Plunder",
    ["ignored Normal"]                   = "den ignorierten Normalen",
    ["the whole ignore list"]            = "der gesamten Ignorierliste",
    ["Shift-click to skip the confirm."] = "Umschalt-Klick überspringt die Abfrage.",
    ["Remove from ignore list."]         = "Von der Ignorierliste entfernen.",

    -- settings window: Junk tab
    ["Items you marked as junk that are in your bags - X unmarks them, nothing is deleted"] =
        "Von dir als Plunder markierte Gegenstände in deinen Taschen. X hebt die Markierung auf, es wird nichts gelöscht",
    ["No marked junk in your bags."]     = "Kein markierter Plunder in deinen Taschen.",
    ["Clear all junk"]                   = "Alle Plundermarken aufheben",
    ["Unmark everything you marked as junk"] = "Alle deine Plundermarkierungen aufheben",
    ["Unmark as junk. Shift-click to skip the confirm."] =
        "Plundermarkierung aufheben. Umschalt-Klick überspringt die Abfrage.",

    -- settings window: Settings tab
    ["Loot-assist"]                      = "Beute-Assistent",
    ["Shift-click a loot item with full bags to choose what to delete, then loot it"] =
        "Umschalt-Klick auf Beute bei vollen Taschen: erst wählen, was gelöscht wird, dann wird geplündert",
    ["Container assist"]                 = "Behälter-Assistent",
    ["Opening a clam, box or pack with full bags offers what to delete, then opens it for you"] =
        "Beim Öffnen einer Muschel, Kiste oder eines Pakets mit vollen Taschen wird angeboten, was gelöscht wird, danach wird geöffnet",
    ["Colour loot rows"]                 = "Beutezeilen einfärben",
    ["Tints the loot window green (worth more than the cheapest thing you would delete) or red (skip it), only while your bags are full"] =
        "Färbt das Beutefenster grün (mehr wert als das Günstigste, was du löschen würdest) oder rot (liegen lassen), nur bei vollen Taschen",
    ["Suggest by AH prices"]             = "Nach AH-Preisen vorschlagen",
    ["Rank by Auctionator AH value instead of vendor (falls back to vendor)"] =
        "Nach Auctionator-AH-Wert statt Händlerpreis bewerten (fällt auf den Händlerpreis zurück)",
    ["Requires Auctionator (not installed / not detected) - ranking uses vendor prices"] =
        "Benötigt Auctionator (nicht installiert / nicht erkannt), die Bewertung nutzt Händlerpreise",
    ["Show item frames"]                 = "Gegenstandsfenster anzeigen",
    ["Master toggle - same as left-clicking the minimap icon"] =
        "Hauptschalter, wie ein Linksklick auf das Minikartensymbol",
    ["Always show item frames"]          = "Gegenstandsfenster immer anzeigen",
    ["Keep the icons visible even when there is nothing to delete"] =
        "Die Symbole sichtbar lassen, auch wenn es nichts zu löschen gibt",
    ["Show minimap icon"]                = "Minikartensymbol anzeigen",
    ["Minimap button: left-click show/hide frames, right-click settings"] =
        "Minikartenknopf: Linksklick blendet die Fenster ein/aus, Rechtsklick öffnet die Einstellungen",
    ["Auto-sell marked items at vendors"] = "Markierte Gegenstände beim Händler automatisch verkaufen",
    ["Sells only items YOU marked as junk and only above gray quality - grays are left to sell-all-junk"] =
        "Verkauft nur Gegenstände, die DU als Plunder markiert hast, und nur oberhalb grauer Qualität. Graue bleiben dem Plunderverkauf überlassen",
    ["Reset icon position"]              = "Symbolposition zurücksetzen",
    ["Frame scale: %d%%"]                = "Fenstergröße: %d%%",

    -- settings window: language picker ("Deutsch" is deliberately not a key -
    -- a language is named in its own language in every locale)
    ["Language"]                         = "Sprache",
    ["Language: %s"]                     = "Sprache: %s",
    ["Automatic (game language)"]        = "Automatisch (Spielsprache)",
    ["English"]                          = "Englisch",
    ["Addon language"]                   = "Sprache des Addons",
    ["Automatic follows the game's language. Pick English or Deutsch to override it, whatever the client is set to. Changing it asks first, then reloads your interface."] =
        "Automatisch folgt der Sprache des Spiels. Wähle Englisch oder Deutsch, um sie unabhängig davon festzulegen. Eine Änderung fragt nach und lädt dann deine Benutzeroberfläche neu.",
    ["The game's own language is used unless you override it here."] =
        "Es wird die Sprache des Spiels verwendet, solange du sie hier nicht überschreibst.",
    ["Type /reload to apply the new language."] =
        "Gib /reload ein, um die neue Sprache zu übernehmen.",
    ["Switch the addon language to %s?"] = "Sprache des Addons auf %s umstellen?",
    ["Your interface will be reloaded."] = "Deine Benutzeroberfläche wird neu geladen.",
    ["Reload now"]                       = "Jetzt neu laden",
    ["not while you are in combat - try again afterwards."] =
        "nicht im Kampf, versuch es danach erneut.",

    -- settings window: profiles
    ["Character profile"]                = "Charakterprofil",
    ["Default"]                          = "Standard",
    ["Default (shared)"]                 = "Standard (geteilt)",
    ["Profile: %s"]                      = "Profil: %s",
    ["This character uses: %s"]          = "Dieser Charakter nutzt: %s",
    ["shared list"]                      = "geteilte Liste",
    ["own list"]                         = "eigene Liste",
    ["Switch profile"]                   = "Profil wechseln",
    ["Default is shared by every character on it; the character profile is private. Both always exist, switching never deletes either."] =
        "Standard wird von jedem Charakter geteilt, der es nutzt; das Charakterprofil ist privat. Beide existieren immer, ein Wechsel löscht keines von beiden.",
    ["Copy from Default"]                = "Von Standard kopieren",
    ["Copy to Default"]                  = "Nach Standard kopieren",
    ["Pull Default into this character"] = "Standard in diesen Charakter holen",
    ["Push this character into Default"] = "Diesen Charakter nach Standard schreiben",
    ["Overwrites this character's ignore list + junk marks. Shift-click skips confirm."] =
        "Überschreibt Ignorierliste und Plundermarkierungen dieses Charakters. Umschalt-Klick überspringt die Abfrage.",
    ["Overwrites the shared Default list for every character on it. Shift-click skips confirm."] =
        "Überschreibt die geteilte Standardliste für jeden Charakter, der sie nutzt. Umschalt-Klick überspringt die Abfrage.",
    ["replace this character's list with a copy of Default"] =
        "die Liste dieses Charakters durch eine Kopie von Standard ersetzen",
    ["overwrite Default with this character's list"] =
        "Standard mit der Liste dieses Charakters überschreiben",
    ["copied %s into this character's profile."] = "%s in das Profil dieses Charakters kopiert.",
    ["copied this character's profile into %s."] = "Profil dieses Charakters nach %s kopiert.",
    ["now using the %s profile."]        = "nutzt jetzt das Profil %s.",
    ["Profiles scope only the ignore list and junk marks; every setting above is shared across your characters. \"Default\" is the shared list, every character on it sees the same entries."] =
        "Profile umfassen nur die Ignorierliste und die Plundermarkierungen; jede Einstellung darüber gilt für alle deine Charaktere. \"Standard\" ist die geteilte Liste, jeder Charakter darauf sieht dieselben Einträge.",

    -- settings window: Debug tab
    ["Open the addon's dialogs on demand, without having to fill your bags first. They use your real items and the real ranking; clicking anything in them does nothing - %s."] =
        "Öffnet die Dialoge des Addons auf Wunsch, ohne dass du erst deine Taschen füllen musst. Sie nutzen deine echten Gegenstände und die echte Bewertung; ein Klick darin bewirkt nichts, %s.",
    ["nothing is ever deleted"]          = "es wird nie etwas gelöscht",
    ["Show comparison dialog"]           = "Vergleichsdialog anzeigen",
    ["Hide comparison dialog"]           = "Vergleichsdialog ausblenden",
    ["Full-bags comparison dialog"]      = "Vergleichsdialog bei vollen Taschen",
    ["Picks a random bag item worth more than your two cheapest, so the \"worth it\" verdict shows. Also available as /dgjunk preview."] =
        "Wählt einen zufälligen Gegenstand aus deinen Taschen, der mehr wert ist als deine zwei günstigsten, damit das Urteil \"lohnt sich\" erscheint. Auch als /dgjunk preview verfügbar.",

    -- settings window: Log tab
    ["Debug logging"]                    = "Debug-Logging",
    ["Record diagnostic messages here (never printed to chat)"] =
        "Diagnosemeldungen hier aufzeichnen (nie im Chat ausgegeben)",
    ["Clear"]                            = "Leeren",
    ["Refresh"]                          = "Aktualisieren",
    ["(log empty - enable Debug logging)"] = "(Log leer, Debug-Logging aktivieren)",

    -- confirm dialogs
    ["Really delete this %s item?"]      = "Diesen Gegenstand der Qualität %s wirklich löschen?",
    ["This cannot be undone."]           = "Das kann nicht rückgängig gemacht werden.",
    ["This will %s."]                    = "Dies wird %s.",
    ["Continue?"]                        = "Fortfahren?",
    ["Remove %d item from %s?"]          = "%d Gegenstand aus %s entfernen?",
    ["Remove %d items from %s?"]         = "%d Gegenstände aus %s entfernen?",
    ["Remove %s from the ignore list?"]  = "%s von der Ignorierliste entfernen?",
    ["nothing to reset for %s"]          = "nichts zurückzusetzen bei %s",
    ["Unmark %s as junk?"]               = "Markierung von %s als Plunder aufheben?",
    ["Unmark all %d item marked as junk?"]  = "Markierung von %d Gegenstand aufheben?",
    ["Unmark all %d items marked as junk?"] = "Markierung von %d Gegenständen aufheben?",
    ["Your items are not touched, only the marks."] =
        "Deine Gegenstände bleiben unangetastet, nur die Markierungen.",
    ["unmarked %d item"]                 = "%d Markierung aufgehoben",
    ["unmarked %d items"]                = "%d Markierungen aufgehoben",
    ["nothing marked as junk"]           = "nichts als Plunder markiert",
    ["shift-click: no confirm"]          = "Umschalt-Klick: ohne Abfrage",
}

-- The locale is fixed at load time and never changes afterwards: the popup
-- templates and every frame label below are built once, from L, as this file
-- runs. DGsJunkDB.locale is a development override set by "/dgjunk lang" and it
-- therefore needs a /reload to take effect, which is what that command says.
-- Reading the saved variable here is a best-effort: if it is not populated yet
-- the client locale wins and the override lands on the next reload.
local function PickLocale()
    local saved = type(DGsJunkDB) == "table" and DGsJunkDB.locale or nil
    return saved or GetLocale()
end

local activeLocale = PickLocale()
for k, v in pairs(locales[activeLocale] or {}) do L[k] = v end
-- Set when the locale had to be re-applied on ADDON_LOADED: the labels built
-- while this file ran are then still in the previous language, so the picker
-- keeps asking for a /reload even though L itself is already correct.
local localeStale = false

local DB                                       -- saved vars (pos + ignore list); set on ADDON_LOADED
local Update, BuildConfig, RefreshConfig       -- fwd decls
local RefreshBagOverlays                       -- fwd decl (bag junk-coin overlay)
local RefreshJunkList                          -- fwd decl (Junk-clear tab)
local LootClearCandidates                      -- fwd decl (defined in the loot-assist section)
local suppressUseHook = false                  -- set around our own UseContainerItem calls
                                               -- (container assist reads it; auto-sell sets it)
local lootSource                               -- bag slot the open loot window came out of, if any
                                               -- (a container being looted: never offer it up)
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
-- Declared up here (assigned in BuildConfirm) so Update() can reach the dialog:
-- every refresh path runs through Update(), and the dialog has to be one of the
-- things it refreshes.
local confirmFrame

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

-- A bag slot that cannot be given up right now.
--
-- Two ways that happens. The client locks a slot while the server is busy with
-- it, and PickupContainerItem on a locked slot does nothing - offering one means
-- offering a delete that silently fails. And the item whose loot window is
-- currently open is the SOURCE of that loot: destroying a clam to make room for
-- its own Clam Meat would take the meat with it, which is the one trade this
-- addon must never propose. `lootSource` is set while such a window is open.
local function SlotUndeletable(bag, slot)
    if lootSource and lootSource.bag == bag and lootSource.slot == slot then return "loot source" end
    local t, _, locked = GetContainerItemInfo(bag, slot)
    if type(t) == "table" then locked = t.isLocked end
    if locked then return "locked" end
    return nil
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
-- independently). The normal one must have vendor value and not be a quest item.
local function ScanBags()
    local junk, cheap
    for bag = BACKPACK_CONTAINER, NUM_BAG_FRAMES do
        for slot = 1, (GetContainerNumSlots(bag) or 0) do
            local id = GetContainerItemID(bag, slot)
            -- quest items are never suggested, even if marked as junk
            if id and not exclusions[id] and not IsQuestItem(id)
               and not SlotUndeletable(bag, slot)
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

-- Coin suffixes come from Blizzard's own globals (enUS g/s/c, deDE G/S/K), so
-- every language is right without a translation entry. GetCoinTextureString is
-- deliberately not used: it draws coin icons and ignores our colour scheme.
local GOLD_SUFFIX   = _G.GOLD_AMOUNT_SYMBOL   or "g"
local SILVER_SUFFIX = _G.SILVER_AMOUNT_SYMBOL or "s"
local COPPER_SUFFIX = _G.COPPER_AMOUNT_SYMBOL or "c"

local function Coin(c)
    if not c or c == 0 then return "0" .. COPPER_SUFFIX end
    local g = math.floor(c / 10000)
    local s = math.floor((c % 10000) / 100)
    local cp = c % 100
    local out = ""
    if g > 0 then out = out .. "|cffffd700" .. g .. GOLD_SUFFIX .. "|r " end
    if s > 0 then out = out .. "|cffc7c7cf" .. s .. SILVER_SUFFIX .. "|r " end
    return out .. "|cffeda55f" .. cp .. COPPER_SUFFIX .. "|r"
end

-- Compact one-line description of a candidate record, so a log entry says which
-- physical bag slot was involved and what it was judged to be worth. Values are
-- raw copper on purpose: colour-coded coin strings are unreadable in a log and
-- cannot be compared by eye.
local function RecTag(rec)
    if not rec then return "-" end
    local name = (rec.id and select(1, GetItemInfo(rec.id))) or ("item " .. tostring(rec.id))
    return string.format("%s(id=%s bag%s/%s x%s value=%sc each=%sc worth=%sc%s)",
        name, tostring(rec.id), tostring(rec.bag), tostring(rec.slot), tostring(rec.count or 1),
        tostring(rec.value or 0), tostring(rec.each or 0), tostring(rec.worthEach or 0),
        rec.junk and " junk" or "")
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
    text = "|cffffcc55DGs Junk|r\n\n" .. L["Really delete this %s item?"] .. "\n\n%s",
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
        local qname = _G["ITEM_QUALITY" .. quality .. "_DESC"] or L["rare"]
        local col = (ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
                     and ITEM_QUALITY_COLORS[quality].hex) or "|cffffffff"
        local what = (link or L["this item"]) .. ((rec.count or 1) > 1 and (" x" .. rec.count) or "")
        act("delete blocked", rec.id, "quality " .. quality .. " - asking to confirm")
        StaticPopup_Show("DGSJUNK_CONFIRM_DELETE_RARE", col .. qname .. "|r", what,
            function() DeleteRecord(rec, tag, true) end)
        return
    end
    act("delete", rec.id, (tag or "deleted") .. " bag " .. tostring(rec.bag) .. " slot " .. tostring(rec.slot))
    PickupContainerItem(rec.bag, rec.slot)
    DeleteCursorItem()                                 -- non-gray -> Blizzard raises a confirm popup
    -- `tag` stays an English key on the act() line above (the log is English by
    -- design) and is translated only here, where the player reads it.
    print(GREEN .. "DGs Junk|r " .. L[tag or "deleted"] .. " " .. (link or L["item"]))
end

local function IgnoreRecord(rec)
    if not rec then return end
    DB.ignore = DB.ignore or {}
    DB.ignore[rec.id] = rec.junk and "junk" or "normal"
    act("ignore", rec.id, "category=" .. DB.ignore[rec.id])
    local link = select(2, GetItemInfo(rec.id))
    print(GOLD .. "DGs Junk|r " .. fmt(L["ignoring %s"], link or L["item"]) ..
        " |cff888888(" .. L["/dgjunk to manage"] .. ")|r")
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
    local link = rec and (select(2, GetItemInfo(rec.id)) or L["this item"])
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
                root:CreateButton(fmt(L["Ignore %s"], link), doIgnore)
                root:CreateButton(marked and L["Unmark as junk"] or L["Mark as junk"], marked and doUnmark or doMark)
                root:CreateDivider()
                root:CreateButton(fmt(L["Delete %s"], link), doDelete)
                root:CreateDivider()
            end
            root:CreateButton(L["Settings"], OpenSettings)
        end)
    elseif EasyMenu then                                     -- legacy fallback
        local menu = { { text = "DGs Junk", isTitle = true, notCheckable = true } }
        if rec then
            menu[#menu + 1] = { text = fmt(L["Ignore %s"], link), notCheckable = true, func = doIgnore }
            menu[#menu + 1] = { text = marked and L["Unmark as junk"] or L["Mark as junk"],
                                notCheckable = true, func = marked and doUnmark or doMark }
            menu[#menu + 1] = { text = "", notCheckable = true, disabled = true }   -- divider
            menu[#menu + 1] = { text = fmt(L["Delete %s"], link), notCheckable = true, func = doDelete }
            menu[#menu + 1] = { text = "", notCheckable = true, disabled = true }   -- divider
        end
        menu[#menu + 1] = { text = L["Settings"], notCheckable = true, func = OpenSettings }
        menu[#menu + 1] = { text = CANCEL or L["Cancel"], notCheckable = true, func = function() end }
        if not legacyMenuFrame then
            legacyMenuFrame = CreateFrame("Frame", "DGsJunkContextMenu", UIParent, "UIDropDownMenuTemplate")
        end
        EasyMenu(menu, legacyMenuFrame, "cursor", 0, 0, "MENU")
    else
        print(GOLD .. "DGs Junk|r " .. L["no menu API; use shift-left = delete, shift-right = ignore, /dgjunk = settings"])
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
            GameTooltip:AddLine("|cff33ff99" .. L["Shift-left-click"] .. "|r|cff888888 " .. L["delete"] .. "|r")
            GameTooltip:AddLine("|cffff8800" .. L["Shift-right-click"] .. "|r|cff888888 " .. L["ignore"] .. "|r")
            GameTooltip:AddLine("|cffffcc55" .. L["Right-click"] .. "|r|cff888888 " .. L["for menu (delete / ignore / settings)"] .. "|r")
        else
            GameTooltip:AddLine("DGs Junk")
            GameTooltip:AddLine("|cff888888" .. L["Nothing to clear right now."] .. "|r")
            GameTooltip:AddLine("|cffffcc55" .. L["Right-click"] .. "|r|cff888888 " .. L["for settings"] .. "|r")
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
        self.ah:SetText(ah and (L["AH"] .. " " .. Coin(ah)) or GREY .. L["AH"] .. " --|r")
        self:Show()
    end

    return b
end

-- First argument is the FRAME name (DGsJunk_Junk / DGsJunk_Cheap) and must stay
-- English; only the visible label is translated.
local junkIcon  = MakeIcon("Junk",  {0.55, 0.55, 0.55}, L["Junk"],  GREY)
local cheapIcon = MakeIcon("Cheap", {0.90, 0.55, 0.15}, L["Normal"], GOLD)

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
    GameTooltip:AddLine("|cff888888" .. L["Drag to move"] .. "|r")
    GameTooltip:AddLine("|cffffcc55" .. L["Right-click"] .. "|r|cff888888 " .. L["for menu"] .. "|r")
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
        GameTooltip:AddLine("|cff888888" .. L["Left-click:"] .. "|r " .. L["show/hide frames"])
        GameTooltip:AddLine("|cff888888" .. L["Right-click:"] .. "|r " .. L["settings"])
        GameTooltip:AddLine("|cff888888" .. L["Drag:"] .. "|r " .. L["move around minimap"])
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
    -- The comparison dialog is rebuilt FIRST and outside the master-hide check:
    -- it is a modal decision the user is looking at right now, and it must agree
    -- with the rest of the addon even when the floating icons are switched off.
    -- Ignoring or marking an item from anywhere - the icons, a bag menu, the
    -- settings window - lands here, so the dialog re-ranks with everything else.
    if confirmFrame and confirmFrame:IsShown() and confirmFrame.SyncLists then
        confirmFrame.SyncLists()
    end
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
                                -- A sale is not the player reaching for a
                                -- container, so it must not arm the container
                                -- assist's "what did you just use" memory.
                                suppressUseHook = true
                                pcall(function() UseContainerItem(b, s) end)
                                suppressUseHook = false
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
        print("|cffffd200DGs Junk|r " .. fmt(L["sold %d marked item(s) for %s."], sold, Coin(value)))
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

-- Which loot slot a tooltip is describing, so its quantity and eligibility can be
-- read back off the slot itself.
local function LootTipSlot(tip)
    local info = tip and (tip.info or tip.processingInfo)
    local slot = info and info.getterName == "GetLootItem" and info.getterArgs and info.getterArgs[1]
    if not slot then
        local owner = tip and tip.GetOwner and tip:GetOwner()
        slot = owner and ((owner.slot) or (owner.GetID and owner:GetID()))
    end
    return slot
end

-- A loot slot can hold a stack, and the whole stack is what the bag slot buys you.
local function LootSlotQuantity(slot)
    return (slot and GetLootSlotInfo and select(3, GetLootSlotInfo(slot))) or 1
end

-- Group loot: while a green or better is being rolled for, the slot is locked for
-- everyone, and it stays locked for you if you lose the roll. There is nothing to
-- decide about an item you cannot take, so every verdict has to sit this out.
local function LootSlotLocked(slot)
    if not (slot and GetLootSlotInfo) then return false end
    return select(6, GetLootSlotInfo(slot)) and true or false
end

local function AddVerdict(tip, id)
    if not id then dbg("no itemID from tooltip"); return end
    if tip.dgsjID == id then return end
    tip.dgsjID = id
    -- Stack total, not unit price: the candidates are ranked on stack totals, so
    -- the looted item has to be measured the same way or the comparison is unfair
    -- to the loot.
    local tipSlot = LootTipSlot(tip)
    local qty = LootSlotQuantity(tipSlot)
    local hoverWorth = select(1, Worth(id, qty))
    if not hoverWorth then dbg("no value for id", id, "(info not cached)"); return end
    if not IsLootTooltip(tip) then return end          -- verdict only in the loot window, not bags
    -- Being rolled for, or lost: a keep/trash verdict would be advice about a
    -- decision that is not yours to make.
    if LootSlotLocked(tipSlot) then
        dbg("loot slot", tipSlot, "locked - roll in progress or not eligible")
        tip:AddLine(GREY .. L["Being rolled for - not yours to take yet"] .. "|r")
        return tip:Show()
    end
    if IsQuestItem(id) then                            -- always worth taking, never compared on value
        dbg("quest item", id, "- take it")
        tip:AddLine(GREEN .. L["Quest item: Take it!"] .. "|r")
        return tip:Show()
    end
    if StackRoom(id) > 0 then                          -- stacks onto what you carry: free
        dbg("stackable", id, "- room in an existing stack")
        tip:AddLine(GREEN .. L["Loot it"] .. "|r " .. GREY .. "(" .. L["stacks, costs no bag slot"] .. ")|r")
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
    dbg("loot verdict id=" .. id, "x" .. qty, "hover=" .. hoverWorth,
        "junk=" .. (junk and (junk.id .. "@" .. (junk.value or 0) .. " x" .. (junk.count or 1)) or "none"),
        "other=" .. (other and (other.id .. "@" .. (other.value or 0) .. " x" .. (other.count or 1)) or "none"))

    if #worths == 0 then
        tip:AddLine(GREY .. L["Nothing to clear a slot"] .. "|r")
    else
        -- Only the cheapest candidate matters: it is the one the dialog
        -- recommends, so that is what looting this item would actually cost.
        local lo = math.min(unpack(worths))
        if hoverWorth > lo then
            tip:AddLine(GREEN .. L["Loot it"] .. "|r " .. GREY .. "(" .. fmt(L["cheapest to discard %s"], Coin(lo)) .. ")|r")
        else
            tip:AddLine(RED .. L["Skip"] .. "|r " .. GREY .. "(" .. fmt(L["cheapest to discard %s"], Coin(lo)) .. ")|r")
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
-- Shift-click a loot item with full bags -> open the comparison dialog with the
-- deletable candidates. Picking one there deletes it and re-loots the slot; the
-- dialog IS the confirm, so nothing is destroyed on the shift-click itself.
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
local lastCandidateSummary      -- log the scan result only when it actually changes
LootClearCandidates = function()
    local junkList, otherList = {}, {}
    for bag = BACKPACK_CONTAINER, NUM_BAG_FRAMES do
        for slot = 1, (GetContainerNumSlots(bag) or 0) do
            local id = GetContainerItemID(bag, slot)
            -- quest items are never offered for deletion, even if marked as junk
            if id and not exclusions[id] and not IsQuestItem(id)
               and not SlotUndeletable(bag, slot)
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
    local rawJunk, rawOther = #junkList, #otherList
    junkList, otherList = byItem(junkList), byItem(otherList)
    -- This runs on every loot tooltip and every row tint, so logging it every
    -- time would flood the 400-line buffer and push out what you were actually
    -- looking for. Log it only when the outcome changes.
    local summary = string.format("junk %d slots -> %d items, other %d slots -> %d items%s | cheapest junk=%s | cheapest other=%s",
        rawJunk, #junkList, rawOther, #otherList,
        ((rawJunk > MAX_CANDIDATES or rawOther > MAX_CANDIDATES) and (" (capped at " .. MAX_CANDIDATES .. ")") or ""),
        RecTag(junkList[1]), RecTag(otherList[1]))
    if summary ~= lastCandidateSummary then
        lastCandidateSummary = summary
        dbg("candidates:", summary,
            "| basis=" .. ((DB and DB.ahSuggest) and "AH" or "vendor"))
    end
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
        print(GOLD .. "DGs Junk|r " .. L["loot is gone - nothing deleted."])
        return
    end
    DeleteRecord(rec, "cleared for loot:")
    pcall(LootSlot, slot)
    if C_Timer then C_Timer.After(0.15, Update) end
end

-- Custom confirm dialog: loot item on the left, the two cheapest replace
-- candidates (junk + non-junk) on the right. Click a candidate to delete it and
-- loot; hover any icon to compare; price shown under each icon.
-- The dialog only makes sense while the loot window is open: its whole promise is
-- "delete this, then loot that". If the loot closes (you ran away, the corpse
-- despawned, someone else took it) the slot is gone, so the dialog must go too -
-- otherwise a click deletes an item and loots nothing.
local function CloseLootConfirm()
    -- Only the LOOT dialog is tied to the loot window. The container dialog uses
    -- the same frame but its target is a bag slot, so a loot window closing
    -- somewhere else must not pull it out from under the player.
    if confirmFrame and confirmFrame.clearAction then return end
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

    -- Paging state lives on the frame, so the arrows, the wheel, a click and a bag
    -- update all read the same thing. Declared up here because the button scripts
    -- below close over it.
    local function listFor(which) return ((which == "junk") and f.junkList or f.otherList) or {} end
    local function idxFor(which)  return ((which == "junk") and f.junkIdx  or f.otherIdx) or 1 end

    local head = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    head:SetPoint("TOP", 0, -26)
    head:SetText(L["Bags full - click a junk/item to delete and loot:"])
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

    local function hover(anchor, hints) return function(self)
        if self.link then GameTooltip:SetOwner(self, anchor); GameTooltip:SetHyperlink(self.link)
        elseif self.itemID then GameTooltip:SetOwner(self, anchor); GameTooltip:SetItemByID(self.itemID)
        else return end
        -- Same hint block as the two bag icons, so the interactions read the same
        -- everywhere: what a click does is never a thing you have to discover.
        if hints and self.rec then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("|cff33ff99" .. L["Left-click"] .. "|r|cff888888 " ..
                (f.hintAction or L["delete this and loot"]) .. "|r")
            GameTooltip:AddLine("|cffff8800" .. L["Shift-right-click"] .. "|r|cff888888 " .. L["ignore"] .. "|r")
            GameTooltip:AddLine("|cffffcc55" .. L["Right-click"] .. "|r|cff888888 " .. L["for menu"] .. "|r")
            if #listFor(self.which) > 1 then
                GameTooltip:AddLine("|cff888888" .. L["Arrows / mouse wheel:"] .. "|r " .. L["pick another item"])
            end
        end
        GameTooltip:Show()
    end end

    -- Deliberately not OpenMenu(): in this dialog the only safe extra action is
    -- Ignore. Delete already has the left-click, and offering it twice - once as
    -- a click, once in a menu - is how an irreversible action gets hit by accident.
    local function IgnoreMenu(rec, owner)
        local link = select(2, GetItemInfo(rec.id)) or L["this item"]
        local function doIgnore() f.IgnoreCandidate(rec) end
        if MenuUtil and MenuUtil.CreateContextMenu then
            MenuUtil.CreateContextMenu(owner or UIParent, function(_, root)
                root:CreateTitle("DGs Junk")
                root:CreateButton(fmt(L["Ignore %s"], link), doIgnore)
            end)
        elseif EasyMenu then
            legacyMenuFrame = legacyMenuFrame or CreateFrame("Frame", "DGsJunkConfirmMenu", UIParent, "UIDropDownMenuTemplate")
            EasyMenu({ { text = "DGs Junk", isTitle = true, notCheckable = true },
                       { text = fmt(L["Ignore %s"], link), notCheckable = true, func = doIgnore } },
                     legacyMenuFrame, "cursor", 0, 0, "MENU")
        else
            doIgnore()          -- no menu API at all: do the only thing the menu offers
        end
    end

    -- Ignoring rebuilds the lists, and LootClearCandidates() filters ignored items
    -- out - so the item disappears and the slot shows the next candidate on its
    -- own. Holding the index still is what makes it feel like "go to the next
    -- one": same position, one fewer entry.
    f.IgnoreCandidate = function(rec)
        if not rec then return end
        if f.preview then
            print(GOLD .. "DGs Junk|r " .. L["preview mode - nothing was ignored."])
            dbg("preview: ignore suppressed for item " .. tostring(rec.id))
            return
        end
        IgnoreRecord(rec)          -- logs via act() and prints
        Update()                   -- rebuilds the icons, the settings lists AND this dialog
    end

    f.lootBtn = Slot("|cff33ff99" .. L["Loot"] .. "|r", 40)
    f.lootBtn:SetScript("OnEnter", hover("ANCHOR_LEFT"))
    f.lootBtn:SetScript("OnLeave", GameTooltip_Hide)
    local arrow = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    arrow:SetPoint("LEFT", f.lootBtn, "RIGHT", 26, 0); arrow:SetText("|cffaaaaaa>|r")

    f.junkBtn  = Slot("|cffcfcfcf" .. L["Junk"] .. "|r", 220)
    f.otherBtn = Slot("|cffffcc55" .. L["Normal"] .. "|r", 320)
    f.junkBtn.which, f.otherBtn.which = "junk", "other"
    Pager(f.junkBtn,  "junk")
    Pager(f.otherBtn, "other")
    for _, b in ipairs({ f.junkBtn, f.otherBtn }) do
        b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        b:SetScript("OnEnter", hover("ANCHOR_RIGHT", true))
        b:SetScript("OnLeave", GameTooltip_Hide)
        b:SetScript("OnClick", function(self, button)
            if button == "RightButton" then
                if not self.rec then return end
                if IsShiftKeyDown() then
                    dbg("candidate shift-right-click:", self.which, RecTag(self.rec))
                    f.IgnoreCandidate(self.rec)
                else
                    dbg("candidate right-click menu:", self.which, RecTag(self.rec))
                    IgnoreMenu(self.rec, self)
                end
                return
            end
            if f.preview then
                print(GOLD .. "DGs Junk|r " .. L["preview mode - nothing was deleted."])
                dbg("preview: click on", self.which, "ignored -", RecTag(self.rec))
                return                                   -- dialog stays open so you can keep poking at it
            end
            if not self.rec then return end
            dbg("candidate chosen:", self.which, idxFor(self.which) .. "/" .. #listFor(self.which),
                RecTag(self.rec))
            -- The record names a bag slot, and bags can shuffle while the dialog
            -- sits open (another delete, a stack merging, an addon moving things).
            -- Deleting by stale coordinates would destroy whatever landed there
            -- instead, so re-check the slot still holds what was picked.
            if GetContainerItemID(self.rec.bag, self.rec.slot) ~= self.rec.id then
                dbg("clear aborted: bag " .. tostring(self.rec.bag) .. " slot " ..
                    tostring(self.rec.slot) .. " no longer holds item " .. tostring(self.rec.id))
                print(GOLD .. "DGs Junk|r " .. L["your bags changed - nothing deleted, pick again."])
                if f.SyncLists then f.SyncLists() end
                return
            end
            f:Hide()
            -- The dialog is target-agnostic from here on: the loot path deletes
            -- and loots, the container path deletes and re-opens. Everything
            -- above (ranking, staleness re-check, preview guard) is shared.
            if f.clearAction then f.clearAction(self.rec) else DoLootClear(self.rec, f.slot) end
        end)
    end

    local cancel = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    cancel:SetSize(120, 24); cancel:SetPoint("BOTTOM", 0, 12); cancel:SetText(CANCEL or L["Cancel"])
    cancel:SetScript("OnClick", function() f:Hide() end)

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
        b.name:SetText(n or fmt(L["item %d"], rec.id))
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
        b.ah:SetText((ahEach and ahEach > 0) and (GREY .. L["AH:"] .. "|r " .. Coin(ahEach * cnt)) or "")
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
        fill(f.junkBtn,  jl[idxFor("junk")],  L["no junk"])
        fill(f.otherBtn, ol[idxFor("other")], L["no normal item"])
        pager(f.junkBtn, "junk"); pager(f.otherBtn, "other")
        -- the paging hint is noise when there is nothing to page through
        f.banner:SetText((#jl > 1 or #ol > 1)
            and (GREY .. L["Arrows or mouse wheel over an icon: pick a different item"] .. "|r") or "")

        -- The recommendation still means "the cheapest thing you could destroy",
        -- so it is anchored to the head of each list, never to whatever you have
        -- paged to. Page away from it and the tag simply goes - you made a
        -- deliberate choice, the dialog should not keep calling it recommended.
        local rj = jl[1] and jl[1].value or math.huge
        local ro = ol[1] and ol[1].value or math.huge
        local best = (rj <= ro) and f.junkBtn or f.otherBtn
        -- A quest item is not a trade. There is no price it loses to, so nothing
        -- on the right may be called too expensive for it: the cheaper head is
        -- still recommended (you do have to free a slot), and the other one is
        -- left neutral rather than warned against. Only quest items get this -
        -- everywhere else the red verdict is the whole point.
        local questLoot = (f.lid and IsQuestItem(f.lid)) and true or false
        for _, b in ipairs({ f.junkBtn, f.otherBtn }) do
            local rec = b.rec
            if rec then
                if not questLoot and f.lworth and rec.value >= f.lworth then
                    -- paged up past the point where the trade pays off
                    b.SetBorder(0.85, 0.15, 0.15)
                    b.tag:SetText(RED .. L["costs more than the loot"] .. "|r")
                elseif b == best and rec == ((b == f.junkBtn) and jl[1] or ol[1]) then
                    b.SetBorder(0.1, 0.85, 0.2)
                    b.tag:SetText(GREEN .. L["recommended"] .. "|r")
                end
            end
        end

        -- Verdict on the loot item: same rule as the loot tooltip, so the two can
        -- never disagree - the looted item's worth against the TOTAL value of the
        -- CHEAPEST stack you would have to destroy. Paging does not move it, or
        -- the dialog and the tooltip would start contradicting each other.
        local lo = math.min(rj, ro)
        if questLoot and not f.lootVerdict then
            f.lootBtn.SetBorder(0.1, 0.85, 0.2)
            f.lootBtn.tag:SetText(GREEN .. L["quest - take it"] .. "|r")
        elseif f.lootVerdict then
            -- A container's contents are not visible before it is opened, so
            -- there is no honest worth to compare. Judging the wrapper's own
            -- vendor price would answer a question nobody asked.
            f.lootBtn.SetBorder(0.3, 0.3, 0.3)
            f.lootBtn.tag:SetText(GREY .. f.lootVerdict .. "|r")
        elseif f.lworth and lo < math.huge then
            if f.lworth > lo then
                f.lootBtn.SetBorder(0.1, 0.85, 0.2)
                f.lootBtn.tag:SetText(GREEN .. L["worth it"] .. "|r")
            else
                f.lootBtn.SetBorder(0.85, 0.15, 0.15)
                f.lootBtn.tag:SetText(RED .. L["not worth it"] .. "|r")
            end
        else
            f.lootBtn.SetBorder(0.3, 0.3, 0.3)
            f.lootBtn.tag:SetText("")
        end

        -- What the player is actually looking at right now: both shown slots,
        -- their position in the list, and the verdict each one was given. This is
        -- the line that explains a screenshot after the fact.
        dbg("dialog render:",
            (f.preview and "[preview]" or "[live]"),
            "junk", idxFor("junk") .. "/" .. #jl, "=", RecTag(f.junkBtn.rec),
            "| other", idxFor("other") .. "/" .. #ol, "=", RecTag(f.otherBtn.rec),
            "| loot worth=" .. tostring(f.lworth or 0) .. "c",
            "cheapest=" .. (lo < math.huge and (lo .. "c") or "none"),
            "| verdict=" .. (f.lootBtn.tag:GetText() or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""),
            "| recommend=" .. ((best == f.junkBtn) and "junk" or "other") ..
            (questLoot and " (quest: no candidate marked too expensive)" or ""))
    end

    f.Step = function(which, dir)
        local from = idxFor(which)
        local i, n = from + dir, #listFor(which)
        if i < 1 or i > n then
            dbg("page:", which, "blocked at", from .. "/" .. n, "(dir " .. dir .. ")")
            return                                           -- hard stops, no wrap-around
        end
        if which == "junk" then f.junkIdx = i else f.otherIdx = i end
        dbg("page:", which, from .. " ->", i .. "/" .. n)
        f.RenderCandidates()
    end

    -- Bags changed under an open dialog: rebuild both lists so the records cannot
    -- go stale, keeping your position where it still exists.
    -- Runs in preview too. Only the loot item on the left is a fixed snapshot
    -- (re-rolling it on every bag change would be unusable); the candidates are
    -- live, so ignoring an item elsewhere drops it out of the preview as well.
    f.SyncLists = function()
        local beforeJ, beforeO = f.junkIdx or 1, f.otherIdx or 1
        local _, _, jl, ol = LootClearCandidates()
        f.junkList, f.otherList = jl or {}, ol or {}
        f.junkIdx  = math.max(1, math.min(f.junkIdx  or 1, #f.junkList))
        f.otherIdx = math.max(1, math.min(f.otherIdx or 1, #f.otherList))
        if f.junkIdx ~= beforeJ or f.otherIdx ~= beforeO then
            dbg("resync: position clamped, junk", beforeJ .. "->" .. f.junkIdx,
                "other", beforeO .. "->" .. f.otherIdx)
        else
            dbg("resync: lists rebuilt, position kept (junk " .. f.junkIdx .. ", other " .. f.otherIdx .. ")")
        end
        f.RenderCandidates()
    end

    -- Disarming on OnHide (rather than at the end of the preview call) means the
    -- flag is tied to the dialog's lifetime: Escape, the X, Cancel and
    -- CloseLootConfirm all clear it.
    f:SetScript("OnHide", function(self)
        dbg("dialog closed", self.preview and "(preview)" or "(live)")
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
local function ShowLootConfirm(lootLink, junkRec, otherRec, slot, preview, junkList, otherList, lootCount)
    local f = confirmFrame or BuildConfirm()
    f.slot = slot
    -- The frame is reused by the container path, which sets these. A loot dialog
    -- opening afterwards must not inherit them, or it would delete for a
    -- container that is long gone.
    f.clearAction, f.lootVerdict, f.hintAction = nil, nil, nil
    f.preview = preview and true or false
    previewMode = f.preview
    -- A preview is deliberately INDISTINGUISHABLE from the real dialog: same
    -- header, same hint line, no banner announcing itself. It exists to be looked
    -- at and photographed, and a warning stamped across it would be in every
    -- screenshot. It is still inert - the acting paths are all guarded - and the
    -- only place that says so is a chat line when you click something, which no
    -- screenshot of the dialog will contain.
    f:SetHeight(250)
    f.head:SetText(L["Bags full - click a junk/item to delete and loot:"])
    f.banner:SetText(GREY .. L["Arrows or mouse wheel over an icon: pick a different item"] .. "|r")
    f.banner:Show()

    local lname, _, _, _, _, _, _, _, _, ltex = GetItemInfo(lootLink)
    f.lootBtn.link = lootLink; f.lootBtn.itemID = nil
    f.lootBtn.icon:SetTexture(ltex)
    f.lootBtn.name:SetText(lname or "?")
    local lid = tonumber((lootLink or ""):match("item:(%d+)"))
    -- A loot slot can hold a stack, and the whole stack is what the bag slot buys
    -- you. Every number on this side is therefore a stack TOTAL, the same measure
    -- the candidates use - otherwise a stack of 5 would be judged as one item
    -- against a candidate's full stack and always look like a bad trade.
    local lcount = lootCount or 1
    -- NB: `lid and Worth(lid, n)` would truncate the multiple returns to one,
    -- so the worth has to be pulled inside the branch.
    local lworth, lvendor
    if lid then
        local total, vend = Worth(lid, lcount)
        lworth, lvendor = total, (vend or 0) * lcount
        if not lworth then                                   -- item info not cached yet
            local sell = select(11, GetItemInfo(lootLink)) or 0   -- 11 = sellPrice
            lworth, lvendor = sell * lcount, sell * lcount
        end
    end
    -- Vendor on top, AH underneath when Auctionator has a price. The verdict below
    -- still uses lworth (whichever basis the setting ranks on), so what decides and
    -- what is displayed stay independent.
    f.lootBtn.price:SetText((lvendor and ("|cffffffff" .. Coin(lvendor) .. "|r") or "") ..
        " " .. GREY .. "(x" .. lcount .. ")|r")
    local lahEach = lid and AHPrice(lid)
    local lah = lahEach and (lahEach * lcount)
    f.lootBtn.ah:SetText((lah and lah > 0) and (GREY .. L["AH:"] .. "|r " .. Coin(lah)) or "")

    -- Callers that have the ranked lists pass them; the single records stay the
    -- fallback, so a one-item list behaves exactly as before (arrows hidden).
    f.lid, f.lworth = lid, lworth
    f.junkList  = junkList  or (junkRec  and { junkRec })  or {}
    f.otherList = otherList or (otherRec and { otherRec }) or {}
    f.junkIdx, f.otherIdx = 1, 1        -- every dialog opens on the cheapest
    dbg("dialog open:", f.preview and "[preview]" or "[live]",
        "loot=" .. tostring(lname or lootLink), "id=" .. tostring(lid),
        "x" .. lcount, "worth=" .. tostring(lworth or 0) .. "c vendor=" .. tostring(lvendor or 0) .. "c",
        "ah=" .. tostring(lah or 0) .. "c",
        "| lists junk=" .. #f.junkList, "other=" .. #f.otherList,
        "| lootSlot=" .. tostring(slot),
        "| basis=" .. ((DB and DB.ahSuggest) and "AH" or "vendor"))
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
        print(GOLD .. "DGs Junk|r " .. L["preview: no usable items in your bags."])
        return
    end
    -- No substitutes for missing candidates: an empty slot now renders as
    -- "no junk" / "no normal item", which IS what the live dialog does, so the
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
    local pool, why = better, "worth more than both candidates"
    if #pool == 0 then
        pool = (#rest > 0) and rest or all
        why = "nothing in bags beats the candidates - plain item, expect a red verdict"
    end
    local pick = pool[math.random(#pool)]

    local link = select(2, GetItemInfo(pick.id))
    dbg("preview: scanned", #all, "bag items, pool", #pool, "(" .. why .. ")",
        "| picked", RecTag(pick),
        "| junk=" .. RecTag(junkRec), "| other=" .. RecTag(otherRec),
        "| lists junk=" .. #(junkList or {}), "other=" .. #(otherList or {}))
    ShowLootConfirm(link or ("item:" .. pick.id), junkRec, otherRec, nil, true, junkList, otherList, pick.count)
end

-- Is a PREVIEW dialog currently up? A real full-bags dialog does not count - the
-- Debug button must never offer to close a live one.
local function PreviewShown()
    return (confirmFrame and confirmFrame:IsShown() and confirmFrame.preview) and true or false
end

local function PreviewToggle()
    if PreviewShown() then
        dbg("preview: toggled off")
        confirmFrame:Hide()          -- OnHide disarms the flag and syncs the button
    else
        dbg("preview: toggled on")
        PreviewLootConfirm()
        if PreviewBtnSync then PreviewBtnSync() end
    end
end

local hookedButtons = {}
------------------------------------------------ container assist (full bags)
-- Right-clicking a clam, lockbox or pack with full bags is refused with
-- "Inventory is full" and nothing else happens: no suggestion of what to
-- destroy, no verdict on what would have arrived. That is the same decision the
-- loot dialog already solves, so this reaches it from a container.
--
-- There is no pre-click hook on a bag item, and Bagnon owns the bag buttons, so
-- the flow is necessarily: fail -> dialog -> free a slot -> open again. The
-- failure IS the trigger. Two independent facts identify the container without
-- ever guessing at it:
--   * hooksecurefunc on UseContainerItem records which bag slot was just used
--     (Blizzard's own bag buttons and Bagnon's both route through it), and
--   * UI_ERROR_MESSAGE / ERR_INV_FULL says that use was refused for space.
-- Only when both land within a second of each other do we say anything.
local CONTAINER_USE_WINDOW = 1.5      -- seconds a use stays "the thing that just failed"
local CONTAINER_DIFF_WINDOW = 6       -- how long after our open a bag change counts as its contents
local lastUse                         -- { bag, slot, id, t } of the most recent player-driven use
local pendingOpen, bagSnapshot        -- armed while we wait for a container's contents
-- (suppressUseHook is declared at the top: auto-sell sets it, and that runs first)

-- Item counts across the normal bags, keyed by item id. Diffing two of these is
-- the only reliable way to see what a container put into the bags: contents that
-- land directly (clams, most packs) fire no loot event at all, and CHAT_MSG_LOOT
-- would be locale fragile and misses stacks merging into ones you already carry.
local function BagCounts()
    local t = {}
    for bag = BACKPACK_CONTAINER, NUM_BAG_FRAMES do
        for slot = 1, (GetContainerNumSlots(bag) or 0) do
            local id = GetContainerItemID(bag, slot)
            if id then t[id] = (t[id] or 0) + (SlotCount(bag, slot) or 1) end
        end
    end
    return t
end

local function RecordUse(bag, slot)
    if suppressUseHook then return end
    if type(bag) ~= "number" or type(slot) ~= "number" then return end
    local id = GetContainerItemID(bag, slot)
    -- The hook runs after the call but before the server answers, so the item is
    -- still sitting in the slot - which is exactly what we need to name it.
    if not id then return end
    lastUse = { bag = bag, slot = slot, id = id, t = GetTime() }
    -- Logged even though most uses are not containers at all: if a right-click
    -- ever fails to reach this hook, its ABSENCE here is the only evidence, and
    -- an absent line is only readable when the present ones are reliable.
    dbg("use: item", id, "at bag", bag, "slot", slot)
end
if C_Container and C_Container.UseContainerItem then
    hooksecurefunc(C_Container, "UseContainerItem", RecordUse)
elseif _G.UseContainerItem then
    hooksecurefunc("UseContainerItem", RecordUse)
end

local function OpenContainer(cont)
    -- Bags shuffle. Opening by stale coordinates would use whatever landed there
    -- instead, and "it used my scroll" is not a mistake this addon gets to make.
    if GetContainerItemID(cont.bag, cont.slot) ~= cont.id then
        dbg("container: bag", cont.bag, "slot", cont.slot, "no longer holds", cont.id, "- not opening")
        print(GOLD .. "DGs Junk|r " .. L["that container is gone - nothing was opened."])
        return
    end
    bagSnapshot = BagCounts()
    pendingOpen = { id = cont.id, t = GetTime() }
    dbg("container: opening", cont.id, "at bag", cont.bag, "slot", cont.slot)
    -- Deliberately NOT suppressed from the use hook: if the contents need more
    -- than the one slot we just freed, the second refusal re-arms the whole flow
    -- and the player is simply asked once more. That is the multi-delete case,
    -- and it costs nothing but letting our own call be recorded.
    pcall(UseContainerItem, cont.bag, cont.slot)
end

-- Deleting is a server round trip, and a non-gray delete puts Blizzard's own
-- confirm in between, so there is no fixed delay that is right. Wait for the
-- slot to actually exist instead, and give up rather than open into full bags.
local function OpenWhenRoom(cont, tries)
    tries = (tries or 0) + 1
    if not BagsFull() then
        -- How long the slot took to appear separates "the delete was instant"
        -- from "Blizzard's confirm popup sat in the way", which look identical
        -- from the outside and fail differently.
        dbg("container: slot free after", tries, "check(s) - opening")
        OpenContainer(cont)
        return
    end
    if tries > 12 or not C_Timer then                       -- ~3s
        dbg("container: no slot freed after", tries, "tries - giving up")
        print(GOLD .. "DGs Junk|r " .. L["no slot was freed - the container was not opened."])
        return
    end
    C_Timer.After(0.25, function() OpenWhenRoom(cont, tries) end)
end

local function DoContainerClear(rec, cont)
    if not rec or not cont then return end
    if previewMode then dbg("preview: container-clear suppressed"); return end
    -- Destroying the container in order to open it is not a trade anyone wants.
    if rec.bag == cont.bag and rec.slot == cont.slot then
        dbg("container-clear aborted: the candidate IS the container")
        return
    end
    if GetContainerItemID(cont.bag, cont.slot) ~= cont.id then
        dbg("container-clear aborted: container", cont.id, "left bag", cont.bag, "slot", cont.slot)
        print(GOLD .. "DGs Junk|r " .. L["that container is gone - nothing was opened."])
        return
    end
    DeleteRecord(rec, "cleared to open:")
    OpenWhenRoom(cont)
    if C_Timer then C_Timer.After(0.6, Update) end
end

-- Candidates minus one exact bag slot: the container being opened is in the bags
-- too, and if it is a gray it would otherwise be offered as the thing to delete.
-- Only that one slot is dropped - deleting your second clam to open your first
-- is a perfectly good trade.
local function WithoutSlot(list, bag, slot)
    local out = {}
    for _, rec in ipairs(list or {}) do
        if not (rec.bag == bag and rec.slot == slot) then out[#out + 1] = rec end
    end
    return out
end

local function ShowContainerConfirm(cont, junkList, otherList, preview)
    local link = select(2, GetItemInfo(cont.id)) or L["this item"]
    ShowLootConfirm(link, junkList[1], otherList[1], nil, preview, junkList, otherList, 1)
    local f = confirmFrame
    f.head:SetText(L["Bags full - click a junk/item to delete, then it opens:"])
    -- No worth is known for what is inside, so nothing on this dialog may claim
    -- one: the left-hand verdict says so, and clearing lworth stops the
    -- candidates being painted red against the wrapper's own vendor price.
    f.lworth = nil
    f.lootVerdict = L["contents unknown"]
    f.hintAction = L["delete this and open"]
    f.clearAction = function(rec) DoContainerClear(rec, cont) end
    f.RenderCandidates()
end

local function InvFullError()
    if DB and DB.containerAssist == false then return end
    if previewMode then return end
    local u = lastUse
    if not u or (GetTime() - u.t) > CONTAINER_USE_WINDOW then
        dbg("inv-full: no bag item was used just now - not ours")
        return
    end
    if GetContainerItemID(u.bag, u.slot) ~= u.id then
        dbg("inv-full: bag", u.bag, "slot", u.slot, "no longer holds", u.id, "- ignoring")
        return
    end
    -- A loot window is open, so nothing was refused for want of a slot: the
    -- container DID open and it is auto-loot that could not fit. Two things make
    -- this indistinguishable from a real failure without the check - the error is
    -- the same, and a loot-window container is not consumed until its contents
    -- are taken, so it is still sitting in the bag slot the guard above accepts.
    -- The loot path owns this case; it already judges and tints every row.
    if (GetNumLootItems and GetNumLootItems() or 0) > 0 then
        dbg("inv-full: a loot window is open - this is auto-loot, not a container that failed to open")
        return
    end
    if confirmFrame and confirmFrame:IsShown() then
        dbg("inv-full: dialog already open - ignoring")
        return
    end
    -- The server said the inventory is full, and the server is the authority
    -- here: BagsFull() is only logged, never used to overrule it (a free slot in
    -- a profession bag is not a slot a clam's contents can use).
    local _, _, junkList, otherList = LootClearCandidates()
    junkList  = WithoutSlot(junkList,  u.bag, u.slot)
    otherList = WithoutSlot(otherList, u.bag, u.slot)
    dbg("inv-full: container", u.id, "at bag", u.bag, "slot", u.slot,
        "| BagsFull()=" .. tostring(BagsFull()),
        "| junk=" .. #junkList, "other=" .. #otherList)
    if #junkList == 0 and #otherList == 0 then
        dbg("inv-full: nothing deletable - no dialog")
        print(GOLD .. "DGs Junk|r " .. L["your bags are full and there is nothing cheap enough to delete."])
        return
    end
    ShowContainerConfirm({ bag = u.bag, slot = u.slot, id = u.id }, junkList, otherList)
end

-- Debug: the container dialog without first filling the bags to exactly zero
-- free slots and then finding a clam. It dresses the live dialog through the
-- very same call InvFullError() makes, so what you are looking at is the real
-- thing; only previewMode (set by ShowLootConfirm) keeps the clicks inert.
local function PreviewContainerConfirm()
    local _, _, junkList, otherList = LootClearCandidates()
    -- Any bag item stands in for the container: the dialog never looks inside
    -- one, it only shows its name, icon and vendor price.
    local cont
    for bag = BACKPACK_CONTAINER, NUM_BAG_FRAMES do
        for slot = 1, (GetContainerNumSlots(bag) or 0) do
            local id = GetContainerItemID(bag, slot)
            local head = (junkList[1] and junkList[1].bag == bag and junkList[1].slot == slot)
                      or (otherList[1] and otherList[1].bag == bag and otherList[1].slot == slot)
            if id and not head and not cont then cont = { bag = bag, slot = slot, id = id } end
        end
    end
    if not cont then
        print(GOLD .. "DGs Junk|r " .. L["preview: no usable items in your bags."])
        return
    end
    dbg("preview: container dialog, standing in for a container:", cont.id,
        "at bag", cont.bag, "slot", cont.slot,
        "| junk=" .. #junkList, "other=" .. #otherList)
    ShowContainerConfirm(cont, WithoutSlot(junkList, cont.bag, cont.slot),
                               WithoutSlot(otherList, cont.bag, cont.slot), true)
end

-- A container that opens a LOOT WINDOW has put nothing in the bags, and the loot
-- path takes over from here. Disarming means a later bag change - looting it,
-- picking anything else up - is never reported as this container's contents. The
-- log line also answers the question a test session actually has about a given
-- container: which of the two kinds is it?
local function ContainerOpenedLootWindow()
    -- If this window came out of a bag item, that item is the loot's source and
    -- has to be taken off the table until the window closes: it is still sitting
    -- in the bag (a container is consumed only once its contents are taken), it
    -- is the cheapest thing there by construction, and destroying it would take
    -- the loot with it. Recorded from the same use hook the assist runs on.
    --
    -- Note it is only taken off the DELETE list, not treated as free room. The
    -- slot it occupies does come back the moment the loot is taken, so it looks
    -- like the contents could simply move into it - but the server grants the
    -- item before consuming the container, so looting into otherwise full bags
    -- fails with the same error (verified in game, 1.15.9). The advice to free
    -- an unrelated slot is therefore correct, not over-cautious.
    local u = lastUse
    if u and (GetTime() - u.t) <= CONTAINER_USE_WINDOW and GetContainerItemID(u.bag, u.slot) == u.id then
        lootSource = { bag = u.bag, slot = u.slot, id = u.id }
        dbg("loot source: item", u.id, "at bag", u.bag, "slot", u.slot,
            "- not offered while its loot window is open")
    end

    -- A container dialog still on screen is now provably wrong: the container it
    -- offers to make room for is open, its contents are in the loot window, and
    -- clicking would destroy something and then re-use an already-opened item.
    -- This is the other half of the loot-window guard in InvFullError, for the
    -- ordering where the refusal arrives before there is a window to see.
    if confirmFrame and confirmFrame:IsShown() and confirmFrame.clearAction and not confirmFrame.preview then
        dbg("container: loot window opened - the container did open, closing the container dialog")
        confirmFrame.clearAction = nil        -- CloseLootConfirm() steps aside for container dialogs
        confirmFrame:Hide()
    end
    if not pendingOpen then return end
    dbg("container:", pendingOpen.id, "opened a loot window - the loot path takes it from here")
    pendingOpen, bagSnapshot = nil, nil
end

-- What actually arrived. Only runs while an open of ours is armed, and only for
-- contents that landed straight in the bags: anything that opens a loot window
-- goes through the loot path instead, which already tints and judges every row.
local function ContainerContentsVerdict()
    if not (pendingOpen and bagSnapshot) then return end
    if (GetTime() - pendingOpen.t) > CONTAINER_DIFF_WINDOW then
        dbg("container: nothing landed in the bags within", CONTAINER_DIFF_WINDOW .. "s (loot window?)")
        pendingOpen, bagSnapshot = nil, nil
        return
    end
    local now, lines, total = BagCounts(), {}, 0
    for id, n in pairs(now) do
        local gained = n - (bagSnapshot[id] or 0)
        -- The container itself is consumed by opening: that is a loss, and a
        -- container that yields more of itself is not worth the special case.
        if gained > 0 and id ~= pendingOpen.id then
            local value = Worth(id, gained) or 0
            total = total + value
            local link = select(2, GetItemInfo(id)) or fmt(L["Item #%d"], id)
            lines[#lines + 1] = link .. ((gained > 1) and (" x" .. gained) or "") ..
                " " .. GREY .. "(" .. Coin(value) .. ")|r"
        end
    end
    -- The container leaving its own slot is a bag change too, so an empty diff is
    -- normal and we keep waiting. Said once per open: on every bag update it
    -- would bury the line that matters.
    if #lines == 0 then
        if not pendingOpen.waited then
            pendingOpen.waited = true
            dbg("container: bags changed, nothing new in them yet - still waiting")
        end
        return
    end
    pendingOpen, bagSnapshot = nil, nil
    print(GOLD .. "DGs Junk|r " .. fmt(L["opened: %s"], table.concat(lines, ", ")) ..
        " " .. GREY .. "= " .. Coin(total) .. "|r")
    dbg("container diff:", #lines, "item(s), total", total .. "c",
        "| basis=" .. ((DB and DB.ahSuggest) and "AH" or "vendor"))
end

local function LootAssistClick(self)
    if DB and DB.lootAssist == false then return end
    if not IsShiftKeyDown() then return end
    local slot = self.slot or (self.GetID and self:GetID())
    if not slot then return end
    if not (LootSlotHasItem and LootSlotHasItem(slot)) then return end
    -- Group loot: a green or better under a roll is locked until the roll ends,
    -- and stays locked if you lose. Offering to destroy something of yours to make
    -- room for an item you may never receive is the worst advice this addon could
    -- give, so say why and stop.
    if LootSlotLocked(slot) then
        dbg("loot-assist: slot", slot, "locked - roll in progress or not eligible, no dialog")
        print(GOLD .. "DGs Junk|r " .. L["that item is still being rolled for - nothing to clear yet."])
        return
    end
    -- Logged from here on: every earlier return is "not our business at all"
    -- (no shift, no slot, empty slot), but from here the addon made a judgement
    -- and the log should say which one, including the times it did nothing.
    if not BagsFull() then dbg("loot-assist: slot", slot, "- bags not full, no dialog"); return end
    -- stacks into a partial stack you already carry -> no slot needed, no dialog
    local lid = GetLootSlotLink and linkID(GetLootSlotLink(slot))
    local need = (GetLootSlotInfo and select(3, GetLootSlotInfo(slot))) or 1
    if lid and StackRoom(lid) >= need then
        dbg("loot-assist: item", lid, "stacks into existing stack (room",
            StackRoom(lid), ">= needed", need .. ") - no clear needed")
        return
    end
    local junkRec, otherRec, junkList, otherList = LootClearCandidates()
    if not junkRec and not otherRec then dbg("loot-assist: bags full, nothing deletable to clear"); return end
    local lootLink = (GetLootSlotLink and GetLootSlotLink(slot)) or L["this item"]
    dbg("loot-assist: slot", slot, "item", tostring(lid),
        "| junk=" .. RecTag(junkRec), "| other=" .. RecTag(otherRec))
    -- the pick-an-item dialog IS the confirm (choose which to delete, or Cancel)
    ShowLootConfirm(lootLink, junkRec, otherRec, slot, nil, junkList, otherList, need)
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
                local qty = LootSlotQuantity(slot)
                if LootSlotLocked(slot) then
                    id = nil        -- under a roll: no verdict, the choice is not yours
                end
                if id and StackRoom(id) >= qty then
                    -- stacks onto what you already carry: costs no slot, no verdict
                    id = nil
                end
                if id and IsQuestItem(id) then
                    tint:SetColorTexture(0.15, 0.95, 0.25, 1); tint:Show()
                elseif id then
                    -- The looted STACK is what you get for the slot, so a stack of
                    -- 5 is worth five times one. Comparing one unit against a
                    -- candidate's full stack value would understate the loot.
                    local lootWorth = select(1, Worth(id, qty))
                    if lootWorth then
                        if lootWorth > lo then tint:SetColorTexture(0.15, 0.95, 0.25, 1)
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
    print(GOLD .. "DGs Junk|r " ..
        fmt(L["copied %s into this character's profile."], "|cffffffff" .. L["Default"] .. "|r"))
end

-- This character -> Default. Stays on the character profile afterwards.
local function ProfileCopyToMain()
    local k = EnsureOwnProfile()
    CopyLists(DB.profiles[k], DB.profiles.Main)
    act("profile copy", nil, k .. " -> Default")
    AfterProfileSwitch()
    print(GOLD .. "DGs Junk|r " ..
        fmt(L["copied this character's profile into %s."], "|cffffffff" .. L["Default"] .. "|r"))
end

-- Bind this character to a profile by name ("Main" or its own key).
local function ProfileSwitchTo(name)
    local k = EnsureOwnProfile()
    DB.chars[k] = (name == "Main") and "Main" or k
    act("profile switch", nil, "now on " .. DB.chars[k])
    AfterProfileSwitch()
    print(GOLD .. "DGs Junk|r " .. fmt(L["now using the %s profile."],
        (name == "Main" and "|cffffffff" .. L["Default"] .. "|r"
                        or "|cffffffff" .. (UnitName("player") or k) .. "|r")))
end

StaticPopupDialogs["DGSJUNK_PROFILE_ACTION"] = {
    text = "|cffffcc55DGs Junk|r\n\n" .. L["This will %s."] .. "\n\n" .. L["Continue?"],
    button1 = YES,
    button2 = NO,
    OnAccept = function(self) if type(self.data) == "function" then self.data() end end,
    timeout = 0, whileDead = true, hideOnEscape = true, showAlert = true, preferredIndex = 3,
}

-- A language change cannot be applied live, so the picker offers to do the
-- reload for us. Reloading is the player's call and never a side effect of
-- clicking a dropdown entry: nothing is stored until this is accepted, so
-- cancelling leaves the setting exactly as it was.
StaticPopupDialogs["DGSJUNK_CONFIRM_LANG"] = {
    text = "|cffffcc55DGs Junk|r\n\n" .. L["Switch the addon language to %s?"] .. "\n\n" ..
           L["Your interface will be reloaded."],
    button1 = L["Reload now"],
    button2 = CANCEL,
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
ev:RegisterEvent("UI_ERROR_MESSAGE")
ev:SetScript("OnEvent", function(_, event, arg1, arg2)
    if event == "UI_ERROR_MESSAGE" then
        -- (errorType, message). The numeric type shifts between builds, so the
        -- global string is what we match; it is already in the client's locale.
        local msg = arg2 or arg1
        if msg == ERR_INV_FULL then
            InvFullError()
        elseif lastUse and (GetTime() - lastUse.t) <= CONTAINER_USE_WINDOW then
            -- A refusal right after a bag click that we did NOT recognise. Worth
            -- a log line: if a container ever fails with a different message,
            -- this is the only place it would show up.
            dbg("ui-error after a bag use, not ERR_INV_FULL:", tostring(msg))
        end
        return
    end
    if event == "LOOT_OPENED" then
        -- Unconditional, unlike the per-button hook lines, which only appear the
        -- first time each button is seen: without this a loot window that opened
        -- for the second time leaves no trace at all.
        dbg("loot window opened:", (GetNumLootItems and GetNumLootItems()) or 0, "item(s)")
        ContainerOpenedLootWindow()
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
        if lootSource then
            dbg("loot source: cleared (loot window closed)")
            lootSource = nil          -- the container is deletable again, or already gone
        end
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
    if event == "BAG_UPDATE_DELAYED" then
        ContainerContentsVerdict()    -- no-op unless we opened something just now
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
        -- SavedVariables are not reliably populated while this file's chunk runs,
        -- so PickLocale() may have missed a stored override. Re-apply it now that
        -- DB definitely exists: everything built lazily from here on (the settings
        -- window, the comparison dialog) comes out in the right language straight
        -- away, and only the few labels built at file scope stay behind until the
        -- /reload the picker asks for. Without this the override would need two
        -- reloads to show up, which reads as "the setting does not work".
        if (DB.locale or GetLocale()) ~= activeLocale then
            activeLocale = DB.locale or GetLocale()
            for k in pairs(L) do L[k] = nil end          -- raw keys only; the fallback lives on the metatable
            for k, v in pairs(locales[activeLocale] or {}) do L[k] = v end
            localeStale = true                            -- file-scope labels are still in the old language
        end
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
        if DB.containerAssist == nil then DB.containerAssist = true end   -- full-bag container opening
        if DB.devMode == nil then DB.devMode = false end         -- Debug tab is hidden until /dgjunk dev
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
    if not name then return "|cff999999" .. fmt(L["Item #%d"], id) .. "|r", nil end
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
    text = "|cffffcc55DGs Junk|r\n\n%s\n\n" .. L["This cannot be undone."],
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
        print(GOLD .. "DGs Junk|r " .. fmt(L["nothing to reset for %s"], label))
        return
    end
    -- Singular and plural are separate keys rather than an "s" glued on: German
    -- inflects the noun, not just its ending.
    StaticPopup_Show("DGSJUNK_CONFIRM_RESET",
        fmt(n == 1 and L["Remove %d item from %s?"] or L["Remove %d items from %s?"], n, label),
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
    text = "|cffffcc55DGs Junk|r\n\n" .. L["Unmark %s as junk?"],
    button1 = YES,
    button2 = NO,
    OnAccept = function(self) if type(self.data) == "function" then self.data() end end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

StaticPopupDialogs["DGSJUNK_CONFIRM_UNMARK_ALL"] = {
    text = "|cffffcc55DGs Junk|r\n\n%s\n\n" .. L["Your items are not touched, only the marks."],
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
    print(GREEN .. "DGs Junk|r " .. fmt(n == 1 and L["unmarked %d item"] or L["unmarked %d items"], n))
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
    if n == 0 then print(GOLD .. "DGs Junk|r " .. L["nothing marked as junk"]); return end
    StaticPopup_Show("DGSJUNK_CONFIRM_UNMARK_ALL",
        fmt(n == 1 and L["Unmark all %d item marked as junk?"]
                    or L["Unmark all %d items marked as junk?"], n),
        nil, ClearAllMarks)
end

StaticPopupDialogs["DGSJUNK_CONFIRM_UNIGNORE"] = {
    text = "|cffffcc55DGs Junk|r\n\n" .. L["Remove %s from the ignore list?"],
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
        else GameTooltip:SetText(select(1, ItemName(id)) or fmt(L["item %d"], id)) end
        GameTooltip:AddLine(GREY .. action .. " |cff888888(" .. L["shift-click: no confirm"] .. ")|r", 0.6, 0.6, 0.6, true)
        GameTooltip:Show()
    end)
    frame:SetScript("OnLeave", GameTooltip_Hide)
end

-- There is no automatic layout in this UI: nothing resizes a button to its
-- caption, and a fixed width that suits English silently clips or overlaps in
-- any longer language. So every button measures its own label and the widths
-- below are MINIMUMS, not fixed sizes.
local BTN_PAD  = 26     -- breathing room either side of the caption
local BTN_H    = 22
-- Window width. Five tabs share this row, and the widest caption in any language
-- decides how tight they look: "Einstellungen" needs noticeably more than
-- "Settings", so the window is sized for the long case rather than the English one.
local CONFIG_W = 580                    -- settings window width
local PANEL_W  = CONFIG_W - 16          -- its panels are inset 8px either side
local SCROLL_W = PANEL_W - 30           -- panels lose 4px left and 26px to the scrollbar

local function FitButton(btn, minW, pad)
    local fs = btn:GetFontString()
    local w = fs and fs:GetStringWidth() or 0
    btn:SetWidth(math.max(minW or 0, math.ceil(w) + (pad or BTN_PAD)))
    return btn
end

local function ConfigBtn(parent, text, w, onClick)
    local btn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    btn:SetSize(w or 90, BTN_H)
    btn:SetText(text)
    btn:SetScript("OnClick", onClick)
    FitButton(btn, w or 90)
    return btn
end

-- A row of buttons that must share one line. Each is fitted to its caption; if
-- the row still would not fit, the padding is squeezed (down to a floor) before
-- anything is allowed to overlap its neighbour.
local function FitRow(buttons, available, gap)
    local function total(pad)
        local sum = 0
        for _, b in ipairs(buttons) do
            FitButton(b, 0, pad)
            sum = sum + b:GetWidth()
        end
        return sum + gap * (#buttons - 1)
    end
    local pad = BTN_PAD
    while total(pad) > available and pad > 8 do pad = pad - 2 end
end

-- Wrapping description line pinned to the top of a panel. Returns the height it
-- actually occupies, so whatever follows can be anchored below it instead of at
-- a guessed offset that only holds for English.
local function PanelHint(panel, width, text)
    local fs = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    fs:SetPoint("TOPLEFT", 4, -2)
    fs:SetWidth(width - 8)
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(true)
    fs:SetText(text)
    return fs, math.ceil(fs:GetStringHeight()) + 6
end

local RefreshLog  -- fwd

BuildConfig = function()
    config = CreateFrame("Frame", "DGsJunkConfig", UIParent, "BasicFrameTemplateWithInset")
    -- Height is a starting point only: the Settings panel measures its own
    -- content at the end of this function and grows the window if it needs more.
    config:SetSize(CONFIG_W, 740)
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
    -- First entry of each pair is the panel key (internal, never translated);
    -- the second is the visible tab label.
    local order = { { "settings", L["Settings"] }, { "ignored", L["Ignored"] }, { "junk", L["Junk"] },
                    { "debug", L["Debug"] }, { "log", L["Log"] } }
    for _, t in ipairs(order) do
        local b = ConfigBtn(config, t[2], 90, function() ShowTab(t[1]) end)
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

    -- Tabs are laid out from the ones actually on show, so hiding Debug closes
    -- the gap instead of leaving a hole, and the remaining tabs share the width.
    config.LayoutTabs = function()
        local visible = {}
        for _, t in ipairs(order) do
            local show = (t[1] ~= "debug") or (DB and DB.devMode)
            config.tabBtns[t[1]]:SetShown(show)
            if show then visible[#visible + 1] = t[1] end
        end
        local w = math.floor((PANEL_W - (#visible - 1) * 4) / #visible)
        for i, name in ipairs(visible) do
            local b = config.tabBtns[name]
            b:SetWidth(w)
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", 8 + (i - 1) * (w + 4), -52)
        end
        -- Leaving dev mode while sitting on the Debug tab would strand the window
        -- on a hidden panel.
        if not (DB and DB.devMode) and config.panels.debug:IsShown() then ShowTab("settings") end
    end

    --====================== IGNORED panel ======================--
    local ip = config.panels.ignored
    local _, hintH = PanelHint(ip, PANEL_W, L["Ignored items - add via shift-right-click or right-click > Ignore"])

    local scroll = CreateFrame("ScrollFrame", "DGsJunkConfigScroll", ip, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 4, -(2 + hintH))
    scroll:SetPoint("BOTTOMRIGHT", -26, 64)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(SCROLL_W, 1)
    scroll:SetScrollChild(content)
    config.content = content
    config.rows = {}

    -- The category strings passed to ResetIgnores/ConfirmReset ("junk", "normal",
    -- "all") are stored values and stay English; only the label beside them is
    -- translated, because that is what ends up in the confirm text.
    local rj = ConfigBtn(ip, L["Reset Junk"],   0, function()
        if IsShiftKeyDown() then ResetIgnores("junk") else ConfirmReset("junk", L["ignored Junk"]) end
    end)
    rj:SetPoint("BOTTOMLEFT", 4, 4)
    BtnHint(rj, L["Reset ignored Junk"], L["Shift-click to skip the confirm."])
    local rn = ConfigBtn(ip, L["Reset Normal"], 0, function()
        if IsShiftKeyDown() then ResetIgnores("normal") else ConfirmReset("normal", L["ignored Normal"]) end
    end)
    rn:SetPoint("LEFT", rj, "RIGHT", 4, 0)
    BtnHint(rn, L["Reset ignored Normal"], L["Shift-click to skip the confirm."])
    local ra = ConfigBtn(ip, L["Reset All"],    0, function()
        if IsShiftKeyDown() then ResetIgnores(nil) else ConfirmReset("all", L["the whole ignore list"]) end
    end)
    ra:SetPoint("LEFT", rn, "RIGHT", 4, 0)
    BtnHint(ra, L["Reset the whole ignore list"], L["Shift-click to skip the confirm."])
    -- All three sit on one line and chain off each other, so their widths decide
    -- both the overlap and the gaps: fit them together against the panel width.
    FitRow({ rj, rn, ra }, PANEL_W - 8, 4)

    --====================== JUNK panel ======================--
    local jp = config.panels.junk
    local _, jhintH = PanelHint(jp, PANEL_W,
        L["Items you marked as junk that are in your bags - X unmarks them, nothing is deleted"])

    local jscroll = CreateFrame("ScrollFrame", "DGsJunkClearScroll", jp, "UIPanelScrollFrameTemplate")
    jscroll:SetPoint("TOPLEFT", 4, -(2 + jhintH))
    jscroll:SetPoint("BOTTOMRIGHT", -26, 36)
    local jcontent = CreateFrame("Frame", nil, jscroll)
    jcontent:SetSize(SCROLL_W, 1)
    jscroll:SetScrollChild(jcontent)
    config.junkContent = jcontent
    config.junkRows = {}

    local jempty = jp:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    jempty:SetPoint("TOPLEFT", 8, -(6 + jhintH))     -- below the hint, however tall it wrapped
    jempty:SetText(GREY .. L["No marked junk in your bags."] .. "|r")
    config.junkEmpty = jempty

    local jca = ConfigBtn(jp, L["Clear all junk"], 0, function()
        if IsShiftKeyDown() then ClearAllMarks() else ConfirmClearAll() end
    end)
    jca:SetPoint("BOTTOMLEFT", 4, 4)
    BtnHint(jca, L["Unmark everything you marked as junk"], L["Shift-click to skip the confirm."])
    config.junkClearAll = jca

    --====================== SETTINGS panel ======================--
    local sp = config.panels.settings
    -- enableFn (optional) is re-evaluated on every Refresh, so a checkbox can go
    -- live when its dependency loads after us. offTip shows while disabled.
    -- `label`, `tip` and `offTip` arrive as ENGLISH keys and are translated here,
    -- at the point of display. That is deliberate: act() below logs the raw
    -- `label`, so the Log tab keeps naming settings in English no matter which
    -- client locale is running.
    -- Running vertical cursor. The description lines wrap, and how many lines
    -- they wrap to depends on the language, so no fixed set of offsets can be
    -- right for every locale: each row reports the height it actually used and
    -- the next one starts below that.
    local spY = -6

    local function Check(label, getFn, setFn, tip, enableFn, offTip)
        local cb = CreateFrame("CheckButton", nil, sp, "UICheckButtonTemplate")
        cb:SetPoint("TOPLEFT", 4, spY)
        local fs = cb:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        fs:SetPoint("LEFT", cb, "RIGHT", 2, 0)
        fs:SetText(L[label])
        cb:SetScript("OnClick", function(self)
            local v = self:GetChecked() and true or false
            setFn(v)
            act("setting", nil, label .. " = " .. tostring(v))
        end)
        local used = 28
        local d
        if tip then
            d = sp:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
            d:SetPoint("TOPLEFT", cb, "BOTTOMLEFT", 4, 2)
            d:SetWidth(PANEL_W - 20)                  -- explicit width so it wraps AND can be measured
            d:SetJustifyH("LEFT")
            d:SetWordWrap(true)
            -- Reserve the taller of the two texts. Refresh() swaps between them
            -- when Auctionator loads or goes missing, and a row that changed
            -- height at runtime would shove everything below it out of place.
            d:SetText(L[tip])
            local h = math.ceil(d:GetStringHeight())
            if offTip then
                d:SetText(L[offTip])
                h = math.max(h, math.ceil(d:GetStringHeight()))
                d:SetText(L[tip])
            end
            d:SetHeight(h)
            used = used + h + 6
        end
        spY = spY - used
        cb.Refresh = function()
            cb:SetChecked(getFn())
            if not enableFn then return end
            if enableFn() then
                cb:Enable()
                fs:SetTextColor(1, 0.82, 0)                    -- GameFontNormal yellow
                if d then d:SetText(L[tip]); d:SetTextColor(0.5, 0.5, 0.5) end
            else
                cb:Disable()
                fs:SetTextColor(0.5, 0.5, 0.5)
                if d then d:SetText(L[offTip or tip]); d:SetTextColor(0.9, 0.35, 0.35) end
            end
        end
        return cb
    end
    config.checks = {}
    config.checks.loot = Check("Loot-assist",
        function() return DB.lootAssist ~= false end,
        function(v) DB.lootAssist = v end,
        "Shift-click a loot item with full bags to choose what to delete, then loot it")
    config.checks.container = Check("Container assist",
        function() return DB.containerAssist ~= false end,
        function(v) DB.containerAssist = v end,
        "Opening a clam, box or pack with full bags offers what to delete, then opens it for you")
    config.checks.lootColor = Check("Colour loot rows",
        function() return DB.lootColor ~= false end,
        function(v) DB.lootColor = v; ColorLootRows() end,
        "Tints the loot window green (worth more than the cheapest thing you would delete) or red (skip it), only while your bags are full")
    config.checks.ah = Check("Suggest by AH prices",
        function() return DB.ahSuggest end,
        function(v) DB.ahSuggest = v; Update() end,
        "Rank by Auctionator AH value instead of vendor (falls back to vendor)",
        HasAuctionator,
        "Requires Auctionator (not installed / not detected) - ranking uses vendor prices")
    config.checks.show = Check("Show item frames",
        function() return DB.showFrames ~= false end,
        function(v) DB.showFrames = v; Update() end,
        "Master toggle - same as left-clicking the minimap icon")
    config.checks.always = Check("Always show item frames",
        function() return DB.alwaysShow end,
        function(v) DB.alwaysShow = v; Update() end,
        "Keep the icons visible even when there is nothing to delete")
    config.checks.minimap = Check("Show minimap icon",
        function() return DB.minimap ~= false end,
        function(v) DB.minimap = v; ApplyMinimap() end,
        "Minimap button: left-click show/hide frames, right-click settings")
    config.checks.autosell = Check("Auto-sell marked items at vendors",
        function() return DB.autoSell end,
        function(v) DB.autoSell = v end,
        "Sells only items YOU marked as junk and only above gray quality - grays are left to sell-all-junk")

    spY = spY - 10
    local rp = ConfigBtn(sp, L["Reset icon position"], 0, function()
        if DB then DB.pos = nil end
        junkIcon:ClearAllPoints()
        junkIcon:SetPoint("CENTER", 0, -140)
    end)
    rp:SetPoint("TOPLEFT", 8, spY)
    spY = spY - BTN_H - 26        -- the slider carries its label above the bar

    -- frame scale slider (50%..200%)
    local slider = CreateFrame("Slider", "DGsJunkScaleSlider", sp, "OptionsSliderTemplate")
    slider:SetPoint("TOPLEFT", 14, spY)
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
        if slabel then slabel:SetText(fmt(L["Frame scale: %d%%"], v * 100)) end
    end)
    slider.Refresh = function()
        slider:SetValue(DB.scale or 1)
        if slabel then slabel:SetText(fmt(L["Frame scale: %d%%"], (DB.scale or 1) * 100)) end
    end
    config.scaleSlider = slider
    spY = spY - 46                -- bar plus the 50%/200% end labels beneath it

    -- language, independent of the client's own locale
    local lhdr = sp:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    lhdr:SetPoint("TOPLEFT", 4, spY)
    lhdr:SetText(L["Language"])
    spY = spY - 24

    -- DB.locale = nil means "follow the client", which is the default; anything
    -- else is an explicit override that beats GetLocale() on the next load. It
    -- cannot apply live: every label in this file was built from L while the file
    -- ran, so the picker stores the choice and says a /reload is needed. enUS is
    -- stored explicitly rather than as nil, otherwise picking English on a German
    -- client would just mean "follow the client" again and stay German.
    local LANGS = {
        { key = false,  name = L["Automatic (game language)"] },
        { key = "enUS", name = L["English"] },
        { key = "deDE", name = "Deutsch" },   -- endonym: a German speaker looks for "Deutsch"
    }
    local lnote                                        -- fwd decl (the /reload hint)
    local function LangKey() return DB.locale or false end
    local function LangName(key)
        for _, e in ipairs(LANGS) do if e.key == key then return e.name end end
        return tostring(key)
    end
    -- Stored and applied in one go, straight from the popup's OnAccept. The
    -- setting is written first so it survives the reload that follows it.
    local function LangApply(key)
        DB.locale = key or nil
        act("setting", nil, "locale = " .. tostring(DB.locale or "auto"))
        ReloadUI()
    end
    local function LangSet(key)
        if key == LangKey() then return end          -- already on it: nothing to confirm
        -- Never reload out from under a fight. This addon is used on Hardcore,
        -- where a loading screen mid-combat can cost the character, so the answer
        -- is "later", not a reload the player did not think through.
        if InCombatLockdown() then
            print(GOLD .. "DGs Junk|r " .. L["not while you are in combat - try again afterwards."])
            if config.RefreshLang then config.RefreshLang() end
            return
        end
        StaticPopup_Show("DGSJUNK_CONFIRM_LANG", LangName(key), nil, function() LangApply(key) end)
        -- The click only opened a question. Nothing is stored yet, so the widget
        -- is put back on the current language until the popup is accepted.
        if config.RefreshLang then config.RefreshLang() end
    end
    local function BuildLangMenu(_, root)
        for _, e in ipairs(LANGS) do
            root:CreateRadio(e.name,
                function() return LangKey() == e.key end,
                function() LangSet(e.key) end)
        end
    end

    -- Same widget story as the profile picker below: the new DropdownButton when
    -- the client has it, a plain button plus context menu when it does not.
    local bLang
    local okL, ddL = pcall(CreateFrame, "DropdownButton", nil, sp, "WowStyle1DropdownTemplate")
    if okL and ddL and ddL.SetupMenu then
        ddL:SetSize(190, 24)
        ddL:SetupMenu(BuildLangMenu)
        bLang = ddL
        config.langIsDropdown = true
    else
        bLang = ConfigBtn(sp, fmt(L["Language: %s"], L["Automatic (game language)"]), 190, function(self)
            if MenuUtil and MenuUtil.CreateContextMenu then
                MenuUtil.CreateContextMenu(self, BuildLangMenu)
            else
                -- no menu API at all: cycle automatic -> English -> Deutsch -> automatic
                local nextKey = { [tostring(false)] = "enUS", enUS = "deDE", deDE = false }
                LangSet(nextKey[tostring(LangKey())])
            end
        end)
    end
    bLang:SetPoint("TOPLEFT", 6, spY)
    spY = spY - 28
    BtnHint(bLang, L["Addon language"],
        L["Automatic follows the game's language. Pick English or Deutsch to override it, whatever the client is set to. Changing it asks first, then reloads your interface."])
    config.langPick = bLang

    lnote = sp:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    lnote:SetPoint("TOPLEFT", 6, spY)
    lnote:SetWidth(PANEL_W - 20)
    lnote:SetJustifyH("LEFT"); lnote:SetWordWrap(true)
    config.langNote = lnote

    config.RefreshLang = function()
        if config.langPick then
            local label = LangName(LangKey())
            if config.langIsDropdown then
                config.langPick:SetDefaultText(label)
                if config.langPick.GenerateMenu then config.langPick:GenerateMenu() end
            else
                config.langPick:SetText(fmt(L["Language: %s"], label))
            end
        end
        if not config.langNote then return end
        -- Compare against the locale actually in use, not against the stored
        -- value: picking Automatic on a German client changes nothing when German
        -- is already what loaded, and asking for a reload there would be wrong.
        local effective = DB.locale or GetLocale()
        if localeStale or effective ~= activeLocale then
            config.langNote:SetText(GOLD .. L["Type /reload to apply the new language."] .. "|r")
        else
            config.langNote:SetText(L["The game's own language is used unless you override it here."])
        end
    end
    config.RefreshLang()
    -- Reserve the taller of the two notes: the hint swaps for the reload warning
    -- when you pick something, and a line that grew would shove the profile
    -- section below it out of place.
    local lnoteH = math.ceil(lnote:GetStringHeight())
    lnote:SetText(GOLD .. L["Type /reload to apply the new language."] .. "|r")
    lnoteH = math.max(lnoteH, math.ceil(lnote:GetStringHeight()))
    config.RefreshLang()
    lnote:SetHeight(lnoteH)
    spY = spY - lnoteH - 10

    -- character data profile (scopes the ignore list + junk marks only)
    local phdr = sp:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    phdr:SetPoint("TOPLEFT", 4, spY)
    phdr:SetText(L["Character profile"])
    spY = spY - 20
    local pstat = sp:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    pstat:SetPoint("TOPLEFT", 4, spY)
    pstat:SetPoint("RIGHT", sp, "RIGHT", -8, 0); pstat:SetJustifyH("LEFT")
    config.profileStatus = pstat
    spY = spY - 24

    -- Profile picker. 1.15.9 ships Blizzard's new dropdown widget
    -- (DropdownButton + WowStyle1DropdownTemplate + SetupMenu); the old
    -- UIDropDownMenuTemplate is gone. Fall back to a plain button + context menu
    -- if the template is ever missing.
    local function BuildProfileMenu(_, root)
        local k = CharKey()
        local me = UnitName("player") or k
        root:CreateRadio(L["Default (shared)"],
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
        bSwitch = ConfigBtn(sp, fmt(L["Profile: %s"], L["Default"]), 190, function(self)
            if MenuUtil and MenuUtil.CreateContextMenu then
                MenuUtil.CreateContextMenu(self, BuildProfileMenu)
            else
                ProfileSwitchTo(ActiveProfileName() == "Main" and CharKey() or "Main")
            end
        end)
    end
    bSwitch:SetPoint("TOPLEFT", 6, spY)
    spY = spY - 28
    BtnHint(bSwitch, L["Switch profile"], L["Default is shared by every character on it; the character profile is private. Both always exist, switching never deletes either."])
    config.profileSwitch = bSwitch

    -- Copy buttons only make sense on the character profile: on Default there is
    -- no second list to copy from or to, so they are hidden entirely.
    local bFrom = ConfigBtn(sp, L["Copy from Default"], 0, function()
        if IsShiftKeyDown() then ProfileCopyFromMain()
        else StaticPopup_Show("DGSJUNK_PROFILE_ACTION",
            L["replace this character's list with a copy of Default"], nil, ProfileCopyFromMain) end
    end)
    bFrom:SetPoint("TOPLEFT", 6, spY)
    BtnHint(bFrom, L["Pull Default into this character"], L["Overwrites this character's ignore list + junk marks. Shift-click skips confirm."])
    config.profileCopyFrom = bFrom

    local bTo = ConfigBtn(sp, L["Copy to Default"], 0, function()
        if IsShiftKeyDown() then ProfileCopyToMain()
        else StaticPopup_Show("DGSJUNK_PROFILE_ACTION",
            L["overwrite Default with this character's list"], nil, ProfileCopyToMain) end
    end)
    bTo:SetPoint("LEFT", bFrom, "RIGHT", 4, 0)
    BtnHint(bTo, L["Push this character into Default"], L["Overwrites the shared Default list for every character on it. Shift-click skips confirm."])
    config.profileCopyTo = bTo
    FitRow({ bFrom, bTo }, PANEL_W - 12, 4)
    spY = spY - BTN_H - 8

    local pdesc = sp:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    pdesc:SetPoint("TOPLEFT", 6, spY)
    pdesc:SetWidth(PANEL_W - 20)
    pdesc:SetJustifyH("LEFT"); pdesc:SetWordWrap(true)
    pdesc:SetText(L["Profiles scope only the ignore list and junk marks; every setting above is shared across your characters. \"Default\" is the shared list, every character on it sees the same entries."])
    spY = spY - math.ceil(pdesc:GetStringHeight()) - 8

    -- The window is sized to whatever the Settings tab actually needed. German
    -- descriptions wrap to two lines where English fits on one, so a height that
    -- is right for English cuts the profile section off in German.
    config:SetHeight(math.max(740, 78 + math.abs(spY) + 20))

    config.RefreshProfile = function()
        local name = ActiveProfileName()
        local onDefault = (name == "Main")
        -- Character name only, not the "Name - Realm" storage key: every profile
        -- you can pick here is on this realm, so the suffix is just noise.
        local me = UnitName("player") or name
        local text
        if onDefault then
            text = fmt(L["This character uses: %s"],
                GREEN .. L["Default"] .. "|r |cff888888(" .. L["shared list"] .. ")|r")
        else
            text = fmt(L["This character uses: %s"],
                GOLD .. me .. "|r |cff888888(" .. L["own list"] .. ")|r")
        end
        if config.profileStatus then config.profileStatus:SetText(text) end
        if config.profileTop then config.profileTop:SetText(text) end
        if config.profileSwitch then
            local label = onDefault and L["Default (shared)"] or me
            if config.profileIsDropdown then
                -- the widget derives its text from the selected radio entry
                config.profileSwitch:SetDefaultText(label)
                if config.profileSwitch.GenerateMenu then config.profileSwitch:GenerateMenu() end
            else
                config.profileSwitch:SetText(fmt(L["Profile: %s"], label))
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
    local dhint, dhintH = PanelHint(dp, PANEL_W,
        fmt(L["Open the addon's dialogs on demand, without having to fill your bags first. They use your real items and the real ranking; clicking anything in them does nothing - %s."],
            RED .. L["nothing is ever deleted"] .. "|r"))
    config.debugHint = dhint

    -- Sized for BOTH captions: the toggle swaps between them, and a button that
    -- resized under the cursor would be a moving target.
    local pv = ConfigBtn(dp, L["Hide comparison dialog"], 0, PreviewToggle)
    local pvW = pv:GetWidth()
    pv:SetText(L["Show comparison dialog"])
    pv:SetWidth(math.max(pvW, FitButton(pv, 0):GetWidth()))
    pv:SetPoint("TOPLEFT", 8, -(12 + dhintH))
    BtnHint(pv, L["Full-bags comparison dialog"],
        L["Picks a random bag item worth more than your two cheapest, so the \"worth it\" verdict shows. Also available as /dgjunk preview."])
    config.previewBtn = pv

    -- Single source of truth for the label: the dialog's own visibility. Closing
    -- it any way at all (X, Escape, Cancel) runs its OnHide, which calls this.
    PreviewBtnSync = function()
        if not (config and config.previewBtn) then return end
        config.previewBtn:SetText(PreviewShown() and L["Hide comparison dialog"] or L["Show comparison dialog"])
    end
    PreviewBtnSync()

    --====================== LOG panel ======================--
    local lp = config.panels.log

    -- Debug toggle lives here; everything below only shows while it is on.
    local dchk = CreateFrame("CheckButton", nil, lp, "UICheckButtonTemplate")
    dchk:SetPoint("TOPLEFT", 4, -2)
    local dlbl = dchk:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    dlbl:SetPoint("LEFT", dchk, "RIGHT", 2, 0)
    dlbl:SetText(L["Debug logging"])
    local ddesc = lp:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    ddesc:SetPoint("TOPLEFT", dchk, "BOTTOMLEFT", 4, 2)
    ddesc:SetWidth(PANEL_W - 20)
    ddesc:SetJustifyH("LEFT"); ddesc:SetWordWrap(true)
    ddesc:SetText(L["Record diagnostic messages here (never printed to chat)"])
    dchk.Refresh = function() dchk:SetChecked(DB and DB.debug) end
    config.checks.debug = dchk

    local lscroll = CreateFrame("ScrollFrame", "DGsJunkLogScroll", lp, "UIPanelScrollFrameTemplate")
    lscroll:SetPoint("TOPLEFT", 4, -(30 + math.ceil(ddesc:GetStringHeight())))
    lscroll:SetPoint("BOTTOMRIGHT", -26, 34)
    local edit = CreateFrame("EditBox", nil, lscroll)
    edit:SetMultiLine(true)
    edit:SetAutoFocus(false)
    edit:SetFontObject(ChatFontNormal)
    edit:SetWidth(SCROLL_W - 10)
    edit:SetScript("OnEscapePressed", function(s) s:ClearFocus() end)
    lscroll:SetScrollChild(edit)
    config.logEdit = edit
    local lclr = ConfigBtn(lp, L["Clear"], 90, function() DB.log = {}; RefreshLog() end)
    lclr:SetPoint("BOTTOMLEFT", 4, 4)
    local lref = ConfigBtn(lp, L["Refresh"], 90, function() RefreshLog() end)
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
    config.LayoutTabs()
    ShowTab("settings")
end

RefreshLog = function()
    if not (config and config.logEdit) then return end
    local lines = DB and DB.log or {}
    config.logEdit:SetText(#lines > 0 and table.concat(lines, "\n") or L["(log empty - enable Debug logging)"])
    config.logEdit:SetCursorPosition(0)
end

RefreshConfig = function()
    if not config then return end
    if config.checks then for _, cb in pairs(config.checks) do cb.Refresh() end end
    if config.LayoutTabs then config.LayoutTabs() end
    if PreviewBtnSync then PreviewBtnSync() end
    if config.scaleSlider then config.scaleSlider.Refresh() end
    if config.RefreshLang then config.RefreshLang() end
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
            r:SetSize(SCROLL_W - 2, 20)
            r.icon = r:CreateTexture(nil, "ARTWORK")
            r.icon:SetSize(16, 16); r.icon:SetPoint("LEFT", 2, 0)
            r.tag = r:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
            r.tag:SetPoint("LEFT", 22, 0); r.tag:SetWidth(52); r.tag:SetJustifyH("LEFT")
            r.text = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            r.text:SetPoint("LEFT", 76, 0); r.text:SetWidth(SCROLL_W - 102); r.text:SetJustifyH("LEFT")
            r.x = CreateFrame("Button", nil, r, "UIPanelCloseButton")
            r.x:SetSize(20, 20); r.x:SetPoint("RIGHT", 2, 0)
            config.rows[i] = r
        end
        local name, tex = ItemName(entry.id)
        r.icon:SetTexture(tex or 134400)
        r.tag:SetText(entry.cat == "junk" and GREY .. L["Junk"] .. "|r" or GOLD .. L["Normal"] .. "|r")
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
        ItemHint(r.x, entry.id, L["Remove from ignore list."])
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
            r:SetSize(SCROLL_W - 2, 20)
            r.icon = r:CreateTexture(nil, "ARTWORK")
            r.icon:SetSize(16, 16); r.icon:SetPoint("LEFT", 2, 0)
            r.text = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            r.text:SetPoint("LEFT", 22, 0); r.text:SetWidth(SCROLL_W - 158); r.text:SetJustifyH("LEFT")
            r.price = r:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
            r.price:SetPoint("RIGHT", -26, 0); r.price:SetWidth(88); r.price:SetJustifyH("RIGHT")
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
        ItemHint(r.x, entry.id, L["Unmark as junk. Shift-click to skip the confirm."])
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
    -- Development mode: undocumented on purpose, no setting in the UI. It exists
    -- for working ON the addon, so the only way in is typing it.
    if cmd == "dev" then
        DB.devMode = not DB.devMode
        act("dev mode", nil, tostring(DB.devMode))
        if not config then BuildConfig() end
        config.LayoutTabs()
        if not DB.devMode then CloseLootConfirm() end   -- a preview must not outlive dev mode
        print(GOLD .. "DGs Junk|r " .. fmt(L["development mode %s"],
            DB.devMode and (GREEN .. L["on"] .. "|r " .. L["- the Debug tab is available"])
                        or (RED .. L["off"] .. "|r")))
        return
    end
    -- Development only, like "dev" above: forces a locale so the German layout
    -- can be checked without installing a second language pack. Everything the
    -- addon draws is built once at load, so this stores the choice and asks for
    -- a /reload rather than pretending it can re-label live frames.
    if cmd == "lang" then
        if not (DB and DB.devMode) then
            print(GOLD .. "DGs Junk|r " .. L["development mode is off (/dgjunk dev)."])
            return
        end
        local want = (msg or ""):match("^%s*%S+%s+(%S+)")
        local alias = { de = "deDE", dede = "deDE", en = "enUS", enus = "enUS",
                        auto = "auto", off = "auto" }
        want = want and (alias[want:lower()] or want) or nil
        if want ~= "enUS" and want ~= "auto" and not locales[want or ""] then
            local have = { "auto", "enUS" }
            for name in pairs(locales) do have[#have + 1] = name end
            table.sort(have)
            print(GOLD .. "DGs Junk|r locale: " .. (activeLocale or "?") ..
                " | usage: /dgjunk lang " .. table.concat(have, "|"))
            return
        end
        -- "auto" is the only value stored as nil: that is what makes the client's
        -- locale win. enUS is stored explicitly, because on a German client nil
        -- would mean "follow the client" and English would never take effect.
        DB.locale = (want ~= "auto") and want or nil
        act("locale", nil, tostring(DB.locale or "auto"))
        if config and config.RefreshLang then config.RefreshLang() end
        print(GOLD .. "DGs Junk|r locale set to " .. (DB.locale or "auto") .. " - type /reload to apply.")
        return
    end
    if cmd == "preview" then
        if not (DB and DB.devMode) then
            print(GOLD .. "DGs Junk|r " .. L["development mode is off (/dgjunk dev)."])
            return
        end
        if not config then BuildConfig() end     -- the Debug tab owns the label sync
        -- "/dgjunk preview container" shows the container variant of the same
        -- dialog. Filling the bags to exactly zero free slots and then finding a
        -- clam is a lot of work to look at a header, so this exists.
        if (msg or ""):lower():match("^%s*%S+%s+container") then
            PreviewContainerConfirm()
            return
        end
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
