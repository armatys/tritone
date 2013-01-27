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

local std = on.GET + on.POST + { 'headers', 'cookies', 'query' }

on [std + { 'echo' } + '"/hello/"{ %w+ }"/"?' - 'index'] = function(name)
  -- body
  return 'siema ' .. echo(name) .. '?' .. (query.q or '') .. '!\n'
end

local ok, errmsg = server:serve()
print(ok, errmsg)
