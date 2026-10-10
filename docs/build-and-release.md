# Build and release with GitHub Actions

The workflows build on `macos-15` with the installed Swift toolchain. They produce a universal app and CLI for Apple silicon and Intel Macs. Live Codex checks are skipped because runners do not have a signed-in account; offline checks, builds, architecture verification, signatures and the packaged CLI are checked before upload.

The app is ad-hoc signed, not Apple-notarized. Linux can edit this repository but cannot perform the full macOS build or packaging workflow.

## Download a development build

CI runs for pushes to `main` and pull requests. To build another branch manually:

1. Push the branch to GitHub.
2. Open the repository's **Actions** tab and select **CI**.
3. Choose **Run workflow**, select the branch and run it. The workflow must first exist on the default branch for the manual button to appear.
4. Open the successful run and download `codex-meter-macos-<run-number>-<attempt>` from **Artifacts**.
5. Extract the artifact download. It contains `Codex-Meter-<version>-ci-<run-number>-<commit>.zip` and its `.zip.sha256` file. Verify the checksum, then extract the inner ZIP to install the app or CLI.

Development artifacts are retained for 14 days and require GitHub access to download. A CI or manual development build does not create a GitHub Release.

## Publish a version

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

The packaging script verifies both architectures, signatures and CLI execution after extracting the generated ZIP. The ZIP and checksum file are written into `dist/`. A custom package label can be supplied as the second argument.
