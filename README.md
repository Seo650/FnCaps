# FnCaps

English | [한국어](README.ko.md) | [日本語](README.ja.md) | [简体中文](README.zh-Hans.md) | [繁體中文](README.zh-Hant.md) | [Українська](README.uk.md) | [Русский](README.ru.md) | [Français](README.fr.md) | [Español](README.es.md) | [Deutsch](README.de.md)

FnCaps is a menu bar app for macOS for anyone who uses three or more input sources and finds switching between them slow.

macOS gives you one key that steps through every input source in turn. With three or more, you press until the language you want comes up, check the menu bar, and press again.

FnCaps splits your input sources between two keys, Caps Lock and fn (🌐).

- Each key has its own list and switches only within that list.
- You decide which language goes on which key. For example, English on Caps Lock and your other languages on fn.
- One long list becomes two short ones. With the layouts FnCaps recommends, the language you want is one or two presses away, so your typing is not interrupted.
- With more languages, you can give an input source its own shortcut and go straight to it.
- Caps Lock switches with no delay. Hold it to turn Caps Lock on or off as usual.

> **First launch:** macOS blocks FnCaps once because it is not notarized by Apple. Open System Settings > Privacy & Security and click Open Anyway. The steps are in [Open Anyway](#open-anyway).

> FnCaps is in early development until 1.0.

## Requirements

- macOS 14 Sonoma or later, Apple silicon or Intel
- Accessibility permission. FnCaps needs it to notice fn and Caps Lock presses.

## Install

### Homebrew

```sh
brew install --cask Seo650/tap/fncaps
```

### GitHub Releases

1. Download the latest `FnCaps-x.y.z.zip` from [Releases](https://github.com/Seo650/FnCaps/releases/latest).
2. Unzip it.
3. Move `FnCaps.app` to `/Applications`.

## First launch

<a id="open-anyway"></a>

### Open Anyway

FnCaps is signed with its own certificate and is not notarized by Apple, so macOS blocks the first launch. This happens once.

1. Open FnCaps. macOS says it cannot verify the app. Click Done.
2. Open System Settings > Privacy & Security.
3. Under Security, click Open Anyway.
4. Enter your password or use Touch ID, then click Open.

The Open Anyway button appears only after a blocked launch and stays for about an hour. If it is gone, open FnCaps again. If you prefer the command line, this removes the block:

```sh
xattr -dr com.apple.quarantine /Applications/FnCaps.app
```

### Setup

When FnCaps opens, it walks you through the Accessibility permission and the key layout. FnCaps needs the permission to notice fn and Caps Lock presses. You can change everything later in the FnCaps settings.

## Updates

FnCaps checks for a new version once a day. To install it, open the FnCaps settings, go to About FnCaps and click Update. Nothing is installed until you click Update. Homebrew users update the same way.

Updates keep the Accessibility permission, because every release is signed with the same certificate.

## What FnCaps sends

FnCaps does not record what you type. It connects to the internet in two cases.

- Update check: once a day FnCaps asks the GitHub API for the latest release. The request carries the app version and nothing else about you.
- Report a Problem: nothing is sent until you click Send. A report contains your message, your email if you enter one, the app and macOS versions, the Mac model, the keyboard type, your FnCaps settings, your input sources, the recent activity log, and a random installation number used only for the daily limit. It does not contain what you type, serial numbers or other device IDs. You can read everything before sending. Reports are stored in a private repository that only the developer can read.
- Report limits: five reports a day for each installation, and five a minute from one network address.

## Known limitations

- Password fields: macOS keeps password fields in English, so FnCaps does not switch languages there, and holding Caps Lock does not turn on Caps Lock.
- Control+Space: does not switch input sources while FnCaps is on. It works again when FnCaps is turned off or quit.
- Caps Lock light: when you turn Caps Lock on by holding the key, the light on the key stays off. Capital letters are typed normally.
- Language indicator: when you press the keys quickly, the small indicator macOS shows next to the cursor can show a different language from the one in use. The menu bar shows the right one.
- Letter being composed: if a Korean, Japanese or Chinese character is still being composed when you press fn, that character can be lost.
- English layout: FnCaps treats ABC and U.S. as English. ABC – AZERTY and ABC – QWERTZ count as French and German.
- Karabiner-Elements and gksdud: these apps change the same keys. A Karabiner rule that uses `caps_lock` takes the key before FnCaps sees it. FnCaps shows a warning while one of them is running.
- Not tested, expected to work: unplugging and reconnecting an external keyboard, macOS 14 to 26, and Macs other than an Apple silicon MacBook Air.

## Recovery

If Caps Lock stops working:

- In FnCaps, choose Restore Keys from the menu bar icon, or click Restore Now in Settings > General. This returns Caps Lock and the input source shortcut to how they were before FnCaps.
- If FnCaps is not running, for example after a crash, Caps Lock can stay remapped and do nothing. Clear the remap in Terminal, then open FnCaps again:

  ```sh
  hidutil property --set '{"UserKeyMapping":[]}'
  ```

- If you cloned this repository, the script clears the remap and also restores the input source shortcut:

  ```sh
  scripts/caps-recover.sh --restore
  ```

If Control+Space still does not switch input sources after you quit FnCaps, check System Settings > Keyboard > Keyboard Shortcuts > Input Sources > "Select the previous input source". Restore Keys puts it back to how it was before FnCaps.

## Uninstall

Quit FnCaps first. Quitting returns Caps Lock and the input source shortcut to how they were. Then run:

```sh
brew uninstall --cask fncaps
```

Or move `FnCaps.app` from `/Applications` to the Trash. To remove the settings too, use `brew uninstall --zap --cask fncaps`.

## Build from source

```sh
swift build
scripts/build-app.sh
```

`scripts/build-app.sh` creates `build/FnCaps.app`. It signs with the "FnCaps Dev Local" certificate when one exists and with an ad-hoc signature otherwise. With an ad-hoc signature, macOS asks for Accessibility permission again after every build. `scripts/make-local-identity.sh` creates the local certificate.

## Contributing

Issues and pull requests are welcome. The app and this README are translated into ten languages. Most translations were not checked by native speakers, so translation fixes are especially welcome.

## License

MIT. See [LICENSE](LICENSE).
