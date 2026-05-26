classdef TrafficMonitor < handle
% visualization.TrafficMonitor  Full-screen global traffic map.
%
% Displays all tracked aircraft with:
%   - Colour-coded altitude layers
%   - Emergency aircraft highlighted
%   - Trail history per aircraft
%   - Flight count statistics
%
% Usage:
%   tm = visualization.TrafficMonitor();
%   tm.addFrame(icao, lat, lon, alt, isEmergency);

    properties (Access = private)
        Fig
        AxMap
        TrackTable      % struct array: icao, lats, lons, alts, isEmerg
        StatsPanel
        C
        IsOpen
        FrameCount
    end

    methods
        function obj = TrafficMonitor()
            obj.C = getColours();
            obj.TrackTable = struct('icao',{},'lats',{},'lons',{},'alts',{},'isEmerg',{});
            obj.IsOpen = false;
            obj.FrameCount = 0;
            obj.buildFigure();
        end

        function addFrame(obj, icao, lat, lon, alt, isEmergency)
            if ~obj.IsOpen || ~isvalid(obj.Fig), return; end
            obj.FrameCount = obj.FrameCount + 1;

            idx = find(strcmp({obj.TrackTable.icao}, icao), 1);
            if isempty(idx)
                n = length(obj.TrackTable) + 1;
                obj.TrackTable(n).icao   = icao;
                obj.TrackTable(n).lats   = lat;
                obj.TrackTable(n).lons   = lon;
                obj.TrackTable(n).alts   = alt;
                obj.TrackTable(n).isEmerg= isEmergency;
            else
                obj.TrackTable(idx).lats(end+1) = lat;
                obj.TrackTable(idx).lons(end+1) = lon;
                obj.TrackTable(idx).alts(end+1) = alt;
                obj.TrackTable(idx).isEmerg = isEmergency;
                % Keep last 20 points per aircraft
                if length(obj.TrackTable(idx).lats) > 20
                    obj.TrackTable(idx).lats = obj.TrackTable(idx).lats(end-19:end);
                    obj.TrackTable(idx).lons = obj.TrackTable(idx).lons(end-19:end);
                    obj.TrackTable(idx).alts = obj.TrackTable(idx).alts(end-19:end);
                end
            end

            if mod(obj.FrameCount, 3) == 0
                obj.renderMap();
                obj.renderStats();
            end
        end

        function show(obj)
            if isvalid(obj.Fig), figure(obj.Fig); obj.IsOpen = true; end
        end

        function close(obj)
            if isvalid(obj.Fig), delete(obj.Fig); end
            obj.IsOpen = false;
        end
    end

    methods (Access = private)

        function buildFigure(obj)
            obj.Fig = uifigure('Name', 'Traffic Monitor', ...
                'Position', [100 50 1100 700], ...
                'Color', obj.C.bg, ...
                'CloseRequestFcn', @(~,~) obj.onClose());

            uilabel(obj.Fig, 'Text', 'TRAFFIC MONITOR', ...
                'Position', [20 666 400 26], 'FontSize', 15, 'FontWeight', 'bold', ...
                'FontColor', obj.C.accentAlt, 'BackgroundColor', obj.C.bg);

            % Main map
            mapPnl = uipanel(obj.Fig, 'Position', [15 12 800 646], ...
                'BackgroundColor', obj.C.panel, 'BorderType', 'none');
            obj.AxMap = uiaxes(mapPnl, 'Position', [10 10 780 626], ...
                'Color', [0.04 0.07 0.12], 'XColor', obj.C.border, 'YColor', obj.C.border);
            obj.AxMap.XGrid = 'on'; obj.AxMap.YGrid = 'on';
            obj.AxMap.GridAlpha = 0.15;
            xlabel(obj.AxMap, 'Longitude', 'Color', obj.C.textSec, 'FontSize', 9);
            ylabel(obj.AxMap, 'Latitude', 'Color', obj.C.textSec, 'FontSize', 9);
            title(obj.AxMap, 'Global ADS-B Traffic', 'Color', obj.C.textSec, 'FontSize', 11);
            hold(obj.AxMap, 'on');

            % Stats side panel
            obj.StatsPanel = uipanel(obj.Fig, 'Position', [825 12 260 646], ...
                'BackgroundColor', obj.C.panel, 'BorderType', 'none');
            uilabel(obj.StatsPanel, 'Text', 'TRAFFIC STATISTICS', ...
                'Position', [10 616 240 22], 'FontSize', 10, 'FontWeight', 'bold', ...
                'FontColor', obj.C.textSec, 'BackgroundColor', obj.C.panel);

            % Altitude legend
            altY = 550;
            altBands = {'>35000 ft', [0.85 0.90 1.00]; ...
                        '25-35k ft',  [0.40 0.65 0.95]; ...
                        '15-25k ft',  [0.15 0.75 0.60]; ...
                        '<15000 ft',  [0.95 0.75 0.20]};
            uilabel(obj.StatsPanel, 'Text', 'ALTITUDE BANDS', ...
                'Position', [10 altY+26 200 16], 'FontSize', 8, 'FontWeight', 'bold', ...
                'FontColor', obj.C.textSec, 'BackgroundColor', obj.C.panel);
            for k = 1:size(altBands,1)
                p = uipanel(obj.StatsPanel, 'Position', [10 altY-(k-1)*22 12 14], ...
                    'BackgroundColor', altBands{k,2}, 'BorderType', 'none');
                uilabel(obj.StatsPanel, 'Text', altBands{k,1}, ...
                    'Position', [28 altY-(k-1)*22 180 14], 'FontSize', 9, ...
                    'FontColor', obj.C.textPri, 'BackgroundColor', obj.C.panel);
            end

            obj.IsOpen = true;
        end

        function renderMap(obj)
            cla(obj.AxMap);
            hold(obj.AxMap, 'on');
            n = length(obj.TrackTable);
            for k = 1:n
                tr = obj.TrackTable(k);
                if isempty(tr.lats), continue; end

                alt = tr.alts(end);
                if     alt > 10668,  clr = [0.85 0.90 1.00];  % >35000ft
                elseif alt > 7620,   clr = [0.40 0.65 0.95];  % 25-35k
                elseif alt > 4572,   clr = [0.15 0.75 0.60];  % 15-25k
                else,                clr = [0.95 0.75 0.20];  % <15k
                end

                if tr.isEmerg, clr = [0.92 0.25 0.25]; end

                % Trail
                if length(tr.lats) > 1
                    plot(obj.AxMap, tr.lons, tr.lats, '-', 'Color', [clr 0.35], 'LineWidth', 1);
                end
                % Aircraft dot
                sz = 24;
                if tr.isEmerg
                    scatter(obj.AxMap, tr.lons(end), tr.lats(end), sz*2, clr, ...
                        'filled', 'Marker', '^');
                    text(obj.AxMap, tr.lons(end)+0.3, tr.lats(end)+0.3, tr.icao, ...
                        'Color', [0.92 0.25 0.25], 'FontSize', 7, 'FontWeight', 'bold');
                else
                    scatter(obj.AxMap, tr.lons(end), tr.lats(end), sz, clr, 'filled');
                end
            end
            title(obj.AxMap, sprintf('Tracking %d aircraft', n), ...
                'Color', obj.C.textSec, 'FontSize', 10);
        end

        function renderStats(obj)
            n = length(obj.TrackTable);
            nEmerg = sum([obj.TrackTable.isEmerg]);
            % Update existing stats label (find by tag or recreate)
            existing = findobj(obj.StatsPanel, 'Tag', 'statsLbl');
            if isempty(existing)
                uilabel(obj.StatsPanel, ...
                    'Text',  obj.buildStatsText(n, nEmerg), ...
                    'Position', [10 12 240 450], ...
                    'FontSize', 10, 'FontColor', obj.C.textPri, ...
                    'BackgroundColor', obj.C.panel, ...
                    'WordWrap', 'on', 'Tag', 'statsLbl');
            else
                existing.Text = obj.buildStatsText(n, nEmerg);
            end
        end

        function s = buildStatsText(~, n, nEmerg)
            s = sprintf('Aircraft tracked:  %d\nEmergency:  %d\nNormal:  %d', ...
                n, nEmerg, n - nEmerg);
        end

        function onClose(obj)
            obj.IsOpen = false;
            if isvalid(obj.Fig), delete(obj.Fig); end
        end
    end
end

function C = getColours()
    C.bg       = [0.08 0.10 0.14];
    C.panel    = [0.11 0.14 0.19];
    C.accent   = [0.20 0.55 0.95];
    C.accentAlt= [0.10 0.75 0.60];
    C.warn     = [0.95 0.55 0.10];
    C.danger   = [0.92 0.25 0.25];
    C.success  = [0.20 0.82 0.45];
    C.textPri  = [0.92 0.93 0.95];
    C.textSec  = [0.55 0.62 0.72];
    C.border   = [0.20 0.25 0.33];
end
