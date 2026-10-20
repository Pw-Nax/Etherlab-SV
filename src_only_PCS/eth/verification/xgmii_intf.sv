`timescale 1ns / 1ps

/*
 * Interfaz del testbench XGMII (loopback enc -> dec).
 *
 *  - txd/txc/tx_valid arrancan en IDLE desde t=0: el DUT nunca ve X.
 *  - cyc cuenta flancos de clk. Driver y monitor lo leen por su clocking
 *    block (valor "preponed"), asi que la diferencia de cyc entre una palabra
 *    manejada y la misma palabra observada es la latencia del DUT.
 */
interface xgmii_if (input logic clk, input logic rst);

    // ---- Estimulo ----
    logic [63:0] txd      = 64'h0707070707070707;
    logic [7:0]  txc      = 8'hFF;
    logic        tx_valid = 1'b1;

    // ---- Observacion ----
    logic [63:0] rxd;
    logic [7:0]  rxc;
    logic        rx_valid;
    logic        tx_bad_block;
    logic        rx_bad_block;
    logic        rx_sequence_error;

    // ---- Contador de ciclos ----
    int unsigned cyc = 0;
    always @(posedge clk) cyc <= cyc + 1;

    // Driver: escribe el estimulo, lee el resto
    clocking drv_cb @(posedge clk);
        default input #1step output #1ns;
        output txd, txc, tx_valid;
        input  rxd, rxc, rx_valid,
               tx_bad_block, rx_bad_block, rx_sequence_error,
               rst, cyc;
    endclocking

    // Monitor: solo lee
    clocking mon_cb @(posedge clk);
        default input #1step;
        input  txd, txc, tx_valid,
               rxd, rxc, rx_valid,
               tx_bad_block, rx_bad_block, rx_sequence_error,
               rst, cyc;
    endclocking

endinterface
