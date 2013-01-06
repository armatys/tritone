local anet = require 'anet'
local hyperparser = require 'hyperparser'
local perun = require 'perun'
local string = require 'string'

local print = print

local _M = {}
setfenv(1, _M)

local response = "HTTP/1.1 200 OK\r\nContent-Length: 14\r\nConnection: close\r\nContent-Type: text/plain\r\n\r\nHello world!\r\n"

local function write_response(cfd)
  local written, errmsg, errcode = anet.writeall(cfd, response, i)
  if not written then
    print("Write error", errmsg)
  end
  anet.close(cfd)
end

local function clienthandler(config, cfd, ip, port)
  local state = nil
  local shouldRead = true

  local settings = {
    msgcomplete = function()
      shouldRead = false
      state = 'complete'
    end
  }
  local request = hyperparser.request(settings)

  while shouldRead do
    local nread, content, errcode = anet.read(cfd)

    if not nread then
      anet.close(cfd)
      break
    elseif nread > 0 then
      local nparsed = request:execute(content)
      if nparsed ~= nread then
        anet.close(cfd)
        break
      end
    else
      anet.close(cfd)
      break
    end
  end

  if state == 'complete' then
    -- can execute handler
    write_response(cfd)
  end
end

function loop(fd, config)
  while true do
    local cfd, ip, port = anet.accept(fd)
    if cfd then
      perun.spawn(clienthandler, config, cfd, ip, port)
    end
  end
end

return _M
