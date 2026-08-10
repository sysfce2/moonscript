import ntype from require "moonscript.types"

class Transformer
  new: (@transformers) =>
    @seen_nodes = setmetatable {}, __mode: "k"

  transform_once: (scope, node, ...) =>
    return node if @seen_nodes[node]
    @seen_nodes[node] = true

    transformer = @transformers[ntype node]
    if transformer
      transformer(scope, node, ...) or node
    else
      node

  transform: (scope, node, ...) =>
    return node if @seen_nodes[node]

    @seen_nodes[node] = true
    while true
      transformer = @transformers[ntype node]
      res = if transformer
        transformer(scope, node, ...) or node
      else
        node

      return node if res == node

      -- carry the source position through the transformation
      if type(res) == "table" and type(node) == "table" and res[-1] == nil
        res[-1] = node[-1]

      node = res

    node

  bind: (scope) =>
    (...) -> @transform scope, ...

  __call: (...) => @transform ...

  can_transform: (node) =>
    @transformers[ntype node] != nil


{ :Transformer }
