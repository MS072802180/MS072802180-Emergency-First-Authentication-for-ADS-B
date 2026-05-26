classdef SimulationDataSource < handle
% utils.SimulationDataSource  Mode 1: synthetic aircraft data generator.
%
% Generates realistic-looking flight paths (holding patterns, approaches,
% departures) with occasional emergency squawk events.

    properties (Access = private)
        T           % simulation time (seconds)
        FrameCount
    end

    properties (Constant)
        UPDATE_HZ = 10
    end

    methods
        function obj = SimulationDataSource()
            obj.T = 0;
            obj.FrameCount = 0;
            fprintf('[Mode 1] Simulation data source ready.\n');
        end

        function [icao, lat, lon, alt, isEmergency] = getNextFrame(obj)
            obj.T = obj.T + 1 / obj.UPDATE_HZ;
            if obj.T > 3600, obj.T = 0; end
            obj.FrameCount = obj.FrameCount + 1;

            % Five synthetic aircraft in varied patterns
            ac = {
                'AAL100', 40.0,  -95.0,  2.0,  12,  33000
                'UAL200', 40.5,  -94.5,  1.5,   8,  28000
                'DAL300', 39.5,  -95.5,  3.0,  18,  35000
                'SWA400', 40.2,  -94.8,  2.5,  10,  30000
                'JBU500', 39.8,  -95.2,  1.8,  15,  32000
            };

            acIdx = mod(floor(obj.T * 0.5), size(ac,1)) + 1;
            row   = ac(acIdx,:);

            clat = row{2}; clon = row{3};
            r    = row{4}; spd  = row{5}; baseAlt = row{6};

            lat = clat + r * sind(obj.T * spd) / 111;
            lon = clon + r * cosd(obj.T * spd) / (111 * cosd(clat));
            alt = baseAlt + 500 * sind(obj.T * 3);

            icao = row{1};

            % Emergency every ~45 seconds, lasts 3 seconds
            isEmergency = (mod(obj.T, 45) > 42);
        end

        function status = getStatus(obj)
            status = sprintf('SIMULATION | Frame %d | T=%.1f s', obj.FrameCount, obj.T);
        end

        function reset(obj)
            obj.T = 0;
            obj.FrameCount = 0;
        end

        function release(~), end
    end
end
