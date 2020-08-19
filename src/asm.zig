const std = @import("std");
const cpu = @import("./cpu.zig");

pub fn translate(allocator: *std.mem.Allocator, text: []const u8) ![]const u8 {
    var code = std.ArrayList(u8).init(allocator);
    errdefer code.deinit();

    var symbols = std.StringHashMap(u8).init(allocator);
    defer symbols.deinit();

    // A list of the symbol that should be written and the address in the code it is
    var to_replace_with_symbol = std.ArrayList(struct { symbol: []const u8, address: u8 }).init(allocator);
    defer to_replace_with_symbol.deinit();

    var line_iterator = std.mem.tokenize(text, "\n\r");
    var line_number: usize = 0;
    while (line_iterator.next()) |line_text| : (line_number += 1) {
        const line = try parse_line(line_text);
        if (line.label) |label| {
            const gop = try symbols.getOrPut(label);
            if (gop.found_existing) {
                std.log.err(.ASM, "Duplicate symbol \"{}\" on line {}", .{ label, line_number });
                return error.DuplicateSymbol;
            }
            gop.entry.value = @intCast(u8, code.items.len);
        }
        switch (line.data) {
            .Byte => |b| try code.append(b),
            .Data => |d| try code.appendSlice(d),
            .Instruction => |i| {
                if (i.instruction) |instruction| {
                    try code.append(@enumToInt(instruction));
                    if (instruction.number_operands() >= 1) {
                        const a = i.op_a orelse {
                            std.log.err(.ASM, "{} requires another parameter line {}", .{ instruction, line_number });
                            return error.NotEnoughParameters;
                        };
                        switch (a) {
                            .Byte => |b| try code.append(b),
                            .Register => |r| try code.append(r),
                            .Symbol => |s| {
                                try to_replace_with_symbol.append(.{
                                    .symbol = s,
                                    .address = @intCast(u8, code.items.len),
                                });
                                try code.append(undefined);
                            },
                        }
                    }
                    if (instruction.number_operands() == 2) {
                        const b = i.op_b orelse {
                            std.log.err(.ASM, "{} requires another parameter line {}", .{ instruction, line_number });
                            return error.NotEnoughParameters;
                        };
                        switch (b) {
                            .Byte => |byte| try code.append(byte),
                            .Register => |r| try code.append(r),
                            .Symbol => |s| {
                                try to_replace_with_symbol.append(.{
                                    .symbol = s,
                                    .address = @intCast(u8, code.items.len),
                                });
                                try code.append(undefined);
                            },
                        }
                    }
                }
            },
        }
    }

    for (to_replace_with_symbol.items) |replace_with_symbol| {
        if (symbols.get(replace_with_symbol.symbol)) |symbol_address| {
            code.items[replace_with_symbol.address] = symbol_address;
        } else {
            std.log.err(.ASM, "Symbol not found: {}", .{replace_with_symbol.symbol});
            return error.SymbolNotFound;
        }
    }

    return code.toOwnedSlice();
}

const Line = struct {
    label: ?[]const u8 = null,
    data: union(enum) {
        Instruction: InstructionLine,
        Data: []const u8,
        Byte: u8,
    },
};

const InstructionLine = struct {
    instruction: ?cpu.Instruction = null,
    op_a: ?Param = null,
    op_b: ?Param = null,
};

const Param = union(enum) {
    Symbol: []const u8,
    Register: u3,
    Byte: u8,
};

fn parse_line(text: []const u8) !Line {
    var comment_start = std.mem.indexOfAny(u8, text, ";#") orelse text.len;
    var parts = std.mem.tokenize(text[0..comment_start], " \t,");
    var line: Line = undefined;
    var instruction_line = InstructionLine{};

    var state: u8 = 0;
    while (parts.next()) |part| {
        switch (state) {
            0 => if (std.mem.endsWith(u8, part, ":")) {
                const first_colon = std.mem.indexOf(u8, part, ":") orelse unreachable;
                line.label = part[0..first_colon];
                state = 1;
            } else if (std.ascii.eqlIgnoreCase(part, "ds")) {
                line.data = .{ .Data = parts.rest() };
                return line;
            } else if (std.ascii.eqlIgnoreCase(part, "db")) {
                const data = std.fmt.trim(parts.rest());

                line.data = .{ .Byte = try parse_int_literal(data) };

                return line;
            } else {
                instruction_line.instruction = cpu.Instruction.parse(part) orelse {
                    std.log.err(.ASM, "Unexpected symbol: '{}'", .{part});
                    return error.ExpectedInstructionName;
                };
                state = 2;
            },
            1 => if (std.ascii.eqlIgnoreCase(part, "ds")) {
                line.data = .{ .Data = parts.rest() };
                return line;
            } else if (std.ascii.eqlIgnoreCase(part, "db")) {
                const data = std.fmt.trim(parts.rest());

                line.data = .{ .Byte = try parse_int_literal(data) };

                return line;
            } else {
                instruction_line.instruction = cpu.Instruction.parse(part) orelse {
                    std.log.err(.ASM, "Unexpected symbol: '{}'", .{part});
                    return error.ExpectedInstructionName;
                };
                state = 2;
            },
            2 => {
                instruction_line.op_a = try parse_param(part);
                state = 3;
            },
            3 => {
                instruction_line.op_b = try parse_param(part);
                state = 4;
            },
            else => {
                std.log.err(.ASM, "Unexpected symbol: {}", .{part});
                return error.UnexpectedSymbol;
            },
        }
    }

    line.data = .{ .Instruction = instruction_line };
    return line;
}

fn parse_param(text: []const u8) !Param {
    if (text.len == 2 and std.ascii.toLower(text[0]) == 'r' and std.ascii.isDigit(text[1]) and text[1] <= '7') {
        const num = try std.fmt.parseInt(u3, text[1..2], 8);
        return Param{ .Register = num };
    } else if (std.ascii.isDigit(text[0])) {
        const num = try parse_int_literal(text);
        return Param{ .Byte = num };
    } else {
        return Param{ .Symbol = text };
    }
}

fn parse_int_literal(text: []const u8) !u8 {
    return if (std.mem.startsWith(u8, text, "0x"))
        try std.fmt.parseInt(u8, text[2..], 16)
    else if (std.mem.startsWith(u8, text, "0b"))
        try std.fmt.parseInt(u8, text[2..], 2)
    else
        try std.fmt.parseInt(u8, text, 10);
}
