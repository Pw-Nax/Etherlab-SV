### TESTPLAN for: taxi_eth_phy_10g.sv (sin mac)

    Test planteados según IEEE 802.3



| ID de Prueba | Nombre de Prueba | Nombre de Archivo | Descripción |
| :--- | :--- | :--- | :--- |
| 0 | sanity_reset | TC0_sanity_reset | 1) Aplicar `tx_rst` y `rx_rst`.<br>2) Comprobar las salidas iniciales del DUT.<br>3) Verificar que `tx_bad_block`, `rx_error_count`, `rx_block_lock` y `rx_high_ber` sean 0.<br>4) Liberar el reset y repetir N iteraciones. |
| 1 | sanity_clk_valid | TC1_sanity_clk_valid | 1) Aplicar reset y liberarlo.<br>2) Conducir `tx_clk` y `rx_clk`.<br>3) Establecer `xgmii_tx_valid` = 1.<br>4) Comprobar la salida `serdes_tx_data`.<br>5) Verificar que no haya estados desconocidos (X) o de alta impedancia (Z) en las salidas del SerDes. |
| 2 | tx_idle | TC2_tx_idle | 1) Aplicar reset.<br>2) Conducir `xgmii_txc` con caracteres de control Idle (FF).<br>3) Comprobar que `serdes_tx_hdr` = 2'b10 (Control).<br>4) Comparar `serdes_tx_data` contra los bloques Idle codificados (*scrambled*) esperados. |
| 3 | tx_basic_frame | TC3_tx_basic_frame | 1) Aplicar reset.<br>2) Enviar trama completa vía XGMII:<br>&nbsp;&nbsp;&nbsp;&nbsp;2.1) Preámbulo y SFD<br>&nbsp;&nbsp;&nbsp;&nbsp;2.2) Carga útil (Data)<br>&nbsp;&nbsp;&nbsp;&nbsp;2.3) EFD (Terminate)<br>3) Verificar la alineación del carácter Start en el Lane 0.<br>4) Verificar que `serdes_tx_hdr` = 2'b01 para los bloques de datos.<br>5) Verificar el bloque Terminate correcto y los caracteres Idle subsiguientes. |
| 4 | tx_prbs31 | TC4_tx_prbs31 | 1) Aplicar reset.<br>2) Establecer `cfg_tx_prbs31_enable` = 1.<br>3) Esperar la latencia del pipeline.<br>4) Verificar que `serdes_tx_data` genere una secuencia matemática PRBS31 válida automáticamente. |
| 5 | rx_block_lock | TC5_rx_block_lock | 1) Aplicar reset.<br>2) Enviar *sync headers* válidos continuos (01 o 10) en `serdes_rx_hdr`.<br>3) Esperar exactamente 64 cabeceras válidas consecutivas.<br>4) Comprobar que `rx_block_lock` se ponga en estado alto. |
| 6 | rx_bitslip | TC6_rx_bitslip | 1) Aplicar reset.<br>2) Inyectar secuencia de datos serializados desalineados en `serdes_rx_data`.<br>3) Comprobar que `serdes_rx_bitslip` emita pulsos cíclicamente.<br>4) Verificar que `rx_block_lock` pase a alto una vez que se encuentre la alineación con éxito. |
| 7 | rx_basic_frame | TC7_rx_basic_frame | 1) Aplicar reset y lograr la sincronización de bloques (block lock).<br>2) Enviar trama válida codificada vía `serdes_rx_data`.<br>3) Comprobar la carga útil de salida en `xgmii_rxd`.<br>4) Verificar que Preámbulo, Data y Terminate se mapeen correctamente.<br>5) Verificar que `xgmii_rxc` se actualice correctamente. |
| 8 | rx_high_ber | TC8_rx_high_ber | 1) Aplicar reset y lograr el block lock.<br>2) Inyectar 16 *sync headers* inválidos (00 o 11) dentro de una ventana de 125us.<br>3) Comprobar que `rx_high_ber` pase a estado alto.<br>4) Comprobar que `rx_block_lock` caiga a nivel bajo. |
| 9 | rx_sequence_error | TC9_rx_sequence_error | 1) Aplicar reset y lograr el block lock.<br>2) Enviar una trama válida.<br>3) Inyectar un carácter de control Terminate sin un carácter Start precedente.<br>4) Comprobar un único error de un ciclo en `rx_sequence_error`.<br>5) Verificar que `rx_error_count` se incremente. |
| 10 | rx_prbs31 | TC10_rx_prbs31 | 1) Aplicar reset.<br>2) Establecer `cfg_rx_prbs31_enable` = 1.<br>3) Inyectar secuencia PRBS31 en `serdes_rx_data`.<br>4) Comprobar que `rx_status` permanezca válido sin reportar errores. |
| 11 | tx_invalid_control | TC11_invalid_control | completar


Respecto al skew

> Claus. 44 exige cumplir con los limites de retardos de propagación , el retardo acumulado del PCS, PMA Y PMD no debe superar los 3584 tiempos de bit.
> Verificacion de los margenes de setup y hold
> Para PCS:
> Codificación 64/66B integridad del scrambler para el polinomio x^58 + x^39 + 1 
> MII
> Alineacion de control (start 0XFB) exclusivo para el lane 0 
> validez de txc/rxc
> Adaptación de fin de trama.