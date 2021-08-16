
--- Unix implementation of filesystem and platform abstractions.
local unix = {}

local fs = require("rocks.fs")

local dir = require("rocks.dir")
local path = require("luarocks.path")
local util = require("luarocks.util")
local posix = require("posix")
local lfs = require("lfs")

--- Annotate command string for quiet execution.
-- @param cmd string: A command-line string.
-- @return string: The command-line, with silencing annotation.
function unix.quiet(cmd)
   return cmd.." 1> /dev/null 2> /dev/null"
end

--- Annotate command string for execution with quiet stderr.
-- @param cmd string: A command-line string.
-- @return string: The command-line, with stderr silencing annotation.
function unix.quiet_stderr(cmd)
   return cmd.." 2> /dev/null"
end

--- Quote argument for shell processing.
-- Adds single quotes and escapes.
-- @param arg string: Unquoted argument.
-- @return string: Quoted argument.
function unix.Q(arg)
   assert(type(arg) == "string")
   return "'" .. arg:gsub("'", "'\\''") .. "'"
end

--- Return an absolute pathname from a potentially relative one.
-- @param pathname string: pathname to convert.
-- @param relative_to string or nil: path to prepend when making
-- pathname absolute, or the current dir in the dir stack if
-- not given.
-- @return string: The pathname converted to absolute.
function unix.absolute_name(pathname, relative_to)
   assert(type(pathname) == "string")
   assert(type(relative_to) == "string" or not relative_to)

   local unquoted = pathname:match("^['\"](.*)['\"]$")
   if unquoted then
      pathname = unquoted
   end

   relative_to = (relative_to or fs.current_dir()):gsub("/*$", "")
   if pathname:sub(1,1) == "/" then
      return pathname
   else
      return relative_to .. "/" .. pathname
   end
end

--- Return the root directory for the given path.
-- In Unix, root is always "/".
-- @param pathname string: pathname to use.
-- @return string: The root of the given pathname.
function unix.root_of(_)
   return "/"
end

--- Check if a file (typically inside path.bin_dir) is an actual binary
-- or a Lua wrapper.
-- @param filename string: the file name with full path.
-- @return boolean: returns true if file is an actual binary
-- (or if it couldn't check) or false if it is a Lua wrapper.
function unix.is_actual_binary(filename)
   if filename:match("%.lua$") then
      return false
   end
   local file = io.open(filename)
   if not file then
      return true
   end
   local first = file:read(2)
   file:close()
   if not first then
      util.warning("could not read "..filename)
      return true
   end
   return first ~= "#!"
end

function unix.copy_binary(filename, dest)
   return fs.copy(filename, dest, "exec")
end

--- Move a file on top of the other.
-- The new file ceases to exist under its original name,
-- and takes over the name of the old file.
-- On Unix this is done through a single rename operation.
-- @param old_file The name of the original file,
-- which will be the new name of new_file.
-- @param new_file The name of the new file,
-- which will replace old_file.
-- @return boolean or (nil, string): True if succeeded, or nil and
-- an error message.
function unix.replace_file(old_file, new_file)
   return os.rename(new_file, old_file)
end

function unix.tmpname()
   return os.tmpname()
end

function unix.is_superuser()
   return os.getenv("USER") == "root"
end

function unix.export_cmd(var, val)
   return ("export %s='%s'"):format(var, val)
end

local octal_to_rwx = {
   ["0"] = "---",
   ["1"] = "--x",
   ["2"] = "-w-",
   ["3"] = "-wx",
   ["4"] = "r--",
   ["5"] = "r-x",
   ["6"] = "rw-",
   ["7"] = "rwx",
}
local rwx_to_octal = {}
for octal, rwx in pairs(octal_to_rwx) do
   rwx_to_octal[rwx] = octal
end
--- Moderate the given permissions based on the local umask
-- @param perms string: permissions to moderate
-- @return string: the moderated permissions
function unix._unix_moderate_permissions(perms)
   local umask = fs._unix_umask()

   local moderated_perms = ""
   for i = 1, 3 do
      local p_rwx = octal_to_rwx[perms:sub(i, i)]
      local u_rwx = octal_to_rwx[umask:sub(i, i)]
      local new_perm = ""
      for j = 1, 3 do
         local p_val = p_rwx:sub(j, j)
         local u_val = u_rwx:sub(j, j)
         if p_val == u_val then
            new_perm = new_perm .. "-"
         else
            new_perm = new_perm .. p_val
         end
      end
      moderated_perms = moderated_perms .. rwx_to_octal[new_perm]
   end
   return moderated_perms
end

function unix.system_cache_dir()
   if fs.is_dir("/var/cache") then
      return "/var/cache"
   end
   return dir.path(fs.system_temp_dir(), "cache")
end

---------------------------------------------------------------------
-- POSIX functions
---------------------------------------------------------------------

function unix._unix_rwx_to_number(rwx, neg)
   local num = 0
   neg = neg or false
   for i = 1, 9 do
      local c = rwx:sub(10 - i, 10 - i) == "-"
      if neg == c then
         num = num + 2^(i-1)
      end
   end
   return math.floor(num)
end


local octal_to_rwx = {
   ["0"] = "---",
   ["1"] = "--x",
   ["2"] = "-w-",
   ["3"] = "-wx",
   ["4"] = "r--",
   ["5"] = "r-x",
   ["6"] = "rw-",
   ["7"] = "rwx",
}

do
   local umask_cache
   function unix._unix_umask()
      if umask_cache then
         return umask_cache
      end
      -- LuaPosix (as of 34.0.4) only returns the umask as rwx
      local rwx = posix.umask()
      local num = unix._unix_rwx_to_number(rwx, true)
      umask_cache = ("%03o"):format(num)
      return umask_cache
   end
end

function unix.set_permissions(filename, mode, scope)
   local perms
   if mode == "read" and scope == "user" then
      perms = fs._unix_moderate_permissions("600")
   elseif mode == "exec" and scope == "user" then
      perms = fs._unix_moderate_permissions("700")
   elseif mode == "read" and scope == "all" then
      perms = fs._unix_moderate_permissions("644")
   elseif mode == "exec" and scope == "all" then
      perms = fs._unix_moderate_permissions("755")
   else
      return false, "Invalid permission " .. mode .. " for " .. scope
   end

   -- LuaPosix (as of 5.1.15) does not support octal notation...
   local new_perms = {}
   for c in perms:sub(-3):gmatch(".") do
      table.insert(new_perms, octal_to_rwx[c])
   end
   perms = table.concat(new_perms)
   local err = posix.chmod(filename, perms)
   return err == 0
end

function unix.current_user()
   return posix.getpwuid(posix.geteuid()).pw_name
end

-- This call is not available on all systems, see #677
if posix.mkdtemp then

   --- Create a temporary directory.
   -- @param name_pattern string: name pattern to use for avoiding conflicts
   -- when creating temporary directory.
   -- @return string or (nil, string): name of temporary directory or (nil, error message) on failure.
   function unix.make_temp_dir(name_pattern)
      assert(type(name_pattern) == "string")
      name_pattern = dir.normalize(name_pattern)
   
      return posix.mkdtemp(fs.system_temp_dir() .. "/luarocks_" .. name_pattern:gsub("/", "_") .. "-XXXXXX")
   end
   
end -- if posix.mkdtemp

function unix.are_the_same_file(f1, f2)
   if f1 == f2 then
      return true
   end
   
   local i1 = lfs.attributes(f1, "ino")
   local i2 = lfs.attributes(f2, "ino")
   if i1 ~= nil and i1 == i2 then
      return true
   end
   
   return false
end

function unix.copy_permissions(src, dest, perms)
   local fullattrs
   if not perms then
      fullattrs = lfs.attributes(src, "permissions")
   end
   if fullattrs then
      return posix.chmod(dest, fullattrs)
   else
      if not perms then
         perms = fullattrs:match("x") and "exec" or "read"
      end
      return fs.set_permissions(dest, perms, "all")
   end
end
return unix
