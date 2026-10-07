# Play release notes

Add `<locale>/changelogs/<pubspec-build-number>.txt` before creating a release
tag. For example, `en-US/changelogs/14.txt`, `tr-TR/changelogs/14.txt`, and
`es-ES/changelogs/14.txt`. Each file must contain 1–500 characters.

At least one locale is required. These files are versioned with the release
commit; Fastlane uploads changelogs while preserving listing metadata and
screenshots. Do not add signing credentials here.
