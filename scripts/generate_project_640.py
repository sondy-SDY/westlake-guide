# -*- coding: utf-8 -*-
"""Generate the 640x480@25 MHz TD project (second, independent top)."""
from pathlib import Path
import xml.etree.ElementTree as E

R = Path(__file__).resolve().parents[1]
P = R.parent
NAME = 'westlake_guide_top_640'


def main():
    pins = (R / 'constraints/pins_base.adc').read_text(encoding='utf-8').rstrip('\n') + '\n'
    for name, pin in [('key2', 'B2'), ('key3', 'B1'), ('key4', 'C1'),
                      ('switches[0]', 'C8'), ('switches[1]', 'C7'), ('switches[2]', 'C6'), ('switches[3]', 'C5'),
                      ('HDMI_DDC_SCL', 'P2'), ('HDMI_DDC_SDA', 'R2'), ('uart_tx', 'D12'),
                      ('pir', 'N1'),                                    # J2 13 脚 GPIOB_10（HC-SR501 OUT）
                      ('i2c_scl', 'D14'), ('i2c_sda', 'G11')]:          # J1 1/2 脚，BH1750
        pins += f'set_pin_assignment {{{name}}} {{LOCATION = {pin}; IOSTANDARD = LVCMOS33; PULLTYPE = PULLUP;}}\n'
    (R / 'constraints/pins_640.adc').write_text(pins, encoding='utf-8')
    files = [P / 'vendor/sys_pll.v']
    files += list((P / 'vendor').glob('sdr*.enc.v'))
    files += [P / 'rtl' / n for n in ['spi_byte.v', 'sd_spi_reader.v', 'sdram_bridge.v']]
    files += [R / 'rtl' / n for n in ['westlake_guide_top_640.v', 'guide_video_640.v',
                                     'guide_memory.v', 'guide_bmp.v', 'guide_media.v',
                                     'guide_fat_stream.v', 'guide_audio.v', 'guide_acr.v',
                                     'guide_keys.v', 'guide_telemetry.v', 'guide_uart.v',
                                     'guide_caption.v', 'guide_subs.v', 'guide_emg.v', 'guide_ad.v',
                                     'guide_font_rom.v', 'guide_text_rom.v', 'guide_tl_rom.v',
                                     'guide_i2c_master.v', 'guide_bh1750.v', 'guide_bright.v',
                                     'guide_dev.v', 'guide_wave.v']]
    files += sorted((R / 'vendor').glob('*.v'))
    for run in [None, 'syn_640', 'phy_640']:
        root = E.fromstring((P / 'scripts/project_template.al').read_text(encoding='utf-8').replace('&', '&amp;'))
        root.set('Path', R.as_posix())
        root.find('Name').text = NAME
        top = root.find('TOP_MODULE')
        top.find('LABEL').text = NAME
        top.find('MODULE').text = NAME
        src = root.find('Source_Files')
        src.clear()
        order = 0
        for kind, paths in [('Verilog', files), ('ADC_FILE', [R / 'constraints/pins_640.adc']),
                            ('SDC_FILE', [R / 'constraints/timing_640.sdc'])]:
            group = E.SubElement(src, kind)
            for p in paths:
                order += 1
                fi = E.SubElement(E.SubElement(group, 'File', Path=p.as_posix()), 'FileInfo')
                for k, v in [('UsedInSyn', 'true'), ('UsedInP&R', 'true'),
                             ('BelongTo', 'design_1' if kind == 'Verilog' else 'constraint_1'),
                             ('CompileOrder', str(order))]:
                    E.SubElement(fi, 'Attr', Name=k, Val=v)
        E.indent(root)
        dest = R if run is None else R / 'build' / run
        dest.mkdir(parents=True, exist_ok=True)
        (dest / (NAME + ('.al' if run is None else '.prj'))).write_text(
            '<?xml version="1.0" encoding="UTF-8"?>\n' +
            E.tostring(root, encoding='unicode').replace('&amp;', '&'), encoding='utf-8')
        if run:
            cfg = [f'set ADCList {{{(R / "constraints/pins_640.adc").as_posix()}}}',
                   f'set SDCList {{{(R / "constraints/timing_640.sdc").as_posix()}}}',
                   'set device_name eagle_s20.db', 'set package_name EG4S20BG256',
                   f'set prj_name {NAME}', f'set top_model_name {NAME}',
                   'set area_option -packarea', 'set arr_filter false', 'set drHoldFix on']
            cfg += (['set run_type syn', 'set start_step read_design', 'set end_step opt_gate']
                    if run == 'syn_640' else
                    ['set run_type phy', 'set start_step opt_place', 'set end_step bitgen', 'set parent ../syn_640'])
            (dest / 'settings.cfg').write_text('\n'.join(cfg) + '\n', encoding='utf-8')
    print(R / (NAME + '.al'))


if __name__ == '__main__':
    main()