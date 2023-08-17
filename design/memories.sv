typedef enum logic [0:5]{
    MEMORY_ACCESS_OK, //data is available
    MEMORY_WAIT_READY, //wait until data is available
    MEMORY_ERROR_OUT_OF_BOUNDS, //the requested address was outside of the address space bounds
    MEMORY_ERROR_MISALIGNED, //the requested byte address was not aligned to the word size
    MEMORY_ERROR_READONLY, //the address requested cannot be written to
    MEMORY_ERROR_WRITEONLY, //the address requested cannot be read from
} memory_status_t;

module writeback_cache #( 
    parameter cache_line_size=16, //the the number of bytes in a cache line
    parameter cache_line_count=128, //the number of cache lines in the cache
    parameter cache_associativity=4, //the number of possible locations for any given address. must be a power of 2

    parameter user_word_size=4, //the number of bytes the user will be reading at once. must be a power of 2

    parameter backing_store_latency=3, //latency of the backing store in cycles(CAS latency if this is DRAM)
    parameter backing_store_word_size=2, //the word size in bytes of the backing store
    parameter backing_store_word_count=2**25, //number of words in the backing store
    parameter backing_store_burst_amount=8, //number of words per burst

    localparam address_space_width = $clog2(backing_store_word_count*backing_store_word_size), //the width of the byte address space
    localparam alignment_bits_width = $clog2(user_word_size),
    localparam associativity_lsb = $clog2(cache_line_size),
    localparam associativity_msb = associativity_lsb + $clog2(cache_line_count) - $clog2(cache_associativity),
    localparam associativity_bin_count = associativity_msb - associativity_lsb,
    localparam cache_tag_lsb = $clog2(cache_line_size) + associativity_bin_count,
    localparam cache_tag_msb = address_space_width - 1,
    localparam cache_tag_width = cache_tag_msb - cache_tag_lsb,
    localparam max_address = backing_store_word_count*backing_store_word_size-1
    )(
    generate
        if(cache_associativity < 1'b1 || cache_associativity > cache_line_count) begin
            $error("Cache associativity must be between 1 and the cache line count")
        end
    endgenerate
    //reset and clock
    input logic reset,
    input logic clk,
    // handles communication with the memory users on ports a and b
    input logic [address_space_width-1:0] address_port_a, address_port_b, //specified user word address
    input logic we_port_a, we_port_b, //high if writing, low if reading
    output memory_status_t status_port_a, status_port_a, //status enum
    output logic [8*user_word_size-1:0] rdata_port_a, rdata_port_b,
    input logic [8*user_word_size-1:0] wdata_port_a, wdata_port_b,
    input logic [user_word_size-1:0]  write_byte_mask_port_a, write_byte_mask_port_b,

    //handles communication with backing store
    output logic [$clog2(backing_store_word_count)-1:0] backing_store_address,
    output logic backing_store_we,
    input logic backing_store_drdy,
    input logic [8*backing_store_word_size-1:0] backing_store_rdata,
    output logic [8*backing_store_word_size-1:0] backing_store_wdata,

    //handles communication with synchronization logic
    input logic invalidate,
    input logic [address_space_width-1:0] invalidation_addr
    );

    logic [7:0][cache_line_size-1:0] cache_memory [cache_line_count];
    logic cache_dirty_table [cache_line_count]; 
    logic cache_invalid_table [cache_line_count];
    logic [cache_tag_width-1:0] cache_index_table [associativity_bin_count][];
    

endmodule

module two_port_ram #(
    parameter pipelining=3, 
    parameter word_size=8,
    parameter word_count=256
)(
    input logic clk, reset,
    input logic [$clog2(word_count)-1:0] address_port_a, address_port_b,
    input logic we_port_a, we_port_a,
    output logic [word_size-1:0] rdata_port_a, rdata_port_b,
    input logic [word_size-1:0] wdata_port_a, wdata_port_b,
);
    logic [word_size-1:0] ram_data [word_count];
    generate
        if(pipelining == 2) begin
            always_ff @ (posedge clk) begin
                case (we_port_a)
                    1'b0: rdata_port_a <= ram_data[address_port_a];
                    1'b1: ram_data[address_port_a] <= wdata_port_a;
                    default: rdata_port_a <= {word_size{1'bX}};
                endcase

                case (we_port_b)
                    1'b0: rdata_port_b <= ram_data[address_port_b];
                    1'b1: ram_data[address_port_b] <= wdata_port_b;
                    default: rdata_port_b <= {word_size{1'bX}};
                endcase
            end
        end
        else if(pipelining == 3) begin
            logic we_port_a_latch, we_port_b_latch;
            logic [word_size-1:0] wdata_port_a_latch, wdata_port_b_latch;
            logic [$clog2(word_count)-1:0] address_port_a_latch, address_port_b_latch;
            always_ff @ (posedge clk) begin
                case (we_port_a_latch)
                    1'b0: rdata_port_a <= ram_data[address_port_a_latch];
                    1'b1: ram_data[address_port_a_latch] <= wdata_port_a_latch;
                    default: rdata_port_a <= {word_size{1'bX}};
                endcase

                case (we_port_b_latch)
                    1'b0: rdata_port_b <= ram_data[address_port_b_latch];
                    1'b1: ram_data[address_port_b_latch] <= wdata_port_b_latch;
                    default: rdata_port_b <= {word_size{1'bX}};
                endcase

                we_port_a_latch <= we_port_a;
                we_port_b_latch <= we_port_b;
                address_port_a_latch <= address_port_a;
                address_port_b_latch <= address_port_b;
                wdata_port_a_latch <= wdata_port_a;
                wdata_port_b_latch <= wdata_port_b;
                if(reset == 1'b1) begin
                    we_port_a_latch <= 1'b0;
                    we_port_b_latch <= 1'b0;
                    address_port_a_latch <= 0;
                    address_port_b_latch <= 0;
                    wdata_port_a_latch <= 0;
                    wdata_port_b_latch <= 0;
                end
            end
        end
        else if(pipelining == 4) begin
            logic we_port_a_latch, we_port_b_latch;
            logic [word_size-1:0] wdata_port_a_latch, wdata_port_b_latch;
            logic [$clog2(word_count)-1:0] address_port_a_latch, address_port_b_latch;
            logic [word_size-1:0] rdata_port_a_latch, rdata_port_b_latch;
            always_ff @ (posedge clk) begin
                rdata_port_a <= rdata_port_a_latch;
                rdata_port_b <= rdata_port_b_latch;
                case (we_port_a_latch)
                    1'b0: rdata_port_a_latch <= ram_data[address_port_a_latch];
                    1'b1: ram_data[address_port_a_latch] <= wdata_port_a_latch;
                    default: rdata_port_a_latch <= {word_size{1'bX}};
                endcase

                case (we_port_b_latch)
                    1'b0: rdata_port_b_latch <= ram_data[address_port_b_latch];
                    1'b1: ram_data[address_port_b_latch] <= wdata_port_b_latch;
                    default: rdata_port_b_latch <= {word_size{1'bX}};
                endcase

                we_port_a_latch <= we_port_a;
                we_port_b_latch <= we_port_b;
                address_port_a_latch <= address_port_a;
                address_port_b_latch <= address_port_b;
                wdata_port_a_latch <= wdata_port_a;
                wdata_port_b_latch <= wdata_port_b;
                if(reset == 1'b1) begin
                    we_port_a_latch <= 1'b0;
                    we_port_b_latch <= 1'b0;
                    address_port_a_latch <= 0;
                    address_port_b_latch <= 0;
                    wdata_port_a_latch <= 0;
                    wdata_port_b_latch <= 0;
                end
            end
        end
        else begin
            $error("Invalid Pipelining Value for module two_port_ram. Valid options are 2, 3 and 4")
            assign rdata_port_a = {word_size{1'bX}};
            assign rdata_port_b = {word_size{1'bX}};
        end
    endgenerate
    


endmodule