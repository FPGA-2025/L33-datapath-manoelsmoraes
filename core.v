module Core #(
    parameter BOOT_ADDRESS = 32'h00000000
)(
    input wire clk,
    input wire rst_n,

    output wire rd_en_o,
    output wire wr_en_o,
    input wire [31:0] data_i,
    output wire [31:0] addr_o,
    output wire [31:0] data_o
);

    // FSM states
    localparam FETCH     = 3'd0;
    localparam DECODE    = 3'd1;
    localparam EXECUTE   = 3'd2;
    localparam MEMORY    = 3'd3;
    localparam WRITEBACK = 3'd4;

    reg [2:0] state, next_state;

    // PC
    reg [31:0] PC;

    // Registers
    reg [31:0] IR;      // instruction register
    reg [31:0] A, B;    // registers A and B
    reg [31:0] ALUOut;

    // Banco de registradores 32x32 bits
    reg [31:0] registers [0:31];

    // ALU signals
    reg [31:0] alu_in1, alu_in2;
    reg [31:0] alu_result;
    reg alu_zero;

    // Controle
    reg pc_write;
    reg pc_write_cond;
    reg ir_write;
    reg reg_write;
    reg memory_read;
    reg memory_write;
    reg [1:0] pc_source;  // 00: ALU result (PC+4), 01: ALUOut (branch), 10: jump address
    reg lorD;
    reg memory_to_reg;
    reg is_immediate;
    reg [1:0] alu_src_a;
    reg [1:0] alu_src_b;
    reg [1:0] alu_op;

    reg reg_dst;
    reg [4:0] reg_dest;

    // Sinais de registradores para leitura
    wire [4:0] rs = IR[25:21];
    wire [4:0] rt = IR[20:16];
    wire [4:0] rd = IR[15:11];
    wire [15:0] imm = IR[15:0];
    wire [25:0] jump_addr = IR[25:0];

    // Extensão de imediato (sign extend)
    wire [31:0] imm_ext = {{16{imm[15]}}, imm};

    // Cálculo habilitação PC
    wire pc_enable = pc_write | (pc_write_cond & alu_zero);

    // Leitura dos registradores (combinacional)
    wire [31:0] reg_data_rs = registers[rs];
    wire [31:0] reg_data_rt = registers[rt];

    // Atribuições contínuas para barramento memória
    assign rd_en_o = memory_read;
    assign wr_en_o = memory_write;
    assign data_o = B;
    assign addr_o = lorD ? ALUOut : PC;

    // Atualiza PC
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            PC <= BOOT_ADDRESS;
        else if (pc_enable) begin
            case (pc_source)
                2'b00: PC <= alu_result;        // PC + 4
                2'b01: PC <= ALUOut;            // Branch target
                2'b10: PC <= {PC[31:28], jump_addr, 2'b00}; // Jump
                default: PC <= PC;
            endcase
        end
    end

    // Atualiza IR
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            IR <= 32'b0;
        else if (ir_write)
            IR <= data_i;
    end

    // Atualiza registradores A e B na fase DECODE
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            A <= 0;
            B <= 0;
        end else if (state == DECODE) begin
            A <= reg_data_rs;
            B <= reg_data_rt;
        end
    end

    // Atualiza ALUOut na fase EXECUTE
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            ALUOut <= 0;
        else if (state == EXECUTE)
            ALUOut <= alu_result;
    end

    // Banco de registradores: escrita no WRITEBACK
    always @(posedge clk or negedge rst_n) begin
        integer i;
        if (!rst_n) begin
            for (i=0; i<32; i=i+1)
                registers[i] <= 0;
        end else if (reg_write) begin
            registers[reg_dest] <= memory_to_reg ? data_i : ALUOut;
        end
    end

    // Atualiza reg_dst e reg_dest combinacionalmente
    always @(*) begin
        reg_dst = (IR[31:26] == 6'b000000); // R-type opcode
        reg_dest = reg_dst ? rd : rt;
    end

    // ALU operação
    always @(*) begin
        // Escolha ALU operand A
        case (alu_src_a)
            2'b00: alu_in1 = PC;
            2'b01: alu_in1 = A;
            2'b10: alu_in1 = B;
            default: alu_in1 = 0;
        endcase

        // Escolha ALU operand B
        case (alu_src_b)
            2'b00: alu_in2 = B;
            2'b01: alu_in2 = 32'd4;
            2'b10: alu_in2 = imm_ext;
            2'b11: alu_in2 = 32'd0;
            default: alu_in2 = 0;
        endcase

        // ALU operação
        case (alu_op)
            2'b00: alu_result = alu_in1 + alu_in2; // add
            2'b01: alu_result = alu_in1 - alu_in2; // sub
            default: alu_result = 0;
        endcase

        alu_zero = (alu_result == 0);
    end

    // FSM: próximo estado
    always @(*) begin
        case (state)
            FETCH: next_state = DECODE;
            DECODE: next_state = EXECUTE;
            EXECUTE: next_state = MEMORY;
            MEMORY: next_state = WRITEBACK;
            WRITEBACK: next_state = FETCH;
            default: next_state = FETCH;
        endcase
    end

    // FSM: atualização de estado
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            state <= FETCH;
        else
            state <= next_state;
    end

    // Controle simplificado dos sinais baseado no estado e opcode/funct
    always @(*) begin
        // resetando sinais
        pc_write       = 0;
        pc_write_cond  = 0;
        ir_write       = 0;
        reg_write      = 0;
        memory_read    = 0;
        memory_write   = 0;
        pc_source      = 2'b00;
        lorD           = 0;
        memory_to_reg  = 0;
        is_immediate   = 0;
        alu_src_a      = 2'b00;
        alu_src_b      = 2'b01;
        alu_op         = 2'b00;

        case (state)
            FETCH: begin
                pc_write = 1;
                ir_write = 1;
                memory_read = 1;
                pc_source = 2'b00;   // PC + 4
                alu_src_a = 2'b00;   // PC
                alu_src_b = 2'b01;   // 4
                alu_op = 2'b00;      // add
            end
            DECODE: begin
                // nada especial, só ler os registradores já feito
            end
            EXECUTE: begin
                // Exemplo para ADDI opcode (001000)
                if (IR[31:26] == 6'b001000) begin
                    alu_src_a = 2'b01; // A (rs)
                    alu_src_b = 2'b10; // imediato estendido
                    alu_op = 2'b00;    // add
                end else if (IR[31:26] == 6'b000000) begin
                    // R-type add (funct == 100000)
                    if (IR[5:0] == 6'b100000) begin
                        alu_src_a = 2'b01; // A
                        alu_src_b = 2'b00; // B
                        alu_op = 2'b00;    // add
                    end else if (IR[5:0] == 6'b100010) begin
                        alu_src_a = 2'b01; // A
                        alu_src_b = 2'b00; // B
                        alu_op = 2'b01;    // sub
                    end
                end else if (IR[31:26] == 6'b000100) begin // beq
                    alu_src_a = 2'b01;
                    alu_src_b = 2'b00;
                    alu_op = 2'b01;  // sub
                    pc_write_cond = 1;
                    pc_source = 2'b01; // branch target
                end else if (IR[31:26] == 6'b000010) begin // jump
                    pc_write = 1;
                    pc_source = 2'b10; // jump address
