# ADS-B Emergency Authentication Monitor  v4.0

A professional MATLAB GUI application implementing a **dual-path ADS-B authentication protocol** with four live data source modes, attack simulation, and interactive visualization tools.

---

## Quick Start

```matlab
run_app
```

That's it. All mode and sub-mode selection happens inside the GUI.

---

## Table of Contents

- [What This Does](#what-this-does)
- [GUI Layout](#gui-layout)
- [Data Source Modes](#data-source-modes)
- [The Dual-Path Protocol](#the-dual-path-protocol)
- [Attack Simulation](#attack-simulation)
- [Visualization Tools](#visualization-tools)
- [File Structure](#file-structure)
- [Requirements](#requirements)
- [Mode 4 — RTL-SDR Hardware Setup](#mode-4--rtl-sdr-hardware-setup)
- [Troubleshooting](#troubleshooting)
- [Extending the Code](#extending-the-code)

---

## What This Does

ADS-B is the global standard for aircraft position broadcasting — and it is completely unauthenticated by design. Any attacker with a software-defined radio can inject fake aircraft positions, replay old messages, or spoof emergency squawks.

This application simulates and evaluates a **dual-path security protocol** that:

1. Authenticates **routine position messages** using a delayed TESLA key-disclosure chain (no latency added at receive time).
2. Authenticates **emergency distress signals** instantly (< 10 ms) using pre-provisioned ground-signed keys.
3. Optionally detects **relay attacks** using Hancke-Kuhn round-trip-time distance bounding.

The GUI connects to four different data sources so you can test against synthetic data, historical archives, live global traffic, or your own RTL-SDR hardware.

---

## GUI Layout

```
┌─────────────────────────────────────────────────────────────────────┐
│  LEFT SIDEBAR          │  CENTRE PANELS         │  RIGHT PANEL      │
│                        │                        │                   │
│  Mode dropdown (1-4)   │  5 metric cards        │  Last aircraft    │
│  Sub-mode dropdown     │  (total/normal/emerg/  │  card             │
│  (active in Mode 2)    │   reject/latency)      │                   │
│                        │                        │  Path breakdown   │
│  SDR Scan button       │  Aircraft position     │  pie chart        │
│  (visible in Mode 4)   │  map                   │                   │
│                        │  (colour by altitude,  │  Latency          │
│  TESLA delay slider    │   red triangles for    │  histogram        │
│                        │   emergencies)         │                   │
│  Attack simulation     │                        │  Emergency event  │
│  dropdown              │  Authentication        │  log              │
│                        │  latency chart         │                   │
│  Speed slider          │  (area plot,           │                   │
│                        │   mean + threshold)    │                   │
│  ▶ START  ■ STOP       │                        │                   │
│  ⬇ Export  ↺ Reset     │                        │                   │
│                        │                        │                   │
│  Threat Dashboard btn  │                        │                   │
│  Signal Visualizer btn │                        │                   │
│  Traffic Monitor btn   │                        │                   │
│                        │                        │                   │
│  ● LIVE indicator      │                        │                   │
│  Status log            │                        │                   │
└─────────────────────────────────────────────────────────────────────┘
```

**Mode dropdown** — switches between all four data sources at any time (even mid-run if stopped first).

**Sub-mode dropdown** — only active when Mode 2 is selected; greyed out for all other modes.

**SDR Scan button** — only visible when Mode 4 is selected. Probes USB, tests the dongle with a live sample, and shows a green "● Hardware Connected" indicator or a descriptive error dialog.

**LIVE badge** — pulsing red "● LIVE" badge appears when Modes 3 or 4 are streaming real-time data.

---


### Mode 1 — Simulation

Five synthetic aircraft fly realistic holding patterns. Emergency squawks fire automatically every ~45 seconds. No internet or hardware required. Best for testing and demonstrating authentication logic offline.

### Mode 2 — Prerecorded

Plays back historical ADS-B data from **ADS-B Exchange** sample archive. Three sub-modes:

**2A — Auto-Download + Cache**
Downloads the midnight UTC snapshot (`YYYYMMDD_00.json.gz`) for the selected date from:
```
https://samples.adsbexchange.com/readsb-hist/YYYY/MM/DD/YYYYMMDD_00.json.gz
```
The file is cached locally in `ADSB_Cache/` as a `.mat` file. Subsequent runs with the same date use the cache — no re-download needed.

**2B — User Upload**
Opens a MATLAB file picker. Accepts `.json`, `.json.gz`, `.csv`, or `.mat` files exported from ADS-B tools.

**2C — Manual Placement**
Reads from the `ADSB_Data/` folder in the project directory. Place any supported file there before starting.

> **Note:** The sub-mode dropdown is greyed out and non-interactive when any mode other than 2 is selected.

### Mode 3 — Live API (OpenSky Network)

Connects to the OpenSky Network REST API for real-time global aircraft positions.

- URL: `https://opensky-network.org/api/states/all`
- **Anonymous:** 100 API calls/day, no registration required
- **Authenticated:** Higher limits — register free at [opensky-network.org](https://opensky-network.org)
- Refreshes every 10 seconds; cycles through the snapshot between refreshes
- Emergency detection: squawk codes 7500 (hijack), 7600 (radio fail), 7700 (general emergency)

### Mode 4 — Live SDR (RTL-SDR Hardware)

Receives raw IQ samples at 1090 MHz and decodes ADS-B Extended Squitter (DF=17) frames in real time.

Before starting, click **🔍 Scan for Device** to:
- Detect the RTL-SDR USB dongle
- Test with a live 1024-sample read
- Confirm signal reception

If no device is found, a dialog explains the issue with specific troubleshooting steps. The source falls back to simulation automatically so the app keeps working.

See [Mode 4 — RTL-SDR Hardware Setup](#mode-4--rtl-sdr-hardware-setup) below.

---

## The Dual-Path Protocol

### Authentication Routing

```
verifyAuth(key, message, mac)
    │
    ├─ keyID > 100?
    │       │
    │       └─ YES → Emergency Path (instant, < 10 ms)
    │                 ① key.used flag          → KEY_ALREADY_USED
    │                 ② replay map lookup      → REPLAY_DETECTED
    │                 ③ ground signature       → INVALID_SIGNATURE
    │                 ④ MAC matches            → MAC_MISMATCH
    │                 ✓ all pass               → VALID_EMERGENCY
    │
    └─ NO  → Normal Path (TESLA, buffered)
              → AWAITING_KEY_DISCLOSURE
              On key disclosure:
                ① chain integrity: K_{i-1} = SHA-256(K_i)
                ② MAC matches
                ✓ all pass  → VALID_DELAYED
```

### Normal Path (TESLA)

1. Pre-compute SHA-256 key chain: `K_{i-1} = SHA-256(K_i)`, random seed `K_n`
2. Send message with MAC; keep key secret
3. Receiver buffers message
4. After `d` packets, sender publishes key
5. Receiver verifies chain integrity then MAC
6. Attacker cannot forge without knowing future key

### Emergency Path (Instant)

1. Ground station provisions batch of signed keys before flight
2. Pilot sets emergency squawk → transponder uses one pre-stored key
3. Receiver: verify signature + MAC immediately
4. Key marked used → replay impossible

---

## Attack Simulation

Select from the **Attack Simulation** dropdown to inject synthetic threat events into the live data stream:

| Mode | Effect |
|---|---|
| None | Normal operation |
| Replay Attack | Periodically re-submits an already-used key |
| Spoofing Attack | Injects aircraft with fake ICAO addresses |
| Relay Attack (RTT) | Flags packets for proximity-bounding rejection |
| Combined Threat | Mix of replay and spoof events |

Watch the **Rejected** counter and **Threat Dashboard** respond in real time.

---

## Visualization Tools

Three dedicated windows, opened from the left sidebar:

### ⚠ Threat Dashboard
- Threat type bar chart (VALID_EMERGENCY / VALID_DELAYED / REPLAY / SPOOF / MAC ERR)
- Threat timeline (stem plot, last 60 events)
- Rejection rate gauge (colour-coded: green < 10%, amber < 30%, red ≥ 30%)
- Latency distribution histogram (last 100 events)

### 📶 Signal Visualizer
*(Most useful in Mode 4 with real hardware)*
- IQ magnitude time series (last frame)
- Power spectral density plot
- IQ constellation diagram
- Signal power history (dBFS)

### 🌍 Traffic Monitor
- Full-screen aircraft position map with flight trails
- Altitude-coded colours: white (> 35,000 ft) → blue → teal → amber (< 15,000 ft)
- Emergency aircraft shown as red triangles with ICAO labels
- Per-aircraft track history (last 20 positions)
- Traffic statistics sidebar

---

## File Structure

```
adsbauth_v5/
│
├── run_app.m                        ← ENTRY POINT — type run_app
├── main_app.m                       ← Complete GUI application
│
├── +auth/
│   ├── AuthSystem.m                 ← Dual-path engine (TESLA + instant)
│   ├── AuthKey.m                    ← Key data record
│   ├── SecureKeyStore.m             ← Simulated hardware TPM
│   ├── ProximityVerifier.m          ← Hancke-Kuhn RTT protocol
│   ├── computeMAC.m                 ← HMAC-SHA256
│   ├── generateKeypair.m            ← Key pair generation
│   └── signVerify.m                 ← Sign / verify
│
├── +utils/
│   ├── SimulationDataSource.m       ← Mode 1: synthetic data
│   ├── PrerecordedDataSource.m      ← Mode 2: ADS-B Exchange JSON
│   ├── LiveADSBApi.m                ← Mode 3: OpenSky REST API
│   ├── LiveSDRDataSource.m          ← Mode 4: RTL-SDR hardware
│   └── ADS_B_Decoder.m             ← 1090 MHz DF=17 frame decoder
│
├── +visualization/
│   ├── ThreatDashboard.m            ← Threat analysis window
│   ├── SignalVisualizer.m           ← IQ signal / spectrum window
│   └── TrafficMonitor.m             ← Global traffic map window
│
├── ADSB_Cache/                      ← Auto-created: cached downloads
├── ADSB_Data/                       ← Manual file placement folder
│   └── README.txt
│
├── README.md
├── SystemUML.txt                    ← PlantUML class diagram
└── ClassRelationships.txt           ← Plain-English class guide
```

---

## Requirements

- **MATLAB R2019b or later** (`uifigure`, `uidropdown`, `containers.Map`)
- **Java enabled** (default; used by `computeMAC.m` for HMAC-SHA256 speed)
- **No toolboxes required** for Modes 1, 2, 3
- **Mode 4 only:** Communications Toolbox Support Package for RTL-SDR

---

## Mode 4 — RTL-SDR Hardware Setup

### Windows (Zadig Driver Installation)

RTL-SDR dongles ship with a default driver that MATLAB cannot use. You must replace it with **WinUSB** using Zadig.

1. **Plug in** your RTL-SDR dongle.
2. **Download Zadig** from [https://zadig.akeo.ie/](https://zadig.akeo.ie/)
3. **Run Zadig** as Administrator.
4. Menu → **Options** → **List All Devices** (check this option).
5. From the dropdown, select **"Bulk-In, Interface (Interface 0)"**.
   - If you see multiple entries, look for the one with USB ID `0BDA:2838` or similar RTL2832.
6. In the driver box on the right, select **WinUSB**.
7. Click **Replace Driver** (or **Install Driver** if first time).
8. Wait for installation to complete (~30 seconds).
9. Unplug and re-plug the dongle.

#### Install MATLAB Support Package

1. In MATLAB: **Add-Ons** → **Get Hardware Support Packages**
2. Search for **"RTL-SDR"**
3. Install: **Communications Toolbox Support Package for RTL-SDR Radio**
4. Follow the installer (may require MATLAB restart).

#### Verify Installation

```matlab
rx = comm.SDRRTLReceiver('CenterFrequency', 1090e6);
data = rx();
fprintf('Samples received: %d\n', length(data));
release(rx);
```

If you see a sample count, the dongle is working.

---

### Linux

```bash
sudo apt-get install rtl-sdr librtlsdr-dev
# Add udev rule so MATLAB can access without sudo:
sudo sh -c 'echo "SUBSYSTEM==\"usb\", ATTRS{idVendor}==\"0bda\", MODE=\"0666\"" \
    > /etc/udev/rules.d/20-rtlsdr.rules'
sudo udevadm control --reload-rules
sudo udevadm trigger
# Verify:
rtl_test -t
```

---

### Antenna Tips

- A **1090 MHz dedicated antenna** (e.g., FlightAware 1090 MHz, or a simple 69 mm monopole) significantly improves range.
- Position vertically, near a window or outdoors — ADS-B is line-of-sight.
- Typical range: 50–200 km depending on antenna height and obstructions.
- Gain setting: start at **40 dB**. Reduce if signal appears saturated (too many noise peaks).

---

## Troubleshooting

**GUI does not open**
```matlab
addpath(genpath(pwd));
main_app();
```

**Mode 2 download fails / returns no data**
- The ADS-B Exchange server may not have data for every date. Try 2024/01/15 or another known date.
- Check internet connection and MATLAB proxy settings.

**Mode 3 returns 0 aircraft**
- OpenSky may be temporarily unavailable or rate-limiting.
- Check: `~isempty(getenv('MLM_WEB_LICENSE'))` — if true, you're on MATLAB Cloud (still supported).
- Wait a few minutes and try again.

**Mode 4 — "No device found" dialog**
- **Windows:** Confirm WinUSB driver is installed via Zadig (not the default Windows driver, not libusb0).
- **All OS:** Close SDR# / dump1090 / GQRX — only one application can use the dongle at a time.
- **Linux:** Check `rtl_test` works in terminal before trying MATLAB.
- **MATLAB:** Ensure the RTL-SDR Support Package is installed and MATLAB was restarted after installation.

**"Undefined function utils.SimulationDataSource"**
```matlab
addpath(genpath(pwd));
```
The `+utils/`, `+auth/`, `+visualization/` folders must be in the same directory as `run_app.m`.

**Charts are slow or not updating**
Reduce playback speed with the Speed slider. The timer fires at 10 Hz × speed multiplier; on slower machines, set speed to 0.5× or lower.

**Export produces empty file**
Run the simulation for at least a few frames before exporting.

---

## Extending the Code

**Change TESLA delay programmatically:**
```matlab
auth = auth.AuthSystem(20, 100);   % 20-packet delay, 100-key chain
```

**Use OpenSky with authentication (higher rate limits):**
```matlab
src = utils.LiveADSBApi('your_username', 'your_password');
```

**Add a new data source (Mode 5):**
1. Create `+utils/MyDataSource.m` with methods: `getNextFrame()`, `getStatus()`, `reset()`, `release()`
2. Add `case 5` in `main_app.m → buildDataSource()`
3. Add entry to `modeDD.Items`

**Export to CSV instead of MAT:**
In `onExport()`, replace `save(...)` with `writetable(struct2table(...), fname)`.

---

## Citation

> Sooriyaarachchi, M., & Abdelhadi, A. (2026). *Emergency-First Authentication for ADS-B: A Dual-Path Protocol with Proximity Verification.* IEEE Conference on Communications and Network Security.
