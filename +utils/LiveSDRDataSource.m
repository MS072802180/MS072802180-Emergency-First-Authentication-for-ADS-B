classdef LiveSDRDataSource < handle
% utils.LiveSDRDataSource  Mode 4: Real-time ADS-B from RTL-SDR hardware.
%
% Connects to an RTL-SDR dongle at 1090 MHz and decodes ADS-B frames.
% If hardware is not found, falls back to realistic simulation automatically.
%
% Hardware requirements:
%   - RTL-SDR dongle connected via USB
%   - MATLAB Communications Toolbox Support Package for RTL-SDR
%   - Windows: WinUSB driver installed via Zadig (https://zadig.akeo.ie/)
%   - Linux: udev rules configured (typically automatic)
%   - Antenna tuned to 1090 MHz

    properties (Constant)
        ADS_B_FREQ       = 1090e6
        SAMPLE_RATE      = 2.4e6
        DEFAULT_GAIN     = 40
        SAMPLES_PER_FRAME = 2^16
    end

    properties
        FallbackMode        % true when hardware is unavailable
        IsHardwareConnected
    end

    properties (Access = private)
        SDRDevice
        Decoder
        FrameCount
        SimT            % fallback simulation time
    end

    methods
        function obj = LiveSDRDataSource(gain)
            if nargin < 1, gain = obj.DEFAULT_GAIN; end

            obj.FrameCount          = 0;
            obj.SimT                = 0;
            obj.IsHardwareConnected = false;
            obj.FallbackMode        = true;
            obj.Decoder             = ADS_B_Decoder();

            obj.tryConnect(gain);
        end

        function tryConnect(obj, gain)
            fprintf('\n[Mode 4] Initializing RTL-SDR at 1090 MHz...\n');

            if ~isempty(getenv('MLM_WEB_LICENSE'))
                fprintf('[Mode 4] MATLAB Cloud: hardware unavailable. Using fallback.\n');
                return;
            end

            if exist('comm.SDRRTLReceiver','class') ~= 8
                fprintf('[Mode 4] RTL-SDR Support Package not found. Install via Add-Ons.\n');
                return;
            end

            try
                obj.SDRDevice = comm.SDRRTLReceiver( ...
                    'CenterFrequency',  obj.ADS_B_FREQ, ...
                    'SampleRate',       obj.SAMPLE_RATE, ...
                    'Gain',             gain, ...
                    'SamplesPerFrame',  obj.SAMPLES_PER_FRAME, ...
                    'OutputDataType',   'double', ...
                    'EnableTunerAGC',   false);

                testData = obj.SDRDevice();

                if ~isempty(testData) && length(testData) >= 1024
                    obj.IsHardwareConnected = true;
                    obj.FallbackMode        = false;
                    fprintf('[Mode 4] RTL-SDR connected. Receiving %.0f ksps at 1090 MHz.\n', ...
                        obj.SAMPLE_RATE/1e3);
                else
                    fprintf('[Mode 4] SDR object created but no signal. Check antenna.\n');
                    release(obj.SDRDevice);
                    obj.SDRDevice = [];
                end

            catch ME
                fprintf('[Mode 4] Hardware error: %s\n', ME.message);
                fprintf('[Mode 4] Falling back to simulation.\n');
                obj.SDRDevice = [];
            end
        end

        function [icao, lat, lon, alt, isEmergency] = getNextFrame(obj)
            obj.FrameCount = obj.FrameCount + 1;

            if obj.FallbackMode || ~obj.IsHardwareConnected
                [icao, lat, lon, alt, isEmergency] = obj.simulateFallback();
                return;
            end

            try
                iqData = obj.SDRDevice();
                [icao, lat, lon, alt, isEmergency] = ...
                    obj.Decoder.decodeFrame(iqData, obj.SAMPLE_RATE);

                if isempty(icao)
                    [icao, lat, lon, alt, isEmergency] = obj.simulateFallback();
                end

            catch ME
                fprintf('[Mode 4] Receive error: %s\n', ME.message);
                [icao, lat, lon, alt, isEmergency] = obj.simulateFallback();
            end
        end

        function status = getStatus(obj)
            if obj.IsHardwareConnected
                status = sprintf('LIVE SDR | 1090 MHz | Frame %d', obj.FrameCount);
            else
                status = 'LIVE SDR | FALLBACK (no hardware)';
            end
        end

        function reset(obj)
            obj.FrameCount = 0;
            obj.SimT = 0;
        end

        function release(obj)
            if ~isempty(obj.SDRDevice) && obj.IsHardwareConnected
                try
                    release(obj.SDRDevice);
                    fprintf('[Mode 4] RTL-SDR released.\n');
                catch
                end
            end
            obj.IsHardwareConnected = false;
            obj.SDRDevice = [];
        end
    end

    methods (Access = private)
        function [icao, lat, lon, alt, isEmergency] = simulateFallback(obj)
            obj.SimT = obj.SimT + 0.1;
            if obj.SimT > 360, obj.SimT = 0; end

            ac = {'LOCAL01','LOCAL02','LOCAL03','LOCAL04','LOCAL05'};
            idx  = mod(floor(obj.SimT * 2), length(ac)) + 1;
            icao = ac{idx};

            clat = 40.0; clon = -95.0;
            r    = 2 + sin(obj.SimT * 0.3);
            lat  = clat + r * sind(obj.SimT * 15) / 111;
            lon  = clon + r * cosd(obj.SimT * 15) / (111 * cosd(clat));
            alt  = 3000 + 500 * sind(obj.SimT * 10);
            isEmergency = (mod(obj.FrameCount, 500) == 250);
        end
    end
end
