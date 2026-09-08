`default_nettype none

// Match-action core: snoops a packet stream, parses the headers, builds a match
// key {ip_dst, udp_dst_port}, looks it up in the flow table, and decodes the
// matched action into a per-packet decision. On a miss the configurable
// dflt_action applies. Emits a 1-cycle decision strobe and maintains live stats.
//
// Action word layout (32 bits):
//   [0]     drop
//   [3:1]   out_port
//   [4]     count_en
//   [5]     timestamp
//   [6]     rewrite UDP dst port with [31:16]
//   [31:16] new UDP dst port
module match_action #(
    parameter int DATA_W  = 64,
    parameter int ENTRIES = 256
) (
    input  var logic                clk,
    input  var logic                rst_n,

    input  var logic [DATA_W-1:0]   s_tdata,
    input  var logic [DATA_W/8-1:0] s_tkeep,
    input  var logic                s_tlast,
    input  var logic                s_tvalid,
    input  var logic                s_tready,

    input  var logic [31:0]         dflt_action,

    input  var logic                ins_valid,
    input  var logic [31:0]         ins_ip_dst,
    input  var logic [15:0]         ins_udp_dport,
    input  var logic [31:0]         ins_action,

    output var logic                dec_valid,
    output var logic                dec_hit,
    output var logic                dec_drop,
    output var logic [2:0]          dec_out_port,
    output var logic                dec_count_en,
    output var logic                dec_timestamp,
    output var logic                dec_rewrite_dport,
    output var logic [15:0]         dec_new_dport,

    output var logic [31:0]         stat_pkts,
    output var logic [31:0]         stat_hits,
    output var logic [31:0]         stat_drops
);

    localparam int KEY_W = 48;

    logic        hdr_valid;
    logic        is_ipv4;
    logic        is_udp;
    logic [31:0] ip_dst;
    logic [15:0] udp_dst_port;
    logic [15:0] eth_type_unused;
    logic [7:0]  ip_proto_unused;
    logic [31:0] ip_src_unused;
    logic [15:0] udp_src_unused;
    logic        hdr_error_unused;

    header_parser #(.DATA_W(DATA_W)) u_parser (
        .clk,
        .rst_n,
        .s_tdata,
        .s_tkeep,
        .s_tlast,
        .s_tvalid,
        .s_tready,
        .hdr_valid    (hdr_valid),
        .hdr_error    (hdr_error_unused),
        .eth_type     (eth_type_unused),
        .is_ipv4      (is_ipv4),
        .ip_proto     (ip_proto_unused),
        .ip_src       (ip_src_unused),
        .ip_dst       (ip_dst),
        .is_udp       (is_udp),
        .udp_src_port (udp_src_unused),
        .udp_dst_port (udp_dst_port)
    );

    logic             res_valid;
    logic             res_hit;
    logic [31:0]      res_action;
    logic             is_udp_r;

    flow_table #(.KEY_W(KEY_W), .ACTION_W(32), .ENTRIES(ENTRIES)) u_table (
        .clk,
        .rst_n,
        .ins_valid,
        .ins_key    ({ins_ip_dst, ins_udp_dport}),
        .ins_action,
        .lu_valid   (hdr_valid),
        .lu_key     ({ip_dst, udp_dst_port}),
        .res_valid  (res_valid),
        .res_hit    (res_hit),
        .res_action (res_action)
    );

    always_ff @(posedge clk) begin
        if (hdr_valid)
            is_udp_r <= is_udp;
    end

    logic        eff_hit;
    logic [31:0] action;
    assign eff_hit = res_hit && is_udp_r;
    assign action  = eff_hit ? res_action : dflt_action;

    assign dec_valid        = res_valid;
    assign dec_hit          = eff_hit;
    assign dec_drop         = action[0];
    assign dec_out_port     = action[3:1];
    assign dec_count_en     = action[4];
    assign dec_timestamp    = action[5];
    assign dec_rewrite_dport = action[6];
    assign dec_new_dport    = action[31:16];

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            stat_pkts  <= '0;
            stat_hits  <= '0;
            stat_drops <= '0;
        end else if (res_valid) begin
            stat_pkts <= stat_pkts + 32'd1;
            if (eff_hit)
                stat_hits <= stat_hits + 32'd1;
            if (action[0])
                stat_drops <= stat_drops + 32'd1;
        end
    end

endmodule

`default_nettype wire
