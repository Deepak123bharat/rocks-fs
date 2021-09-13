
--- Native Lua implementation of filesystem and platform abstractions,
-- using LuaFileSystem, LuaSocket, LuaSec, lua-zlib, MD5.
-- module("luarocks.fs.lua")
local fs_lua = {}

local fs = require("rocks.fs")

local dir = require("rocks.dir")

local pack = table.pack or function(...) return { n = select("#", ...), ... } end

local http = require("socket.http")
local ftp = require("socket.ftp")
local lfs = require("lfs")
local md5 = require("md5")

local dir_stack = {}


local function starts_with(s, prefix)
   return s:sub(1,#prefix) == prefix
end

--- Test is file/dir is writable.
-- Warning: testing if a file/dir is writable does not guarantee
-- that it will remain writable and therefore it is no replacement
-- for checking the result of subsequent operations.
-- @param file string: filename to test
-- @return boolean: true if file exists, false otherwise.
function fs_lua.is_writable(file)
   assert(file)
   file = dir.normalize(file)
   local result
   if fs.is_dir(file) then
      local file2 = dir.path(file, '.tmpluarockstestwritable')
      local fh = io.open(file2, 'wb')
      result = fh ~= nil
      if fh then fh:close() end
      os.remove(file2)
   else
      local fh = io.open(file, 'r+b')
      result = fh ~= nil
      if fh then fh:close() end
   end
   return result
end

local function quote_args(command, ...)
   local out = { command }
   local args = pack(...)
   for i=1, args.n do
      local arg = args[i]
      assert(type(arg) == "string")
      out[#out+1] = fs.Q(arg)
   end
   return table.concat(out, " ")
end

--- Run the given command, quoting its arguments.
-- The command is executed in the current directory in the dir stack.
-- @param command string: The command to be executed. No quoting/escaping
-- is applied.
-- @param ... Strings containing additional arguments, which are quoted.
-- @return boolean: true if command succeeds (status code 0), false
-- otherwise.
function fs_lua.execute(command, ...)
   assert(type(command) == "string")
   return fs.execute_string(quote_args(command, ...))
end

--- Run the given command, quoting its arguments, silencing its output.
-- The command is executed in the current directory in the dir stack.
-- Silencing is omitted if 'verbose' mode is enabled.
-- @param command string: The command to be executed. No quoting/escaping
-- is applied.
-- @param ... Strings containing additional arguments, which will be quoted.
-- @return boolean: true if command succeeds (status code 0), false
-- otherwise.
function fs_lua.execute_quiet(command, ...)
   assert(type(command) == "string")
   if fs.fs_is_verbose then -- omit silencing output
      return fs.execute_string(quote_args(command, ...))
   else
      return fs.execute_string(fs.quiet(quote_args(command, ...)))
   end
end

function fs.execute_env(env, command, ...)
   assert(type(command) == "string")
   local envstr = {}
   for var, val in pairs(env) do
      table.insert(envstr, fs.export_cmd(var, val))
   end
   return fs.execute_string(table.concat(envstr, "\n") .. "\n" .. quote_args(command, ...))
end

local tool_available_cache = {}

function fs_lua.set_tool_available(tool_name, value)
   assert(type(value) == "boolean")
   tool_available_cache[tool_name] = value
end

--- Checks if the given tool is available.
-- The tool is executed using a flag, usually just to ask its version.
-- @param tool_cmd string: The command to be used to check the tool's presence (e.g. hg in case of Mercurial)
-- @param tool_name string: The actual name of the tool (e.g. Mercurial)
-- @param arg string: The flag to pass to the tool. '--version' by default.
function fs_lua.is_tool_available(tool_cmd, tool_name, arg)
   assert(type(tool_cmd) == "string")
   assert(type(tool_name) == "string")

   arg = arg or "--version"
   assert(type(arg) == "string")

   local ok
   if tool_available_cache[tool_name] ~= nil then
      ok = tool_available_cache[tool_name]
   else
      ok = fs.execute_quiet(tool_cmd, arg)
      tool_available_cache[tool_name] = (ok == true)
   end

   if ok then
      return true
   end
end

--- Check the MD5 checksum for a file.
-- @param file string: The file to be checked.
-- @param md5sum string: The string with the expected MD5 checksum.
-- @return boolean: true if the MD5 checksum for 'file' equals 'md5sum', false + msg if not
-- or if it could not perform the check for any reason.
function fs_lua.check_md5(file, md5sum)
   file = dir.normalize(file)
   local computed, msg = fs.get_md5(file)
   if not computed then
      return false, msg
   end
   if computed:match("^"..md5sum) then
      return true
   else
      return false, "Mismatch MD5 hash for file "..file
   end
end

--- List the contents of a directory.
-- @param at string or nil: directory to list (will be the current
-- directory if none is given).
-- @return table: an array of strings with the filenames representing
-- the contents of a directory.
function fs_lua.list_dir(at)
   local result = {}
   for file in fs.dir(at) do
      result[#result+1] = file
   end
   return result
end

--- Iterate over the contents of a directory.
-- @param at string or nil: directory to list (will be the current
-- directory if none is given).
-- @return function: an iterator function suitable for use with
-- the for statement.
function fs_lua.dir(at)
   if not at then
      at = fs.current_dir()
   end
   at = dir.normalize(at)
   if not fs.is_dir(at) then
      return function() end
   end
   return coroutine.wrap(function() fs.dir_iterator(at) end)
end

--- List the Lua modules at a specific require path.
-- eg. `modules("luarocks.cmd")` would return a list of all LuaRocks command
-- modules, in the current Lua path.
function fs_lua.modules(at)
   at = at or ""
   if #at > 0 then
      -- turn require path into file path
      at = at:gsub("%.", package.config:sub(1,1)) .. package.config:sub(1,1)
   end

   local path = package.path:sub(-1, -1) == ";" and package.path or package.path .. ";"
   local paths = {}
   for location in path:gmatch("(.-);") do
      if location:lower() == "?.lua" then
         location = "./?.lua"
      end
      local _, q_count = location:gsub("%?", "") -- only use the ones with a single '?'
      if location:match("%?%.[lL][uU][aA]$") and q_count == 1 then  -- only use when ending with "?.lua"
         location = location:gsub("%?%.[lL][uU][aA]$", at)
         table.insert(paths, location)
      end
   end

   if #paths == 0 then
      return {}
   end

   local modules = {}
   local is_duplicate = {}
   for _, path in ipairs(paths) do  -- luacheck: ignore 421
      local files = fs.list_dir(path)
      for _, filename in ipairs(files or {}) do
         if filename:match("%.[lL][uU][aA]$") then
           filename = filename:sub(1,-5) -- drop the extension
           if not is_duplicate[filename] then
              is_duplicate[filename] = true
              table.insert(modules, filename)
           end
         end
      end
   end

   return modules
end

function fs_lua.filter_file(fn, input_filename, output_filename)
   local fd, err = io.open(input_filename, "rb")
   if not fd then
      return nil, err
   end

   local input, err = fd:read("*a")
   fd:close()
   if not input then
      return nil, err
   end

   local output, err = fn(input)
   if not output then
      return nil, err
   end

   fd, err = io.open(output_filename, "wb")
   if not fd then
      return nil, err
   end

   local ok, err = fd:write(output)
   fd:close()
   if not ok then
      return nil, err
   end

   return true
end

function fs_lua.system_temp_dir()
   return os.getenv("TMPDIR") or os.getenv("TEMP") or "/tmp"
end

---------------------------------------------------------------------
-- LuaFileSystem functions
---------------------------------------------------------------------

--- Run the given command.
-- The command is executed in the current directory in the dir stack.
-- @param cmd string: No quoting/escaping is applied to the command.
-- @return boolean: true if command succeeds (status code 0), false
-- otherwise.
function fs_lua.execute_string(cmd)
   local code = os.execute(cmd)
   return (code == 0 or code == true)
end

--- Obtain current directory.
-- Uses the module's internal dir stack.
-- @return string: the absolute pathname of the current directory.
function fs_lua.current_dir()
   return lfs.currentdir()
end

--- Change the current directory.
-- Uses the module's internal dir stack. This does not have exact
-- semantics of chdir, as it does not handle errors the same way,
-- but works well for our purposes for now.
-- @param d string: The directory to switch to.
function fs_lua.change_dir(d)
   table.insert(dir_stack, lfs.currentdir())
   d = dir.normalize(d)
   return lfs.chdir(d)
end

--- Change directory to root.
-- Allows leaving a directory (e.g. for deleting it) in
-- a crossplatform way.
function fs_lua.change_dir_to_root()
   local current = lfs.currentdir()
   if not current or current == "" then
      return false
   end
   table.insert(dir_stack, current)
   lfs.chdir("/") -- works on Windows too
   return true
end

--- Change working directory to the previous in the dir stack.
-- @return true if a pop occurred, false if the stack was empty.
function fs_lua.pop_dir()
   local d = table.remove(dir_stack)
   if d then
      lfs.chdir(d)
      return true
   else
      return false
   end
end

--- Create a directory if it does not already exist.
-- If any of the higher levels in the path name do not exist
-- too, they are created as well.
-- @param directory string: pathname of directory to create.
-- @return boolean or (boolean, string): true on success or (false, error message) on failure.
function fs_lua.make_dir(directory)
   assert(type(directory) == "string")
   directory = dir.normalize(directory)
   local path = nil
   if directory:sub(2, 2) == ":" then
     path = directory:sub(1, 2)
     directory = directory:sub(4)
   else
     if directory:match("^/") then
        path = ""
     end
   end
   for d in directory:gmatch("([^/]+)/*") do
      path = path and path .. "/" .. d or d
      local mode = lfs.attributes(path, "mode")
      if not mode then
         local ok, err = lfs.mkdir(path)
         if not ok then
            return false, err
         end
         ok, err = fs.set_permissions(path, "exec", "all")
         if not ok then
            return false, err
         end
      elseif mode ~= "directory" then
         return false, path.." is not a directory"
      end
   end
   return true
end

--- Remove directory recursively
-- @param path string: directory path to delete
function fs_lua.remove_dir(path)
   local attr, err = lfs.attributes(path, "mode")
   if attr ~= "directory" then
      return nil, err
   end

   for file in lfs.dir(path) do
      if file ~= "." and file ~= ".." then
         local full_path = path..'/'..file

         if lfs.attributes(full_path, "mode") == "directory" then
            fs_lua.remove_dir(full_path)
         else
            os.remove(full_path)
         end
      end
   end

   return lfs.rmdir(path)
end

--- Remove a directory if it is empty.
-- Does not return errors (for example, if directory is not empty or
-- if already does not exist)
-- @param d string: pathname of directory to remove.
function fs_lua.remove_dir_if_empty(d)
   assert(d)
   d = dir.normalize(d)
   lfs.rmdir(d)
end

--- Remove a directory if it is empty.
-- Does not return errors (for example, if directory is not empty or
-- if already does not exist)
-- @param d string: pathname of directory to remove.
function fs_lua.remove_dir_tree_if_empty(d)
   assert(d)
   d = dir.normalize(d)
   for i=1,10 do
      lfs.rmdir(d)
      d = dir.dir_name(d)
   end
end

function fs_lua.are_the_same_file(f1, f2)
   if f1 == f2 then
      return true
   end
   
   return false
end

function fs_lua.copy_permissions(src, dest, perms)
   if perms then
      return fs.set_permissions(dest, perms, "all")
   else
      return true
   end
end

--- Copy a file.
-- @param src string: Pathname of source
-- @param dest string: Pathname of destination
-- @param perms string ("read" or "exec") or nil: Permissions for destination
-- file or nil to use the source file permissions
-- @return boolean or (boolean, string): true on success, false on failure,
-- plus an error message.
function fs_lua.copy(src, dest, perms)
   assert(src and dest)
   src = dir.normalize(src)
   dest = dir.normalize(dest)
   local destmode = lfs.attributes(dest, "mode")
   if destmode == "directory" then
      dest = dir.path(dest, dir.base_name(src))
   end
   if fs.are_the_same_file(src, dest) then
      return nil, "The source and destination are the same files"
   end
   local src_h, err = io.open(src, "rb")
   if not src_h then return nil, err end
   local dest_h, err = io.open(dest, "w+b")
   if not dest_h then src_h:close() return nil, err end
   while true do
      local block = src_h:read(8192)
      if not block then break end
      dest_h:write(block)
   end
   src_h:close()
   dest_h:close()
   return fs.copy_permissions(src, dest, perms)
end

--- Implementation function for recursive copy of directory contents.
-- Assumes paths are normalized.
-- @param src string: Pathname of source
-- @param dest string: Pathname of destination
-- @param perms string ("read" or "exec") or nil: Optional permissions.
-- If not given, permissions of the source are copied over to the destination.
-- @return boolean or (boolean, string): true on success, false on failure
local function recursive_copy(src, dest, perms)
   local srcmode = lfs.attributes(src, "mode")

   if srcmode == "file" then
      local ok = fs.copy(src, dest, perms)
      if not ok then return false end
   elseif srcmode == "directory" then
      local subdir = dir.path(dest, dir.base_name(src))
      local ok, err = fs.make_dir(subdir)
      if not ok then return nil, err end
      if pcall(lfs.dir, src) == false then
         return false
      end
      for file in lfs.dir(src) do
         if file ~= "." and file ~= ".." then
            local ok = recursive_copy(dir.path(src, file), subdir, perms)
            if not ok then return false end
         end
      end
   end
   return true
end

--- Recursively copy the contents of a directory.
-- @param src string: Pathname of source
-- @param dest string: Pathname of destination
-- @param perms string ("read" or "exec") or nil: Optional permissions.
-- @return boolean or (boolean, string): true on success, false on failure,
-- plus an error message.
function fs_lua.copy_contents(src, dest, perms)
   assert(src and dest)
   src = dir.normalize(src)
   dest = dir.normalize(dest)
   if not fs.is_dir(src) then
      return false, src .. " is not a directory"
   end
   if pcall(lfs.dir, src) == false then
      return false, "Permission denied"
   end
   for file in lfs.dir(src) do
      if file ~= "." and file ~= ".." then
         local ok = recursive_copy(dir.path(src, file), dest, perms)
         if not ok then
            return false, "Failed copying "..src.." to "..dest
         end
      end
   end
   return true
end

--- Copy a directory and its contents to a new directory.
-- @param src string: Pathname of source
-- @param dest string: Pathname of destination
-- @param perms string ("read" or "exec") or nil: Optional permissions.
-- @return boolean or (boolean, string): true on success, false on failure,
-- plus an error message.
function fs_lua.copy_dir(src, dest, perms)
   assert(src and dest)
   src = dir.normalize(src)
   dest = dir.normalize(dest)
   if not fs.is_dir(src) then
      return false, src .. " is not a directory"
   end

   local ok, err = fs.make_dir(dest)
   if not ok then
      return nil, err
   end
   return fs.copy_contents(src, dest, perms)
end

--- Implementation function for recursive removal of directories.
-- Assumes paths are normalized.
-- @param name string: Pathname of file
-- @return boolean or (boolean, string): true on success,
-- or nil and an error message on failure.
local function recursive_delete(name)
   local ok = os.remove(name)
   if ok then return true end
   local pok, ok, err = pcall(function()
      for file in lfs.dir(name) do
         if file ~= "." and file ~= ".." then
            local ok, err = recursive_delete(dir.path(name, file))
            if not ok then return nil, err end
         end
      end
      local ok, err = lfs.rmdir(name)
      return ok, (not ok) and err
   end)
   if pok then
      return ok, err
   else
      return pok, ok
   end
end

--- Delete a file or a directory and all its contents.
-- @param name string: Pathname of source
-- @return nil
function fs_lua.delete(name)
   name = dir.normalize(name)
   recursive_delete(name)
end

--- Internal implementation function for fs.dir.
-- Yields a filename on each iteration.
-- @param at string: directory to list
-- @return nil or (nil and string): an error message on failure
function fs_lua.dir_iterator(at)
   local pok, iter, arg = pcall(lfs.dir, at)
   if not pok then
      return nil, iter
   end
   for file in iter, arg do
      if file ~= "." and file ~= ".." then
         coroutine.yield(file)
      end
   end
end

--- Implementation function for recursive find.
-- Assumes paths are normalized.
-- @param cwd string: Current working directory in recursion.
-- @param prefix string: Auxiliary prefix string to form pathname.
-- @param result table: Array of strings where results are collected.
local function recursive_find(cwd, prefix, result)
   local pok, iter, arg = pcall(lfs.dir, cwd)
   if not pok then
      return nil
   end
   for file in iter, arg do
      if file ~= "." and file ~= ".." then
         local item = prefix .. file
         table.insert(result, item)
         local pathname = dir.path(cwd, file)
         if lfs.attributes(pathname, "mode") == "directory" then
            recursive_find(pathname, item.."/", result)
         end
      end
   end
end

--- Recursively scan the contents of a directory.
-- @param at string or nil: directory to scan (will be the current
-- directory if none is given).
-- @return table: an array of strings with the filenames representing
-- the contents of a directory.
function fs_lua.find(at)
   assert(type(at) == "string" or not at)
   if not at then
      at = fs.current_dir()
   end
   at = dir.normalize(at)
   local result = {}
   recursive_find(at, "", result)
   return result
end

--- Test for existence of a file.
-- @param file string: filename to test
-- @return boolean: true if file exists, false otherwise.
function fs_lua.exists(file)
   assert(file)
   file = dir.normalize(file)
   return type(lfs.attributes(file)) == "table"
end

--- Test is pathname is a directory.
-- @param file string: pathname to test
-- @return boolean: true if it is a directory, false otherwise.
function fs_lua.is_dir(file)
   assert(file)
   file = dir.normalize(file)
   return lfs.attributes(file, "mode") == "directory"
end

--- Test is pathname is a regular file.
-- @param file string: pathname to test
-- @return boolean: true if it is a file, false otherwise.
function fs_lua.is_file(file)
   assert(file)
   file = dir.normalize(file)
   return lfs.attributes(file, "mode") == "file"
end

-- Set access and modification times for a file.
-- @param filename File to set access and modification times for.
-- @param time may be a number containing the format returned
-- by os.time, or a table ready to be processed via os.time; if
-- nil, current time is assumed.
function fs_lua.set_time(file, time)
   assert(time == nil or type(time) == "table" or type(time) == "number")
   file = dir.normalize(file)
   if type(time) == "table" then
      time = os.time(time)
   end
   return lfs.touch(file, time)
end

---------------------------------------------------------------------
-- LuaSocket functions
---------------------------------------------------------------------

local ltn12 = require("ltn12")
local luasec_ok, https = pcall(require, "ssl.https")

local redirect_protocols = {
   http = http,
   https = luasec_ok and https,
}

local function request(url, opts)  -- luacheck: ignore 431
   local result = {}

   local method = opts.method
   local http = opts.http
   local loop_control = opts.loop_control
   
   if fs.fs_is_verbose then
      print(method, url)
   end

   local proxy = os.getenv("http_proxy")
   if type(proxy) ~= "string" then proxy = nil end
   -- LuaSocket's http.request crashes when given URLs missing the scheme part.
   if proxy and not proxy:find("://") then
      proxy = "http://" .. proxy
   end

   if opts.show_downloads then
      io.write(method.." "..url.." ...\n")
   end
   local dots = 0
   if opts.connection_timeout and opts.connection_timeout > 0 then
      http.TIMEOUT = opts.connection_timeout
   end
   local res, status, headers, err = http.request {
      url = url,
      proxy = proxy,
      method = method,
      redirect = false,
      sink = ltn12.sink.table(result),
      step = opts.show_downloads and function(...)
         io.write(".")
         io.flush()
         dots = dots + 1
         if dots == 70 then
            io.write("\n")
            dots = 0
         end
         return ltn12.pump.step(...)
      end,
      headers = {
         ["user-agent"] = opts.user_agent.." via LuaSocket"
      },
   }
   if opts.show_downloads then
      io.write("\n")
   end
   if not res then
      return nil, status
   elseif status == 301 or status == 302 then
      local location = headers.location
      if location then
         local protocol, rest = dir.split_url(location)
         if redirect_protocols[protocol] then
            if not loop_control then
               loop_control = {}
            elseif loop_control[location] then
               return nil, "Redirection loop -- broken URL?"
            end
            loop_control[url] = true
            opts.http = redirect_protocols[protocol]
            opts.loop_control = loop_control
            return request(location, opts)
         else
            return nil, "URL redirected to unsupported protocol - install luasec to get HTTPS support.", "https"
         end
      end
      return nil, err
   elseif status ~= 200 then
      return nil, err
   else
      return result, status, headers, err
   end
end

local function write_timestamp(filename, data)
   local fd = io.open(filename, "w")
   if fd then
      fd:write(data)
      fd:close()
   end
end

local function read_timestamp(filename)
   local fd = io.open(filename, "r")
   if fd then
      local data = fd:read("*a")
      fd:close()
      return data
   end
end

local function fail_with_status(filename, status, headers)
   write_timestamp(filename .. ".unixtime", os.time())
   write_timestamp(filename .. ".status", status)
   return nil, status, headers
end

-- @param url string: URL to fetch.
-- @param filename string: local filename of the file to fetch.
-- @param http table: The library to use (http from LuaSocket or LuaSec)
-- @param cache boolean: Whether to use a `.timestamp` file to check
-- via the HTTP Last-Modified header if the full download is needed.
-- @return (boolean | (nil, string, string?)): True if successful, or
-- nil, error message and optionally HTTPS error in case of errors.
local function http_request(url, opts)  -- luacheck: ignore 431
   local filename = opts.filename
   local http = opts.http
   local cache = opts.cache

   if cache then
      local status = read_timestamp(filename..".status")
      local timestamp = read_timestamp(filename..".timestamp")
      if status or timestamp then
         local unixtime = read_timestamp(filename..".unixtime")
         if tonumber(unixtime) then
            local diff = os.time() - tonumber(unixtime)
            if status then
               if diff < opts.cache_fail_timeout then
                  return nil, status, {}
               end
            else
               if diff < opts.cache_timeout then
                  return true, nil, nil, true
               end
            end
         end
         opts.method = "HEAD"
         opts.http = http
         opts.loop_control = nil
         local result, status, headers, err = request(url, opts)  -- luacheck: ignore 421
         if not result then
            return fail_with_status(filename, status, headers)
         end
         if status == 200 and headers["last-modified"] == timestamp then
            write_timestamp(filename .. ".unixtime", os.time())
            return true, nil, nil, true
         end
      end
   end
   opts.method = "GET"
   opts.http = http
   opts.loop_control = nil
   local result, status, headers, err = request(url, opts)
   if not result then
      if status then
         return fail_with_status(filename, status, headers)
      end
   end
   if cache and headers["last-modified"] then
      write_timestamp(filename .. ".timestamp", headers["last-modified"])
      write_timestamp(filename .. ".unixtime", os.time())
   end
   local file = io.open(filename, "wb")
   if not file then return nil, 0, {} end
   for _, data in ipairs(result) do
      file:write(data)
   end
   file:close()
   return true
end

local function ftp_request(url, filename)
   local content, err = ftp.get(url)
   if not content then
      return false, err
   end
   local file = io.open(filename, "wb")
   if not file then return false, err end
   file:write(content)
   file:close()
   return true
end


--- Download a remote file.
-- @param url string: URL to be fetched.
-- @param filename string or nil: this function attempts to detect the
-- resulting local filename of the remote file as the basename of the URL;
-- if that is not correct (due to a redirection, for example), the local
-- filename can be given explicitly as this second argument.
-- @return (boolean, string, boolean):
-- In case of success:
-- * true
-- * a string with the filename
-- * true if the file was retrieved from local cache
-- In case of failure:
-- * false
-- * error message
function fs_lua.download(url, opts)
   assert(type(opts) == "table")
   assert(type(url) == "string")
   
   local filename = opts.filename
   filename = fs.absolute_name(filename or dir.base_name(url))
   opts.filename = filename

   -- delegate to the configured downloader so we don't have to deal with whitelists
   if os.getenv("no_proxy") then
      return fs.use_downloader(url, opts)
   end

   
   local ok, err, https_err, from_cache
   if starts_with(url, "http:") then
      opts.http = http
      ok, err, https_err, from_cache = http_request(url, opts)
   elseif starts_with(url, "ftp:") then
      ok, err = ftp_request(url, filename)
   elseif starts_with(url, "https:") then
      -- skip LuaSec when proxy is enabled since it is not supported
      if luasec_ok and not os.getenv("https_proxy") then
         local _
         opts.http = https
         ok, err, _, from_cache = http_request(url, opts)
      else
         https_err = true
      end
   else
      err = "Unsupported protocol"
   end
   if https_err then
      local downloader, err = fs.which_tool("downloader")
      if not downloader then
         return nil, err
      end
      return fs.use_downloader(url, opts)
   elseif not ok then
      return nil, err
   end
   return true, filename, from_cache
end

---------------------------------------------------------------------
-- MD5 functions
---------------------------------------------------------------------

-- Support the interface of lmd5 by lhf in addition to md5 by Roberto
-- and the keplerproject.
if not md5.sumhexa and md5.digest then
   md5.sumhexa = function(msg)
      return md5.digest(msg)
   end
end

if md5.sumhexa then

--- Get the MD5 checksum for a file.
-- @param file string: The file to be computed.
-- @return string: The MD5 checksum or nil + error
function fs_lua.get_md5(file)
   file = fs.absolute_name(file)
   local file_handler = io.open(file, "rb")
   if not file_handler then return nil, "Failed to open file for reading: "..file end
   local computed = md5.sumhexa(file_handler:read("*a"))
   file_handler:close()
   if computed then return computed end
   return nil, "Failed to compute MD5 hash for file "..file
end

end

function fs_lua.is_superuser()
   return false
end

---------------------------------------------------------------------
-- Other functions
---------------------------------------------------------------------

if not fs_lua.make_temp_dir then

function fs_lua.make_temp_dir(name_pattern)
   assert(type(name_pattern) == "string")
   name_pattern = dir.normalize(name_pattern)

   local pattern = fs.system_temp_dir() .. "/luarocks_" .. name_pattern:gsub("/", "_") .. "-"

   while true do
      local name = pattern .. tostring(math.random(10000000))
      if lfs.mkdir(name) then
         return name
      end
   end
end

end

--- Move a file.
-- @param src string: Pathname of source
-- @param dest string: Pathname of destination
-- @param perms string ("read" or "exec") or nil: Permissions for destination
-- file or nil to use the source file permissions.
-- @return boolean or (boolean, string): true on success, false on failure,
-- plus an error message.
function fs_lua.move(src, dest, perms)
   assert(src and dest)
   if fs.exists(dest) and not fs.is_dir(dest) then
      return false, "File already exists: "..dest
   end
   local ok, err = fs.copy(src, dest, perms)
   if not ok then
      return false, err
   end
   fs.delete(src)
   if fs.exists(src) then
      return false, "Failed move: could not delete "..src.." after copy."
   end
   return true
end

return fs_lua
