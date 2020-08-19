const std = @import("std");
const builtin = @import("builtin");
const assembler = @import("./asm.zig");
const emulator = @import("./cpu.zig");

const MAX_FILE_SIZE = 1024 * 1024 * 1024;
const VTIME = 5;
const VMIN = 6;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(!gpa.deinit());
    const allocator = &gpa.allocator;

    if (std.os.argv.len != 2) {
        std.log.err(.LS8, "Incorrect usage. Correct usage:\n\n\t{} ./<filename>.asm", .{std.os.argv[0]});
        std.os.exit(1);
    }

    const program_bytes = assemble_program: {
        // Get the input filepath
        const filename_len = std.mem.len(std.os.argv[1]);
        const filename = std.os.argv[1][0..filename_len];

        // Get the contents of the input file
        const cwd = std.fs.cwd();
        const contents = try cwd.readFileAlloc(allocator, filename, MAX_FILE_SIZE);
        defer allocator.free(contents);

        // Convert the LS8 text into actually binary LS8
        if (assembler.translate(allocator, contents)) |bytes| {
            break :assemble_program bytes;
        } else |err| {
            std.log.err(.LS8, "Failed to translate assembly: {}", .{err});
            std.os.exit(1);
        }
    };
    defer allocator.free(program_bytes);

    // Set up stdin to make input nonblocking
    var stdin_file = std.io.getStdIn();
    if (builtin.os.tag == .linux) {
        const flags = try std.os.fcntl(stdin_file.handle, std.os.F_GETFL, 0);
        _ = try std.os.fcntl(stdin_file.handle, std.os.F_SETFL, flags | std.os.O_NONBLOCK);
    }

    // Set up terminal to input every key
    const original_term_attr = set_up_term: {
        if (builtin.os.tag != .linux) break :set_up_term null;
        if (!std.os.isatty(stdin_file.handle)) break :set_up_term null;

        const original_term_attr = try std.os.tcgetattr(stdin_file.handle);

        var new_term_attr = original_term_attr;
        new_term_attr.lflag &= ~(@as(c_uint, std.os.ECHO) | std.os.ICANON);
        new_term_attr.cc[VTIME] = 0;
        new_term_attr.cc[VMIN] = 0;
        try std.os.tcsetattr(stdin_file.handle, .NOW, new_term_attr);

        break :set_up_term original_term_attr;
    };
    defer {
        if (original_term_attr) |attr| {
            std.os.tcsetattr(stdin_file.handle, .NOW, attr) catch {};
        }
    }

    const stdin = stdin_file.reader();

    const stdout = std.io.getStdOut().writer();

    // Initialize CPU
    var cpu = emulator.Cpu(@TypeOf(stdin), @TypeOf(stdout)).init(stdin, stdout);

    // Load program into memory
    std.mem.copy(u8, &cpu.memory, program_bytes);

    const MAX_DELTA_SECONDS: f64 = 0.25;
    var prev_time = std.time.milliTimestamp();
    var accumulator: f64 = 0.0;

    while (!cpu.halted) {
        const tick_delta_seconds: f64 = 1.0 / @intToFloat(f64, cpu.frequency);
        const current_time = std.time.milliTimestamp();

        var delta = @intToFloat(f64, current_time - prev_time) / 1000;
        if (delta > MAX_DELTA_SECONDS) {
            delta = MAX_DELTA_SECONDS;
        }
        prev_time = current_time;

        accumulator += delta;

        while (accumulator >= tick_delta_seconds) {
            try cpu.step();
            accumulator -= tick_delta_seconds;
        }
    }
}
