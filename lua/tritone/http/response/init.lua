local bencode = require "bencode"
local Cookie = require "tritone.http.cookie"
local string = require "string"
local table = require "table"

local pairs = pairs
local setmetatable = setmetatable
local tostring = tostring
local type = type

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
        if string.match(v, patt) then
            n = i
            break
        end
    end

    return (n == 0) and #self.headers["Set-Cookie"] + 1 or n
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
    local flashes = self:cookievalue("_tritone.flashes") or "le"
    if string.sub(flashes, 1, 1) ~= "l" then
        flashes = "le"
    end
    self:setcookie("_tritone.flashes", string.format("l%s%d:%se", string.sub(flashes, 2, -2), #msg, msg))
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

function M:cookievalue(name)
    local n = self:_findCookieIndex(name)
    self.headers["Set-Cookie"] = self.headers["Set-Cookie"] or {}
    return self.headers["Set-Cookie"][n]
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

function M:panic(statuscode)
    self.status = statuscode or self.status
    self._panic = true
    error(self)
end

function M:queuedflashes()
    local f = {}
    local val = self:cookievalue("_tritone.flashes")

    if val then
        f = bencode.decode(val)
    end

    return f
end

function M:redirect(uri, code)
    self.status = code or 303
    self:setheader("Location", uri)
    error(self)
end

function M:render(b)
    self.body = b or self.body
    error(self)
end

function M:setcookie(paramsOrName, maybeValue)
    self.headers["Set-Cookie"] = self.headers["Set-Cookie"] or {}
    local params

    if type(paramsOrName) == "string" then
        params = {paramsOrName, maybeValue}
    else
        params = paramsOrName
    end

    local cookie = Cookie:new(params)
    local n = self:_findCookieIndex(params[1])
    self.headers["Set-Cookie"][n] = tostring(cookie)
    return self
end

function M:setheader(name, value)
    self.headers[name] = {}
    table.insert(self.headers[name], value)
    return self
end

return M
