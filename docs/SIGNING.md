# Signing and macOS trust

Glosslet has three distinct signing modes. They solve different problems and
should not be treated as equivalent.

| Build | Cost | Accessibility across updates | Gatekeeper and notarization |
| --- | ---: | --- | --- |
| Ad-hoc local build | Free | Usually changes after every rebuild | Not notarized |
| Official project-signed release | Free | Stable after one grant | Unidentified developer; not notarized |
| Developer ID release | Paid Apple Developer Program | Stable after one grant | Can be notarized by Apple |

## Official release identity

Starting with v0.2.7, the GitHub release workflow signs every public asset with
the same self-signed code-signing certificate:

- Authority: `Glosslet Open Source Release`
- Certificate SHA-256:
  `8763149EEC0EC0FF4F6DFEFFDB1BA30E09DC0174E17FB6EA4CD920CCC6490B4E`
- Designated-requirement root SHA-1:
  `A87CA09FE1C067978A7DFE782F26AC21677C9FF9`
- Valid through: 2036-07-28

The private key is not stored in the repository. The tag workflow imports it
from encrypted repository secrets, signs the universal app, rejects a
CDHash-only identity, verifies the bundle, and then publishes the archive and
checksum.

This stable certificate fixes the update-specific Accessibility problem: TCC
can identify later builds as the same application even though their executable
hashes differ. It does not make the certificate an Apple Developer ID and does
not notarize the app.

## The v0.2.7 migration

Versions through v0.2.6 were ad-hoc signed. Their designated requirement was
based on the exact build's CDHash, so a replacement could leave System Settings
showing an enabled row that no longer matched the installed executable.

The first project-signed installation therefore needs one clean migration:

1. Open Glosslet.
2. If the setup screen still reports no access, click **Repair stale permission
   entry…**.
3. Enable the current `/Applications/Glosslet.app` in **System Settings →
   Privacy & Security → Accessibility**.
4. Return to Glosslet and wait for the setup screen to show **Access granted**.

The repair action resets only Glosslet's TCC entry. It cannot enable the switch
or bypass macOS consent.

## Verify an installed copy

```bash
codesign -dv --verbose=4 /Applications/Glosslet.app
codesign -d -r- /Applications/Glosslet.app
codesign --verify --deep --strict --verbose=2 /Applications/Glosslet.app
```

The first command should show `Authority=Glosslet Open Source Release`. The
designated requirement should contain the certificate root above and should
not contain `cdhash`.

## Developer ID path

A Developer ID Application certificate and Apple notarization remain the
recommended distribution path when the project joins the paid Apple Developer
Program. The existing build scripts support that identity and a `notarytool`
keychain profile without changing Glosslet's runtime permission model.
