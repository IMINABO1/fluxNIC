`default_nettype none

// Synchronous FIFO with first-word-fall-through reads: when not empty, rd_data
// already shows the head word, and asserting rd_en pops it on the next edge.
// DEPTH must be a power of two.
module sync_fifo #(
    parameter int WIDTH = 8,
    parameter int DEPTH = 16
) (
    input  var logic                   clk,
    input  var logic                   rst_n,

    input  var logic                   wr_en,
    input  var logic [WIDTH-1:0]       wr_data,
    output var logic                   full,

    input  var logic                   rd_en,
    output var logic [WIDTH-1:0]       rd_data,
    output var logic                   empty,

    output var logic [$clog2(DEPTH):0] count
);

    localparam int AW = $clog2(DEPTH);

    logic [WIDTH-1:0] mem [DEPTH];
    logic [AW:0]      wr_ptr;
    logic [AW:0]      rd_ptr;

    logic do_wr;
    logic do_rd;
    assign do_wr = wr_en && !full;
    assign do_rd = rd_en && !empty;

    assign empty   = (wr_ptr == rd_ptr);
    assign full    = (wr_ptr[AW] != rd_ptr[AW]) && (wr_ptr[AW-1:0] == rd_ptr[AW-1:0]);
    assign count   = wr_ptr - rd_ptr;
    assign rd_data = mem[rd_ptr[AW-1:0]];

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            wr_ptr <= '0;
            rd_ptr <= '0;
        end else begin
            if (do_wr) begin
                mem[wr_ptr[AW-1:0]] <= wr_data;
                wr_ptr <= wr_ptr + 1'b1;
            end
            if (do_rd) begin
                rd_ptr <= rd_ptr + 1'b1;
            end
        end
    end

`ifdef FORMAL
    always_comb begin
        assert (count <= DEPTH);
        assert (!(full && empty));
    end
`endif

endmodule

`default_nettype wire
