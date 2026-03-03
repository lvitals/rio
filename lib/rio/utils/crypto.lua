-- rio/lib/rio/utils/crypto.lua
-- Pure Lua SHA256 and HMAC-SHA256 implementations.
-- Compatible with Lua 5.1, 5.2, 5.3, 5.4

local compat = require("rio.utils.compat")
local band, bor, bxor, bnot, lshift, rshift = compat.band, compat.bor, compat.bxor, compat.bnot, compat.lshift, compat.rshift

local M = {}

-- Bitwise operations for compatibility across Lua versions
local function tobit(x) return band(x, 0xFFFFFFFF) end

-- Rotate Right (used in SHA-256)
local function rotr(x, n)
    return bor(rshift(band(x, 0xFFFFFFFF), n), band(lshift(x, 32 - n), 0xFFFFFFFF))
end

-- Add 32-bit integers (handle overflow using bitwise AND with 0xFFFFFFFF)
local function add32(a, b)
    return band(a + b, 0xFFFFFFFF)
end

-- Constants for SHA-256 (first 32 bits of the fractional parts of the cube roots of the first 64 primes)
local K = {
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2
}

-- SHA256 Implementation (Pure Lua)
function M.sha256(msg)
    local H = {
        0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19
    }

    -- Pre-processing: Padding the message
    local len = #msg
    local bit_len = len * 8
    msg = msg .. string.char(0x80) -- Append a single '1' bit
    
    -- Pad with zeros until length is 448 mod 512
    local k0 = (56 - (len + 1) % 64) % 64 -- number of zero bytes needed
    msg = msg .. string.rep(string.char(0), k0)
    
    -- Append 64-bit message length (big-endian)
    local high = math.floor(bit_len / 0x100000000)
    local low = bit_len % 0x100000000
    msg = msg .. string.char(
        band(rshift(high, 24), 0xFF), band(rshift(high, 16), 0xFF), band(rshift(high, 8), 0xFF), band(high, 0xFF),
        band(rshift(low, 24), 0xFF), band(rshift(low, 16), 0xFF), band(rshift(low, 8), 0xFF), band(low, 0xFF)
    )

    -- Process the message in 512-bit (64-byte) chunks
    for i = 1, #msg, 64 do
        local chunk = msg:sub(i, i + 63)
        local W = {}
        for t = 0, 15 do
            W[t] = tobit(
                lshift(chunk:byte(t*4 + 1), 24) +
                lshift(chunk:byte(t*4 + 2), 16) +
                lshift(chunk:byte(t*4 + 3), 8) +
                chunk:byte(t*4 + 4)
            )
        end

        for t = 16, 63 do
            local s0 = bxor(rotr(W[t-15], 7), rotr(W[t-15], 18), rshift(W[t-15], 3))
            local s1 = bxor(rotr(W[t-2], 17), rotr(W[t-2], 19), rshift(W[t-2], 10))
            W[t] = add32(add32(s0, W[t-16]), add32(s1, W[t-7]))
        end

        local a, b, c, d, e, f, g, h = H[1], H[2], H[3], H[4], H[5], H[6], H[7], H[8]

        for t = 0, 63 do
            local S1 = bxor(rotr(e, 6), rotr(e, 11), rotr(e, 25))
            local ch = bxor(band(e, f), band(band(bnot(e), 0xFFFFFFFF), g))
            local temp1 = add32(add32(add32(add32(h, S1), ch), K[t+1]), W[t])
            local S0 = bxor(rotr(a, 2), rotr(a, 13), rotr(a, 22))
            local maj = bxor(band(a, b), band(a, c), band(b, c))
            local temp2 = add32(S0, maj)

            h = g
            g = f
            f = e
            e = add32(d, temp1)
            d = c
            c = b
            b = a
            a = add32(temp1, temp2)
        end

        H[1] = add32(H[1], a)
        H[2] = add32(H[2], b)
        H[3] = add32(H[3], c)
        H[4] = add32(H[4], d)
        H[5] = add32(H[5], e)
        H[6] = add32(H[6], f)
        H[7] = add32(H[7], g)
        H[8] = add32(H[8], h)
    end
    
    local digest = ""
    for i = 1, 8 do
        local h_val = H[i]
        digest = digest .. string.char(
            band(rshift(h_val, 24), 0xFF), band(rshift(h_val, 16), 0xFF), band(rshift(h_val, 8), 0xFF), band(h_val, 0xFF)
        )
    end
    return digest
end

-- HMAC-SHA256 Implementation (Pure Lua)
function M.hmac_sha256(key, msg)
    local B = 64 -- SHA-256 block size is 64 bytes
    local L = 32 -- SHA-256 output size is 32 bytes

    if #key > B then
        key = M.sha256(key)
    end
    
    -- Pad key to B bytes
    key = key .. string.rep(string.char(0), B - #key)

    -- Inner pad
    local ipad = ""
    for i = 1, B do
        ipad = ipad .. string.char(bxor(key:byte(i), 0x36))
    end

    -- Outer pad
    local opad = ""
    for i = 1, B do
        opad = opad .. string.char(bxor(key:byte(i), 0x5C))
    end
    
    local inner_hash = M.sha256(ipad .. msg)
    local final_hash = M.sha256(opad .. inner_hash)
    
    return final_hash
end

-- Secure string comparison to prevent timing attacks
function M.constant_time_equals(a, b)
    if type(a) ~= "string" or type(b) ~= "string" then
        return false
    end
    if #a ~= #b then
        return false
    end
    local result = 0
    for i = 1, #a do
        result = bor(result, bxor(a:byte(i), b:byte(i)))
    end
    return result == 0
end

return M
