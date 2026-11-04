# Android build and device checks

HERO//HQ targets Android first. This document records the toolchain that was
actually used, the exact commands, and what was verified on a running Android
system. Nothing here assumes Android Studio.

## Verified environment

| Piece | Version / path used |
|---|---|
| Host | Windows, Git Bash |
| Godot | 4.7.2 stable console build |
| Export templates | 4.7.2 stable (`android_debug.apk`, `android_release.apk`) |
| JDK | Temurin 21.0.13 (`C:/Tools/jdk21`) |
| Android SDK | command-line tools 11076708 (`C:/Tools/android-sdk`) |
| SDK packages | `platform-tools`, `build-tools;35.0.0`, `platforms;android-35`, `emulator`, `system-images;android-35;google_apis;x86_64` |
| Emulator | AVD `herohq`, Pixel 6 profile, Android 35 x86_64 |
| App | debug APK, `com.jetroberts.herohq`, version 0.1.0 |

A physical phone has **not** been tested. Everything below ran on the emulator.

## One-time setup

```bash
# Export templates: unzip into the versioned folder Godot expects
#   %APPDATA%/Godot/export_templates/4.7.2.stable/
# It must contain android_debug.apk and android_release.apk.

# JDK
curl -L -o jdk.zip "https://api.adoptium.net/v3/binary/latest/21/ga/windows/x64/jdk/hotspot/normal/eclipse"
unzip jdk.zip -d /c/Tools/jdk_tmp && mv /c/Tools/jdk_tmp/jdk-* /c/Tools/jdk21

# Android command-line tools
curl -L -o cmdline.zip "https://dl.google.com/android/repository/commandlinetools-win-11076708_latest.zip"
mkdir -p /c/Tools/android-sdk/cmdline-tools/latest
unzip cmdline.zip -d /tmp/cmd_extract
cp -r /tmp/cmd_extract/cmdline-tools/* /c/Tools/android-sdk/cmdline-tools/latest/

export JAVA_HOME=/c/Tools/jdk21
export PATH="$JAVA_HOME/bin:$PATH"
yes | sdkmanager.bat --sdk_root=C:/Tools/android-sdk \
  "platform-tools" "build-tools;35.0.0" "platforms;android-35" \
  "emulator" "system-images;android-35;google_apis;x86_64"

# Debug signing key (Godot's default keystore path)
mkdir -p "$APPDATA/Godot/keystores"
keytool -keyalg RSA -genkeypair -alias androiddebugkey -keypass android \
  -keystore "$APPDATA/Godot/keystores/debug.keystore" -storepass android \
  -dname "CN=Android Debug,O=Android,C=US" -validity 9999 -deststoretype pkcs12
```

Godot reads its paths from editor settings (`editor_settings-4.7.tres`):

```text
export/android/java_sdk_path = "C:/Tools/jdk21"
export/android/android_sdk_path = "C:/Tools/android-sdk"
export/android/debug_keystore = "C:/Users/<user>/AppData/Roaming/Godot/keystores/debug.keystore"
export/android/debug_keystore_pass = "android"
```

## Build and install

```bash
godot --headless --path . --export-debug "Android" build/hero_hq.apk
adb install -r build/hero_hq.apk
adb shell monkey -p com.jetroberts.herohq -c android.intent.category.LAUNCHER 1
```

The export is signed with the debug key and needs no Gradle build. Godot prints
one warning that no project icon is set; it does not block the export.

The preset (`export_presets.cfg`) exports `all_resources` minus `tests/*`,
`tooling/*`, `ui_shots/*` and `docs/*`, targets arm64-v8a and x86_64, and uses
immersive fullscreen.

## Emulator

```bash
echo no | avdmanager.bat create avd -n herohq \
  -k "system-images;android-35;google_apis;x86_64" -d pixel_6 --force
emulator.exe -avd herohq -no-window -no-audio -no-boot-anim -no-snapshot -gpu host
adb wait-for-device
```

Two things matter on this host:

- **Use `-gpu host`.** With `-gpu swiftshader_indirect`, Godot's GLES3 canvas
  shader fails to link (`Fragment shader active uniforms exceed
  GL_MAX_FRAGMENT_UNIFORM_VECTORS (261)`) and the game renders as a black
  rectangle. The host GPU exposes real limits and renders correctly.
- **adb can report `device offline` during an install.** Retrying the install
  after `adb wait-for-device` succeeds.

For readable captures the emulator was set to `adb shell wm size 540x1200`
(same 9:20 aspect). Restore with `adb shell wm size reset`.

## What was verified on the emulator

Fresh save (profile deleted by reinstalling into a cleared app, then confirmed
through the save file):

- onboarding: HQ shows "Deploy your first operation from Missions" at step 1/5,
  50 Credits, roster 1/240
- first mission: Alley Patrol deploys, settles after 20 s, pays 18 Credits, and
  the on-device save reads credits 68 / tasks_completed 1 / assignments 0
- all five tabs render: HQ, Heroes, Missions, Teams, Upgrades
- recruitment: role picker offers every declared role; choosing Tech produces a
  Tech on the **first** hire (save: `op_0008:tech`)
- persistence: force-stop and relaunch keep credits, roster and roles
- research: with Intel funded, buying `ops_reward` spends 15 Intel and stores
  `{"ops_reward": 1}` in the save
- rebirth: regated seed at level 7 / 5,000 lifetime Credits shows "Rebirth for
  +4"; the first tap changes the button to "Confirm rebirth" and the second tap
  banks 4 chips, resets Credits to 50 and Intel to 0, rewinds both agents to
  level 1 with base attributes (rating 70), keeps the roster, and survives a
  restart

The rebirth test used a hand-seeded save (level and lifetime written into the
profile) because reaching level 7 takes far longer than a scripted device run.
Everything else was played through the UI.

## Device bugs found and fixed by this pass

- **Touch scrolling did not exist.** Godot's `ScrollContainer` ignores finger
  drags, so content below the fold — including the Rebirth button — could not be
  reached on a phone. `framework/ui/touch_scroll.gd` adds drag scrolling and
  swallows only the release that follows a real drag, so a scroll never presses
  the control it started on.
- **Reason labels collapsed inside button rows.** On Missions, Heroes training
  and Teams the blocked-reason label sat next to the button in an HBox, had zero
  minimum width because it wraps, and rendered as a one-character-wide vertical
  column that stretched the button to hundreds of pixels tall. Reasons now take
  their own full-width line.
- **Research named the wrong currency.** A 15-Intel purchase said "Not enough
  Credits"; the reason now formats the actual resource name.
- **A one-short squad said "No free hero".** The agent-count message now states
  how many heroes the operation needs.

## Not done

- Physical-device testing, release signing and an app icon.
- Play Billing and any ad integration. The product rule is unchanged: no banner,
  interstitial, native or forced ads, ever; only a player-initiated, optionally
  watched rewarded ad may exist at M6.
