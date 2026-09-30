`timescale 1ns / 1ps
/*=========================================================================
 * aurora_led.v — LED 外设模块（aurora 单窗口的“外设”示例）。
 *
 * 寄存器组只管寄存器（aurora_regbank），外设模块只管引脚驱动。二者通过
 * 一根级别的握手线耦合：led_value_i/led_en_i 来自寄存器组（由 PS 写）。
 * “加外设”就照这个模式加一个模块 + 在 JSON 加寄存器即可。
 *========================================================================*/
module aurora_led (
    input  wire [3:0] led_value_i,  // 控制值：bit0->LED0 ... bit3->LED3（高电平点亮）
    input  wire       led_en_i,     // 使能：0 全灭, 1 按 value 点亮
    output wire [3:0] led_o,        // 到引脚
    output wire [3:0] led_status_o  // 实际输出回读（= led_o），供寄存器组 LED_STATUS
);

    assign led_o        = led_en_i ? led_value_i : 4'b0000;
    assign led_status_o = led_o;

endmodule