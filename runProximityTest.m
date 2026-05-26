function runProximityTest()
% runProximityTest  Single-scenario proximity verification test.
%
% Runs two scenarios using the Hancke-Kuhn rapid bit-exchange protocol:
%   Scenario 1 - Standard Authentication : transponder at 1.0 m
%   Scenario 2 - Relay Attack            : transponder at 50.0 m,
%                                          5 us relay hardware delay
%
% Called from: AdsbAuthMain.m (Test 5)

RELAY_DELAY_S = 5e-6;

scenarios = struct( ...
    'label',    {'Standard Authentication', 'Relay Attack Attempt'}, ...
    'distance', {1.0, 50.0}, ...
    'isAttack', {false, true} ...
);

for s = 1:length(scenarios)
    sc = scenarios(s);
    fprintf('\n[%s]\n', upper(sc.label));
    fprintf('Actual Physical Distance: %.1f m\n', sc.distance);

    if sc.isAttack
        relayDelay = RELAY_DELAY_S;
        fprintf('Relay Hardware Latency:   %.1f us per bit\n', RELAY_DELAY_S * 1e6);
    else
        relayDelay = 0.0;
    end

    [reg0, reg1] = auth.ProximityVerifier.buildRegisters();

    [~, correctBits] = auth.ProximityVerifier.measureRTT( ...
        reg0, reg1, sc.distance, relayDelay);

    [accessGranted, cryptoOK, rangeOK, estDist, avgRTT_ns] = ...
        auth.ProximityVerifier.checkAccess(reg0, reg1, sc.distance, relayDelay);

    fprintf('%s\n', repmat('-', 1, 32));
    fprintf('Cryptographic Check : %s (%d/%d bits valid)\n', ...
        boolLabel(cryptoOK, 'PASS', 'FAIL'), correctBits, auth.ProximityVerifier.BIT_COUNT);
    fprintf('Average RTT         : %.2f ns\n', avgRTT_ns);
    fprintf('Estimated Range     : %.4f m\n', estDist);
    fprintf('Range Threshold     : %.1f m (d_max)\n', auth.ProximityVerifier.MAX_RANGE_M);
    fprintf('%s\n', repmat('-', 1, 32));

    if accessGranted
        fprintf('>>> AUTHENTICATION PASSED: Proximity and identity confirmed. <<<\n');
    elseif cryptoOK && ~rangeOK
        fprintf('>>> AUTHENTICATION FAILED: Relay attack detected — range exceeded. <<<\n');
    else
        fprintf('>>> AUTHENTICATION FAILED: Cryptographic response invalid. <<<\n');
    end
end
end


function s = boolLabel(flag, trueStr, falseStr)
if flag
    s = trueStr;
else
    s = falseStr;
end
end
