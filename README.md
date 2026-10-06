# Omarchy Germany Polls

An Omarchy bar plugin for German election polls.

The bar shows the party leading the Bundestag polls, a news-style ticker
that scrolls through every party, or just a ballot-box icon. Click it for a map of
Germany with every state filled in its polling leader's colour, and the full
results for the Bundestag or any state you hover or click.

## Data

- Polls: [DAWUM](https://dawum.de/) (`api.dawum.de/newest_surveys.json`),
  licensed [ODbL](https://opendatacommons.org/licenses/odbl/1-0/).
  Refreshed every 30 minutes.
- By default each figure is the average of every institute's newest poll from
  the 30 days before the latest poll for that parliament; a party a poll does
  not list counts as 0 there, so the average adds up like the polls do. Most
  states only have one poll. Set `pollMode` to `"latest"` (or use the toggle in
  the map panel) to show only the most recent poll instead.
- State borders: [deutschlandGeoJSON](https://github.com/isellsoap/deutschlandGeoJSON),
  simplified into `GermanyMap.js` by `tools/build-map.py`.

## Installation

```bash
omarchy plugin add https://github.com/yubinex/omarchy-germany-polls.git --enable
```

## Settings

Set `parliament` on the bar entry in `~/.config/omarchy/shell.json` to show a
state instead of the Bundestag, using DAWUM's parliament id (`2` is Bayern,
`10` is Nordrhein-Westfalen, see `GermanyMap.js`):

```json
{ "id": "yubinex.germany-polls", "parliament": "2" }
```

Set `barDisplay` to `"leader"` (default), `"ticker"` to scroll through every
party, or `"icon"` to keep results out of the bar entirely (the tooltip stays
neutral too). The map panel has the same toggle. `tickerWidth` sets the
ticker's visible width in pixels (default `220`); hovering pauses it.

```json
{ "id": "yubinex.germany-polls", "barDisplay": "ticker", "tickerWidth": 260 }
```

`screenDisplay` overrides the mode per monitor (names from `hyprctl monitors`),
and also accepts `"hidden"`. For example, a ticker on the ultrawide and just the
leader everywhere else:

```json
{ "id": "yubinex.germany-polls", "barDisplay": "leader", "screenDisplay": { "DP-1": "ticker" } }
```

The panel lists every monitor with its mode, so a monitor where the widget is
hidden can be switched back from any monitor where it is still visible. The
last visible monitor cannot be hidden from the panel; if every monitor is
hidden via `shell.json`, edit it there or open the panel with
`omarchy-shell shell toggle yubinex.germany-polls`.

## Controls

- Left click: open or close the map
- Middle click: refresh the polls
- Right click: open the parliament on dawum.de

## License

[MIT](LICENSE)
