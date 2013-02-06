local string = require "string"
local table = require "table"
local ipairs = ipairs
local pairs = pairs
local tonumber = tonumber
local type = type

local _M = {}
setfenv(1, _M)

StatusLine = {
  [100] = "Continue",
  [101] = "Switching Protocols",
  [200] = "OK",
  [201] = "Created",
  [202] = "Accepted",
  [203] = "Non-Authoritative Information",
  [204] = "No Content",
  [205] = "Reset Content",
  [206] = "Partial Content",
  [300] = "Multiple Choices",
  [301] = "Moved Permanently",
  [302] = "Found",
  [303] = "See Other",
  [304] = "Not Modified",
  [305] = "Use Proxy",
  [307] = "Temporary Redirect",
  [400] = "Bad Request",
  [401] = "Unauthorized",
  [402] = "Payment Required",
  [403] = "Forbidden",
  [404] = "Not Found",
  [405] = "Method Not Allowed",
  [406] = "Not Acceptable",
  [407] = "Proxy Authentication Required",
  [408] = "Request Timeout",
  [409] = "Conflict",
  [410] = "Gone",
  [411] = "Length Required",
  [412] = "Precondition Failed",
  [413] = "Request Entity Too Large",
  [414] = "Request-URI Too Long",
  [415] = "Unsupported Media Type",
  [416] = "Requested Range Not Satisfiable",
  [417] = "Expectation Failed",
  [500] = "Internal Server Error",
  [501] = "Not Implemented",
  [502] = "Bad Gateway",
  [503] = "Service Unavailable",
  [504] = "Gateway Timeout",
  [505] = "HTTP Version Not Supported"
}

local function escapeMagicChars(s)
  local magic = "[%^%$%(%)%%%.%[%]%*%+%-%?]"
  return string.gsub(s, magic, function(cap)
    return "%" .. cap
  end)
end

--- Dumps a table with headers into a string.
-- Since an HTTP request or response can contain
-- multiple headers with the same key,
-- but Lua tables cannot hold two different values
-- for the same key. To get around that, multiple values are stored
-- inside an array and this array should be then written as
-- a value for given HTTP header key. 
function dumpHeaders(htable)
  local hbuf = {}
  for k, v in pairs(htable) do
    if type(v) == "table" then
      for _, m in ipairs(v) do
        table.insert(hbuf, k)
        table.insert(hbuf, ": ")
        table.insert(hbuf, m)
        table.insert(hbuf, "\r\n")
      end
    else
      table.insert(hbuf, k)
      table.insert(hbuf, ": ")
      table.insert(hbuf, v)
      table.insert(hbuf, "\r\n")
    end
  end
  return table.concat(hbuf)
end

-- http://lua-users.org/wiki/StringRecipes
function urlDecode(str)
  str = string.gsub(str, "+", " ")
  str = string.gsub(str, "%%(%x%x)", function(h) return string.char(tonumber(h,16)) end)
  str = string.gsub(str, "\r\n", "\n")
  return str
end

-- http://lua-users.org/wiki/StringRecipes
function urlEncode(str)
  if (str) then
    str = string.gsub(str, "\n", "\r\n")
    str = string.gsub(str, "([^%w ])", function(c) return string.format("%%%02X", string.byte(c)) end)
    str = string.gsub(str, " ", "+")
  end
  return str  
end

function parseCookieHeader(data, cookies)
  local regexp = '^([^=]+)="?([^";]*)"?;?%s?(.*)$'
  cookies = cookies or {}

  while true do
    local name, value, rest = string.match(data, regexp)
    if name then
      cookies[name] = value
      data = rest
    else
      break
    end
  end

  return cookies
end

function parseUrlEncodedQuery(data)
  if not data then
    return {}
  end

  local params = {}
  local regexp = "^([^=]+)=([^&]*)&?(.*)$"

  while true do
    local name, value, rest = string.match(data, regexp)
    if name then
      name, value = urlDecode(name), urlDecode(value)
      params[name] = value
      data = rest
    else
      break
    end
  end

  return params
end

function getMultipartDataBoundary(contentTypeHeader)
  local boundary = string.match(contentTypeHeader, "[;%s]boundary=([^\r\n;]+)")
  return boundary or nil
end

--- Parses a multipart/form-data body content.
-- Parsed data is inserted into array, which is returned to the caller.
-- For each data part, an object with the following
-- keys is created: "filename", "content-type", "content". The created object
-- is inserted into returned table using a string key `name` (if it exists).
-- If the data part does not have a `name` property, the object is inserted
-- using `table.insert` (at the first available numerical index, starting from one).
-- If a data part does not have a `filename` property, and its "content-type" is
-- equal to "text/plain", then the string content is inserted directly into
-- the returned table (without the object wrapper).
-- @param boundary The multipart boundary.
-- @param content The body content.
-- @return An object with parsed data.
function parseMultipartData(boundary, content)
  local params = {}
  local headerRe = "^([^:%s]+):%s?([^\r\n]+)\r\n"
  local boundaryRe = "%-%-" .. pstring.escapeMagicChars(boundary)
  local partRe = "^(.-)\r\n" .. boundaryRe

  -- read initial boundary
  local rest = string.match(content, "^" .. boundaryRe .. "\r?\n(.*)")
  if not rest then
    return nil
  end
  content = rest

  while true do
    local headers = {["content-type"]="text/plain"}
    local data = nil

    -- read headers
    while true do
      local k, v, rest = string.match(content, headerRe .. "(.*)")
      if not k then
        break
      end
      content = rest
      headers[k:lower()] = v
    end

    -- read an empty line
    local rest = string.match(content, "^\r\n(.*)")
    if not rest then
      break
    end
    content = rest

    -- read the content part
    local d, rest = string.match(content, partRe .. "(.*)")
    if not d then
      break
    end
    data = d
    content = rest

    -- now I have headers and data; from header content-disposition (if exists) extract name and filename (both optional)
    local name, filename = nil, nil
    if headers["content-disposition"] then
      name = string.match(headers["content-disposition"], '[:;%s]name="?([^;"\r\n]+)"?')
      filename = string.match(headers["content-disposition"], '[:;%s]filename="?([^;"\r\n]+)"?')
    end
    local obj = {
      ["content-type"] = headers["content-type"],
      content = data,
      filename = filename,
    }

    if name then
      if not filename and headers["content-type"] == "text/plain" then
        params[name] = data
      else
        params[name] = obj
      end
    else
      table.insert(params, obj)
    end

    -- now check if we have \r\n or --\r\n, which means end of the stream
    rest = string.match(content, "^%-%-\r?\n(.*)")
    if rest then
      break
    else
      rest = string.match(content, "^\r?\n(.*)")
      if rest then
        content = rest
      end
    end
  end

  return params
end

return _M
