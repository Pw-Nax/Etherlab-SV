### TESTPLAN for: xgmii_top.sv (Encoder + Decoder Loopback)

Test planteados según IEEE 802.3 (Cláusula 49: 64B/66B PCS para 10GBASE-R).



| ID de Prueba | Nombre de Prueba | Nombre de Archivo | Estado | Descripción |
| :--- | :--- | :--- | :---: | :--- |
| **0** | `sanity_reset` | `TC0_sanity_reset` | **[ - ]** | 1) Aplicar `rst = 1`.<br>2) Comprobar salidas iniciales del DUT.<br>3) Verificar que `tx_bad_block`, `rx_bad_block` y `rx_sequence_error` permanezcan en `0`.<br>4) Liberar reset y verificar que `xgmii_rxd` y `xgmii_rxc` no presenten estados desconocidos (`X`) o de alta impedancia (`Z`). |
| **1** | `tx_rx_idle` | `TC1_tx_rx_idle` | **[✅ Hecho]** | 1) Aplicar y liberar reset.<br>2) Conducir `xgmii_txd` con caracteres de control Idle (`0x0707...`) y `xgmii_txc = 0xFF`.<br>3) Comprobar que el Decoder devuelva exactamente los mismos caracteres de Idle en `xgmii_rxd` y `xgmii_rxc = 0xFF` tras la latencia del pipeline. |
| **2** | `tx_rx_data` | `TC2_tx_rx_data` | **[✅ Hecho]** | 1) Enviar un bloque puro de datos (`xgmii_txc = 0x00`, `xgmii_txd = 0xDEADBEEF...`).<br>2) Verificar que el Encoder genere un bloque `SYNC_DATA` (`2'b01`).<br>3) Comprobar que el Decoder devuelva la misma carga útil en `xgmii_rxd` con `xgmii_rxc = 0x00` (transparencia de datos puros). |
| **3** | `basic_frame_lane0` | `TC3_basic_frame_lane0` | **[✅ Hecho]** | 1) Enviar trama completa XGMII con delimitadores en Lane 0:<br>&nbsp;&nbsp;&nbsp;&nbsp;1.1) Start (`0xFB`) en Lane 0 (`xgmii_txc = 0x01`).<br>&nbsp;&nbsp;&nbsp;&nbsp;1.2) Bloques de datos (`xgmii_txc = 0x00`).<br>&nbsp;&nbsp;&nbsp;&nbsp;1.3) Terminate (`0xFD`) en Lane 0 (`xgmii_txc = 0xFF`).<br>2) Comprobar alineación correcta del delimitador Start y Terminate en la recepción (`xgmii_rxd`, `xgmii_rxc`). |
| **4** | `basic_frame_lane4` | `TC4_basic_frame_lane4` | **[✅ Hecho]** | 1) Enviar trama con Start (`0xFB`) posicionado en Lane 4 (`xgmii_txc = 0x1F`).<br>2) Transmitir carga útil de datos.<br>3) Finalizar con Terminate en Lane 4 (`xgmii_txc = 0xF0`).<br>4) Comprobar que el Encoder y Decoder procesen correctamente la segunda posición de alineación válida permitida por norma. |
| **5** | `invalid_block_noformat` | `TC5_invalid_block_noformat` | **[✅ Hecho]** | 1) Inyectar un patrón de control con máscara sin formato válido en la tabla 64B/66B (ej. `xgmii_txc = 0x02` con Start en Lane 0).<br>2) Comprobar que el Encoder levante el flag `tx_bad_block = 1`.<br>3) Verificar que el Decoder identifique el bloque inválido y fuerce la salida a `0xFE` (`XGMII_ERROR`) con `xgmii_rxc = 0xFF` sin colgar la máquina de estados. |
| **6** | `term_lanes_sweep` | `TC6_term_lanes_sweep` | **[ - ]** | 1) Generar tramas con el carácter Terminate (`0xFD`) ubicado secuencialmente en las 8 posiciones posibles (Lanes 0 a 7).<br>2) Verificar que el Encoder seleccione los 8 *Block Type Fields* correspondientes (`0x87`, `0x99`, `0xAA`, `0xB4`, `0xCC`, `0xD2`, `0xE1`, `0xE1/0xFF`).<br>3) Comprobar la reconstrucción exacta de la máscara `xgmii_rxc` en el Decoder para cada caso. |
| **7** | `data_ctrl_lookalikes` | `TC7_data_ctrl_lookalikes` | **[ - ]** | 1) Transmitir bloques de datos puros (`xgmii_txc = 0x00`) cargados con bytes que coinciden numéricamente con caracteres de control (`0xFB`, `0xFD`, `0x07`, `0xFE`).<br>2) Verificar que el Encoder preserve el *Sync Header* `2'b01` (Data) y no interprete falsos delimitadores.<br>3) Comprobar la transparencia total de los datos a la salida del RX. |
| **8** | `invalid_control_char` | `TC8_invalid_control_char` | **[ - ]** | 1) Transmitir un bloque de control (`xgmii_txc = 0xFF`) inyectando caracteres de control no reconocidos o reservados (ej. `0x00`, `0xAA`).<br>2) Verificar la activación del flag de error en el Encoder (`tx_bad_block`).<br>3) Comprobar que el Decoder reemplace únicamente el byte afectado por el carácter de error `0xFE` en `xgmii_rxd`. |
| **9** | `rx_sequence_error_term` | `TC9_rx_seq_err_term` | **[ - ]** | 1) Transmitir una secuencia de Idles seguida directamente por un carácter Terminate (`0xFD`) sin un Start previo.<br>2) Verificar que el Decoder detecte la violación de secuencia del protocolo IEEE 802.3.<br>3) Comprobar que el flag `rx_sequence_error` emita un pulso en alto de exactamente 1 ciclo. |
| **10** | `rx_sequence_error_start` | `TC10_rx_seq_err_start` | **[ - ]** | 1) Transmitir un delimitador Start (`0xFB`).<br>2) Antes de enviar un Terminate, inyectar un segundo delimitador Start.<br>3) Verificar la detección de trama abortada y la activación inmediata del flag `rx_sequence_error`. |
| **11** | `stress_ifg_minimum` | `TC11_stress_ifg_minimum` | **[ - ]** | 1) Transmitir un flujo continuo de tramas con Inter-Frame Gap (IFG) mínimo (Terminación seguida inmediatamente por Start en el ciclo siguiente).<br>2) Verificar que el pipeline de codificación/decodificación mantenga el rendimiento del 100% (*back-to-back*) sin corrupción de delimitadores ni desalineación de latencia. |
| **12** | `tx_valid_backpressure` | `TC12_tx_valid_backpressure` | **[ - ]** | 1) Bajar el flag `xgmii_tx_valid` a `0` en medio de una transmisión de trama.<br>2) Comprobar el comportamiento de congelamiento (*stall*) o inserción de Idles/Errores en el Encoder.<br>3) Verificar que el RX recupere la sincronía de la trama al restablecer `xgmii_tx_valid = 1`. |


```cpp
   ┌──────────┐  new() + set campos  ┌──────────┐
   │   TEST   │ ───────────────────► │   tr     │
   └──────────┘                      └──────────┘
                                          │
                                          │ drv_mb.put(tr)
                                          ▼
                                     ┌──────────┐
                                     │ MAILBOX  │  (cola FIFO)
                                     │  drv_mb  │
                                     └──────────┘
                                          │
                                          │ drv_mb.get(tr)
                                          ▼
   ┌──────────┐  case(tr.drv_op)    ┌──────────┐
   │  DRIVER  │ ◄─────────────────── │   tr     │
   │          │ drive_xxx(tr)        └──────────┘
   └────┬─────┘
        │ señales al DUT
        ▼
   ┌──────────┐                    ┌──────────┐
   │   DUT    │ ──► rxd/rxc ────►  │ MONITOR  │
   └──────────┘                    └────┬─────┘
                                        │ mon2scb.put(tr')
                                        ▼
                                   ┌──────────┐
                                   │SCOREBOARD│ ◄── drv2scb.put(tr) (del driver)
                                   └──────────┘

```
