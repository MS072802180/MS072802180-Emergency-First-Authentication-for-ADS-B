classdef SecureKeyStore < handle
    properties
        keyStore
        usedKeyIDs
        hardwareProtected = true;
    end

    methods
        function obj = SecureKeyStore()
            obj.keyStore   = containers.Map('KeyType', 'int32', 'ValueType', 'any');
            obj.usedKeyIDs = containers.Map('KeyType', 'int32', 'ValueType', 'logical');
        end

        function storeKey(obj, key)
            obj.keyStore(key.keyID) = key;
        end

        function key = useKey(obj, keyID)
            if obj.usedKeyIDs.isKey(keyID)
                key = [];
                return;
            end
            if ~obj.keyStore.isKey(keyID)
                key = [];
                return;
            end
            key = obj.keyStore(keyID);
            key.used = true;
            obj.usedKeyIDs(keyID) = true;
        end

        function key = peekKey(obj, keyID)
            % peekKey  Read a key without marking it as used.
            % Used internally by AuthSystem buffer processing to inspect
            % a normal-path key without consuming its single-use status.
            if ~obj.keyStore.isKey(keyID)
                key = [];
                return;
            end
            key = obj.keyStore(keyID);
        end

        function protected = isProtected(obj)
            protected = obj.hardwareProtected;
        end
    end
end
