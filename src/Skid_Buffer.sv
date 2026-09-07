// ============================================================
// Skid_Buffer.sv
// Two-entry skid buffer: registered valid, registered data AND registered
// ready on the input side. Breaks every combinational path across a
// valid/ready boundary in both directions:
//   - out_* launch from o_*_r (clock-to-Q at the port)
//   - in_ready is a flop output (!s_valid_r), so the producer's pop
//     decision never sees out_ready in the same cycle
// Full throughput: with the consumer draining every cycle and the skid
// empty, o_*_r loads in_* every cycle. Latency +1 cycle.
//
// Discipline (Entry 29): only the two valid bits carry the reset; the
// payload registers free-run (load-enabled, no reset).
//
// iter21 experiment, 2026-09-07 - first use: the CPU response port in
// Response_Unit (was 4.67 ns of FWFT mux + select to the pins, and
// cpu_resp_ready gating both FIFO pops combinationally, on iter19b).
// ============================================================

module Skid_Buffer #(
    parameter int WIDTH = 32
)(
    input  logic             clk,
    input  logic             rst,

    input  logic             in_valid,
    output logic             in_ready,
    input  logic [WIDTH-1:0] in_data,

    output logic             out_valid,
    input  logic             out_ready,
    output logic [WIDTH-1:0] out_data
);

    logic             o_valid_r;
    logic [WIDTH-1:0] o_data_r;
    logic             s_valid_r;
    logic [WIDTH-1:0] s_data_r;

    logic in_fire;
    logic o_advance;

    assign in_ready  = !s_valid_r;
    assign in_fire   = in_valid && in_ready;

    // the output slot is free at this edge: consumed now, or empty
    assign o_advance = (o_valid_r && out_ready) || !o_valid_r;

    always_ff @(posedge clk) begin
        if (rst) begin
            o_valid_r <= 1'b0;
            s_valid_r <= 1'b0;
        end
        else begin
            if (o_advance) begin
                // skid first (older), else the live input beat.
                // in_fire is 0 whenever s_valid_r is 1 (in_ready = !s_valid_r),
                // so the two sources are never both live.
                o_valid_r <= s_valid_r || in_fire;
                s_valid_r <= 1'b0;
            end
            else if (in_fire) begin
                // output stalled holding data: the accepted beat parks here
                s_valid_r <= 1'b1;
            end
        end
    end

    always_ff @(posedge clk) begin
        if (o_advance) begin
            o_data_r <= s_valid_r ? s_data_r : in_data;
        end
        if (in_fire) begin
            s_data_r <= in_data;
        end
    end

    assign out_valid = o_valid_r;
    assign out_data  = o_data_r;

endmodule
