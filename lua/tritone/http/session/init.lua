local bencode = require 'bencode'
local pbkdf2 = require 'pbkdf2'

local M = {}

--- Creates a new session object.
-- @param expirationTime number Expiration time (Unix time in seconds)
function M:new(expirationTime)
  local o = {}
  o._data = {}
  o._expiration = expirationTime
  setmetatable(o, self)
  return o
end

function M:__index(k)
  return self._data[k]
end

function M:__newindex(k, v)
  if type(k) ~= 'string' then
    error('Invalid argument - string expected.', 2)
  end
  self._data[k] = v
end

function M:clear()
  self._data = {}
end

function M:invalidate()
  self:clear()
  self._expiration = 0
end

function M:decode(sessionCookieValueString)
  local cookieValueObj = bencode.decode(sessionCookieValueString)
  if not (cookieValueObj.da and cookieValueObj.ex and cookieValueObj.ou and cookieValueObj.sa) then
    return false
  end

  local _, hexout = M.encode({ _data = cookieValueObj.da, _expiration = cookieValueObj.ex}, cookieValueObj.sa)
  if hexout == cookieValueObj.ou then
    self._data = cookieValueObj.da
    self._expiration = cookieValueObj.ex
    return true
  end

  return false
end

function M:encode(salt)
  local timestampedBuf = { 'l' }

  table.insert(timestampedBuf, bencode.encode(self._expiration))

  for k, v in pairs(self._data) do
    local kv = {k, v}
    table.insert(timestampedBuf, bencode.encode(kv))
  end

  table.insert(timestampedBuf, 'e')

  local iterCount = 4096
  local salt, out = pbkdf2.pbkdf2(table.concat(timestampedBuf, ''), salt or iterCount, iterCount)
  local hexout = pbkdf2.hex(out)

  local cookieValueObj = {
    da = self._data,
    ex = self._expiration,
    ou = hexout,
    sa = pbkdf2.hex(salt)
  }

  return bencode.encode(cookieValueObj), hexout
end

return M
