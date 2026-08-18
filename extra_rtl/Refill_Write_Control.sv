module Refill_Write_Control #(
    parameter int ASSOC       = 4,
    parameter int LINE_WIDTH  = 128,
    parameter int TAG_WIDTH   = 16,
    parameter int FLAG_BITS   = 4,
    parameter int WAY_INDEX_W = 2
)(
    input  logic                      refill_valid,
    input  logic                      refill_write,
    input  logic [WAY_INDEX_W-1:0]    refill_way,
    input  logic [LINE_WIDTH-1:0]     refill_line,
    input  logic [TAG_WIDTH-1:0]      refill_tag,

    output logic [ASSOC-1:0]          data_wen,
    output logic [ASSOC-1:0]          tag_wen,
    output logic [ASSOC-1:0]          flag_wen,
    output logic [LINE_WIDTH-1:0]     data_wline [ASSOC],
    output logic [TAG_WIDTH-1:0]      tag_wdata  [ASSOC],
    output logic [FLAG_BITS-1:0]      flag_wdata [ASSOC]
);

    always_comb begin
        data_wen = '0;
        tag_wen  = '0;
        flag_wen = '0;

        for (int i = 0; i < ASSOC; i++) begin
            data_wline[i] = '0;
            tag_wdata[i]  = refill_tag;
            flag_wdata[i] = refill_write ? 4'b0011 : 4'b0001;
        end

        if (refill_valid) begin
            data_wen[refill_way]   = 1'b1;
            tag_wen[refill_way]    = 1'b1;
            flag_wen[refill_way]   = 1'b1;
            data_wline[refill_way] = refill_line;
        end
    end
    

endmodule