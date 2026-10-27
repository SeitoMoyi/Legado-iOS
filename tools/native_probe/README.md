# Native integration verification

This standalone simulator app compiles production core services, the QuickJS adapter,
BookStore, SourceWebSession, RSS renderer and browser. Its own bundle identifier and
fake loopback fixtures keep it separate from the user's installed app and credentials.
It is not included in the production target.

Run from the iOS repository on a Mac with Xcode and installed simulator runtimes:

1. Build `LegadoApp` in Debug for `generic/platform=iOS Simulator`, using a dedicated
   derived-data directory. Resolve the checked-in package versions first. This provides
   matching SwiftSoup/ZIPFoundation modules and QuickJS C object files.
2. Start `python3 tools/native_probe/fixture_server.py /tmp/legado-native-fixture-url`
   in a separate terminal. It binds only 127.0.0.1 on an ephemeral port.
3. Compile the verification app (replace the derived-data path as needed):

```sh
python3 tools/native_probe/build_probe.py \
  /tmp/legado-directory-xcode/Build/Products/Debug-iphonesimulator \
  /tmp/legado-directory-xcode/Build/Intermediates.noindex/Legado.build/Debug-iphonesimulator/LegadoApp.build/Objects-normal/$(uname -m) \
  /tmp/LegadoNativeVerification.app /tmp/legado-native-fixture-url
```

4. Create and boot a **new disposable simulator**, then use its exact ID for
   `xcrun simctl install DEVICE /tmp/LegadoNativeVerification.app` and
   `xcrun simctl launch DEVICE org.legado.NativeVerification`.
5. Locate its data directory with
   `xcrun simctl get_app_container DEVICE org.legado.NativeVerification data`.
   Read `Documents/verification.json` and inspect `Documents/rss-render.png`.
   Refresh this path after reinstalling, because the container UUID can change.
6. Stop the fixture server and shut down/delete only that disposable simulator.
   Never erase, reset or reuse the user's testing device for these checks.

The build requires the host's native simulator architecture (x86_64 on the verification
Mac, arm64 on Apple Silicon). Do not mix device or other-architecture object files.
The report records the production version and a SHA-256 of all Swift files compiled by
this harness. Cookie/download/rendering assertions run against actual WebKit delegates.

v0.4.0: 18 checks passed independently on iOS 15.5 and 17.2. Full check names,
fingerprint, offline results and limitations are in
[the verification record](../../docs/Verification-v0.4.0.md). This does not validate
arbitrary third-party sites, physical devices or full Android parity.
