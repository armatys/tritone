local anet = require 'anet'
local class = require '30log'
local debug = require 'debug'
local os = require 'os'
local perun = require 'perun'
local string = require 'string'
local table = require 'table'

local error = error
local ipairs = ipairs
local loadstring = loadstring
local setmetatable = setmetatable
local type = type
local print = print

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

Handler = class {
  _fn = nil,
  _services = {}
}

function Handler:__init(services, fn)
  self._fn = string.dump(fn)
  self._services = {}
  for _, service in ipairs(services) do
    self._services[service] = true
  end
end

HttpServer = class {
  _configtable = {},
  _errorstragety = ErrorStrategy.Retry,
  _fd = 0, -- server listening socket
  _isrunning = false,
  _userservices = {},
  _workercount = 1,
  _workerfutures = {}
}

function HttpServer:__init()
  -- body
end

function HttpServer:_dispatchMissingWorkers()
  local requiredWorkerCount = self._workercount - #self._workerfutures
  for i = 1, requiredWorkerCount do
    self:_dispatchWorker()
  end
end

function HttpServer:_dispatchWorker()
  local f = perun.future(function(fd, config)
    local perun = require 'perun'
    local clienthandler = require 'tritone.clienthandler'
    perun.spawn(clienthandler.loop, fd, config)
    perun.main()
  end, self._fd, self._configtable, self._userservices)

  table.insert(self._workerfutures, f)
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
        -- the error could be logged anyway (e.g. through zmq)
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

function HttpServer:services(servicesDict)
  self._userservices = servicesDict
end

function HttpServer:serve(host, port)
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

function HttpServer:urls(t)
  for _, config in ipairs(t) do
    local urlpatt, handler = config[1], config[2]

    if not (urlpatt and handler) then
      error('URL pattern or handler not specified.')
    end

    local methods = t.method or t.methods
    if type(methods) == 'string' then
      methods = { methods }
    end

    table.insert(self._configtable, {
      pattern = urlpatt,
      handler = handler,
      name = config.name,
      methods = methods
    })
  end
end

return _M
