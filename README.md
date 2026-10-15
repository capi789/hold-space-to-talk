# Hold Space to Talk

Push-to-talk for the **Claude** and **ChatGPT** Mac apps.

- **Hold Space**: the app's mic turns on, your Mac goes quiet and Spotify pauses.
- **Tap Space**: the mic turns off, your words stay in the box and the sound comes back.
- **Return**: the mic turns off and the message sends once your words land. One press.

Space works normally in every other app, and a quick tap in Claude or ChatGPT is still a space.

## Install

Paste this into Terminal:

```bash
curl -fsSL https://raw.githubusercontent.com/capi789/hold-space-to-talk/main/install.sh | bash
```

Then allow **Hammerspoon** in System Settings → Privacy & Security → Accessibility when macOS asks.

The installer:
1. Installs [Hammerspoon](https://www.hammerspoon.org), the free app that runs the script, if you don't have it.
2. Adds the script to Hammerspoon's config.
3. Sets Hammerspoon to start at login.

## Updates

The script checks this repo when it starts and every 6 hours. When a new version is out, it installs it
and reloads on its own. If a Claude or ChatGPT update renames the mic button, the fix lands here and
reaches every install automatically.

## Uninstall

```bash
curl -fsSL https://raw.githubusercontent.com/capi789/hold-space-to-talk/main/uninstall.sh | bash
```

## Notes

- Mac only (it uses macOS accessibility to press the app's own mic button).
- Works with the app's English labels.
- Log file: `~/.hammerspoon/hold-space-to-talk/log.txt`.
