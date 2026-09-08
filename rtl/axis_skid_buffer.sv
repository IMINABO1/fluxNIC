`default_nettype none

// OPTION 2 (full skid buffer): registers BOTH the forward path (tdata/tvalid)
// and the backward path (tready). A one-entry "skid" register catches the word
// that arrives in the cycle ready deasserts, so no data is lost and one
// word/cycle is sustained. Because s_tready is a register output, chaining these
// does not let ready ripple -- the critical path stays flat with depth.
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

    logic [DATA_W-1:0] m_data;
    logic [DATA_W-1:0] skid_data;
    logic              m_valid;
    logic              skid_valid;

    assign m_tdata  = m_data;
    assign m_tvalid = m_valid;
    assign s_tready = !skid_valid;

    logic s_beat;
    assign s_beat = s_tvalid && s_tready;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            m_valid    <= 1'b0;
            skid_valid <= 1'b0;
            m_data     <= '0;
            skid_data  <= '0;
        end else if (!m_valid || m_tready) begin
            if (skid_valid) begin
                m_data     <= skid_data;
                m_valid    <= 1'b1;
                skid_valid <= 1'b0;
            end else begin
                m_data  <= s_tdata;
                m_valid <= s_beat;
            end
        end else if (s_beat) begin
            skid_data  <= s_tdata;
            skid_valid <= 1'b1;
        end
    end

endmodule

`default_nettype wire
