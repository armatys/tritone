local tritone = require 'tritone'

local server = tritone.HttpServer:new{debug=true}

-- as each function will be serialized,
-- they must not contain any upvalues

server:services {
  echo = function(s)
    return s .. s
  end,
  checklogin = function(matched, url, params, here)
    -- The environment of this function would contain all the requested services
    -- or all requested built-in services?
    if not user then
      --error(response{status=401, body='Not authenticated'})
    end
  end,
  customheader = function()
    response:setheader('X-Server-Name', 'tritone')
  end,
  saveStartTime = function()
    response._starttime = os.time()
  end,
  saybye = function()
    local now = os.time()
    response:addheader('X-Processing-Time-Sec', tostring(now - response._starttime))
  end
}

local on = server:builder()
local std = on.GET + on.POST + 
  { 'headers', 'cookies', 'query', 'form', 'files', 'session', 'echo' } +
  on.before('saveStartTime') + on.before('checklogin') + on.after('customheader') +
  on.finally('saybye')

-- TODO cookie-based session, on.before, on.after

server '"/"' [std] = function()
  local perun = require 'perun'
  perun.sleep(1000)
  response.body = 'This is index.\n'
end

server '"/hello/"{ %w+ }"/"?' 'hello' [std] = function(name)
  -- TODO manipulating response: headers, setting cookie, status code
  response:setheader('Content-Type', 'text/plain')
  response:setcookie{'sid', '238a0e4f'}
  response.body = 'siema ' .. echo(name) .. '?' .. (query.q or '') ..  '!\n'
  response:addflash('This is a flash message.')
  return response
end

local ok, errmsg = server:serve()
print(ok, errmsg)
