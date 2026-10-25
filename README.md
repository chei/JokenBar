# JokenBar

**Your Claude usage in the Mac menu bar.**

![JokenBar popover showing a work and a personal account](docs/screenshot.png)

Work and personal accounts side by side. The menu bar icon turns orange at
75% and red at 90%. Press **⌃⌥J** to open it from anywhere.

## Install

macOS 14 or later. Paste into Terminal:

```sh
curl -fsSL https://raw.githubusercontent.com/chei/JokenBar/main/install.sh | bash
```

Then click the JokenBar icon → **Add Account…** and sign in to claude.ai as
usual. Add more accounts under **Settings ›**.

Run the same command again to update.

## Privacy

JokenBar talks only to claude.ai and reads the same numbers as its Usage page.
You sign in on claude.ai's own page, just like in a browser, and the app never
sees your password.

## Uninstall

Paste into Terminal:

```sh
pkill -x JokenBar
rm -rf /Applications/JokenBar.app ~/Applications/JokenBar.app ~/Library/WebKit/io.github.chei.jokenbar
defaults delete io.github.chei.jokenbar
```

## Development

Command Line Tools are enough, no Xcode needed.

```sh
git clone https://github.com/chei/JokenBar.git && cd JokenBar
scripts/test.sh        # unit tests
scripts/build-app.sh   # dist/JokenBar.app, copy it to Applications
```

## License

[MIT](LICENSE)
