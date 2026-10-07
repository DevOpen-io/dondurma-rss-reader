# Store releases

GitHub Actions owns validation, builds, artifacts and submissions in
[the release workflow](../.github/workflows/build-and-release.yml). Fastlane
handles Apple signing/packaging and store APIs. There are no Python or shell
helper files. Flutter is pinned to 3.47.4, Java to 17, and iOS to macOS 15 /
Xcode 26.3. iOS uses Swift Package Manager exclusively, with an iOS 15.5 minimum.
The compatible Workmanager update fixes its earlier SPM package layout.

Pull requests and main pushes run analysis/tests and produce a **debug-signed**
APK artifact for testing. Exact `vMAJOR.MINOR.PATCH` tags produce signed APK,
AAB and IPA artifacts, a GitHub release, and submissions to both stores.
Malformed `v*` tags fail validation. Both signed build jobs must succeed before
either submission job starts. Submissions are serialized across workflow runs;
an active release is never cancelled. GitHub concurrency retains at most one
pending run, so wait for the active release to finish before tagging another.

## Configure GitHub

Add these repository Actions secrets in Settings → Secrets and variables →
Actions. Use the existing Android upload key and Apple Distribution identity;
do not generate replacements for an established app.

| Secret | Value |
| --- | --- |
| `ANDROID_KEYSTORE_BASE64` | Single-line base64 of the existing upload keystore |
| `ANDROID_KEYSTORE_PASSWORD` | Keystore password |
| `ANDROID_KEY_ALIAS` | Existing upload-key alias |
| `ANDROID_KEY_PASSWORD` | Private-key password |
| `PLAY_SERVICE_ACCOUNT_JSON` | Raw service-account JSON with access to `io.devopen.dondurma` and production releases in Play Console |
| `APPLE_CERTIFICATE_BASE64` | Single-line base64 of Apple Distribution `.p12`, including its private key |
| `APPLE_CERTIFICATE_PASSWORD` | `.p12` password |
| `APPLE_PROFILE_BASE64` | Single-line base64 of the matching, unexpired App Store provisioning profile for `io.devopen.dondurma`, team `6NLKUNN3FH` |
| `ASC_KEY_BASE64` | Single-line base64 of the App Store Connect API `.p8` key |
| `ASC_KEY_ID` | App Store Connect API key ID |
| `ASC_ISSUER_ID` | App Store Connect API issuer ID |

For file secrets, `base64 < file | tr -d '\n'` produces a single-line value.
Keep credentials out of commits, artifacts and logs. The workflow restores
files under the runner's temporary directory, checks the Android signing
certificate against the supplied upload key, validates Apple profile/certificate
matching, and always removes temporary files, profiles and keychains.

Disable **managed publishing** in Play Console and set repository Actions
variable `PLAY_MANAGED_PUBLISHING_DISABLED` to `true`. This is an operator
attestation: the workflow cannot query that console setting. Production uploads
use `release_status: completed` and send changes for review. Approved releases
then publish automatically. See [Play delivery options](https://docs.fastlane.tools/actions/upload_to_play_store/).

Complete all listing metadata, screenshots, review contact details, privacy,
content declarations and any required export-compliance documentation before
submitting. Enter App Store release notes in its upcoming version. Commit Play notes
as `fastlane/metadata/android/<locale>/changelogs/<BUILD>.txt` (for example
`en-US/changelogs/14.txt`); at least one locale is required, with 1–500
characters per file. The workflow uploads only these build-specific changelogs.
Fastlane preserves listing content and screenshots. On Apple it
uploads and waits for the binary, selects the explicit build number for review,
and sets `AFTER_APPROVAL` directly because `skip_metadata` also skips Fastlane's
release-type update. See [App Store delivery](https://docs.fastlane.tools/actions/upload_to_app_store/).

The iOS binary declares `ITSAppUsesNonExemptEncryption=false` for the app's
exempt encryption use (standard HTTPS; no custom encryption feature). This
answers the build-specific encryption question automatically for fresh uploads;
the signed IPA check verifies the declaration is present. Reassess this value
if encryption features or dependencies change. See [Apple's declaration guidance](https://developer.apple.com/documentation/bundleresources/information-property-list/itsappusesnonexemptencryption).

## Create a release

1. Set `pubspec.yaml` to `MAJOR.MINOR.PATCH+BUILD`. Increase the positive integer
   build number beyond **all** previously uploaded builds in both stores.
2. Complete App Store release notes and declarations, and commit Play
   changelog files for that build number.
3. Merge to main and wait for green CI. The tag's commit must be an ancestor
   of `origin/main`, and its version must exactly match `pubspec.yaml`.
4. Create and push the exact version tag, for example `git tag v1.0.4` followed
   by `git push origin v1.0.4`. This immediately authorizes both store submissions.
5. Follow the Actions job summaries and store consoles. A successful job means
   submission succeeded; review approval remains external and may take time.

Signed files are available in the `android-store` and `ios-store` workflow
artifacts and the tagged GitHub release. GitHub release publication describes
build availability, not store approval.

## Validate without submitting

Run `flutter analyze`, `flutter test`, and `flutter build apk --release
--no-tree-shake-icons` locally. Android release builds require the existing
`android/key.properties` (`storeFile`, `storePassword`, `keyAlias`, `keyPassword`)
or the corresponding `ANDROID_KEYSTORE_PATH`, `ANDROID_KEYSTORE_PASSWORD`,
`ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD` environment variables. Debug builds
need no release credentials; release builds never fall back to debug signing.

Run `flutter build ios --release --no-codesign --no-tree-shake-icons` to validate
the SPM build without signing. Install locked Ruby dependencies with
`bundle install`; `bundle exec fastlane lanes` checks that the lanes load.

With credentials restored to a private temporary directory, set
`CREDENTIAL_DIR`, `RUNNER_TEMP`, `RELEASE_VERSION`, `RELEASE_BUILD`,
`APPLE_CERTIFICATE_PASSWORD`, `ASC_KEY_ID`,
`ASC_ISSUER_ID` and `PLAY_JSON_PATH` as appropriate. File names are
`distribution.p12`, `app.mobileprovision`, `AuthKey.p8`, and `play.json`.
`bundle exec fastlane ios build` builds a signed IPA without uploading.
`bundle exec fastlane android verify_access` and
`bundle exec fastlane ios verify_access` check store API authentication without
submitting. Remove the installed profile and temporary keychain afterwards;
the workflow contains the same cleanup steps. Do not run either `release` lane
or push a release tag during validation.

## Recover a failed platform

Inspect the failed job and the corresponding store console first. Both stores
can approve independently. Re-run only the failed `android-submit` or
`ios-submit` job using its Actions job menu, keeping the original tag and
artifacts. Do not re-run the successful platform or the entire workflow.
Apple reuses an already uploaded build with the exact version/build rather than
uploading it again. If Play accepted the AAB before a later submission error,
complete that existing release in Play Console; uploading the same versionCode
again will fail. Never move a release tag to a different commit. For a changed
binary, increment the build number and use a new version tag.

If artifact retention has expired, investigate and recover the existing store
build before attempting another upload. Store review, signing credentials,
API permissions and complete metadata must be verified with real credentials
before the first production tag.
