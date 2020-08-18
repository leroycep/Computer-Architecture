const std = @import("std");

/// Our CPU's memory size is 256, and the end of the space is for the stack and misc other stuff
const MAX_FILE_SIZE = 240;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(!gpa.deinit());
    const allocator = &gpa.allocator;

    if (std.os.argv.len != 2) {
        std.log.err(.LS8ToBin, "Incorrect usage. Correct usage:\n\n\t{} ./<filename>.ls8.bin", .{std.os.argv[0]});
        std.os.exit(1);
    }

    // Get the input filepath
    const filename_len = std.mem.len(std.os.argv[1]);
    const filename = std.os.argv[1][0..filename_len];

    // Get the contents of the input file
    const cwd = std.fs.cwd();
    const program = try cwd.readFileAlloc(allocator, filename, MAX_FILE_SIZE);
    defer allocator.free(program);

    // Initialize CPU
    var cpu = Cpu.init(allocator);

    // Load program into memory
    std.mem.copy(u8, &cpu.memory, program);

    try cpu.run();
}

pub const Cpu = struct {
    allocator: *std.mem.Allocator,
    memory: [256]u8,
    registers: [8]u8,

    /// Address of the currently executing instruction
    program_counter: u8,

    /// Contains a copy of the currently executing instruction
    instruction_register: u8,

    /// The memory address we're reading or writing
    memory_address_register: u8,

    /// The data to write or the value just read from memory
    memory_data_register: u8,

    /// How two numbers compared to each other
    flags: packed struct {
        less_than: bool,
        greater_than: bool,
        equal: bool,
    },

    interrupts_enabled: bool,

    last_timer_interrupt: std.time.Timer,

    /// Which register holds the Interrupt Mask
    pub const IM = 5;

    /// Which register holds the Interrupt Status
    pub const IS = 6;

    /// Which register holds the Stack Pointer
    pub const SP = 7;

    /// The initial value of the stack register
    pub const MEM_ADDR_KEY_PRESSED = 0xF4;

    /// The initial value of the stack register
    pub const STACK_INIT = 0xF3;

    /// The base address of the interrupt handlers in memory
    pub const INTERRUPT_VECTORS_BASE = 0xF8;

    /// The interrupt number that the 1 second timer calls
    pub const TIMER_INTERRUPT = 0;

    /// The interrupt number that key presses call
    pub const KEYBOARD_INTERRUPT = 1;

    pub fn init(allocator: *std.mem.Allocator) @This() {
        var registers = [_]u8{0} ** 8;
        registers[SP] = STACK_INIT;

        return .{
            .allocator = allocator,
            // Initialize ram to 0
            .memory = [_]u8{0} ** 256,
            .registers = registers,
            .program_counter = 0,
            .instruction_register = 0,
            .memory_address_register = 0,
            .memory_data_register = 0,
            .flags = .{
                .less_than = false,
                .greater_than = false,
                .equal = false,
            },
            .interrupts_enabled = true,
            .last_timer_interrupt = undefined,
        };
    }

    pub fn push_stack(this: *@This(), value: u8) void {
        _ = @subWithOverflow(u8, this.registers[SP], 1, &this.registers[SP]);
        this.memory[this.registers[SP]] = value;
    }

    pub fn pop_stack(this: *@This()) u8 {
        defer _ = @addWithOverflow(u8, this.registers[SP], 1, &this.registers[SP]);
        return this.memory[this.registers[SP]];
    }

    pub fn interrupt(this: *@This(), num: u3) void {
        if (!this.interrupts_enabled) return;
        const check_mask = @as(u8, 1) << num;
        if (check_mask & this.registers[IM] == check_mask) {
            this.interrupts_enabled = false;

            // Clear every status bit except for the one being called
            this.registers[IS] = 0;
            this.registers[IS] |= check_mask;

            this.push_stack(this.program_counter);
            this.push_stack(@bitCast(u3, this.flags));
            this.push_stack(this.registers[0]);
            this.push_stack(this.registers[1]);
            this.push_stack(this.registers[2]);
            this.push_stack(this.registers[3]);
            this.push_stack(this.registers[4]);
            this.push_stack(this.registers[5]);
            this.push_stack(this.registers[6]);

            const handler_address = this.memory[INTERRUPT_VECTORS_BASE + @as(u8, num)];
            this.program_counter = handler_address;
        }
    }

    pub fn interrupt_return(this: *@This()) !void {
        // If interrupts_enabled is true, IRET was called outside of an Interrupt
        if (this.interrupts_enabled) return error.InterruptReturnOutsideInterrupt;

        // Clear every status bit except for the one being called
        this.registers[IS] = 0;

        this.registers[6] = this.pop_stack();
        this.registers[5] = this.pop_stack();
        this.registers[4] = this.pop_stack();
        this.registers[3] = this.pop_stack();
        this.registers[2] = this.pop_stack();
        this.registers[1] = this.pop_stack();
        this.registers[0] = this.pop_stack();

        const flag_val = this.pop_stack();
        if (flag_val & 0b00000111 != flag_val) {
            return error.InterruptReturnInvalidFlagsValue;
        }
        this.flags = @bitCast(@TypeOf(this.flags), @intCast(u3, flag_val));

        this.program_counter = this.pop_stack();

        this.interrupts_enabled = true;
    }

    pub fn run(this: *@This()) !void {
        const stdout = std.io.getStdOut().writer();
        this.last_timer_interrupt = try std.time.Timer.start();

        var is_running = true;

        var keyboard_input_queue = std.atomic.Queue(KeyboardInputThread.Error!u8).init();

        const keyboard_input_context = KeyboardInputThread{
            .allocator = this.allocator,
            .is_running = &is_running,
            .key_queue = &keyboard_input_queue,
        };
        const keyboard_input_thread = try std.Thread.spawn(keyboard_input_context, KeyboardInputThread.run);
        defer {
            is_running = false;
            keyboard_input_thread.wait();
        }

        while (true) {
            // Check timer interrupt
            if (this.interrupts_enabled) {
                if (this.last_timer_interrupt.read() >= 1 * std.time.ns_per_s) {
                    this.last_timer_interrupt.reset();
                    this.interrupt(TIMER_INTERRUPT);
                }
                if (keyboard_input_queue.get()) |node| {
                    defer this.allocator.destroy(node);
                    const key = node.data catch |e| switch (e) {
                        error.EndOfStream => break,
                        else => |ue| return ue,
                    };
                    this.memory[MEM_ADDR_KEY_PRESSED] = key;
                    this.interrupt(KEYBOARD_INTERRUPT);
                }
            }

            const instruction = Instruction.decode(this.memory[this.program_counter]) catch |e| switch (e) {
                error.InvalidInstruction => {
                    std.log.err(.CPU, "Invalid instruction {b:0>8}", .{this.memory[this.program_counter]});
                    return e;
                },
            };
            // If we didn't jump we need to increment the program counter like normal
            var did_not_jump = false;
            switch (instruction) {
                .NOP => {},
                .HLT => break,
                .ADD => {
                    const a = this.memory[this.program_counter + 1];
                    const b = this.memory[this.program_counter + 2];
                    _ = @addWithOverflow(u8, this.registers[a], this.registers[b], &this.registers[a]);
                },
                .SUB => {
                    const a = this.memory[this.program_counter + 1];
                    const b = this.memory[this.program_counter + 2];
                    _ = @subWithOverflow(u8, this.registers[a], this.registers[b], &this.registers[a]);
                },
                .MUL => {
                    const a = this.memory[this.program_counter + 1];
                    const b = this.memory[this.program_counter + 2];
                    _ = @mulWithOverflow(u8, this.registers[a], this.registers[b], &this.registers[a]);
                },
                .DIV => {
                    const a = this.memory[this.program_counter + 1];
                    const b = this.memory[this.program_counter + 2];
                    this.registers[a] /= this.registers[b];
                },
                .MOD => {
                    const a = this.memory[this.program_counter + 1];
                    const b = this.memory[this.program_counter + 2];
                    this.registers[a] %= this.registers[b];
                },
                .INC => {
                    const register = this.memory[this.program_counter + 1];
                    _ = @addWithOverflow(u8, this.registers[register], 1, &this.registers[register]);
                },
                .DEC => {
                    const register = this.memory[this.program_counter + 1];
                    _ = @subWithOverflow(u8, this.registers[register], 1, &this.registers[register]);
                },
                .AND => {
                    const a = this.memory[this.program_counter + 1];
                    const b = this.memory[this.program_counter + 2];
                    this.registers[a] = this.registers[a] & this.registers[b];
                },
                .NOT => {
                    const a = this.memory[this.program_counter + 1];
                    this.registers[a] = ~this.registers[a];
                },
                .OR => {
                    const a = this.memory[this.program_counter + 1];
                    const b = this.memory[this.program_counter + 2];
                    this.registers[a] = this.registers[a] | this.registers[b];
                },
                .XOR => {
                    const a = this.memory[this.program_counter + 1];
                    const b = this.memory[this.program_counter + 2];
                    this.registers[a] = this.registers[a] ^ this.registers[b];
                },
                .SHL => {
                    const a = this.memory[this.program_counter + 1];
                    const b = this.memory[this.program_counter + 2];
                    if (this.registers[b] >= 8) {
                        this.registers[a] = 0;
                    } else {
                        this.registers[a] <<= @intCast(u3, this.registers[b]);
                    }
                },
                .SHR => {
                    const a = this.memory[this.program_counter + 1];
                    const b = this.memory[this.program_counter + 2];
                    if (this.registers[b] >= 8) {
                        this.registers[a] = 0;
                    } else {
                        this.registers[a] >>= @intCast(u3, this.registers[b]);
                    }
                },
                .ST => {
                    const registerA = this.memory[this.program_counter + 1];
                    const registerB = this.memory[this.program_counter + 2];
                    this.memory[this.registers[registerA]] = this.registers[registerB];
                },
                .LD => {
                    const registerA = this.memory[this.program_counter + 1];
                    const registerB = this.memory[this.program_counter + 2];
                    this.registers[registerA] = this.memory[this.registers[registerB]];
                },
                .LDI => {
                    const register = this.memory[this.program_counter + 1];
                    const immediate = this.memory[this.program_counter + 2];
                    this.registers[register] = immediate;
                },
                .PRN => {
                    const register = this.memory[this.program_counter + 1];
                    const value = this.registers[register];
                    try stdout.print("{}", .{value});
                },
                .PRA => {
                    const register = this.memory[this.program_counter + 1];
                    const value = this.registers[register];
                    _ = try stdout.write(&[_]u8{value});
                },
                .PUSH => {
                    const register = this.memory[this.program_counter + 1];
                    this.push_stack(this.registers[register]);
                },
                .POP => {
                    const register = this.memory[this.program_counter + 1];
                    this.registers[register] = this.pop_stack();
                },
                .CALL => {
                    const register = this.memory[this.program_counter + 1];

                    var return_address: u8 = 0;
                    _ = @addWithOverflow(u8, this.program_counter, instruction.number_operands() + 1, &return_address);
                    this.push_stack(return_address);

                    this.program_counter = this.registers[register];
                },
                .RET => this.program_counter = this.pop_stack(),
                .JMP => {
                    const jump_address = this.registers[this.memory[this.program_counter + 1]];
                    this.program_counter = jump_address;
                },
                .CMP => {
                    const a = this.memory[this.program_counter + 1];
                    const b = this.memory[this.program_counter + 2];
                    this.flags.greater_than = this.registers[a] > this.registers[b];
                    this.flags.equal = this.registers[a] == this.registers[b];
                    this.flags.less_than = this.registers[a] < this.registers[b];
                },
                .JEQ => if (this.flags.equal) {
                    const jump_address = this.registers[this.memory[this.program_counter + 1]];
                    this.program_counter = jump_address;
                } else {
                    did_not_jump = true;
                },
                .JNE => if (!this.flags.equal) {
                    const jump_address = this.registers[this.memory[this.program_counter + 1]];
                    this.program_counter = jump_address;
                } else {
                    did_not_jump = true;
                },
                .JGE => if (this.flags.greater_than or this.flags.equal) {
                    const jump_address = this.registers[this.memory[this.program_counter + 1]];
                    this.program_counter = jump_address;
                } else {
                    did_not_jump = true;
                },
                .JGT => if (this.flags.greater_than) {
                    const jump_address = this.registers[this.memory[this.program_counter + 1]];
                    this.program_counter = jump_address;
                } else {
                    did_not_jump = true;
                },
                .JLE => if (this.flags.less_than or this.flags.equal) {
                    const jump_address = this.registers[this.memory[this.program_counter + 1]];
                    this.program_counter = jump_address;
                } else {
                    did_not_jump = true;
                },
                .JLT => if (this.flags.less_than) {
                    const jump_address = this.registers[this.memory[this.program_counter + 1]];
                    this.program_counter = jump_address;
                } else {
                    did_not_jump = true;
                },
                .INT => {
                    const register = this.memory[this.program_counter + 1];
                    this.interrupt(@intCast(u3, this.registers[register]));
                },
                .IRET => try this.interrupt_return(),
            }
            if (!instruction.sets_program_counter() or did_not_jump) {
                var result: u8 = 0;
                const did_overflow = @addWithOverflow(u8, this.program_counter, instruction.number_operands() + 1, &result);
                this.program_counter = result;
            }
        }
    }
};

const KeyboardInputThread = struct {
    allocator: *std.mem.Allocator,

    /// Whether the main thread is still running
    is_running: *bool,

    /// Whether a key was pressed
    key_queue: *std.atomic.Queue(Error!u8),

    pub const Error = std.fs.File.ReadError || error{EndOfStream};

    pub fn run(this: @This()) void {
        const stdin = std.io.getStdIn().reader();
        while (this.is_running.*) {
            const node = this.allocator.create(std.atomic.Queue(Error!u8).Node) catch |e| {
                std.log.err(.KeyboardInputThread, "Keyboard input thread is out of memory!", .{});
                return;
            };
            const byte = stdin.readByte() catch |e| {
                node.* = .{
                    .prev = undefined,
                    .next = undefined,
                    .data = e,
                };
                this.key_queue.put(node);
                return;
            };
            node.* = .{
                .prev = undefined,
                .next = undefined,
                .data = byte,
            };
            this.key_queue.put(node);
        }
        while (this.key_queue.get()) |node| {
            defer this.allocator.destroy(node);
        }
    }
};

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
