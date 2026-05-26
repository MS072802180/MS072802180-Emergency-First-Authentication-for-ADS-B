function run_app()
% run_app  Launch the ADS-B Emergency Authentication Monitor.
%
% Type in MATLAB Command Window:
%   run_app
%
% All mode selection is inside the GUI.  No command-line prompts.

    clc;
    fprintf('\n');
    fprintf('=========================================================\n');
    fprintf('   ADS-B Emergency Authentication Monitor  v4.0\n');
    fprintf('   Dual-Path Auth + Proximity Verification\n');
    fprintf('=========================================================\n');
    fprintf('[INFO] MATLAB %s\n', version('-release'));

    if ~isempty(getenv('MLM_WEB_LICENSE'))
        fprintf('[INFO] MATLAB Cloud detected. Modes 1-3 available.\n');
        fprintf('[INFO] Mode 4 (RTL-SDR) requires desktop MATLAB + USB access.\n');
    end

    addpath(genpath(pwd));
    fprintf('[INFO] Launching GUI...\n\n');
    main_app();
end
