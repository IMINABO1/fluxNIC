`default_nettype none

// A chain of STAGES axis_skid_buffer instances back to back. Used to measure how
// the combinational critical path grows with depth: if the buffer's ready path
// is combinational, ready ripples through every stage and the path grows with
// STAGES; if ready is registered, the path stays flat.
module axis_slice_chain #(
    parameter int DATA_W = 8,
    parameter int STAGES = 8
) (
    input  var logic              clk,
    input  var logic              rst_n,

    input  var logic [DATA_W-1:0] s_tdata,
    input  var logic              s_tvalid,
    output var logic              s_tready,

    output var logic [DATA_W-1:0] m_tdata,
    output var logic              m_tvalid,
    input  var logic              m_tready
);

    logic [DATA_W-1:0] d [STAGES+1];
    logic              v [STAGES+1];
    logic              r [STAGES+1];

    assign d[0]      = s_tdata;
    assign v[0]      = s_tvalid;
    assign s_tready  = r[0];
    assign m_tdata   = d[STAGES];
    assign m_tvalid  = v[STAGES];
    assign r[STAGES] = m_tready;

    for (genvar i = 0; i < STAGES; i++) begin : stage
        axis_skid_buffer #(.DATA_W(DATA_W)) u (
            .clk,
            .rst_n,
            .s_tdata (d[i]),
            .s_tvalid(v[i]),
            .s_tready(r[i]),
            .m_tdata (d[i+1]),
            .m_tvalid(v[i+1]),
            .m_tready(r[i+1])
        );
    end

endmodule

`default_nettype wire
