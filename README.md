# Home Power for Garmin Fēnix 8 (47 mm AMOLED)

A native Garmin Connect IQ watch app prototype for the 454×454 AMOLED Fēnix 8 target.

## Included screens

1. Overview
2. Solar
3. Home consumption
4. Battery
5. Grid import/export
6. Summary ring
7. List view
8. Connection / retry

Use **UP/DOWN** or swipe to change pages. Press **START/ENTER** to advance or retry from the connection page.

## First run: demo mode

`source/Config.mc` ships with:

```monkeyc
const USE_DEMO_DATA = true;
```

That means the app can compile and run without a backend. When your watch API is ready, change it to `false` and point `API_URL` to your endpoint.

## Expected JSON

The default URL is:

`https://h0me-p0wer.lucianhanga.stream/api/watch/status`

The app accepts this flat structure (only the fields you provide are updated):

```json
{
  "solar": 4.21,
  "home": 1.87,
  "grid": -2.34,
  "battery": 78,
  "batteryPower": 1.20,
  "solarToday": 18.4,
  "homeToday": 22.6,
  "exportedToday": 18.1,
  "importedToday": 6.4,
  "batteryCapacity": 14.2,
  "batteryMinutesToFull": 195,
  "solarHistory": [0.4, 0.7, 1.1, 1.8, 2.6, 3.4, 4.0, 4.4],
  "homeHistory": [1.2, 1.6, 1.3, 1.1, 1.0, 1.2, 1.4, 1.7],
  "gridHistory": [-0.8, -1.1, -1.6, -2.1, -2.4, -2.8, -3.1, -3.0]
}
```

Negative `grid` means export; positive means import. Positive `batteryPower` is shown as charging.

## Compile and run in the Garmin simulator

1. Install Visual Studio Code.
2. Install Garmin's **Monkey C** extension in VS Code.
3. Install Garmin **Connect IQ SDK Manager**, sign in, and install the latest SDK plus the Fēnix 8 device files.
4. Open this `HomePowerGarmin` folder in VS Code.
5. Open any `.mc` file under `source/`.
6. Run **Monkey C: Verify Installation** from the command palette.
7. Run **Run > Run Without Debugging** (`Ctrl+F5`, or `Cmd+F5` on macOS).
8. Select the Fēnix 8 47 mm / 51 mm AMOLED target.

## Build a .PRG for the real watch

1. Connect the Fēnix 8 to the computer by USB.
2. In VS Code open the command palette (`Ctrl+Shift+P`; `Cmd+Shift+P` on macOS).
3. Run **Monkey C: Build for Device**.
4. Choose the **fēnix 8 47 mm / 51 mm** target.
5. Choose an output folder.
6. The wizard generates a `.prg` file.
7. Copy the `.prg` into the watch's `GARMIN/APPS/` directory.
8. Safely eject the watch, disconnect USB, then open **Home Power** from the watch's Apps list.

## If the target is missing

Run **Monkey C: Edit Products** and ensure the Fēnix 8 AMOLED product is selected. This project's manifest already contains the current product id `fenix847mm`.

## Developer key

The Garmin toolchain may ask you to generate/select a developer signing key the first time you build for hardware. Follow the prompt from the Monkey C extension/SDK Manager; keep that key private.

## Important

This ZIP contains source code, not a precompiled `.prg`, because Garmin's SDK/compiler is not installed in the environment that generated this package. Compile it locally with Garmin's official toolchain before sideloading.
