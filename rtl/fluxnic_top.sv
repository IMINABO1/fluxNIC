`default_nettype none

// fluxNIC top: a programmable store-and-forward packet data plane.
//
//   ingress ---+--> packet FIFO (buffers the whole packet) --> egress FSM --> m_axis
//              |                                                   ^
//              +--> match_action (parse, look up, decide) --> decision FIFO
//
// The packet is buffered while its decision is computed from the headers; the
// egress FSM then drains each packet in order and forwards it to the decided
// output port or drops it. Decisions stay aligned with packets because both the
// packet FIFO and the decision FIFO are strictly in order, one decision/packet.
// Assumes well-formed packets (>= 5 words); malformed/short packets are future
// work (they would need an error->drop decision path).
module fluxnic_top #(
    parameter int DATA_W     = 64,
    parameter int FIFO_DEPTH = 512,
    parameter int ENTRIES    = 256
) (
    input  var logic                clk,
    input  var logic                rst_n,

    input  var logic [DATA_W-1:0]   s_tdata,
    input  var logic [DATA_W/8-1:0] s_tkeep,
    input  var logic                s_tlast,
    input  var logic                s_tvalid,
    output var logic                s_tready,

    input  var logic [7:0]          dflt_action,
    input  var logic                ins_valid,
    input  var logic [31:0]         ins_ip_dst,
    input  var logic [15:0]         ins_udp_dport,
    input  var logic [7:0]          ins_action,

    output var logic [DATA_W-1:0]   m_tdata,
    output var logic [DATA_W/8-1:0] m_tkeep,
    output var logic                m_tlast,
    output var logic                m_tvalid,
    input  var logic                m_tready,
    output var logic [2:0]          m_tdest,

    output var logic [31:0]         stat_pkts,
    output var logic [31:0]         stat_hits,
    output var logic [31:0]         stat_drops,
    output var logic [31:0]         stat_forwarded
);

    localparam int DEC_DEPTH = 128;

    logic in_ready;
    assign s_tready = in_ready;

    // --- packet buffer ---
    logic [DATA_W-1:0]   pf_tdata;
    logic [DATA_W/8-1:0] pf_tkeep;
    logic                pf_tlast;
    logic                pf_tvalid;
    logic                pf_tready;

    axis_fifo #(.DATA_W(DATA_W), .DEPTH(FIFO_DEPTH)) u_pkt_fifo (
        .clk,
        .rst_n,
        .s_tdata,
        .s_tkeep,
        .s_tlast,
        .s_tvalid,
        .s_tready (in_ready),
        .m_tdata  (pf_tdata),
        .m_tkeep  (pf_tkeep),
        .m_tlast  (pf_tlast),
        .m_tvalid (pf_tvalid),
        .m_tready (pf_tready),
        .count    ()
    );

    // --- decision engine (snoops the same accepted beats) ---
    logic       dec_valid;
    logic       dec_hit;
    logic       dec_drop;
    logic [2:0] dec_out_port;
    logic       dec_count_en;
    logic       dec_timestamp;

    match_action #(.DATA_W(DATA_W), .ENTRIES(ENTRIES)) u_ma (
        .clk,
        .rst_n,
        .s_tdata,
        .s_tkeep,
        .s_tlast,
        .s_tvalid,
        .s_tready     (in_ready),
        .dflt_action,
        .ins_valid,
        .ins_ip_dst,
        .ins_udp_dport,
        .ins_action,
        .dec_valid,
        .dec_hit,
        .dec_drop,
        .dec_out_port,
        .dec_count_en,
        .dec_timestamp,
        .stat_pkts,
        .stat_hits,
        .stat_drops
    );

    // --- decision FIFO: {out_port[2:0], drop} per packet, in order ---
    logic       dec_pop;
    logic [3:0] dec_head;
    logic       dec_empty;
    logic       dec_full;

    sync_fifo #(.WIDTH(4), .DEPTH(DEC_DEPTH)) u_dec_fifo (
        .clk,
        .rst_n,
        .wr_en   (dec_valid),
        .wr_data ({dec_out_port, dec_drop}),
        .full    (dec_full),
        .rd_en   (dec_pop),
        .rd_data (dec_head),
        .empty   (dec_empty),
        .count   ()
    );

    // --- egress FSM ---
    typedef enum logic [1:0] {IDLE, FWD, DROP} state_t;
    state_t     state;
    logic [2:0] cur_port;

    logic df_drop;
    logic [2:0] df_port;
    assign df_drop = dec_head[0];
    assign df_port = dec_head[3:1];

    always_comb begin
        m_tvalid   = 1'b0;
        pf_tready  = 1'b0;
        dec_pop    = 1'b0;
        m_tdata    = pf_tdata;
        m_tkeep    = pf_tkeep;
        m_tlast    = pf_tlast;
        m_tdest    = cur_port;

        case (state)
            IDLE: begin
                if (!dec_empty && pf_tvalid)
                    dec_pop = 1'b1;
            end
            FWD: begin
                m_tvalid  = pf_tvalid;
                pf_tready = m_tready;
                m_tdest   = cur_port;
            end
            DROP: begin
                pf_tready = pf_tvalid;  // consume and discard
            end
            default: ;
        endcase
    end

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            state          <= IDLE;
            cur_port       <= '0;
            stat_forwarded <= '0;
        end else begin
            case (state)
                IDLE: begin
                    if (!dec_empty && pf_tvalid) begin
                        cur_port <= df_port;
                        state    <= df_drop ? DROP : FWD;
                    end
                end
                FWD: begin
                    if (pf_tvalid && m_tready && pf_tlast) begin
                        stat_forwarded <= stat_forwarded + 32'd1;
                        state          <= IDLE;
                    end
                end
                DROP: begin
                    if (pf_tvalid && pf_tlast)
                        state <= IDLE;
                end
                default: state <= IDLE;
            endcase
        end
    end

endmodule

`default_nettype wire
