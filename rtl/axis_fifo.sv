`default_nettype none

// AXI-Stream FIFO: buffers whole stream words (tdata + tkeep + tlast) by packing
// them into one sync_fifo. First-word-fall-through, so m_tvalid/m_tdata present
// the head with no read latency. DEPTH must be a power of two.
module axis_fifo #(
    parameter int DATA_W = 64,
    parameter int DEPTH  = 512
) (
    input  var logic                     clk,
    input  var logic                     rst_n,

    input  var logic [DATA_W-1:0]        s_tdata,
    input  var logic [DATA_W/8-1:0]      s_tkeep,
    input  var logic                     s_tlast,
    input  var logic                     s_tvalid,
    output var logic                     s_tready,

    output var logic [DATA_W-1:0]        m_tdata,
    output var logic [DATA_W/8-1:0]      m_tkeep,
    output var logic                     m_tlast,
    output var logic                     m_tvalid,
    input  var logic                     m_tready,

    output var logic [$clog2(DEPTH):0]   count
);

    localparam int KEEP_W  = DATA_W / 8;
    localparam int PAY_W   = DATA_W + KEEP_W + 1;

    logic [PAY_W-1:0] wr_pay;
    logic [PAY_W-1:0] rd_pay;
    logic             full;
    logic             empty;

    assign wr_pay   = {s_tlast, s_tkeep, s_tdata};
    assign s_tready = !full;

    assign {m_tlast, m_tkeep, m_tdata} = rd_pay;
    assign m_tvalid = !empty;

    sync_fifo #(
        .WIDTH(PAY_W),
        .DEPTH(DEPTH)
    ) u_fifo (
        .clk,
        .rst_n,
        .wr_en  (s_tvalid && s_tready),
        .wr_data(wr_pay),
        .full   (full),
        .rd_en  (m_tvalid && m_tready),
        .rd_data(rd_pay),
        .empty  (empty),
        .count  (count)
    );

endmodule

`default_nettype wire
