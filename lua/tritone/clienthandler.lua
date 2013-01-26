local anet = require 'anet'
local hyperparser = require 'hyperparser'
local lpeg = require 'lpeg'
local perun = require 'perun'
local re = require 're'
local string = require 'string'
local table = require 'table'

local error = error
local ipairs = ipairs
local type = type
local print = print

local _M = {}
setfenv(1, _M)

local cookiePatt = lpeg.S'Cc' * lpeg.P'ookie'

local response = "HTTP/1.1 200 OK\r\nContent-Length: 14\r\nConnection: close\r\nContent-Type: text/plain\r\n\r\nHello world!\r\n"

local function write_response(cfd)
  local written, errmsg, errcode = anet.writeall(cfd, response, i)
  if not written then
    error("Cannot write to the socket: " .. errmsg)
  end
end

local function compilePatterns(configtable)
  for _, v in ipairs(configtable) do
    local p = re.compile(v.pattern)
    v.pattern = lpeg.Ct(p * lpeg.P(-1))
  end
end

local function clienthandler(configtable, userservices, cfd, ip, port)
  local state = nil
  local shouldRead = true -- Determines if we should read from the client socket.

  local function stopReading(s)
    shouldRead = false
    state = s
  end

  local captures = nil -- a table with captured values (may be empty)
  local method = nil -- parsed method name, e.g. 'GET' or 'POST'
  local config = nil -- {pattern=, handler=, name=?, methods=?}

  -- Each one of the 'should*' variables corrensponds to a service (at least partly).
  local shouldKeepHeaders = false -- 'headers'
  local shouldParseCookies = false -- 'cookies'
  local shouldParseQuery = false -- 'request'
  local shouldKeepBody = false -- 'body'
  local shouldParseBody = false -- 'jsonform' (application/json), 'files' (multipart/form-data), 'form' (application/x-www-form-urlencoded)

  local headers = {}
  local body = nil

  local headerfieldbuf = {}
  local headervaluebuf = {}
  local bodybuf = {}

  local function putHeader(k, v)
    headers[k] = headers[k] or {}
    table.insert(headers[k], v)
  end

  local request = hyperparser.request()
  local parsersettings = {
    msgbegin = nil,
    statuscomplete = nil,
    headerscomplete = nil,
    url = function(url)
      if not shouldRead then return end

      local parsed = hyperparser.parseurl(url)
      method = request:method()
      for _, v in ipairs(configtable) do
        captures = v.pattern:match(parsed.path)
        if captures then
          config = v
          break
        end
      end

      if captures then
        if config.methods[method] then
          -- determine if headers, cookies or body need to be parsed/stored
          local requiredServices = config.services
          shouldKeepHeaders = requiredServices['headers'] or requiredServices['cookies']
          shouldParseQuery = requiredServices['request']
        else
          stopReading(405)
        end
      else
        stopReading(404)
      end
    end,
    headerfield = function(value)
      if not shouldRead then return end
      if not (shouldKeepHeaders or shouldParseCookies) then return end

      if #headerfieldbuf > 0 then
        local key = table.concat(headerfieldbuf, '')
        local val = table.concat(headervaluebuf, '')
        if shouldKeepHeaders or cookiePatt:match(key) then
          putHeader(key, val)
        end
        headerfieldbuf = {}
        headervaluebuf = {}
      end
      table.insert(headerfieldbuf, value)
    end, 
    headervalue = function(value)
      if not shouldRead then return end
      if not (shouldKeepHeaders or shouldParseCookies) then return end
      table.insert(headervaluebuf, value)
    end,
    body = function(content)
      if not shouldRead then return end
      table.insert(bodybuf, content)
    end,
    msgcomplete = function()
      if not shouldRead then return end
      body = table.concat(bodybuf, '')
      stopReading('complete')
    end
  }

  while shouldRead do
    local nread, content, errcode = anet.read(cfd)

    if not nread then
      error('Cannot read from the socket: ' .. content)
    elseif nread > 0 then
      local nparsed = request:execute(content, parsersettings)
      if request:isupgrade() then
        error('Not implemented') -- TODO
      elseif nparsed ~= nread then
        error('Cannot parse the request.')
      end
    else -- EOF
      break
    end
  end

  -- TODO split the method here
  if state == 'complete' then
    -- TODO create a handler function
    -- by setting a proper func env
    -- then run the handler for as long as it returns true?
    -- run the function using pcall? and return 500 in case of error?
    write_response(cfd)
    if not request:shouldkeepalive() then
      anet.close(cfd)
    end
  elseif type(state) == 'number' then
    -- TODO write the response with state as error code
    anet.close(cfd)
  else
    anet.close(cfd)
  end
end

function loop(fd, configtable, userservices)
  compilePatterns(configtable)
  while true do
    local cfd, ip, port = anet.accept(fd)
    if cfd then
      perun.spawn(function()
        perun.defer(function(ok)
          if not ok then
            -- Close the client fd only if the handler did not finish cleanly.
            perun.c.close(cfd)
          end
        end)
        clienthandler(configtable, userservices, cfd, ip, port)
      end)
    end
  end
end

return _M
