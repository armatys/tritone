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
  "getopt >= 0.1",
  "perun >= 0.1",
  "pbkdf2 >= 0.1"
}

supported_platforms = { "macosx", "freebsd", "linux" }

build = {
  type = "builtin",

  modules = {
    tritone = "lua/tritone/init.lua",
  }
}
