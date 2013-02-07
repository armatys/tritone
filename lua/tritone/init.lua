local anet = require 'anet'
local debug = require 'debug'
local os = require 'os'
local perun = require 'perun'
local string = require 'string'
local table = require 'table'

local error = error
local ipairs = ipairs
local loadstring = loadstring
local pairs = pairs
local setmetatable = setmetatable
local type = type
local log = print

local _M = {}
setfenv(1, _M)

function enum(t)
  local o = {}
  for i, v in ipairs(t) do
    o[v] = i
  end
  return setmetatable({}, {
    __index = function(self, k)
      return o[k]
    end,
    __newindex = function()
      error('Cannot modify an enum.')
    end
  })
end

ErrorStrategy = enum {'Fail', 'Retry'}

local Builder = {}

function Builder:__add(other)
  local otherType = type(other)

  if otherType == 'table' and other._builder then
    for k, v in pairs(other._methods) do
      self._methods[string.lower(k)] = true
    end
  elseif otherType == 'table' then
    -- save services
    for _, v in ipairs(other) do
      table.insert(self._services, v)
    end
  elseif otherType == 'string' then
    -- save url pattern
    self._pattern = other
  else
    error('Invalid argument (add)', 2)
  end

  return self
end

function Builder:__index(k)
  if k == 'before' then
    return function(fnname)
      table.insert(self._before, fnname)
      return self
    end
  elseif k == 'after' then
    return function(fnname)
      table.insert(self._after, fnname)
      return self
    end
  elseif k == 'finally' then
    return function(fnname)
      table.insert(self._finally, fnname)
      return self
    end
  else
    self._methods[k] = true
    return self
  end
end

function Builder:__sub(other)
  if type(other) == 'string' then
    self._name = other
  else
    error('Invalid argument (substraction)', 2)
  end
  return self
end

function Builder:__tostring()
  local buf = {'<Builder: M('}
  for k, _ in pairs(self._methods) do
    table.insert(buf, k)
  end
  table.insert(buf, ')')

  if #self._pattern > 0 then
    table.insert(buf, 'PATTERN:')
    table.insert(buf, self._pattern)
  end

  table.insert(buf, '>')
  return table.concat(buf, ' ')
end

function Builder:new(server)
  local o = {}
  o._after = {}
  o._before = {}
  o._builder = true
  o._finally = {}
  o._methods = {}
  o._name = ''
  o._pattern = ''
  o._services = {}
  o._server = server
  setmetatable(o, self)
  return o
end

HttpServer = {}

function HttpServer:new(tmpl)
  local o = tmpl or {}
  o._configtable = {}
  o._errorstragety = ErrorStrategy.Retry
  o._fd = 0 -- server listening socket
  o._isrunning = false
  o._userservices = {}
  o._workercount = 1
  o._workerfutures = {}
  self.__index = self
  setmetatable(o, self)
  return o
end

function HttpServer:__newindex(k, v)
  if type(k) == 'table' and k._builder then
    -- freeze and store in server
    self:_setroute(k, v)
  else
    error('Invalid argument (newindex)', 2)
  end
end

function HttpServer:__call(arg)
  if type(arg) ~= 'string' then
    error('Invalid argument: url string expected', 2)
  end
  local server = self
  local o = {}
  o._url = arg
  o._name = ''
  function o:__call(arg)
    if type(arg) == 'string' then
      self._name = arg
    else
      error('Invalid argument', 2)
    end
    return self
  end
  function o:__newindex(k, v)
    if type(k) ~= 'table' then
      error('Invalid argument', 2)
    end
    server:_setroute(k, v, self._url, self._name)
  end
  setmetatable(o, o)
  return o
end

function HttpServer:_dispatchMissingWorkers()
  local requiredWorkerCount = self._workercount - #self._workerfutures
  for i = 1, requiredWorkerCount do
    self:_dispatchWorker()
  end
end

function HttpServer:_dispatchWorker()
  local f = perun.future(function(fd, config, userservices)
    local perun = require 'perun'
    local clienthandler = require 'tritone.clienthandler'
    perun.spawn(clienthandler.loop, fd, config, userservices)
    perun.main()
  end, self._fd, self._configtable, self._userservices)

  table.insert(self._workerfutures, f)
end

function HttpServer:_setroute(builder, handler, url, routename)
  if not (builder and handler and url) then
    error('URL pattern or handler not specified.')
  end

  local requiredServices = {}
  for _, v in ipairs(builder._services) do
    requiredServices[v] = true
  end

  table.insert(self._configtable, {
      after = builder._after,
      before = builder._before,
      debug = self.debug,
      finally = builder._finally,
      pattern = url,
      handler = string.dump(handler),
      name = routename,
      methods = builder._methods,
      services = requiredServices
    })
end

function HttpServer:_wait()
  local maxFailureInterval = 5 -- seconds
  local lastDispatchTime = 0

  while true do
    local readyFuture = perun.getany(self._workerfutures)
    local ok, errmsg = readyFuture:get()

    if ok then
      self:_dispatchMissingWorkers()
    else
      if self._errorstragety == ErrorStrategy.Fail then
        error(errmsg)
      elseif self._errorstragety == ErrorStrategy.Retry then
        if self.debug then
          log(errmsg)
        end
        local now = os.time()
        local d = now - lastDispatchTime
        lastDispatchTime = now
        if d < maxFailureInterval then
          error(errmsg)
        else
          self:_dispatchMissingWorkers()
        end
      end
    end
  end
end

function HttpServer:builder()
  return Builder:new(self)
end

function HttpServer:services(servicesDict)
  for k, v in pairs(servicesDict) do
    self._userservices[k] = string.dump(v)
  end
end

function HttpServer:serve(host, port)
  if #self._configtable == 0 then
    error('No routes were defined.', 2)
  end

  local fd, errmsg, errcode = anet.tcpserver(port or 8080, host or '127.0.0.1')
  if not fd then
    return false, errmsg
  end

  self._fd = fd

  for i = 1, self._workercount do
    self:_dispatchWorker()
  end

  perun.async(function()
    self:_wait()
  end)

  self._isrunning = true
  perun.main()
end

return _M
