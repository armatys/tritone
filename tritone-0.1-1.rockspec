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
  homepage = "https://github.com/armatys/tritone",
  license = "MIT/X11"
}

dependencies = {
  "lua >= 5.1",
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
