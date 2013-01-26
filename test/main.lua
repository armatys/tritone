local tritone = require 'tritone'

local server = tritone.HttpServer:new{debug=true}
local on = server:builder()

-- as each function will be serialized,
-- they must not contain any upvalues

local std = on.GET + on.POST + { 'headers', 'login', 'templates', 'db' }

on [std + '"/hello/"{ %w+ }"/"?' - 'index'] = function(name)
  -- body
end

server:services {
  echo = function(s)
    return s .. s
  end
}

local ok, errmsg = server:serve()
print(ok, errmsg)
