/*
Author:      Cabero, Mauro
Testbench:   xgmii_top.sv

Loopback XGMII -> 64B/66B -> XGMII:

    xgmii_txd/txc --> taxi_xgmii_baser_enc --(encoded_*)--> taxi_xgmii_baser_dec --> xgmii_rxd/rxc

XGMII es la interfaz entre la subcapa RS y la PCS. El estandar la define de
32 bits de datos + 4 de control en DDR; Taxi la usa de 64 bits de datos + 8 de
control en SDR (misma tasa efectiva). En este top: DATA_W = 64, CTRL_W = 8.

Los cables encoded_* entre enc y dec son internos: no son puertos del top.
*/

`timescale 1ns / 1ps

module xgmii_top #(
    parameter DATA_W = 64,
    parameter CTRL_W = DATA_W/8,
    parameter HDR_W  = 2,
    parameter logic GBX_IF_EN = 1'b0
)(
    input  logic               clk,
    input  logic               rst,

    // Estimulo (lo que maneja el driver)
    input  logic [DATA_W-1:0]  xgmii_txd,
    input  logic [CTRL_W-1:0]  xgmii_txc,
    input  logic               xgmii_tx_valid,

    // Resultado (lo que observa el monitor)
    output logic [DATA_W-1:0]  xgmii_rxd,
    output logic [CTRL_W-1:0]  xgmii_rxc,
    output logic               xgmii_rx_valid,

    // Flags de error
    output logic               tx_bad_block,
    output logic               rx_bad_block,
    output logic               rx_sequence_error
);

    // Cables internos enc -> dec
    wire [DATA_W-1:0] enc_data;
    wire [HDR_W-1:0]  enc_hdr;
    wire              enc_data_valid, enc_hdr_valid;

    taxi_xgmii_baser_enc #(
        .DATA_W(DATA_W),
        .CTRL_W(CTRL_W),
        .HDR_W(HDR_W),
        .GBX_IF_EN(GBX_IF_EN)
    )
    enc (
        .clk(clk),
        .rst(rst),
        .xgmii_txd(xgmii_txd),
        .xgmii_txc(xgmii_txc),
        .xgmii_tx_valid(xgmii_tx_valid),
        .tx_gbx_sync_in('0),
        .encoded_tx_data(enc_data),
        .encoded_tx_data_valid(enc_data_valid),
        .encoded_tx_hdr(enc_hdr),
        .encoded_tx_hdr_valid(enc_hdr_valid),
        .tx_gbx_sync_out(),
        .tx_os('0),
        .tx_os_sig(1'b0),
        .tx_os_valid(1'b0),
        .tx_os_ready(),
        .tx_bad_block(tx_bad_block)
    );

    taxi_xgmii_baser_dec #(
        .DATA_W(DATA_W),
        .CTRL_W(CTRL_W),
        .HDR_W(HDR_W),
        .GBX_IF_EN(GBX_IF_EN)
    )
    dec (
        .clk(clk),
        .rst(rst),
        .encoded_rx_data(enc_data),
        .encoded_rx_data_valid(enc_data_valid),
        .encoded_rx_hdr(enc_hdr),
        .encoded_rx_hdr_valid(enc_hdr_valid),
        .rx_gbx_sync_in('0),
        .xgmii_rxd(xgmii_rxd),
        .xgmii_rxc(xgmii_rxc),
        .xgmii_rx_valid(xgmii_rx_valid),   // antes estaba sin conectar: el top nunca lo manejaba
        .rx_gbx_sync_out(),
        .rx_os(),
        .rx_os_sig(),
        .rx_os_valid(),
        .rx_os_match(),
        .rx_idle_match(),
        .rx_bad_block(rx_bad_block),
        .rx_sequence_error(rx_sequence_error)
    );

endmodule
