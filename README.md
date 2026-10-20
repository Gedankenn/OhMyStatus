# OhMyStatus

Omarchy bar widget for **this machine**: CPU, RAM, GPU, VRAM, disk and estimated watts. Click the chip for a popup with time line charts.

Not wall/PSU watts. GPU PPT is measured when the driver exports it; CPU watts fall back to TDP × utilization if RAPL is unreadable.

## Install

```bash
omarchy plugin add https://github.com/Gedankenn/OhMyStatus.git --enable
```

Place it in the bar if it does not show up:

```bash
omarchy plugin enable ohmystatus --section center
```

## Use

- Left click: popup
- Middle click: refresh now
- History lives in `$XDG_RUNTIME_DIR/ohmystatus.<hostname>.hist.json` while the session is up. Reboot clears it.

## License

MIT
