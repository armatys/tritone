local tritone = require 'tritone'

local server = tritone.HttpServer:new()

-- as each function will be serialized,
-- they must not contain any upvalues
local function hello(headers, body, cookies, files, request, templates, db)
  -- request: http version, path, query params, '#' part
end

server:urls {
  { '/', hello }
}

local ok, errmsg = server:serve()
print(ok, errmsg)