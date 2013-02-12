local bencode = require "bencode"
local Cookie = require "tritone.http.cookie"
local string = require "string"
local table = require "table"

local pairs = pairs
local setmetatable = setmetatable
local tostring = tostring
local type = type
local print = print

local M = {}

function M:__call(args)
  self.body = args.body or self.body
  self.headers = args.headers or self.headers
  self.status = args.status or self.status
  return self
end

function M:_findCookieIndex(name)
  local n = 0
  local patt = string.format("^%s", name)

  self.headers["Set-Cookie"] = self.headers["Set-Cookie"] or {}
  for i, v in pairs(self.headers["Set-Cookie"]) do
    if v._cookie and string.match(v:name(), patt) then
      n = i
      break
    end
  end

  return (n == 0) and (#self.headers["Set-Cookie"] + 1) or n
end

function M:new(o)
  o = o or {}
  o._panic = false
  o._response = true
  o.body = o.body or nil
  o.headers = o.headers or {}
  o.status = o.status or 200
  o.userdata = o.userdata or {}

  setmetatable(o, self)
  self.__index = self
  return o
end

function M:abort(statuscode)
  self.status = statuscode or self.status
  error(self)
end

function M:addflash(msg)
  local cookieName = '_tritone.flashes'
  local cookie = self:getcookie(cookieName) or Cookie:new{cookieName, 'le'}
  local flashes = cookie:value()
  if string.sub(flashes, 1, 1) ~= "l" then
    flashes = "le"
  end
  cookie:setvalue(string.format("l%s%d:%se", string.sub(flashes, 2, -2), #msg, msg))
  local idx = self:_findCookieIndex(cookieName)
  self.headers["Set-Cookie"][idx] = cookie
  return self
end

function M:addheader(name, value)
  self.headers[name] = self.headers[name] or {}
  table.insert(self.headers[name], value)
  return self
end

function M:clear()
  o._panic = false
  o.body = nil
  o.headers = {}
  o.status = 200
  o.userdata = {}
  return self
end

function M:getcookie(name)
  local n = self:_findCookieIndex(name)
  self.headers["Set-Cookie"] = self.headers["Set-Cookie"] or {}
  return self.headers["Set-Cookie"][n]
end

function M:created(b)
  self.status = 201
  self.body = b or self.body
  error(self)
end

function M:delcookie(name)
  self.headers["Set-Cookie"] = self.headers["Set-Cookie"] or {}
  local cookie = Cookie:new{name, "_deleted", delete=true}
  local n = self:_findCookieIndex(name)
  self.headers["Set-Cookie"][n] = tostring(cookie)
  return self
end

function M:delqueuedflashes()
  local n = self:_findCookieIndex("_tritone.flashes")
  self.headers["Set-Cookie"] = self.headers["Set-Cookie"] or {}
  self.headers["Set-Cookie"][n] = nil
  return self
end

function M:getbody()
  return self.body
end

function M:notfound(b)
  self.status = 404
  self.body = b or self.body
  error(self)
end

function M:ok(b)
  self.status = 200
  self.body = b or self.body
  error(self)
end

function M:panic(statuscode)
  self.status = statuscode or self.status
  self._panic = true
  error(self)
end

function M:queuedflashes()
  local f = {}
  local cookie = self:getcookie("_tritone.flashes")

  if cookie then
    f = bencode.decode(cookie:value())
  end

  return f
end

function M:redirect(uri, code)
  self.status = code or 303
  self:setheader("Location", uri)
  error(self)
end

local function getNameValue(paramsOrName, valueOrNil)
  local name, value
  if type(paramsOrName) == 'table' then
    name = paramsOrName[1]
    value = paramsOrName[2]
  else
    name = paramsOrName
    value = valueOrNil
  end
  return name, value
end

local function getParams(paramsOrName, valueOrNil)
  local params
  if type(paramsOrName) == 'table' then
    params = paramsOrName
  else
    params = { paramsOrName, valueOrNil }
  end
  return params
end

function M:setcookie(paramsOrName, valueOrNil)
  local cookieparams = getParams(paramsOrName, valueOrNil)
  if cookieparams.signed then
    cookieparams.salt = self.cookiesecret
  end
  local cookie = Cookie:new(cookieparams)
  self.headers["Set-Cookie"] = self.headers["Set-Cookie"] or {}
  local n = self:_findCookieIndex(cookie:name())
  self.headers["Set-Cookie"][n] = cookie
  return self
end

function M:setheader(paramsOrName, valueOrNil)
  local name, value = getNameValue(paramsOrName, valueOrNil)
  self.headers[name] = {}
  table.insert(self.headers[name], value)
  return self
end

return M
