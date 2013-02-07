local tritone = require 'tritone'

local server = tritone.HttpServer:new{debug=true}
local on = server:builder()

-- as each function will be serialized,
-- they must not contain any upvalues

server:services {
  echo = function(s)
    return s .. s
  end
}

local std = on.GET + on.POST + { 'headers', 'cookies', 'query', 'form', 'files', 'session' }

-- TODO cookie-based session

on [std + { 'echo' } + '"/hello/"{ %w+ }"/"?' - 'index'] = function(name)
  -- TODO manipulating response: headers, setting cookie, status code
  response:setheader('Content-Type', 'text/plain')
  response:setcookie{'sid', '238a0e4f'}
  response.body = 'siema ' .. echo(name) .. '?' .. (query.q or '') ..  '!\n'
  return response
end

local ok, errmsg = server:serve()
print(ok, errmsg)
