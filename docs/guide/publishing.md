# Publishing

Choose a destination based on who needs the build. Test the web version first if you’re sending it to someone for feedback.

| I want to… | Command | What it needs |
|---|---|---|
| Send someone a temporary browser link | `npx helder share` | A project that builds for the web. |
| Give the app a permanent web address | `npx helder publish --run` | A `run.name` and GitHub sign-in or a trusted Actions workflow. |
| Upload to a store | `npx helder publish --play` or `--testflight` | Store access, app setup and signing credentials. |
| Notarize a desktop macOS release | `npx helder publish --notarize` | A Mac and Apple signing and notarization credentials. |

```sh
npx helder publish               # every destination helder.json names
npx helder publish --run         # helder.run only
npx helder publish --play        # Google Play only
npx helder publish --testflight  # TestFlight only
npx helder publish --notarize    # Apple's notary service, on a Mac
```

With no destination flag, it publishes to helder.run first, when [helder.json](settings.md) has a `run` block, and then to each target's `publish` list.

## helder.run

helder.run hosts the web build of your app. There are two ways to put it there.

### helder share

```sh
npx helder share
```

No account needed. The app gets a random address such as `https://quiet-otter-k7m2.helder.run`, is unlisted, and is removed after a week. A share can be 25 MB at most.

### helder publish --run

Publishing under a name of your own needs an account. Sign in once with GitHub:

```sh
npx helder login
```

Add a `run` block to helder.json:

```json helder.json
{
  "name": "Little Skies",
  "run": {"name": "little-skies", "kind": "game"}
}
```

Then publish:

```sh
npx helder publish --run
```

Each publish is a new version. `run.name` is the address. The first account to publish a name owns it. `helder logout` forgets the token that `helder login` stored. In CI, set `HELDER_TOKEN` instead of logging in, or use [GitHub Actions](#github-actions) with no token at all.

### The app and its project page

| Address | What is there |
|---|---|
| `<name>.helder.run` | The app itself, full screen, on an origin of its own. |
| `helder.build/<name>` | The project page: the name, screenshots, a Play or Open button, links to its stores, a QR code, and what the app can access. |

The command prints both.

### What is uploaded

- The web build: the WebAssembly module, its assets and fonts, and Helder's runtime modules.
- The icon, at 512 px.
- The images in `run.screenshots`. Without any, Helder runs the program without a display and takes one screenshot. `--no-screenshot` skips that.

Files are sent by their hash, so anything helder.run already has is not sent again. A file can be 25 MB at most, and a release 100 MB.

### What helder.run allows

- Your HTML page is not uploaded. helder.run renders the page itself.
- Only Helder's own runtime runs there. helder.run accepts the runtime modules of Helder's main branch, by hash. A runtime you changed locally is refused, and so is a module that imports anything else.
- A published app has no network access, and no camera, microphone or location.
- Each app runs on its own address, apart from helder.build and from every other project.

The project page lists what the app can do, such as saving data in the browser, playing sound or reading game controllers. That list is made from the program itself when it is published, not from what the author says.

### Listing on Explore

Set `run.listed` to `true` to list the project on [helder.build/explore](https://helder.build/explore). `run.kind` and `run.tags` say where it belongs there. Projects are unlisted by default: anyone with the address can open them, but they are not shown.

```
"run": {"name": "little-skies", "listed": true, "kind": "game", "tags": ["golf"]}
```

### GitHub Actions

A workflow can publish to helder.run without a secret. Give it `id-token: write`, and `helder publish --run` signs in with the workflow's OIDC token.

```yaml .github/workflows/publish.yml
name: publish

on:
  push:
    branches: [main]

permissions:
  contents: read
  id-token: write

jobs:
  publish:
    runs-on: ubuntu-24.04
    steps:
      - uses: actions/checkout@v7
      - uses: actions/setup-node@v7
        with:
          node-version: 24
      - run: npm ci
      # for the screenshot, which is taken without a display
      - run: sudo apt-get update && sudo apt-get install -y --no-install-recommends libegl1 libegl-mesa0
      - run: npx helder publish --run
```

A project accepts publishes only from repositories it trusts. The first publish of a new name from GitHub Actions makes the project the repository owner's and trusts that repository. For a project that exists already, add the repository in its settings on helder.build.

## The stores

Helder builds, signs and uploads through each store’s API. Set up the app and its credentials before running the command. You can supply credentials through your CI environment.

### Google Play

```sh
npx helder publish --play                  # the internal track
npx helder publish --play --track beta     # internal, alpha, beta or production
npx helder publish --play --draft          # a draft release, for an app never published
```

This builds an App Bundle (`.aab`), signs it with your release key and uploads it to the track. It needs:

- The release key, which is Play's upload key: `HELDER_ANDROID_UPLOAD_IDENTITY` (the certificate and the key in one PEM), or `HELDER_ANDROID_SIGNING_CERTIFICATE` and `HELDER_ANDROID_SIGNING_KEY`, or `targets.android.signing` in helder.json. Helder reads PEM files, not a keystore.
- Access to the Play Developer API: a service account's JSON key in `HELDER_PLAY_SERVICE_ACCOUNT`, in `targets.android.serviceAccount`, or in `GOOGLE_APPLICATION_CREDENTIALS`. Or a ready access token in `GOOGLE_OAUTH_ACCESS_TOKEN` or `HELDER_PLAY_ACCESS_TOKEN`, which is what Workload Identity Federation gives a CI job.

The service account needs the app's release permissions in Play Console, under Users and permissions. Google Play also needs the app's first bundle uploaded by hand, to create its listing.

### TestFlight

```sh
npx helder publish --testflight
```

This builds the `.ipa`, signs it for distribution and uploads it to App Store Connect. It does not need a Mac. It needs:

- The distribution identity: `HELDER_IOS_IDENTITY` (the certificate, its chain and the key in one PEM), or `HELDER_IOS_CERTIFICATE` and `HELDER_IOS_KEY`, or `targets.ios.signing` in helder.json. The key must be unencrypted.
- The App Store provisioning profile in `HELDER_IOS_PROFILE`. This is optional: without it, Helder fetches the bundle id's active App Store profile from App Store Connect.
- An App Store Connect API key: `HELDER_ASC_KEY_ID`, `HELDER_ASC_ISSUER_ID` and `HELDER_ASC_KEY` (the `.p8` file). Or all three as JSON in `HELDER_ASC_API_KEY`: `key_id`, `issuer_id` and `private_key`.

The app must exist in App Store Connect with the same bundle id. TestFlight lists the build once App Store Connect has processed it. Validation errors arrive by email and on the build's page.

### macOS notarization

```sh
npx helder build --target macos --package
npx helder publish --notarize
```

`build --package` makes the universal `.app` in a zip in `bin/dist`. `publish --notarize` submits the release to Apple's notary service, waits, and staples the ticket. It runs on a Mac, because it uses `xcrun notarytool`. It needs:

- A Developer ID signature on the app: `HELDER_MACOS_IDENTITY`, or `HELDER_MACOS_CERTIFICATE` and `HELDER_MACOS_KEY`. Without one the app is signed ad hoc, which Apple does not notarize.
- The same App Store Connect API key as TestFlight: `HELDER_ASC_KEY_ID`, `HELDER_ASC_ISSUER_ID` and `HELDER_ASC_KEY`.

If Apple refuses the app, the command prints the notary log.

### Store screenshots

`helder publish --screenshots` renders the project's stories that are marked for the stores, at the stores' sizes, into `bin/store`, with a review sheet. `--listing` uploads them to the stores' listings (`--locale` sets the language, `en-US` by default).

`--listing` also sends helder.json's `listing`, the store page's text. Only what it sets is sent; a field, language or image type it leaves out stays as the store has it. Each set of screenshots it sends replaces the store's, in order, and one already the same is left alone. Everything is checked before the first request. Google Play's changes go in one edit, committed at the end, so a failure changes nothing. App Store Connect has no such thing, so helder reads everything first and refuses to start when the version being prepared is missing: `--create-version` makes it.

`listing.notes` belongs to the build, not the page: `--play` sends it as the release's notes, `--testflight --submit` as the version's what's new. `helder publish --pull` prints what the stores have now as a `listing`, to start from for an app already in the stores.

## --dry-run

Add `--dry-run` to see what a publish would do. It builds and signs, signs in, reads what is there now, and prints what would change. Nothing is uploaded.

```sh
npx helder publish --run --dry-run
npx helder publish --play --track beta --dry-run
npx helder share --dry-run
```
