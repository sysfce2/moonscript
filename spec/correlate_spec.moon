
import unindent, with_dev from require "spec.helpers"
import split from require "moonscript.util"

lua_load = loadstring or load

describe "correlate compile", ->
  local to_lua

  with_dev ->
    to_lua = require("moonscript.base").to_lua

  compile = (code) ->
    lua_code, posmap = assert to_lua code, correlate: true
    assert lua_load(lua_code), "correlate output is not valid lua"
    lua_code, posmap

  it "places functions on their source lines", ->
    code = unindent [[
      first = ->
        "hello"

      second = (a, b) ->
        a + b

      {first, second}
    ]]

    lua_code = compile code
    fns = assert(lua_load(lua_code))!

    assert.same 1, debug.getinfo(fns[1], "S").linedefined
    assert.same 4, debug.getinfo(fns[2], "S").linedefined

  it "reports runtime error at source line", ->
    code = unindent [[
      fn = ->
        error "boom"

      fn!
    ]]

    lua_code = compile code
    chunk = assert lua_load lua_code, "@correlate_test"
    ok, err = pcall chunk
    assert.same false, ok
    assert.matches "correlate_test:2: boom", err

  it "pads lines to match source", ->
    code = unindent [[
      -- comment
      -- comment
      x = 100
      x
    ]]

    lua_code = compile code
    lines = split lua_code, "\n"
    assert.same "", lines[1]
    assert.same "", lines[2]
    assert.matches "x = 100", lines[3]
    assert.matches "return x", lines[4]

  it "separates ambiguous statements when padding", ->
    code = unindent [[
      x = tostring
      (x or error) "hi"
      1234
    ]]

    lua_code = compile code
    assert.same 1234, assert(lua_load(lua_code))!

  it "compiles class to valid lua on its source line", ->
    code = unindent [[
      class Thing
        new: (@x) =>
        double: => @x * 2

      t = Thing 5
      t\double!
    ]]

    lua_code = compile code
    assert.same 10, assert(lua_load(lua_code))!
    assert.matches "local Thing do", split(lua_code, "\n")[1]

  it "keeps multiline strings intact", ->
    code = unindent [[
      x = [==[
      one
      two
      ]==]
      y = "last"
      {x, y}
    ]]

    lua_code = compile code
    result = assert(lua_load(lua_code))!
    assert.same "one\ntwo\n", result[1]
    assert.matches [[y = "last"]], split(lua_code, "\n")[5]

  it "reports error line inside if expression assign", ->
    code = unindent [[
      x = if true
        error "boom"
    ]]

    lua_code = compile code
    chunk = assert lua_load lua_code, "@correlate_test"
    ok, err = pcall chunk
    assert.same false, ok
    assert.matches "correlate_test:2: boom", err

  it "reports error line inside switch expression assign", ->
    code = unindent [[
      v = 2
      x = switch v
        when 1
          "one"
        else
          error "boom"
    ]]

    lua_code = compile code
    chunk = assert lua_load lua_code, "@correlate_test"
    ok, err = pcall chunk
    assert.same false, ok
    assert.matches "correlate_test:6: boom", err

  it "correlates against the right source when options are reused", ->
    options = correlate: true

    assert to_lua "a = 1", options
    lua_code = assert to_lua "-- comment\n-- comment\nb = 2", options

    assert.same nil, options.source
    assert.matches "b = 2", split(lua_code, "\n")[3]

  it "resolves marked positions to their own line or earlier", ->
    import pos_to_line from require "moonscript.util"

    code = unindent [[
      add = (a, b) ->
        a + b

      class Counter
        new: => @count = 0
        increment: =>
          @count += 1
          @count

      c = Counter!
      for i=1,10
        c\increment!

      print add c.count, 5
    ]]

    _, posmap = compile code
    for lua_line, pos in pairs posmap
      assert pos_to_line(code, pos) <= lua_line,
        "posmap entry for line #{lua_line} resolves past it"
