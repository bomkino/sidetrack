# Contributing to Sidetrack

Sidetrack is deliberately small. A useful change should make the page quieter, clearer, more humane, or cheaper to run.

Before opening a large pull request, start with an issue and explain the person-sized problem. Screenshots help for layout work; an idle CPU sample helps for performance work.

## Keep these promises

- Native, local, and offline. No accounts, telemetry, network calls, or embedded browser runtime.
- No continuous render loop. Redraw on input, state change, and the minute.
- No urgency theatre: no red, seconds, badges, streaks, celebrations, or surprise sound.
- Keyboard and mouse must both work. Respect Reduce Motion.
- Preserve readable local JSON and Markdown exports.
- Prefer subtraction. A new preference needs a strong reason.

## Check a change

```sh
Scripts/test.sh
Scripts/build-app.sh
codesign --verify --deep --strict build/Sidetrack.app
plutil -lint build/Sidetrack.app/Contents/Info.plist
```

For visual changes, test at 900 × 600 and on a portrait display. For timing changes, cover every timer state and a relaunch.

Contributions to Sidetrack’s original source and artwork are accepted under [CC0 1.0 Universal](LICENSE). The bundled Newsreader font keeps its own SIL Open Font License.
