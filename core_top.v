module core_top #(
    parameter MEMORY_FILE = ""
)(
    input  wire clk,
    input  wire rst_n
);

    // Sinais de conexão entre Core e Memória
    wire rd_en;
    wire wr_en;
    wire [31:0] addr;
    wire [31:0] data_i_mem; // dados que vêm da memória para o Core
    wire [31:0] data_o_mem; // dados que vão do Core para a memória

    // Instancia Core
    Core #(
        .BOOT_ADDRESS(32'h00000000)
    ) core_inst (
        .clk(clk),
        .rst_n(rst_n),
        .rd_en_o(rd_en),
        .wr_en_i(wr_en),
        .data_i(data_i_mem),
        .addr_o(addr),
        .data_o(data_o_mem)
    );

    // Instancia Memória com nome 'mem'
    Memory #(
        .MEMORY_FILE(MEMORY_FILE),
        .MEMORY_SIZE(4096)
    ) mem (
        .clk(clk),
        .rd_en_i(rd_en),
        .wr_en_i(wr_en),
        .addr_i(addr),
        .data_i(data_o_mem),
        .data_o(data_i_mem),
        .ack_o()  // não usado
    );

endmodule
