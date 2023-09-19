module writeback_cache #( 
    parameter cache_line_size=16, //the the number of bytes in a cache line
    parameter cache_line_count=128, //the number of cache lines in the cache
    parameter cache_associativity=4, //the number of possible locations for any given address. must be a power of 2
    parameter cache_max_stall; //how large the latency can get on either port before it must be processed

    parameter user_word_size=4, //the number of bytes the user will be reading at once. must be a power of 2

    parameter backing_store_latency=3, //latency of the backing store in cycles(CAS latency if this is DRAM)
    parameter backing_store_word_size=2, //the word size in bytes of the backing store
    parameter backing_store_word_count=2**25, //number of words in the backing store
    parameter backing_store_burst_amount=8, //number of words per burst
    parameter backing_store_slow_msbs=10, //how many MSBs of the backing store are considered slow(bank and row address bits for DRAM)
    
    parameter clock_crossing=0, //how many clock crossing flip flops to generate when working with the backing store
    parameter backing_store_fifo_capacity=128, //how many fifo words are needed 

    localparam address_space_width = $clog2(backing_store_word_count*backing_store_word_size), //the width of the byte address space
    localparam alignment_bits_width = $clog2(user_word_size),
    localparam associativity_lsb = $clog2(cache_line_size),
    localparam associativity_msb = associativity_lsb + $clog2(cache_line_count) - $clog2(cache_associativity),
    localparam associativity_bit_count = associativity_msb - associativity_lsb,
    localparam associativity_bins = cache_line_count/cache_associativity,
    localparam cache_tag_lsb = $clog2(cache_line_size) + associativity_bit_count,
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
    input logic port_clk, backing_clk,
    // handles communication with the memory users on ports a and b
    input logic [address_space_width-1:0] address_port_a, address_port_b, //specified user word address
    input logic re_port_a, re_port_b, we_port_a, we_port_b, //onehot enable signals
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
    input logic invalidate, invalidate_all,
    input logic [address_space_width-1:0] invalidation_addr

    //handles communication with sync logic
    input logic sync, sync_all,
    input logic [address_space_width-1:0] sync_addr
    );
    //permanent signals
    logic [7:0][cache_line_size-1:0] cache_memory [cache_line_count];
    logic cache_dirty_table [cache_line_count]; 
    logic dirty_line_exists
    logic cache_invalid_table [cache_line_count];
    logic [cache_tag_width-1:0] cache_index_table [associativity_bins][cache_associativity]; //first one is pretty easily addressed, the second one is walked
    logic [$clog2(cache_associativity)-1:0] cache_eviction_score [associativity_bins][cache_associativity]; //the lower the score the more likely a cache line is to be evicted
    logic [$clog2(cache_max_stall)-1:0] cycles_stalled_port_a, cycles_stalled_port_a;
    logic cache_line_locked [associativity_bins][cache_associativity];
    logic 

    //this FSM runs in the port clock domain
    enum logic [2:0]{
        RESET,
        READY, // port user can keep issuing reads/writes and expect data to appear
        WAIT, // port user must stall until FSM returns to READY
    } PORT_A_STATE, PORT_A_STATE_NEXT, PORT_B_STATE, PORT_B_STATE_NEXT;

    //this FSM runs in the backing clock domain
    enum logic [9:0]{
        RESET, //clears all information
        IDLE, 
        SYNC,
        SYNC_ALL, 
        INVALIDATE,
        INVALIDATE_ALL,
        PORT_A_READ_READY,
        PORT_A_READ_WAIT,
        PORT_B_READ_READY,
        PORT_B_READ_WAIT,
        PORT_A_WRITE_READY,
        PORT_A_WRITE_WAIT,
        PORT_B_WRITE_READY,
        PORT_B_WRITE_WAIT        
    } BACKING_STORE_STATE, BACKING_STORE_STATE_NEXT;

    always_ff @ (posedge port_clk) begin
        if(reset==1'b1) begin
            
        end
    end

endmodule