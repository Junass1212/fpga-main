`timescale 1ns/1ps
//============================================================
// fpga-main (demo3 OSD + demo2 Sobel移植) 全链路仿真
//
// 摄像头侧(真实模块): RGB流发生器 -> edge_detect_96(Sobel)
//     -> data_96bit_to_128bit -> video_in(异步FIFO+240字突发+4缓冲环)
// 假DDR: 可读写的存储器数组(复刻顶层"写优先"地址mux)
// 显示侧(真实模块): uivtc -> video_out(读出+拆像素) -> hdmi_mixer(OSD)
// 期望输出: Sobel边缘图背景 + 左上角安路Logo + "安路 CNT:n"递增
//============================================================
module tb_fpgamain;

    //---------- 三时钟域(照抄真实系统) ----------
    reg cam_clk = 1'b0;      // 50MHz 摄像头/ISP域(真实=csi_rx_clk)
    reg ddr_clk = 1'b0;      // 100MHz DDR用户口域
    reg pix_clk = 1'b0;      // 51.2MHz 显示域
    always #10    cam_clk = ~cam_clk;
    always #5     ddr_clk = ~ddr_clk;
    always #9.765 pix_clk = ~pix_clk;

    reg rst_n = 1'b0;

    localparam BEATS = 153600;   // 1024*600/4

    //---------- 摄像头流发生器 ----------
    reg [95:0] beats [0:BEATS-1];
    reg        tvalid = 0, tuser = 0, tlast = 0;
    reg [95:0] tdata  = 0;
    integer    f, k;
    initial $readmemh("test_in_beats.hex", beats);

    initial begin : camera
        wait (rst_n);
        // 关键: 等到20ms再启动摄像头(显示侧第一帧场同步在16.13ms结束)。
        // 原因: video_in/video_out的FIFO复位是异步的、只在各自帧开始脉冲时触发;
        // 仿真里FIFO内部指针从X起步, 收到第一次复位脉冲前处于X锁死(硬件上电为0,无此问题)。
        // 若摄像头数据在显示侧FIFO"苏醒"前到来, 会因rd_busy=X全部积压溢出。
        #20_000_000;
        repeat (50) @(posedge cam_clk);
        for (f = 0; f < 5; f = f + 1) begin
            for (k = 0; k < BEATS; k = k + 1) begin
                @(posedge cam_clk);
                tvalid <= 1'b1;
                tuser  <= (k == 0);
                tlast  <= (k == BEATS-1);
                tdata  <= beats[k];
            end
            @(posedge cam_clk);
            tvalid <= 1'b0; tuser <= 1'b0; tlast <= 1'b0;
            repeat (2000) @(posedge cam_clk);   // 帧间隙40us
        end
        $display("[%0t] camera done: 4 frames sent", $time);
    end

    //---------- Sobel边缘检测(demo2真实模块) ----------
    wire        edge_tvalid, edge_tuser, edge_tlast;
    wire [95:0] edge_tdata;
    edge_detect_96 #(
        .IMG_WIDTH  (1024),
        .IMG_HEIGHT (600),
        .EDGE_TH_LOW (11'd130),
        .EDGE_TH_HIGH(11'd190)
    ) u_edge (
        .I_clk   (cam_clk),
        .I_rst_n (rst_n),
        .I_tlast (tlast),
        .I_tuser (tuser),
        .I_tdata (tdata),
        .I_tvalid(tvalid),
        .I_tready(1'b1),
        .O_tlast (edge_tlast),
        .O_tuser (edge_tuser),
        .O_tdata (edge_tdata),
        .O_tvalid(edge_tvalid),
        .O_tready()
    );

    //---------- 96->128位宽转换(真实模块) ----------
    wire         conv_fs, conv_v;
    wire [127:0] conv_d;
    data_96bit_to_128bit u_conv (
        .I_clk             (cam_clk),
        .I_rst_n           (rst_n),
        .I_96b_frame_start(edge_tuser),
        .I_96b_valid       (edge_tvalid),
        .I_96b_data        (edge_tdata),
        .O_128b_frame_start(conv_fs),
        .O_128b_valid      (conv_v),
        .O_128b_data       (conv_d)
    );

    //---------- 写入侧(真实模块) ----------
    wire        vi_we;
    wire [24:0] vi_a;
    wire [127:0] vi_d;
    wire        vi_busy;
    wire [1:0]  rp;
    wire        vo_busy;

    video_in u_video_in (
        .I_rst_n            (rst_n),
        .I_camera_clk       (cam_clk),
        .I_camera_frame_start(conv_fs),
        .I_camera_valid     (conv_v),
        .I_camera_data      (conv_d),
        .I_mipi_rx_error    (1'b0),
        .I_ddr_clk          (ddr_clk),
        .I_display_pause    (1'b0),
        .I_video_out_rd_busy(vo_busy),
        .O_video_in_wr_busy (vi_busy),
        .O_video_out_rp     (rp),
        .O_ddr_user_wr_en   (vi_we),
        .O_ddr_user_addr    (vi_a),
        .O_ddr_user_wr_data (vi_d),
        .I_ddr_user_ready   (1'b1)
    );

    //---------- 假DDR: 可写可读, 复刻顶层"写优先"地址mux ----------
    wire        vo_re;
    wire [24:0] vo_a;
    reg         ddr_rv;
    reg [127:0] ddr_rd;
    wire [24:0] ddr_addr = vi_we ? vi_a : (vo_re ? vo_a : 25'd0);

    reg [127:0] dram [0:2740199];
    integer i;
    initial begin
        for (i = 0; i <= 2740199; i = i + 1) dram[i] = 128'd0;
    end
    always @(posedge ddr_clk) begin
        if (vi_we) dram[ddr_addr[24:3]] <= vi_d;
        ddr_rv <= vo_re;
        if (vo_re) ddr_rd <= dram[ddr_addr[24:3]];
    end

    //---------- 诊断探针 ----------
    integer n_edge = 0, n_conv = 0, n_we = 0, n_re = 0;
    always @(posedge cam_clk) begin
        if (edge_tvalid) n_edge <= n_edge + 1;
        if (conv_v)      n_conv <= n_conv + 1;
    end
    always @(posedge ddr_clk) begin
        if (vi_we) begin
            n_we <= n_we + 1;
            if (n_we < 4) $display("[%0t] WRITE#%0d addr=%0d (%h) data=%h", $time, n_we, vi_a, vi_a, vi_d);
        end
        if (vo_re) begin
            n_re <= n_re + 1;
            if (n_re < 4) $display("[%0t] READ#%0d addr=%0d (%h)", $time, n_re, vo_a, vo_a);
        end
    end

    //---------- 显示时序(真实模块) ----------
    wire vs, hs, de, user, last;
    uivtc #(
        .H_ActiveSize(1024), .H_FrameSize(1344), .H_SyncStart(1184), .H_SyncEnd(1208),
        .V_ActiveSize( 600), .V_FrameSize( 635), .V_SyncStart( 612), .V_SyncEnd( 614)
    ) u_vtc (
        .I_vtc_rstn    (rst_n),
        .I_vtc_clk     (pix_clk),
        .O_vtc_vs      (vs),
        .O_vtc_hs      (hs),
        .O_vtc_de_valid(de),
        .O_vtc_user    (user),
        .O_vtc_last    (last)
    );

    //---------- 读出侧(真实模块) ----------
    wire        rd_en;
    wire [23:0] pix_data;
    video_out u_video_out (
        .I_rst_n            (rst_n),
        .I_ddr_clk          (ddr_clk),
        .O_video_out_rd_busy(vo_busy),
        .I_video_in_wr_busy (vi_busy),
        .I_video_out_rp     (rp),
        .O_ddr_user_rd_en   (vo_re),
        .O_ddr_user_addr    (vo_a),
        .I_ddr_user_ready   (1'b1),
        .I_ddr_user_rd_valid(ddr_rv),
        .I_ddr_user_rd_data (ddr_rd),
        .I_dsi_clk          (pix_clk),
        .I_video_vsync      (~vs),
        .I_video_rd_en      (rd_en),
        .O_vdieo_data       (pix_data)
    );

    //---------- OSD混合器(demo3真实模块) ----------
    wire out_vs, out_hs, out_de;
    wire [23:0] out_data;
    hdmi_mixer #(
        .H_OFFSET (0),
        .V_OFFSET (0),
        .IMG_WIDTH (1024),
        .IMG_HEIGHT(600),
        .DEBUG_MODE(0)
    ) u_mixer (
        .I_clk           (pix_clk),
        .I_rst_n         (rst_n),
        .I_video_vsync   (vs),
        .I_video_hsync   (hs),
        .I_video_de      (de),
        .I_video_user    (user),
        .I_video_last    (last),
        .I_debug_status  (4'b0),
        .O_video_rd_en   (rd_en),
        .I_video_rd_data (pix_data),
        .O_hdmi_vsync    (out_vs),
        .O_hdmi_hsync    (out_hs),
        .O_hdmi_de       (out_de),
        .O_hdmi_data     (out_data)
    );

    //---------- 输出捕获 ----------
    integer fd;
    integer frame_cnt = 0;
    reg vs_d = 1'b0;
    initial fd = $fopen("frames.raw", "wb");

    always @(posedge pix_clk) begin
        if (out_de)
            $fwrite(fd, "%c%c%c", out_data[23:16], out_data[15:8], out_data[7:0]);
    end

    always @(posedge pix_clk) begin
        vs_d <= out_vs;
        if (out_vs && !vs_d) begin
            frame_cnt <= frame_cnt + 1;
            $display("[%0t] display frame %0d done", $time, frame_cnt);
        end
    end

    //---------- 复位与结束 ----------
    integer j, nz;
    initial begin
        #200 rst_n = 1'b1;
        wait (frame_cnt == 6);
        #100_000;
        $display("SIM_DONE frames=%0d", frame_cnt);
        $display("COUNTS: edge_valid=%0d conv_valid=%0d ddr_writes=%0d ddr_reads=%0d",
                 n_edge, n_conv, n_we, n_re);
        $display("dram[0]=%h dram[875000]=%h dram[1750000]=%h dram[2625000]=%h",
                 dram[0], dram[875000], dram[1750000], dram[2625000]);
        nz = 0;
        for (j = 875000; j < 990200; j = j + 1)
            if (dram[j] !== 128'd0) nz = nz + 1;
        $display("buffer1 nonzero words: %0d / 115200", nz);
        $fclose(fd);
        $finish;
    end

    initial begin
        #110_000_000;
        $display("TIMEOUT!");
        $fclose(fd);
        $finish;
    end

endmodule
