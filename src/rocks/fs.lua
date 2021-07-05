
--- Proxy module for filesystem and platform abstractions.
-- All code using "fs" code should require "luarocks.fs",
-- and not the various platform-specific implementations.
-- However, see the documentation of the implementation
-- for the API reference.

local pairs = pairs

local fs = {}

local pack = table.pack or function(...) return { n = select("#", ...), ... } end
local unpack = table.unpack or unpack

math.randomseed(os.time())


local fs_is_verbose = false

----------| Start |---------- Defaults fs variables ------------------------------------
local function make_defaults()
   local defaults = {
      variables = {
         MD5SUM = "md5sum",
         OPENSSL = "openssl",
         MD5 = "md5",
         
         WGET = "wget",
         CURL = "curl",
         
         PWD = "pwd",
         LS = "ls",
       
         MKDIR = "mkdir",
         RMDIR = "rmdir",
         CP = "cp",
         RM = "rm",
         FIND = "find",
         
         ZIP = "zip",
         UNZIP = "unzip -n",

         CHMOD = "chmod",
         TOUCH = "touch",

         MKTEMP = "mktemp",
         SEVENZ = "7z",
         ICACLS = "icacls",
         
         WGETNOCERTFLAG = "",
         CURLNOCERTFLAG = "",

         LUA_BINDIR = "/usr/local/bin",
         TEST = "test",
      },
   }

   return defaults;
end
--------- | End | -------- Defaults fs variables End------------------------------------

--------- | Start | ------------ Util functions to add defualts variable to fs ------------------
--- Merges contents of src below those of dst's contents
-- (i.e. if an key from src already exists in dst, do not replace it).
-- @param dst Destination table, which will receive src's contents.
-- @param src Table which provides new contents to dst.
local function deep_merge_under(dst, src)
   for k, v in pairs(src) do
      if type(v) == "table" then
         if dst[k] == nil then
            dst[k] = {}
         end
         if type(dst[k]) == "table" then
            deep_merge_under(dst[k], v)
         end
      elseif dst[k] == nil then
         dst[k] = v
      end
   end
end

local function use_defaults(variables, defaults)

   -- Populate variables with values from their 'defaults' counterparts
   -- if they were not already set by user.
   if not variables then
      variables = {}
   end
   for k,v in pairs(defaults.variables) do
      if not variables[k] then
         variables[k] = v
      end
   end

   deep_merge_under(variables, defaults)

   -- FIXME get rid of this
   if not variables.check_certificates then
      variables.variables.CURLNOCERTFLAG = "-k"
      variables.variables.WGETNOCERTFLAG = "--no-check-certificate"
   end
end
-----------| End |-------- Util functions to add defualts variable to fs ---------------

do
   local old_popen, old_execute

   -- patch io.popen and os.execute to display commands in verbose mode
   function fs.verbose()
      fs_is_verbose = true

      if old_popen or old_execute then return end
      old_popen = io.popen
      -- luacheck: push globals io os
      io.popen = function(one, two)
         if two == nil then
            print("\nio.popen: ", one)
         else
            print("\nio.popen: ", one, "Mode:", two)
         end
         return old_popen(one, two)
      end

      old_execute = os.execute
      os.execute = function(cmd)
         -- redact api keys if present
         print("\nos.execute: ", (cmd:gsub("(/api/[^/]+/)([^/]+)/", function(cap, key) return cap.."<redacted>/" end)) )
         local code = pack(old_execute(cmd))
         print("Results: "..tostring(code.n))
         for i = 1,code.n do
            print("  "..tostring(i).." ("..type(code[i]).."): "..tostring(code[i]))
         end
         return unpack(code, 1, code.n)
      end
      -- luacheck: pop
   end
end


do
   local function load_fns(fs_table, inits)
      for name, fn in pairs(fs_table) do
         if name ~= "init" and not fs[name] then
            fs[name] = function(...)
               if fs_is_verbose then
                  local args = pack(...)
                  for i=1, args.n do
                     local arg = args[i]
                     local pok, v = pcall(string.format, "%q", arg)
                     args[i] = pok and v or tostring(arg)
                  end
                  print("fs." .. name .. "(" .. table.concat(args, ", ") .. ")")
               end
               return fn(...)
            end
         end
      end
      if fs_table.init then
         table.insert(inits, fs_table.init)
      end
   end

   local function load_platform_fns(plats, patt, inits)

      for _, platform in ipairs(plats) do
         local ok, fs_plat = pcall(require, patt:format(platform))
         if ok and fs_plat then
            load_fns(fs_plat, inits)
         end
      end
   end

   function fs.init(plats, variables)
      local inits = {}

      local defaults = make_defaults()
      use_defaults(variables, defaults)

      if fs.current_dir then
         -- unload luarocks fs so it can be reloaded using all modules
         -- providing extra functionality in the current package paths
         for k, _ in pairs(fs) do
            if k ~= "init" and k ~= "verbose" then
               fs[k] = nil
            end
         end
         for m, _ in pairs(package.loaded) do
            if m:match("luarocks%.fs%.") then
               package.loaded[m] = nil
            end
         end
      end

      -- Load platform-specific functions
      load_platform_fns(plats, "rocks.fs.%s", inits)

      -- Load platform-independent pure-Lua functionality
      load_fns(require("rocks.fs.native"), inits)

      -- Load platform-specific fallbacks for missing Lua modules
      load_platform_fns(plats, "rocks.fs.%s.tools", inits)

      -- Load platform-independent external tool functionality
      load_fns(require("rocks.fs.tools"), inits)

      -- Run platform-specific initializations after everything is loaded
      for _, init in ipairs(inits) do
         init()
      end
   end
end

return fs
