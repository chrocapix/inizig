const std = @import("std");
const __name__ = @import("__name__");
const juice = @import("utilz.juice");
const Timer = @import("utilz.timer");

const usage =
    \\usage: __name__ [options] [arguments]
    \\
    \\options:
    \\  -h, --help      print this help and exit.
    \\
    \\
;

pub fn juicyMain(i: juice.Init(usage)) !void {
    try i.out.print("answer = {}\n", .{__name__.answer()});
}

pub fn main() !void {
    var tim = try Timer.start();
    defer std.log.info("{f}: main", .{tim.read()});
    return juice.main(usage, juicyMain);
}
