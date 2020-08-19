const std = @import("std");

pub const Instruction = enum(u8) {
    /// Perform no operation
    NOP = 0b00000000,

    /// Halt execution
    HLT = 0b00000001,

    /// Add
    ADD = 0b10100000,

    /// Add
    SUB = 0b10100001,

    /// Divide
    DIV = 0b10100011,

    /// Multiply
    MUL = 0b10100010,

    /// Modulus
    MOD = 0b10100100,

    /// Bitwise AND
    AND = 0b10101000,

    /// Bitwise NOT
    NOT = 0b01101001,

    /// Bitwise OR
    OR = 0b10101010,

    /// Bitwise XOR
    XOR = 0b10101011,

    /// Shift the bits in registerA registerB left
    SHL = 0b10101100,

    /// Shift the bits in registerA registerB right
    SHR = 0b10101101,

    /// Call subroutine
    CALL = 0b01010000,

    /// Return from subroutine
    RET = 0b00010001,

    /// Pop value off of the stack and into the given register
    POP = 0b01000110,

    /// Push value from given register onto the stack
    PUSH = 0b01000101,

    /// If equal flag is set, jump to the given address
    JMP = 0b01010100,

    /// Compare
    CMP = 0b10100111,

    /// If equal flag is set, jump to the given address
    JEQ = 0b01010101,

    /// If equal flag is not set, jump to the given address
    JNE = 0b01010110,

    /// If greater than flag or the equal flag are set, jump to the given address
    JGE = 0b01011010,

    /// If greater than flag is set, jump to the given address
    JGT = 0b01010111,

    /// If less than flag or the equal flag are set, jump to the given address
    JLE = 0b01011001,

    /// If less than flag is set, jump to the given address
    JLT = 0b01011000,

    /// Loads the data into registerA from the address in registerB
    LD = 0b10000011,

    /// Stores the data in registerB to the address in registerA
    ST = 0b10000100,

    /// Set registerA to the immediate value
    LDI = 0b10000010,

    /// Decrement
    DEC = 0b01100110,

    /// Increment
    INC = 0b01100101,

    /// Run an interrupt
    INT = 0b01010010,

    /// Return from an interrupt handler
    IRET = 0b00010011,

    /// Print the register as an ASCII value
    PRA = 0b01001000,

    /// Print the register as a number
    PRN = 0b01000111,

    pub const OperandType = enum {
        None,
        Immediate,
        Register,
    };

    pub fn number_operands(this: @This()) u2 {
        const val = @enumToInt(this);
        return @intCast(u2, (0b11000000 & val) >> 6);
    }

    pub fn alu_instruction(this: @This()) bool {
        const val = @enumToInt(this);
        return (0b00100000 & val) != 0;
    }

    pub fn sets_program_counter(this: @This()) bool {
        const val = @enumToInt(this);
        return (0b00010000 & val) != 0;
    }

    pub fn operand_types(this: @This()) [2]OperandType {
        return switch (this) {
            .NOP => .{ .None, .None },
            .HLT => .{ .None, .None },
            .ADD => .{ .Register, .Register },
            .SUB => .{ .Register, .Register },
            .DIV => .{ .Register, .Register },
            .MUL => .{ .Register, .Register },
            .MOD => .{ .Register, .Register },
            .AND => .{ .Register, .Register },
            .NOT => .{ .Register, .None },
            .OR => .{ .Register, .Register },
            .XOR => .{ .Register, .Register },
            .SHL => .{ .Register, .Register },
            .SHR => .{ .Register, .Register },
            .CALL => .{ .Register, .None },
            .RET => .{ .None, .None },
            .POP => .{ .Register, .None },
            .PUSH => .{ .Register, .None },
            .JMP => .{ .Register, .None },
            .CMP => .{ .Register, .Register },
            .JEQ => .{ .Register, .None },
            .JNE => .{ .Register, .None },
            .JGE => .{ .Register, .None },
            .JGT => .{ .Register, .None },
            .JLE => .{ .Register, .None },
            .JLT => .{ .Register, .None },
            .LD => .{ .Register, .Register },
            .ST => .{ .Register, .Register },
            .LDI => .{ .Register, .Immediate },
            .DEC => .{ .Register, .None },
            .INC => .{ .Register, .None },
            .INT => .{ .Register, .None },
            .IRET => .{ .None, .None },
            .PRA => .{ .Register, .None },
            .PRN => .{ .Register, .None },
        };
    }

    pub fn decode(val: u8) !@This() {
        return switch (val) {
            @enumToInt(@This().NOP) => .NOP,
            @enumToInt(@This().HLT) => .HLT,
            @enumToInt(@This().ADD) => .ADD,
            @enumToInt(@This().MUL) => .MUL,
            @enumToInt(@This().INC) => .INC,
            @enumToInt(@This().DEC) => .DEC,
            @enumToInt(@This().CALL) => .CALL,
            @enumToInt(@This().RET) => .RET,
            @enumToInt(@This().PUSH) => .PUSH,
            @enumToInt(@This().POP) => .POP,
            @enumToInt(@This().CMP) => .CMP,
            @enumToInt(@This().JMP) => .JMP,
            @enumToInt(@This().JEQ) => .JEQ,
            @enumToInt(@This().JNE) => .JNE,
            @enumToInt(@This().JGT) => .JGT,
            @enumToInt(@This().ST) => .ST,
            @enumToInt(@This().LD) => .LD,
            @enumToInt(@This().LDI) => .LDI,
            @enumToInt(@This().PRN) => .PRN,
            @enumToInt(@This().PRA) => .PRA,
            @enumToInt(@This().INT) => .INT,
            @enumToInt(@This().IRET) => .IRET,
            else => error.InvalidInstruction,
        };
    }

    pub fn parse(text: []const u8) ?@This() {
        const type_info = @typeInfo(@This());
        inline for (type_info.Enum.fields) |field| {
            if (std.ascii.eqlIgnoreCase(field.name, text)) {
                return @field(@This(), field.name);
            }
        }
        return null;
    }
};
