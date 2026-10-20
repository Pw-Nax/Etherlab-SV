`timescale 1ns / 1ps
`include "xgmii_driver.sv"

module tb_xgmii;

    localparam int  CLK_MHZ     = 156_250_000;   // 156.25 MHz XGMII
    localparam int  TIMEOUT_US  = 500;
    localparam int  EXP_LAT     = 3;             // enc (1) + dec (1) + muestreo (1)

    logic clk = 1'b0;
    logic rst = 1'b1;

    // ---------------------------------------------------------
    // Reloj, timeout y volcado de ondas
    // ---------------------------------------------------------
    initial begin
        automatic realtime PERIOD      = 1s * (1.0 / CLK_MHZ);
        automatic realtime HALF_PERIOD = PERIOD / 2.0;
        clk = 1'b0;
        forever #(HALF_PERIOD) clk = ~clk;
    end

    initial begin
        #(TIMEOUT_US * 1us);
        $error("[%0t] Timeout (%0d us)", $time, TIMEOUT_US);
        $finish;
    end

    // ---------------------------------------------------------
    // Interfaz y DUT
    // ---------------------------------------------------------
    xgmii_if xif (
        .clk(clk),
        .rst(rst)
    );

    xgmii_top #(
        .GBX_IF_EN(1'b0)
    ) dut (
        .clk(clk),
        .rst(rst),
        .xgmii_txd(xif.txd),
        .xgmii_txc(xif.txc),
        .xgmii_tx_valid(xif.tx_valid),
        .xgmii_rxd(xif.rxd),
        .xgmii_rxc(xif.rxc),
        .xgmii_rx_valid(xif.rx_valid),
        .tx_bad_block(xif.tx_bad_block),
        .rx_bad_block(xif.rx_bad_block),
        .rx_sequence_error(xif.rx_sequence_error)
    );

    // ---------------------------------------------------------
    // Mailboxes y componentes
    // ---------------------------------------------------------
    mailbox #(xgmii_sequence_item) drv_mb  = new();
    mailbox #(xgmii_sequence_item) drv2scb = new();
    mailbox #(xgmii_sequence_item) mon2scb = new();

    xgmii_driver     drv;
    xgmii_monitor    mon;
    xgmii_scoreboard scb;

    xgmii_sequence_item tr;
    int n_items = 0;                 // ordenes enviadas al driver

    task automatic send(xgmii_sequence_item t);
        drv_mb.put(t);
        n_items++;
    endtask

    task automatic send_idle(int n);
        xgmii_sequence_item t;
        t = new(XGMII_IDLE);
        t.n_words = n;
        send(t);
    endtask

    // ---------------------------------------------------------
    // Test principal (SIMPLIFICADO)
    // ---------------------------------------------------------
    initial begin
        // 1. Instanciar componentes y arrancarlos en paralelo
        drv = new(xif, drv_mb, drv2scb);
        mon = new(xif, mon2scb);
        scb = new(drv2scb, mon2scb, EXP_LAT);

        fork
            drv.run();
            mon.run();
        join_none

        // 2. Reset
        rst = 1'b1;
        repeat (4) @(posedge clk);
        rst <= 1'b0;
        repeat (2) @(posedge clk);

        // 3. Encolar test corto (6 items en total)
        $display("[%0t] TB: Encolando transacciones de prueba...", $time);
        
        send_idle(5); // 5 idles
        
        tr = new(XGMII_DATA); tr.data = 64'hDEADBEEFCAFEBABE; send(tr);
        
        tr = new(XGMII_FRAME);
        tr.start_lane = 0; tr.term_lane = 0; tr.frame_len = 1; send(tr);
        
        tr = new(XGMII_FRAME);
        tr.start_lane = 4; tr.term_lane = 4; tr.frame_len = 1; send(tr);
        
        tr = new(XGMII_ILLEGAL);
        tr.data      = 64'h00000000000000FB;
        tr.ctrl      = 8'h02;
        send(tr);
        
        send_idle(5); // 5 idles finales

        // 4. Espera fija (evita el bug de "null object" de Vivado)
        $display("[%0t] TB: Esperando a que el driver y el pipeline terminen...", $time);
        repeat (50) @(posedge clk); // 50 ciclos son más que suficientes para 6 items
        repeat (EXP_LAT + 5) @(posedge clk);

        // 5. Reportar resultados
        scb.check();
        scb.report();
        $finish;
    end

endmodule