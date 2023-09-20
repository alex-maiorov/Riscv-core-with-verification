package memory_control_interfaces
typedef enum logic [0:6]{
    MEMORY_READY, //data is available
    MEMORY_WAIT, //wait until data is available
    MEMORY_ERROR_OUT_OF_BOUNDS, //the requested address was outside of the address space bounds
    MEMORY_ERROR_MISALIGNED, //the requested byte address was not aligned to the word size
    MEMORY_ERROR_READONLY, //the address requested cannot be written to
    MEMORY_ERROR_DUAL_WRITE, //the users tried to write to the same address at the same time. Defined to cause no changes. 
    MEMORY_ERROR_WRITEONLY, //the address requested cannot be read from
} memory_status_t;
endpackage


module two_clock_fifo #(
    parameter word_size=16,
    parameter word_count=128, //must be a power of 2
    parameter pipelining=3, //pipelining of the underlying SRAM. can be 2,3 or 4, corresponding to the latency in clock cycles
    parameter clockcrossers=2, //how many flip flops between different clock domains when it comes to crossing the read and write clock domains
    // 0 can be used for when the read and write clock are the same. 
    // 1 can be used when the clocks are the same but out of phase with a known offset
    // 2 can be used for different clock frequencies
    // 3 can be used for maximum metastability protection
    
    localparam counter_bits = $clog2(word_count)

)(  
    input logic rclk, wclk, reset,
    input logic r,w,
    output logic full, empty, 
    input logic [word_size-1:0] wdata,
    output logic [word_size-1:0] rdata,
);
    logic [counter_bits:0] rcounter, wcounter;
    logic [counter_bits:0] rcounter_write_clockdomain, wcounter_read_clockdomain;
    genvar crosser_index;
    generate
        if(clockcrossers < 0) begin
            $error("two_clock_fifo: There cannot be less than 0 clock crossers")
        end
        if(clockcrossers == 0) begin
            assign rcounter_write_clockdomain = rcounter;
            assign rcounter_write_clockdomain = rcounter;
        end
        else if(clockcrossers == 1) begin
            logic [counter_bits:0] rcounter_to_write_clockdomain;
            logic [counter_bits:0] wcounter_to_read_clockdomain;
            assign wcounter_read_clockdomain = wcounter_to_read_clockdomain;
            assign rcounter_write_clockdomain = rcounter_to_write_clockdomain;
            always_ff @ (posedge rclk) begin
                wcounter_to_read_clockdomain <= wcounter;
            end

            always_ff @ (posedge wclk) begin
                for(i=0; i<clockcrossers-1; i++) begin
                    rcounter_to_write_clockdomain <= rcounter;
                end
            end
        end
        else begin
            logic [counter_bits:0] rcounter_to_write_clockdomain [clockcrossers];
            logic [counter_bits:0] rcounter_to_write_clockdomain [clockcrossers];
            assign wcounter_read_clockdomain = wcounter_to_read_clockdomain[clockcrossers-1];
            assign rcounter_write_clockdomain = rcounter_to_write_clockdomain[clockcrossers-1];
            always_ff @ (posedge wclk) begin
                for(crosser_index=0; crosser_index<clockcrossers-1; crosser_index++) begin
                    rcounter_to_write_clockdomain [crosser_index+1] <= rcounter_to_write_clockdomain [crosser_index];
                end
                rcounter_to_write_clockdomain[0] <= rcounter;
            end

            always_ff @ (posedge rclk) begin
                for(crosser_index=0; crosser_index<clockcrossers-1; crosser_index++) begin
                    wcounter_to_read_clockdomain [crosser_index+1] <= wcounter_to_read_clockdomain [crosser_index];
                end
                wcounter_to_read_clockdomain[0] <= wcounter;
            end
        end
    endgenerate
    //port a is the read port, port b is the write port
    assign empty = ((wcounter - rcounter - clockcrossers)) <= 0;
    assign full = ((wcounter - rcounter + clockcrossers)) >= word_count;
    two_port_ram #(.word_size(word_size), .word_count(word_count), .pipelining(pipelining)) 
    two_port_ram_fifo_inst (.clk_a(rclk), .clk_b(wclk), .reset(reset), 
    .address_port_a(rcounter), .address_port_b(wcounter),
    .we_port_a(1'b0), .we_port_b(w), 
    .rdata_port_a(rdata), .wdata_port_b(wdata));
endmodule
 
module two_port_ram #(
    parameter pipelining=3, 
    parameter word_size=8,
    parameter word_count=256
)(
    input logic clk_a, clk_b, reset,
    input logic [$clog2(word_count)-1:0] address_port_a, address_port_b,
    input logic we_port_a, we_port_a,
    output logic [word_size-1:0] rdata_port_a, rdata_port_b,
    input logic [word_size-1:0] wdata_port_a, wdata_port_b,
);
    logic [word_size-1:0] ram_data [word_count];
    generate
        if(pipelining == 2) begin
            always_ff @ (posedge clk_a) begin
                case (we_port_a)
                    1'b0: rdata_port_a <= ram_data[address_port_a];
                    1'b1: ram_data[address_port_a] <= wdata_port_a;
                    default: rdata_port_a <= {word_size{1'bX}};
                endcase
            end
            always_ff @ (posedge clk_b) begin
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
            always_ff @ (posedge clk_a) begin
                case (we_port_a_latch)
                    1'b0: rdata_port_a <= ram_data[address_port_a_latch];
                    1'b1: ram_data[address_port_a_latch] <= wdata_port_a_latch;
                    default: rdata_port_a <= {word_size{1'bX}};
                endcase
                we_port_a_latch <= we_port_a;
                address_port_a_latch <= address_port_a;
                wdata_port_a_latch <= wdata_port_a;
                if(reset == 1'b1) begin
                    we_port_a_latch <= 1'b0;
                    address_port_a_latch <= 0;
                    wdata_port_a_latch <= 0;
                end
            end
            always_ff @ (posedge clk_b) begin
                case (we_port_b_latch)
                    1'b0: rdata_port_b <= ram_data[address_port_b_latch];
                    1'b1: ram_data[address_port_b_latch] <= wdata_port_b_latch;
                    default: rdata_port_b <= {word_size{1'bX}};
                endcase
                we_port_b_latch <= we_port_b;
                address_port_b_latch <= address_port_b;
                wdata_port_b_latch <= wdata_port_b;
                if(reset == 1'b1) begin
                    we_port_b_latch <= 1'b0;
                    address_port_b_latch <= 0;
                    wdata_port_b_latch <= 0;
                end
            end
        end
        else if(pipelining == 4) begin
            logic we_port_a_latch, we_port_b_latch;
            logic [word_size-1:0] wdata_port_a_latch, wdata_port_b_latch;
            logic [$clog2(word_count)-1:0] address_port_a_latch, address_port_b_latch;
            logic [word_size-1:0] rdata_port_a_latch, rdata_port_b_latch;
            always_ff @ (posedge clk_a) begin
                rdata_port_a <= rdata_port_a_latch;
                case (we_port_a_latch)
                    1'b0: rdata_port_a_latch <= ram_data[address_port_a_latch];
                    1'b1: ram_data[address_port_a_latch] <= wdata_port_a_latch;
                    default: rdata_port_a_latch <= {word_size{1'bX}};
                endcase
                we_port_a_latch <= we_port_a;
                address_port_a_latch <= address_port_a;
                wdata_port_a_latch <= wdata_port_a;
                if(reset == 1'b1) begin
                    we_port_a_latch <= 1'b0;
                    address_port_a_latch <= 0;
                    wdata_port_a_latch <= 0;
                    rdata_port_a_latch <= 0;
                end
            end
            always_ff @ (posedge clk_b) begin
                rdata_port_b <= rdata_port_b_latch;
                case (we_port_b_latch)
                    1'b0: rdata_port_b_latch <= ram_data[address_port_b_latch];
                    1'b1: ram_data[address_port_b_latch] <= wdata_port_b_latch;
                    default: rdata_port_b_latch <= {word_size{1'bX}};
                endcase
                we_port_b_latch <= we_port_b;
                address_port_b_latch <= address_port_b;
                wdata_port_b_latch <= wdata_port_b;
                if(reset == 1'b1) begin
                    we_port_b_latch <= 1'b0;
                    address_port_b_latch <= 0;
                    wdata_port_b_latch <= 0;
                    rdata_port_b_latch <= 0;
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