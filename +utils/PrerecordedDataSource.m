% Place this file in the +utils/ folder.
classdef PrerecordedDataSource < handle
    % PRERECORDED MODE - ADS-B Exchange sample data
    % 
    % Three data loading methods:
    %   1. AUTO-DOWNLOAD + CACHE: Downloads from ADS-B Exchange, saves locally
    %   2. USER UPLOAD: User selects a file via GUI
    %   3. MANUAL PLACEMENT: Reads from ADSB_Data/ folder
    %
    % Data sources:
    %   - ADS-B Exchange: https://www.adsbexchange.com/data-products/sample-data/
    %   - OpenSky Network: https://opensky-network.org (fallback)
    
    properties (Access = private)
        Data            % Parsed aircraft states
        CurrentIndex    % Current position in data
        LoopMode        % Whether to loop when reaching end
        DataSourceName  % Name of loaded dataset
        CacheFolder     % Folder for cached downloads
        DataFolder      % Folder for manual file placement
        LoadMethod      % 'cache', 'upload', 'manual'
        CustomFilePath  % Path to user-uploaded file
    end
    
    properties (Constant)
        SAMPLE_URL = 'https://samples.adsbexchange.com'
        DEFAULT_CACHE_FOLDER = 'ADSB_Cache'
        DEFAULT_DATA_FOLDER = 'ADSB_Data'
    end
    
    methods
        function obj = PrerecordedDataSource(loadMethod, varargin)
            % PrerecordedDataSource Constructor
            %
            % Usage:
            %   % Auto-download + cache (default date)
            %   src = PrerecordedDataSource('cache')
            %
            %   % Auto-download + cache (specific date)
            %   src = PrerecordedDataSource('cache', 'year', 2024, 'month', 1, 'day', 1)
            %
            %   % User upload (opens file picker)
            %   src = PrerecordedDataSource('upload')
            %
            %   % Manual placement (reads from ADSB_Data folder)
            %   src = PrerecordedDataSource('manual')
            %
            %   % Custom file path (programmatic)
            %   src = PrerecordedDataSource('manual', 'filepath', '/path/to/data.json')
            
            obj.LoopMode = true;
            obj.CurrentIndex = 1;
            obj.LoadMethod = loadMethod;
            
            % Setup folders
            obj.CacheFolder = fullfile(pwd, obj.DEFAULT_CACHE_FOLDER);
            obj.DataFolder = fullfile(pwd, obj.DEFAULT_DATA_FOLDER);
            
            % Create folders if they don't exist
            if ~exist(obj.CacheFolder, 'dir')
                mkdir(obj.CacheFolder);
            end
            if ~exist(obj.DataFolder, 'dir')
                mkdir(obj.DataFolder);
            end
            
            % Parse varargin for optional parameters
            p = inputParser;
            addParameter(p, 'year', 2024, @isnumeric);
            addParameter(p, 'month', 1, @isnumeric);
            addParameter(p, 'day', 1, @isnumeric);
            addParameter(p, 'filepath', '', @ischar);
            parse(p, varargin{:});
            
            year = num2str(p.Results.year);
            month = sprintf('%02d', p.Results.month);
            day = sprintf('%02d', p.Results.day);
            customPath = p.Results.filepath;
            
            % Load data based on method
            switch loadMethod
                case 'cache'
                    obj.loadFromCacheOrDownload(year, month, day);
                case 'upload'
                    obj.loadFromUserUpload();
                case 'manual'
                    if ~isempty(customPath)
                        obj.loadFromFile(customPath);
                    else
                        obj.loadFromDataFolder();
                    end
                otherwise
                    error('[Prerecorded] Unknown load method: %s', loadMethod);
            end
        end
        
        % =================================================================
        % Method 1: Auto-download + Cache
        % =================================================================
        function loadFromCacheOrDownload(obj, year, month, day)
            fprintf('\n========================================================\n');
            fprintf('[Prerecorded] Mode 2A: Auto-Download + Cache\n');
            fprintf('========================================================\n');
            
            cacheFile = fullfile(obj.CacheFolder, sprintf('adsb_%s%s%s.mat', year, month, day));
            
            % Check if cache exists
            if exist(cacheFile, 'file')
                fprintf('[INFO] Cache found: %s\n', cacheFile);
                load(cacheFile, 'cachedData');
                obj.Data = cachedData;
                obj.DataSourceName = sprintf('Cached: %s-%s-%s', year, month, day);
                fprintf('[OK] Loaded from cache (%d records)\n', length(obj.Data.lat));
                return;
            end
            
            % Download from ADS-B Exchange
            fprintf('[INFO] Cache not found. Downloading from ADS-B Exchange...\n');
            
            % ADS-B Exchange readsb-hist URL.
            % File: YYYYMMDD_00.json.gz  — midnight UTC snapshot, largest global file.
            % e.g.: https://samples.adsbexchange.com/readsb-hist/2026/05/01/20260501_00.json.gz
            url = sprintf('%s/readsb-hist/%s/%s/%s/%s%s%s_00.json.gz', ...
                obj.SAMPLE_URL, year, month, day, year, month, day);
            
            fprintf('[INFO] URL: %s\n', url);
            
            try
                tempFile = tempname();
                websave(tempFile, url);
                
                % Gunzip
                gunzip(tempFile, fileparts(tempFile));
                jsonFile = strrep(tempFile, '.gz', '');
                
                % Parse JSON
                fid = fopen(jsonFile, 'r');
                raw = fread(fid, '*char')';
                fclose(fid);
                jsonData = jsondecode(raw);
                
                % Parse state vectors
                obj.Data = obj.parseStateVectors(jsonData);
                
                % Cache the data
                cachedData = obj.Data;
                save(cacheFile, 'cachedData');
                fprintf('[OK] Downloaded and cached to: %s\n', cacheFile);
                
                obj.DataSourceName = sprintf('ADS-B Exchange: %s-%s-%s', year, month, day);
                
                % Cleanup
                delete(tempFile);
                delete(jsonFile);
                
            catch ME
                fprintf('[ERROR] Download failed: %s\n', ME.message);
                fprintf('[INFO] Falling back to sample data generator.\n');
                obj.generateSampleData();
                obj.DataSourceName = 'FALLBACK (Sample Data)';
            end
            
            fprintf('========================================================\n\n');
        end
        
        % =================================================================
        % Method 2: User Upload (File Picker)
        % =================================================================
        function loadFromUserUpload(obj)
            fprintf('\n========================================================\n');
            fprintf('[Prerecorded] Mode 2B: User Upload\n');
            fprintf('========================================================\n');
            
            % Open file picker dialog
            [filename, pathname] = uigetfile(...
                {'*.json;*.csv;*.mat', 'Data Files (*.json, *.csv, *.mat)'; ...
                 '*.json', 'JSON Files (*.json)'; ...
                 '*.csv', 'CSV Files (*.csv)'; ...
                 '*.mat', 'MATLAB Files (*.mat)'}, ...
                'Select ADS-B Data File', ...
                obj.DataFolder);
            
            if filename == 0
                fprintf('[INFO] No file selected. Using sample data.\n');
                obj.generateSampleData();
                obj.DataSourceName = 'SAMPLE DATA (No file selected)';
                return;
            end
            
            filepath = fullfile(pathname, filename);
            obj.CustomFilePath = filepath;
            fprintf('[INFO] Selected file: %s\n', filename);
            
            obj.loadFromFile(filepath);
            fprintf('========================================================\n\n');
        end
        
        % =================================================================
        % Method 3: Manual File Placement
        % =================================================================
        function loadFromDataFolder(obj)
            fprintf('\n========================================================\n');
            fprintf('[Prerecorded] Mode 2C: Manual File Placement\n');
            fprintf('========================================================\n');
            fprintf('[INFO] Scanning folder: %s\n', obj.DataFolder);
            
            % Find all supported files
            jsonFiles = dir(fullfile(obj.DataFolder, '*.json'));
            csvFiles = dir(fullfile(obj.DataFolder, '*.csv'));
            matFiles = dir(fullfile(obj.DataFolder, '*.mat'));
            
            allFiles = [jsonFiles; csvFiles; matFiles];
            
            if isempty(allFiles)
                fprintf('[INFO] No data files found in %s\n', obj.DataFolder);
                fprintf('[INFO] Please place JSON/CSV/MAT files in this folder.\n');
                fprintf('[INFO] Generating sample data for demonstration.\n');
                obj.generateSampleData();
                obj.DataSourceName = 'SAMPLE DATA (No files found)';
                return;
            end
            
            % List available files
            fprintf('[INFO] Found %d data file(s):\n', length(allFiles));
            for i = 1:length(allFiles)
                fprintf('  %d. %s\n', i, allFiles(i).name);
            end
            
            % If multiple files, let user choose
            if length(allFiles) == 1
                selectedFile = allFiles(1).name;
                fprintf('\n[INFO] Auto-selecting: %s\n', selectedFile);
            else
                fprintf('\n');
                choice = input('Enter file number to load (1-%d): ', length(allFiles));
                if choice < 1 || choice > length(allFiles)
                    fprintf('[INFO] Invalid selection. Using first file.\n');
                    choice = 1;
                end
                selectedFile = allFiles(choice).name;
            end
            
            filepath = fullfile(obj.DataFolder, selectedFile);
            obj.loadFromFile(filepath);
            fprintf('========================================================\n\n');
        end
        
        % =================================================================
        % Core Data Loading Functions
        % =================================================================
        function loadFromFile(obj, filepath)
            % loadFromFile Load data from JSON/CSV/MAT file
            [~, ~, ext] = fileparts(filepath);
            
            fprintf('[INFO] Loading file: %s\n', filepath);
            
            try
                switch lower(ext)
                    case '.json'
                        obj.loadFromJSON(filepath);
                    case '.csv'
                        obj.loadFromCSV(filepath);
                    case '.mat'
                        obj.loadFromMAT(filepath);
                    otherwise
                        error('Unsupported file format: %s', ext);
                end
                fprintf('[OK] Loaded %d records\n', length(obj.Data.lat));
            catch ME
                fprintf('[ERROR] Failed to load file: %s\n', ME.message);
                fprintf('[INFO] Generating sample data.\n');
                obj.generateSampleData();
            end
        end
        
        function loadFromJSON(obj, filepath)
            % loadFromJSON Parse ADS-B Exchange JSON format
            fid = fopen(filepath, 'r');
            raw = fread(fid, '*char')';
            fclose(fid);
            
            jsonData = jsondecode(raw);
            
            if isfield(jsonData, 'aircraft')
                obj.Data = obj.parseStateVectors(jsonData);
            elseif isfield(jsonData, 'trace')
                obj.Data = obj.parseTraceData(jsonData);
            else
                % Try to parse as generic array
                obj.Data = obj.parseGenericJSON(jsonData);
            end
            
            obj.DataSourceName = sprintf('File: %s', filepath);
        end
        
        function loadFromCSV(obj, filepath)
            % loadFromCSV Parse CSV format
            % Expected columns: icao,lat,lon,alt,isEmergency,timestamp
            data = readtable(filepath);
            
            obj.Data.icao = {};
            obj.Data.lat = [];
            obj.Data.lon = [];
            obj.Data.alt = [];
            obj.Data.emergency = [];
            
            if ismember('icao', data.Properties.VariableNames)
                obj.Data.icao = table2cell(data(:, 'icao'));
            end
            if ismember('lat', data.Properties.VariableNames)
                obj.Data.lat = data.lat;
            end
            if ismember('lon', data.Properties.VariableNames)
                obj.Data.lon = data.lon;
            end
            if ismember('alt', data.Properties.VariableNames)
                obj.Data.alt = data.alt;
            end
            if ismember('isEmergency', data.Properties.VariableNames)
                obj.Data.emergency = data.isEmergency;
            else
                obj.Data.emergency = false(height(data), 1);
            end
            
            obj.DataSourceName = sprintf('CSV: %s', filepath);
        end
        
        function loadFromMAT(obj, filepath)
            % loadFromMAT Load MATLAB .mat file
            loaded = load(filepath);
            
            if isfield(loaded, 'data')
                obj.Data = loaded.data;
            elseif isfield(loaded, 'adsbData')
                obj.Data = loaded.adsbData;
            else
                % Take first struct found
                fields = fieldnames(loaded);
                for i = 1:length(fields)
                    if isstruct(loaded.(fields{i}))
                        obj.Data = loaded.(fields{i});
                        break;
                    end
                end
            end
            
            obj.DataSourceName = sprintf('MAT: %s', filepath);
        end
        
        % =================================================================
        % Data Access Methods
        % =================================================================
        function [icao, lat, lon, alt, isEmergency] = getNextFrame(obj)
            if isempty(obj.Data) || obj.CurrentIndex > length(obj.Data.lat)
                if obj.LoopMode
                    obj.CurrentIndex = 1;
                    fprintf('[Prerecorded] Looping to start of data\n');
                else
                    icao = '';
                    lat = 0;
                    lon = 0;
                    alt = 0;
                    isEmergency = false;
                    return;
                end
            end
            
            idx = obj.CurrentIndex;
            icao = obj.Data.icao{idx};
            lat = obj.Data.lat(idx);
            lon = obj.Data.lon(idx);
            alt = obj.Data.alt(idx);
            
            if isfield(obj.Data, 'emergency') && idx <= length(obj.Data.emergency)
                isEmergency = obj.Data.emergency(idx);
            else
                isEmergency = false;
            end
            
            obj.CurrentIndex = obj.CurrentIndex + 1;
        end
        
        function status = getStatus(obj)
            if isempty(obj.Data)
                status = 'PRERECORDED | No data loaded';
                return;
            end
            
            progress = (obj.CurrentIndex / length(obj.Data.lat)) * 100;
            status = sprintf('%s | %.1f%% (%d/%d)', ...
                obj.DataSourceName, progress, obj.CurrentIndex, length(obj.Data.lat));
        end
        
        function reset(obj)
            obj.CurrentIndex = 1;
        end
        
        function info = getDataInfo(obj)
            % getDataInfo Return metadata about loaded data
            if isempty(obj.Data)
                info = struct('loaded', false);
                return;
            end
            
            info.loaded = true;
            info.numRecords = length(obj.Data.lat);
            info.source = obj.DataSourceName;
            info.method = obj.LoadMethod;
            
            if isfield(obj.Data, 'emergency')
                info.emergencyCount = sum(obj.Data.emergency);
            else
                info.emergencyCount = 0;
            end
        end
        
        function release(obj)
            obj.Data = [];
            obj.CurrentIndex = 1;
        end
        
        % =================================================================
        % Utility Methods
        % =================================================================
        function saveToCSV(obj, filepath)
            % saveToCSV Export loaded data to CSV
            if isempty(obj.Data)
                fprintf('[ERROR] No data to export.\n');
                return;
            end
            
            if nargin < 2
                filepath = fullfile(obj.DataFolder, sprintf('exported_data_%s.csv', datestr(now, 'yyyymmdd_HHMMSS')));
            end
            
            T = table();
            T.icao = obj.Data.icao';
            T.lat = obj.Data.lat';
            T.lon = obj.Data.lon';
            T.alt = obj.Data.alt';
            T.isEmergency = obj.Data.emergency';
            
            writetable(T, filepath);
            fprintf('[OK] Data exported to: %s\n', filepath);
        end
    end
    
    methods (Static)
        function data = parseStateVectors(jsonData)
            % parseStateVectors Parse readsb-hist JSON
            data = struct();
            data.icao = {};
            data.lat = [];
            data.lon = [];
            data.alt = [];
            data.emergency = [];
            
            if isfield(jsonData, 'aircraft')
                n = length(jsonData.aircraft);
                for i = 1:n
                    ac = jsonData.aircraft(i);
                    data.icao{i} = ac.hex;
                    data.lat(i) = ac.lat;
                    data.lon(i) = ac.lon;
                    data.alt(i) = ac.altitude;
                    
                    if isfield(ac, 'squawk') && ismember(ac.squawk, {'7500', '7600', '7700'})
                        data.emergency(i) = true;
                    else
                        data.emergency(i) = false;
                    end
                end
            end
        end
        
        function data = parseTraceData(jsonData)
            data = struct();
            data.icao = {};
            data.lat = [];
            data.lon = [];
            data.alt = [];
            data.emergency = [];
            
            if isfield(jsonData, 'trace') && isfield(jsonData.trace, 'path')
                path = jsonData.trace.path;
                n = length(path);
                for i = 1:n
                    data.icao{i} = jsonData.trace.hex;
                    data.lat(i) = path{i}.lat;
                    data.lon(i) = path{i}.lon;
                    data.alt(i) = path{i}.alt;
                    data.emergency(i) = false;
                end
            end
        end
        
        function data = parseGenericJSON(jsonData)
            data = struct();
            data.icao = {};
            data.lat = [];
            data.lon = [];
            data.alt = [];
            data.emergency = [];
            
            % Try to detect array of objects
            if isstruct(jsonData)
                fields = fieldnames(jsonData);
                if ismember('lat', fields)
                    data.lat = jsonData.lat;
                    data.lon = jsonData.lon;
                    data.alt = jsonData.alt;
                    if ismember('icao', fields)
                        data.icao = jsonData.icao;
                    else
                        for i = 1:length(data.lat)
                            data.icao{i} = 'UNKNOWN';
                        end
                    end
                    data.emergency = false(1, length(data.lat));
                end
            end
        end
    end
    
    methods (Access = private)
        function generateSampleData(obj)
            % generateSampleData Create synthetic data for demonstration
            duration = 120;
            sampleRate = 10;
            numSamples = duration * sampleRate;
            
            obj.Data.icao = cell(1, numSamples);
            obj.Data.lat = zeros(1, numSamples);
            obj.Data.lon = zeros(1, numSamples);
            obj.Data.alt = zeros(1, numSamples);
            obj.Data.emergency = false(1, numSamples);
            
            aircraftList = {'AAL123', 'UAL456', 'DAL789', 'SWA012', 'JBU345'};
            centerLat = 40.0;
            centerLon = -95.0;
            
            for i = 1:numSamples
                t = i / sampleRate;
                acIdx = mod(floor(t / 10), length(aircraftList)) + 1;
                obj.Data.icao{i} = aircraftList{acIdx};
                
                radius = 3 + sin(t * 0.2);
                obj.Data.lat(i) = centerLat + radius * sind(t * 12) / 111;
                obj.Data.lon(i) = centerLon + radius * cosd(t * 12) / (111 * cosd(centerLat));
                obj.Data.alt(i) = 30000 + 2000 * sind(t * 5);
                obj.Data.emergency(i) = (mod(t, 45) > 42 && mod(t, 45) < 45);
            end
        end
    end
end