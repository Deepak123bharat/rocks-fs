local record fs 

    record Env
        CC: string
    end

    execute_env: function(env: Env, command: string, ...: string): boolean

    filter_file: function(fn: function, input_filename: string, output_filename: string): boolean , string

    system_cache_dir: function():string

    set_tool_available: function(tool_name: string, value: boolean)

    tmpname: function(): string

    --- Cpies the given binary file to the file specified in the dest argument
    -- @param filename string
    -- @param dest string
    -- @return boolean 
    copy_binary: function(filename: string, dest: string): boolean

    --- Recursively scan the contents of a directory.
    -- @param at string or nil: directory to scan (will be the current
    -- directory if none is given).
    -- @return table: an array of strings with the filenames representing
    -- the contents of a directory. Paths are returned with forward slashes.
    find: function(at: string): {string}

    --- Annotate command string for execution with quiet stderr.
    -- @param cmd string: A command-line string.
    -- @return string: The command-line, with stderr silencing annotation.
    quiet_stderr: function(cmd: string): string

    _unix_rwx_to_number: function(rwx: string, neg: boolean): number

    --- Quote argument for shell processing.
    -- Adds single quotes and escapes.
    -- @param arg string: Unquoted argument.
    -- @return string: Quoted argument.
    Q: function(art: string): string

    system_temp_dir: function(): string

    --- Annotate command string for quiet execution.
    -- @param cmd string: A command-line string.
    -- @return string: The command-line, with silencing annotation.
    quiet: function(cmd: string): string

    --- Move a file.
    -- @param src string: Pathname of source
    -- @param dest string: Pathname of destination
    -- @param perms string ("read" or "exec") or nil: Permissions for destination
    -- file or nil to use the source file permissions.
    -- @return boolean or (boolean, string): true on success, false on failure,
    -- plus an error message.
    move: function(src: string, dest: string, perms: string): boolean , string

    export_cmd: function(val: string, var: string): string

    --- Internal implementation function for fs.dir.
    -- Yields a filename on each iteration.
    -- @param at string: directory to list
    -- @return nil or (nil and string): an error message on failure
    dir_iterator: function(at: string): string, string

    --- Iterate over the contents of a directory.
    -- @param at string or nil: directory to list (will be the current
    -- directory if none is given).
    -- @return function: an iterator function suitable for use with
    -- the for statement.
    dir: function(at: string) : (function() : string, string)
    
    --@param tool_type string
    which_tool: function(tool_type: string): string, string
    
    --- List the Lua modules at a specific require path.
    --@param at string
    -- eg. `modules("luarocks.cmd")` would return a list of all LuaRocks command
    -- modules, in the current Lua path.
    modules: function(at: string): {string}
    
    -- Check if a file (typically inside path.bin_dir) is an actual binary or a Lua wrapper.
    is_actual_binary: function(filename: string): boolean

    --- Change working directory to the previous in the dir stack.
    -- @return true if a pop occurred, false if the stack was empty.
    pop_dir: function(): boolean

    --- Download a remote file.
    -- @param url string: URL to be fetched.
    -- @param filename string or nil: this function attempts to detect the
    -- resulting local filename of the remote file as the basename of the URL;
    -- if that is not correct (due to a redirection, for example), the local
    -- filename can be given explicitly as this second argument.
    -- @param cache boolean: compare remote timestamps via HTTP HEAD prior to
    -- re-downloading the file.
    -- @return (boolean, string): true and the filename on success,
    -- false and the error message on failure.
    use_downloader: function(url: string, filename: string, cache: boolean): boolean, string

    --- Checks if the given tool is available.
    -- The tool is executed using a flag, usually just to ask its version.
    -- @param tool_cmd string: The command to be used to check the tool's presence (e.g. hg in case of Mercurial)
    -- @param tool_name string: The actual name of the tool (e.g. Mercurial)
    -- @param arg string: The flag to pass to the tool. '--version' by default.
    is_tool_available: function(tool_cmd: string, tool_name: string, arg: string): boolean

    --Is a directory or not
    is_dir: function(file: string): boolean

    --- Recursively copy the contents of a directory.
    -- @param src string: Pathname of source
    -- @param dest string: Pathname of destination
    -- @return boolean or (boolean, string): true on success, false on failure,
    -- plus an error message.
    copy_contents: function(src: string, dest: string): boolean | boolean, string

    --- Change the current directory.
    -- Uses the module's internal directory stack. This does not have exact
    -- semantics of chdir, as it does not handle errors the same way,
    -- but works well for our purposes for now.
    -- @param directory string: The directory to switch to.
    -- @return boolean or (nil, string): true if successful, (nil, error message) if failed.
    change_dir: function(directory: string):boolean, string

    --- Obtain current directory.
    -- Uses the module's internal dir stack.
    -- @return string: the absolute pathname of the current directory.
    current_dir: function(): string

    --- Run the given command, quoting its arguments, silencing its output.
    -- The command is executed in the current directory in the dir stack.
    -- @param command string: The command to be executed. No quoting/escaping
    -- is applied.
    -- @param ... Strings containing additional arguments, which will be quoted.
    -- @return boolean: true if command succeeds (status code 0), false
    execute_quiet: function(command: string, ...:string ): boolean

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
    replace_file: function(old_file: string, new_file: string): boolean, string

    --- Create a directory if it does not already exist.
    -- If any of the higher levels in the path name does not exist
    -- too, they are created as well.
    -- @param directory string: pathname of directory to create.
    -- @return boolean: true on success, false on failure.
    make_dir: function(directory: string): boolean

    --- Test is file/dir is writable.
    -- Warning: testing if a file/dir is writable does not guarantee
    -- that it will remain writable and therefore it is no replacement
    -- for checking the result of subsequent operations.
    -- @param file string: filename to test
    -- @return boolean: true if file exists, false otherwise.
    is_writable: function(file: string): boolean

    --- Return an absolute pathname from a potentially relative one.
    -- @param pathname string: pathname to convert.
    -- @param relative_to string or nil: path to prepend when making
    -- pathname absolute, or the current dir in the dir stack if
    -- not given.
    -- @return string: The pathname converted to absolute.
    absolute_name: function(pathname: string, relative_to: string): string

    --- Test is pathname is a regular file.
    -- @param file string: pathname to test
    -- @return boolean: true if it is a regular file, false otherwise.
    is_file: function(file: string): boolean

    --- Check if platform is unix
    -- @return boolean: true if LuaRocks is currently running on unix.
    is_platform_unix: function(): boolean

    --- Check the MD5 checksum for a file.
    -- @param file string: The file to be checked.
    -- @param md5sum string: The string with the expected MD5 checksum.
    -- @return boolean: true if the MD5 checksum for 'file' equals 'md5sum', false + msg if not
    -- or if it could not perform the check for any reason.
    check_md5: function(file: string, md5sum: string): boolean | boolean,string

    --- Copy a file.
    -- @param src string: Pathname of source
    -- @param dest string: Pathname of destination
    -- @return boolean or (boolean, string): true on success, false on failure,
    -- plus an error message.
    copy: function(src: string, dest: string): boolean | boolean , string

    --- Uncompresses a .bz2 file.
    -- @param infile string: pathname of .bz2 file to be extracted.
    -- @param outfile string or nil: pathname of output file to be produced.
    -- If not given, name is derived from input file.
    -- @return boolean: true on success; nil and error message on failure.
    bunzip2: function(infile: string, outfile: string): boolean , string
    
    --- Apply a patch.
    -- @param patchname string: The filename of the patch.
    -- @param patchdata string or nil: The actual patch as a string.
    -- @param create_delete boolean: Support creating and deleting files in a patch.
    apply_patch: function(patchname: string, patchdata: string , create_delete: boolean): boolean , string
    
    --- Remove a directory if it is empty.
    -- Does not return errors (for example, if directory is not empty or
    -- if already does not exist)
    -- @param d string: pathname of directory to remove.
    remove_dir_if_empty: function(d: string)

    --- Moderate the given permissions based on the local umask
    -- @param perms string: permissions to moderate
    -- @return string: the moderated permissions
    _unix_moderate_permissions: function(perms: string): string

    --- Set permissions for file or directory
    -- @param filename string: filename whose permissions are to be modified
    -- @param mode string ("read" or "exec"): permissions to set
    -- @param scope string ("user" or "all"): the user(s) to whom the permission applies
    -- @return boolean or (boolean, string): true on success, false on failure,
    -- plus an error message
    set_permissions: function(filename: string, mode: string, scope: string): boolean | boolean, string

    is_superuser: function(): boolean

    --- Get the MD5 checksum for a file.
    -- @param file string: The file to be computed.
    -- @return string: The MD5 checksum or nil + message
    get_md5: function(file: string): string , string

    --- Remove a directory if it is empty.
    -- Does not return errors (for example, if directory is not empty or
    -- if already does not exist)
    -- @param d string: pathname of directory to remove.
    remove_dir_tree_if_empty: function(d: string)

    --- Create a temporary directory.
    -- @param name_pattern string: name pattern to use for avoiding conflicts
    -- when creating temporary directory.
    -- @return string or (nil, string): name of temporary directory or (nil, error message) on failure.
    make_temp_dir: function(name_pattern: string): string, string

    --- List the contents of a directory.
    -- @param at string or nil: directory to list (will be the current
    -- directory if none is given).
    -- @return table: an array of strings with the filenames representing
    -- the contents of a directory.
    list_dir: function(at: string): {string}

    --- Test is file/directory exists
    -- @param file string: filename to test
    -- @return boolean: true if file exists, false otherwise.
    exists: function(file: string): boolean

    --- Change directory to root.
    -- Allows leaving a directory (e.g. for deleting it) in
    -- a crossplatform way.
    change_dir_to_root: function(): boolean

    current_user: function(): string

    --- Run the given command.
    -- The command is executed in the current directory in the directory stack.
    -- @param cmd string: No quoting/escaping is applied to the command.
    -- @return boolean: true if command succeeds (status code 0), false
    -- otherwise.
    execute_string: function(cmd: string): boolean

    --- Run the given command, quoting its arguments.
    -- The command is executed in the current directory in the dir stack.
    -- @param command string: The command to be executed. No quoting/escaping
    -- is applied.
    -- @param ... Strings containing additional arguments, which are quoted.
    -- @return boolean: true if command succeeds (status code 0), false
    -- otherwise.
    execute: function(command: string, ...: string): boolean

    --- Uncompress files from a .zip archive.
    -- @param zipfile string: pathname of .zip archive to be extracted.
    -- @return boolean: true on success, nil and error message on failure.
    unzip: function(zipfile: string): boolean , string

    --- Adds prefix to command to make it run from a directory.
    -- @param directory string: Path to a directory.
    -- @param cmd string: A command-line string.
    -- @return string: The command-line with prefix.
    command_at: function(directory: string, cmd: string): string

    --- Delete a file or a directory and all its contents.
    -- For safety, this only accepts absolute paths.
    -- @param arg string: Pathname of source
    -- @return nil
    delete: function(arg: string)

    --- Uncompresses a .gz file.
    -- @param infile string: pathname of .gz file to be extracted.
    -- @param outfile string or nil: pathname of output file to be produced.
    -- If not given, name is derived from input file.
    -- @return boolean: true on success; nil and error message on failure.
    gunzip: function(infile: string, outfile: string ): boolean , string

    --- Return the root directory for the given path.
    -- In Unix, root is always "/".
    -- In Windows, for "c:\hello", returns "c:\"
    -- @param pathname string: pathname to use.
    -- @return string: The root of the given pathname.
    root_fo: function(pathname: string): string

    --- Compress files in a .zip archive.
    -- @param zipfile string: pathname of .zip archive to be created.
    -- @param ... Filenames to be stored in the archive are given as
    -- additional arguments.
    -- @return boolean: true on success, nil and error message on failure.
    zip: function(zipfile: string, ...: string): boolean , string

    --******FIX It for windos******--
    -- Set access and modification times for a file.
    -- @param filename File to set access and modification times for.
    -- @param time may be a string or number containing the format returned
    -- by os.time, or a table ready to be processed via os.time; if
    -- nil, current time is assumed.
    set_time: function(filename: string, time: string): boolean


end

return fs