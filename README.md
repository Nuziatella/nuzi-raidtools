# Nuzi Raidtools

Raid management, but with less menu wrestling and fewer "who has lead?" moments.

`Nuzi Raidtools` keeps the useful parts close at hand:

- auto-invite from recruit chat
- whitelist and blacklist management
- give-lead protection and handoff tools
- quick raid role assignment
- a cleaner raid info view that focuses on `Name / Class / GS`

## Install

1. Drop the `nuzi-raidtools` folder into your AAClassic `Addon` directory.
2. Make sure the addon is enabled in game.
3. Open the raid manager and let the addon build its UI.

Saved data lives in `nuzi-raidtools/.data` so updates do not wipe your lists.

## Quick Start

1. Open the raid tools panel.
2. Set your recruit message.
3. Pick the chat scope you want to listen to.
4. Open `List Manager` and create or edit your whitelists.
5. Hit `Start Auto-Invite` when you are ready to recruit.

If you only want trusted names to trigger invites, enable whitelist recruiting and keep the list tight.

## How To

### Auto-Invite

1. Enter the recruit phrase you want the addon to watch for.
2. Choose the chat channel filter.
3. Toggle `Start Auto-Invite`.
4. Anyone who matches your rules can be invited automatically.

You can also enable whitelist auto-invite if you want selected names to skip the normal recruit phrase check.

### List Manager

Use `List Manager` to:

- create named whitelists
- add names manually
- add current raid members
- remove names
- toggle which lists are active for recruiting

There are also reserved lists for:

- `Blacklist`
- `Give Lead Whitelist`

Those are built in on purpose, because sometimes leadership is a privilege and sometimes it is a containment strategy.

### Give Lead Controls

1. Set your code word.
2. Decide whether lead sniffing should be enabled.
3. Maintain the `Give Lead Whitelist`.

Only approved names can trigger a lead handoff when whitelist protection is enabled.

### Raid Info View

The stock raid info window is cleaned up to show the stuff that actually matters during raid assembly:

- Name
- Class
- GS

Less clutter, less squinting, fewer excuses.

## Notes

- Legacy root-level list files are migrated into `.data` automatically.
- The addon keeps local settings and list files separate so they survive addon updates more reliably.
- If something looks wrong after a major update, reload once so the latest saved settings are re-read cleanly.

## Version

Current version: `1.0.0`
