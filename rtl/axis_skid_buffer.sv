`default_nettype none

// OPTION 1 (register slice): registers the forward path (tdata/tvalid) only.
// s_tready is combinational in m_tready, so the backward (ready) path is NOT
// broken -- chaining many of these lets ready ripple through all of them.
// Sustains one word/cycle. Kept here to compare against the full skid buffer.
module axis_skid_buffer #(
    parameter int DATA_W = 8
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

    logic [DATA_W-1:0] data_reg;
    logic              valid_reg;

    assign s_tready = !valid_reg || m_tready;
    assign m_tdata  = data_reg;
    assign m_tvalid = valid_reg;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            valid_reg <= 1'b0;
            data_reg  <= '0;
        end else if (s_tready) begin
            valid_reg <= s_tvalid;
            data_reg  <= s_tdata;
        end else if (m_tready) begin
            valid_reg <= 1'b0;
        end
    end

endmodule

`default_nettype wire
