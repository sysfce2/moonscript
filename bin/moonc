#!/usr/bin/env lua

local argparse = require "argparse"
local lfs = require "lfs"

local parser = argparse()

parser:flag("-l --lint", "Perform a lint on the file instead of compiling")

-- may be nil when an older moonscript.cmd.lint is loaded from the module path
local all_lint_stages = require("moonscript.cmd.lint").LINT_STAGES
local all_lint_formats = require("moonscript.cmd.lint").LINT_FORMATS

local lint_stage_opt = parser:option("--lint-stage",
  "Limit lint to the given stage name (repeatable)"):count("*")
local exclude_lint_stage_opt = parser:option("--exclude-lint-stage",
  "Lint with all stages except the given stage name (repeatable)"):count("*")
local lint_format_opt = parser:option("--lint-format",
  "Set the output format of lint results")

if all_lint_stages then
  lint_stage_opt:choices(all_lint_stages)
  exclude_lint_stage_opt:choices(all_lint_stages)
end

if all_lint_formats then
  lint_format_opt:choices(all_lint_formats)
end

parser:mutex(lint_stage_opt, exclude_lint_stage_opt)

parser:flag("-v --version", "Print version"):action(function()
  require("moonscript.version").print_version()
  os.exit(0)
end)
parser:flag("-w --watch", "Watch file/directory for updates")
parser:flag("--correlate", "Write output where line numbers match the source line numbers")
parser:option("--transform", "Transform syntax tree with module")

parser:mutex(
  parser:option("-t --output-to", "Specify where to place compiled files"),
  parser:option("-o", "Write output to file"),
  parser:flag("-p", "Write output to standard output"),
  parser:flag("-T", "Write parse tree instead of code (to stdout)"),
  parser:flag("-b", "Write parse and compile time instead of code(to stdout)"),
  parser:flag("-X", "Write line rewrite map instead of code (to stdout)")
)

parser:flag("-",
  "Read from standard in, print to standard out")

local read_stdin = false
for i = #arg, 1, -1 do -- luacheck: ignore 113
  if arg[i] == "-" then
    read_stdin = true
    table.remove(arg, i)
  end
end

if not read_stdin then
  parser:argument("file/directory"):args("+")
end

local opts = parser:parse(arg)

-- options passed to lint_file, stages: nil runs all of them
local lint_opts
do
  local lint_stages
  local included, excluded = opts.lint_stage, opts.exclude_lint_stage
  if included and #included > 0 then
    lint_stages = included
  elseif excluded and #excluded > 0 then
    local skip = {}
    for _, name in ipairs(excluded) do
      skip[name] = true
    end

    lint_stages = {}
    for _, name in ipairs(all_lint_stages or {}) do
      if not skip[name] then
        table.insert(lint_stages, name)
      end
    end
  end

  lint_opts = {
    stages = lint_stages,
    format = opts.lint_format,
  }
end

function log_msg(...)
  if not opts.p then
    io.stderr:write(table.concat({...}, " ") .. "\n")
  end
end

local moonc = require("moonscript.cmd.moonc")
local util = require "moonscript.util"
local normalize_dir = moonc.normalize_dir
local compile_and_write = moonc.compile_and_write
local path_to_target = moonc.path_to_target

local function scan_directory(root, collected)
  root = normalize_dir(root)
  collected = collected or {}

  for fname in lfs.dir(root) do
    if not fname:match("^%.") then
      local full_path = root..fname

      if lfs.attributes(full_path, "mode") == "directory" then
        scan_directory(full_path, collected)
      elseif fname:match("%.moon$") then
        table.insert(collected, full_path)
      end
    end
  end

  return collected
end

local function remove_dups(tbl, key_fn)
  local hash = {}
  local final = {}

  for _, v in ipairs(tbl) do
    local dup_key = key_fn and key_fn(v) or v
    if not hash[dup_key] then
      table.insert(final, v)
      hash[dup_key] = true
    end
  end

  return final
end

-- creates tuples of input and target
local function get_files(fname, files)
  files = files or {}

  if lfs.attributes(fname, "mode") == "directory" then
    for _, sub_fname in ipairs(scan_directory(fname)) do
      table.insert(files, {
        sub_fname,
        path_to_target(sub_fname, opts.output_to, fname)
      })
    end
  else
    table.insert(files, {
      fname,
      path_to_target(fname, opts.output_to)
    })
  end

  return files
end

if read_stdin then
  if opts.watch or opts.output_to then
    io.stderr:write("stdin can't be used with --watch or --output-to\n")
    os.exit(1)
  end

  local text = io.stdin:read("*a")

  if opts.lint then
    local lint = require "moonscript.cmd.lint"
    local res, err = lint.lint_code(text, "stdin", nil, lint_opts)
    if res then
      io.stderr:write(res .. "\n")
      os.exit(1)
    elseif err then
      io.stderr:write(err .. "\n")
      os.exit(1)
    end
    os.exit()
  end

  local code, err = moonc.compile_file_text(text, {
    fname = "stdin",
    benchmark = opts.b,
    show_posmap = opts.X,
    show_parse_tree = opts.T,
    transform_module = opts.transform,
    correlate = opts.correlate
  })

  if not code then
    io.stderr:write(err .. "\n")
    os.exit(1)
  end

  -- true means an option like -T already handled the output
  if code ~= true then
    if opts.o then
      local success, write_err = moonc.write_file(opts.o, code)
      if not success then
        io.stderr:write(write_err .. "\n")
        os.exit(1)
      end
    else
      print(code)
    end
  end

  os.exit()
end

local inputs = opts["file/directory"]

local files = {}
for _, input in ipairs(inputs) do
  get_files(input, files)
end

files = remove_dups(files, function(f)
  return f[2]
end)

-- returns an iterator that returns files that have been updated
local function create_watcher(files)
  local watchers = require("moonscript.cmd.watchers")

  if watchers.InotifyWacher:available() then
    return watchers.InotifyWacher(files):each_update()
  end

  return watchers.SleepWatcher(files):each_update()
end

if opts.watch then
  -- build function to check for lint or compile in watch
  local handle_file
  if opts.lint then
    local lint = require "moonscript.cmd.lint"
    handle_file = function(fname)
      return lint.lint_file(fname, lint_opts)
    end
  else
    handle_file = function(fname, target)
      return compile_and_write(fname, target, {
        correlate = opts.correlate
      })
    end
  end

  local watcher = create_watcher(files)
  -- catches interrupt error for ctl-c
  local protected = function()
    local status, file = true, watcher()
    if status then
      return file
    elseif file ~= "interrupted!" then
      error(file)
    end
  end

  for fname in protected do
    local target = path_to_target(fname, opts.t)

    if opts.o then
      target = opts.o
    end

    local success, err = handle_file(fname, target)
    if opts.lint then
      if success then
        io.stderr:write(success .. "\n\n")
      elseif err then
        io.stderr:write(fname .. "\n" .. err .. "\n\n")
      end
    elseif not success then
      io.stderr:write(table.concat({
        "",
        "Error: " .. fname,
        err,
        "\n",
      }, "\n"))
    elseif success == "build" then
      log_msg("Built", fname, "->", target)
    end
  end

  io.stderr:write("\nQuitting...\n")
elseif opts.lint then
  local has_linted_with_error;
  local lint = require "moonscript.cmd.lint"
  for _, tuple in pairs(files) do
    local fname = tuple[1]
    local res, err = lint.lint_file(fname, lint_opts)
    if res then
      has_linted_with_error = true
      -- compact format lines identify their file, no separator needed
      local sep = opts.lint_format == "compact" and "\n" or "\n\n"
      io.stderr:write(res .. sep)
    elseif err then
      has_linted_with_error = true
      io.stderr:write(fname .. "\n" .. err.. "\n\n")
    end
  end
  if has_linted_with_error then
    os.exit(1)
  end
else
  for _, tuple in ipairs(files) do
    local fname, target = util.unpack(tuple)
    if opts.o then
      target = opts.o
    end

    local success, err = compile_and_write(fname, target, {
      print = opts.p,
      fname = fname,
      benchmark = opts.b,
      show_posmap = opts.X,
      show_parse_tree = opts.T,
      transform_module = opts.transform,
      correlate = opts.correlate
    })

    if not success then
      io.stderr:write(fname .. "\t" .. err .. "\n")
      os.exit(1)
    end
  end
end


