`timescale 10ns / 100ps
////////////////////////////////////////////////////////////////////////////////
//
// Filename: 	toplevel.v
//
// Project:	CMod S6 System on a Chip, ZipCPU demonstration project
//
// Purpose:	This is (supposed to be) the one Xilinx specific file in the
//		project.  The idea is that all of the board specific logic,
//	the logic used in simulation, is kept in the busmaster.v  file.  It's
//	not quite true, since rxuart and txuart modules are instantiated here,
//	but it's mostly true.
//
//	One thing that makes this module unique is that all of its inputs and
//	outputs must match those on the chip, as specified within the cmod.ucf
//	file (up one directory).
//
//	Within this file you will find specific I/O for output pins, such as
//	the necessary adjustments to make an I2C port from GPIO pins, as well
//	as the clock management approach.
//
//
//
// Creator:	Dan Gisselquist, Ph.D.
//		Gisselquist Technology, LLC
//
////////////////////////////////////////////////////////////////////////////////
//
// Copyright (C) 2015-2016, Gisselquist Technology, LLC
//
// This program is free software (firmware): you can redistribute it and/or
// modify it under the terms of  the GNU General Public License as published
// by the Free Software Foundation, either version 3 of the License, or (at
// your option) any later version.
//
// This program is distributed in the hope that it will be useful, but WITHOUT
// ANY WARRANTY; without even the implied warranty of MERCHANTIBILITY or
// FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License
// for more details.
//
// You should have received a copy of the GNU General Public License along
// with this program.  (It's in the $(ROOT)/doc directory, run make with no
// target there if the PDF file isn't present.)  If not, see
// <http://www.gnu.org/licenses/> for a copy.
//
// License:	GPL, v3, as defined and found on www.gnu.org,
//		http://www.gnu.org/licenses/gpl.html
//
//
////////////////////////////////////////////////////////////////////////////////
//
//
`define	LOWLOGIC_FLASH
module toplevel(i_clk_8mhz,
		o_qspi_cs_n, o_qspi_sck, io_qspi_dat,
		i_btn, o_led, o_pwm, o_pwm_shutdown_n, o_pwm_gain,
			i_uart, o_uart, o_uart_rts_n, i_uart_cts_n,
		i_kp_row, o_kp_col,
		i_gpio, o_gpio,
		io_scl, io_sda);
	input		i_clk_8mhz;
	//
	// Quad SPI Flash
	output	wire		o_qspi_cs_n;
	output	wire		o_qspi_sck;
	inout	wire	[3:0]	io_qspi_dat;
	//
	// General purpose I/O
	input		[1:0]	i_btn;
	output	wire	[3:0]	o_led;
	output	wire		o_pwm, o_pwm_shutdown_n, o_pwm_gain;
	//
	// and our serial port
	input		i_uart;
	output	wire	o_uart;
	//	and it's associated control wires
	output	wire	o_uart_rts_n;
	input		i_uart_cts_n;
	// Our keypad
	input		[3:0]	i_kp_row;
	output	wire	[3:0]	o_kp_col;
	// and our GPIO
	input		[15:2]	i_gpio;
	output	wire	[15:2]	o_gpio;
	// and our I2C port
	inout			io_scl, io_sda;


	//
	// Clock management
	//
	//	Generate a usable clock for the rest of the board to run at.
	//
	wire	ck_zero_0, clk_s, clk_sn;

	// Clock frequency = (20 / 2) * 8Mhz = 80 MHz
	// Clock period = 12.5 ns
	DCM_SP #(
		.CLKDV_DIVIDE(2.0),
		.CLKFX_DIVIDE(2),		// Here's the divide by two
		.CLKFX_MULTIPLY(20),		// and here's the multiply by 20
		.CLKIN_DIVIDE_BY_2("FALSE"),
		.CLKIN_PERIOD(125.0),
		.CLKOUT_PHASE_SHIFT("NONE"),
		.CLK_FEEDBACK("1X"),
		.DESKEW_ADJUST("SYSTEM_SYNCHRONOUS"),
		.DLL_FREQUENCY_MODE("LOW"),
		.DUTY_CYCLE_CORRECTION("TRUE"),
		.PHASE_SHIFT(0),
		.STARTUP_WAIT("TRUE")
	) u0(	.CLKIN(i_clk_8mhz),
		.CLK0(ck_zero_0),
		.CLKFB(ck_zero_0),
		.CLKFX(clk_s),
		.CLKFX180(clk_sn),
		.PSEN(1'b0),
		.RST(1'b0));

	// Baud rate is set by clock rate / baud rate desired.  Thus,
	// 80 MHz / 9600 Baud = 8333, or about 0x208d.  We choose a slow
	// speed such as 9600 Baud to help the CPU keep up with the serial
	// port rate.
	localparam [30:0]	UART_SETUP = 31'h4000208d;

	//
	// BUSMASTER
	//
	//	Busmaster is so named because it contains the wishbone
	//	interconnect that all of the internal devices are hung off of.
	//	To reconfigure this device for another purpose, usually
	//	the busmaster module (i.e. the interconnect) is all that needs
	//	to be changed: either to add more devices, or to remove them.
	//
`ifdef	LOWLOGIC_FLASH
	wire	[1:0]	qspi_sck;
`else
	wire		qspi_sck;
`endif
	wire		qspi_cs_n;
	wire	[3:0]	qspi_dat;
	wire	[1:0]	qspi_bmod;
	wire	[15:0]	w_gpio;

	wire	w_uart_rts_n;
	busmaster	#(.UART_SETUP(UART_SETUP))
		masterbus(clk_s, 1'b0,
		// Serial port wires
		i_uart, o_uart_rts_n, o_uart, i_uart_cts_n,
		// SPI/SD-card flash
		qspi_cs_n, qspi_sck, qspi_dat, io_qspi_dat, qspi_bmod,
		// Board lights and switches
		i_btn, o_led, o_pwm, { o_pwm_shutdown_n, o_pwm_gain },
		// Keypad connections
		i_kp_row, o_kp_col,
		// GPIO lines
		{ i_gpio, io_scl, io_sda }, w_gpio
		);

	//
	// Quad SPI support
	//
	//	Supporting a Quad SPI port requires knowing which direction the
	//	wires are going at each instant, whether the device is in full
	//	Quad mode in, full quad mode out, or simply the normal SPI
	//	port with one wire in and one wire out.  This utilizes our
	//	control wires (qspi_bmod) to set the output lines appropriately.
	//
	//
	//	2'b0?	-- Normal SPI
	//	2'b10	-- Quad Output
	//	2'b11	-- Quad Input
`ifdef	LOWLOGIC_FLASH
	reg		r_qspi_cs_n;
	reg	[1:0]	r_qspi_bmod;
	reg	[3:0]	r_qspi_dat, r_qspi_z;
	reg	[1:0]	r_qspi_sck;
	always @(posedge clk_s)
		r_qspi_sck <= qspi_sck;
	xoddr	xqspi_sck({clk_s, clk_sn}, r_qspi_sck, o_qspi_sck);
	initial	r_qspi_cs_n = 1'b1;
	initial	r_qspi_z = 4'b1101;
	always @(posedge clk_s)
	begin
		r_qspi_dat  <= (qspi_bmod[1]) ? qspi_dat:{ 3'b111, qspi_dat[0]};
		r_qspi_z    <= (!qspi_bmod[1])? 4'b1101
				: ((qspi_bmod[0]) ? 4'h0 : 4'hf);
		r_qspi_cs_n <= qspi_cs_n;
	end

	assign	o_qspi_cs_n    = r_qspi_cs_n;
	assign	io_qspi_dat[0] = (r_qspi_z[0]) ? r_qspi_dat[0] : 1'bz;
	assign	io_qspi_dat[1] = (r_qspi_z[1]) ? r_qspi_dat[1] : 1'bz;
	assign	io_qspi_dat[2] = (r_qspi_z[2]) ? r_qspi_dat[2] : 1'bz;
	assign	io_qspi_dat[3] = (r_qspi_z[3]) ? r_qspi_dat[3] : 1'bz;
`else
	assign io_qspi_dat = (!qspi_bmod[1])?({2'b11,1'bz,qspi_dat[0]})
				:((qspi_bmod[0])?(4'bzzzz):(qspi_dat[3:0]));

	assign	o_qspi_cs_n = qspi_cs_n;
	assign	o_qspi_sck  = qspi_sck;
`endif	// LOWLOGIC_FLASH

	//
	// I2C support
	//
	//	Supporting I2C requires a couple quick adjustments to our
	//	GPIO lines.  Specifically, we'll allow that when the output
	//	(i.e. w_gpio) pins are high, then the I2C lines float.  They
	//	will be (need to be) pulled up by a resistor in order to
	//	match the I2C protocol, but this change makes them look/act
	//	more like GPIO pins.
	//
	assign	io_sda = (w_gpio[0]) ? 1'bz : 1'b0;
	assign	io_scl = (w_gpio[1]) ? 1'bz : 1'b0;
	assign	o_gpio[15:2] = w_gpio[15:2];

endmodule