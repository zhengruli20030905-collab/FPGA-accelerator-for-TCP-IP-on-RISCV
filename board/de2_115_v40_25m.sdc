# DE2-115 v40 formal 25 MHz CPU/MMIO/system constraints.

create_clock -name CLOCK_50 -period 20.000 [get_ports CLOCK_50]

# The formal revision selects cpu_pll_25m to derive the CPU/MMIO/TSE ff-side clock
# from CLOCK_50. The PLL output is 25 MHz. Let TimeQuest derive the PLL
# generated clock from the ALTPLL configuration instead of constraining a
# fabric register divider.
derive_pll_clocks

# ENET0 MII clocks come from the 88E1111 PHY. In 100 Mbps MII mode they are
# 25 MHz. The generated TSE IP uses internal FIFO/CDC logic between these
# clocks and the CPU/MMIO/ff_tx domain.
create_clock -name ENET0_TX_CLK_25M -period 40.000 [get_ports ENET0_TX_CLK]
create_clock -name ENET0_RX_CLK_25M -period 40.000 [get_ports ENET0_RX_CLK]

# MII receive inputs are captured relative to ENET0_RX_CLK. MII transmit
# outputs are driven relative to ENET0_TX_CLK. These are simple board-prep
# constraints, not a substitute for a final PHY timing characterization.
set_input_delay -clock ENET0_RX_CLK_25M -max 10.000 \
    [get_ports {ENET0_RX_DATA[*] ENET0_RX_DV ENET0_RX_ER ENET0_RX_CRS ENET0_RX_COL}]
set_input_delay -clock ENET0_RX_CLK_25M -min 0.000 \
    [get_ports {ENET0_RX_DATA[*] ENET0_RX_DV ENET0_RX_ER ENET0_RX_CRS ENET0_RX_COL}]

set_output_delay -clock ENET0_TX_CLK_25M -max 10.000 \
    [get_ports {ENET0_TX_DATA[*] ENET0_TX_EN ENET0_TX_ER}]
set_output_delay -clock ENET0_TX_CLK_25M -min 0.000 \
    [get_ports {ENET0_TX_DATA[*] ENET0_TX_EN ENET0_TX_ER}]

# Custom MII observability CDC. These exceptions terminate only at the
# first stage of explicit two-flop synchronizers in tse_mii_debug_monitor:
# source Gray counter -> CPU, CPU clear-toggle -> TX/RX, and TX/RX clear-ack
# -> CPU.  They do not alter any generated Intel TSE CDC constraints.
set_false_path -from [get_registers {*u_mii_debug_monitor*tx_frame_gray_source*}] \
    -to [get_registers {*u_mii_debug_monitor*tx_frame_gray_sync1*}]
set_false_path -from [get_registers {*u_mii_debug_monitor*tx_active_gray_source*}] \
    -to [get_registers {*u_mii_debug_monitor*tx_active_gray_sync1*}]
set_false_path -from [get_registers {*u_mii_debug_monitor*tx_error_gray_source*}] \
    -to [get_registers {*u_mii_debug_monitor*tx_error_gray_sync1*}]
set_false_path -from [get_registers {*u_mii_debug_monitor*rx_frame_gray_source*}] \
    -to [get_registers {*u_mii_debug_monitor*rx_frame_gray_sync1*}]
set_false_path -from [get_registers {*u_mii_debug_monitor*rx_active_gray_source*}] \
    -to [get_registers {*u_mii_debug_monitor*rx_active_gray_sync1*}]
set_false_path -from [get_registers {*u_mii_debug_monitor*rx_error_gray_source*}] \
    -to [get_registers {*u_mii_debug_monitor*rx_error_gray_sync1*}]
set_false_path -from [get_registers {*u_mii_debug_monitor*clear_request_toggle*}] \
    -to [get_registers {*u_mii_debug_monitor*tx_clear_request_sync1*}]
set_false_path -from [get_registers {*u_mii_debug_monitor*clear_request_toggle*}] \
    -to [get_registers {*u_mii_debug_monitor*rx_clear_request_sync1*}]
set_false_path -from [get_registers {*u_mii_debug_monitor*tx_clear_ack_toggle*}] \
    -to [get_registers {*u_mii_debug_monitor*tx_clear_ack_sync1*}]
set_false_path -from [get_registers {*u_mii_debug_monitor*rx_clear_ack_toggle*}] \
    -to [get_registers {*u_mii_debug_monitor*rx_clear_ack_sync1*}]

# KEY[0] is the external active-low manual reset source. It is adapted to the
# active-high PLL input, then cpu_reset_async_n is synchronized into cpu_rst_n.
set_false_path -from [get_ports {KEY[0]}]

# Board switches/buttons are asynchronous and are synchronized before CPU/MMIO
# use, so only the async input-to-first-sync-flop path is cut.
set_false_path -from [get_ports {SW[*]}] -to [get_registers {*u_sw_sync*sync_stage1*}]
set_false_path -from [get_ports {KEY[3] KEY[2] KEY[1]}] -to [get_registers {*u_key31_sync*sync_stage1*}]

# These status/control inputs are not firmware-visible or active datapath pins
# in this board-prep build. If later used for control or MMIO, route them
# through sync_2ff first and constrain only the first synchronizer stage.
set_false_path -from [get_ports {UART_RXD UART_CTS ENET0_INT_N ENET0_LINK100}]

# MDIO remains a low-speed board-prep management interface sampled by the
# mdio_master state machine. It is not treated as a generic CDC block here.
set_false_path -from [get_ports {ENET0_MDIO}]

# Non-MII board outputs are not source-synchronous board timing interfaces in
# this board-prep scope. Active MII packet pins are constrained above.
set_false_path -to [get_ports {LEDR[*] LEDG[*] UART_TXD UART_RTS ENET0_MDC ENET0_MDIO ENET0_RST_N ENET0_GTX_CLK}]

# Reserved JTAG ports are inserted by Intel debug/OpenCore Plus support logic.
# They are not board datapath pins and are constrained separately from active
# CLOCK_50/CPU/MII timing.
set_false_path -from [get_ports {altera_reserved_tdi altera_reserved_tms}]
set_false_path -to [get_ports {altera_reserved_tdo}]

derive_clock_uncertainty
