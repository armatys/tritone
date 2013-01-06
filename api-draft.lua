local tritone = require 'tritone'

local server = tritone.HttpServer:new()

-- as each function will be serialized,
-- they must not contain any upvalues
local function hello(headers, body, cookies, files, request, templates, db)
  -- request: http version, path, query params, '#' part
end

local hello = tritone.handler{'body', 'cookies', 'db', 'request'}(function(name)
  -- now all the requested services are in function's environment
end)

local ello = tritone.Handler:new(function(name)
  -- body
end, cookies, request) -- could those values be recognized based on tritone.handler env?

-- the functions for each service should return an object
-- that would be used in each lua state
-- each factory function sh;ud be able to accept arguments?
server:services {
  db = function()
    local db = require 'db'
    return db:new('127.0.0.1', 3737)
  end,
  templates = function()
    local templates = require 'templates'
    local o = templates:new('./templates')
    return o
  end
}

server:urls {
  { '/hello/{:name %w+ :}', hello }
}

server:serve('localhost', 8080)
