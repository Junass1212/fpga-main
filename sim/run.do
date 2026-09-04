# fpga-main全链路仿真: Sobel(demo2移植) + OSD(demo3)
vlib work
vlog src/soft_fifo_al_4057d6b76aa6.v \
     src/w128_d512_fifo.v \
     src/uivtc.v \
     src/video_in.v \
     src/video_out.v \
     src/edge_detect_96.v \
     src/data_96bit_to_128bit.v \
     src/osd_char_lib.v \
     src/anlogic_logo_rom.v \
     src/hdmi_mixer.v \
     tb_fpgamain.v
vsim work.tb_fpgamain
run -all
quit -f
