=== BWP App Builder ===
Contributors: bwpexperts
Requires at least: 5.8
Tested up to: 6.8
Requires PHP: 7.4
Stable tag: 1.0.0
License: GPLv2 or later

Turn any website into an iPhone app (IPA) and an Android app (APK) with one click.

== Description ==

The plugin adds a form to your site (shortcode `[bwp_app_builder]`). A user enters an app name, a
website address and a logo and presses "Build my app". The plugin starts a build in YOUR GitHub
repository (workflow `build-app.yml`, GitHub Actions). After about 3 to 10 minutes the user gets
download buttons for:

* `<App-Name>.ipa` - iPhone app, unsigned
* `<App-Name>.apk` - Android test app, installs directly

The app is a native shell around the website: splash screen, loading and offline screens,
pull-to-refresh, downloads, print, share, camera/gallery upload, safe areas.

= Important limits =

* The IPA is UNSIGNED. It cannot be installed by tapping it. It is installed with a sideloading
  tool (Sideloadly, AltStore) and an Apple ID; with a free Apple ID it runs for 7 days.
  It cannot be uploaded to the App Store as it is.
* The APK is a debug (test) build. It is not a Google Play release.
* Only https websites are accepted.
* Builds run on your GitHub account. In a public repository GitHub Actions is free, but GitHub's
  terms expect Actions to be used for the repository's own project - keep the limits low if the
  form is open to everybody. In a private repository Mac build minutes are limited and then paid.
* With access set to "Everyone", anybody can build an app around any website, not only their own.

== Installation ==

1. The GitHub repository must contain the app project with `.github/workflows/build-app.yml`.
2. Upload the `bwp-app-builder` folder to `/wp-content/plugins/` (or Plugins > Add New > Upload) and activate it.
3. On GitHub: Settings > Developer settings > Personal access tokens > Fine-grained tokens >
   Generate new token. Repository access: "Only select repositories" > your build repository.
   Permissions: **Actions: Read and write**, **Contents: Read-only**. Copy the token.
4. In WordPress: Settings > App Builder. Enter the repository owner, repository name and the token. Save.
5. Press "Test the GitHub connection".
6. Add the shortcode `[bwp_app_builder]` to a page.

The token can also be set in `wp-config.php` instead of the database:
`define( 'BWP_APP_BUILDER_GITHUB_TOKEN', 'github_pat_...' );`

== Settings ==

* **Access** - Administrators only / Logged-in users (default) / Everyone.
* **Apps offered** - iPhone, Android or both.
* **Builds per person per day** - per user account, or per IP address for visitors (default 3).
* **Builds running at the same time** - default 2.

== How it works ==

1. The form posts to WordPress. WordPress validates the request, stores the logo in
   `wp-content/uploads/bwp-app-builder/` and starts the workflow through the GitHub API.
2. The workflow validates the request again, builds the app and publishes the files to a release
   named `build-<id>` with a small JSON status.
3. The page asks WordPress for the status every few seconds. WordPress reads the release.
4. Downloads are streamed through WordPress, so the GitHub token never reaches the browser.
5. Builds are removed after 7 days (on GitHub by the workflow, in WordPress by a daily task).

The logo is downloaded by GitHub from your site, so the site must be reachable from the internet
over https. On a local test site the logo cannot be fetched and a letter icon is used instead.

== Changelog ==

= 1.0.0 =
* First version.
