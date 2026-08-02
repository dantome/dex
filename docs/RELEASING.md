# Releasing DEX

DEX is distributed directly through GitHub Releases rather than the Mac App Store. Ordinary users do not need an Apple developer account. The maintainer signs each public build with Developer ID and submits it to Apple's automated notarization service so Gatekeeper can verify it.

## One-time setup

1. Join the Apple Developer Program and create a **Developer ID Application** certificate for the publishing team.
2. Install the certificate and its private key in the login Keychain. Confirm it appears under `security find-identity -v -p codesigning`.
3. Create notarization credentials. An App Store Connect API key is preferred for automation; an app-specific password also works for a local release.
4. Store local credentials in Keychain:

   ```sh
   xcrun notarytool store-credentials "DEX_NOTARY"
   ```

   Follow the prompts for the chosen authentication method. Never commit a `.p8` key, password, certificate export, or Keychain credential to this repository.

## Release checklist

1. Update `CFBundleShortVersionString` and `CFBundleVersion` in `Resources/Info.plist`.
2. Run the tests:

   ```sh
   swift test
   ```

3. Build, sign, notarize, staple, and validate the disk image:

   ```sh
   DEX_NOTARY_PROFILE=DEX_NOTARY ./scripts/release.sh
   ```

4. Install the resulting `dist/Dex-<version>.dmg` on a separate macOS user account or Mac and verify first-launch Gatekeeper and Accessibility behavior.
5. Tag the exact commit as `v<version>` and create a GitHub Release with the disk image and release notes.

The release script intentionally fails when a Developer ID identity or notarization credential is unavailable. Local builds may use Apple Development or ad-hoc signing; public builds may not.

## Protecting continuity

Keep `com.dantome.Dex` as the bundle identifier and use the same Apple Developer team for future releases. Do not revoke or replace the Developer ID certificate unless necessary. Export an encrypted backup of the certificate and private key to secure storage; losing the private key prevents that certificate from signing future releases.
