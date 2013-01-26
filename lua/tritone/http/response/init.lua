local bencode = require "perun.bencode"
local Cookie = require "tritone.http.cookie"
local string = require "string"
local table = require "table"

local pairs = pairs
local setmetatable = setmetatable
local tostring = tostring
local type = type

local M = {}

function M:new(o)
    o = o or {}
    o.body = o.body or nil
    o.headers = o.headers or {}
    o.status = o.status or 200

    setmetatable(o, self)
    self.__index = self
    return o
end

function M:addheader(name, value)
    self.headers[name] = self.headers[name] or {}
    table.insert(self.headers[name], value)
end

function M:delcookie(name)
    self.headers["Set-Cookie"] = self.headers["Set-Cookie"] or {}
    local cookie = Cookie:new{name, "_deleted", delete=true}
    local n = self:_findCookieIndex(name)
    self.headers["Set-Cookie"][n] = tostring(cookie)
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
end

function M:cookievalue(name)
    local n = self:_findCookieIndex(name)
    self.headers["Set-Cookie"] = self.headers["Set-Cookie"] or {}
    return self.headers["Set-Cookie"][n]
end

function M:setheader(name, value)
    self.headers[name] = {}
    table.insert(self.headers[name], value)
end

function M:redirect(uri, code)
    code = code or 303
    self.status = code
    self:setheader("Location", uri)
end

function M:render(template, context)
    self._render = {template, context}
end

function M:addflash(msg)
    local flashes = self:cookievalue("_perun.flashes") or "le"
    if string.sub(flashes, 1, 1) ~= "l" then
        flashes = "le"
    end
    self:setcookie("_perun.flashes", string.format("l%s%d:%se", string.sub(flashes, 2, -2), #msg, msg))
end

function M:queuedflashes()
    local f = {}
    local val = self:cookievalue("_perun.flashes")

    if val then
        f = bencode.decode(val)
    end

    return f
end

function M:delqueuedflashes()
    local n = self:_findCookieIndex("_perun.flashes")
    self.headers["Set-Cookie"] = self.headers["Set-Cookie"] or {}
    self.headers["Set-Cookie"][n] = nil
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

return M
