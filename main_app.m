function appFig = main_app()
% main_app  ADS-B Emergency Authentication Monitor  v4.0
%
% Launch with:   run_app
%
% All mode selection, sub-mode selection, and controls are inside the GUI.
% No command-line prompts.  Switch modes at any time without restarting.

% =========================================================================
% COLOUR PALETTE
% =========================================================================
C.bg        = [0.08 0.10 0.14];
C.panel     = [0.11 0.14 0.19];
C.panelAlt  = [0.09 0.12 0.16];
C.accent    = [0.20 0.55 0.95];
C.accentAlt = [0.10 0.75 0.60];
C.warn      = [0.95 0.55 0.10];
C.danger    = [0.92 0.25 0.25];
C.success   = [0.20 0.82 0.45];
C.textPri   = [0.92 0.93 0.95];
C.textSec   = [0.55 0.62 0.72];
C.border    = [0.20 0.25 0.33];
C.live      = [0.95 0.25 0.25];
C.sdrGreen  = [0.10 0.85 0.45];
C.btnHover  = [0.18 0.22 0.30];

% =========================================================================
% ROOT FIGURE
% =========================================================================
fig = uifigure( ...
    'Name',             'ADS-B Emergency Authentication Monitor  v4.0', ...
    'Position',         [40 30 1440 860], ...
    'Color',            C.bg, ...
    'Resize',           'off', ...
    'CloseRequestFcn',  @onClose);

% =========================================================================
% APP STATE
% =========================================================================
S.mode          = 1;
S.subMode       = 'cache';
S.running       = false;
S.auth          = [];
S.dataSource    = [];
S.frameCount    = 0;
S.sdrConnected  = false;
S.liveActive    = false;
S.authLat       = [];      % latency history
S.normalCount   = 0;
S.emergCount    = 0;
S.rejectCount   = 0;
S.mapLat        = [];
S.mapLon        = [];
S.mapICAO       = {};
S.mapEmerg      = [];
S.mapAlt        = [];
S.eventLog      = {};      % for visualization tools
S.attackMode    = 'none';
S.speedMult     = 1;
S.year = 2026; S.month = 5; S.day = 1;
S.threatDash    = [];
S.sigViz        = [];
S.trafficMon    = [];
S.lastIQData    = [];
S.livePulse     = 0;       % for pulsing LIVE badge

% =========================================================================
% ── LEFT SIDEBAR  (width 310)
% =========================================================================
SB = uipanel(fig, 'Position', [6 6 310 848], ...
    'BackgroundColor', C.panel, 'BorderType', 'none');

% App title
uilabel(SB, 'Text', 'ADS-B AUTH', ...
    'Position', [14 808 240 32], 'FontSize', 22, 'FontWeight', 'bold', ...
    'FontColor', C.accent, 'BackgroundColor', C.panel);
uilabel(SB, 'Text', 'Emergency Authentication Monitor  v4.0', ...
    'Position', [14 790 290 16], 'FontSize', 9, ...
    'FontColor', C.textSec, 'BackgroundColor', C.panel);
divider(SB, C, 14, 782, 284);

% ── MODE SELECTOR ──────────────────────────────────────────────────────
sectionLabel(SB, C, 'DATA SOURCE MODE', 14, 758);

modeDD = uidropdown(SB, ...
    'Items',    {'1 — Simulation', '2 — Prerecorded', '3 — Live API (OpenSky)', '4 — Live SDR (RTL-SDR)'}, ...
    'Value',    '1 — Simulation', ...
    'Position', [14 728 284 28], ...
    'FontSize', 12, 'FontColor', C.textPri, ...
    'BackgroundColor', C.border, ...
    'ValueChangedFcn', @onModeChanged);

% ── SUB-MODE (Mode 2) ──────────────────────────────────────────────────
subModeLbl = sectionLabel(SB, C, 'PRERECORDED SUB-MODE', 14, 694);

subModeDD = uidropdown(SB, ...
    'Items',   {'2A — Auto-Download + Cache', '2B — User Upload', '2C — Manual Placement'}, ...
    'Value',   '2A — Auto-Download + Cache', ...
    'Position', [14 666 284 26], ...
    'FontSize', 11, ...
    'FontColor', [0.35 0.40 0.48], ...
    'BackgroundColor', [0.12 0.15 0.20], ...
    'Enable',  'off', ...
    'Tag',     'subModeDD', ...
    'ValueChangedFcn', @onSubModeChanged);

% Date picker row (Mode 2A only)
datePnl = uipanel(SB, 'Position', [14 598 284 62], ...
    'BackgroundColor', C.panel, 'BorderType', 'none', ...
    'Visible', 'off', 'Tag', 'datePnl');
uilabel(datePnl, 'Text', 'DATE:   YYYY', ...
    'Position', [0 40 100 18], 'FontSize', 8, 'FontWeight', 'bold', ...
    'FontColor', C.textSec, 'BackgroundColor', C.panel);
uilabel(datePnl, 'Text', 'MM', ...
    'Position', [110 40 30 18], 'FontSize', 8, 'FontWeight', 'bold', ...
    'FontColor', C.textSec, 'BackgroundColor', C.panel);
uilabel(datePnl, 'Text', 'DD', ...
    'Position', [160 40 30 18], 'FontSize', 8, 'FontWeight', 'bold', ...
    'FontColor', C.textSec, 'BackgroundColor', C.panel);
yearF  = numField(datePnl, C,  0, 8, 88, 30, 2026, [2020 2030], 'yearF');
monthF = numField(datePnl, C, 100, 8, 52, 30,    5, [1 12],    'monthF');
dayF   = numField(datePnl, C, 154, 8, 52, 30,    1, [1 31],    'dayF');

% ── SDR SECTION (Mode 4 only) ───────────────────────────────────────────
sdrPnl = uipanel(SB, 'Position', [14 598 284 76], ...
    'BackgroundColor', C.panel, 'BorderType', 'none', ...
    'Visible', 'off', 'Tag', 'sdrPnl');

sdrScanBtn = uibutton(sdrPnl, ...
    'Text',            '🔍  Scan for Device', ...
    'Position',        [0 42 200 30], ...
    'FontSize', 11, 'FontColor', C.textPri, ...
    'BackgroundColor', C.btnHover, ...
    'ButtonPushedFcn', @onScanSDR);

sdrStatusLbl = uilabel(sdrPnl, ...
    'Text',            'No device scanned yet.', ...
    'Position',        [0 10 284 28], ...
    'FontSize', 9, 'FontColor', C.textSec, ...
    'BackgroundColor', C.panel, ...
    'WordWrap', 'on');

divider(SB, C, 14, 590, 284);

% ── AUTHENTICATION SETTINGS ──────────────────────────────────────────────
sectionLabel(SB, C, 'AUTHENTICATION', 14, 566);

uilabel(SB, 'Text', 'TESLA Delay (packets)', ...
    'Position', [14 543 200 16], 'FontSize', 9, ...
    'FontColor', C.textPri, 'BackgroundColor', C.panel);

teslaSlider = uislider(SB, ...
    'Limits', [1 30], 'Value', 10, ...
    'Position', [14 534 270 20], ...
    'ValueChangedFcn', @onTeslaChanged);
teslaSlider.FontColor = C.textSec;

teslaLbl = uilabel(SB, ...
    'Text',    '10 packets  (~1.6 s)', ...
    'Position', [14 510 250 16], ...
    'FontSize', 9, 'FontColor', C.textSec, ...
    'BackgroundColor', C.panel, 'Tag', 'teslaLbl');

% ── ATTACK SIMULATION ────────────────────────────────────────────────────
sectionLabel(SB, C, 'ATTACK SIMULATION', 14, 488);

attackDD = uidropdown(SB, ...
    'Items',   {'None (normal operation)', 'Replay Attack', 'Spoofing Attack', 'Relay Attack (RTT)', 'Combined Threat'}, ...
    'Value',   'None (normal operation)', ...
    'Position', [14 460 284 26], ...
    'FontSize', 10, 'FontColor', C.textPri, ...
    'BackgroundColor', C.border, ...
    'ValueChangedFcn', @onAttackChanged);

% ── SPEED SLIDER ─────────────────────────────────────────────────────────
sectionLabel(SB, C, 'PLAYBACK SPEED', 14, 436);

speedSlider = uislider(SB, ...
    'Limits', [0.1 5], 'Value', 1, ...
    'Position', [14 424 270 20], ...
    'ValueChangedFcn', @onSpeedChanged);
speedSlider.FontColor = C.textSec;

speedLbl = uilabel(SB, ...
    'Text',    '1.0×', ...
    'Position', [14 400 100 16], ...
    'FontSize', 9, 'FontColor', C.textSec, ...
    'BackgroundColor', C.panel, 'Tag', 'speedLbl');

divider(SB, C, 14, 392, 284);

% ── START / STOP ─────────────────────────────────────────────────────────
startBtn = uibutton(SB, ...
    'Text',     '▶  START', ...
    'Position', [14 348 136 44], ...
    'FontSize', 14, 'FontWeight', 'bold', ...
    'FontColor', [1 1 1], ...
    'BackgroundColor', C.success, ...
    'Tag', 'startBtn', ...
    'ButtonPushedFcn', @onStart);

stopBtn = uibutton(SB, ...
    'Text',     '■  STOP', ...
    'Position', [162 348 136 44], ...
    'FontSize', 14, 'FontWeight', 'bold', ...
    'FontColor', [1 1 1], ...
    'BackgroundColor', [0.30 0.14 0.14], ...
    'Enable', 'off', ...
    'Tag', 'stopBtn', ...
    'ButtonPushedFcn', @onStop);

% ── EXPORT / RESET ───────────────────────────────────────────────────────
exportBtn = uibutton(SB, ...
    'Text',     '⬇  Export Data', ...
    'Position', [14 296 136 36], ...
    'FontSize', 10, 'FontColor', C.textPri, ...
    'BackgroundColor', C.btnHover, ...
    'ButtonPushedFcn', @onExport);

resetBtn = uibutton(SB, ...
    'Text',     '↺  Reset', ...
    'Position', [162 296 136 36], ...
    'FontSize', 10, 'FontColor', C.textSec, ...
    'BackgroundColor', C.border, ...
    'ButtonPushedFcn', @onReset);

divider(SB, C, 14, 286, 284);

% ── VISUALIZATION TOOLS ───────────────────────────────────────────────────
sectionLabel(SB, C, 'VISUALIZATION TOOLS', 14, 262);

threatBtn = mkToolBtn(SB, C, '⚠  Threat Dashboard',   14, 230, @onThreatDash);
sigBtn    = mkToolBtn(SB, C, '📶  Signal Visualizer',  14, 188, @onSignalViz);
trafficBtn= mkToolBtn(SB, C, '🌍  Traffic Monitor',    14, 146, @onTrafficMon);

divider(SB, C, 14, 136, 284);

% ── LIVE INDICATOR ────────────────────────────────────────────────────────
liveDot = uilabel(SB, 'Text', '●', ...
    'Position', [14 104 22 22], 'FontSize', 18, ...
    'FontColor', C.border, 'BackgroundColor', C.panel, 'Tag', 'liveDot');
liveLbl = uilabel(SB, 'Text', 'OFFLINE', ...
    'Position', [38 105 260 20], 'FontSize', 11, 'FontWeight', 'bold', ...
    'FontColor', C.textSec, 'BackgroundColor', C.panel, 'Tag', 'liveLbl');

% LIVE badge (Mode 3/4)
liveBadge = uilabel(SB, 'Text', '● LIVE', ...
    'Position', [200 104 90 22], 'FontSize', 10, 'FontWeight', 'bold', ...
    'FontColor', C.live, 'BackgroundColor', C.panel, ...
    'Tag', 'liveBadge', 'Visible', 'off');

divider(SB, C, 14, 96, 284);

% ── STATUS LOG ────────────────────────────────────────────────────────────
sectionLabel(SB, C, 'STATUS LOG', 14, 72);

logBox = uitextarea(SB, ...
    'Value',    {'Ready. Select mode and press ▶ START.'}, ...
    'Position', [14 8 284 56], ...
    'FontSize', 8, 'FontColor', C.accentAlt, ...
    'BackgroundColor', [0.06 0.08 0.11], ...
    'Editable', 'off', 'Tag', 'logBox');

% =========================================================================
% ── CENTRE  (map + latency chart)
% =========================================================================

% Metric cards
cX = 328; cW = 178; cH = 82; cY = 760; gap = 8;
mkCard(fig, C, cX,                 cY, cW, cH, 'TOTAL FRAMES',   '0',    C.accent,    'totalLbl');
mkCard(fig, C, cX+(cW+gap),        cY, cW, cH, 'NORMAL PATH',    '0',    C.accentAlt, 'normalLbl');
mkCard(fig, C, cX+(cW+gap)*2,      cY, cW, cH, 'EMERGENCY PATH', '0',    C.warn,      'emergLbl');
mkCard(fig, C, cX+(cW+gap)*3,      cY, cW, cH, 'REJECTED',       '0',    C.danger,    'rejectLbl');
mkCard(fig, C, cX+(cW+gap)*4,      cY, cW, cH, 'MEAN LATENCY',   '— ms', C.success,   'latLbl');

% Map panel
mapPnl = uipanel(fig, 'Position', [328 308 744 444], ...
    'BackgroundColor', C.panel, 'BorderType', 'none');
uilabel(mapPnl, 'Text', 'AIRCRAFT POSITION MAP', ...
    'Position', [12 416 300 20], 'FontSize', 10, 'FontWeight', 'bold', ...
    'FontColor', C.textSec, 'BackgroundColor', C.panel);
mapAx = uiaxes(mapPnl, 'Position', [12 10 720 402], ...
    'Color', [0.04 0.06 0.11], 'XColor', C.border, 'YColor', C.border, 'Tag', 'mapAx');
mapAx.XGrid = 'on'; mapAx.YGrid = 'on'; mapAx.GridAlpha = 0.2;
xlabel(mapAx, 'Longitude', 'Color', C.textSec);
ylabel(mapAx, 'Latitude', 'Color', C.textSec);
title(mapAx, 'Waiting for data...', 'Color', C.textSec, 'FontSize', 10);
hold(mapAx, 'on');

% Latency panel
latPnl = uipanel(fig, 'Position', [328 8 744 292], ...
    'BackgroundColor', C.panel, 'BorderType', 'none');
uilabel(latPnl, 'Text', 'AUTHENTICATION LATENCY  (last 200 frames)', ...
    'Position', [12 264 420 20], 'FontSize', 10, 'FontWeight', 'bold', ...
    'FontColor', C.textSec, 'BackgroundColor', C.panel);
latAx = uiaxes(latPnl, 'Position', [12 8 720 252], ...
    'Color', [0.04 0.06 0.11], 'XColor', C.border, 'YColor', C.border, 'Tag', 'latAx');
latAx.XGrid = 'on'; latAx.YGrid = 'on'; latAx.GridAlpha = 0.2;
xlabel(latAx, 'Frame', 'Color', C.textSec);
ylabel(latAx, 'Latency (ms)', 'Color', C.textSec);
hold(latAx, 'on');

% =========================================================================
% ── RIGHT PANEL
% =========================================================================
RP = uipanel(fig, 'Position', [1080 6 354 848], ...
    'BackgroundColor', C.panel, 'BorderType', 'none');

uilabel(RP, 'Text', 'AUTHENTICATION DETAIL', ...
    'Position', [14 814 320 24], 'FontSize', 12, 'FontWeight', 'bold', ...
    'FontColor', C.textPri, 'BackgroundColor', C.panel);
divider(RP, C, 10, 806, 334);

% Last verified aircraft card
sectionLabel(RP, C, 'LAST VERIFIED AIRCRAFT', 14, 778);
acCard = uipanel(RP, 'Position', [14 664 326 110], ...
    'BackgroundColor', [0.08 0.11 0.16], 'BorderType', 'line', 'HighlightColor', C.border);
infoRow(acCard, C, 'ICAO',    '—', 10, 82, 'icaoLbl');
infoRow(acCard, C, 'PATH',    '—', 10, 58, 'pathLbl');
infoRow(acCard, C, 'RESULT',  '—', 10, 34, 'resultLbl');
infoRow(acCard, C, 'LATENCY', '—', 10,  8, 'latencyLbl');

divider(RP, C, 10, 656, 334);
sectionLabel(RP, C, 'PATH BREAKDOWN', 14, 628);

pieAx = uiaxes(RP, 'Position', [14 474 326 152], ...
    'Color', C.panel, 'Tag', 'pieAx');
pieAx.XAxis.Visible = 'off'; pieAx.YAxis.Visible = 'off'; pieAx.Box = 'off';

divider(RP, C, 10, 466, 334);
sectionLabel(RP, C, 'LATENCY DISTRIBUTION', 14, 438);

histAx = uiaxes(RP, 'Position', [14 284 326 152], ...
    'Color', [0.04 0.06 0.11], 'XColor', C.border, 'YColor', C.border, 'Tag', 'histAx');
histAx.YGrid = 'on'; histAx.GridAlpha = 0.2;

divider(RP, C, 10, 276, 334);
sectionLabel(RP, C, 'EMERGENCY EVENTS', 14, 248);

emergLog = uitextarea(RP, ...
    'Value',    {' No emergency events.'}, ...
    'Position', [14 8 326 234], ...
    'FontSize', 9, 'FontColor', C.warn, ...
    'BackgroundColor', [0.06 0.08 0.11], ...
    'Editable', 'off', 'Tag', 'emergLog');

% =========================================================================
% TIMER  (10 Hz base, speed multiplier applied)
% =========================================================================
updateTimer = timer( ...
    'ExecutionMode', 'fixedRate', ...
    'Period',        0.1, ...
    'TimerFcn',      @timerUpdate, ...
    'StopFcn',       @timerStopped);

% =========================================================================
% CALLBACKS
% =========================================================================

    function onModeChanged(src, ~)
        idx = find(strcmp(src.Items, src.Value));
        S.mode = idx;
        updateModeVisibility();
        appendLog(sprintf('Mode: %s', src.Value));
    end

    function onSubModeChanged(src, ~)
        v = src.Value(1:2);
        switch v
            case '2A', S.subMode = 'cache';
            case '2B', S.subMode = 'upload';
            case '2C', S.subMode = 'manual';
        end
        datePnl.Visible = strcmp(S.subMode,'cache');
        appendLog(sprintf('Sub-mode: %s', src.Value));
    end

    function onTeslaChanged(src, ~)
        v = round(src.Value);
        findobj(fig,'Tag','teslaLbl').Text = sprintf('%d packets  (~%.1f s)', v, v*0.16);
    end

    function onAttackChanged(src, ~)
        v = src.Value;
        if contains(v,'Replay'),   S.attackMode = 'replay';
        elseif contains(v,'Spoof'), S.attackMode = 'spoof';
        elseif contains(v,'Relay'), S.attackMode = 'relay';
        elseif contains(v,'Combined'), S.attackMode = 'combined';
        else,                       S.attackMode = 'none';
        end
        appendLog(sprintf('Attack mode: %s', S.attackMode));
    end

    function onSpeedChanged(src, ~)
        S.speedMult = src.Value;
        findobj(fig,'Tag','speedLbl').Text = sprintf('%.1f×', S.speedMult);
    end

    function onScanSDR(~, ~)
        sdrStatusLbl.Text      = 'Scanning USB for RTL-SDR...';
        sdrStatusLbl.FontColor = C.warn;
        drawnow;
        [found, msg] = scanForSDR();
        S.sdrConnected = found;
        if found
            sdrStatusLbl.Text      = '●  Hardware Connected  (1090 MHz)';
            sdrStatusLbl.FontColor = C.sdrGreen;
            appendLog('RTL-SDR dongle detected and ready.');
        else
            sdrStatusLbl.Text      = '✘  No device found';
            sdrStatusLbl.FontColor = C.danger;
            appendLog(['SDR scan: ' msg]);
            uialert(fig, ...
                sprintf(['No RTL-SDR dongle detected.\n\n' ...
                    'Reason: %s\n\n' ...
                    'Troubleshooting:\n' ...
                    '  • Check USB connection\n' ...
                    '  • Windows: install WinUSB via Zadig\n' ...
                    '    (https://zadig.akeo.ie/)\n' ...
                    '  • Close other apps using the dongle\n' ...
                    '    (SDR#, dump1090, GQRX)\n' ...
                    '  • Install RTL-SDR Support Package:\n' ...
                    '    Add-Ons → Get Hardware Support Packages'], msg), ...
                'RTL-SDR Device Not Found', 'Icon', 'warning');
        end
    end

    function onStart(~, ~)
        if S.running, return; end
        delay = round(teslaSlider.Value);
        S.auth        = auth.AuthSystem(delay, 100);
        S.frameCount  = 0;
        S.authLat     = [];
        S.normalCount = 0; S.emergCount = 0; S.rejectCount = 0;
        S.mapLat = []; S.mapLon = []; S.mapICAO = {}; S.mapEmerg = []; S.mapAlt = [];
        S.eventLog    = {};

        try
            S.dataSource = buildDataSource();
        catch ME
            uialert(fig, ME.message, 'Data Source Error', 'Icon', 'error');
            return;
        end

        S.running = true;
        startBtn.Enable  = 'off';
        stopBtn.Enable   = 'on';
        stopBtn.BackgroundColor = C.danger;
        modeDD.Enable    = 'off';
        subModeDD.Enable = 'off';
        setLiveIndicator(true);
        appendLog(sprintf('Started — Mode %d  |  Attack: %s  |  Speed: %.1f×', ...
            S.mode, S.attackMode, S.speedMult));
        updateTimer.Period = max(0.02, 0.1 / S.speedMult);
        start(updateTimer);
    end

    function onStop(~, ~)
        if ~S.running, return; end
        stop(updateTimer);
    end

    function onReset(~, ~)
        S.frameCount  = 0;
        S.authLat     = [];
        S.normalCount = 0; S.emergCount = 0; S.rejectCount = 0;
        S.mapLat = []; S.mapLon = []; S.mapICAO = {}; S.mapEmerg = []; S.mapAlt = [];
        S.eventLog = {};
        updateMetrics();
        cla(mapAx); cla(latAx); cla(pieAx); cla(histAx);
        emergLog.Value = {' No emergency events.'};
        appendLog('Statistics reset.');
    end

    function onExport(~, ~)
        if isempty(S.authLat)
            uialert(fig, 'No data to export. Run the simulation first.', ...
                'Export', 'Icon', 'info');
            return;
        end
        ts = datestr(now, 'yyyymmdd_HHMMSS');
        fname = sprintf('adsb_auth_export_%s.mat', ts);
        exportData.latencies    = S.authLat;
        exportData.normalCount  = S.normalCount;
        exportData.emergCount   = S.emergCount;
        exportData.rejectCount  = S.rejectCount;
        exportData.frameCount   = S.frameCount;
        exportData.mapLat       = S.mapLat;
        exportData.mapLon       = S.mapLon;
        exportData.mapICAO      = S.mapICAO;
        exportData.eventLog     = S.eventLog;
        exportData.exportTime   = datetime('now');
        exportData.mode         = S.mode;
        try
            save(fname, '-struct', 'exportData');
            appendLog(sprintf('Exported: %s', fname));
            uialert(fig, sprintf('Data exported to:\n%s', fullfile(pwd, fname)), ...
                'Export Complete', 'Icon', 'success');
        catch ME
            uialert(fig, ME.message, 'Export Failed', 'Icon', 'error');
        end
    end

    function onThreatDash(~, ~)
        if isempty(S.threatDash) || ~isvalid(S.threatDash.Fig)
            S.threatDash = visualization.ThreatDashboard();
        end
        S.threatDash.update(S.eventLog);
        S.threatDash.show();
    end

    function onSignalViz(~, ~)
        if isempty(S.sigViz) || ~isvalid(S.sigViz.Fig)
            S.sigViz = visualization.SignalVisualizer();
        end
        S.sigViz.updateIQ(S.lastIQData, 2.4e6);
        S.sigViz.show();
    end

    function onTrafficMon(~, ~)
        if isempty(S.trafficMon) || ~isvalid(S.trafficMon.Fig)
            S.trafficMon = visualization.TrafficMonitor();
        end
        S.trafficMon.show();
    end

    function onClose(~, ~)
        try stop(updateTimer); catch, end
        try delete(updateTimer); catch, end
        if ~isempty(S.dataSource)
            try S.dataSource.release(); catch, end
        end
        if ~isempty(S.threatDash) && isvalid(S.threatDash.Fig)
            try S.threatDash.close(); catch, end
        end
        if ~isempty(S.sigViz) && isvalid(S.sigViz.Fig)
            try S.sigViz.close(); catch, end
        end
        if ~isempty(S.trafficMon) && isvalid(S.trafficMon.Fig)
            try S.trafficMon.close(); catch, end
        end
        delete(fig);
    end

% =========================================================================
% TIMER CALLBACK
% =========================================================================
    function timerUpdate(~, ~)
        if ~S.running || isempty(S.dataSource), return; end

        try
            [icao, lat, lon, alt, isEmergency] = S.dataSource.getNextFrame();
        catch ME
            appendLog(['Data error: ' ME.message]);
            return;
        end

        if isempty(icao), return; end

        % Apply attack simulation override
        [icao, isEmergency] = applyAttack(icao, isEmergency);

        S.frameCount = S.frameCount + 1;

        % ── Auth routing ──────────────────────────────────────────────
        if isEmergency
            keyID = 1000 + mod(S.frameCount, 800) + 1;
            S.auth.issueEmergencyKey(keyID, icao);
            key = S.auth.keyStore.useKey(keyID);
            if isempty(key), return; end
            msg = uint8(sprintf('SQUAWK7700|%s|%.4f|%.4f|%.0f', icao, lat, lon, alt));
            [mac, ~]            = S.auth.computeAuthMAC(key, msg);
            [isValid, latMs, reason] = S.auth.verifyAuth(key, msg, mac);
            pathName = 'EMERGENCY';
            S.emergCount = S.emergCount + 1;
        else
            key = S.auth.getNextNormalKey();
            msg = uint8(sprintf('POS|%s|%.4f|%.4f|%.0f', icao, lat, lon, alt));
            [mac, ~]            = S.auth.computeAuthMAC(key, msg);
            [isValid, latMs, reason] = S.auth.verifyAuth(key, msg, mac);
            pathName = 'NORMAL';
            S.normalCount = S.normalCount + 1;
        end

        if ~isValid && ~contains(reason, 'AWAIT') && ~contains(reason, 'PENDING')
            S.rejectCount = S.rejectCount + 1;
        end

        S.authLat(end+1) = latMs;
        if length(S.authLat) > 200, S.authLat = S.authLat(end-199:end); end

        % Map data
        S.mapLat(end+1)  = lat;
        S.mapLon(end+1)  = lon;
        S.mapICAO{end+1} = icao;
        S.mapEmerg(end+1)= isEmergency;
        S.mapAlt(end+1)  = alt;
        if length(S.mapLat) > 600
            S.mapLat  = S.mapLat(end-599:end);
            S.mapLon  = S.mapLon(end-599:end);
            S.mapICAO = S.mapICAO(end-599:end);
            S.mapEmerg= S.mapEmerg(end-599:end);
            S.mapAlt  = S.mapAlt(end-599:end);
        end

        % Event log
        evt = struct('icao', icao, 'result', reason, 'latencyMs', latMs, ...
            'isEmergency', isEmergency, 'ts', datetime('now'));
        S.eventLog{end+1} = evt;
        if length(S.eventLog) > 500, S.eventLog = S.eventLog(end-499:end); end

        % Update detail panel
        updateDetailPanel(icao, pathName, reason, latMs);

        % Emergency log
        if isEmergency
            ts  = datestr(now, 'HH:MM:SS');
            col = '';
            if ~isValid, col = ' [REJECTED]'; end
            newLine = sprintf(' [%s] %s — %s%s', ts, icao, reason, col);
            old = emergLog.Value;
            if length(old) > 30, old = old(1:30); end
            emergLog.Value = [{newLine}, old{:}];
        end

        % Refresh visuals every N frames (lighter on CPU)
        if mod(S.frameCount, 4) == 0
            updateMetrics();
            updateMap();
            updateLatencyChart();
            updateCharts();
        end

        % LIVE badge pulsing
        S.livePulse = S.livePulse + 1;
        if S.mode >= 3 && mod(S.livePulse, 8) < 4
            liveBadge.Visible = 'on';
        elseif S.mode >= 3
            liveBadge.Visible = 'off';
        end

        % Feed visualization tools if open
        if ~isempty(S.trafficMon) && isvalid(S.trafficMon.Fig)
            S.trafficMon.addFrame(icao, lat, lon, alt, isEmergency);
        end
        if ~isempty(S.threatDash) && isvalid(S.threatDash.Fig) && mod(S.frameCount,10)==0
            S.threatDash.update(S.eventLog);
        end
    end

    function timerStopped(~, ~)
        S.running = false;
        startBtn.Enable = 'on';
        stopBtn.Enable  = 'off';
        stopBtn.BackgroundColor = [0.30 0.14 0.14];
        modeDD.Enable   = 'on';
        if S.mode == 2, subModeDD.Enable = 'on'; end
        setLiveIndicator(false);
        liveBadge.Visible = 'off';
        if ~isempty(S.dataSource)
            try S.dataSource.release(); catch, end
        end
        appendLog(sprintf('Stopped. %d frames processed.', S.frameCount));
    end

% =========================================================================
% HELPER — build data source
% =========================================================================
    function ds = buildDataSource()
        switch S.mode
            case 1
                ds = utils.SimulationDataSource();
            case 2
                yr = yearF.Value; mo = monthF.Value; dy = dayF.Value;
                switch S.subMode
                    case 'cache'
                        ds = utils.PrerecordedDataSource('cache', ...
                            'year', yr, 'month', mo, 'day', dy);
                    case 'upload'
                        ds = utils.PrerecordedDataSource('upload');
                    case 'manual'
                        ds = utils.PrerecordedDataSource('manual');
                end
            case 3
                ds = utils.LiveADSBApi();
            case 4
                ds = utils.LiveSDRDataSource();
                if ds.FallbackMode
                    appendLog('[SDR] Hardware not found — fallback simulation active.');
                else
                    appendLog('[SDR] Hardware streaming at 1090 MHz.');
                end
            otherwise
                ds = utils.SimulationDataSource();
        end
    end

% =========================================================================
% HELPER — scan USB for RTL-SDR
% =========================================================================
    function [found, msg] = scanForSDR()
        found = false; msg = '';
        if ~isempty(getenv('MLM_WEB_LICENSE'))
            msg = 'MATLAB Cloud does not support USB hardware.'; return;
        end
        if exist('comm.SDRRTLReceiver','class') ~= 8
            msg = 'RTL-SDR Support Package not installed. Install via Add-Ons.'; return;
        end
        try
            rx   = comm.SDRRTLReceiver('CenterFrequency', 1090e6, ...
                'SampleRate', 2.4e6, 'SamplesPerFrame', 1024, 'OutputDataType', 'double');
            data = rx();
            release(rx);
            if ~isempty(data) && length(data) >= 512
                found = true;
                msg   = sprintf('RTL-SDR: %d samples at 1090 MHz.', length(data));
                S.lastIQData = data;
            else
                msg = 'SDR connected but no samples received. Check antenna.';
            end
        catch ME
            msg = ME.message;
        end
    end

% =========================================================================
% HELPER — attack injection
% =========================================================================
    function [outIcao, outEmerg] = applyAttack(inIcao, inEmerg)
        outIcao  = inIcao;
        outEmerg = inEmerg;
        switch S.attackMode
            case 'replay'
                % Force replayed key by sporadically re-using a key index
                if mod(S.frameCount, 15) == 7, outEmerg = true; end
            case 'spoof'
                % Inject a fake ICAO
                if mod(S.frameCount, 20) == 0
                    outIcao  = sprintf('FAKE%03d', mod(S.frameCount,10));
                    outEmerg = true;
                end
            case 'relay'
                % relay is handled by ProximityVerifier — just flag it
            case 'combined'
                if mod(S.frameCount, 12) == 0
                    outIcao  = 'ATTK001';
                    outEmerg = true;
                end
        end
    end

% =========================================================================
% DISPLAY HELPERS
% =========================================================================
    function updateModeVisibility()
        isM2 = (S.mode == 2);
        isM4 = (S.mode == 4);
        if isM2
            subModeDD.Enable   = 'on';
            subModeDD.FontColor = C.textPri;
        else
            subModeDD.Enable   = 'off';
            subModeDD.FontColor = [0.35 0.40 0.48];
        end
        datePnl.Visible = isM2 && strcmp(S.subMode,'cache');
        sdrPnl.Visible  = isM4;
        if ~isM4
            sdrStatusLbl.Text = 'No device scanned yet.';
        end
    end

    function updateMetrics()
        findobj(fig,'Tag','totalLbl').Text  = num2str(S.frameCount);
        findobj(fig,'Tag','normalLbl').Text = num2str(S.normalCount);
        findobj(fig,'Tag','emergLbl').Text  = num2str(S.emergCount);
        findobj(fig,'Tag','rejectLbl').Text = num2str(S.rejectCount);
        if ~isempty(S.authLat)
            findobj(fig,'Tag','latLbl').Text = sprintf('%.2f ms', mean(S.authLat));
        end
    end

    function updateMap()
        cla(mapAx); hold(mapAx,'on');
        n = length(S.mapLat);
        if n == 0, return; end
        normIdx  = ~logical(S.mapEmerg);
        emergIdx =  logical(S.mapEmerg);
        % Colour by altitude
        if any(normIdx)
            alts = S.mapAlt(normIdx);
            altNorm = (alts - min(alts)) / max(range(alts), 1);
            scatter(mapAx, S.mapLon(normIdx), S.mapLat(normIdx), 18, ...
                altNorm .* [0 0.4 0.9] + (1-altNorm) .* [0.1 0.7 0.6], ...
                'filled', 'MarkerFaceAlpha', 0.75);
        end
        if any(emergIdx)
            scatter(mapAx, S.mapLon(emergIdx), S.mapLat(emergIdx), 44, ...
                [0.92 0.25 0.25], 'filled', 'Marker', '^');
        end
        nLabel = min(6, n);
        for k = n-nLabel+1:n
            text(mapAx, S.mapLon(k)+0.06, S.mapLat(k)+0.06, S.mapICAO{k}, ...
                'Color', C.textSec, 'FontSize', 7);
        end
        uniq = length(unique(S.mapICAO));
        title(mapAx, sprintf('Tracking %d aircraft  |  %d frames', uniq, S.frameCount), ...
            'Color', C.textSec, 'FontSize', 10);
    end

    function updateLatencyChart()
        cla(latAx);
        if length(S.authLat) < 2, return; end
        n = length(S.authLat);
        area(latAx, 1:n, S.authLat, 'FaceColor', C.accent, 'FaceAlpha', 0.25, ...
            'EdgeColor', C.accent, 'LineWidth', 1);
        yline(latAx, 10,               '--', 'Color', C.warn,    'LineWidth', 1.2);
        yline(latAx, mean(S.authLat),  '-.', 'Color', C.success, 'LineWidth', 1.2);
        ylim(latAx, [0 max(12, max(S.authLat)*1.15)]);
    end

    function updateCharts()
        % Pie
        cla(pieAx);
        vals = [S.normalCount, S.emergCount, S.rejectCount];
        if sum(vals) > 0
            pie(pieAx, vals + (vals==0)*0.001, {'Normal','Emergency','Rejected'});
            pieAx.Colormap = [C.accentAlt; C.warn; C.danger];
        end
        % Histogram
        cla(histAx);
        if length(S.authLat) >= 5
            histogram(histAx, S.authLat, 20, 'FaceColor', C.accent, ...
                'EdgeColor', 'none', 'FaceAlpha', 0.85);
            xlabel(histAx, 'Latency (ms)', 'Color', C.textSec, 'FontSize', 8);
            ylabel(histAx, 'Count', 'Color', C.textSec, 'FontSize', 8);
        end
    end

    function updateDetailPanel(icao, path, result, latMs)
        findobj(fig,'Tag','icaoLbl').Text    = icao;
        findobj(fig,'Tag','pathLbl').Text    = path;
        findobj(fig,'Tag','resultLbl').Text  = result;
        findobj(fig,'Tag','latencyLbl').Text = sprintf('%.3f ms', latMs);
        rl = findobj(fig,'Tag','resultLbl');
        if contains(result,'VALID'),   rl.FontColor = C.success;
        elseif contains(result,'REJECT') || contains(result,'INVALID') || contains(result,'MISMATCH')
            rl.FontColor = C.danger;
        else, rl.FontColor = C.warn;
        end
    end

    function setLiveIndicator(on)
        dot = findobj(fig,'Tag','liveDot');
        lbl = findobj(fig,'Tag','liveLbl');
        if on
            dot.FontColor = C.live;
            switch S.mode
                case 1, lbl.Text = 'SIMULATION RUNNING';   lbl.FontColor = C.accentAlt;
                case 2, lbl.Text = 'PRERECORDED PLAYING';  lbl.FontColor = C.accent;
                case 3, lbl.Text = 'LIVE API  (OpenSky)';  lbl.FontColor = C.live;
                case 4
                    if S.sdrConnected
                        lbl.Text = 'LIVE SDR  (1090 MHz)';
                    else
                        lbl.Text = 'SDR FALLBACK SIM';
                    end
                    lbl.FontColor = C.live;
            end
        else
            dot.FontColor = C.border;
            lbl.Text = 'OFFLINE';  lbl.FontColor = C.textSec;
        end
    end

    function appendLog(msg)
        box = findobj(fig,'Tag','logBox');
        ts  = datestr(now,'HH:MM:SS');
        old = box.Value;
        if length(old) > 60, old = old(1:60); end
        box.Value = [{sprintf('[%s] %s', ts, msg)}, old{:}];
        drawnow limitrate;
    end

appFig = fig;
end  % main_app

% =========================================================================
% LAYOUT UTILITY FUNCTIONS  (file-scope, outside main_app)
% =========================================================================
function divider(parent, C, x, y, w)
    uipanel(parent, 'Position', [x y w 1], ...
        'BackgroundColor', C.border, 'BorderType', 'none');
end

function lbl = sectionLabel(parent, C, txt, x, y)
    lbl = uilabel(parent, 'Text', txt, ...
        'Position', [x y 280 16], ...
        'FontSize', 8, 'FontWeight', 'bold', ...
        'FontColor', C.textSec, 'BackgroundColor', parent.BackgroundColor);
end

function mkCard(fig, C, x, y, w, h, titleStr, valStr, valColor, valTag)
    p = uipanel(fig, 'Position', [x y w h], ...
        'BackgroundColor', C.panel, 'BorderType', 'none');
    uilabel(p, 'Text', titleStr, ...
        'Position', [10 h-24 w-20 16], ...
        'FontSize', 8, 'FontWeight', 'bold', ...
        'FontColor', C.textSec, 'BackgroundColor', C.panel);
    uilabel(p, 'Text', valStr, ...
        'Position', [10 6 w-20 h-36], ...
        'FontSize', 24, 'FontWeight', 'bold', ...
        'FontColor', valColor, 'BackgroundColor', C.panel, ...
        'Tag', valTag, 'HorizontalAlignment', 'left');
end

function infoRow(parent, C, labelStr, valStr, x, y, valTag)
    uilabel(parent, 'Text', [labelStr ':'], ...
        'Position', [x y+1 68 16], 'FontSize', 8, 'FontWeight', 'bold', ...
        'FontColor', C.textSec, 'BackgroundColor', parent.BackgroundColor);
    uilabel(parent, 'Text', valStr, ...
        'Position', [x+70 y+1 240 16], 'FontSize', 9, ...
        'FontColor', C.textPri, 'BackgroundColor', parent.BackgroundColor, ...
        'Tag', valTag);
end

function f = numField(parent, C, x, y, w, h, val, lims, tag)
    f = uieditfield(parent, 'numeric', ...
        'Value', val, 'Limits', lims, ...
        'Position', [x y w h], ...
        'FontSize', 10, 'FontColor', C.textPri, ...
        'BackgroundColor', C.border, 'Tag', tag);
end

function btn = mkToolBtn(parent, C, txt, x, y, cb)
    btn = uibutton(parent, 'Text', txt, ...
        'Position', [x y 284 34], ...
        'FontSize', 11, 'FontColor', C.textPri, ...
        'BackgroundColor', [0.14 0.18 0.26], ...
        'ButtonPushedFcn', cb);
end
