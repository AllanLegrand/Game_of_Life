const std = @import("std");

const print = std.debug.print;

const ANSI_COLOR_RESET = "\x1b[0m";
const ANSI_CLEAR = "\x1B[H\x1B[J";
const args_enum = enum {
    time,
    percent,
    columns,
    rows,
    symbol,
    birth,
    survi,
    color,
    help,
    unknown,
};

const args_strings = std.StaticStringMap(args_enum).initComptime(.{
    .{ "-t", .time },
    .{ "--time", .time },
    .{ "-p", .percent },
    .{ "--percent", .percent },
    .{ "-c", .columns },
    .{ "--columns", .columns },
    .{ "-r", .rows },
    .{ "--rows", .rows },
    .{ "-s", .symbol },
    .{ "--symbol", .symbol },
    .{ "-b", .birth },
    .{ "--birth", .birth },
    .{ "-v", .survi },
    .{ "--survi", .survi },
    .{ "-o", .color },
    .{ "--color", .color },
    .{ "-h", .help },
    .{ "--help", .help },
});

var exit: bool = false;

fn handle_sigint(sig: i32, _: ?*const std.posix.siginfo_t, _: ?*const anyopaque) callconv(.C) void {
    print(" Exit\n", .{});
    _ = sig;
    exit = true;
}

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    var sleep_time: usize = 1000;

    var cell_state: [][]bool = undefined;

    var rows: usize = 10;
    var cols: usize = 10;

    var percent: usize = 25;

    var arr_birth = try parse_rule(args[0], "comptime_error", "3");
    var arr_survi = try parse_rule(args[0], "comptime_error", "23");

    var symbol: u8 = 'X';

    var color: u8 = 30;

    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const arg = args_strings.get(args[i]) orelse .unknown;
        switch (arg) {
            .time => {
                try verify_required_arg(args, &i);

                sleep_time = try parse_int(args[0], args[i - 1], args[i]);
            },
            .percent => {
                try verify_required_arg(args, &i);

                percent = try parse_int(args[0], args[i - 1], args[i]);

                if (percent < 0 or percent > 100) {
                    print("{s}: {s}: percentage must be between 0 and 100\n", .{ args[0], args[i - 1] });
                    return error.InvalidCharacter;
                }
            },
            .columns => {
                try verify_required_arg(args, &i);

                cols = try parse_int(args[0], args[i - 1], args[i]);

                if (cols <= 0) {
                    print("{s}: {s}: number of columns must be more than 0\n", .{ args[0], args[i - 1] });
                    return error.InvalidCharacter;
                }
            },
            .rows => {
                try verify_required_arg(args, &i);

                rows = try parse_int(args[0], args[i - 1], args[i]);

                if (rows <= 0) {
                    print("{s}: {s}: number of rows must be more than 0\n", .{ args[0], args[i - 1] });
                    return error.InvalidCharacter;
                }
            },
            .symbol => {
                try verify_required_arg(args, &i);

                symbol = args[i][0];

                if (symbol & 0b10000000 != 0) {
                    print("{s}: {s}: symbol must be an ascii character\n", .{ args[0], args[i - 1] });
                    return error.InvalidCharacter;
                }
            },
            .birth => {
                try verify_required_arg(args, &i);

                arr_birth = try parse_rule(args[i], args[i - 1], args[i]);
            },
            .survi => {
                try verify_required_arg(args, &i);

                arr_survi = try parse_rule(args[0], args[i - 1], args[i]);
            },
            .color => {
                try verify_required_arg(args, &i);

                color = @intCast(try parse_int(args[0], args[i - 1], args[i]));

                if (color < 0 or color > 255) {
                    print("{s}: {s}: color must between 0 and 255\n", .{ args[0], args[i] });
                    return error.InvalidCharacter;
                }
            },
            .help => {
                print_help(args[0]);
                return;
            },
            .unknown => {
                print("{s}: {s}: unknown parameter\n\n", .{ args[0], args[i] });
                print_help(args[0]);
                return;
            },
        }
    }

    var act = std.posix.Sigaction{
        .handler = .{ .sigaction = handle_sigint },
        .mask = std.posix.empty_sigset,
        .flags = 0,
    };
    std.posix.sigaction(std.posix.SIG.INT, &act, null);

    var prng = std.Random.DefaultPrng.init(blk: {
        var seed: u64 = undefined;
        try std.posix.getrandom(std.mem.asBytes(&seed));
        break :blk seed;
    });

    const rand = prng.random();

    cell_state = try allocator.alloc([]bool, rows);
    for (cell_state) |*row| {
        row.* = try allocator.alloc(bool, cols);
        for (0..cols) |col| {
            row.*[col] = rand.intRangeAtMost(u8, 0, 100) < percent;
        }
    }

    defer {
        for (cell_state) |row| {
            allocator.free(row);
        }
        allocator.free(cell_state);
    }

    while (!exit) {
        print("{s}", .{ANSI_CLEAR});
        print_arr(cell_state, symbol, color);
        try next_state(allocator, cell_state, arr_birth, arr_survi);
        std.time.sleep(sleep_time * std.time.ns_per_ms);
    }
}

fn count_neighboor(cell_state: [][]bool, row: usize, col: usize) usize {
    const rows: isize = @as(isize, @intCast(cell_state.len));
    const cols: isize = @as(isize, @intCast(cell_state[row].len));

    var count: usize = 0;
    comptime var i: i3 = -1;
    inline while (i <= 1) : (i += 1) {
        comptime var j: i3 = -1;
        inline while (j <= 1) : (j += 1) {
            if (i == 0 and j == 0)
                continue;

            const r = @as(usize, @intCast(@mod(@as(isize, @intCast(row)) + @as(isize, i) + rows, rows)));
            const c = @as(usize, @intCast(@mod(@as(isize, @intCast(col)) + @as(isize, j) + cols, cols)));
            count += if (cell_state[r][c]) 1 else 0;
        }
    }

    return count;
}

fn next_state(allocator: std.mem.Allocator, cell_state: [][]bool, arr_birth: [9]bool, arr_survi: [9]bool) !void {
    var next = try allocator.alloc([]bool, cell_state.len);
    for (0..cell_state.len) |row|
        next[row] = try allocator.alloc(bool, cell_state[row].len);

    defer {
        for (next) |row|
            allocator.free(row);
        allocator.free(next);
    }

    for (0..next.len) |row| {
        for (0..next[row].len) |col| {
            const count = count_neighboor(cell_state, row, col);
            next[row][col] = (cell_state[row][col] and arr_survi[count]) or (!cell_state[row][col] and arr_birth[count]);
        }
    }

    for (0..cell_state.len) |row|
        @memcpy(cell_state[row], next[row]);
}

fn print_arr(cell_state: [][]bool, symbol: u8, color: u8) void {
    print("\x1b[38;5;{d}m", .{color});
    for (cell_state) |cell_row| {
        for (cell_row) |cell| {
            print("{c}", .{if (cell) symbol else ' '});
        }
        print("\n", .{});
    }

    print("{s}\n", .{ANSI_COLOR_RESET});
}

fn print_help(filename: []const u8) void {
    print(
        \\Usage: {s} [-t miliseconds] [-p percent] [-c columns] [-r rows] [-s char] [-b birth rules] [-v survive rules] [-o color]
        \\Launches The Game of Life by John Horton Conway
        \\
        \\Options:
        \\  -t, --time      set the time interval between displaying each generation
        \\  -p, --percent   set the live cell percentage at the start
        \\  -c, --columns   set number of columns
        \\  -r, --rows      set number of rows
        \\  -s, --symbol    set the character representing living cells
        \\  -b, --birth     set number of neighboring cells alive so that a cell can be born
        \\  -v, --survi     set number of neighboring cells alive so that a cell can stay alive
        \\  -o, --color     change cell color
        \\  -h, --help      show help and quit
        \\
    , .{filename});
}

fn parse_int(filename: []const u8, optname: []const u8, value: []const u8) !usize {
    return std.fmt.parseInt(usize, value, 10) catch |err| {
        switch (err) {
            error.InvalidCharacter => {
                print("{s}: {s}: {s}: illegal numeric value\n", .{ filename, optname, value });
            },
            error.Overflow => {
                print("{s}: {s}: {s}: overflow\n", .{ filename, optname, value });
            },
        }

        return err;
    };
}

fn verify_required_arg(args: [][:0]u8, i: *usize) !void {
    i.* += 1;
    if (i.* >= args.len) {
        print("{s}: {s}: requires additional arguments\n", .{ args[0], args[i.* - 1] });
        return error.ExpectedArgument;
    }
}

fn parse_rule(filename: []const u8, optname: []const u8, rules: []const u8) ![9]bool {
    var arr_rules = [_]bool{false} ** 9;

    for (rules) |c| {
        if (c < '0' or c > '8') {
            print("{s}: {s}: {c}: illegal numeric value\n", .{ filename, optname, c });
            return error.InvalidCharacter;
        }

        arr_rules[c - '0'] = true;
    }

    return arr_rules;
}

test "parse_int" {
    const expect = std.testing.expect;
    const expectError = std.testing.expectError;

    try expect(try parse_int("test", "-t", "123") == 123);
    try expect(try parse_int("test", "-p", "0") == 0);
    try expectError(error.InvalidCharacter, parse_int("test", "-t", "abc"));
    try expectError(error.Overflow, parse_int("test", "-t", "999999999999999999999"));
}

test "parse_rule" {
    const expectError = std.testing.expectError;
    const expectEqualSlices = std.testing.expectEqualSlices;

    const rule_b3 = try parse_rule("test", "-b", "3");
    try expectEqualSlices(bool, &rule_b3, &[_]bool{ false, false, false, true, false, false, false, false, false });

    const rule_s23 = try parse_rule("test", "-v", "23");
    try expectEqualSlices(bool, &rule_s23, &[_]bool{ false, false, true, true, false, false, false, false, false });

    try expectError(error.InvalidCharacter, parse_rule("test", "-b", "9"));
    try expectError(error.InvalidCharacter, parse_rule("test", "-v", "abc"));
}

test "count_neighboor" {
    const allocator = std.testing.allocator;
    const expect = std.testing.expect;

    var grid = try allocator.alloc([]bool, 3);
    for (grid) |*row| {
        row.* = try allocator.alloc(bool, 3);
    }
    defer {
        for (grid) |row| allocator.free(row);
        allocator.free(grid);
    }

    for (grid) |row| @memset(row, false);
    try expect(count_neighboor(grid, 1, 1) == 0);

    grid[0][1] = true;
    grid[1][0] = true;
    grid[1][2] = true;
    try expect(count_neighboor(grid, 1, 1) == 3);

    grid[2][0] = true;
    grid[0][2] = true;
    try expect(count_neighboor(grid, 0, 0) == 5);
}

test "next_state" {
    const allocator = std.testing.allocator;
    const expect = std.testing.expect;

    const grid = try allocator.alloc([]bool, 3);
    for (grid) |*row| {
        row.* = try allocator.alloc(bool, 3);
    }
    defer {
        for (grid) |row| allocator.free(row);
        allocator.free(grid);
    }

    const arr_birth = try parse_rule("test", "default", "3");
    const arr_survi = try parse_rule("test", "default", "23");

    @memset(grid[0], false);
    @memset(grid[1], true);
    @memset(grid[2], false);

    try next_state(allocator, grid, arr_birth, arr_survi);

    try expect(grid[0][1] == true);
    try expect(grid[1][1] == true);
    try expect(grid[2][1] == true);
    try expect(grid[0][0] == true);
    try expect(grid[0][2] == true);
    try expect(grid[1][0] == true);
    try expect(grid[1][2] == true);
    try expect(grid[2][0] == true);
    try expect(grid[2][2] == true);
}
