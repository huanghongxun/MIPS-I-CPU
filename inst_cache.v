`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: Sun Yat-sen University
// Engineer: Yuhui Huang
// 
// Create Date: 2018/05/25 00:13:18
// Design Name: Instruction Cache
// Module Name: inst_cache
// Project Name: SimpleCPU
// Target Devices: Basys3
// Tool Versions: Vivado 2018.1
// Description: 
//
//   physical address:
//   [group index | block index | block offset]
//         8             3             9
//
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module inst_cache#(
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 20, // main memory address width

    parameter BLOCKS_PER_GROUP_WIDTH = 1, // for n-way associative caching
    parameter BLOCK_OFFSET_WIDTH = 9, // width of address of a block
    parameter BLOCK_INDEX_WIDTH = 3,
    parameter GROUP_INDEX_WIDTH = ADDR_WIDTH - INDEX_WIDTH - BYTE_OFFSET_WIDTH, // Upper 13 bits of the physical address (the tag) are compared to the 13 bit tag field at that cache entry.
)(
    input clk,
    input rst_n,

    // request
    input valid,
    input [ADDR_WIDTH-1:0] addr,

    // data memory transaction
    input mem_valid_in,
    input mem_last,
    input [DATA_WIDTH-1:0] mem_data,
    output reg mem_valid_out,
    output reg [ADDR_WIDTH-1:0] mem_addr,
    
    // outputs
    output ready,
    output reg valid_out,
    output reg [DATA_WIDTH-1:] data
    );

    // constants
    localparam BLOCKS_PER_GROUP = 1<<BLOCKS_PER_GROUP_WIDTH;
    localparam BLOCK_OFFSET = 1<<BLOCK_OFFSET_WIDTH;
    localparam BLOCK_INDEX = 1<<BLOCK_INDEX_WIDTH;

    // variable
    integer i;

    // physical memory address parsing
    wire [GROUP_INDEX_WIDTH -1:0] group_index  = addr[ADDR_WIDTH-1:BLOCK_INDEX_WIDTH+BLOCK_OFFSET_WIDTH];
    wire [BLOCK_INDEX_WIDTH -1:0] block_index  = addr[BLOCK_INDEX_WIDTH+BLOCK_OFFSET_WIDTH-1:BLOCK_OFFSET_WIDTH];
    wire [BLOCK_OFFSET_WIDTH-1:0] block_offset = addr[BLOCK_OFFSET_WIDTH-1:0];
    reg [BLOCKS_PER_GROUP_WIDTH-1:0] location;

    // registers to save operands of synchronization
    reg [GROUP_INDEX_WIDTH -1:0] group_index_reg;
    reg [BLOCK_INDEX_WIDTH -1:0] block_index_reg;
    reg [BLOCK_OFFSET_WIDTH-1:0] block_offset_reg;
    reg [BLOCK_PER_GROUP_WIDTH-1:0] location;

    reg [BLOCK_OFFSET_WIDTH-1:0] write_cnt; // block offset that we are pulling from memory. We always pull a full block from memory per miss.

    // cache storage
    reg [GROUP_INDEX_WIDTH-1:0] tags[0:(1<<BLOCK_INDEX_WIDTH)-1][0:BLOCKS_PER_GROUP-1];
    reg [DATA_WIDTH-1:0] blocks[0:(1<<BLOCK_INDEX_WIDTH)-1][0:BLOCKS_PER_GROUP-1][0:BLOCK_OFFSET-1];
    reg is_valid[0:(1<<BLOCK_INDEX_WIDTH)-1][0:BLOCKS_PER_GROUP-1];

    reg [1:0] state;
    reg [1:0] next_state;

    localparam STATE_READY = 0;
    localparam STATE_MISS = 1;

    // determine which block is bound to the memory requested.
    always @*
    begin
        location <= 'bx;
        for (i = 0; i < BLOCKS_PER_GROUP; i = i + 1)
            if (tags[block_index][i] == group_index)
                location <= i;
    end

    always @*
    begin
        next_state <= state;
        valid_out <= 0;
        data <= 'bx;
        mem_vaild_out <= 0;
        mem_addr <= 'bx;

        case (state)
            STATE_READY: begin
                if (valid)
                begin
                    if (is_valid[block_index][location] && tags[block_index][location] == group_index)
                    begin
                        valid_out <= 1;

                        data <= blocks[block_index][location];
                    end
                    else
                    begin
                        next_state <= STATE_MISS;
                    end
                end
                else
                begin
                    // invalid request
                end
            end
            STATE_MISS: begin
                mem_valid_out <= 1;
                mem_addr <= {group_index_reg, block_index_reg, {BLOCK_OFFSET_WIDTH{1'b0}}};

                if (mem_valid_in)
                begin
                    // .
                    if (write_cnt == block_offset_reg)
                    begin
                        valid_out <= 1;
                        data <= mem_data;
                    end

                    // if we have finished transferring data from memory
                    if (mem_last)
                    begin
                        next_state <= STATE_READY;
                    end
                end
            end
        endcase
    end
      
    // Finite-state Machine
    always @(posedge clk, negedge rst_n)
    begin
        if (!rst_n)
        begin
            state <= STATE_READY;
        end
        else
        begin
            state <= next_state;

            case (state)
                STATE_READY: begin
                    if (next_state == STATE_MISS)
                    begin
                        write_cnt <= 0;

                        // record the data location we are going to pull from memory
                        block_offset_reg <= block_offset;
                        block_index_reg <= block_index;
                        group_index_reg <= group_index;
                        location_reg <= location;
                    end
                end
                STATE_MISS: begin
                    if (next_state == STATE_READY)
                    begin
                        // we have successfully finished pulling data from memory
                        tags[block_index_reg][location_reg] <= group_index_reg;
                        is_valid[block_index_reg][location_reg] <= 1;
                    end

                    // If we are pulling data from memory
                    if (mem_valid_in)
                    begin
                        write_cnt <= write_cnt + 1;
                        blocks[block_index_reg][location_reg][write_cnt] <= mem_data;
                    end
                end
            endcase
        end
    end
endmodule
