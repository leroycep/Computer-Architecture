const std = @import("std");

pub fn build(b: *std.build.Builder) void {
    const exe = b.addExecutable("ls8", "src/main.zig");
    exe.install();
    b.getInstallStep().dependOn(&exe.step);

    const run = exe.run();
    const asm_file = b.option([]const u8, "asm-file", "The asm file that should be passed to the executable") orelse "asm/print8.asm";
    run.addArg(asm_file);
    run.step.dependOn(b.getInstallStep());

    b.step("native", "Build native executable").dependOn(&exe.step);
    b.step("run", "Run the native executable").dependOn(&run.step);
}
