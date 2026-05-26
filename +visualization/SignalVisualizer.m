classdef SignalVisualizer < handle
% visualization.SignalVisualizer  IQ signal and spectrum display.
%
% Opens a dedicated window showing:
%   - IQ magnitude time series (last frame)
%   - Power spectral density
%   - Constellation diagram
%   - Signal strength history
%
% Usage:
%   sv = visualization.SignalVisualizer();
%   sv.updateIQ(iqData, sampleRate);

    properties (Access = private)
        Fig
        AxMag
        AxPSD
        AxConst
        AxPower
        C
        PowerHistory
        IsOpen
    end

    methods
        function obj = SignalVisualizer()
            obj.C = getColours();
            obj.PowerHistory = [];
            obj.IsOpen = false;
            obj.buildFigure();
        end

        function updateIQ(obj, iqData, sampleRate)
            if ~obj.IsOpen || ~isvalid(obj.Fig), return; end
            if nargin < 3, sampleRate = 2.4e6; end
            if isempty(iqData), return; end

            obj.renderMagnitude(iqData, sampleRate);
            obj.renderPSD(iqData, sampleRate);
            obj.renderConstellation(iqData);
            obj.updatePowerHistory(iqData);
            obj.renderPowerHistory();
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
            obj.Fig = uifigure('Name', 'Signal Visualizer — 1090 MHz', ...
                'Position', [250 100 880 600], ...
                'Color', obj.C.bg, ...
                'CloseRequestFcn', @(~,~) obj.onClose());

            uilabel(obj.Fig, 'Text', 'SIGNAL VISUALIZER', ...
                'Position', [20 566 400 26], 'FontSize', 15, 'FontWeight', 'bold', ...
                'FontColor', obj.C.accent, 'BackgroundColor', obj.C.bg);
            uilabel(obj.Fig, 'Text', '1090 MHz  |  2.4 Msps  |  RTL-SDR', ...
                'Position', [20 546 350 18], 'FontSize', 9, ...
                'FontColor', obj.C.textSec, 'BackgroundColor', obj.C.bg);

            % IQ Magnitude (top-left)
            p1 = uipanel(obj.Fig, 'Position', [15 295 420 243], ...
                'BackgroundColor', obj.C.panel, 'BorderType', 'none');
            uilabel(p1, 'Text', 'IQ MAGNITUDE  (last frame)', ...
                'Position', [10 217 300 20], 'FontSize', 9, 'FontWeight', 'bold', ...
                'FontColor', obj.C.textSec, 'BackgroundColor', obj.C.panel);
            obj.AxMag = uiaxes(p1, 'Position', [10 10 400 203], ...
                'Color', [0.04 0.06 0.10], 'XColor', obj.C.border, 'YColor', obj.C.border);
            obj.AxMag.XGrid = 'on'; obj.AxMag.YGrid = 'on'; obj.AxMag.GridAlpha = 0.2;
            xlabel(obj.AxMag, 'Sample', 'Color', obj.C.textSec, 'FontSize', 8);
            ylabel(obj.AxMag, 'Amplitude', 'Color', obj.C.textSec, 'FontSize', 8);

            % PSD (top-right)
            p2 = uipanel(obj.Fig, 'Position', [448 295 418 243], ...
                'BackgroundColor', obj.C.panel, 'BorderType', 'none');
            uilabel(p2, 'Text', 'POWER SPECTRAL DENSITY', ...
                'Position', [10 217 300 20], 'FontSize', 9, 'FontWeight', 'bold', ...
                'FontColor', obj.C.textSec, 'BackgroundColor', obj.C.panel);
            obj.AxPSD = uiaxes(p2, 'Position', [10 10 396 203], ...
                'Color', [0.04 0.06 0.10], 'XColor', obj.C.border, 'YColor', obj.C.border);
            obj.AxPSD.XGrid = 'on'; obj.AxPSD.YGrid = 'on'; obj.AxPSD.GridAlpha = 0.2;
            xlabel(obj.AxPSD, 'Frequency (MHz)', 'Color', obj.C.textSec, 'FontSize', 8);
            ylabel(obj.AxPSD, 'Power (dB)', 'Color', obj.C.textSec, 'FontSize', 8);

            % Constellation (bottom-left)
            p3 = uipanel(obj.Fig, 'Position', [15 12 280 275], ...
                'BackgroundColor', obj.C.panel, 'BorderType', 'none');
            uilabel(p3, 'Text', 'IQ CONSTELLATION', ...
                'Position', [10 249 200 20], 'FontSize', 9, 'FontWeight', 'bold', ...
                'FontColor', obj.C.textSec, 'BackgroundColor', obj.C.panel);
            obj.AxConst = uiaxes(p3, 'Position', [10 10 260 235], ...
                'Color', [0.04 0.06 0.10], 'XColor', obj.C.border, 'YColor', obj.C.border);
            obj.AxConst.XGrid = 'on'; obj.AxConst.YGrid = 'on'; obj.AxConst.GridAlpha = 0.2;
            xlabel(obj.AxConst, 'I', 'Color', obj.C.textSec, 'FontSize', 8);
            ylabel(obj.AxConst, 'Q', 'Color', obj.C.textSec, 'FontSize', 8);
            axis(obj.AxConst, 'equal');

            % Power history (bottom-right)
            p4 = uipanel(obj.Fig, 'Position', [308 12 557 275], ...
                'BackgroundColor', obj.C.panel, 'BorderType', 'none');
            uilabel(p4, 'Text', 'SIGNAL POWER HISTORY  (dBFS)', ...
                'Position', [10 249 350 20], 'FontSize', 9, 'FontWeight', 'bold', ...
                'FontColor', obj.C.textSec, 'BackgroundColor', obj.C.panel);
            obj.AxPower = uiaxes(p4, 'Position', [10 10 535 235], ...
                'Color', [0.04 0.06 0.10], 'XColor', obj.C.border, 'YColor', obj.C.border);
            obj.AxPower.XGrid = 'on'; obj.AxPower.YGrid = 'on'; obj.AxPower.GridAlpha = 0.2;
            xlabel(obj.AxPower, 'Frame', 'Color', obj.C.textSec, 'FontSize', 8);
            ylabel(obj.AxPower, 'dBFS', 'Color', obj.C.textSec, 'FontSize', 8);

            obj.IsOpen = true;
        end

        function renderMagnitude(obj, iqData, ~)
            cla(obj.AxMag);
            n = min(2048, length(iqData));
            mag = abs(iqData(1:n));
            plot(obj.AxMag, 1:n, mag, 'Color', obj.C.accentAlt, 'LineWidth', 0.8);
        end

        function renderPSD(obj, iqData, sampleRate)
            cla(obj.AxPSD);
            n = min(4096, length(iqData));
            data = iqData(1:n);
            nfft = 2^nextpow2(n);
            window = hann(n);
            Pxx = abs(fftshift(fft(data .* window, nfft))).^2 / (sampleRate * sum(window.^2));
            PxxdB = 10*log10(Pxx + eps);
            freqs = linspace(-sampleRate/2, sampleRate/2, nfft) / 1e6;
            plot(obj.AxPSD, freqs, PxxdB, 'Color', obj.C.accent, 'LineWidth', 0.8);
            xlabel(obj.AxPSD, 'Frequency (MHz)', 'Color', obj.C.textSec, 'FontSize', 8);
        end

        function renderConstellation(obj, iqData)
            cla(obj.AxConst);
            n = min(1024, length(iqData));
            data = iqData(1:n);
            scatter(obj.AxConst, real(data), imag(data), 4, ...
                [obj.C.accent], 'filled', 'MarkerFaceAlpha', 0.5);
        end

        function updatePowerHistory(obj, iqData)
            pwr = 20 * log10(mean(abs(iqData)) + eps);
            obj.PowerHistory(end+1) = pwr;
            if length(obj.PowerHistory) > 120
                obj.PowerHistory = obj.PowerHistory(end-119:end);
            end
        end

        function renderPowerHistory(obj)
            cla(obj.AxPower);
            if length(obj.PowerHistory) < 2, return; end
            n = length(obj.PowerHistory);
            area(obj.AxPower, 1:n, obj.PowerHistory, ...
                'FaceColor', obj.C.accent, 'FaceAlpha', 0.3, ...
                'EdgeColor', obj.C.accent, 'LineWidth', 1);
            ylim(obj.AxPower, [min(obj.PowerHistory)-5, max(obj.PowerHistory)+5]);
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
