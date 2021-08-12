rockspec_format = "3.0"
package = "rocks-fs"
version = "dev-1"
source = {
	url = "git://github.com/Deepak123bharat/rocks-fs",
}
description = {
	summary = "Module for filesystem and platform abstractions. ",
	detailed = [[
		fs is a Lua implementation of filesystem and platform abstractions.
	]],
	homepage = "https://github.com/Deepak123bharat/rocks-fs", 
	license = "MIT" 
}
dependencies = {
	"lua >= 5.1, < 5.5",
	"luafilesystem",
	"luasocket",
	"md5",
	"lua-bz2",
	"luaposix",
	"rocks-dir",
}
build = {
	type = "builtin",
	modules = {
		["rocks.fs"] = "src/rocks/fs.lua",

		["rocks.fs.unix.tools"] = "src/rocks/fs/unix/tools.lua",
		["rocks.fs.win32.tools"] = "src/rocks/fs/win32/tools.lua",

		["rocks.fs.freebsd"] = "src/rocks/fs/freebsd.lua",
		["rocks.fs.linux"] = "src/rocks/fs/linux.lua",
		["rocks.fs.macosx"] = "src/rocks/fs/macosx.lua",
		["rocks.fs.native"] = "src/rocks/fs/native.lua",
		["rocks.fs.netbsd"] = "src/rocks/fs/netbsd.lua",
		["rocks.fs.tools"] = "src/rocks/fs/tools.lua",
		["rocks.fs.unix"] = "src/rocks/fs/unix.lua",
		["rocks.fs.win32"] = "src/rocks/fs/win32.lua",
	}
}
test_dependencies = {
   "luacov",
   "busted-htest",
   "rocks-sysdetect",
}
test = {
   type = "busted",
   platforms = {
      windows = {
         flags = { "--exclude-tags=ssh,git,unix" }
      },
      unix = {
         flags = { "--exclude-tags=ssh,git" }
      }
   }
}