# Home Power Face

A companion Garmin Connect IQ **watch face** (separate from the `h0me-p0wer-garmin` watch app one level up - Connect IQ requires a watch face and a watch app to be separate projects/manifests) showing the same [h0me-p0wer](https://github.com/lucianhanga/h0me-p0wer) backend's today-so-far energy breakdown, always on your wrist.

- **Time**, centered.
- **Outer ring** - a plain circle in the house's neutral color, framing the composition.
- **Inner ring** - today's home consumption split into Grid / direct-PV / battery-out, as clockwise arc segments sized by each source's share of the total (same fields and color convention as the watch app's "Today" page).
- **Four readouts** below the time - HOUSE, PV DIRECT, GRID, BATT OUT, each in its brand color.

## Why this needs its own project

A watch face can't poll a timer every few seconds like the watch app does - the OS suspends that once the face isn't actively being looked at. Data refresh instead goes through `Toybox.Background`: `HomePowerFaceApp` schedules a temporal event (`Config.REFRESH_MINUTES`, 30 min by default), `HomePowerFaceDelegate` runs in that background slot to make the actual request, and the result lands in `Application.Storage` for the view to read on its next `onUpdate`.

## Quick start: run it in the simulator

```sh
./scripts/run-simulator.sh
```

Same kill/relaunch/rebuild/push pattern as the watch app's script. To see data without waiting for the real 30-minute cycle, use the simulator's **Simulation → Background Events** menu to fire the temporal event on demand.

## Demo/live data and the API token

Same `Config.mc`/`Secrets.mc` split as the watch app:

```monkeyc
const API_URL = "https://h0me-p0wer.lucianhanga.stream/api/watch/status";
const API_TOKEN = Secrets.API_TOKEN;
```

`source/Secrets.mc` is gitignored - copy `source/Secrets.mc.example` to create it, same token value as the watch app's own `Secrets.mc`.

## Installing on the real watch

Same as the watch app: build a signed `.prg` (`./scripts/run-simulator.sh` builds `bin/HomePowerFace.prg` as a side effect), copy it into `GARMIN/APPS/`, then set it as your active watch face from the watch's face picker.
