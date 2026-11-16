# DroidNest: Husk Solo

DroidNest is Husk with one game in front of it. Opening it starts the game chosen last, full screen, with no library in the
way; three fingers held on the game for five seconds bring the games back, where another APK can be chosen or a new one added.

It is a second **target** in this repository, not a fork of the sources: Husk keeps its own identifier, screens, icon and
behaviour, and the two apps can be installed side by side. Everything DroidNest runs with is Husk's -- the translation layer,
its importer, its JIT machinery and its game screen -- so a fix in one is a fix in both.

## Building it

```
xcodegen generate --spec src/app/project.yml --project src/app   # or just: ./scripts/package_ipa.sh
xcodebuild -project src/app/Husk.xcodeproj -scheme DroidNest -sdk iphoneos -configuration Release build
./scripts/package_droidnest_ipa.sh                               # → ~/Desktop/DroidNest.ipa
```

The target is `DroidNest` in `src/app/project.yml`:

| | Husk | DroidNest |
|---|---|---|
| Bundle identifier | `com.husk.app` (`HUSK_BUNDLE_IDENTIFIER`) | `com.droidnest.app` (`DROIDNEST_BUNDLE_IDENTIFIER`) |
| Name | Husk | DroidNest (fixed; see below) |
| Entry point | `HuskApp.swift` (`@main struct HuskApp`) | `src/app/DroidNest/DroidNestApp.swift` |
| JIT helper | `HuskJITHelper.appex`, `…​.JITHelper` | `DroidNestJITHelper.appex`, `…​.JITHelper` |
| Icon | `Assets.xcassets/AppIcon` + four alternates | `src/app/DroidNest/Assets.xcassets/AppIcon` |
| URL scheme | `husk://` | `droidnest://` |
| Screens | `ContentView` (Home, Library, Store, Settings) | `SoloManagerView`, `SoloPlayer` |
| Sources | `Husk/`, `translation-layer/`, `translation-layer-next/`, `Shared/` | the same, plus `DroidNest/` |

`DROIDNEST` is defined for this target only, and `HuskApp.swift` wraps its `@main` in `#if !DROIDNEST`; that is the whole of
the difference in the shared code. `HuskAppDelegate` and `HuskOrientation` are shared unchanged, because a game that turns the
screen needs them in both apps.

The guest kernel, its initramfs and the UEFI firmware Husk stages are **not** copied into DroidNest's bundle: it never boots
Android, so they would be 25 MB of an IPA for a screen it does not have. QEMU, ANGLE, MoltenVK and the PS4 dylib are still
embedded, because the shared sources link against them; trimming them out would mean a separate translation-layer build.

## What it does

**Opening it.** `SoloRootView` reads the chosen game, decides against what is on disk now (`SoloLaunch.plan`), and presents
`SoloPlayer` over the games if it can run. If it cannot, the games open with the reason: nothing chosen, the game's files gone,
or an APK whose report says its code cannot run here.

**Importing.** The `+` button opens the system file picker (`HuskFilePicker`, presented from UIKit because SwiftUI's
`.fileImporter` goes quiet on certificate-signed installs). `APK`, `.xapk`, `.apkm`, `.apks` and `.obb` are taken. The file is
**copied** into `Documents/TranslationLayer/<uuid>/`, and `TranslationLayerStore` reads the name and icon out of the APK's
manifest and resource table exactly as it does for Husk -- adaptive (XML) icons included -- and stores the app's report.
Imports are refused *before* the copy when the file is not an Android package or when the copy plus 64 MB of headroom will not
fit, so "not enough space" is said in words rather than arriving as a half-written folder.

**Remembering.** The APKs are files in the app's own container, so they survive being closed, force-quit and restarted. The
choice of game is one value in `UserDefaults` (`droidnest.primaryGame`, JSON: id, label, package name), kept beside the label
so a game whose folder has gone can still be named when the games open.

**Switching.** Tapping a game makes it the one DroidNest opens. The runtime holds one game's libraries in the process and does
not let go, so switching away from a game already loaded this session is offered as "Close DroidNest" (which saves the choice
and exits) -- the same answer Husk gives, made explicit instead of happening at a `blockedBy` check.

**Leaving a game.** Three fingers held for five seconds. It is built to be impossible to trip by playing: exactly three
fingers, all five seconds, no fourth joining and none lifting, with a ring filling on screen to say it is happening, and then a
question -- "Leave *game*?" -- before anything closes. A game that needs three fingers of its own is given them by turning the
gesture off in the games screen. The decision is `ThreeFingerHold` in `SoloCore.swift`, which is unit-checked; the recognizer
in `SoloPlayer.swift` only reports touches to it.

The recognizer is a passive `UIGestureRecognizer` attached to the window: it never enters `.began`/`.ended`/`.failed`, so it
cancels no touch, delays none, and blocks no other recognizer. The game keeps every touch it had before.

## Names and icons on the Home Screen

DroidNest is called DroidNest on the Home Screen, always. iOS has no supported way for an app to rename itself, and this app
does not try.

The icon is the app's own (`src/app/DroidNest/Assets.xcassets/AppIcon.appiconset/Icon-1024.png`, currently Husk's artwork as a
placeholder -- replace it with DroidNest's own). Changing the Home Screen icon at run time would only be possible between
`appiconset`s **shipped in the bundle**, through `UIApplication.setAlternateIconName`, and an APK's icon cannot be one of those:
it is not in the bundle, and iOS will not take an icon from a file at run time. Husk's own alternate-icon picker
(`HuskAppIcon.swift`) is therefore not offered here, and the game's icon and name are shown inside the app, where iOS does let
an app draw them.

## JIT: what turns on by itself, and what cannot

Games run Android's own ARM code, which has to come from memory that can be written and then executed. iOS grants that to an
app only through an attached debugger (see [02-jit-substrate.md](02-jit-substrate.md)), so "no step in front of the game" is a
question about how a debugger attaches -- not something an app can invent.

DroidNest asks for the unattended ways by itself as it opens (`SoloJIT.turnOnAtLaunchIfPossible`):

| Where | Turns JIT on with no step? | What is needed |
|---|---|---|
| iOS 26+ with Built-in StikJIT | **Yes** | Husk's own helper extension attaches while DroidNest is in the foreground. Needs the pairing file and LocalDevVPN, set up once in the walkthrough. |
| Installed through TrollStore (iOS 14–17) | **Yes** | TrollStore attaches as the app opens, provided its URL Scheme setting is on. |
| Jailbroken (Dopamine, "Allow JIT in Apps") | **Yes** | iOS marks the app debugged as it starts. |
| JIT-less mode, certificate imported | **Yes**, for engines that do not generate code at run time | The game's libraries are converted to signed dylibs once, then no executable memory is needed. Mono/LuaJIT-style JITs still need JIT. |
| iOS 16–25, sideloaded without TrollStore or a jailbreak | **No** | iOS gives an app no way to attach its own debugger there. Husk hands off to **StikDebug** (`stikjit://`) each launch, which is a step in front of the game, or JIT-less mode is used. |

Where none of those apply, DroidNest says so on the games screen (Husk's `JITCard` and setup walkthrough) and does not start a
game rather than starting one that would die at its first frame. Nothing here is a bypass of iOS, and no claim is made that
every APK or every game from any store runs: what starts is what Husk's translation layer can run on that iPhone.

## Errors it says out loud

| Situation | What is said |
|---|---|
| Not an Android package | "*name* is not something DroidNest can add. Choose an APK, or a bundle of them…" |
| Not enough room | Needs about X, this iPhone has Y free. |
| Copy failed | Husk's own message from `TranslationLayerStore` (`Husk could not copy it: …`). |
| APK copied but unreadable | It stays, and the games say it may not start. |
| Chosen game's files gone | The games open and name it; choose another or add it again. |
| APK with no ARM code | It is not started on launch; tapping it still tries. |
| JIT off or its setup incomplete | The JIT card, the helper's own error text, and the setup walkthrough. |
| Another game already loaded | "Close DroidNest?" -- the choice is saved and the next launch opens it. |
| Game stops on its own | Husk's game screen says so, with **Run Again**. |

## Tests

```
./tests/solo/run.sh
```

Compiles `src/app/DroidNest/SoloCore.swift` with `tests/solo/solo_core_test.swift` and runs it: the launch decision (nothing
chosen, a renamed game, a removed game, an APK that cannot run), the choice surviving a relaunch through `UserDefaults`, what
an import accepts and refuses (extension, several files adding up, no free space, unreadable free space), the three-finger
state machine (a fourth finger, one lifted at 4.9 s, progress never running backwards, a second hold in the same session) and
the one-game-per-session message.

`tests/translation-layer/run.sh` and the rest of Husk's tests are unchanged.

## What this does not do

- One game per launch of the app. That is the runtime's shape, not a setting.
- The Android emulator, the Store catalogue, PS4 games and multitasking windows are compiled in (they are the shared sources)
  but no screen in DroidNest offers them.
- The game runs full screen on its own; there is no library, wallpaper or Home Screen widget of the chosen game.
- The IPA is Husk's size, minus the guest images.

## Licence

GPL-2.0-or-later, as Husk is, because it is Husk. The bundled StikJIT (MPL-2.0) and idevice (MIT) licences travel with the app
exactly as in Husk's bundle; see [01-licensing.md](01-licensing.md).
