local tritone = require 'tritone'

local server = tritone.HttpServer:new()

-- as each function will be serialized,
-- they must not contain any upvalues
local requiredServices = {'headers', 'body', 'cookies', 'files', 'request', 'templates', 'db'}
local hello = tritone.Handler:new(requiredServices, function()
  -- request: http version, path, query params, '#' part
end)

server:services {
  -- echo = function(s)
  --   return s .. s
  -- end
}

server:urls {
  { '"/"', hello, method='GET' },
  { '"/hello"', hello, methods={'GET', 'POST'} }
}

local ok, errmsg = server:serve()
print(ok, errmsg)