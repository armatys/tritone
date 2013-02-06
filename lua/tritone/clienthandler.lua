local anet = require 'anet'
local http = require 'tritone.http'
local hyperparser = require 'hyperparser'
local lpeg = require 'lpeg'
local math = require 'math'
local os = require 'os'
local perun = require 'perun'
local re = require 're'
local Response = require 'tritone.http.response'
local string = require 'string'
local table = require 'table'

local error = error
local ipairs = ipairs
local loadstring = loadstring
local pairs = pairs
local pcall = pcall
local print = print -- TODO remove that later
local setfenv = setfenv
local type = type
local unpack = unpack

local globals = _G

local _M = {}
setfenv(1, _M)

local isTerminating = false
local cookiePatt = lpeg.S'Cc' * lpeg.P'ookie'

local function keepaliveHeader(httpver, keepalive)
  if keepalive and httpver == '1.1' then
    return ''
  elseif keepalive and httpver == '1.0' then
    return 'Connection: Keep-Alive'
  elseif not keepalive then
    return 'Connection: Close'
  end
  return ''
end

local function write_response(cfd, httpver, keepalive, response)
  local statusText = http.StatusLine[response.status] or ''
  local headers = http.dumpHeaders(response.headers)
  local body = response:getbody() or ''
  local buf = {
    'HTTP/', httpver, ' ', response.status, ' ', statusText, '\r\n',
    keepaliveHeader(httpver, keepalive),
    'Content-Length: ', #body, '\r\n',
    headers, '\r\n', body}
  local r = table.concat(buf, '')
  local written, errmsg, errcode = anet.writeall(cfd, r)
  if not written then
    error("Cannot write to the socket: " .. errmsg)
  end
end

local function write_code_response(cfd, httpver, code, msg)
  local statusText = http.StatusLine[code] or ''
  msg = (msg or statusText) .. '\n'
  local buf = {
    'HTTP/', httpver, ' ', code, ' ', statusText, '\r\n',
    'Content-Length: ', #msg, '\r\n',
    'Connection: close\r\nContent-Type: text/plain\r\n\r\n', msg}
  local r = table.concat(buf, '')
  local written, errmsg, errcode = anet.writeall(cfd, r)
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

local function copyGlobals()
  local t = {}
  for k, v in pairs(globals) do
    t[k] = v
  end
  return t
end

local function _clienthandler(configtable, userservices, cfd, ip, port)
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
  local shouldParseQuery = false -- 'query'
  local shouldKeepBody = false -- 'body'
  local shouldParseBody = false -- 'jsonform' (application/json), 'files' (multipart/form-data), 'form' (application/x-www-form-urlencoded)

  local cookies = nil
  local headers = nil
  local body = nil
  local query = nil

  local headerfieldbuf = {}
  local headervaluebuf = {}
  local bodybuf = {}

  local function putHeader(k, v)
    headers[k] = headers[k] or {}
    table.insert(headers[k], v)
  end

  local request = hyperparser.request()
  local httpver = '1.1'
  local parsersettings = {
    msgbegin = nil,
    statuscomplete = nil,
    headerscomplete = nil,
    url = function(url)
      if not shouldRead then return end

      method = request:method()

      local parsed = hyperparser.parseurl(url)
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
          shouldKeepHeaders = requiredServices['headers']
          shouldParseCookies = requiredServices['cookies']
          shouldParseQuery = requiredServices['query']

          if shouldKeepHeaders then headers = {} end
          if shouldParseCookies then cookies = {} end
          if shouldParseQuery then
            query = http.parseUrlEncodedQuery(parsed.query)
          end
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
        if shouldKeepHeaders then
          putHeader(key, val)
        end

        if cookiePatt:match(key) then
          cookies = http.parseCookieHeader(val, cookies)
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
        stopReading(501)
      elseif nparsed ~= nread then
        body = 'Cannot parse the request.'
        stopReading(500)
      end
    else -- EOF
      break
    end
  end

  -- TODO split the method here
  if state == 'complete' then
    httpver = request:httpmajor() .. '.' .. request:httpminor()
    -- TODO create a handler function
    -- by setting a proper func env
    -- then run the handler for as long as it returns true?
    -- run the function using pcall? and return 500 in case of error?
    local clb = loadstring(config.handler)
    local env = copyGlobals()
    env.response = Response:new()
    if config.services.headers then env.headers = headers end
    if config.services.cookies then env.cookies = cookies end
    if config.services.query then env.query = query end
    for k, _ in pairs(config.services) do
      if userservices[k] then
        env[k] = userservices[k]
      end
    end
    setfenv(clb, env)
    local ok, response = pcall(clb, unpack(captures or {}))
    if ok then
      local keepalive = request:shouldkeepalive() and (not isTerminating)
      write_response(cfd, httpver, keepalive, response)
      if keepalive then
        return true
      end
    else
      write_code_response(cfd, httpver, 500, config.debug and response or nil)
    end
  elseif type(state) == 'number' then
    write_code_response(cfd, httpver, state, body)
  end

  anet.close(cfd)
  return false
end

local function clienthandler(configtable, userservices, cfd, ip, port)
  while _clienthandler(configtable, userservices, cfd, ip, port) do end
end

function loop(fd, configtable, userservices)
  math.randomseed(os.time())
  -- After this number of requests, finish serving.
  -- That will release the memory of the worker thread.
  local maxServedRequestCount = 10000 + math.random(0, 10000)
  local currentServedRequestCount = 0
  compilePatterns(configtable)
  
  local definedServices = {}
  for k, v in pairs(userservices) do
    definedServices[k] = loadstring(v)
  end

  while not isTerminating do
    local cfd, ip, port = anet.accept(fd)
    if cfd then
      perun.spawn(function()
        perun.defer(function(ok)
          if not ok then
            -- Close the client fd only if the handler did not finish cleanly.
            perun.c.close(cfd)
          end
        end)
        clienthandler(configtable, definedServices, cfd, ip, port)
      end)
    end

    currentServedRequestCount = currentServedRequestCount + 1
    if currentServedRequestCount >= maxServedRequestCount then
      isTerminating = true
    end
  end

  perun.stop()
end

return _M
