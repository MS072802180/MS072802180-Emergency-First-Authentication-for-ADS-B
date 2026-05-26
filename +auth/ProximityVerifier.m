classdef ProximityVerifier
% ProximityVerifier  Hancke-Kuhn rapid bit-exchange proximity protocol.
%
% Verifies physical proximity of an aircraft or transponder by measuring
% the round-trip time (RTT) of a rapid cryptographic bit exchange.
% A relay attack inflates RTT, pushing the estimated distance beyond
% the hard threshold and triggering rejection.
%
% Constants:
%   LIGHT_SPEED    = 299,792,458 m/s
%   MAX_RANGE_M    = 2.0 m       (d_max: maximum permitted distance)
%   BIT_COUNT      = 64          (rapid exchange iterations)
%   BASE_PROC_TIME = 1e-9 s      (1 ns baseline processing time)

    properties (Constant)
        LIGHT_SPEED    = 299792458;
        MAX_RANGE_M    = 2.0;
        BIT_COUNT      = 64;
        BASE_PROC_TIME = 1e-9;
    end

    methods (Static)

        function [reg0, reg1] = buildRegisters()
            % Simulates cryptographic pre-computation.
            % Generates two BIT_COUNT-length bit registers from the shared secret.
            reg0 = randi([0, 1], 1, ProximityVerifier.BIT_COUNT);
            reg1 = randi([0, 1], 1, ProximityVerifier.BIT_COUNT);
        end

        function [totalTime, correctBits] = measureRTT(reg0, reg1, trueDistance, relayDelay)
            % Simulates the physical-layer rapid bit exchange.
            %
            % Inputs:
            %   reg0, reg1    - precomputed bit registers (1 x BIT_COUNT)
            %   trueDistance  - actual separation in meters
            %   relayDelay    - added hardware latency in seconds
            %                   (0.0 = legitimate, e.g. 5e-6 = relay attack)
            %
            % Outputs:
            %   totalTime   - summed RTT across all bit exchanges (seconds)
            %   correctBits - number of cryptographically valid responses

            if nargin < 4
                relayDelay = 0.0;
            end

            tofOneway  = trueDistance / ProximityVerifier.LIGHT_SPEED;
            totalTime  = 0.0;
            correctBits = 0;

            for i = 1:ProximityVerifier.BIT_COUNT
                challengeBit = randi([0, 1]);

                if challengeBit == 0
                    responseBit = reg0(i);
                else
                    responseBit = reg1(i);
                end

                expectedBit = reg0(i) * (challengeBit == 0) + reg1(i) * (challengeBit == 1);
                if responseBit == expectedBit
                    correctBits = correctBits + 1;
                end

                % Gaussian hardware jitter: sigma = 0.5 ns
                jitter      = randn() * 0.5e-9;
                procTime    = max(0, ProximityVerifier.BASE_PROC_TIME + jitter);

                % RTT = outbound ToF + processing + return ToF + relay penalty
                bitRTT    = (tofOneway * 2) + procTime + relayDelay;
                totalTime = totalTime + bitRTT;
            end
        end

        function estDist = computeRange(totalTime)
            % Applies distance equation: d = c * (t_avg - t_proc) / 2
            avgRTT  = totalTime / ProximityVerifier.BIT_COUNT;
            estDist = ProximityVerifier.LIGHT_SPEED * ...
                      (avgRTT - ProximityVerifier.BASE_PROC_TIME) / 2;
        end

        function [accessGranted, cryptoOK, rangeOK, estDist, avgRTT_ns] = checkAccess(reg0, reg1, trueDistance, relayDelay)
            % Full dual check: cryptographic validity AND distance bound.
            % accessGranted = (all bits correct) AND (estDist <= MAX_RANGE_M)

            if nargin < 4
                relayDelay = 0.0;
            end

            [totalTime, correctBits] = ProximityVerifier.measureRTT( ...
                reg0, reg1, trueDistance, relayDelay);

            estDist      = ProximityVerifier.computeRange(totalTime);
            avgRTT_ns    = (totalTime / ProximityVerifier.BIT_COUNT) * 1e9;
            cryptoOK     = (correctBits == ProximityVerifier.BIT_COUNT);
            rangeOK      = (estDist <= ProximityVerifier.MAX_RANGE_M);
            accessGranted = cryptoOK && rangeOK;
        end

    end
end
