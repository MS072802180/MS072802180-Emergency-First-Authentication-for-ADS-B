classdef ThreatDashboard < handle
% visualization.ThreatDashboard  Standalone threat analysis figure.
%
% Opens a dedicated window showing:
%   - Threat type breakdown (bar chart)
%   - Replay vs spoof vs relay counts over time
%   - Threat timeline (stem plot)
%   - Rejection rate gauge
%
% Usage:
%   td = visualization.ThreatDashboard();
%   td.update(eventLog);   % eventLog: cell array of structs from AuthSystem

    properties (Access = private)
        Fig
        AxBar
        AxTimeline
        AxGauge
        AxHeatmap
        C               % colour palette
        EventLog        % accumulated events
        IsOpen
    end

    methods
        function obj = ThreatDashboard()
            obj.C = getColours();
            obj.EventLog = {};
            obj.IsOpen = false;
            obj.buildFigure();
        end

        function update(obj, newEvents)
            % update  Refresh all panels with new event data.
            if ~obj.IsOpen || ~isvalid(obj.Fig), return; end
            if nargin >= 2 && ~isempty(newEvents)
                obj.EventLog = [obj.EventLog, newEvents];
            end
            obj.renderAll();
        end

        function show(obj)
            if isvalid(obj.Fig)
                figure(obj.Fig);
                obj.IsOpen = true;
            end
        end

        function close(obj)
            if isvalid(obj.Fig)
                delete(obj.Fig);
            end
            obj.IsOpen = false;
        end
    end

    methods (Access = private)

        function buildFigure(obj)
            obj.Fig = uifigure( ...
                'Name',     'Threat Dashboard', ...
                'Position', [200 150 900 620], ...
                'Color',    obj.C.bg, ...
                'CloseRequestFcn', @(~,~) obj.onClose());

            % Title bar
            uilabel(obj.Fig, 'Text', 'THREAT ANALYSIS DASHBOARD', ...
                'Position', [20 582 500 28], 'FontSize', 16, 'FontWeight', 'bold', ...
                'FontColor', obj.C.danger, 'BackgroundColor', obj.C.bg);
            uilabel(obj.Fig, 'Text', 'Real-time authentication threat monitoring', ...
                'Position', [20 560 400 18], 'FontSize', 10, ...
                'FontColor', obj.C.textSec, 'BackgroundColor', obj.C.bg);

            % --- Threat type bar chart (top-left) ---
            p1 = uipanel(obj.Fig, 'Position', [15 300 420 252], ...
                'BackgroundColor', obj.C.panel, 'BorderType', 'none');
            uilabel(p1, 'Text', 'THREAT TYPE BREAKDOWN', ...
                'Position', [10 226 300 20], 'FontSize', 9, 'FontWeight', 'bold', ...
                'FontColor', obj.C.textSec, 'BackgroundColor', obj.C.panel);
            obj.AxBar = uiaxes(p1, 'Position', [10 10 400 212], ...
                'Color', [0.05 0.07 0.11], 'XColor', obj.C.border, 'YColor', obj.C.border);
            obj.AxBar.XGrid = 'off'; obj.AxBar.YGrid = 'on';
            obj.AxBar.GridAlpha = 0.25;

            % --- Timeline (top-right) ---
            p2 = uipanel(obj.Fig, 'Position', [448 300 437 252], ...
                'BackgroundColor', obj.C.panel, 'BorderType', 'none');
            uilabel(p2, 'Text', 'THREAT TIMELINE', ...
                'Position', [10 226 300 20], 'FontSize', 9, 'FontWeight', 'bold', ...
                'FontColor', obj.C.textSec, 'BackgroundColor', obj.C.panel);
            obj.AxTimeline = uiaxes(p2, 'Position', [10 10 415 212], ...
                'Color', [0.05 0.07 0.11], 'XColor', obj.C.border, 'YColor', obj.C.border);
            obj.AxTimeline.XGrid = 'on'; obj.AxTimeline.YGrid = 'on';
            obj.AxTimeline.GridAlpha = 0.25;

            % --- Rejection rate gauge (bottom-left) ---
            p3 = uipanel(obj.Fig, 'Position', [15 12 280 278], ...
                'BackgroundColor', obj.C.panel, 'BorderType', 'none');
            uilabel(p3, 'Text', 'REJECTION RATE', ...
                'Position', [10 252 200 20], 'FontSize', 9, 'FontWeight', 'bold', ...
                'FontColor', obj.C.textSec, 'BackgroundColor', obj.C.panel);
            obj.AxGauge = uiaxes(p3, 'Position', [10 10 260 238], ...
                'Color', obj.C.panel);
            obj.AxGauge.XAxis.Visible = 'off';
            obj.AxGauge.YAxis.Visible = 'off';

            % --- Result heatmap (bottom-right) ---
            p4 = uipanel(obj.Fig, 'Position', [308 12 577 278], ...
                'BackgroundColor', obj.C.panel, 'BorderType', 'none');
            uilabel(p4, 'Text', 'RESULT DISTRIBUTION (last 100 events)', ...
                'Position', [10 252 400 20], 'FontSize', 9, 'FontWeight', 'bold', ...
                'FontColor', obj.C.textSec, 'BackgroundColor', obj.C.panel);
            obj.AxHeatmap = uiaxes(p4, 'Position', [10 10 555 238], ...
                'Color', [0.05 0.07 0.11], 'XColor', obj.C.border, 'YColor', obj.C.border);
            obj.AxHeatmap.XGrid = 'off'; obj.AxHeatmap.YGrid = 'on';
            obj.AxHeatmap.GridAlpha = 0.25;

            obj.renderAll();
            obj.IsOpen = true;
        end

        function renderAll(obj)
            obj.renderBar();
            obj.renderTimeline();
            obj.renderGauge();
            obj.renderHeatmap();
        end

        function renderBar(obj)
            cla(obj.AxBar);
            results = obj.getResultCounts();
            labels  = {'VALID EMERG', 'VALID DELAY', 'REPLAY', 'SPOOF', 'MAC ERR', 'PENDING'};
            counts  = [results.validEmerg, results.validDelay, results.replay, ...
                       results.spoof, results.macErr, results.pending];
            colors  = [[0.20 0.82 0.45]; [0.10 0.75 0.60]; [0.92 0.25 0.25]; ...
                       [0.95 0.55 0.10]; [0.85 0.20 0.65]; [0.50 0.55 0.65]];
            b = bar(obj.AxBar, counts, 'FaceColor', 'flat');
            b.CData = colors;
            b.EdgeColor = 'none';
            set(obj.AxBar, 'XTickLabel', labels, 'XTickLabelRotation', 15, ...
                'FontSize', 8, 'FontColor', obj.C.textSec);
            ylabel(obj.AxBar, 'Count', 'Color', obj.C.textSec, 'FontSize', 8);
        end

        function renderTimeline(obj)
            cla(obj.AxTimeline);
            n = min(60, length(obj.EventLog));
            if n < 2, return; end
            events = obj.EventLog(end-n+1:end);
            x = 1:n;
            isThreats = cellfun(@(e) contains(lower(e.result), ...
                'replay') || contains(lower(e.result), 'invalid') || ...
                contains(lower(e.result), 'mismatch'), events);
            hold(obj.AxTimeline, 'on');
            if any(~isThreats)
                stem(obj.AxTimeline, x(~isThreats), ones(1,sum(~isThreats)), ...
                    'Color', obj.C.accentAlt, 'MarkerFaceColor', obj.C.accentAlt, ...
                    'LineStyle', 'none', 'MarkerSize', 5);
            end
            if any(isThreats)
                stem(obj.AxTimeline, x(isThreats), ones(1,sum(isThreats))*1.5, ...
                    'Color', obj.C.danger, 'MarkerFaceColor', obj.C.danger, ...
                    'LineStyle', 'none', 'MarkerSize', 8);
            end
            hold(obj.AxTimeline, 'off');
            ylim(obj.AxTimeline, [0 2.5]);
            ylabel(obj.AxTimeline, 'Events', 'Color', obj.C.textSec, 'FontSize', 8);
            xlabel(obj.AxTimeline, 'Recent frames', 'Color', obj.C.textSec, 'FontSize', 8);
        end

        function renderGauge(obj)
            cla(obj.AxGauge);
            results = obj.getResultCounts();
            total = results.total;
            if total == 0, rate = 0; else, rate = results.rejected / total; end

            theta = linspace(pi, 0, 100);
            hold(obj.AxGauge, 'on');
            % Background arc
            plot(obj.AxGauge, cos(theta), sin(theta), '-', ...
                'Color', obj.C.border, 'LineWidth', 12);
            % Filled arc
            thetaFill = linspace(pi, pi - rate*pi, max(2,round(rate*100)));
            if length(thetaFill) >= 2
                if rate < 0.1
                    arcColor = obj.C.success;
                elseif rate < 0.3
                    arcColor = obj.C.warn;
                else
                    arcColor = obj.C.danger;
                end
                plot(obj.AxGauge, cos(thetaFill), sin(thetaFill), '-', ...
                    'Color', arcColor, 'LineWidth', 12);
            end
            text(obj.AxGauge, 0, 0.1, sprintf('%.1f%%', rate*100), ...
                'HorizontalAlignment', 'center', 'FontSize', 22, ...
                'FontWeight', 'bold', 'Color', obj.C.textPri);
            text(obj.AxGauge, 0, -0.25, sprintf('%d / %d rejected', results.rejected, total), ...
                'HorizontalAlignment', 'center', 'FontSize', 9, 'Color', obj.C.textSec);
            hold(obj.AxGauge, 'off');
            axis(obj.AxGauge, 'equal');
            xlim(obj.AxGauge, [-1.3 1.3]); ylim(obj.AxGauge, [-0.5 1.2]);
        end

        function renderHeatmap(obj)
            cla(obj.AxHeatmap);
            n = min(100, length(obj.EventLog));
            if n < 2, return; end
            events = obj.EventLog(end-n+1:end);
            latencies = cellfun(@(e) e.latencyMs, events);
            histogram(obj.AxHeatmap, latencies, 20, ...
                'FaceColor', obj.C.accent, 'EdgeColor', 'none', 'FaceAlpha', 0.85);
            xlabel(obj.AxHeatmap, 'Latency (ms)', 'Color', obj.C.textSec, 'FontSize', 9);
            ylabel(obj.AxHeatmap, 'Count', 'Color', obj.C.textSec, 'FontSize', 9);
            xline(obj.AxHeatmap, 10, '--', 'Color', obj.C.warn, 'LineWidth', 1.5);
        end

        function r = getResultCounts(obj)
            r.total = length(obj.EventLog);
            r.validEmerg = sum(cellfun(@(e) contains(e.result,'VALID_EMERGENCY'), obj.EventLog));
            r.validDelay = sum(cellfun(@(e) contains(e.result,'VALID_DELAYED'), obj.EventLog));
            r.replay     = sum(cellfun(@(e) contains(e.result,'REPLAY'), obj.EventLog));
            r.spoof      = sum(cellfun(@(e) contains(e.result,'SIGNATURE'), obj.EventLog));
            r.macErr     = sum(cellfun(@(e) contains(e.result,'MISMATCH'), obj.EventLog));
            r.pending    = sum(cellfun(@(e) contains(e.result,'AWAIT') || contains(e.result,'PENDING'), obj.EventLog));
            r.rejected   = r.replay + r.spoof + r.macErr;
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
