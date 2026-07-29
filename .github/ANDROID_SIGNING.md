# Android release signing

The automatic `CI Build` workflow always builds an unsigned debug APK and never
reads signing secrets. The manual `Release` workflow builds a signed APK and AAB
only when all four repository secrets below are configured; otherwise it fails.

| Secret | Value |
| --- | --- |
| `ANDROID_KEYSTORE_BASE64` | Base64-encoded upload keystore (`.jks`) |
| `ANDROID_KEYSTORE_PASSWORD` | Keystore password |
| `ANDROID_KEY_ALIAS` | Upload key alias |
| `ANDROID_KEY_PASSWORD` | Upload key password |

Generate an upload keystore on Windows:

```powershell
keytool -genkey -v -keystore $env:USERPROFILE\upload-keystore.jks `
  -storetype JKS -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

Encode the keystore for the GitHub secret:

```powershell
[Convert]::ToBase64String(
  [IO.File]::ReadAllBytes("$env:USERPROFILE\upload-keystore.jks")
)
```

Keep the keystore and all passwords private. Do not commit `android/key.properties`
or the `.jks` file. For Google Play, upload the signed `.aab`; Google Play signs
the APK delivered to end users through Play App Signing.

To publish a release, open **Actions > Release > Run workflow**, enter a new
`x.y.z` version, select one or more platforms, and run it from the commit or
branch that should be released. The workflow creates the matching `vX.Y.Z` tag
only after all selected packages and checks succeed.
