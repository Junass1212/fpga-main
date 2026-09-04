`timescale 1ns/1ps
//============================================================
// demo3 (lab_hd_3_osd) 显示侧子系统仿真
// 实例化真实 uivtc + video_out + hdmi_mixer(含OSD), 只stub掉DDR读口
// 期望输出: 每帧 = 背景图案 + 左上角160x160安路Logo + (375,120)处 "安路 CNT:n"
//============================================================
module tb_demo3;

    reg clk_pix = 1'b0;      // 51.2MHz像素时钟 (1344*635*60)
    reg clk_ddr = 1'b0;      // 100MHz, 模拟DDR用户口时钟
    reg rst_n   = 1'b0;
    always #9.765 clk_pix = ~clk_pix;
    always #5.0    clk_ddr = ~clk_ddr;

    // vtc输出
    wire vs, hs, de, user, last;
    // mixer <-> video_out
    wire        rd_en;
    wire [23:0] pix_data;
    wire        vo_rd_busy;
    wire        out_vs, out_hs, out_de;
    wire [23:0] out_data;
    // video_out -> fake ddr
    wire        ddr_rd_en;
    wire [24:0] ddr_addr;
    reg         ddr_rd_valid;
    reg [127:0] ddr_rd_data;

    //---------------- 视频时序发生(真实模块) ----------------
    uivtc #(
        .H_ActiveSize(1024), .H_FrameSize(1344), .H_SyncStart(1184), .H_SyncEnd(1208),
        .V_ActiveSize( 600), .V_FrameSize( 635), .V_SyncStart( 612), .V_SyncEnd( 614)
    ) u_vtc (
        .I_vtc_rstn    (rst_n),
        .I_vtc_clk     (clk_pix),
        .O_vtc_vs      (vs),
        .O_vtc_hs      (hs),
        .O_vtc_de_valid(de),
        .O_vtc_user    (user),
        .O_vtc_last    (last)
    );

    //---------------- OSD混合器(demo3真实模块) ----------------
    hdmi_mixer #(
        .H_OFFSET (0),
        .V_OFFSET (0),
        .IMG_WIDTH (1024),
        .IMG_HEIGHT(600),
        .DEBUG_MODE(0)
    ) u_mixer (
        .I_clk           (clk_pix),
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

    //---------------- DDR读出(真实模块,只stub存储器) ----------------
    video_out u_video_out (
        .I_rst_n            (rst_n),
        .I_ddr_clk          (clk_ddr),
        .O_video_out_rd_busy(vo_rd_busy),
        .I_video_in_wr_busy (1'b0),          // 仿真中无摄像头写入
        .I_video_out_rp     (2'd0),          // 固定读0号缓冲
        .O_ddr_user_rd_en   (ddr_rd_en),
        .O_ddr_user_addr    (ddr_addr),
        .I_ddr_user_ready   (1'b1),
        .I_ddr_user_rd_valid(ddr_rd_valid),
        .I_ddr_user_rd_data (ddr_rd_data),
        .I_dsi_clk          (clk_pix),
        .I_video_vsync      (~vs),           // 与真实顶层一致: S_video_out_vsync=~S_hdmi_vsync
        .I_video_rd_en      (rd_en),
        .O_vdieo_data       (pix_data)
    );

    //---------------- 假DDR: 1拍延迟返回背景帧 ----------------
    reg [127:0] bg_mem [0:115199];
    initial $readmemh("bg_frame.hex", bg_mem);
    always @(posedge clk_ddr) begin
        ddr_rd_valid <= ddr_rd_en;
        if (ddr_rd_en) ddr_rd_data <= bg_mem[ddr_addr[24:3]];
    end

    //---------------- 输出捕获: de有效像素写入raw文件 ----------------
    integer fd;
    integer frame_cnt = 0;
    reg vs_d = 1'b0;
    initial fd = $fopen("frames.raw", "wb");

    always @(posedge clk_pix) begin
        if (out_de) begin
            $fwrite(fd, "%c", out_data[23:16]);
            $fwrite(fd, "%c", out_data[15:8]);
            $fwrite(fd, "%c", out_data[7:0]);
        end
    end

    always @(posedge clk_pix) begin
        vs_d <= out_vs;
        if (out_vs && !vs_d) begin
            frame_cnt <= frame_cnt + 1;
            $display("[%0t] frame %0d done", $time, frame_cnt);
        end
    end

    //---------------- 复位与结束控制 ----------------
    initial begin
        #200 rst_n = 1'b1;
        // 一帧 = 1344*635*19.53ns ≈ 16.67ms, 跑3帧半留余量
        #52_000_000;
        $display("SIM_DONE frames=%0d", frame_cnt);
        $fclose(fd);
        $finish;
    end

    // 安全超时
    initial begin
        #80_000_000;
        $display("TIMEOUT!");
        $fclose(fd);
        $finish;
    end

endmodule
