const std = @import("std");
const sep_str = std.fs.path.sep_str;

const SITE_DIR = "www";

pub fn build(b: *std.build.Builder) void {
    // Set up native binary
    const exe = b.addExecutable("ls8", "src/main.zig");
    exe.install();
    b.getInstallStep().dependOn(&exe.step);

    const run = exe.run();
    const asm_file = b.option([]const u8, "asm-file", "The asm file that should be passed to the executable") orelse "asm/print8.asm";
    run.addArg(asm_file);
    run.step.dependOn(b.getInstallStep());

    b.step("native", "Build native executable").dependOn(&exe.step);
    b.step("run", "Run the native executable").dependOn(&run.step);

    // Set up wasm target
    const wasm = b.addStaticLibrary("ls8-web", "src/web.zig");
    wasm.addPackage(.{
        .name = "zee_alloc",
        .path = "./zee_alloc/src/main.zig",
    });

    const wasmOutDir = b.fmt("{}" ++ sep_str ++ SITE_DIR, .{b.install_prefix});
    wasm.setOutputDir(wasmOutDir);
    wasm.setBuildMode(b.standardReleaseOptions());
    wasm.setTarget(.{
        .cpu_arch = .wasm32,
        .os_tag = .freestanding,
    });

    const wwwInstall = b.addInstallDirectory(.{
        .source_dir = "www",
        .install_dir = .Prefix,
        .install_subdir = SITE_DIR,
    });

    wasm.step.dependOn(&wwwInstall.step);

    b.step("wasm", "Build WASM binary").dependOn(&wasm.step);
}
