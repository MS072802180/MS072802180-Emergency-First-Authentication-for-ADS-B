function result = signVerify(mode, keyVal, keyMaterial, signature)
% signVerify  Sign or verify key material using SHA-256.
%
% Usage:
%   sig     = signVerify('sign',   privateKey, keyMaterial)
%   isValid = signVerify('verify', publicKey,  keyMaterial, signature)

import java.security.MessageDigest;
md       = MessageDigest.getInstance('SHA-256');
combined = [typecast(uint64(keyVal), 'uint8'), keyMaterial];
hashOut  = md.digest(combined);

if strcmp(mode, 'sign')
    result = hashOut(1:16);
else
    expected = hashOut(1:16);
    result   = isequal(expected, signature);
end
end
