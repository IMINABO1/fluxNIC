`default_nettype none

// Direct-mapped exact-match flow table. Keys + actions live in a block RAM; a
// resettable "occupied" bit vector (flip-flops) tracks which slots are live so
// the table clears in one cycle. A key is hashed (XOR-fold) to a slot; a lookup
// is a hit only if the slot is occupied and its stored key matches exactly.
// One insert port and one lookup port; lookup result is registered (1-cycle).
// ENTRIES must be a power of two.
module flow_table #(
    parameter int KEY_W    = 48,
    parameter int ACTION_W = 8,
    parameter int ENTRIES  = 256
) (
    input  var logic                clk,
    input  var logic                rst_n,

    input  var logic                ins_valid,
    input  var logic [KEY_W-1:0]    ins_key,
    input  var logic [ACTION_W-1:0] ins_action,

    input  var logic                lu_valid,
    input  var logic [KEY_W-1:0]    lu_key,

    output var logic                res_valid,
    output var logic                res_hit,
    output var logic [ACTION_W-1:0] res_action
);

    localparam int INDEX_W = $clog2(ENTRIES);
    localparam int CHUNKS  = (KEY_W + INDEX_W - 1) / INDEX_W;
    localparam int PAD_W   = CHUNKS * INDEX_W;

    function automatic logic [INDEX_W-1:0] hashfn(input [KEY_W-1:0] k);
        logic [PAD_W-1:0]   padded;
        logic [INDEX_W-1:0] h;
        integer             i;
        padded = {{(PAD_W-KEY_W){1'b0}}, k};
        h = {INDEX_W{1'b0}};
        for (i = 0; i < CHUNKS; i = i + 1)
            h = h ^ padded[i*INDEX_W +: INDEX_W];
        hashfn = h;
    endfunction

    logic [KEY_W+ACTION_W-1:0] mem [ENTRIES];
    logic [ENTRIES-1:0]        occupied;

    logic [KEY_W+ACTION_W-1:0] rd_entry;
    logic [KEY_W-1:0]          lu_key_r;
    logic                      occ_r;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            occupied  <= '0;
            res_valid <= 1'b0;
        end else begin
            if (ins_valid) begin
                mem[hashfn(ins_key)]      <= {ins_key, ins_action};
                occupied[hashfn(ins_key)] <= 1'b1;
            end
            rd_entry  <= mem[hashfn(lu_key)];
            occ_r     <= occupied[hashfn(lu_key)];
            lu_key_r  <= lu_key;
            res_valid <= lu_valid;
        end
    end

    logic [KEY_W-1:0] stored_key;
    assign stored_key = rd_entry[ACTION_W +: KEY_W];
    assign res_hit    = occ_r && (stored_key == lu_key_r);
    assign res_action = rd_entry[0 +: ACTION_W];

endmodule

`default_nettype wire
