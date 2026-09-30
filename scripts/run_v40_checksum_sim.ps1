param([int[]]$Seeds=@(3501,3502,3518))
& "$PSScriptRoot\invoke_v40_questa.ps1" -Name v40_checksum_sim -Top tb_v40_checksum_engine -Sources @('rtl/eth/internet_checksum_engine.sv','sim/tb_v40_checksum_engine.sv') -Seeds $Seeds
