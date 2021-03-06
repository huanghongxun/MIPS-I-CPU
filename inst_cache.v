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
//   physical address(width 32):
//   [group index | block index | block offset | 00]
//         22            3             5         2
//
//   2KB instruction cache
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
//     See https://en.wikipedia.org/wiki/CPU_cache
//////////////////////////////////////////////////////////////////////////////////

`include "defines.v"

module inst_cache#(
    parameter DATA_WIDTH = 32,
    parameter DATA_PER_BYTE_WIDTH = 2, // $clog2(DATA_WIDTH/8)

    parameter ASSO_WIDTH = 1, // for n-way associative caching
    parameter BLOCK_OFFSET_WIDTH = 5, // width of address of a block
    parameter INDEX_WIDTH = 3,
    parameter TAG_WIDTH = DATA_WIDTH - INDEX_WIDTH - BLOCK_OFFSET_WIDTH - DATA_PER_BYTE_WIDTH // Upper 22 bits of the physical address (the tag) are compared to the 22 bit tag field at that cache entry.
)(
    input clk,
    input rst_n,

    // request
    input [`DATA_BUS] addr, // lowest 2 bits are assumed 2'b00.
    input enable, // 1 if we are requesting data
    
    // outputs
    output ready,
    output reg [`DATA_BUS] data,
    output reg data_valid,

    // BRAM transaction
    output reg [`DATA_BUS] mem_addr,
    output reg mem_enable,

    input [`DATA_BUS] mem_read,
    input mem_read_valid,
    
    input mem_last
    );

    // constants
    localparam ASSOCIATIVITY = 1 << ASSO_WIDTH;
    localparam BLOCK_SIZE = 1 << BLOCK_OFFSET_WIDTH;
    localparam INDEX_SIZE = 1 << INDEX_WIDTH;

    // states
    localparam STATE_READY = 0;
    localparam STATE_MISS = 1;

    // variable
    integer i, j, k;

    reg [1:0] state;
    reg [1:0] next_state;

    // physical memory address parsing.
    wire [TAG_WIDTH         -1:0] tag  = addr[DATA_WIDTH-1:INDEX_WIDTH+BLOCK_OFFSET_WIDTH+DATA_PER_BYTE_WIDTH];
    wire [INDEX_WIDTH       -1:0] block_index  = addr[INDEX_WIDTH+BLOCK_OFFSET_WIDTH+DATA_PER_BYTE_WIDTH-1:BLOCK_OFFSET_WIDTH+DATA_PER_BYTE_WIDTH];
    wire [BLOCK_OFFSET_WIDTH-1:0] block_offset = addr[BLOCK_OFFSET_WIDTH+DATA_PER_BYTE_WIDTH-1:DATA_PER_BYTE_WIDTH];
    reg  [ASSO_WIDTH        -1:0] location;

    // registers to save operands of synchronization
    reg  [TAG_WIDTH         -1:0] tag_reg;
    reg  [INDEX_WIDTH       -1:0] block_index_reg;
    reg  [BLOCK_OFFSET_WIDTH-1:0] block_offset_reg;
    reg  [ASSO_WIDTH        -1:0] location_reg;

    reg [BLOCK_OFFSET_WIDTH-1:0] write_cnt; // block offset that we are pulling from memory. We always pull a full block from memory per miss.

    // cache storage
    reg [ASSO_WIDTH-1:0] timestamp[0:INDEX_SIZE-1][0:ASSOCIATIVITY-1]; // the visit order
    reg [TAG_WIDTH-1:0] tags[0:INDEX_SIZE-1][0:ASSOCIATIVITY-1]; // which group in memory
    reg [`DATA_BUS] blocks[0:INDEX_SIZE-1][0:ASSOCIATIVITY-1][0:BLOCK_SIZE-1]; // cached blocks
    reg valid[0:INDEX_SIZE-1][0:ASSOCIATIVITY-1]; // true if this cache space has stored a block.

    assign ready = state == STATE_READY;
    
    localparam LOCATION_X = {ASSO_WIDTH{1'bx}};
    localparam TAG_X = {TAG_WIDTH{1'bx}};

    // determine which block is bound to the memory requested.
    always @*
    begin
        location = LOCATION_X;
        // check if we have already loaded the block of data
        for (i = 0; i < ASSOCIATIVITY; i = i + 1)
            if (tags[block_index][i] == tag)
                location = i;
        if (location === LOCATION_X)
            // check if empty space to cache data
            for (i = 0; i < ASSOCIATIVITY; i = i + 1)
                if (tags[block_index][i] === TAG_X)
                    location = i;
        if (location === LOCATION_X) // LRU
            // if no block available, we choose the block unvisited for the longest time.
            for (i = 0; i < ASSOCIATIVITY; i = i + 1)
                if (timestamp[block_index][i] == {ASSO_WIDTH{1'b1}})
                    location = i;
        
        // location should not be 'bx now
    end

    always @*
    begin
        next_state <= state;
        data_valid <= 0;
        data <= 'bx;
        mem_enable <= 0;
        mem_addr <= 'bx;

        case (state)
            STATE_READY: begin
                if (enable)
                begin
                    if (valid[block_index][location] && tags[block_index][location] == tag)
                    begin
                        data_valid <= 1;

                        data <= blocks[block_index][location][block_offset];
                        
                        timestamp[block_index][location] <= 0;
                        for (i = 0; i < ASSOCIATIVITY; i = i + 1)
                            if (timestamp[block_index][i] < timestamp[block_index][location])
                                timestamp[block_index][i] <= timestamp[block_index][i] + 1;
                    end
                    else
                    begin
`ifdef DEBUG_INST
                        $display("Inst cache miss on addr %x", addr);
`endif

                        next_state <= STATE_MISS;
                    end
                end
                else
                begin
                    // invalid request
                end
            end
            STATE_MISS: begin
                // start requesting data operation
                mem_enable <= 1;

                // We must figure out that BRAM address format is equal to cache here
                // if your BRAM data width is 8-bit(a byte), you should append 2'b00 to LSB as 1 word consits of 4 bytes.
                mem_addr <= {tag_reg, block_index_reg, {BLOCK_OFFSET_WIDTH{1'b0}}, {DATA_PER_BYTE_WIDTH{1'b0}}};

                if (mem_read_valid)
                begin
                    // .
                    if (write_cnt == block_offset_reg)
                    begin
                        data_valid <= 1;
                        data <= mem_read;
                    end

                    // if we have finished transferring data from memory
                    if (mem_last)
                    begin
                        next_state <= STATE_READY;
                                            
                        timestamp[block_index_reg][location_reg] <= 0;
                        for (i = 0; i < ASSOCIATIVITY; i = i + 1)
                            if (timestamp[block_index_reg][i] < timestamp[block_index_reg][location_reg])
                                timestamp[block_index_reg][i] <= timestamp[block_index_reg][i] + 1;
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
            write_cnt <= 0;
            block_offset_reg <= 0;
            block_index_reg <= 0;
            tag_reg <= 0;
            location_reg <= 0;
            
            for (i = 0; i < INDEX_SIZE; i = i + 1)
                for (j = 0; j < ASSOCIATIVITY; j = j + 1)
                begin
                    tags[i][j] <= TAG_X;
                    valid[i][j] <= 0;
                    timestamp[i][j] <= j;
                    for (k = 0; k < BLOCK_SIZE; k = k + 1)
                        blocks[i][j][k] <= 0;
                end
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
                        tag_reg <= tag;
                        location_reg <= location;
                    end
                end
                STATE_MISS: begin
                    if (next_state == STATE_READY)
                    begin
                        // we have successfully finished pulling data from memory
                        tags[block_index_reg][location_reg] <= tag_reg;
                        valid[block_index_reg][location_reg] <= 1;
                    end

                    // If we are pulling data from memory
                    if (mem_read_valid)
                    begin
                        write_cnt <= write_cnt + 1;
                        blocks[block_index_reg][location_reg][write_cnt] <= mem_read;
                    end
                end
            endcase
        end
    end
endmodule
