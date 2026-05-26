classdef AuthSystem < handle
% AuthSystem  Dual-path ADS-B authentication engine.
%
%   Implements two independent authentication paths:
%
%   PATH 1 — Normal (Delayed Key Disclosure / TESLA):
%     Keys are pre-generated into a one-way SHA-256 chain.
%     Each message is transmitted with its MAC; the key is published
%     only after a fixed delay (DELAY_PACKETS packets).
%     On disclosure, the receiver verifies chain integrity, then the MAC.
%
%   PATH 2 — Emergency (Instant Key):
%     Pre-provisioned, ground-signed keys are stored in the SecureKeyStore.
%     Verification is immediate (<10 ms) and single-use (replay-resistant).
%
%   Routing in verifyAuth() is based on keyID:
%     keyID <= CHAIN_LENGTH  ->  Normal path (delayed, TESLA)
%     keyID >  CHAIN_LENGTH  ->  Emergency path (instant)
%
%   Proximity verification (Hancke-Kuhn) is available via verifyProximity().

    properties
        keyStore                % SecureKeyStore  — simulated hardware TPM
        privateKey              % uint64          — ground station private key
        publicKey               % uint64          — ground station public key
        usedEmergencyKeyIDs     % Map<int32,bool> — tracks spent emergency keys
        verificationLog         % cell            — audit log of all results

        % --- Normal Path (TESLA key chain) ---
        keyChain                % cell{uint8(32)} — pre-computed key chain
        currentKeyIndex         % int — next key index to use for signing
        disclosedUntilIndex     % int — highest index disclosed so far
        messageBuffer           % cell — buffered {keyID, message, mac, ts}
        DELAY_PACKETS           % int — disclosure delay in packets (default 10)
        CHAIN_LENGTH            % int — total pre-computed keys (default 100)
    end

    methods

        % =================================================================
        % Constructor
        % =================================================================
        function obj = AuthSystem(delayPackets, chainLength)
            % AuthSystem(delayPackets, chainLength)
            %
            % delayPackets : packets before a key is disclosed. Default = 10
            %                (~1.6 sec at the 6.25 Hz ADS-B broadcast rate).
            % chainLength  : total keys in the normal-path chain. Default = 100.

            if nargin < 1 || isempty(delayPackets), delayPackets = 10;  end
            if nargin < 2 || isempty(chainLength),  chainLength  = 100; end

            obj.DELAY_PACKETS       = delayPackets;
            obj.CHAIN_LENGTH        = chainLength;
            obj.keyStore            = SecureKeyStore();
            [obj.publicKey, obj.privateKey] = generateKeypair();
            obj.usedEmergencyKeyIDs = containers.Map('KeyType', 'int32', 'ValueType', 'logical');
            obj.verificationLog     = {};
            obj.messageBuffer       = {};
            obj.currentKeyIndex     = 1;
            obj.disclosedUntilIndex = 0;
            obj.keyChain            = obj.generateKeyChain(chainLength);
        end

        % =================================================================
        % Normal Path — Key Chain
        % =================================================================
        function chain = generateKeyChain(obj, len)
            % generateKeyChain  Pre-computes a SHA-256 one-way key chain.
            %   Direction: K_{i-1} = SHA-256(K_i).
            %   K_n is a random seed; K_1 is derived from it.
            import java.security.MessageDigest;
            md = MessageDigest.getInstance('SHA-256');

            chain      = cell(1, len);
            chain{len} = randi([0, 255], 1, 32, 'uint8');

            for i = len-1:-1:1
                raw      = md.digest(chain{i+1});
                chain{i} = typecast(raw, 'uint8');
                chain{i} = chain{i}(1:32);
            end
            fprintf('[AuthSystem] Key chain generated (length = %d).\n', len);
        end

        function key = getNextNormalKey(obj)
            % getNextNormalKey  Returns the next chain key for message signing.
            % The key is stored in the SecureKeyStore so it can be retrieved
            % when disclosed later. Carries no ground signature — chain integrity
            % proves authenticity instead.
            if obj.currentKeyIndex > obj.CHAIN_LENGTH
                error('[AuthSystem] Key chain exhausted. Increase chainLength.');
            end
            idx         = obj.currentKeyIndex;
            keyMaterial = obj.keyChain{idx};
            issueTime   = floor(posixtime(datetime('now')));
            key         = AuthKey(idx, keyMaterial, issueTime, []);
            obj.keyStore.storeKey(key);
            fprintf('[AuthSystem] Normal key K_%d issued (discloses after %d packets).\n', ...
                idx, obj.DELAY_PACKETS);
            obj.currentKeyIndex = obj.currentKeyIndex + 1;
        end

        function discloseNormalKey(obj, keyIndex)
            % discloseNormalKey  Simulates the sender broadcasting K_i after the delay.
            % Triggers verification of all buffered messages awaiting this key.
            if keyIndex ~= obj.disclosedUntilIndex + 1
                warning('[AuthSystem] Key K_%d disclosed out of order.', keyIndex);
            end
            obj.disclosedUntilIndex = max(obj.disclosedUntilIndex, keyIndex);
            fprintf('[AuthSystem] Key K_%d disclosed.\n', keyIndex);
            obj.processBufferForIndex(keyIndex);
        end

        function processBufferForIndex(obj, keyIndex)
            % processBufferForIndex  Verifies buffered messages for a given key.
            % Uses peekKey (non-consuming read) — normal-path keys must remain
            % accessible for chain-integrity cross-checks.
            key = obj.keyStore.peekKey(keyIndex);
            if isempty(key)
                fprintf('[AuthSystem] Key K_%d not found in store.\n', keyIndex);
                return;
            end

            if ~obj.verifyKeyChainIntegrity(keyIndex)
                fprintf('[AuthSystem] Chain integrity FAILED for K_%d — messages rejected.\n', keyIndex);
                obj.messageBuffer = obj.messageBuffer( ...
                    cellfun(@(e) e.keyID ~= keyIndex, obj.messageBuffer));
                return;
            end

            remaining = {};
            for i = 1:length(obj.messageBuffer)
                entry = obj.messageBuffer{i};
                if entry.keyID == keyIndex
                    [isValid, elapsedMs, reason] = obj.verifyDelayed(key, entry.message, entry.mac);
                    fprintf('  [Buffer] K_%d: %s (%.3f ms)\n', keyIndex, reason, elapsedMs);
                    obj.verificationLog{end+1} = struct( ...
                        'timestamp',   datetime('now'), ...
                        'keyID',       keyIndex,        ...
                        'result',      reason,          ...
                        'latencyMs',   elapsedMs,       ...
                        'isEmergency', false);
                else
                    remaining{end+1} = entry; %#ok<AGROW>
                end
            end
            obj.messageBuffer = remaining;
        end

        function valid = verifyKeyChainIntegrity(obj, keyIndex)
            % verifyKeyChainIntegrity  Checks K_{i-1} = SHA-256(K_i).
            import java.security.MessageDigest;
            md = MessageDigest.getInstance('SHA-256');

            if keyIndex <= 1
                valid = true;
                return;
            end
            raw      = md.digest(obj.keyChain{keyIndex});
            computed = typecast(raw, 'uint8');
            computed = computed(1:32);
            valid    = isequal(obj.keyChain{keyIndex - 1}, computed);
        end

        % =================================================================
        % Emergency Path — Key Issuance
        % =================================================================
        function key = issueEmergencyKey(obj, keyID, icao)
            % issueEmergencyKey  Creates a ground-signed instant key.
            % keyID must be > CHAIN_LENGTH so verifyAuth routes it correctly.
            import java.security.MessageDigest;
            md = MessageDigest.getInstance('SHA-256');

            keyInput    = [uint8(icao), typecast(uint32(keyID), 'uint8'), ...
                           typecast(uint64(posixtime(datetime('now'))), 'uint8')];
            raw         = md.digest(keyInput);
            keyMaterial = typecast(raw, 'uint8');
            keyMaterial = keyMaterial(1:32);
            sig         = signVerify('sign', obj.privateKey, keyMaterial);
            issueTime   = floor(posixtime(datetime('now')));
            key         = AuthKey(keyID, keyMaterial, issueTime, sig);
            obj.keyStore.storeKey(key);
        end

        % =================================================================
        % MAC Computation (shared by both paths)
        % =================================================================
        function [mac, elapsedMs] = computeAuthMAC(obj, key, message)
            t0        = tic;
            mac       = computeMAC(key.keyMaterial, message);
            elapsedMs = toc(t0) * 1000;
        end

        % =================================================================
        % Verification — Dual-Path Router
        % =================================================================
        function [isValid, elapsedMs, reason] = verifyAuth(obj, key, message, receivedMAC)
            % verifyAuth  Routes to emergency or normal path based on keyID.
            %   keyID > CHAIN_LENGTH  -> instant emergency verification
            %   keyID <= CHAIN_LENGTH -> buffer for delayed TESLA verification
            t0 = tic;

            if key.keyID > obj.CHAIN_LENGTH
                % ---- Emergency Path ----
                [isValid, reason] = obj.verifyInstant(key, message, receivedMAC);
                elapsedMs = toc(t0) * 1000;

                if isValid
                    obj.verificationLog{end+1} = struct( ...
                        'timestamp',   datetime('now'), ...
                        'keyID',       key.keyID,       ...
                        'result',      reason,          ...
                        'latencyMs',   elapsedMs,       ...
                        'isEmergency', true);
                end

            else
                % ---- Normal Path: buffer for delayed verification ----
                obj.messageBuffer{end+1} = struct( ...
                    'keyID',   key.keyID,    ...
                    'message', message,      ...
                    'mac',     receivedMAC,  ...
                    'ts',      tic);

                if key.keyID <= obj.disclosedUntilIndex
                    obj.processBufferForIndex(key.keyID);
                    reason = 'PENDING_DELAYED_VERIFICATION';
                else
                    reason = 'AWAITING_KEY_DISCLOSURE';
                end
                isValid   = false;   % resolved asynchronously on disclosure
                elapsedMs = toc(t0) * 1000;
            end
        end

        % =================================================================
        % Emergency Path — Instant Verification
        % =================================================================
        function [isValid, reason] = verifyInstant(obj, key, message, receivedMAC)
            % verifyInstant  Four-step emergency check:
            %   (1) key.used flag, (2) replay map, (3) ground signature, (4) MAC.
            isValid = false;

            if key.used
                reason = 'KEY_ALREADY_USED';
                return;
            end

            if obj.usedEmergencyKeyIDs.isKey(key.keyID)
                reason = 'REPLAY_DETECTED';
                return;
            end

            if isempty(key.signature) || ...
               ~signVerify('verify', obj.publicKey, key.keyMaterial, key.signature)
                reason = 'INVALID_SIGNATURE';
                return;
            end

            computedMAC = computeMAC(key.keyMaterial, message);
            if ~isequal(computedMAC, receivedMAC)
                reason = 'MAC_MISMATCH';
                return;
            end

            isValid = true;
            reason  = 'VALID_EMERGENCY';
            obj.usedEmergencyKeyIDs(key.keyID) = true;
            % AuthKey is a value class, so key.used = true would not persist.
            % Replay protection is handled solely by usedEmergencyKeyIDs.
        end

        % =================================================================
        % Normal Path — Delayed Verification (called after key disclosure)
        % =================================================================
        function [isValid, elapsedMs, reason] = verifyDelayed(obj, key, message, receivedMAC)
            % verifyDelayed  MAC check after chain integrity has been confirmed.
            t0          = tic;
            computedMAC = computeMAC(key.keyMaterial, message);

            if ~isequal(computedMAC, receivedMAC)
                isValid   = false;
                elapsedMs = toc(t0) * 1000;
                reason    = 'MAC_MISMATCH';
                return;
            end

            isValid   = true;
            elapsedMs = toc(t0) * 1000;
            reason    = 'VALID_DELAYED';
        end

        % =================================================================
        % Optional — Proximity Verification (Hancke-Kuhn)
        % =================================================================
        function [accessGranted, estDist] = verifyProximity(obj, trueDistance, relayDelay)
            % verifyProximity  RTT-based proximity check via ProximityVerifier.
            % trueDistance : actual separation in metres
            % relayDelay   : attacker hardware delay in seconds (0 = legitimate)
            if nargin < 3, relayDelay = 0.0; end
            [reg0, reg1] = ProximityVerifier.buildRegisters();
            [accessGranted, ~, ~, estDist, ~] = ProximityVerifier.checkAccess( ...
                reg0, reg1, trueDistance, relayDelay);
        end

    end
end
