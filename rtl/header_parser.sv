`default_nettype none

// Snoops a 64-bit AXI-Stream and extracts the Ethernet/IPv4/UDP header fields the
// flow table matches on. It observes the shared handshake (beat = tvalid &&
// tready) rather than driving ready, so it sits alongside a packet buffer without
// affecting flow control. The first 5 words (40 bytes) reach the UDP ports, which
// is all that is extracted; assumes IPv4 with no options (IHL == 5).
module header_parser #(
    parameter int DATA_W = 64
) (
    input  var logic                clk,
    input  var logic                rst_n,

    input  var logic [DATA_W-1:0]   s_tdata,
    input  var logic [DATA_W/8-1:0] s_tkeep,
    input  var logic                s_tlast,
    input  var logic                s_tvalid,
    input  var logic                s_tready,

    output var logic                hdr_valid,   // 1-cycle strobe; fields valid
    output var logic                hdr_error,   // packet ended before headers done
    output var logic [15:0]         eth_type,
    output var logic                is_ipv4,
    output var logic [7:0]          ip_proto,
    output var logic [31:0]         ip_src,
    output var logic [31:0]         ip_dst,
    output var logic                is_udp,
    output var logic [15:0]         udp_src_port,
    output var logic [15:0]         udp_dst_port
);

    localparam int HDR_WORDS = 5;                 // 40 bytes: Eth + IPv4 + UDP ports
    localparam int LAST_IDX  = HDR_WORDS - 1;

    logic [HDR_WORDS*DATA_W-1:0] hdr;
    logic [2:0]                  word_cnt;
    logic                        emit;

    logic beat;
    assign beat = s_tvalid && s_tready;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            word_cnt  <= '0;
            emit      <= 1'b0;
            hdr_valid <= 1'b0;
            hdr_error <= 1'b0;
        end else begin
            hdr_valid <= emit;
            hdr_error <= 1'b0;
            emit      <= 1'b0;

            if (beat) begin
                if (word_cnt < HDR_WORDS[2:0]) begin
                    hdr[word_cnt*DATA_W +: DATA_W] <= s_tdata;
                    word_cnt <= word_cnt + 3'd1;
                    if (word_cnt == LAST_IDX[2:0])
                        emit <= 1'b1;
                end
                if (s_tlast) begin
                    word_cnt <= '0;
                    if (word_cnt < LAST_IDX[2:0])
                        hdr_error <= 1'b1;
                end
            end
        end
    end

    assign eth_type     = {hdr[12*8 +: 8], hdr[13*8 +: 8]};
    assign ip_proto     =  hdr[23*8 +: 8];
    assign ip_src       = {hdr[26*8 +: 8], hdr[27*8 +: 8], hdr[28*8 +: 8], hdr[29*8 +: 8]};
    assign ip_dst       = {hdr[30*8 +: 8], hdr[31*8 +: 8], hdr[32*8 +: 8], hdr[33*8 +: 8]};
    assign udp_src_port = {hdr[34*8 +: 8], hdr[35*8 +: 8]};
    assign udp_dst_port = {hdr[36*8 +: 8], hdr[37*8 +: 8]};
    assign is_ipv4      = (eth_type == 16'h0800) && (hdr[14*8+4 +: 4] == 4'd4);
    assign is_udp       = is_ipv4 && (ip_proto == 8'd17) && (hdr[14*8 +: 4] == 4'd5);

endmodule

`default_nettype wire
