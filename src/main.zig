const std = @import("std");
const juice = @import("utilz.juice");

const Allocator = std.mem.Allocator;

const usage =
    \\inizig [options] [argument]
    \\
    \\  Kick-starts a Zig project in the current directory, which must
    \\  be empty.
    \\
    \\options:
    \\  -h, --help           print this help and exit
    \\  -n, --name=<str>     project name (default: name of the working dir)
    \\  -f, --force          run even if the working dir is not isCwdEmpty
    \\  -u, --utilz=<str>    version of utilz to use
    \\  --env                print info
    \\
    \\arguments:
    \\  <str>                [template] template to use (default: cli)
    \\
;

var stdin: *std.Io.Reader = undefined;
var stdout: *std.Io.Writer = undefined;
var stderr: *std.Io.Writer = undefined;

const Options = struct {
    utilz: []const u8 = "0.15.1-0.7",
    force: bool = false,
    name: []const u8 = undefined,
    template: []const u8 = "cli",
};

var opt: Options = .{};

fn juicyMain(i: juice.Init(usage)) !void {
    const al = i.gpa;
    stdin = i.in;
    stdout = i.out;
    stderr = i.err;

    if (i.argv.force > 0)
        opt.force = true;
    if (i.argv.utilz) |u|
        opt.utilz = u;

    opt.name = try getName(al, i.argv.name);
    defer al.free(opt.name);

    if (i.argv.template) |t|
        opt.template = t;

    if (!opt.force and !try isCwdEmpty(al)) {
        std.log.err("working directory not empty", .{});
        return error.CwdNotEmpty;
    }

    const exe_dir = try std.fs.selfExeDirPathAlloc(al);
    defer al.free(exe_dir);
    const home = try std.fs.path.resolve(al, &.{ exe_dir, ".." });
    defer al.free(home);
    std.log.info("inizig home: {s}", .{home});

    const template_dir = try std.fs.path.join(
        al,
        &.{ home, "share", "utilz", "templates", opt.template },
    );
    defer al.free(template_dir);

    if (i.argv.env > 0) {
        std.log.info("utilz version: {s}", .{opt.utilz});
        return;
    }

    std.log.info("zig init -m", .{});
    try run(al, &.{ "zig", "init", "-m" });

    // try zigFetch(al, version);
    try zigFetch(al);

    try copyFiles(i.gpa, template_dir, opt.name);

    std.log.info("zig build", .{});
    try run(al, &.{ "zig", "build" });
    std.log.info("git init, add & commit", .{});
    try run(al, &.{ "git", "init", "." });
    try run(al, &.{ "git", "add", "." });
    try run(al, &.{ "git", "commit", "-m", "initialized by inizig" });
}

fn isCwdEmpty(al: Allocator) !bool {
    var cwd = try std.fs.cwd().openDir(".", .{ .iterate = true });
    defer cwd.close();

    var iter = try cwd.walk(al);
    defer iter.deinit();
    return (try iter.next()) == null;
}

fn copyFiles(al: Allocator, src: []const u8, name: []const u8) !void {
    var dir = try std.fs.cwd().openDir(src, .{ .iterate = true });
    defer dir.close();

    var iter = try dir.walk(al);
    defer iter.deinit();
    while (try iter.next()) |entry| {
        if (std.mem.indexOf(u8, entry.path, ".zig-cache") != null) {
            std.log.info("ignoring {s}", .{entry.path});
            continue;
        }
        switch (entry.kind) {
            .directory => {
                try std.fs.cwd().makeDir(entry.path);
            },
            .file => {
                try dir.copyFile(entry.path, std.fs.cwd(), entry.path, .{});
                try setName(al, entry.path, name);
            },
            else => std.log.warn(
                "inizig: ignoring file '{s}' of type {t}",
                .{ entry.basename, entry.kind },
            ),
        }
    }
}

fn zigFetch(al: Allocator) !void {
    const root = "https://github.com/chrocapix/utilz/archive/refs/";
    const typ = if (std.mem.eql(u8, opt.utilz, "main"))
        "heads/"
    else
        "tags/";

    const url = try std.mem.join(
        al,
        "",
        &.{ root, typ, opt.utilz, ".tar.gz" },
    );
    defer al.free(url);

    std.log.info("utilz: fetching {s}", .{url});
    try run(al, &.{ "zig", "fetch", "--save", url });
}

fn run(al: Allocator, argv: []const []const u8) !void {

    // const cmd = try std.mem.join(al, " ", argv);
    // defer al.free(cmd);
    // try stdout.print("{s}\n", .{cmd});
    // try stdout.flush();

    var child = std.process.Child.init(argv, al);
    child.stdin_behavior = .Ignore;
    child.stdout_behavior = .Inherit;
    child.stderr_behavior = .Inherit;

    const term = try child.spawnAndWait();
    switch (term) {
        .Exited => |code| if (code == 0) return,
        else => {},
    }

    return error.SubProcessFailed;
}

fn setName(
    al: Allocator,
    filename: []const u8,
    name: []const u8,
) !void {
    std.log.info("updating {s}", .{filename});
    // std.debug.print("setName filename {s} name {s}\n", .{filename, name});
    var data = blk: {
        var file = try std.fs.cwd().openFile(filename, .{ .mode = .read_only });
        defer file.close();
        var buf: [1024]u8 = undefined;
        var ifile = file.reader(&buf);
        const in = &ifile.interface;

        var data: std.Io.Writer.Allocating = .init(al);
        _ = try in.stream(&data.writer, .limited(1000_0000));
        break :blk data;
    };
    defer data.deinit();
    // std.debug.print("setName file loaded\n", .{});

    const slabs = try searchAndReplace(al, data.written(), "__name__", name);
    defer al.free(slabs);
    // std.debug.print("setName replace OK\n", .{});

    var file = try std.fs.cwd().createFile(filename, .{});
    defer file.close();
    var buf: [1024]u8 = undefined;
    var ofile = file.writer(&buf);
    const out = &ofile.interface;
    // std.debug.print("setName opened file for writing\n", .{});

    try out.writeVecAll(slabs);
    try out.flush();
    // std.debug.print("setName all done\n", .{});
}

fn searchAndReplace(
    al: Allocator,
    text: []const u8,
    pattern: []const u8,
    repl: []const u8,
) ![][]const u8 {
    var slabs: std.ArrayList([]const u8) = .empty;

    var todo: []const u8 = text;
    while (std.mem.indexOf(u8, todo, pattern)) |i| {
        try slabs.append(al, todo[0..i]);
        try slabs.append(al, repl);
        todo = todo[i + pattern.len ..];
    }
    try slabs.append(al, todo);

    // std.debug.print("slabs:\n", .{});
    // for (slabs.items) |s|
    // std.debug.print("[{s}]\n", .{s});

    return slabs.toOwnedSlice(al);
}

fn getName(al: Allocator, name: ?[]const u8) ![]const u8 {
    if (name) |n| return al.dupe(u8, n);

    const n = try std.fs.realpathAlloc(al, ".");
    defer al.free(n);
    const base = std.fs.path.basename(n);

    return al.dupe(u8, base);
}

pub fn main() !void {
    return juice.main(usage, juicyMain);
}
