// ============================================================
// Downstream RAM with request/response ID tracking
// 32-bit word memory, word-addressed interface
// Response ID matches MSHR ID, not CPU request ID
//
// Reset behavior:
//   - Reloads INIT_FILE on reset so every test starts from a
//     clean downstream memory image.
//   - Clears pending read-response pipeline state.
// ============================================================

module RAM_ID #(
    parameter int ADDR_WIDTH   = 32,
    parameter int D_WIDTH      = 32,
    parameter int DEPTH        = 1024,
    parameter int ID_WIDTH     = 2,
    parameter int READ_LATENCY = 20,
    parameter string INIT_FILE = "downstream_init.hex"
)(
    input  logic                    clk,
    input  logic                    rst,

    input  logic                    req_valid,
    input  logic                    req_write,
    input  logic [ADDR_WIDTH-1:0]   req_addr,
    input  logic [D_WIDTH-1:0]      req_wdata,
    input  logic [ID_WIDTH-1:0]     req_id,

    output logic                    resp_valid,
    input  logic                    resp_ready,
    output logic [D_WIDTH-1:0]      resp_rdata,
    output logic [ID_WIDTH-1:0]     resp_id
);

    localparam int WORD_ADDR_W = $clog2(DEPTH);

    logic [D_WIDTH-1:0] mem [0:DEPTH-1];
    string init_file_path;

    logic [WORD_ADDR_W-1:0] word_addr;

    // Cache sends word addresses, not byte addresses.
    assign word_addr = req_addr[WORD_ADDR_W-1:0];

    function automatic string resolve_init_file;
        int fd;
        string candidates [0:5];
        begin
            candidates[0] = INIT_FILE;
            candidates[1] = "../Verification/downstream_init.hex";
            candidates[2] = "../../Verification/downstream_init.hex";
            candidates[3] = "Verification/downstream_init.hex";
            candidates[4] = "../downstream_init.hex";
            candidates[5] = "../../downstream_init.hex";

            resolve_init_file = INIT_FILE;

            for (int i = 0; i < 6; i++) begin
                fd = $fopen(candidates[i], "r");

                if (fd != 0) begin
                    $fclose(fd);
                    resolve_init_file = candidates[i];
                    return resolve_init_file;
                end
            end
        end
    endfunction

    task automatic init_memory;
        begin
            for (int i = 0; i < DEPTH; i++) begin
                mem[i] = D_WIDTH'(32'h1000_0000 + i);
            end

            $readmemh(init_file_path, mem);
        end
    endtask

    initial begin
        init_file_path = resolve_init_file();
        $display("RAM_ID loading init file: %s", init_file_path);
        init_memory();
    end

    logic [READ_LATENCY:0] valid_pipe;
    logic [ID_WIDTH-1:0]   id_pipe   [0:READ_LATENCY];
    logic [D_WIDTH-1:0]    data_pipe [0:READ_LATENCY];

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            // Reload RAM contents on every reset so each test is isolated.
            init_memory();

            valid_pipe <= '0;

            for (int i = 0; i <= READ_LATENCY; i++) begin
                id_pipe[i]   <= '0;
                data_pipe[i] <= '0;
            end
        end
        else begin
            valid_pipe[0] <= req_valid && !req_write;
            id_pipe[0]    <= req_id;
            data_pipe[0]  <= mem[word_addr];

            if (req_valid && req_write) begin
                mem[word_addr] <= req_wdata;
            end

            for (int i = 1; i <= READ_LATENCY; i++) begin
                valid_pipe[i] <= valid_pipe[i-1];
                id_pipe[i]    <= id_pipe[i-1];
                data_pipe[i]  <= data_pipe[i-1];
            end
        end
    end

    assign resp_valid = valid_pipe[READ_LATENCY];
    assign resp_id    = id_pipe[READ_LATENCY];
    assign resp_rdata = data_pipe[READ_LATENCY];

endmodule
