# Changelog

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
