local M = {}

function M:initially(fnname)
  return  {
    _action = '_initially',
    name = fnname
  }
end

function M:before(fnname)
  return  {
    _action = '_before',
    name = fnname
  }
end

function M:after(fnname)
  return  {
    _action = '_after',
    name = fnname
  }
end

function M:finally(fnname)
  return  {
    _action = '_finally',
    name = fnname
  }
end

return M
