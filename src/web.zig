const std = @import("std");
const assembler = @import("./asm.zig");
const emulator = @import("./cpu.zig");
const zee_alloc = @import("zee_alloc");

pub extern fn get_time_seconds() f64;
pub extern fn get_output_buffer() usize;
pub extern fn console_error(buffer_id: usize) void;
pub extern fn console_debug(buffer_id: usize) void;
pub extern fn console_warn(buffer_id: usize) void;
pub extern fn console_info(buffer_id: usize) void;

comptime {
    (zee_alloc.ExportC{
        .allocator = zee_alloc.ZeeAllocDefaults.wasm_allocator,
        .malloc = true,
        .free = true,
    }).run();
}

pub fn log(comptime message_level: std.log.Level, scope: anytype, comptime format: []const u8, args: anytype) void {
    const buffer = WebBuffer.init();
    defer buffer.deinit();
    const writer = buffer.writer();

    writer.print(format, args) catch {};

    switch (message_level) {
        .err, .crit, .alert, .emerg => console_error(buffer.buffer_id),
        .debug => console_debug(buffer.buffer_id),
        .warn => console_warn(buffer.buffer_id),
        .notice, .info => console_info(buffer.buffer_id),
    }
}

pub fn panic(format: []const u8, stacktrace: ?*std.builtin.StackTrace) noreturn {
    @setCold(true);
    while (true) {
        @breakpoint();
    }
}

// Global state
const allocator = zee_alloc.ZeeAllocDefaults.wasm_allocator;
var cpu: emulator.Cpu(WebReader, WebBuffer.Writer) = undefined;
const MAX_DELTA_SECONDS: f64 = 0.25;
var prev_time: f64 = undefined;
var accumulator: f64 = 0.0;

pub export fn init() void {
    reset();
}

pub export fn reset() void {
    const output_buffer = WebBuffer{
        .buffer_id = get_output_buffer(),
    };
    cpu = emulator.Cpu(WebReader, WebBuffer.Writer).init(WebReader{}, output_buffer.writer());
    prev_time = get_time_seconds();
    accumulator = 0;
}

pub export fn upload_program(ptr: [*]u8, len: usize) bool {
    const text = ptr[0..len];
    defer allocator.free(text);

    // Convert the LS8 text into actually binary LS8
    if (assembler.translate(allocator, text)) |bytes| {
        defer allocator.free(bytes);
        std.log.debug("Program: {x}", .{bytes});
        for (bytes) |b, idx| {
            cpu.memory[idx] = b;
        }
        return true;
    } else |err| {
        std.log.err("Failed to translate assembly: {}", .{err});
        return false;
    }
}

pub export fn step() void {
    cpu.step() catch |err| {
        std.log.err("Error stepping CPU: {}", .{err});
    };
}

pub export fn stepMany() bool {
    const tick_delta_seconds: f64 = 1.0 / @intToFloat(f64, cpu.frequency);
    const current_time = get_time_seconds();

    var delta = current_time - prev_time;
    if (delta > MAX_DELTA_SECONDS) {
        delta = MAX_DELTA_SECONDS;
    }
    prev_time = current_time;

    accumulator += delta;

    while (!cpu.halted and accumulator >= tick_delta_seconds) {
        cpu.step() catch |err| {
            std.log.err("Error stepping CPU: {}", .{err});
            return false;
        };
        accumulator -= tick_delta_seconds;
    }
    return !cpu.halted;
}

const WebReader = struct {
    pub fn readByte(this: *@This()) error{ WouldBlock, EndOfStream }!u8 {
        return error.WouldBlock;
    }
};

const WebBuffer = struct {
    buffer_id: usize,

    extern fn buffer_init() usize;
    extern fn buffer_extend(buffer_id: usize, ptr: [*]const u8, len: usize) void;
    extern fn buffer_deinit(buffer_id: usize) void;

    pub const Writer = std.io.Writer(@This(), error{}, write);

    pub fn init() @This() {
        return @This(){
            .buffer_id = buffer_init(),
        };
    }

    pub fn deinit(this: @This()) void {
        buffer_deinit(this.buffer_id);
    }

    pub fn write(this: @This(), bytes: []const u8) error{}!usize {
        buffer_extend(this.buffer_id, bytes.ptr, bytes.len);
        return bytes.len;
    }

    pub fn writer(this: @This()) Writer {
        return Writer{
            .context = this,
        };
    }
};
