`default_nettype none

// AXI4-Lite slave: the fluxNIC control plane. Writes load flow rules and the
// default action; reads return the live statistics counters. 32-bit data.
//
// Register map (byte address):
//   0x00  W  rule ip_dst
//   0x04  W  rule udp_dst_port (low 16 bits)
//   0x08  W  rule action word
//   0x0C  W  control: writing bit0=1 commits the rule (ins pulse)
//   0x10  W  default action (applied on a miss)
//   0x20  R  stat: packets
//   0x24  R  stat: hits
//   0x28  R  stat: drops
//   0x2C  R  stat: forwarded
module axil_regs #(
    parameter int ADDR_W = 8
) (
    input  var logic              clk,
    input  var logic              rst_n,

    input  var logic [ADDR_W-1:0] awaddr,
    input  var logic              awvalid,
    output var logic              awready,
    input  var logic [31:0]       wdata,
    input  var logic [3:0]        wstrb,
    input  var logic              wvalid,
    output var logic              wready,
    output var logic [1:0]        bresp,
    output var logic              bvalid,
    input  var logic              bready,

    input  var logic [ADDR_W-1:0] araddr,
    input  var logic              arvalid,
    output var logic              arready,
    output var logic [31:0]       rdata,
    output var logic [1:0]        rresp,
    output var logic              rvalid,
    input  var logic              rready,

    output var logic              ins_valid,
    output var logic [31:0]       ins_ip_dst,
    output var logic [15:0]       ins_udp_dport,
    output var logic [31:0]       ins_action,
    output var logic [31:0]       dflt_action,

    input  var logic [31:0]       stat_pkts,
    input  var logic [31:0]       stat_hits,
    input  var logic [31:0]       stat_drops,
    input  var logic [31:0]       stat_forwarded
);

    localparam logic [7:0] REG_IPDST  = 8'h00;
    localparam logic [7:0] REG_DPORT  = 8'h04;
    localparam logic [7:0] REG_ACTION = 8'h08;
    localparam logic [7:0] REG_CTRL   = 8'h0C;
    localparam logic [7:0] REG_DFLT   = 8'h10;

    logic do_write;
    assign do_write = awvalid && wvalid && !bvalid;
    assign awready  = do_write;
    assign wready   = do_write;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            ins_valid     <= 1'b0;
            ins_ip_dst    <= '0;
            ins_udp_dport <= '0;
            ins_action    <= '0;
            dflt_action   <= 32'h1;   // default: drop on miss
            bvalid        <= 1'b0;
            bresp         <= 2'b00;
        end else begin
            ins_valid <= 1'b0;
            if (do_write) begin
                unique case (awaddr[7:0])
                    REG_IPDST:  ins_ip_dst    <= wdata;
                    REG_DPORT:  ins_udp_dport <= wdata[15:0];
                    REG_ACTION: ins_action    <= wdata;
                    REG_DFLT:   dflt_action   <= wdata;
                    REG_CTRL:   if (wdata[0]) ins_valid <= 1'b1;
                    default: ;
                endcase
                bvalid <= 1'b1;
                bresp  <= 2'b00;
            end else if (bvalid && bready) begin
                bvalid <= 1'b0;
            end
        end
    end

    assign arready = arvalid && !rvalid;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            rvalid <= 1'b0;
            rresp  <= 2'b00;
            rdata  <= '0;
        end else if (arvalid && !rvalid) begin
            unique case (araddr[7:0])
                8'h00:   rdata <= ins_ip_dst;
                8'h04:   rdata <= {16'h0, ins_udp_dport};
                8'h08:   rdata <= ins_action;
                8'h10:   rdata <= dflt_action;
                8'h20:   rdata <= stat_pkts;
                8'h24:   rdata <= stat_hits;
                8'h28:   rdata <= stat_drops;
                8'h2C:   rdata <= stat_forwarded;
                default: rdata <= 32'hDEAD_BEEF;
            endcase
            rvalid <= 1'b1;
            rresp  <= 2'b00;
        end else if (rvalid && rready) begin
            rvalid <= 1'b0;
        end
    end

endmodule

`default_nettype wire
