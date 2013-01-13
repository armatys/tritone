local anet = require 'anet'
local hyperparser = require 'hyperparser'
local perun = require 'perun'
local string = require 'string'

local error = error
local print = print

local _M = {}
setfenv(1, _M)

local response = "HTTP/1.1 200 OK\r\nContent-Length: 14\r\nConnection: close\r\nContent-Type: text/plain\r\n\r\nHello world!\r\n"

local function write_response(cfd)
  local written, errmsg, errcode = anet.writeall(cfd, response, i)
  if not written then
    error("Cannot write to the socket: " .. errmsg)
  end
end

local function clienthandler(config, cfd, ip, port)
  local state = nil
  local shouldRead = true

  local request = hyperparser.request{
    msgbegin = nil,
    statuscomplete = nil,
    headerscomplete = nil,
    url = function(url)
      local uparser = hyperparser.parseurl(url)
      print(uparser:schema(), uparser:host(), uparser:port(), uparser:path(), uparser:query(), uparser:fragment(), uparser:userinfo())
    end,
    headerfield = nil, -- 
    headervalue = nil, --
    body = nil, --
    msgcomplete = function()
      shouldRead = false
      state = 'complete'
    end
  }

  while shouldRead do
    local nread, content, errcode = anet.read(cfd)

    if not nread then
      error('Cannot read from the socket: ' .. content)
    elseif nread > 0 then
      local nparsed = request:execute(content)
      if nparsed ~= nread then
        error('Cannot parse the request.')
      end
    else -- EOF
      break
    end
  end

  if state == 'complete' then
    write_response(cfd)
    if not request:shouldkeepalive() then
      anet.close(cfd)
    end
  else
    anet.close(cfd)
  end
end

function loop(fd, config)
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
        clienthandler(config, cfd, ip, port)
      end)
    end
  end
end

return _M
