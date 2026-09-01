# Synthesizable RTL dependency list for Cache.
# Paths are relative to the repository root and ordered lower-level first.

set RTL_FILES [list \
    src/Reg_r.sv \
    src/Reg.sv \
    src/FIFO_FWFT.sv \
    src/FIFO_NF.sv \
    src/Delay_r.sv \
    src/Delay.sv \
    src/Address_Decode.sv \
    src/Flag_Tag_Data_Array.sv \
    src/Replacement.sv \
    src/Compare_Select_Replace.sv \
    src/Dispacher.sv \
    src/Reservation_Station.sv \
    src/MSHR_Response_DeMux.sv \
    src/MSHR_Mux.sv \
    src/MSHR_Entry.sv \
    src/MSHR_File.sv \
    src/MSHR_Request_Arbiter.sv \
    src/Response_Unit.sv \
    src/Cache.sv \
]
