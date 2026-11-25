# Publishing to the stores

`helder publish` builds, signs and uploads in one command: to Google Play, to TestFlight and the App Store, to Apple's notary service for macOS, and to helder.run for the web. It talks to the stores' APIs directly, so it needs no Mac for iOS and no Android SDK, and runs in CI.

<Platforms/>

The app's name, icon, colours and id live in `helder.json`, beside `package.json`. One icon is enough: helder makes every size each platform needs.

```json helder.json
{
  "$schema": "https://helder.build/schema/helder.json",
  "name": "Little Skies",
  "id": "build.helder.littleskies",
  "version": "1.2",
  "icon": "icon.svg",
  "colors": {"theme": "#9fd0ff", "background": "#fbdfea"},
  "run": {"name": "little-skies", "kind": "game"},
  "targets": {
    "android": {"publish": [{"to": "play", "track": "internal"}]},
    "ios": {"publish": ["testflight"]}
  }
}
```

```sh
npx helder share                  # a browser link for a week, no account
npx helder publish --run          # little-skies.helder.run, with a project page
npx helder publish --play         # Google Play's internal track
npx helder publish --testflight   # App Store Connect
npx helder publish --dry-run      # what would change, nothing uploaded
```

`share` gives you a temporary preview link. Use `publish --run` for the
project's permanent page, or `--dry-run` to check the steps before an upload.

## What else

- **Setup:** `helder setup` makes the stores' keys and certificates through their APIs and lists what is left to do by hand.
- **Store listings:** the store page's text and screenshots, rendered from your app's stories at each store's sizes.
- **Splash screens, orientation, permissions** and each platform's settings, in `helder.json`.
- **CI:** keys from environment variables, and GitHub Actions publishing to helder.run with no secret at all.
- **Desktop releases:** a universal macOS app, notarized; a Windows `.exe`; a Linux archive and Flatpak manifest. Attach them to a GitHub release and link them from the project's page with `run.downloads` (`{"macos": "https://github.com/<owner>/<repo>/releases/..."}`): helder.build links only to GitHub releases.

<Reference to="cli,pack"/>
