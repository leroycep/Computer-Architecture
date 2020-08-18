const std = @import("std");
const assembler = @import("./asm.zig");
const emulator = @import("./cpu.zig");

const MAX_FILE_SIZE = 1024 * 1024 * 1024;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(!gpa.deinit());
    const allocator = &gpa.allocator;

    if (std.os.argv.len != 2) {
        std.log.err(.LS8ToBin, "Incorrect usage. Correct usage:\n\n\t{} ./<filename>.asm", .{std.os.argv[0]});
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
        break :assemble_program try assembler.translate(allocator, contents);
    };
    defer allocator.free(program_bytes);

    // Initialize CPU
    var cpu = emulator.Cpu.init();

    // Load program into memory
    std.mem.copy(u8, &cpu.memory, program_bytes);

    try cpu.run();
}
