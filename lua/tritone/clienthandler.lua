local anet = require 'anet'
local bencode = require 'bencode'
local Cookie = require 'tritone.http.Cookie'
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
local setmetatable = setmetatable
local type = type
local unpack = unpack

local globals = _G

local _M = {}
setfenv(1, _M)

math.randomseed(os.time())
-- After this number of requests, finish serving.
-- That will release the memory of the worker thread.
local maxServedRequestCount = 10000 + math.random(0, 10000)
local currentServedRequestCount = 0
local isTerminating = false
local cookiePatt = lpeg.S'Cc' * lpeg.P'ookie'

local function keepaliveHeader(httpver, keepalive)
  if keepalive and httpver == '1.1' then
    return ''
  elseif keepalive and httpver == '1.0' then
    return 'Connection: Keep-Alive\r\n'
  elseif not keepalive then
    return 'Connection: Close\r\n'
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

local function getflashes(cookies, response)
  return function()
    local reqFlashes = bencode.decode(cookies['_tritone.flashes'] or 'le') or {}
    local all = {}

    for i, v in ipairs(reqFlashes) do
      table.insert(all, {msg=v})
    end

    return all
  end
end

local function _clienthandler(configtable, userservices, cfd, ip, port)
  local state = nil
  local shouldRead = true -- Determines if we should read from the client socket.
  local responseError --

  local function stopReading(s)
    shouldRead = false
    state = s
  end

  local captures = nil -- a table with captured values (may be empty)
  local method = nil -- parsed method name, e.g. 'get' or 'post'
  local config = nil -- {pattern=, handler=, name=?, methods=?} (see HttpServer:_setroute for more fileds)

  -- Each one of the 'should*' variables corrensponds to a service.
  local shouldKeepHeaders = false -- 'headers'
  local shouldParseCookies = false -- 'cookies'
  local shouldParseQuery = false -- 'query'
  local shouldKeepBody = false -- 'body'
  local shouldParseFormData = false -- 'form' application/x-www-form-urlencoded
  local shouldParseMultipartFormData = false -- 'formdata' multipart/form-data
  local shouldParseFlashes = false -- 'flashes'
  local shouldKeepRequest = false -- 'request'

  -- Containers for request data
  local body = nil
  local cookies = nil
  local flashes = nil
  local formdata = nil
  local formurlencoded = nil
  local headers = nil
  local query = nil
  local requestdata = nil

  -- Bufferes for request data
  local bodybuf = {}
  local headerfieldbuf = {}
  local headervaluebuf = {}

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
          shouldParseFlashes = requiredServices['flashes']
          shouldParseCookies = requiredServices['cookies'] or shouldParseFlashes
          shouldParseQuery = requiredServices['query']
          shouldParseFormData = requiredServices['form']
          shouldParseMultipartFormData = requiredServices['formdata']
          shouldKeepBody = requiredServices['body'] or shouldParseFormData or shouldParseMultipartFormData
          shouldKeepHeaders = requiredServices['headers'] or shouldParseFormData or shouldParseMultipartFormData or shouldParseCookies
          shouldKeepRequest = requiredServices['request']

          if shouldKeepHeaders then headers = {} end
          if shouldParseCookies then cookies = {} end
          if shouldParseQuery then
            query = http.parseUrlEncodedQuery(parsed.query)
          end
          if shouldKeepRequest then
            requestdata = { method=method, path=parsed.path }
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
          putHeader(string.lower(key), val)
        end

        if cookiePatt:match(key) then
          cookies = Cookie.parseCookieHeader(val, cookies, configtable._cookiesecret)
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
      if shouldParseFormData then
        local contentTypeHeader = headers['content-type'] or ''
        local contentTypeMatches = string.match(contentTypeHeader, 'application/x%-www%-form%-urlencoded')
        if contentTypeMatches then
          formurlencoded = http.parseUrlEncodedQuery(body)
        end
        if not formurlencoded then
          formurlencoded = {}
        end
      end
      if shouldParseMultipartFormData then
        local contentTypeHeader = headers['content-type'] or ''
        local contentTypeMatches = string.match(contentTypeHeader, 'multipart/form%-data')
        local boundary = contentTypeMatches and http.getMultipartDataBoundary(contentTypeHeader)
        if contentTypeMatches and boundary then
          formdata = http.parseMultipartData(boundary, body)
        end
        if not formdata then
          formdata = {}
        end
      end
      if shouldParseFlashes then
        flashes = getflashes(cookies)
        if not flashes then
          flashes = {}
        end
      end
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
        responseError = 'Cannot parse the request.'
        stopReading(500)
      end
    else -- EOF
      break
    end
  end

  if state == 'complete' then
    httpver = request:httpmajor() .. '.' .. request:httpminor()
    local clb = loadstring(config.handler)
    local env = copyGlobals()
    env.response = Response:new{cookiesecret=configtable._cookiesecret}

    -- Fill in built-in services
    if config.services.cookies then env.cookies = cookies end
    if config.services.headers then env.headers = headers end
    if config.services.body then env.body = body end
    if config.services.query then env.query = query end
    if config.services.form then env.form = formurlencoded end
    if config.services.request then
      env.request = requestdata
      env.request.version = httpver
    end
    if config.services.formdata then env.formdata = formdata end
    if config.services.flashes then
      env.flashes = flashes
      env.response:delcookie('_tritone.flashes')
    end
    
    local envmeta = {}
    function envmeta:__index(k)
      local fn = userservices[k]
      if fn then
        setfenv(fn, env)
      end
      return fn
    end
    setmetatable(env, envmeta)

    local ok, err = true, nil

    -- Initially functions
    for _, fnname in ipairs(config.initially) do
      local fn = userservices[fnname]

      if fn then
        setfenv(fn, env)
        local ok, err = pcall(fn, unpack(captures or {}))
        if not ok and config.debug then
          env.response:addheader('X-Tritone-Initially-Error', err)
        end
      else
        error(string.format('No service with name "%s" was found', fnname))
      end
    end

    -- Before functions
    for _, fnname in ipairs(config.before) do
      local fn = userservices[fnname]
      if fn then
        setfenv(fn, env)
        ok, err = pcall(fn, unpack(captures or {}))
        ok = (type(err) == 'table' and err._response and not err._panic) or ok
      else
        error(string.format('No service with name "%s" was found', fnname))
      end
    end

    -- Handler
    if ok then
      setfenv(clb, env)
      ok, err = pcall(clb, unpack(captures or {}))
      ok = (type(err) == 'table' and err._response and not err._panic) or ok
    end

    if ok then
      -- After functions
      for _, fnname in ipairs(config.after) do
        local fn = userservices[fnname]
        if fn then
          setfenv(fn, env)
          ok, err = pcall(fn, unpack(captures or {}))
          ok = (type(err) == 'table' and err._response and not err._panic) or ok
        else
          error(string.format('No service with name "%s" was found', fnname))
        end
      end
    end

    -- Finally functions
    for _, fnname in ipairs(config.finally) do
      local fn = userservices[fnname]

      if fn then
        setfenv(fn, env)
        local ok, err = pcall(fn, unpack(captures or {}))
        if not ok and config.debug then
          env.response:addheader('X-Tritone-Finally-Error', err)
        end
      else
        error(string.format('No service with name "%s" was found', fnname))
      end
    end

    if ok then
      local keepalive = request:shouldkeepalive() and (not isTerminating)
      write_response(cfd, httpver, keepalive, env.response)
      if keepalive then
        return true
      end
    elseif not ok and type(err) == 'table' and err._response then
      write_response(cfd, httpver, false, err)
    else
      write_code_response(cfd, httpver, 500, config.debug and err or nil)
    end
  elseif type(state) == 'number' then
    write_code_response(cfd, httpver, state, responseError)
  end

  anet.close(cfd)
  return false
end

local function clienthandler(configtable, userservices, cfd, ip, port)
  while _clienthandler(configtable, userservices, cfd, ip, port) do
    currentServedRequestCount = currentServedRequestCount + 1
    if currentServedRequestCount >= maxServedRequestCount then
      isTerminating = true
    end
  end
end

function loop(fd, configtable, userservices)
  compilePatterns(configtable)
  
  local definedServices = {}
  for k, v in pairs(userservices) do
    local fn = loadstring(v)
    if type(fn) == 'function' then
      definedServices[k] = fn()
    end
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
  end

  perun.stop()
end

return _M
