const std = @import("std");
const builtin = @import("builtin");
const Instruction = @import("./instruction.zig").Instruction;
const log = std.log.scoped(.emulator);

const DEFAULT_FREQUENCY = 1000000;

pub fn Cpu(comptime R: type, comptime W: type) type {
    return struct {
        input: R,
        output: W,
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

        last_timer_interrupt: usize,
        cycles: usize,
        frequency: usize,

        halted: bool,

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

        pub fn init(input: R, output: W) @This() {
            var registers = [_]u8{0} ** 8;
            registers[SP] = STACK_INIT;

            return .{
                .input = input,
                .output = output,
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
                .last_timer_interrupt = 0,
                .cycles = 0,
                .frequency = DEFAULT_FREQUENCY,
                .halted = false,
            };
        }

        pub fn push_stack(this: *@This(), value: u8) void {
            this.registers[SP] -%= 1;
            this.memory[this.registers[SP]] = value;
        }

        pub fn pop_stack(this: *@This()) u8 {
            defer this.registers[SP] +%= 1;
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
                const flags_val = @intCast(u8, @bitCast(u3, this.flags));
                this.push_stack(@as(u8, 0b00000111) & flags_val);
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
                log.err("interrupt return invalid flags value: {b:0>8}", .{flag_val});
                return error.InterruptReturnInvalidFlagsValue;
            }
            this.flags = @bitCast(@TypeOf(this.flags), @intCast(u3, flag_val));

            this.program_counter = this.pop_stack();

            this.interrupts_enabled = true;
        }

        pub fn step(this: *@This()) !void {
            defer this.cycles += 1;
            // Check timer interrupt
            if (this.interrupts_enabled) {
                if (this.cycles >= this.last_timer_interrupt +% this.frequency) {
                    this.last_timer_interrupt = this.cycles;
                    this.interrupt(TIMER_INTERRUPT);
                }
                if (this.input.readByte()) |byte| {
                    this.memory[MEM_ADDR_KEY_PRESSED] = byte;
                    this.interrupt(KEYBOARD_INTERRUPT);
                } else |err| switch (err) {
                    error.WouldBlock, error.EndOfStream => {},
                    else => |e| return e,
                }
            }

            const instruction = Instruction.decode(this.memory[this.program_counter]) catch |e| switch (e) {
                error.InvalidInstruction => {
                    log.err("Invalid instruction {b:0>8}", .{this.memory[this.program_counter]});
                    return e;
                },
            };
            // If we didn't jump we need to increment the program counter like normal
            var did_not_jump = false;
            switch (instruction) {
                .NOP => {},
                .HLT => this.halted = true,
                .ADD => {
                    const a = this.memory[this.program_counter + 1];
                    const b = this.memory[this.program_counter + 2];
                    this.registers[a] +%= this.registers[b];
                },
                .SUB => {
                    const a = this.memory[this.program_counter + 1];
                    const b = this.memory[this.program_counter + 2];
                    this.registers[a] -%= this.registers[b];
                },
                .MUL => {
                    const a = this.memory[this.program_counter + 1];
                    const b = this.memory[this.program_counter + 2];
                    this.registers[a] *%= this.registers[b];
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
                    this.registers[register] +%= 1;
                },
                .DEC => {
                    const register = this.memory[this.program_counter + 1];
                    this.registers[register] -%= 1;
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
                    try this.output.print("{}", .{value});
                },
                .PRA => {
                    const register = this.memory[this.program_counter + 1];
                    const value = this.registers[register];
                    _ = try this.output.write(&[_]u8{value});
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

                    var return_address: u8 = this.program_counter +% instruction.number_operands() + 1;
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
                this.program_counter +%= instruction.number_operands() + 1;
            }
        }
    };
}
