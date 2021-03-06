tritone
=======

Lua web framework

### Imaginary but fabulous features (what I'm aiming for):

- multi-thread performance
- on-the-fly reload and easy configuration
- modular
- templates: precompiled
- testable and tested
- fast url-dispatch
- secure cookie sessions
- dependency injection for handlers
- response streaming
- websockets
- http keep-alive support
- big file uploads (streaming to disk)
- auto-restart on errors
- code reload on demand or automatically (e.g. in dev mode)
- logging
- modes: production, test, development

### Installation

The framework is not finished and the only way to test it is by fetching the source and all its dependencies:

* luagetopt https://bitbucket.org/armatys/luagetopt
* luapbkdf2 https://bitbucket.org/armatys/luapbkdf2
* fundamento https://bitbucket.org/armatys/fundamento
* perun https://bitbucket.org/armatys/perun
* hyperparser https://github.com/armatys/hyperparser
* anet https://github.com/armatys/LuaAnet
* lastly, get the tritone framework:

```sh
git clone git://github.com/armatys/tritone.git
cd tritone
sudo luarocks make
```
