# Changelog

## 1.4.0

Pricing you can act on, and a dialog that says what it means.

- **A price basis you choose**, replacing the old *Suggest by AH prices* checkbox. Pick **Vendor
  only** (the default, and no Auctionator needed), **Best of both**, or **AH only**. The old
  checkbox made the AH price *replace* the vendor price, so whichever channel was cheaper decided
  what to destroy, and that is never the channel you would have used. Best of both takes the higher
  of the two for each item instead: a 1c vendor item that sells for 12s at auction is no longer the
  cheapest thing in your bags. Had the old checkbox on? You are moved to Best of both, since that
  is what you were asking for.
- **The comparison dialog says which item to destroy.** Green used to mean *take this* on the loot
  side and *destroy this* on the candidate side, and the word was *recommended*, which reads like
  something to keep. The slot to give up is now framed red with a marker in its corner and the words
  **delete this**. Colour means the action from here on, so a candidate you paged past keeps only
  its red warning text and drops back to a neutral frame.
- Both prices stay on screen whatever basis you rank by. The setting decides what counts, not what
  you get to see, and the picker greys itself out with a reason when Auctionator is missing.

## 1.3.0

Opening things with full bags.

- **The container you are looting is never offered up.** Open a clam or a lockbox with full bags
  and its contents wait in the loot window, while the container itself stays in your bag until you
  take them. It is usually the cheapest thing you are carrying, so it was being recommended as the
  item to destroy, which would have taken the contents with it. It is now held back for as long as
  its loot window is open, and so is anything else the game has locked, since destroying a locked
  item silently does nothing at all.
- **No more phantom dialog over an open loot window.** The "inventory is full" that appears when a
  container opens into full bags comes from auto-loot, not from the container failing, so the addon
  no longer treats it as one. The loot window is in charge there and gives its usual keep-or-skip
  verdicts on the contents.
- **Container assist**, for containers that refuse to open at all because there is no room. You get
  the same pick-an-item dialog the loot window uses, and once a slot is free the container is opened
  for you. It is re-checked immediately beforehand, so bags that shuffled in between cannot make it
  use the wrong item, and because the contents cannot be seen in advance the dialog says *contents
  unknown* rather than pricing the wrapper. Need more than the one slot you freed and it simply asks
  again. Whatever lands in your bags is then listed with its value. On by default, with its own
  switch in the settings.
- **Quest items no longer get priced.** A quest item is not a trade you can lose, so the comparison
  dialog stops telling you both of your candidates are too expensive for it. The cheaper of the two
  is still marked green as the one to give up, and the other is simply left neutral instead of
  warned against. Everything that is not a quest item keeps the old red verdict.
- Fixed: when both candidates in the comparison dialog were priced above the loot, their two red
  verdicts grew into each other and overlapped. The wording is shorter now, and that line is held to
  the same width as the item name above it, so a longer translation can no longer spill sideways.

## 1.2

The addon now speaks German, and the second icon got a clearer name.

- **German translation.** On a German client every line the addon shows you is in German: the two
  icons and their tooltips, the loot verdicts, the comparison dialog, the context menu, all four
  tabs, the settings and their explanations, and the confirmation dialogs. Nothing needs to be
  switched on and no other client is affected: the language follows the game. Should a line ever
  be missing a translation it simply shows in English instead of coming up blank.
- **Language picker** in the settings. It sits above the profile section and offers *Automatic
  (game language)*, *English* and *Deutsch*. Automatic is the default and is what you get without
  touching anything; the other two override the client, so you can run a German game with the addon
  in English or the other way round. The choice is account-wide. Because a language cannot be
  swapped on a window that is already drawn, picking one asks whether to reload your interface and
  then does it for you. Cancel and nothing is changed at all. It refuses while you are in combat.
- The **Cheap!** icon is now called **Normal**. It never meant "this is cheap", it means "this is
  the cheapest item you did *not* flag as junk", and Junk / Normal are the two categories the rest
  of the addon already used: the ignore list, its reset buttons and the comparison dialog all say
  Junk and Normal. The icon now matches them.

## 1.1.1

- Fixed: items being rolled for in a group no longer get a keep-or-discard verdict. While a green
  or better is under a roll, nobody can take it yet, and it stays out of reach if you lose the
  roll, so the addon no longer offers to clear a bag slot for it. Shift-clicking such an item says
  it is still being rolled for instead of opening the dialog, the loot tooltip says the same, and
  those rows are left untinted. Once you win the roll it behaves normally again.

## 1.1

Improvements to the full-bags dialog, plus a way to look at it without filling your bags first.

- The dialog can page through your other discardable items: arrows either side of each icon, or the
  mouse wheel over one. It always opens on the cheapest and stops at both ends, so nothing wraps
  around to an expensive item by accident. Up to ten choices per side.
- Each item is offered once, not once per bag slot. Carrying three stacks of cloth now offers you
  the smallest stack, and the other two are left alone.
- Every icon shows both prices, vendor and auction house, whichever one the ranking is set to use.
  The stack size is always shown, so it is clear whether a price covers one item or a whole stack.
- Fixed: a looted stack is now judged as the whole stack, not as a single item. Looting 4 pieces of
  meat is worth four times one, and it used to be compared as one against a full stack you would
  have to destroy, so stacked loot could be called not worth taking when it clearly was. The loot
  tooltip and the coloured loot rows use the same corrected comparison.
- Right-click an item in the dialog to ignore it, or shift-right-click to ignore it straight away.
  The item drops out of the list and the next one takes its place.
- An empty side of the dialog now says why it is empty instead of vanishing.
- The dialog keeps up with everything else: ignoring or marking an item anywhere else updates it
  immediately, and the other way round.
- Debug logging now records what the dialog decided and why.

## 1.0

First public release. Built for WoW Classic Era / Hardcore, interface 11509 (patch 1.15.9).

- Two floating icons: cheapest junk and cheapest non-junk item, each with vendor and AH value.
- Shift-left-click to delete, shift-right-click to ignore, right-click for the context menu
  (mark/unmark, delete, ignore, settings). Rarity-aware confirmations.
- Loot verdict in the loot tooltip, judged against the cheapest item you would have to discard.
- Full-bags dialog: pick between the loot and your cheapest discardable items, cheaper one
  recommended; limited to Common quality and below so the deletion is instant.
- Junk-coin overlay on self-marked items, compatible with Bagnon and the default bags.
- Opt-in vendor auto-sell for self-marked items above gray quality.
- Junk and Ignored tabs, per-row removal and bulk resets.
- Account-wide settings with Default / per-character profiles for marks and ignores.
- Copyable diagnostic log tab.
- Quest items are never suggested, auto-sold or deletable.
