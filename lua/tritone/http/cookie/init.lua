local bencode = require 'bencode'
local os = require "os"
local pbkdf2 = require 'pbkdf2'
local string = require "string"
local table = require "table"

local function encode(data, expiration, salt)
  local timestampedBuf = { 'l' }

  table.insert(timestampedBuf, bencode.encode(expiration))

  for k, v in pairs(data) do
    local kv = {k, v}
    table.insert(timestampedBuf, bencode.encode(kv))
  end

  table.insert(timestampedBuf, 'e')

  local iterCount = 4096
  local salt, out = pbkdf2.pbkdf2(table.concat(timestampedBuf, ''), salt, iterCount)
  local hexout = pbkdf2.hex(out)

  local cookieValueObj = {
    da = data,
    ex = expiration,
    ou = hexout,
  }

  return bencode.encode(cookieValueObj), hexout
end

local function decode(salt, sessionCookieValueString)
  local cookieValueObj = bencode.decode(sessionCookieValueString)
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

function M:new(params)
    local o = {}
    if params.signed then
        if not (params.expires or params.maxage) then
            error('Signed cookie has to have "expires" or "maxage" specified.', 2)
        end
        local value = params[2]
    end
    o._params = params
    setmetatable(o, self)
    self.__index = self
    return o
end

function M:decodedvalue()
    return self._params[2]
end

function M:name()
    return self._params[1]
end

function M:value()
    return self._params[2]
end

function M:__tostring()
    local buf = {}
    table.insert(buf, string.format("%s=%s", self._params[1], self._params[2]))

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
