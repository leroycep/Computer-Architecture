"""CPU functionality."""

import sys

NOP = 0b00000000
HLT = 0b00000001
ADD = 0b10100000
SUB = 0b10100001
DIV = 0b10100011
MUL = 0b10100010
MOD = 0b10100100
AND = 0b10101000
NOT = 0b01101001
OR = 0b10101010
XOR = 0b10101011
SHL = 0b10101100
SHR = 0b10101101
CALL = 0b01010000
RET = 0b00010001
POP = 0b01000110
PUSH = 0b01000101
JMP = 0b01010100
CMP = 0b10100111
JEQ = 0b01010101
JNE = 0b01010110
JGE = 0b01011010
JGT = 0b01010111
JLE = 0b01011001
JLT = 0b01011000
LD = 0b10000011
ST = 0b10000100
LDI = 0b10000010
DEC = 0b01100110
INC = 0b01100101
INT = 0b01010010
IRET = 0b00010011
PRA = 0b01001000
PRN = 0b01000111


class CPU:
    """Main CPU class."""

    def __init__(self):
        """Construct a new CPU."""
        self.ram = [0] * 256
        self.reg = [0] * 8
        self.pc = 0
        self.running = True

        self.instruction_table = {}
        self.instruction_table[NOP] = self.op_nop
        self.instruction_table[HLT] = self.op_hlt
        self.instruction_table[ADD] = self.op_add
        self.instruction_table[SUB] = self.unimplemented_op
        self.instruction_table[DIV] = self.unimplemented_op
        self.instruction_table[MUL] = self.unimplemented_op
        self.instruction_table[MOD] = self.unimplemented_op
        self.instruction_table[AND] = self.unimplemented_op
        self.instruction_table[NOT] = self.unimplemented_op
        self.instruction_table[OR] = self.unimplemented_op
        self.instruction_table[XOR] = self.unimplemented_op
        self.instruction_table[SHL] = self.unimplemented_op
        self.instruction_table[SHR] = self.unimplemented_op
        self.instruction_table[CALL] = self.unimplemented_op
        self.instruction_table[RET] = self.unimplemented_op
        self.instruction_table[POP] = self.unimplemented_op
        self.instruction_table[PUSH] = self.unimplemented_op
        self.instruction_table[JMP] = self.unimplemented_op
        self.instruction_table[CMP] = self.unimplemented_op
        self.instruction_table[JEQ] = self.unimplemented_op
        self.instruction_table[JNE] = self.unimplemented_op
        self.instruction_table[JGE] = self.unimplemented_op
        self.instruction_table[JGT] = self.unimplemented_op
        self.instruction_table[JLE] = self.unimplemented_op
        self.instruction_table[JLT] = self.unimplemented_op
        self.instruction_table[LD] = self.unimplemented_op
        self.instruction_table[ST] = self.unimplemented_op
        self.instruction_table[LDI] = self.op_ldi
        self.instruction_table[DEC] = self.unimplemented_op
        self.instruction_table[INC] = self.unimplemented_op
        self.instruction_table[INT] = self.unimplemented_op
        self.instruction_table[IRET] = self.unimplemented_op
        self.instruction_table[PRA] = self.unimplemented_op
        self.instruction_table[PRN] = self.op_prn

    def load(self, filepath):
        """Load a program into memory."""

        program = []
        with open(filepath) as f:
            for line in f.readlines():
                comment_start = line.find("#")
                #if comment_start == -1:
                #    comment_start = len(line)
                without_comment = line[:comment_start]
                clean_line = without_comment.strip()

                if clean_line == "":
                    continue

                program.append(int(clean_line, 2))

        address = 0
        for instruction in program:
            self.ram[address] = instruction
            address += 1

    def trace(self):
        """
        Handy function to print out the CPU state. You might want to call this
        from run() if you need help debugging.
        """

        print(f"TRACE: %02X | %02X %02X %02X |" % (
            self.pc,
            # self.fl,
            # self.ie,
            self.ram_read(self.pc),
            self.ram_read(self.pc + 1),
            self.ram_read(self.pc + 2)
        ), end='')

        for i in range(8):
            print(" %02X" % self.reg[i], end='')

        print()

    def run(self):
        """Run the CPU."""
        while self.running:
            op = self.ram[self.pc]
            a = self.ram[self.pc + 1]
            b = self.ram[self.pc + 2]

            op_size = (0b11000000 & op) >> 6
            is_alu = ((0b00100000 & op) >> 5) == 1
            sets_pc = ((0b00010000 & op) >> 4) == 1

            if op in self.instruction_table:
                self.instruction_table[op](op, a, b)
            else:
                raise Exception(f"Invalid opcode at {self.pc:02x}: {op:08b}")

            if is_alu:
                # Keep numbers in 0xFF range
                self.reg[a] &= 0xFF

            if not sets_pc:
                self.pc += 1 + op_size

    def unimplemented_op(self, op, a, b):
        raise Exception(f"Unimplemented opcode {op:08b}")

    def op_ldi(self, op, reg_a, reg_b):
        self.reg[reg_a] = reg_b

    def op_add(self, op, reg_a, reg_b):
        self.reg[reg_a] += self.reg[reg_b]

    def op_prn(self, op, reg_a, reg_b):
        print(f"{self.reg[reg_a]:d}", end="")

    def op_nop(self, op, reg_a, reg_b):
        pass

    def op_hlt(self, op, reg_a, reg_b):
        self.running = False
