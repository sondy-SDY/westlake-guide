"""Reproducible tests. Requires Icarus Verilog on PATH and Pillow."""
import subprocess,sys,time,json
from pathlib import Path
R=Path(__file__).resolve().parents[1]
UI=['guide_video.v','guide_text.v','guide_ui.v','guide_ui_plain.v','guide_ui_rom.v','guide_ui_sel.v']
TESTS={
 'fat_stream':['guide_fat_stream.v'], 'bmp':['guide_bmp.v'],
 'audio':['guide_audio.v','guide_acr.v'], 'mute':['guide_audio.v'], 'control':['guide_keys.v'], 'media':['guide_media.v'], 'ad':['guide_ad.v'], 'emg':['guide_emg.v'],
 # 环境光自适应：I2C+BH1750 驱动（带从机模型）、lux->亮度映射
 'bh1750':['guide_bh1750.v','guide_i2c_master.v'], 'bright':['guide_bright.v'],
 # 开发者模式菜单 + 音频可视化
 'dev':['guide_dev.v'], 'wave':['guide_wave.v'],
 'video':['guide_memory.v']+UI,
 'telemetry':['guide_telemetry.v','guide_uart.v'],
 'video640':['guide_video_640.v','guide_memory.v','guide_caption.v','guide_subs.v','guide_font_rom.v','guide_text_rom.v','guide_tl_rom.v','guide_wave.v'],
 # BUG-3 回归：缩放只作用于导览页 1..5（只看取行请求序列，不重复像素比对）
 'zoom_gate':['guide_video_640.v','guide_caption.v','guide_subs.v','guide_font_rom.v','guide_text_rom.v','guide_tl_rom.v','guide_wave.v'],
 # 广告平移：页 7->8 逐像素核对 + 每帧取行请求数（平移时每行两份）
 'ad_slide':['guide_video_640.v','guide_caption.v','guide_subs.v','guide_font_rom.v','guide_text_rom.v','guide_tl_rom.v','guide_wave.v'],
 # 'ui' 已移除：1024x600 界面层是废弃的对照件，它的金标准预览图来自已被 v4 取代的 v3 素材包。
}
# Full-frame dumps: tb_ui_frame compares against the supplied gold preview.
DUMPS={'ui':(['+PAGE=1','+AUTO=1','+HEX=build/test/card_p1.hex','+OUT=build/test/frame_p1.txt'],1)}
SOURCES={'ui':'tb_ui_frame','video640':'tb_video_640'}   # ad/emg 的 TB 顶部模块名即测试名
def run(cmd):
    result=subprocess.run(cmd,cwd=R,text=True,encoding='utf-8',errors='replace',capture_output=True)
    if result.returncode:raise RuntimeError(' '.join(cmd)+'\n'+result.stdout+result.stderr)
    return result.stdout+result.stderr
def main():
    print(run([sys.executable,'scripts/make_fixtures.py']),flush=True)
    results=[]
    for name,files in TESTS.items():
        start=time.monotonic();target=f'build/test/{name}.vvp'
        print(f'Running {name}',flush=True)
        src=SOURCES.get(name,'tb_'+name)
        run(['iverilog','-g2012','-s',src,'-o',target,f'sim/{src}.sv']+['rtl/'+f for f in files])
        args=DUMPS[name][0] if name in DUMPS else []
        log=run(['vvp',target]+args);print(log,flush=True)
        if name in DUMPS:
            page=DUMPS[name][1]
            print(run([sys.executable,'scripts/ui_card_hex.py',str(page)]),flush=True)
            sys.path.insert(0,str(R/'scripts'));import ui_check
            outs,ins=ui_check.main(page,'p%d'%page)
            if ins or outs>1500:raise RuntimeError(f'UI frame differs from preview: ui={outs} card={ins}')
            log+=f'PASS UI frame matches preview (outside-card diff {outs} px, card exact)'
        if 'PASS' not in log:raise RuntimeError('No PASS result')
        (R/'reports'/f'test_{name}.log').write_text(log,encoding='utf-8')
        results.append({'test':name,'result':'PASS','seconds':round(time.monotonic()-start,2)})
    (R/'reports/tests.json').write_text(json.dumps(results,indent=2),encoding='utf-8')
if __name__=='__main__':main()