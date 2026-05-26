function [publicKey, privateKey] = generateKeypair()
% generateKeypair  Generates a simulated public/private key pair.
% In production replace with ECDSA from Communications Toolbox.
rng('shuffle');
privateKey = randi([1, 2^32-1], 1, 1);
publicKey  = mod(privateKey * 123456789, 2^32-1);
end
