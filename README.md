# Lumen

Ian's iPhone app for WiZ smart lights. It talks to the lights directly over the home Wi-Fi (no internet, no WiZ account), so they respond instantly.

- **Rooms and lights:** tap a light to switch it, open it for brightness, warm-to-cool white, a colour wheel and WiZ's built-in scenes (with speed for the moving ones). Rooms control all their lights together.
- **Moods:** save how any set of lights looks right now and bring it back with one tap.
- **Widgets:** Rooms, Moods and a single Room switch (Home Screen and Lock Screen).
- **Control Centre:** a room switch, a mood button and All lights off.
- **Shortcuts and Siri:** turn rooms on or off, set brightness, colour, scene or mood.

## How it works

- WiZ lights listen for small JSON messages on UDP port 38899 (`getPilot`, `setPilot`, `getSystemConfig`, `getModelConfig`). Lumen finds them by asking every address on the Wi-Fi network (iOS only allows broadcast with a special Apple approval, so it doesn't use one), and remembers each light by its hardware address so it can find it again if its address changes.
- Light actions for widgets, Control Centre and Shortcuts run in the app's own process (they're `LiveActivityIntent`s), which is where the Local Network permission lives.
- The home set-up is shared with the widget extension through the keychain (like Nudge, Shelf and Murmur), so no App Group is needed.
- Native SwiftUI, iOS 26+, iPhone only. The Xcode project is generated from `project.yml` with XcodeGen.

## Workflows

1. **Set up with Apple**: `check` the secrets, create the `identifiers`, then `certificates`, then `testers`.
2. **Check build and screenshots**: runs on every push; builds for the simulator, runs an end-to-end check against a pretend WiZ light (`scripts/fake_bulb.py`) and saves screenshots to the `screenshots` branch.
3. **Build Lumen**: builds and uploads to TestFlight. Runs on every push to `main`, monthly (so it never expires) and on demand. Uses the same Apple secrets and `Match-Secrets` certificate store as Trio, Nudge, Shelf and Murmur.
