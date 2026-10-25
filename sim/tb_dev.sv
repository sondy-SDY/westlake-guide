`timescale 1ns/1ps
// 开发者模式菜单：SW1 进入、K2/K3 上下、K4 修改、默认值、切手动就近取档、复位回默认、可视化开关、对比度。
module tb_dev;
 reg pclk=0;always #20 pclk=~pclk;
 reg prst=1,sw=0,tu=0,td=0,te=0;reg [8:0] cg=9'd256;
 wire dev;wire [3:0] row;wire [3:0] col;wire bm;wire [8:0] bg;wire [1:0] con;
 wire [23:0] af;wire [1:0] vol;wire [23:0] adf;wire [6:0] ps;wire vu;wire [23:0] sel;
 guide_dev dut(.pclk(pclk),.prst(prst),.sw_dev(sw),.tap_up(tu),.tap_dn(td),.tap_edit(te),.cur_gain(cg),
  .dev(dev),.row(row),.col(col),.bright_manual(bm),.bright_gain(bg),.contrast(con),
  .absent_frames(af),.volume(vol),.ad_frames(adf),.period_s(ps),.vu_on(vu),.sel(sel));
 task up;begin @(negedge pclk);tu=1;@(negedge pclk);tu=0;@(negedge pclk);end endtask
 task dn;begin @(negedge pclk);td=1;@(negedge pclk);td=0;@(negedge pclk);end endtask
 task ed;begin @(negedge pclk);te=1;@(negedge pclk);te=0;@(negedge pclk);end endtask
 task chk(input [3:0] r,input [3:0] c);begin
  if(row!==r||col!==c)$fatal(1,"row=%0d col=%0d want %0d/%0d",row,col,r,c);
 end endtask
 initial begin
  @(negedge pclk);prst=0;@(negedge pclk);
  if(dev!==0)$fatal(1,"dev after reset");
  // 默认：自动 / 75% / 对比度 100% / 20 s / 满 / 12 s / 20 s / 可视化开
  if(bm!==0||bg!==9'd192||con!==2'd1||af!==24'd1200||vol!==2'd2||adf!==24'd720||ps!==7'd20||vu!==1)
   $fatal(1,"defaults bm=%b bg=%0d con=%0d af=%0d vol=%0d adf=%0d ps=%0d vu=%b",bm,bg,con,af,vol,adf,ps,vu);
  sw=1;repeat(3)@(negedge pclk);
  if(dev!==1||row!==0)$fatal(1,"enter dev=%b row=%0d",dev,row);
  chk(0,0);
  dn; chk(1,2);                         // 手动亮度 -> 当前 75%
  ed; chk(1,3);                         // 90%，并且自动切手动
  if(!bm||bg!==9'd230)$fatal(1,"manual switch bm=%b bg=%0d",bm,bg);
  ed; chk(1,4); if(bg!==9'd256)$fatal(1,"100%% bg=%0d",bg);
  ed; chk(1,0); if(bg!==9'd90)$fatal(1,"wrap 35%% bg=%0d",bg);
  up; chk(0,1);                         // 模式=手动
  ed; chk(0,0); if(bm!==0)$fatal(1,"mode auto");
  cg=9'd256; ed; chk(0,1); if(!bm||bg!==9'd256)$fatal(1,"snap to 100%% bg=%0d",bg);
  dn;dn; chk(2,1);                      // 对比度 100%
  ed; chk(2,2); if(con!==2'd2)$fatal(1,"con 125 con=%0d",con);
  ed; chk(2,3); if(con!==2'd3)$fatal(1,"con 150 con=%0d",con);
  ed; chk(2,0); if(con!==2'd0)$fatal(1,"con 75 con=%0d",con);
  ed; chk(2,1); if(con!==2'd1)$fatal(1,"con 100 con=%0d",con);
  dn; chk(3,2);                         // 人体感应延迟
  ed; chk(3,3); if(af!==24'd1800)$fatal(1,"30s af=%0d",af);
  dn; chk(4,2);                         // 音量（满）
  ed; chk(4,0); if(vol!==0)$fatal(1,"vol wrap");
  ed; chk(4,1); ed; chk(4,2);
  dn; chk(5,1);                         // 广告停留 12 s
  ed; chk(5,2); if(adf!==24'd1200)$fatal(1,"20s ad");
  ed; chk(5,0); if(adf!==24'd480)$fatal(1,"8s ad");
  dn; chk(6,1);                         // 周期 20 s
  ed; chk(6,2); if(ps!==7'd30)$fatal(1,"30s period");
  ed; chk(6,3); ed; chk(6,0); if(ps!==7'd10)$fatal(1,"10s period");
  dn; chk(7,1);                         // 音频可视化：默认开
  ed; chk(7,0); if(vu!==0)$fatal(1,"vu off");
  ed; chk(7,1); if(vu!==1)$fatal(1,"vu on");
  dn; chk(8,0);                         // 恢复默认
  ed;
  if(bm!==0||bg!==9'd192||con!==2'd1||af!==24'd1200||vol!==2'd2||adf!==24'd720||ps!==7'd20||vu!==1)
   $fatal(1,"reset defaults bm=%b bg=%0d con=%0d af=%0d vol=%0d adf=%0d ps=%0d vu=%b",bm,bg,con,af,vol,adf,ps,vu);
  chk(8,0);
  up; chk(7,1);
  repeat(7) up; chk(0,0);
  up; chk(8,0);                         // 0 再上移 -> 8
  sw=0;repeat(3)@(negedge pclk);
  if(dev!==0)$fatal(1,"exit dev");
  dn; if(row!==0)$fatal(1,"keys must be ignored outside dev");
  sw=1;repeat(3)@(negedge pclk);
  if(row!==0||col!==0)$fatal(1,"re-enter must reset cursor");
  $display("PASS dev menu: 9 rows, contrast cycle, wrap navigation, snap, defaults, VU");
  $finish;
 end
 initial begin #2000000;$fatal(1,"timeout");end
endmodule
