`default_nettype none

// fluxNIC with an AXI4-Lite control plane: rules and the default action are
// loaded over AXI-Lite, statistics are read back over it, and packets flow
// through the AXI-Stream data path.
module fluxnic_axil #(
    parameter int DATA_W     = 64,
    parameter int FIFO_DEPTH = 512,
    parameter int ENTRIES    = 256,
    parameter int ADDR_W     = 8
) (
    input  var logic                clk,
    input  var logic                rst_n,

    // AXI4-Lite control plane
    input  var logic [ADDR_W-1:0]   awaddr,
    input  var logic                awvalid,
    output var logic                awready,
    input  var logic [31:0]         wdata,
    input  var logic [3:0]          wstrb,
    input  var logic                wvalid,
    output var logic                wready,
    output var logic [1:0]          bresp,
    output var logic                bvalid,
    input  var logic                bready,
    input  var logic [ADDR_W-1:0]   araddr,
    input  var logic                arvalid,
    output var logic                arready,
    output var logic [31:0]         rdata,
    output var logic [1:0]          rresp,
    output var logic                rvalid,
    input  var logic                rready,

    // AXI-Stream data path
    input  var logic [DATA_W-1:0]   s_tdata,
    input  var logic [DATA_W/8-1:0] s_tkeep,
    input  var logic                s_tlast,
    input  var logic                s_tvalid,
    output var logic                s_tready,

    output var logic [DATA_W-1:0]   m_tdata,
    output var logic [DATA_W/8-1:0] m_tkeep,
    output var logic                m_tlast,
    output var logic                m_tvalid,
    input  var logic                m_tready,
    output var logic [2:0]          m_tdest
);

    logic        ins_valid;
    logic [31:0] ins_ip_dst;
    logic [15:0] ins_udp_dport;
    logic [31:0] ins_action;
    logic [31:0] dflt_action;
    logic [31:0] stat_pkts;
    logic [31:0] stat_hits;
    logic [31:0] stat_drops;
    logic [31:0] stat_forwarded;

    axil_regs #(.ADDR_W(ADDR_W)) u_regs (
        .clk,
        .rst_n,
        .awaddr,
        .awvalid,
        .awready,
        .wdata,
        .wstrb,
        .wvalid,
        .wready,
        .bresp,
        .bvalid,
        .bready,
        .araddr,
        .arvalid,
        .arready,
        .rdata,
        .rresp,
        .rvalid,
        .rready,
        .ins_valid,
        .ins_ip_dst,
        .ins_udp_dport,
        .ins_action,
        .dflt_action,
        .stat_pkts,
        .stat_hits,
        .stat_drops,
        .stat_forwarded
    );

    fluxnic_top #(.DATA_W(DATA_W), .FIFO_DEPTH(FIFO_DEPTH), .ENTRIES(ENTRIES)) u_top (
        .clk,
        .rst_n,
        .s_tdata,
        .s_tkeep,
        .s_tlast,
        .s_tvalid,
        .s_tready,
        .dflt_action,
        .ins_valid,
        .ins_ip_dst,
        .ins_udp_dport,
        .ins_action,
        .m_tdata,
        .m_tkeep,
        .m_tlast,
        .m_tvalid,
        .m_tready,
        .m_tdest,
        .stat_pkts,
        .stat_hits,
        .stat_drops,
        .stat_forwarded
    );

endmodule

`default_nettype wire
