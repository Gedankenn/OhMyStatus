# OhMyStatus

Local stats on the [Omarchy](https://omarchy.org/) bar. Click the chip for time line charts of CPU, RAM, GPU, VRAM, disk and power.

<p align="center">
  <img src="assets/screenshot.png" alt="OhMyStatus: bar chip and popup with line charts" width="420">
</p>

## Install

```bash
omarchy plugin add https://github.com/Gedankenn/OhMyStatus.git --enable
```

If it does not appear on the bar:

```bash
omarchy plugin enable ohmystatus --section center
```

## Use

| Input | Action |
| --- | --- |
| Left click | Open popup |
| Middle click | Refresh now |

History is kept in `$XDG_RUNTIME_DIR/ohmystatus.<hostname>.hist.json` for the session. A reboot clears it.

GPU watts come from the driver PPT sensor when it exists. CPU watts use RAPL if readable, otherwise TDP × utilization. Totals are not wall/PSU draw.

## License

MIT
