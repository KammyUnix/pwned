# Releasing Pwned

A release is made by pushing a version tag. The Build Pwned workflow builds the app and publishes it as a GitHub Release. Nothing else is needed.

## Build types

| Trigger | Channel | Result |
| --- | --- | --- |
| Push to `main` | Development | Unsigned IPA kept as a workflow artifact for 14 days. No release. |
| Tag `v0.4.0` | Production | The same build, published as a GitHub Release and marked Latest. |
| Tag `v0.5.0-beta.1` | Pre-release | Published as a pre-release. The app's update check ignores it. |
| Manual run with `release_dry_run` on | Dry run | Builds, writes the notes and checksum, publishes nothing. |

Development IPAs are named `Pwned-<version>-dev-<commit>-unsigned.ipa`. Release IPAs are named `Pwned-<version>-unsigned.ipa` and come with a `.sha256` file.

## Making a release

1. In `project.yml`, set `MARKETING_VERSION` and raise `CURRENT_PROJECT_VERSION`. Commit and push to `main`.
2. Wait for Build Pwned and Test Pwned to pass on that commit.
3. Tag the commit and push the tag:

   ```sh
   git tag v0.4.0
   git push origin v0.4.0
   ```

4. Open the Releases page and check the notes and attached files. Edit the notes there if they need more than the commit list.

To rehearse first, open Actions, choose Build Pwned, run it on `main` with `release_dry_run` on, and read the job summary. It shows the notes and checksum that a real release would have.

## What the workflow checks

- `project.yml` is the only place the version is set. The workflow reads `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` from it, so the tag, the file name, the release and the version shown in the app cannot disagree.
- The tag must match `MARKETING_VERSION`. A tag like `v0.5.0` on a commit that still says `0.4.0` fails with a message saying so, and nothing is published. A pre-release suffix is allowed (`v0.5.0-beta.1` matches `0.5.0`) because the app's version number cannot hold one.
- If a release for the tag already exists, the workflow leaves it alone. Re-running a tag build does not create a second release or replace the files.
- The release notes list up to 15 commit subjects since the previous version tag, with a link to the full comparison.

## How the app finds updates

The Info page asks the GitHub API for the repository's latest release (`/repos/KammyUnix/pwned/releases/latest`). GitHub returns the newest release that is neither a draft nor a pre-release, so pre-releases never appear as updates.

The release tag is compared with the installed `MARKETING_VERSION` as a semantic version. A leading `v` is ignored, a missing part counts as zero (`1.2` is `1.2.0`), and a pre-release sorts below its release. The build number is shown but not compared. The check runs when you press Check for Updates and once when the Info page opens, which can be turned off under Settings, Data and Privacy. The app never polls in the background.

If the repository has no release yet, the page says so.

## Signing

The IPAs are unsigned: the workflow builds with `CODE_SIGNING_ALLOWED=NO` and has no signing steps. That is unchanged. An unsigned IPA has to be signed with the installer's own certificate, or installed with a sideloading tool that signs it.

To publish signed IPAs from CI, this has to be set up first. None of it exists yet.

1. An Apple Developer Program membership.
2. A signing certificate for the team (Apple Distribution for TestFlight or the App Store, Apple Development or Ad Hoc for devices), exported from Keychain Access as a `.p12` file with a password.
3. A provisioning profile for the bundle identifier `by.thekammy.pwned`, of the same type as the certificate.
4. These repository secrets, under Settings, Secrets and variables, Actions. The names are a suggestion, and the workflow has to be written to read whatever names are chosen:

   | Secret | Content |
   | --- | --- |
   | `BUILD_CERTIFICATE_BASE64` | The `.p12` file, from `base64 -i certificate.p12` |
   | `P12_PASSWORD` | The password set when exporting the `.p12` |
   | `BUILD_PROVISION_PROFILE_BASE64` | The `.mobileprovision` file, from `base64 -i profile.mobileprovision` |
   | `KEYCHAIN_PASSWORD` | Any value, used for a temporary keychain on the runner |

5. Changes to `build.yml`: create the temporary keychain and import the certificate, install the profile, build with `xcodebuild archive` using the team and signing settings, export with `xcodebuild -exportArchive` and an `ExportOptions.plist` whose `method` matches the profile, and attach the exported IPA instead of the unsigned one.
6. For TestFlight uploads, also an App Store Connect API key: its key ID, its issuer ID and the `.p8` file, stored as secrets and read by an upload step added to the workflow.

Until then, releases carry the unsigned IPA only.
