// Version15 TSE TX/RX MMIO address map.
//
// The 0x10003000..0x100030ff window is the retained TSE wrapper CPU-facing
// control and MMIO-loaded packet-buffer path.
`ifndef TSE_ADDR_MAP_SVH
`define TSE_ADDR_MAP_SVH

`define TSE_BASE_ADDR               32'h10003000
`define TSE_END_ADDR                32'h10003100
`define TSE_ID_ADDR                 32'h10003000
`define TSE_VERSION_ADDR            32'h10003004
`define TSE_CONTROL_ADDR            32'h10003008
`define TSE_STATUS_ADDR             32'h1000300c
`define TSE_SCRATCH_ADDR            32'h10003010
`define TSE_CSR_ADDR_ADDR           32'h10003020
`define TSE_CSR_WDATA_ADDR          32'h10003024
`define TSE_CSR_RDATA_ADDR          32'h10003028
`define TSE_CSR_CMD_ADDR            32'h1000302c
`define TSE_CSR_STATUS_ADDR         32'h10003030
`define TSE_STREAM_CTRL_ADDR        32'h10003040
`define TSE_STREAM_STATUS_ADDR      32'h10003044
`define TSE_TX_DATA_ADDR            32'h10003050
`define TSE_TX_LEN_ADDR             32'h10003054
`define TSE_TX_CMD_ADDR             32'h10003058
`define TSE_TX_STATUS_ADDR          32'h1000305c
`define TSE_TX_COUNT_ADDR           32'h10003060
`define TSE_TX_DEBUG_WORDS_ADDR     32'h10003064
`define TSE_TX_DEBUG_LAST_ADDR      32'h10003068
`define TSE_RX_DATA_ADDR            32'h10003070
`define TSE_RX_LEN_ADDR             32'h10003074
`define TSE_RX_CMD_ADDR             32'h10003078
`define TSE_RX_STATUS_ADDR          32'h1000307c
`define TSE_RX_COUNT_ADDR           32'h10003080
`define TSE_RX_DEBUG_WORDS_ADDR     32'h10003084
`define TSE_RX_DEBUG_LAST_ADDR      32'h10003088
`define TSE_RX_DROP_COUNT_ADDR      32'h1000308c
`define TSE_RX_ERROR_COUNT_ADDR     32'h10003090
`define TSE_MII_DEBUG_CONTROL_ADDR          32'h10003094
`define TSE_MII_TX_FRAME_COUNT_ADDR         32'h10003098
`define TSE_MII_TX_ACTIVE_NIBBLE_COUNT_ADDR 32'h1000309c
`define TSE_MII_TX_ERROR_NIBBLE_COUNT_ADDR  32'h100030a0
`define TSE_MII_RX_FRAME_COUNT_ADDR         32'h100030a4
`define TSE_MII_RX_ACTIVE_NIBBLE_COUNT_ADDR 32'h100030a8
`define TSE_MII_RX_ERROR_NIBBLE_COUNT_ADDR  32'h100030ac
`define TSE_MII_DEBUG_STATUS_ADDR           32'h100030b0

// Backward-compatible names used by the existing wrapper files.
`define TSE_MMIO_BASE_ADDR          32'h10003000
`define TSE_MMIO_ID_ADDR            32'h10003000
`define TSE_MMIO_VERSION_ADDR       32'h10003004
`define TSE_MMIO_CONTROL_ADDR       32'h10003008
`define TSE_MMIO_STATUS_ADDR        32'h1000300c
`define TSE_MMIO_SCRATCH_ADDR       32'h10003010

// Future Avalon-MM CSR bridge registers. These are CPU-facing staging
// registers only; they do not imply that a generated TSE IP is present.
`define TSE_MMIO_CSR_ADDR_ADDR      32'h10003020
`define TSE_MMIO_CSR_WDATA_ADDR     32'h10003024
`define TSE_MMIO_CSR_RDATA_ADDR     32'h10003028
`define TSE_MMIO_CSR_CMD_ADDR       32'h1000302c
`define TSE_MMIO_CSR_STATUS_ADDR    32'h10003030

// Stream datapath status/control. Packet movement is deliberately not
// descriptor-ring based here.
`define TSE_MMIO_STREAM_CTRL_ADDR   32'h10003040
`define TSE_MMIO_STREAM_STATUS_ADDR 32'h10003044
`define TSE_MMIO_TX_DATA_ADDR       32'h10003050
`define TSE_MMIO_TX_LEN_ADDR        32'h10003054
`define TSE_MMIO_TX_CMD_ADDR        32'h10003058
`define TSE_MMIO_TX_STATUS_ADDR     32'h1000305c
`define TSE_MMIO_TX_COUNT_ADDR      32'h10003060
`define TSE_MMIO_TX_DEBUG_WORDS_ADDR 32'h10003064
`define TSE_MMIO_TX_DEBUG_LAST_ADDR 32'h10003068
`define TSE_MMIO_RX_DATA_ADDR       32'h10003070
`define TSE_MMIO_RX_LEN_ADDR        32'h10003074
`define TSE_MMIO_RX_CMD_ADDR        32'h10003078
`define TSE_MMIO_RX_STATUS_ADDR     32'h1000307c
`define TSE_MMIO_RX_COUNT_ADDR      32'h10003080
`define TSE_MMIO_RX_DEBUG_WORDS_ADDR 32'h10003084
`define TSE_MMIO_RX_DEBUG_LAST_ADDR 32'h10003088
`define TSE_MMIO_RX_DROP_COUNT_ADDR 32'h1000308c
`define TSE_MMIO_RX_ERROR_COUNT_ADDR 32'h10003090
`define TSE_MMIO_MII_DEBUG_CONTROL_ADDR          32'h10003094
`define TSE_MMIO_MII_TX_FRAME_COUNT_ADDR         32'h10003098
`define TSE_MMIO_MII_TX_ACTIVE_NIBBLE_COUNT_ADDR 32'h1000309c
`define TSE_MMIO_MII_TX_ERROR_NIBBLE_COUNT_ADDR  32'h100030a0
`define TSE_MMIO_MII_RX_FRAME_COUNT_ADDR         32'h100030a4
`define TSE_MMIO_MII_RX_ACTIVE_NIBBLE_COUNT_ADDR 32'h100030a8
`define TSE_MMIO_MII_RX_ERROR_NIBBLE_COUNT_ADDR  32'h100030ac
`define TSE_MMIO_MII_DEBUG_STATUS_ADDR           32'h100030b0
`define TSE_MMIO_END_ADDR           32'h10003100

// RX_STATUS bits. READY describes a complete CPU-readable frame; it is not
// the Avalon-ST ready/backpressure signal.
`define TSE_RX_STATUS_READY_BIT       0
`define TSE_RX_STATUS_EMPTY_BIT       1
`define TSE_RX_STATUS_OVERFLOW_BIT    2
`define TSE_RX_STATUS_LENGTH_OK_BIT   3
`define TSE_RX_STATUS_LOOPBACK_BIT    4
`define TSE_RX_STATUS_READ_DONE_BIT   5
`define TSE_RX_STATUS_CAPTURING_BIT   6
`define TSE_RX_STATUS_PROTOCOL_ERR_BIT 7
`define TSE_RX_STATUS_DROP_BIT        8
// Synchronous packet-RAM read response. Firmware writes RX_CMD.FETCH, waits
// for DATA_READY, then reads RX_DATA. READ_PENDING is the intervening cycle.
`define TSE_RX_STATUS_DATA_READY_BIT  9
`define TSE_RX_STATUS_READ_PENDING_BIT 10

// RX_CMD bits. CLEAR and REWIND retain their legacy meanings; FETCH requests
// one word from the current RX read pointer through the synchronous RAM port.
`define TSE_RX_CMD_CLEAR_BIT          0
`define TSE_RX_CMD_REWIND_BIT         1
`define TSE_RX_CMD_FETCH_BIT          2

`define TSE_PROBE_ID_VALUE          32'h54534531
// Keep the legacy software-visible probe version stable so v17/v18/v19
// acceptance images remain reproducible.  v20 capability is identified by
// the documented MII debug MMIO range rather than by changing this ABI word.
`define TSE_PROBE_VERSION_VALUE     32'h00001500

// MII_DEBUG_CONTROL bits.
`define TSE_MII_DEBUG_CONTROL_CLEAR_BIT 0

// MII_DEBUG_STATUS bits. CDC valid only means that the CPU-side two-flop
// capture stages have left reset; it is not an MII-clock or PHY-link proof.
`define TSE_MII_DEBUG_STATUS_TX_CDC_VALID_BIT    0
`define TSE_MII_DEBUG_STATUS_RX_CDC_VALID_BIT    1
`define TSE_MII_DEBUG_STATUS_TX_CLEAR_PENDING_BIT 2
`define TSE_MII_DEBUG_STATUS_RX_CLEAR_PENDING_BIT 3

`endif
