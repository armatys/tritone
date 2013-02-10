local bencode = require 'bencode'
local http = require 'tritone.http'
local os = require "os"
local pbkdf2 = require 'pbkdf2'
local string = require "string"
local table = require "table"

local function encode(data, expiration, salt)
  local timestampedBuf = {
    'l',
    bencode.encode(expiration),
    bencode.encode(data),
    'e'
  }

  local iterCount = 128
  local salt, out = pbkdf2.pbkdf2(table.concat(timestampedBuf, ''), salt, iterCount)
  local hexout = pbkdf2.hex(out)

  local cookieValueObj = {
    da = data,
    ex = expiration,
    ou = hexout,
  }

  return bencode.encode(cookieValueObj)
end

local function decode(salt, cookieValueString)
  local cookieValueObj = bencode.decode(cookieValueString)
  if not (cookieValueObj.da and cookieValueObj.ex and cookieValueObj.ou) then
    return false
  end

  local _, hexout = encode(cookieValueObj.da, cookieValueObj.ex, salt)
  if hexout == cookieValueObj.ou then
    return true, cookieValueObj.da, cookieValueObj.ex
  end

  return false
end

local M = {}

function M.parseCookieHeader(data, cookies, salt)
  local regexp = '^([^=]+)="?([^";]*)"?;?%s?(.*)$'
  cookies = cookies or {}

  while true do
    local name, value, rest = string.match(data, regexp)
    if name then
      cookies[name] = Cookie:new{name, value, salt=salt, request=true}
      data = rest
    else
      break
    end
  end

  return cookies
end

function M:new(params)
  local o = {}
  if params.signed then
    if not ((params.expires or params.maxage) and params.salt) then
      error('Signed cookie has to have "expires" or "maxage", and "salt" specified.', 2)
    end
  end
  if params.request then
    params[1] = http.urlDecode(params[1])
    params[2] = http.urlDecode(params[2])
  end
  o._params = params
  o._cookie = true
  setmetatable(o, self)
  self.__index = self
  return o
end

function M:decodedvalue()
  if not self._params.salt then
    error('Salt was not specified when creating the cookie.')
  end
  local ok, data, expiration = decode(self._params.salt, self._params[2])
  if ok then
    return data
  end
  return false
end

function M:encodedvalue()
  local expiration = 0
  if self.maxage then
    expiration = self.maxage
  elseif self.expires then
    local now = os.time()
    local diff = os.time(self.expires) - now
    expiration = diff > 0 and diff or 0
  end
  return encode(self._params[2], expiration, self._params.salt)
end

function M:name()
  return self._params[1]
end

function M:value()
  return self._params[2]
end

function M:setvalue(v)
  self._params[2] = v
end

function M:__tostring()
  local buf = {}
  local val = http.urlEncode(self._params.signed and self:encodedvalue() or self:value())
  table.insert(buf, string.format("%s=%s", self:name(), val))

  if self._params.delete then
    self._params.expires = {year=1970, month=1, day=1}
  end

  if self._params.expires then
    -- generate a string like "Sun, 06 Nov 1994 08:49:37 GMT"
    local s = os.date("%a, %d %b %Y %H:%M:%S GMT", os.time(self._params.expires))
    table.insert(buf, string.format("Expires=%s", s))
  end

  if self._params.maxage then
    table.insert(buf, string.format("Max-Age=%d", self._params.maxage))
  end

  if self._params.domain then
    table.insert(buf, string.format("Domain=%s", self._params.domain))
  end

  if self._params.path then
    table.insert(buf, string.format("Path=%s", self._params.path))
  end

  if self._params.httponly then
    table.insert(buf, "HttpOnly")
  end

  if self._params.secure then
    table.insert(buf, "Secure")
  end

  return table.concat(buf, "; ")
end

return M
