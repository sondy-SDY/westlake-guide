// 红外感应 -> 无人时循环播广告。
//   - 最后一次检测到人之后 T_ABSENT 帧没人 -> 进广告态，从第 7 页开始每 T_AD 帧翻一页
//   - 有人（PIR 拉到高）立刻退出，回到导览
//   - 只有讲解已经播完（narration_done）并且正好落在帧边界，超时才允许接管；
//     讲解中途只留给紧急播报打断（BUG-4）
//   - 拨码 force_absent 一拨 = 帧边界立刻进广告态（现场演示用，不用干等两分钟）；
//     拨回来的那一拍也退出，方便来回对比
// 无人等待 / 广告停留都改成运行时输入（开发者模式里可调），单位是帧（60 fps）。
module guide_ad(
 input pclk,input prst,input frame_boundary,input motion,input force_absent,input enable,
  input narration_done,input [23:0] absent_frames,input [23:0] ad_frames,
  output reg ad,output reg [3:0] ad_page,output reg tick);
 localparam [3:0] AD_FIRST=4'd7, AD_LAST=4'd9;
 reg [23:0] last,rot;reg sel_d;reg ndone_q;
 always @(posedge pclk or posedge prst) begin
  if(prst) begin ad<=0;ad_page<=AD_FIRST;tick<=0;last<=0;rot<=0;sel_d<=0;ndone_q<=0;end
  else begin
   sel_d<=force_absent;
   if(frame_boundary) begin
    ndone_q<=narration_done;
    if(motion) last<=0;else if(last!=24'hffffff) last<=last+1'b1;
    if(ad) begin
     if(rot>=ad_frames-1'b1) begin
      rot<=0;
      ad_page<=(ad_page>=AD_LAST)?AD_FIRST:ad_page+1'b1;
     end else rot<=rot+1'b1;
    end
   end
   if(enable) begin
    if(!ad) begin
     // 超时进广告必须同时满足：帧边界（换页不撕裂）、讲解已结束（不掐断讲解）、无人。
     // narration_done 要连续两个帧边界都为 1（ndone_q 是上一个边界的值）：广告退出那一拍
     // audio_done 还会保持约 200 ns 才被 media 的 flush 清掉，只认一个边界的话，正好撞上
     // 边界就会"刚退出又弹回广告"。多要一个边界只晚 16 ms，彻底躲开这个窄窗口。
     // force_absent 是现场演示开关，只要求帧边界，方便直接对比广告/导览。
     if(frame_boundary && (force_absent || (!motion && narration_done && ndone_q && last>=absent_frames))) begin
      ad<=1'b1;ad_page<=AD_FIRST;rot<=0;tick<=~tick;
     end
    end else begin
     if(force_absent) begin
      // 演示开关一直拨着就停在广告态
     end else if(motion || sel_d) begin
      // 退出广告时无人计时清零：人回来了 / 演示开关拨回来了，就从这一刻重新计 120 s，
      // 不会等讲解一播完又立刻弹回广告。
      ad<=1'b0;ad_page<=AD_FIRST;tick<=~tick;last<=0;
     end
    end
   end
  end
 end
endmodule
