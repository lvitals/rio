-- rio/utils/hash.lua
-- Password hashing and data integrity functions, using pure Lua cryptography.

local crypto = require('rio.utils.crypto')
local compat = require('rio.utils.compat')
local band, bor, bxor = compat.band, compat.bor, compat.bxor

local hash = {}

-- Standard configurations
local DEFAULT_ITERATIONS = tonumber(os.getenv("RIO_HASH_ITERATIONS")) or 1000
local SALT_LENGTH = 16 -- in bytes
local HASH_LENGTH = 32 -- in bytes (for SHA256)

-- ==========================================
-- RANDOM SALT GENERATION
-- ==========================================

local function generateSalt()
    -- math.random is generally not secure enough for cryptographic salts.
    math.randomseed(os.time())
    local salt = ""
    for _ = 1, SALT_LENGTH do
        salt = salt .. string.char(math.random(0, 255))
    end
    return salt
end

local function bytesToHex(bytes)
    return (bytes:gsub(".", function(c)
        return string.format("%02x", string.byte(c))
    end))
end

local function hexToBytes(hex)
    local bytes = {}
    for i = 1, #hex, 2 do
        table.insert(bytes, string.char(tonumber(hex:sub(i, i + 1), 16)))
    end
    return table.concat(bytes)
end

-- ==========================================
-- PBKDF2 IMPLEMENTATION (using HMAC-SHA256)
-- ==========================================

local function pbkdf2(password, salt, iterations, keyLength)
    local function f(password_bytes, salt_bytes, iterations_count, blockIndex)
        local block = salt_bytes .. string.char(
            band(math.floor(blockIndex / 0x1000000), 0xFF),
            band(math.floor(blockIndex / 0x10000), 0xFF),
            band(math.floor(blockIndex / 0x100), 0xFF),
            band(blockIndex, 0xFF)
        )
        local u = crypto.hmac_sha256(password_bytes, block)
        local result = u
        
        for i = 2, iterations_count do
            u = crypto.hmac_sha256(password_bytes, u)
            -- XOR result with u
            local xor_result = {}
            for j = 1, #result do
                xor_result[j] = string.char(bxor(string.byte(result, j), string.byte(u, j)))
            end
            result = table.concat(xor_result)
        end
        
        return result
    end
    
    local blocks_needed = math.ceil(keyLength / 32) -- SHA256 produces 32 bytes
    local derivedKey = {}
    
    for i = 1, blocks_needed do
        derivedKey[i] = f(password, salt, iterations, i)
    end
    
    return string.sub(table.concat(derivedKey), 1, keyLength)
end

-- ==========================================
-- ENCRYPT (HASH) PASSWORD
-- ==========================================

function hash.encrypt(password, iterations)
    if type(password) ~= "string" or password == "" then
        error("Password must be a non-empty string", 2)
    end
    
    iterations = iterations or DEFAULT_ITERATIONS
    
    local salt = generateSalt()
    local derivedKey = pbkdf2(password, salt, iterations, HASH_LENGTH)
    
    return string.format("%d$%s$%s", 
        iterations,
        bytesToHex(salt),
        bytesToHex(derivedKey)
    )
end

-- ==========================================
-- VERIFY PASSWORD
-- ==========================================

function hash.verify(password, hashedPassword)
    if type(password) ~= "string" or password == "" then
        error("Password must be a non-empty string", 2)
    end
    
    if type(hashedPassword) ~= "string" or hashedPassword == "" then
        error("Hashed password must be a non-empty string", 2)
    end
    
    local parts = {}
    for part in string.gmatch(hashedPassword, "[^$]+") do
        table.insert(parts, part)
    end
    
    if #parts ~= 3 then
        error("Invalid hash format", 2)
    end
    
    local iterations = tonumber(parts[1])
    local salt = hexToBytes(parts[2])
    local originalHash = parts[3]
    
    local derivedKey = pbkdf2(password, salt, iterations, HASH_LENGTH)
    local newHash = bytesToHex(derivedKey)
    
    return hash.secureCompare(newHash, originalHash)
end

-- ==========================================
-- TIMING-SAFE COMPARISON
-- ==========================================

function hash.secureCompare(a, b)
    if type(a) ~= "string" or type(b) ~= "string" then
        return false
    end
    
    if #a ~= #b then
        return false
    end
    
    local result = 0
    for i = 1, #a do
        result = bor(result, bxor(string.byte(a, i), string.byte(b, i)))
    end
    
    return result == 0
end

-- ==========================================
-- SIMPLE HASHING (NOT FOR PASSWORDS)
-- ==========================================

function hash.sha256(data)
    if type(data) ~= "string" then
        error("Data must be a string", 2)
    end
    return crypto.sha256(data)
end

-- ==========================================
-- ALIASES
-- ==========================================

hash.encript = hash.encrypt -- Common typo
hash.decript = hash.verify
hash.decrypt = hash.verify
hash.make = hash.encrypt
hash.check = hash.verify

return hash
