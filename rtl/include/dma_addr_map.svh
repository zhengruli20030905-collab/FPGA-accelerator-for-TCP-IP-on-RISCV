`ifndef DMA_ADDR_MAP_SVH
`define DMA_ADDR_MAP_SVH

// V34 independent TX/RX descriptor-ring packet DMA MMIO window. Both rings
// share one frame scheduler, one segment payload engine, and DMEM Port B.
`define DMA_BASE                  32'h10004000
`define DMA_END                   32'h10004200
`define SG_ID                     32'h10004000
`define SG_CTRL                   32'h10004004
`define SG_STATUS                 32'h10004008
`define SG_ERROR                  32'h1000400c
`define SG_ARB_STATE              32'h10004010
`define SG_LAST_ERROR_RING        32'h10004014
`define SG_LAST_ERROR_DESC        32'h10004018

`define SG_TX_DESC_BASE           32'h10004020
`define SG_TX_RING_SIZE           32'h10004024
`define SG_TX_HEAD                32'h10004028
`define SG_TX_TAIL                32'h1000402c
`define SG_TX_DESC_DONE           32'h10004030
`define SG_TX_BYTES               32'h10004034
`define SG_TX_ERRORS              32'h10004038
`define SG_TX_TAIL_WRITES         32'h1000403c

`define SG_RX_DESC_BASE           32'h10004040
`define SG_RX_RING_SIZE           32'h10004044
`define SG_RX_HEAD                32'h10004048
`define SG_RX_TAIL                32'h1000404c
`define SG_RX_DESC_DONE           32'h10004050
`define SG_RX_BYTES               32'h10004054
`define SG_RX_ERRORS              32'h10004058
`define SG_RX_TAIL_WRITES         32'h1000405c

`define SG_BUSY_CYCLES            32'h10004060
`define SG_IDLE_CYCLES            32'h10004064
`define SG_WAIT_TX_CYCLES         32'h10004068
`define SG_WAIT_RX_CYCLES         32'h1000406c
`define SG_DESC_FETCH_CYCLES      32'h10004070
`define SG_DESC_WRITEBACK_CYCLES  32'h10004074
`define SG_TX_GRANTS              32'h10004078
`define SG_RX_GRANTS              32'h1000407c
`define SG_BOTH_READY_CYCLES      32'h10004080
`define SG_STATE                  32'h10004084
`define SG_CAPABILITY             32'h10004088
`define SG_TX_FRAME_COUNT         32'h1000408c
`define SG_RX_FRAME_COUNT         32'h10004090
`define SG_TX_SEGMENT_COUNT       32'h10004094
`define SG_RX_SEGMENT_COUNT       32'h10004098
`define SG_CHAIN_ERROR_COUNT      32'h1000409c
`define SG_TX_CANCEL_COUNT        32'h100040a0
`define SG_RX_DROP_COUNT          32'h100040a4
`define SG_MAX_TX_SEGMENTS        32'h100040a8
`define SG_MAX_RX_SEGMENTS        32'h100040ac
`define SG_ID_VALUE               32'h5347_3335
`define SG_CAPABILITY_VALUE       32'h0000_03ff
`define SG_CSUM_COUNTER_BASE      32'h10004100
// STATUS bit7 tags checksum result encoding in bits14:8. Legacy transport
// errors retain bit7=0 and the original error code in bits15:8.
`define SG_DESC_CSUM_DONE          16'h0080
`define SG_DESC_IP_OK              16'h0100
`define SG_DESC_L4_OK              16'h0200
`define SG_DESC_CSUM_BAD           16'h0400
`define SG_DESC_CSUM_UNSUPPORTED   16'h0800
`define SG_DESC_UDP_ZERO           16'h1000
`define SG_DESC_CSUM_PATCHED       16'h2000
`define SG_DESC_CSUM_PARSE         16'h4000
`define SG_ERR_CSUM_CONFIG         8'd24
`define SG_ERR_CSUM_PARSE          8'd25
`define SG_ERR_CSUM_PATCH          8'd26
`define SG_ERR_IP_CSUM             8'd27
`define SG_ERR_L4_CSUM             8'd28
`define SG_ERR_CSUM_UNSUPPORTED    8'd29

`define SG_CTRL_ENABLE_BIT        0
`define SG_CTRL_ABORT_BIT         1
`define SG_CTRL_CLEAR_STATUS_BIT  2
`define SG_CTRL_RESET_RING_BIT    3

`define SG_STATUS_BUSY_BIT        0
`define SG_STATUS_IDLE_BIT        1
`define SG_STATUS_WAIT_DESC_BIT   2
`define SG_STATUS_WAIT_TX_BIT     3
`define SG_STATUS_WAIT_RX_BIT     4
`define SG_STATUS_ERROR_BIT       5
`define SG_STATUS_ABORTED_BIT     6
`define SG_STATUS_ENABLED_BIT     7

`define SG_DESC_BUFFER_WORD       0
`define SG_DESC_LENGTH_WORD       1
`define SG_DESC_CONTROL_WORD      2
`define SG_DESC_STATUS_WORD       3
`define SG_DESC_BYTES             16
`define SG_DESC_OWN_BIT           0
`define SG_DESC_DIR_BIT           1
`define SG_DESC_FIRST_BIT         2
`define SG_DESC_LAST_BIT          3
`define SG_DESC_IRQ_BIT           4

`define SG_DESC_DONE_BIT          0
`define SG_DESC_ERROR_BIT         1
`define SG_DESC_ABORTED_BIT       2
`define SG_DESC_TIMEOUT_BIT       3
`define SG_DESC_CONFLICT_BIT      4
`define SG_DESC_BAD_BIT           5
`define SG_DESC_SMALL_BIT         6

`define SG_ERR_NONE               8'd0
`define SG_ERR_BAD_BASE           8'd1
`define SG_ERR_BAD_RING_SIZE      8'd2
`define SG_ERR_BAD_TAIL           8'd3
`define SG_ERR_OWN                8'd4
`define SG_ERR_SEGMENTATION       8'd5
`define SG_ERR_BAD_BUFFER         8'd6
`define SG_ERR_BAD_LENGTH         8'd7
`define SG_ERR_BUFFER_SMALL       8'd8
`define SG_ERR_DESC_TIMEOUT       8'd9
`define SG_ERR_PAYLOAD_TIMEOUT    8'd10
`define SG_ERR_DESC_CONFLICT      8'd11
`define SG_ERR_PAYLOAD_CONFLICT   8'd12
`define SG_ERR_PACKET_CONFLICT    8'd13
`define SG_ERR_ABORTED            8'd14
`define SG_ERR_OVERLAP            8'd15
`define SG_ERR_INTERNAL           8'd16
`define SG_ERR_DIRECTION          8'd17
`define SG_ERR_MISSING_FIRST      8'd18
`define SG_ERR_UNEXPECTED_FIRST   8'd19
`define SG_ERR_MISSING_LAST       8'd20
`define SG_ERR_CHAIN_TOO_LONG     8'd21
`define SG_ERR_CHAIN_ABORTED      8'd22
`define SG_ERR_FRAME_TOO_LARGE    8'd23

`define SG_CAP_MULTI_SEGMENT_BIT  0
`define SG_CAP_UNALIGNED_BIT      1
`define SG_CAP_TX_GATHER_BIT      2
`define SG_CAP_RX_SCATTER_BIT     3
`define SG_CAP_ZERO_COPY_BIT      4

`define SG_ERROR_RING_NONE        2'd0
`define SG_ERROR_RING_TX          2'd1
`define SG_ERROR_RING_RX          2'd2

`endif
