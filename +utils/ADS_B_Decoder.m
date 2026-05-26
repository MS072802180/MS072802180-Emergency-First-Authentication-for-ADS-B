classdef ADS_B_Decoder < handle
    % ADS_B_Decoder Decodes ADS-B messages from IQ samples
    %   Implements basic 1090 MHz Extended Squitter decoding
    %
    %   References:
    %     - RTCA DO-260C
    %     - The 1090MHz Riddle (mode-s.org)
    
    properties (Constant)
        PREAMBLE = [1, 0, 1, 0, 0, 0, 0, 0, 1, 0, 1, 0, 0, 0, 0, 0]  % Magnitude pattern
        BIT_DURATION = 1e-6  % 1 microsecond per bit
        MESSAGE_BITS = 112
        DF17 = 17  % ADS-B Extended Squitter
    end
    
    properties
        DebugMode
    end
    
    methods
        function obj = ADS_B_Decoder()
            obj.DebugMode = false;
        end
        
        function [icao, lat, lon, alt, isEmergency] = decodeFrame(obj, iqData, sampleRate)
            % decodeFrame Process IQ samples and extract ADS-B messages
            %   iqData: Complex IQ samples from SDR
            %   sampleRate: Sampling rate in Hz
            
            icao = '';
            lat = 0;
            lon = 0;
            alt = 0;
            isEmergency = false;
            
            % Compute magnitude from IQ samples
            magnitude = abs(iqData);
            
            % Detect preamble (correlation-based detection)
            preambleIdx = obj.detectPreamble(magnitude, sampleRate);
            
            if isempty(preambleIdx)
                return;
            end
            
            % Extract message bits
            bits = obj.extractBits(magnitude, preambleIdx(1), sampleRate);
            
            if length(bits) < obj.MESSAGE_BITS
                return;
            end
            
            % Decode based on Downlink Format (first 5 bits)
            df = obj.bitsToUint32(bits(1:5));
            
            if df == obj.DF17
                % ADS-B Extended Squitter
                [icao, lat, lon, alt, isEmergency] = obj.decodeDF17(bits);
            else
                % Other message types (not implemented for demo)
                if obj.DebugMode
                    fprintf('[Decoder] DF=%d (not ADS-B)\n', df);
                end
            end
        end
        
        function idx = detectPreamble(obj, magnitude, sampleRate)
            % detectPreamble Find preamble pattern in magnitude signal
            samplesPerBit = round(sampleRate * obj.BIT_DURATION);
            preamblePattern = [];
            
            for i = 1:length(obj.PREAMBLE)
                preamblePattern = [preamblePattern, repmat(obj.PREAMBLE(i), 1, samplesPerBit)];
            end
            
            % Correlation-based detection
            corr = xcorr(magnitude, preamblePattern);
            corr = corr(length(magnitude):end);
            
            % Find peaks above threshold
            threshold = mean(magnitude) + 3 * std(magnitude);
            [peaks, locs] = findpeaks(corr, 'MinPeakHeight', threshold * length(preamblePattern));
            
            if isempty(locs)
                idx = [];
            else
                % Return first valid preamble location
                idx = locs(1);
            end
        end
        
        function bits = extractBits(obj, magnitude, startIdx, sampleRate)
            % extractBits Extract 112-bit message from magnitude signal
            if nargin < 4
                sampleRate = 2.4e6;
            end
            
            samplesPerBit = round(sampleRate * obj.BIT_DURATION);
            bits = zeros(1, obj.MESSAGE_BITS);
            
            for i = 1:obj.MESSAGE_BITS
                bitStart = startIdx + (i-1) * samplesPerBit;
                bitEnd = min(bitStart + samplesPerBit - 1, length(magnitude));
                
                if bitEnd <= bitStart
                    bits = bits(1:i-1);
                    break;
                end
                
                % Pulse Position Modulation (PPM)
                firstHalf = mean(magnitude(bitStart:bitStart + samplesPerBit/2 - 1));
                secondHalf = mean(magnitude(bitStart + samplesPerBit/2:bitEnd));
                
                if firstHalf > secondHalf
                    bits(i) = 1;
                else
                    bits(i) = 0;
                end
            end
        end
        
        function [icao, lat, lon, alt, isEmergency] = decodeDF17(obj, bits)
            % decodeDF17 Decode ADS-B Extended Squitter (DF=17)
            %   bits: 112-bit message as array of 0/1
            
            icao = '';
            lat = 0;
            lon = 0;
            alt = 0;
            isEmergency = false;
            
            % Extract ICAO address (bits 9-32)
            if length(bits) >= 32
                icao = obj.bitsToHex(bits(9:32));
            end
            
            % Extract Type Code (bits 33-37)
            typeCode = obj.bitsToUint32(bits(33:37));
            
            % Decode based on Type Code
            if typeCode >= 9 && typeCode <= 18
                % Airborne position message
                [lat, lon] = obj.decodePosition(bits);
            elseif typeCode >= 19 && typeCode <= 22
                % Airborne velocity
                alt = obj.decodeAltitude(bits);
            end
            
            % Check for emergency (simplified - would check squawk in real decoder)
            isEmergency = false;
        end
        
        function hexStr = bitsToHex(obj, bits)
            % bitsToHex Convert bit array to hex string
            hexStr = '';
            for i = 1:6
                byte = obj.bitsToUint32(bits((i-1)*4 + 1: i*4));
                hexStr = [hexStr, dec2hex(byte, 1)];
            end
        end
        
        function value = bitsToUint32(~, bits)
            % bitsToUint32 Convert bit array to unsigned integer
            value = 0;
            for i = 1:length(bits)
                value = value * 2 + bits(i);
            end
        end
        
        function [lat, lon] = decodePosition(~, ~)
            % decodePosition Simplified position decoding
            % In production, use CPR (Compact Position Reporting) algorithm
            lat = 40.0 + (rand - 0.5) * 0.5;
            lon = -95.0 + (rand - 0.5) * 0.5;
        end
        
        function alt = decodeAltitude(~, ~)
            % decodeAltitude Simplified altitude decoding
            alt = 30000 + (rand - 0.5) * 2000;
        end
    end
end