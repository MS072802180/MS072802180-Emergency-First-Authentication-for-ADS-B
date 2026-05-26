function [legitDist, legitEst, attackDist, attackEst] = runProximityMonteCarlo()
% runProximityMonteCarlo  Monte Carlo proximity verification analysis (500 trials).
%
% Sweeps physical distances uniformly from 0.1 m to 100 m.
% Each trial runs both a legitimate and a relay-attack scenario and
% records the verifier's estimated range.
%
% Relay hardware delay: 1.5 us (representative of analog SDR conversion latency).
%
% Outputs:
%   legitDist  - actual distances for legitimate trials (1 x 500)
%   legitEst   - estimated distances for legitimate trials (1 x 500)
%   attackDist - actual distances for relay-attack trials (1 x 500)
%   attackEst  - estimated distances for relay-attack trials (1 x 500)
%
% Called from: AdsbAuthMain.m (Test 6)

NUM_TRIALS    = 500;
RELAY_DELAY_S = 1.5e-6;
MIN_DIST      = 0.1;
MAX_DIST      = 100.0;

fprintf('Running proximity Monte Carlo analysis (%d trials)...\n', NUM_TRIALS);

legitDist  = zeros(1, NUM_TRIALS);
legitEst   = zeros(1, NUM_TRIALS);
attackDist = zeros(1, NUM_TRIALS);
attackEst  = zeros(1, NUM_TRIALS);

trialDistances = MIN_DIST + (MAX_DIST - MIN_DIST) * rand(1, NUM_TRIALS);

for i = 1:NUM_TRIALS
    d = trialDistances(i);
    [reg0, reg1] = auth.ProximityVerifier.buildRegisters();

    % Legitimate scenario
    [tNorm, ~]  = auth.ProximityVerifier.measureRTT(reg0, reg1, d, 0.0);
    legitDist(i) = d;
    legitEst(i)  = auth.ProximityVerifier.computeRange(tNorm);

    % Relay attack scenario
    [tAtk, ~]    = auth.ProximityVerifier.measureRTT(reg0, reg1, d, RELAY_DELAY_S);
    attackDist(i) = d;
    attackEst(i)  = auth.ProximityVerifier.computeRange(tAtk);
end

fprintf('Analysis complete.\n');

% --- Figure ---
figure('Name', 'Proximity Verification Analysis', 'Position', [150, 150, 900, 550]);
hold on;

scatter(legitDist, legitEst, 15, [0.2, 0.4, 0.8], 'filled', ...
    'DisplayName', 'Legitimate Authentication', 'MarkerFaceAlpha', 0.6);

scatter(attackDist, attackEst, 15, [0.85, 0.2, 0.2], 'filled', ...
    'DisplayName', sprintf('Relay Attack (%.1f\\mus hardware delay)', RELAY_DELAY_S * 1e6), ...
    'MarkerFaceAlpha', 0.6);

yline(auth.ProximityVerifier.MAX_RANGE_M, 'g--', 'LineWidth', 2, ...
    'DisplayName', sprintf('d_{max} = %.1f m (rejection threshold)', auth.ProximityVerifier.MAX_RANGE_M));

fill([0, MAX_DIST, MAX_DIST, 0], ...
     [0, 0, auth.ProximityVerifier.MAX_RANGE_M, auth.ProximityVerifier.MAX_RANGE_M], ...
     [0.2, 0.8, 0.2], 'FaceAlpha', 0.08, 'EdgeColor', 'none', ...
     'DisplayName', 'Authentication Zone');

xlabel('True Physical Separation (meters)', 'FontSize', 12);
ylabel('Verifier Range Estimate via RTT (meters)', 'FontSize', 12);
title({'ADS-B Proximity Verification: True vs Estimated Range', ...
       '(Hancke-Kuhn Protocol, 500 Monte Carlo Trials)'}, ...
       'FontSize', 14, 'FontWeight', 'bold');
xlim([0, MAX_DIST]);
ylim([0, max(max(attackEst), max(legitEst)) * 1.1]);
legend('Location', 'northwest', 'FontSize', 10);
grid on;
grid minor;
hold off;

saveas(gcf, 'proximityAnalysis.png');
fprintf('Figure saved as proximityAnalysis.png\n');

% Summary stats
fprintf('\n--- Monte Carlo Summary ---\n');
fprintf('Legitimate   | Mean est. range: %6.3f m | Std: %.4f m\n', ...
    mean(legitEst), std(legitEst));
fprintf('Relay Attack | Mean est. range: %6.3f m | Std: %.4f m\n', ...
    mean(attackEst), std(attackEst));
fprintf('Mean range inflation from relay: +%.2f m\n', mean(attackEst - attackDist));
pctDetected = sum(attackEst > auth.ProximityVerifier.MAX_RANGE_M) / NUM_TRIALS * 100;
fprintf('Relay attacks flagged by threshold: %.1f%%\n', pctDetected);
end
