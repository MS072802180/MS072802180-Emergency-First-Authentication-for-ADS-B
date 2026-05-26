classdef AuthKey
    properties
        keyID
        keyMaterial
        issueTime
        signature
        used
    end

    methods
        function obj = AuthKey(keyID, keyMaterial, issueTime, signature)
            obj.keyID       = keyID;
            obj.keyMaterial = keyMaterial;
            obj.issueTime   = issueTime;
            obj.signature   = signature;
            obj.used        = false;
        end
    end
end
