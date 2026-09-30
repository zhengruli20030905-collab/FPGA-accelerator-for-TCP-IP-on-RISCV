param([int[]]$Seeds=@(3501,3502,3518))
& "$PSScriptRoot\invoke_v40_questa.ps1" -Name v40_sgdma_checksum_sim -Top tb_v40_sgdma_checksum -Sources @('rtl/eth/dma_transfer_engine.sv','rtl/eth/internet_checksum_engine.sv','rtl/eth/sgdma_descriptor_engine.sv','rtl/eth/packet_dma.sv','sim/tb_v40_sgdma_checksum.sv') -Seeds $Seeds
