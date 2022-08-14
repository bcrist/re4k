-- This file is used to generate build.zig, based on the configuration in build.sx

local parser = sx.parser(get_file_contents('build.sx'))
local root_visitor = {}
local dir_visitor = {}
local pkg_visitor = {}
local exe_visitor = {}

local dirs = {}
local notest_dirs = {}
local file_deps = {}
local packages = {}
local exes = {}
local tests = {}

function root_visitor.dir ()
    local path = parser:require_string()
    dirs[#dirs + 1] = path
    while nil ~= parser:property(dir_visitor, path) do end
    parser:require_close()
end


function dir_visitor.pkg (_, _, dir_path)
    local name = parser:require_string()
    local default_path = fs.compose_path_slash(dir_path, name .. '.zig')
    local package = {
        name = name,
        dir = dir_path,
        path = default_path,
    }
    while nil ~= parser:property(pkg_visitor, package) do end
    parser:require_close()
    packages[package.name] = package
end

function dir_visitor.exe (_, _, dir_path)
    local name = parser:require_string()
    local default_path = fs.compose_path_slash(dir_path, name .. '.zig')
    local executable = {
        name = name,
        dir = dir_path,
        path = default_path,
    }
    while nil ~= parser:property(exe_visitor, executable) do end
    parser:require_close()
    exes[executable.name] = executable
end

function dir_visitor.notest (_, _, dir_path)
    parser:require_close()
    notest_dirs[dir_path] = true
end

function exe_visitor.runStep (_, _, executable)
    executable.runStep = parser:require_string()
    parser:require_close()
end


while nil ~= parser:property(root_visitor) do end

-- Look for file dependencies and tests within .zig files
for i = 1, #dirs do
    local dir = dirs[i]
    local check_for_tests = not notest_dirs[dir]
    fs.visit(dir, function(subpath, kind)
        if kind ~= 'File' or fs.path_extension(subpath) ~= '.zig' then return end

        local path = fs.compose_path_slash(dir, subpath)
        local contents = get_file_contents(path)
        local deps = {}
        for import_name in contents:gmatch('@import%("([^"]+)"%)') do
            if fs.path_extension(import_name) == '.zig' then
                deps[#deps + 1] = fs.compose_path_slash(dir, import_name)
            elseif import_name ~= 'std' and import_name ~= 'builtin' then
                deps[#deps + 1] = import_name
            end
        end
        if #deps > 0 then
            file_deps[path] = deps
        end

        if check_for_tests and (contents:match('\ntest%s*"[^"]*"%s*{') or contents:match('\ntest%s*{')) then
            tests[path] = true
        end
    end)
end

local function collect_named_deps (path, named_deps, visited_files)
    local deps = file_deps[path]
    if deps == nil then return end

    if visited_files[path] ~= nil then return end
    visited_files[path] = true

    for i = 1, #deps do
        local dep = deps[i]
        if fs.path_extension(dep) == '.zig' then
            collect_named_deps(dep, named_deps, visited_files)
        else
            if packages[dep] == nil then
                error("Package not found: " .. dep)
            end
            named_deps[dep] = true
            packages[dep].used = true
        end
    end
end

-- Compile dependencies for each package
for _, package in pairs(packages) do
    if package.deps == nil then
        package.deps = {}
        collect_named_deps(package.path, package.deps, {})
    end
end

-- Compile dependencies for each executable
for _, exe in pairs(exes) do
    if exe.deps == nil then
        exe.deps = {}
        collect_named_deps(exe.path, exe.deps, {})
    end
    if exe.runStep == nil then
        exe.runStep = exe.name
    end
end

local function get_package (pkg_name)
    local pkg = packages[pkg_name]
    if pkg == nil then
        error("Package " .. pkg_name .. " not found!")
    end
    return pkg
end

write [[
const std = @import("std");
const Pkg = std.build.Pkg;

pub fn build(b: *std.build.Builder) void {
    const target = b.standardTargetOptions(.{});
    const mode = b.standardReleaseOptions();

    ]]
indent()

local write_pkg = template [[
const `name` = Pkg {
    .name = "`name`",
    .source = .{ .path = "`path`" },`
if next(deps) then
    indent()
    nl()
    write '.dependencies = &[_]Pkg {'
    indent()
    for dep in spairs(deps) do
        write(nl, dep, ',')
    end
    unindent()
    nl()
    unindent()
    write '},'
end
`
};
]]
local function try_write_package (package)
    if not package.written_to_build then
        for dep in spairs(package.deps) do
            try_write_package(get_package(dep))
        end
        write_pkg(package)
        package.written_to_build = true
    end
end

for _, package in spairs(packages) do
    try_write_package(package)
end

local write_exe = template [[

const `name` = b.addExecutable("`name`", "`path`");`
for dep in spairs(deps) do
    write(nl, name, '.addPackage(', dep, ');')
end`
`name`.linkLibC();
`name`.setTarget(target);
`name`.setBuildMode(mode);
`name`.install();
_ = makeRunStep(b, `name`, "`runStep`", "run `name`");
]]

for _, exe in spairs(exes) do
    write_exe(exe)
end

local i = 1
for test in spairs(tests) do
    local deps = {}
    collect_named_deps(test, deps, {})

    write(nl, 'const tests', i, ' = b.addTest("', test, '");')
    for dep in spairs(deps) do
        write(nl, 'tests', i, '.addPackage(', dep, ');')
    end
    write(nl, 'tests', i, '.setTarget(target);')
    write(nl, 'tests', i, '.setBuildMode(mode);')
    nl()
    i = i + 1
end

if i > 1 then
    nl()
    write 'const test_step = b.step("test", "Run all tests");'

    local i = 1
    for test in spairs(tests) do
        write(nl, 'test_step.dependOn(&tests', i, '.step);')
        i = i + 1
    end

    nl()
end

for _, package in spairs(packages) do
    if not package.used then
        write(nl, '_ = ', package.name, ';')
    end
end

unindent()
nl()
write '}'
