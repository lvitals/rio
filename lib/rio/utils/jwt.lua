-- rio/utils/jwt.lua
-- Pure Lua JWT HS256 (HMAC-SHA256) implementation.
-- API:
--   jwt.sign(payload, secret, options) -> token
--   jwt.verify(token, secret, options) -> true, payload | false, err
--   jwt.decode(token) -> header, payload (no signature check)
--   jwt.create_access_token(payload, secret, expiresIn?)
--   jwt.create_refresh_token(payload, secret, expiresIn?)

local crypto = require("rio.utils.crypto")
local compat = require("rio.utils.compat")
local json = compat.json
local b64chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local b64lookup = {}
for i = 1, #b64chars do
  b64lookup[b64chars:sub(i, i)] = i - 1
end
b64lookup["="] = 0

local function base64_encode(data)
  local out = {}
  local len = #data
  local i = 1
  while i <= len do
    local a = data:byte(i) or 0
    local b = data:byte(i + 1) or 0
    local c = data:byte(i + 2) or 0
    local triple = a * 65536 + b * 256 + c

    local s1 = math.floor(triple / 262144) % 64
    local s2 = math.floor(triple / 4096) % 64
    local s3 = math.floor(triple / 64) % 64
    local s4 = triple % 64

    out[#out + 1] = b64chars:sub(s1 + 1, s1 + 1)
    out[#out + 1] = b64chars:sub(s2 + 1, s2 + 1)

    if i + 1 <= len then
      out[#out + 1] = b64chars:sub(s3 + 1, s3 + 1)
    else
      out[#out + 1] = "="
    end

    if i + 2 <= len then
      out[#out + 1] = b64chars:sub(s4 + 1, s4 + 1)
    else
      out[#out + 1] = "="
    end

    i = i + 3
  end
  return table.concat(out)
end

local function base64_decode(data)
  data = data:gsub("%s", "")
  if (#data % 4) ~= 0 then return nil end

  local out = {}
  local i = 1
  while i <= #data do
    local c1 = b64lookup[data:sub(i, i)]
    local c2 = b64lookup[data:sub(i + 1, i + 1)]
    local c3 = b64lookup[data:sub(i + 2, i + 2)]
    local c4 = b64lookup[data:sub(i + 3, i + 3)]
    if c1 == nil or c2 == nil or c3 == nil or c4 == nil then return nil end

    local triple = c1 * 262144 + c2 * 4096 + c3 * 64 + c4
    local a = math.floor(triple / 65536) % 256
    local b = math.floor(triple / 256) % 256
    local c = triple % 256

    out[#out + 1] = string.char(a)
    if data:sub(i + 2, i + 2) ~= "=" then out[#out + 1] = string.char(b) end
    if data:sub(i + 3, i + 3) ~= "=" then out[#out + 1] = string.char(c) end

    i = i + 4
  end
  return table.concat(out)
end

local function base64url_encode(raw)
  local b64 = base64_encode(raw)
  b64 = b64:gsub("%+", "-"):gsub("/", "_"):gsub("=", "")
  return b64
end

local function base64url_decode(s)
  s = s:gsub("%-", "+"):gsub("_", "/")
  local pad = #s % 4
  if pad == 2 then s = s .. "=="
  elseif pad == 3 then s = s .. "="
  elseif pad ~= 0 then return nil end
  return base64_decode(s)
end

local M = {}

-- ------------------------------------------------------------
-- helpers
-- ------------------------------------------------------------
local function split3(token)
  local a, b, c = token:match("^([^.]+)%.([^.]+)%.([^.]+)$")
  return a, b, c
end

local function shallow_copy(t)
  local out = {}
  for k, v in pairs(t) do out[k] = v end
  return out
end

local function now_sec(options)
  if options and type(options.now) == "function" then
    return options.now()
  end
  return os.time()
end

-- ------------------------------------------------------------
-- Public API
-- ------------------------------------------------------------
function M.sign(payload, secret, options)
  if type(payload) ~= "table" then error("payload must be a table") end
  if type(secret) ~= "string" or secret == "" then error("secret is required") end
  options = options or {}

  local p = shallow_copy(payload)
  local now = now_sec(options)

  if options.expiresIn then p.exp = now + options.expiresIn end
  if options.notBefore then p.nbf = now + options.notBefore end
  if options.issuer then p.iss = options.issuer end
  if options.audience then p.aud = options.audience end
  if p.iat == nil then p.iat = now end

  local header = { alg = "HS256", typ = "JWT" }

  local header_b64 = base64url_encode(json.encode(header))
  local payload_b64 = base64url_encode(json.encode(p))
  local message = header_b64 .. "." .. payload_b64

  local sig = crypto.hmac_sha256(secret, message)
  local sig_b64 = base64url_encode(sig)

  return message .. "." .. sig_b64
end

function M.verify(token, secret, options)
  if type(token) ~= "string" or token == "" then return false, "token is required" end
  if type(secret) ~= "string" or secret == "" then return false, "secret is required" end
  options = options or {}

  local h64, p64, s64 = split3(token)
  if not h64 then return false, "invalid token format" end

  local header_json = base64url_decode(h64)
  local payload_json = base64url_decode(p64)
  local sig = base64url_decode(s64)
  if not header_json then return false, "invalid header encoding" end
  if not payload_json then return false, "invalid payload encoding" end
  if not sig then return false, "invalid signature encoding" end

  local ok, header = pcall(json.decode, header_json)
  if not ok or type(header) ~= "table" then return false, "invalid header json" end

  if header.alg ~= "HS256" then
    return false, "unsupported algorithm: " .. tostring(header.alg)
  end

  ok, payload = pcall(json.decode, payload_json)
  if not ok or type(payload) ~= "table" then return false, "invalid payload json" end

  local message = h64 .. "." .. p64
  local expected = crypto.hmac_sha256(secret, message)

  if not crypto.constant_time_equals(sig, expected) then -- use crypto.constant_time_equals
    return false, "invalid signature"
  end

  local leeway = tonumber(options.leeway or 0) or 0
  local now = now_sec(options)

  if payload.exp and type(payload.exp) == "number" and (payload.exp + leeway) < now then
    return false, "token expired"
  end
  if payload.nbf and type(payload.nbf) == "number" and (payload.nbf - leeway) > now then
    return false, "token not yet valid"
  end

  if options.issuer and payload.iss ~= options.issuer then
    return false, "invalid issuer"
  end

  if options.audience then
    local aud = payload.aud
    if type(aud) == "table" then
      local found = false
      for _, v in ipairs(aud) do
        if v == options.audience then found = true; break end
      end
      if not found then return false, "invalid audience" end
    elseif aud ~= options.audience then
      return false, "invalid audience"
    end
  end

  return true, payload
end

function M.decode(token)
  if type(token) ~= "string" or token == "" then return nil, nil end
  local h64, p64 = token:match("^([^.]+)%.([^.]+)%.([^.]+)$")
  if not h64 then return nil, nil end

  local header_json = base64url_decode(h64)
  local payload_json = base64url_decode(p64)
  if not header_json or not payload_json then return nil, nil end

  local ok1, header = pcall(json.decode, header_json)
  local ok2, payload = pcall(json.decode, payload_json)
  if not ok1 or not ok2 then return nil, nil end
  return header, payload
end

function M.create_refresh_token(payload, secret, expiresIn)
  expiresIn = expiresIn or (30 * 24 * 60 * 60)
  return M.sign(payload, secret, { expiresIn = expiresIn })
end

function M.create_access_token(payload, secret, expiresIn)
  expiresIn = expiresIn or (15 * 60)
  return M.sign(payload, secret, { expiresIn = expiresIn })
end

return M
