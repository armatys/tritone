local M = {}

function M:__index(k)
  return {
    _method = true,
    name = k
  }
end

setmetatable(M, M)

return M