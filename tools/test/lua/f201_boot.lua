-- RSF-F201 boot fixture for the TaxMod lifecycle test. The repo prelude's
-- Utils.appendedFunction returns only the new function, which is enough for the
-- F224 contract test but drops every hook but the last one on a method main.lua
-- hooks twice (FSBaseMission.delete). Chain them here, engine-style, before
-- main.lua loads: appended runs old then new, prepended runs new then old.
Utils = Utils or {}
function Utils.appendedFunction(old, new)
  if old == nil then return new end
  return function(...) old(...); return new(...) end
end
function Utils.prependedFunction(old, new)
  if old == nil then return new end
  return function(...) new(...); return old(...) end
end
getfenv = getfenv or function() return _G end
