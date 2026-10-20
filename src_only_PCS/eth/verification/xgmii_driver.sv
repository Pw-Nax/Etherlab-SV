`ifndef XGMII_DRIVER_SV
`define XGMII_DRIVER_SV

`define XGMII_IDLE_W 64'h0707070707070707

// 1. Sequence item
typedef enum {
    XGMII_RST,       // n_words idles (reset)
    XGMII_IDLE,      // n_words idles
    XGMII_DATA,      // 1 palabra de datos (txc = 00)
    XGMII_START,     // 1 palabra /S/ en lane 0 o 4
    XGMII_TERM,      // 1 palabra /T/ en lane 0..7
    XGMII_FRAME,     // START + frame_len datos + TERM + gap idles
    XGMII_ILLEGAL    // 1 palabra que el encoder no puede codificar
} xgmii_drv_op_e;

class xgmii_sequence_item;
    xgmii_drv_op_e  drv_op;
    rand bit [63:0] data;
    rand bit [7:0]  ctrl;
    int             n_words    = 1;           
    int             start_lane = 0;           
    int             term_lane  = 0;           
    int             frame_len  = 0;           

    // Sello de ciclo y esperados (para el scoreboard)
    int unsigned    cyc = 0;
    string          tag = "";
    bit [63:0]      exp_rxd;
    bit [7:0]       exp_rxc;

    // Observado (lo llena el monitor)
    bit [63:0]      got_rxd;
    bit [7:0]       got_rxc;

    function new(xgmii_drv_op_e op = XGMII_RST);
        drv_op = op;
    endfunction
endclass

// 2. Driver
class xgmii_driver;
    virtual xgmii_if               vif; // Interfaz completa, no el modport
    mailbox #(xgmii_sequence_item) drv_mb;
    mailbox #(xgmii_sequence_item) drv2scb;

    bit stop = 1'b0;

    function new(
        virtual xgmii_if               vif,
        mailbox #(xgmii_sequence_item) drv_mb,
        mailbox #(xgmii_sequence_item) drv2scb
    );
        this.vif     = vif;
        this.drv_mb  = drv_mb;
        this.drv2scb = drv2scb;
    endfunction

    virtual task run();
        xgmii_sequence_item tr;
        
        // Esperar a que baje el reset
        @(vif.drv_cb);
        while (vif.drv_cb.rst !== 1'b0) @(vif.drv_cb);

        while (!stop) begin
            // try_get NO se bloquea. Si no hay nada, manda idle-fill.
            if (drv_mb.try_get(tr)) begin
                $display("[%0t] DRV got tr: %0s", $time, tr.drv_op.name());
                case (tr.drv_op)
                    XGMII_RST:     drive_rst();
                    XGMII_IDLE:    drive_idle(tr.n_words);
                    XGMII_DATA:    drive_data(tr.data);
                    XGMII_START:   drive_start(tr.start_lane);
                    XGMII_TERM:    drive_term(tr.term_lane);
                    XGMII_FRAME:   drive_frame(tr);
                    XGMII_ILLEGAL: drive_illegal(tr);
                    default:       $fatal(1, "[DRV] op no soportada");
                endcase
            end else begin
                // MANTIENE EL BUS VIVO: Si no hay comandos, manda idle
                drive_idle_word("idle-fill");
            end
        end
    endtask

    // ---- Primitiva base ----
    virtual task drive_word(bit [63:0] d, bit [7:0] c, bit [63:0] e_d, bit [7:0] e_c, string tag);
        @(vif.drv_cb);
        vif.drv_cb.txd      <= d;
        vif.drv_cb.txc      <= c;
        vif.drv_cb.tx_valid <= 1'b1;

        if (tag != "idle-fill") begin
            xgmii_sequence_item t = new();
            t.cyc     = vif.drv_cb.cyc;
            t.tag     = tag;
            t.exp_rxd = e_d;
            t.exp_rxc = e_c;
            drv2scb.put(t);
        end
    endtask

    virtual task drive_idle_word(string tag = "idle");
        drive_word(`XGMII_IDLE_W, 8'hFF, `XGMII_IDLE_W, 8'hFF, tag);
    endtask

    // ---- Comandos ----
    virtual task drive_rst();
        repeat (10) drive_idle_word("idle");
    endtask

    virtual task drive_idle(int n);
        repeat (n) drive_idle_word("idle");
    endtask

    virtual task drive_data(bit [63:0] d);
        drive_word(d, 8'h00, d, 8'h00, "data");
    endtask

    virtual task drive_start(int lane);
        bit [63:0] d = `XGMII_IDLE_W;
        bit [7:0]  c;
        case (lane)
            0: begin d[7:0]   = 8'hFB; c = 8'h01; end
            4: begin d[31:0]  = 32'h07070707; d[39:32] = 8'hFB; c = 8'h1F; end
            default: $fatal(1, "[DRV] START solo en lane 0 o 4");
        endcase
        drive_word(d, c, d, c, "start");
    endtask

    virtual task drive_term(int lane);
        bit [63:0] d = `XGMII_IDLE_W;
        bit [7:0]  c = 8'hFF << lane;
        d[8*lane +: 8] = 8'hFD;
        drive_word(d, c, d, c, "term");
    endtask

    virtual task drive_frame(xgmii_sequence_item tr);
        drive_start(tr.start_lane);
        repeat (tr.frame_len) drive_data($urandom); 
        drive_term(tr.term_lane);
    endtask

    virtual task drive_illegal(xgmii_sequence_item tr);
        drive_word(tr.data, tr.ctrl, 64'hFEFEFEFEFEFEFEFE, 8'hFF, "illegal");
    endtask
endclass

// 3. Monitor
class xgmii_monitor;
    virtual xgmii_if               vif;
    mailbox #(xgmii_sequence_item) mon2scb;

    function new(virtual xgmii_if vif, mailbox #(xgmii_sequence_item) mon2scb);
        this.vif     = vif;
        this.mon2scb = mon2scb;
    endfunction

    virtual task run();
        xgmii_sequence_item t;
        forever begin
            @(vif.mon_cb);
            if (vif.mon_cb.rst === 1'b0 && vif.mon_cb.rx_valid === 1'b1) begin
                t            = new();
                t.cyc        = vif.mon_cb.cyc;
                t.got_rxd    = vif.mon_cb.rxd;
                t.got_rxc    = vif.mon_cb.rxc;
                mon2scb.put(t);
            end
        end
    endtask
endclass

// 4. Scoreboard (Usa el método robusto de comparación por ciclo)
class xgmii_scoreboard;
    mailbox #(xgmii_sequence_item) drv2scb;
    mailbox #(xgmii_sequence_item) mon2scb;

    xgmii_sequence_item exp_by_cyc [int unsigned];
    xgmii_sequence_item mon_by_cyc [int unsigned];

    int errors = 0, checks = 0, exp_lat = 3;

    function new(mailbox #(xgmii_sequence_item) drv2scb, mailbox #(xgmii_sequence_item) mon2scb, int exp_lat = 3);
        this.drv2scb = drv2scb;
        this.mon2scb = mon2scb;
        this.exp_lat = exp_lat;
    endfunction

    function void drain();
        xgmii_sequence_item t;
        while (drv2scb.try_get(t)) exp_by_cyc[t.cyc] = t;
        while (mon2scb.try_get(t)) mon_by_cyc[t.cyc] = t;
    endfunction

    function void check();
        xgmii_sequence_item e, g;
        drain();
        
        foreach (exp_by_cyc[k]) begin
            e = exp_by_cyc[k];
            checks++;
            if (!mon_by_cyc.exists(k + exp_lat)) begin
                $error("[SCB] cyc %0d (%s): sin muestra en monitor", k, e.tag);
                errors++;
            end else begin
                g = mon_by_cyc[k + exp_lat];
                if (g.got_rxd !== e.exp_rxd || g.got_rxc !== e.exp_rxc) begin
                    $error("[SCB] cyc %0d (%s): exp %h/%h, got %h/%h", k, e.tag, e.exp_rxd, e.exp_rxc, g.got_rxd, g.got_rxc);
                    errors++;
                end
            end
        end
    endfunction

    function void report();
        $display("========================================");
        $display("[SCB] Checks=%0d Errors=%0d", checks, errors);
        if (errors == 0 && checks > 0) $display("[SCB] *** PASS ***");
        else                           $display("[SCB] *** FAIL ***");
        $display("========================================");
    endfunction
endclass

`endif