# Build and release with GitHub Actions

The workflows build on `macos-15` with the installed Swift toolchain. They produce a universal app and CLI for Apple silicon and Intel Macs. Live Codex checks are skipped because runners do not have a signed-in account; offline checks, builds, architecture verification, signatures and the packaged CLI are checked before upload.

The app is ad-hoc signed, not Apple-notarized. Linux can edit this repository but cannot perform the full macOS build or packaging workflow.

## Download an automatically published build

Every successful push build on `main` publishes its verified macOS ZIP and SHA-256 checksum directly to [GitHub Releases](https://github.com/ooeooo/codex-meter/releases/latest). A manually started **Actions → CI → Run workflow** build also publishes when the selected branch is `main`.

1. Open **Releases** or **Download latest** in the README.
2. Select `Codex-Meter-<version>-ci-<run-number>-<commit>.zip` under **Assets**.
3. Download the matching `.zip.sha256` file if you want to verify the checksum.
4. Extract the ZIP to install the app or CLI. There is no extra workflow-artifact ZIP around the installer.

Each publication uses its own `build-<run-number>-<attempt>-<commit>` tag pinned to the tested source commit, preserves previous releases, and becomes the latest download. Failed tests, failed package verification, pull requests and manual builds from other branches do not publish a Release. The publish job downloads the exact build job's artifact, checks its checksum again, uploads both files to a draft, then makes the Release public. Main builds finish publishing before the next main run starts; newer pushes do not cancel an upload midway. Reruns use a new attempt in the tag and never overwrite an older Release.

The automatic token has `contents: write` only in the main-only publish job. The build job and pull-request workflows retain read-only repository permissions. A generated build tag does not match the `v*` release trigger, so it does not start another build.

## Workflow artifact fallback

CI still retains `codex-meter-macos-<run-number>-<attempt>` under **Actions → CI → the run → Artifacts** for 14 days. This also provides downloads for pull requests and non-main manual builds. Extracting an artifact produces the installer ZIP and checksum. These temporary artifacts require GitHub access; published Release assets do not expire with the artifact retention period.

## Publish a version tag

1. Update `CFBundleShortVersionString` and `CFBundleVersion` in `Resources/Info.plist`, update the changelog and commit the changes.
2. Push the release commit and wait for CI to pass.
3. Replace `vX.Y.Z` below with the exact `CFBundleShortVersionString` prefixed with `v`. Create the tag on the intended release commit and push it:

   ```sh
   git tag -a vX.Y.Z -m "Codex Meter X.Y.Z"
   git push origin vX.Y.Z
   ```

Pushing the tag starts **Release**, which checks out that exact tag, checks its version against `Info.plist`, runs the offline tests, builds and verifies the package, and creates a GitHub Release with:

- `Codex-Meter-X.Y.Z.zip`: the app, CLI and installation instructions.
- `Codex-Meter-X.Y.Z.zip.sha256`: the archive's SHA-256 checksum.
- Automatically generated release notes.

The same files are also retained as workflow artifacts for 30 days, including if the final GitHub Release creation fails.

To release an existing tag manually, open **Actions → Release → Run workflow** and enter the existing `vX.Y.Z` tag. The checked-out source always comes from that tag, regardless of the branch selected for the workflow. The tag must include the build and packaging scripts used by the workflow. This action publishes a Release; it is not a development build. No personal access token is needed: the workflow uses GitHub's automatic token with `contents: write` permission.

Tags must use `vMAJOR.MINOR.PATCH`. A tag/version mismatch stops the job before compilation. The workflow will not create a missing tag or overwrite an existing Release. If a run fails before creating a Release, fix the cause and rerun it; use a new version and tag for changes to an already published version.

## Verify a downloaded archive

Place the ZIP and its checksum file in the same directory, then run on macOS:

```sh
shasum -a 256 -c Codex-Meter-X.Y.Z.zip.sha256
```

The result should say `OK`. Development packages use their full CI filename instead.

## Build and package locally on a Mac

From the repository root with Swift 6 installed:

```sh
SKIP_LIVE_CODEX_CHECK=1 ./scripts/test.sh
./scripts/build-app.sh dist
./scripts/package-app.sh dist
```

The build script converts `Resources/AppIcon.png` into a complete macOS ICNS icon using system `sips` and `iconutil`, and bundles `en` and `zh-Hans` display-name resources. The packaging script verifies the extracted icon, language resources, both architectures, signatures and CLI execution after extracting the generated ZIP. The ZIP and checksum file are written into `dist/`. A custom package label can be supplied as the second argument.
