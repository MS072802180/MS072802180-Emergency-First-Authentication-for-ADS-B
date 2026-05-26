function mac = computeMAC(key, message)
% computeMAC  HMAC-SHA256 message authentication code.
% Inputs : key (uint8 vector), message (uint8 vector)
% Output : 7-byte (56-bit) truncated MAC

import java.security.MessageDigest;
import javax.crypto.Mac;
import javax.crypto.spec.SecretKeySpec;

try
    macObj  = Mac.getInstance('HmacSHA256');
    keySpec = SecretKeySpec(key, 'HmacSHA256');
    macObj.init(keySpec);
    rawResult = macObj.doFinal(message);
    rawBytes  = typecast(rawResult, 'uint8');
    mac       = rawBytes(1:7);
catch
    mac = fallbackMAC(key, message);
end
end


function mac = fallbackMAC(key, message)
% Pure MATLAB fallback when Java HMAC is unavailable
blockSize = 64;
if length(key) > blockSize
    key = hashBytes(key);
end
if length(key) < blockSize
    key = [key, zeros(1, blockSize - length(key), 'uint8')];
end
outerPad = bitxor(key, uint8(hex2dec('5c')) * ones(1, blockSize, 'uint8'));
innerPad = bitxor(key, uint8(hex2dec('36')) * ones(1, blockSize, 'uint8'));
innerHash = hashBytes([innerPad, message]);
outerHash = hashBytes([outerPad, innerHash]);
mac = outerHash(1:7);
end


function hashOut = hashBytes(inputBytes)
% SHA-256 digest via Java
import java.security.MessageDigest;
md      = MessageDigest.getInstance('SHA-256');
hashOut = typecast(md.digest(inputBytes), 'uint8');
end
