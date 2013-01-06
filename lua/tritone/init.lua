local anet = require 'anet'
local class = require '30log'
local debug = require 'debug'
local os = require 'os'
local perun = require 'perun'
local string = require 'string'
local table = require 'table'

local error = error
local ipairs = ipairs
local setmetatable = setmetatable
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

HttpServer = class {
  errorstragety = ErrorStrategy.Retry,
  workercount = 1,
  _configtable = {},
  _fd = 0, -- server listening socket
  _isrunning = false,
  _workerfutures = {}
}

function HttpServer:__init()
  -- body
end

function HttpServer:urls(t)
  for _, config in ipairs(t) do
    local urlpatt, fn = config[1], config[2]
    local fndump = string.dump(fn)
    local fnname = config.name or debug.getinfo(fn, 'n').name

    self._configtable[urlpatt] = {
      callback = fndump,
      name = fnname
    }
  end
end

function HttpServer:dispatchWorker()
  local f = perun.future(function(fd, config)
    local perun = require 'perun'
    local clienthandler = require 'tritone.clienthandler'
    perun.spawn(clienthandler.loop, fd, config)
    perun.main()
  end, self._fd, self._configtable)

  table.insert(self._workerfutures, f)
end

function HttpServer:dispatchMissingWorkers()
  local requiredWorkerCount = self.workercount - #self._workerfutures
  for i = 1, requiredWorkerCount do
    self:dispatchWorker()
  end
end

function HttpServer:wait()
  local maxFailureInterval = 5 -- seconds
  local lastDispatchTime = 0

  while true do
    local readyFuture = perun.getany(self._workerfutures)
    local ok, errmsg = readyFuture:get()

    if ok then
      self:dispatchMissingWorkers()
    else
      if self.errorstragety == ErrorStrategy.Fail then
        error(errmsg)
      elseif self.errorstragety == ErrorStrategy.Retry then
        -- the error could be logged anyway (e.g. through zmq)
        local now = os.time()
        local d = now - lastDispatchTime
        lastDispatchTime = now
        if d < maxFailureInterval then
          error(errmsg)
        else
          self:dispatchMissingWorkers()
        end
      end
    end
  end
end

function HttpServer:serve(host, port)
  local fd, errmsg, errcode = anet.tcpserver(port or 8080, host or '127.0.0.1')
  if not fd then
    return false, errmsg
  end

  self._fd = fd

  for i = 1, self.workercount do
    self:dispatchWorker()
  end

  perun.async(function()
    self:wait()
  end)

  self._isrunning = true
  perun.main()
end

return _M
