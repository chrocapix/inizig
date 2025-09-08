const std = @import("std");
const juice = @import("utilz.juice");
const Timer = @import("utilz.timer");

const usage =
    \\usage: __name__ [options] [arguments]
    \\
    \\options:
    \\  -h, --help      print this help and exit.
    \\
    \\arguments:
    \\  <uint>          [answer]
    \\
;

pub fn juicyMain(i: juice.Init(usage)) !void {
    try i.out.print("answer = {}\n", .{i.argv.answer orelse 42});
}

pub fn main() !void {
    var tim = try Timer.start();
    defer std.log.info("{f}: main", .{tim.read()});
    return juice.main(usage, juicyMain);
}
