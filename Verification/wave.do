onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate /Basic_Test/clk
add wave -noupdate /Basic_Test/DUT/compare_valid_bits
add wave -noupdate /Basic_Test/DUT/compare_miss
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {257448 ps} 0}
quietly wave cursor active 1
configure wave -namecolwidth 150
configure wave -valuecolwidth 100
configure wave -justifyvalue left
configure wave -signalnamewidth 0
configure wave -snapdistance 10
configure wave -datasetprefix 0
configure wave -rowmargin 4
configure wave -childrowmargin 2
configure wave -gridoffset 0
configure wave -gridperiod 1
configure wave -griddelta 40
configure wave -timeline 0
configure wave -timelineunits ps
update
WaveRestoreZoom {257448 ps} {260344 ps}
