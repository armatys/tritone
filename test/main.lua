local tritone = require 'tritone'
local Method = require 'tritone.http.Method'
local Action = require 'tritone.http.Action'

local server = tritone.HttpServer:new{debug=true}

-- as each function will be serialized,
-- they must not contain any upvalues

server:services {
  echo = function(s)
    return s .. s
  end,
  checklogin = function()
    -- The environment of this function would contain all the requested services
    -- or all requested built-in services?
    if not user then
      --error(response{status=401, body='Not authenticated'})
      --response{status=401, body='Not authenticated'}:abort()
      response:panic(401)
    end
  end,
  customheader = function()
    response:setheader('X-Server-Name', 'tritone')
  end,
  saveStartTime = function()
    response.userdata._starttime = os.time()
  end,
  saybye = function()
    local now = os.time()
    response:addheader('X-Processing-Time-Sec', tostring(now - response.userdata._starttime))
  end
}

local std = server:builder() + Method.GET + Method.POST + 
  { 'request', 'headers', 'cookies', 'query', 'form', 'files', 'session', 'echo' } +
  Action.initially('saveStartTime') + Action.before('checklogin') +
  Action.after('customheader') + Action.finally('saybye')

-- TODO cookie-based session service

server '"/"' [std] = function()
  print 'index'
  local perun = require 'perun'
  perun.sleep(1000)
  response:redirect('/hello/mate')
  print('Will not be printed out.')
end

server '"/hello/"{ %w+ }"/"?' 'hello' [std] = function(name)
  response:setheader('Content-Type', 'text/plain')
  response:setcookie{'sid', '238a0e4f'}
  response:addflash('This is a flash message.')
  response:render('siema ' .. echo(name) .. '?' .. (query.q or '') ..  '!\n')
end

local ok, errmsg = server:serve()
print(ok, errmsg)
