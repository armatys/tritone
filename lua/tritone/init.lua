local anet = require 'anet'
local class = require '30log'
local debug = require 'debug'
local perun = require 'perun'
local string = require 'string'

local ipairs = ipairs
local setmetatable = setmetatable

local _M = {}
setfenv(1, _M)

HttpServer = class {
  _configtable = {},
  _currentworkercount = 0,
  _fd = 0,
  _isrunning = false,
  _workercount = 1
}

local errorHandler = function(reason)
  print('_tritone', _tritone, _tritone.fd, _tritone.config)
  print(reason)
end

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

function HttpServer:serve(host, port)
  local fd, errmsg, errcode = anet.tcpserver(port or 8080, host or '127.0.0.1')
  if not fd then
    return false, errmsg
  end

  for i = 1, self._workercount do
    perun.dispatch(errorHandler, function(fd, config)
      local perun = require 'perun'
      local handler = require 'tritone.handler'
      _tritone = {
        fd = fd,
        config = config
      }
      perun.spawn(handler.loop, fd, config)
      perun.main()
    end, fd, self._configtable)
    self._currentworkercount = self._currentworkercount + 1
  end

  self._isrunning = true
  perun.main()
end

return _M
