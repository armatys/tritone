local os = require "os"
local string = require "string"
local table = require "table"

local setmetatable = setmetatable

local M = {}

function M:new(params)
    local o = {}
    o.params = params
    setmetatable(o, self)
    self.__index = self
    return o
end

function M:__tostring()
    local buf = {}
    table.insert(buf, string.format("%s=%s", self.params[1], self.params[2]))

    if self.params.delete then
        self.params.expires = {year=1970, month=1, day=1}
    end

    if self.params.expires then
        -- generate a string like "Sun, 06 Nov 1994 08:49:37 GMT"
        local s = os.date("%a, %d %b %Y %H:%M:%S GMT", os.time(self.params.expires))
        table.insert(buf, string.format("Expires=%s", s))
    end

    if self.params.maxage then
        table.insert(buf, string.format("Max-Age=%d", self.params.maxage))
    end

    if self.params.domain then
        table.insert(buf, string.format("Domain=%s", self.params.domain))
    end

    if self.params.path then
        table.insert(buf, string.format("Path=%s", self.params.path))
    end

    if self.params.httponly then
        table.insert(buf, "HttpOnly")
    end

    if self.params.secure then
        table.insert(buf, "Secure")
    end

    return table.concat(buf, "; ")
end

return M
