classdef LiveADSBApi < handle
% utils.LiveADSBApi  Mode 3: OpenSky Network REST API live data source.
%
% Provides real-time aircraft state vectors (5-10 second latency).
% Anonymous access: 100 API calls/day.
% Register at opensky-network.org for higher rate limits.
%
% Usage:
%   src = utils.LiveADSBApi()
%   [icao, lat, lon, alt, isEmergency] = src.getNextFrame()

    properties (Constant)
        BASE_URL = 'https://opensky-network.org/api'
        MAX_ANON_CALLS = 100
        REFRESH_INTERVAL_S = 10   % seconds between API calls
    end

    properties (Access = private)
        StateCache      % last fetched state struct
        CacheTime       % datetime of last fetch
        CacheIndex      % position within current cache
        TodayCallCount
        LastCallDate
        Username
        Password
        UseAuth
        FrameCount
    end

    methods
        function obj = LiveADSBApi(username, password)
            obj.StateCache     = [];
            obj.CacheTime      = datetime('now') - seconds(999);
            obj.CacheIndex     = 1;
            obj.TodayCallCount = 0;
            obj.LastCallDate   = datetime('today');
            obj.UseAuth        = nargin >= 2;
            obj.FrameCount     = 0;
            if nargin >= 1, obj.Username = username; end
            if nargin >= 2, obj.Password = password; end

            fprintf('[Mode 3] OpenSky Network API client ready.\n');
            fprintf('[Mode 3] Rate limit: %d calls/day (anonymous).\n', obj.MAX_ANON_CALLS);
            if obj.UseAuth
                fprintf('[Mode 3] Authenticated mode enabled.\n');
            end
        end

        function [icao, lat, lon, alt, isEmergency] = getNextFrame(obj)
            % getNextFrame  Returns one aircraft state per call.
            % Refreshes from the API every REFRESH_INTERVAL_S seconds.

            obj.FrameCount = obj.FrameCount + 1;

            % Refresh cache if stale or empty
            if isempty(obj.StateCache) || ...
               seconds(datetime('now') - obj.CacheTime) > obj.REFRESH_INTERVAL_S
                obj.refreshCache();
            end

            % Return empty if still no data
            if isempty(obj.StateCache) || obj.StateCache.count == 0
                icao = ''; lat = 0; lon = 0; alt = 0; isEmergency = false;
                return;
            end

            % Advance index, looping within current cache snapshot
            n = obj.StateCache.count;
            if obj.CacheIndex > n, obj.CacheIndex = 1; end

            i = obj.CacheIndex;
            obj.CacheIndex = obj.CacheIndex + 1;

            icao        = obj.StateCache.icao24{i};
            lat         = obj.StateCache.latitude(i);
            lon         = obj.StateCache.longitude(i);
            alt         = obj.StateCache.altitude(i);
            isEmergency = obj.StateCache.emergency(i);

            % Guard against NaN
            if isnan(lat) || isnan(lon)
                icao = ''; lat = 0; lon = 0; alt = 0; isEmergency = false;
            end
        end

        function status = getStatus(obj)
            n = 0;
            if ~isempty(obj.StateCache), n = obj.StateCache.count; end
            status = sprintf('LIVE API (OpenSky) | %d aircraft | %d API calls today', ...
                n, obj.TodayCallCount);
        end

        function reset(obj)
            obj.StateCache = [];
            obj.CacheIndex = 1;
        end

        function release(~), end
    end

    methods (Access = private)

        function refreshCache(obj)
            % Reset daily counter if new day
            if datetime('today') > obj.LastCallDate
                obj.TodayCallCount = 0;
                obj.LastCallDate   = datetime('today');
            end

            if obj.TodayCallCount >= obj.MAX_ANON_CALLS
                fprintf('[Mode 3] Daily rate limit reached (%d calls). Using last snapshot.\n', ...
                    obj.MAX_ANON_CALLS);
                return;
            end

            url  = [obj.BASE_URL '/states/all'];
            opts = weboptions('ContentType', 'json', 'Timeout', 30);
            if obj.UseAuth
                opts.Username = obj.Username;
                opts.Password = obj.Password;
            end

            try
                raw = webread(url, opts);
                obj.TodayCallCount = obj.TodayCallCount + 1;
                obj.CacheTime      = datetime('now');
                obj.StateCache     = obj.parseStates(raw);
                obj.CacheIndex     = 1;
                fprintf('[Mode 3] Refreshed: %d aircraft.\n', obj.StateCache.count);
            catch ME
                fprintf('[Mode 3] API error: %s\n', ME.message);
                if isempty(obj.StateCache)
                    obj.StateCache = struct('count', 0);
                end
            end
        end

        function data = parseStates(~, response)
            data = struct();
            if ~isfield(response,'states') || isempty(response.states)
                data.count = 0;
                return;
            end

            states = response.states;
            n = length(states);
            data.count      = n;
            data.icao24     = cell(1,n);
            data.callsign   = cell(1,n);
            data.latitude   = nan(1,n);
            data.longitude  = nan(1,n);
            data.altitude   = zeros(1,n);
            data.onGround   = false(1,n);
            data.squawk     = cell(1,n);
            data.emergency  = false(1,n);

            for i = 1:n
                s = states{i};
                if iscell(s)
                    data.icao24{i}    = s{1};
                    data.callsign{i}  = strtrim(char(s{2}));
                    if ~isempty(s{6}) && isnumeric(s{6}), data.latitude(i)  = s{6}; end
                    if ~isempty(s{7}) && isnumeric(s{7}), data.longitude(i) = s{7}; end
                    if ~isempty(s{8}) && isnumeric(s{8}), data.altitude(i)  = s{8}; end
                    data.onGround(i) = logical(s{9});
                    if length(s) >= 15 && ~isempty(s{15})
                        data.squawk{i} = char(s{15});
                        data.emergency(i) = ismember(char(s{15}), {'7500','7600','7700'});
                    end
                end
            end
        end
    end
end
