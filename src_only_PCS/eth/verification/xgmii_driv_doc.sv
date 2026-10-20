`ifndef XGMII_DRIVER_SV
`define XGMII_DRIVER_SV

// Macro que define el patrón de 64 bits de un bloque IDLE en XGMII:
// Todos los bytes son 0x07 (Idle) y el control es 0xFF (todos son control).
`define XGMII_IDLE_W 64'h0707070707070707

// =========================================================================
// 1. SEQUENCE ITEM (El "paquete" de datos / Transaction)
// =========================================================================
// Enum: Lista de las operaciones posibles que el Driver puede ejecutar.
// Se usa para saber "qué acción" tomar sin tener que adivinar por los datos.
typedef enum {
    XGMII_RST,       // Comando: Mandar idles (reset del bus)
    XGMII_IDLE,      // Comando: Mandar 'n_words' idles
    XGMII_DATA,      // Comando: Mandar 1 bloque de datos (txc=00)
    XGMII_START,     // Comando: Mandar 1 carácter START (en lane 0 o 4)
    XGMII_TERM,      // Comando: Mandar 1 carácter TERM (en lane 0 a 7)
    XGMII_FRAME,     // Comando: Mandar una trama completa (START + Datos + TERM)
    XGMII_ILLEGAL    // Comando: Mandar un patrón inválido para forzar errores
} xgmii_drv_op_e;

class xgmii_sequence_item;
    // --- Parámetros de la orden (los llena el Testbench) ---
    // 'rand' significa que el valor puede ser randomizado automáticamente.
    xgmii_drv_op_e  drv_op;      // ¿Qué comando quiero ejecutar? (el enum de arriba)
    rand bit [63:0] data;        // Dato de 64 bits (para XGMII_DATA o tramas)
    rand bit [7:0]  ctrl;        // Byte de control (para XGMII_ILLEGAL)
    
    int n_words    = 1;          // Cuántos idles mandar (para XGMII_IDLE)
    int start_lane = 0;          // En qué lane va el START (0 o 4)
    int term_lane  = 0;          // En qué lane va el TERM (0 a 7)
    int frame_len  = 0;          // Cuántos datos poner entre el START y el TERM
    
    // --- Variables de control para el Scoreboard ---
    int unsigned cyc = 0;        // Ciclo de reloj exacto en el que se ejecutó la orden (sirve como huella digital)
    string tag = "";             // Etiqueta de texto ("start", "data", "idle-fill"). Sirve para debug.
    bit [63:0] exp_rxd;          // Dato que ESPERAMOS ver en el RX (lo llena el Driver)
    bit [7:0]  exp_rxc;          // Control que ESPERAMOS ver en el RX

    // --- Variables de observación (las llena el Monitor) ---
    bit [63:0] got_rxd;          // Dato que REALMENTE salió del DUT
    bit [7:0]  got_rxc;          // Control que REALMENTE salió del DUT

    // Constructor: Se llama al hacer 'new()'. Inicializa la variable 'drv_op'.
    // En SystemVerilog OOP, declarar la variable (ej. 'xgmii_sequence_item tr;') NO crea el objeto en memoria, 
    // solo crea un "puntero". El objeto real se crea (se instancia) recién cuando llamamos a 'new()'.
    function new(xgmii_drv_op_e op = XGMII_RST);
        drv_op = op;
    endfunction
endclass

// =========================================================================
// 2. DRIVER (El que maneja los cables físicos de entrada al DUT)
// =========================================================================
class xgmii_driver;
    // 'virtual xgmii_if': Es un puntero a la interfaz física. Permite que esta clase acceda a los cables 'txd', 'txc', etc.
    virtual xgmii_if               vif;      
    
    // 'mailbox': Son buzones (colas FIFO) que permiten pasar objetos (sequence items) entre clases.
    mailbox #(xgmii_sequence_item) drv_mb;   // Buzón de entrada (el Testbench nos manda las órdenes acá)
    mailbox #(xgmii_sequence_item) drv2scb;  // Buzón de salida (le avisamos al Scoreboard qué enviamos)

    bit stop = 1'b0; // Bandera para apagar el driver si quisiéramos (no se usa en este test)

    // Constructor del Driver: Recibe la interfaz y los buzones, y los guarda en sus variables internas.
    function new(virtual xgmii_if vif,
                 mailbox #(xgmii_sequence_item) drv_mb,
                 mailbox #(xgmii_sequence_item) drv2scb);
        this.vif     = vif;
        this.drv_mb  = drv_mb;
        this.drv2scb = drv2scb;
    endfunction

    // --- El bucle principal del Driver (Thread infinito) ---
    virtual task run();
        // 'tr' es convención para Transaction. Representa la orden actual que estamos procesando.
        xgmii_sequence_item tr; 
        
        // 1. Esperar a que el reset baje. '@(vif.drv_cb)' espera al flanco del clocking block.
        @(vif.drv_cb);
        while (vif.drv_cb.rst !== 1'b0) @(vif.drv_cb);

        // 2. Bucle infinito de trabajo
        while (!stop) begin
            // 'try_get' intenta sacar un objeto del buzón. Si el buzón está vacío, NO se bloquea, devuelve 0.
            // Usamos 'try_get' en vez de 'get' para que el bus nunca se quede congelado esperando una orden.
            if (drv_mb.try_get(tr)) begin
                // Llegó una orden: la ejecutamos.
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
                // Si el buzón está vacío, mandamos un IDLE de relleno. Esto mantiene el bus "vivo" 
                // y evita que el último dato transmitido (ej. un TERM) se quede pegado en el cable.
                drive_idle_word("idle-fill");
            end
        end
    endtask

    // --- Primitiva base: maneja 1 solo ciclo de reloj ---
    // Es la tarea más baja en la jerarquía. Recibe los bits exactos a poner en los cables.
    virtual task drive_word(bit [63:0] d, bit [7:0] c, bit [63:0] e_d, bit [7:0] e_c, string tag);
        @(vif.drv_cb); // Esperar el flanco del reloj
        
        // Asignar los valores a los cables físicos usando '<='
        vif.drv_cb.txd      <= d;
        vif.drv_cb.txc      <= c;
        vif.drv_cb.tx_valid <= 1'b1;

        // Si NO es un idle de relleno, avisamos al Scoreboard.
        if (tag != "idle-fill") begin
            // 't' (temp) es convención para un objeto temporal. 
            // Acá instanciamos (creamos en memoria) un nuevo Sequence Item.
            xgmii_sequence_item t = new(); 
            t.cyc     = vif.drv_cb.cyc; // Sellar el ciclo actual en el que se envió
            t.tag     = tag;            // Poner la etiqueta de texto
            t.exp_rxd = e_d;            // Guardar qué esperamos recibir
            t.exp_rxc = e_c;
            drv2scb.put(t);             // Mandarlo al buzón del Scoreboard
        end
    endtask

    // --- Atajos para mandar bloques Idle ---
    virtual task drive_idle_word(string tag = "idle");
        drive_word(`XGMII_IDLE_W, 8'hFF, `XGMII_IDLE_W, 8'hFF, tag);
    endtask

    // --- Comandos de alto nivel ---
    virtual task drive_rst();
        repeat (10) drive_idle_word("idle"); // Manda 10 idles seguidos
    endtask

    virtual task drive_idle(int n);
        repeat (n) drive_idle_word("idle");
    endtask

    virtual task drive_data(bit [63:0] d);
        // Envía un bloque con txc=00 (todos los bytes son datos puros)
        drive_word(d, 8'h00, d, 8'h00, "data");
    endtask

    virtual task drive_start(int lane);
        bit [63:0] d = `XGMII_IDLE_W; // Base de idles
        bit [7:0]  c;
        case (lane)
            // Si es lane 0, ponemos 0xFB (S) en el byte 0 y txc=01 (solo el byte 0 es control)
            0: begin d[7:0]   = 8'hFB; c = 8'h01; end
            // Si es lane 4, ponemos 0xFB en el byte 4. 
            // txc=1F significa: bytes 0-3 son Idle (control), byte 4 es START (control), bytes 5-7 son datos.
            4: begin d[31:0]  = 32'h07070707; d[39:32] = 8'hFB; c = 8'h1F; end
            default: $fatal(1, "[DRV] START solo en lane 0 o 4");
        endcase
        drive_word(d, c, d, c, "start");
    endtask

    virtual task drive_term(int lane);
        bit [63:0] d = `XGMII_IDLE_W;
        // Truco de máscara: 8'hFF << lane. Si lane=2, c = 1111_1100 (lanes 2 a 7 son control).
        // Esto enciende los bits de control exactos para cerrar la trama en esa lane.
        bit [7:0]  c = 8'hFF << lane; 
        // Ponemos el 0xFD (T - Terminate) en el byte correspondiente
        d[8*lane +: 8] = 8'hFD;
        drive_word(d, c, d, c, "term");
    endtask

    virtual task drive_frame(xgmii_sequence_item tr);
        // Arma una trama completa: START -> Datos -> TERM
        drive_start(tr.start_lane);
        repeat (tr.frame_len) drive_data($urandom); // Mete datos random en el medio
        drive_term(tr.term_lane);
    endtask

    virtual task drive_illegal(xgmii_sequence_item tr);
        // Manda basura intencional (por ejemplo, un txc que no cumple el formato de bloque).
        // El encoder va a devolver 0xFE (Error) en todas las lanes.
        drive_word(tr.data, tr.ctrl, 64'hFEFEFEFEFEFEFEFE, 8'hFF, "illegal");
    endtask
endclass

// =========================================================================
// 3. MONITOR (El que espía los cables físicos de salida del DUT)
// =========================================================================
class xgmii_monitor;
    virtual xgmii_if               vif;
    mailbox #(xgmii_sequence_item) mon2scb; // Buzón para enviarle lo observado al Scoreboard

    function new(virtual xgmii_if vif, mailbox #(xgmii_sequence_item) mon2scb);
        this.vif     = vif;
        this.mon2scb = mon2scb;
    endfunction

    virtual task run();
        xgmii_sequence_item t;
        forever begin
            @(vif.mon_cb); // Esperar flanco de reloj (usa el clocking block del monitor)
            
            // Si no hay reset y el RX nos avisa que hay un dato válido en el cable...
            if (vif.mon_cb.rst === 1'b0 && vif.mon_cb.rx_valid === 1'b1) begin
                // Instanciamos un item temporal 't' para guardar lo que vimos
                t            = new();
                t.cyc        = vif.mon_cb.cyc;     // Sellar el ciclo en que llegó
                t.got_rxd    = vif.mon_cb.rxd;     // Capturar dato
                t.got_rxc    = vif.mon_cb.rxc;     // Capturar control
                mon2scb.put(t);                    // Mandarlo al Scoreboard
            end
        end
    endtask
endclass

// =========================================================================
// 4. SCOREBOARD (El cerebro que compara lo que enviamos vs lo que recibimos)
// =========================================================================
class xgmii_scoreboard;
    mailbox #(xgmii_sequence_item) drv2scb; // Recibe lo del Driver
    mailbox #(xgmii_sequence_item) mon2scb; // Recibe lo del Monitor

    // Arrays Asociativos: Funcionan como diccionarios. 
    // La 'clave' (key) es el número de ciclo (int). El 'valor' es el objeto.
    // Nos permiten buscar "qué dato envié en el ciclo 50?" de forma instantánea.
    xgmii_sequence_item exp_by_cyc [int unsigned];
    xgmii_sequence_item mon_by_cyc [int unsigned];

    int errors = 0, checks = 0;
    int exp_lat = 3; // Latencia esperada del DUT (3 ciclos: 1 enc + 1 dec + 1 muestreo)

    function new(mailbox #(xgmii_sequence_item) drv2scb, 
                 mailbox #(xgmii_sequence_item) mon2scb, 
                 int exp_lat = 3);
        this.drv2scb = drv2scb;
        this.mon2scb = mon2scb;
        this.exp_lat = exp_lat;
    endfunction

    // Vacia los buzones y guarda todo en los arrays usando el ciclo como índice
    function void drain();
        xgmii_sequence_item t;
        while (drv2scb.try_get(t)) exp_by_cyc[t.cyc] = t;
        while (mon2scb.try_get(t)) mon_by_cyc[t.cyc] = t;
    endfunction

    // La comparación real
    function void check();
        xgmii_sequence_item e, g;
        drain();
        
        // Recorremos TODO lo que el driver dijo que envió (k = número de ciclo)
        foreach (exp_by_cyc[k]) begin
            e = exp_by_cyc[k];
            checks++;
            
            // Si el monitor NO capturó nada en el ciclo (k + latencia), es un error.
            // Ejemplo: Si enviamos en el ciclo 10, y la latencia es 3, el monitor debería tener algo en el ciclo 13.
            if (!mon_by_cyc.exists(k + exp_lat)) begin
                $error("[SCB] cyc %0d (%s): sin muestra en monitor", k, e.tag);
                errors++;
            end else begin
                // Si capturó algo, lo comparamos
                g = mon_by_cyc[k + exp_lat];
                if (g.got_rxd !== e.exp_rxd || g.got_rxc !== e.exp_rxc) begin
                    $error("[SCB] cyc %0d (%s): exp %h/%h, got %h/%h", k, e.tag, e.exp_rxd, e.exp_rxc, g.got_rxd, g.got_rxc);
                    errors++;
                end
            end
        end
    endfunction

    // Imprime el resultado final en consola
    function void report();
        $display("========================================");
        $display("[SCB] Checks=%0d Errors=%0d", checks, errors);
        if (errors == 0 && checks > 0) $display("[SCB] *** PASS ***");
        else                           $display("[SCB] *** FAIL ***");
        $display("========================================");
    endfunction
endclass

`endif