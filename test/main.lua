local tritone = require 'tritone'
local Action = require 'tritone.http.Action'
local Method = require 'tritone.http.Method'

local server = tritone.HttpServer:new {
  cookiesecret = 'm213kr98dsj9493wd',
  debug = true
}

-- as each function will be serialized,
-- they must not contain any upvalues

server:services {
  echo = function()
    return function(s)
      return s .. s
    end
  end,
  checklogin = function()
    return function()
      -- The environment of this function would contain all the requested services
      -- or all requested built-in services?
      if not user then
        --error(response{status=401, body='Not authenticated'})
        --response{status=401, body='Not authenticated'}:abort()
        --response:panic(401)
      end
    end
  end,
  customheader = function()
    return function()
      response:setheader('X-Server-Name', 'tritone')
    end
  end,
  saveStartTime = function()
    return function()
      response.userdata._starttime = os.time()
    end
  end,
  saybye = function()
    return function()
      local now = os.time()
      response:addheader('X-Processing-Time-Sec', tostring(now - response.userdata._starttime))
    end
  end
}

local std = server:builder() + Method.GET + Method.POST + 
  { 'request', 'headers', 'cookies', 'query', 'form', 'formdata', 'session', 'echo' } +
  Action.initially('saveStartTime') + Action.before('checklogin') +
  Action.after('customheader') + Action.finally('saybye')

server '"/"' [std] = function()
  local perun = require 'perun'
  perun.sleep(1000)
  response:redirect('/hello/mate')
  print('Will not be printed out.')
end

server '"/hello/"{ %w+ }"/"?' 'hello' [std] = function(name)
  response:setheader('Content-Type', 'text/plain')
  response:setcookie{'sid', '238a0e4f'}
  response:setcookie{'user', 'mako', signed=true, maxage=60*60}
  response:addflash('This is a flash message.')
  response:ok('siema ' .. echo(name) .. '?' .. (query.q or '') ..  '!\n')
end

local ok, errmsg = server:serve()
print(ok, errmsg)
