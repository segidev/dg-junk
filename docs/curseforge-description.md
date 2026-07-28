Bag space is the real currency in Classic. **DGs Junk** always knows the two items you should throw away first, and tells you, at the moment you need to decide, whether the thing you just looted is worth more than the worst thing you are already carrying.

Standalone, no libraries required. [Auctionator](https://www.curseforge.com/wow/addons/auctionator) is optional and only used for auction-house prices.

## Features

- **Two floating icons.** Your cheapest *junk* (gray quality plus anything you marked yourself) and your cheapest *non-junk* item, tracked independently, each with vendor and auction-house value.
- **Icon interactions.** Shift-left-click deletes, shift-right-click ignores, right-click opens a context menu (mark/unmark as junk, delete, ignore, settings). Grays go instantly, whites raise Blizzard's confirm, green or better asks once more and names the rarity in its own colour.
- **Loot verdict.** Hovering an item in the loot window says *Loot it* or *Skip*, judged against the cheapest thing you would have to discard. Quest items always read **Quest item: Take it!**
- **Coloured loot rows.** The loot window is tinted per row, green when the item beats your cheapest junk, red when it does not, so you can read the whole window at a glance without hovering anything.
- **Full bags?** Clicking a loot item with no free slot opens a pick-an-item dialog: the loot on the left, your cheapest junk and cheapest non-junk on the right with both vendor and AH prices, the cheaper one recommended. Limited to Common quality and below, so the deletion is instant. Not the item you wanted to lose? Page through the next-cheapest with the arrows either side of an icon or the mouse wheel over it, up to ten per side, always starting at the cheapest and stopping at both ends. Each item appears once rather than once per bag slot, and you are offered its smallest stack. Right-click an item there to ignore it instead.
- **Junk-coin overlay.** Items you marked get a small coin in the bag slot corner. Works with Bagnon and the default bags, and never overwrites rarity borders.
- **Vendor auto-sell** (opt-in, off by default). Sells only items you marked yourself, and only above gray quality, so it can never fight another gray-seller.
- **Junk and Ignored tabs.** Per-row removal and bulk resets. Nothing on these tabs touches your bags.
- **Profiles.** Settings are account-wide; marks and the ignore list live in a shared **Default** profile or this character's own, with copy-in / copy-out buttons.
- **Copyable diagnostic log**: debug output never goes to chat.

Quest items are never suggested, never auto-sold and never deletable, even if marked.

## Worth calculation

Items are ranked by real worth: vendor price, or the Auctionator AH price when *Suggest by AH* is enabled and data exists. Ranking uses the stack's total value, while the loot comparison uses per-item worth, so a stack of cheap junk no longer outranks a genuinely valuable single item.

## Slash command

`/dgjunk` opens the settings window. Loot-assist, suggest-by-AH, auto-sell, minimap button, frame scale, profiles and debug logging all live in there.

## Compatibility

Built for WoW **Classic Era / Hardcore**, interface 11509 (patch 1.15.9). Compatible with Bagnon.

## Feedback

Bugs and suggestions: [github.com/segidev/dg-junk/issues](https://github.com/segidev/dg-junk/issues)
