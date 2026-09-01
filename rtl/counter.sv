`default_nettype none

module counter #(
    parameter int WIDTH = 8
) (
    input  var logic             clk,
    input  var logic             rst_n,
    input  var logic             en,
    output var logic [WIDTH-1:0] count
);

    always_ff @(posedge clk) begin
        if (!rst_n)
            count <= '0;
        else if (en)
            count <= count + 1'b1;
    end

endmodule

`default_nettype wire
