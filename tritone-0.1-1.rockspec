package = "Tritone"
version = "0.1-1"

source = {
  url = "http://"
}

description = {
  summary = "Web framework",
  detailed = [[
    Simple Lua web framework
  ]],
  homepage = "http://armatys.github.com/tritone",
  license = "MIT/X11"
}

dependencies = {
  "lua >= 5.1",
  "anet >= 1.0",
  "bencode >= 2.0.1",
  --"getopt >= 0.1",
  "hyperparser >= 1.0",
  "pbkdf2 >= 0.1",
  "perun >= 0.1"
}

supported_platforms = { "macosx", "freebsd", "linux" }

build = {
  type = "builtin",

  modules = {
    tritone = "lua/tritone/init.lua",
    ["tritone.http"] = "lua/tritone/http/init.lua",
    ["tritone.http.Action"] = "lua/tritone/http/action/init.lua",
    ["tritone.http.Cookie"] = "lua/tritone/http/cookie/init.lua",
    ["tritone.http.Method"] = "lua/tritone/http/method/init.lua",
    ["tritone.http.Response"] = "lua/tritone/http/response/init.lua"
  }
}
