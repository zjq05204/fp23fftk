-------------------------------------------------------------------------------
--
-- Title       : fp23_logic_m2
-- Design      : fp23fftk
-- Author      : Kapitanov
-- Company     :
--
-- Description : Main module for FFT/IFFT logic
--
-------------------------------------------------------------------------------
-------------------------------------------------------------------------------
--
--	The MIT License (MIT)
--	Copyright (c) 2016 Kapitanov Alexander 													 
--		                                          				 
-- Permission is hereby granted, free of charge, to any person obtaining a copy 
-- of this software and associated documentation files (the "Software"), 
-- to deal in the Software without restriction, including without limitation 
-- the rights to use, copy, modify, merge, publish, distribute, sublicense, 
-- and/or sell copies of the Software, and to permit persons to whom the 
-- Software is furnished to do so, subject to the following conditions:
--
-- The above copyright notice and this permission notice shall be included in 
-- all copies or substantial portions of the Software.
--
--
-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR 
-- IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, 
-- FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL 
-- THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER 
-- LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, 
-- OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS 
-- IN THE SOFTWARE.
-- 	                                                 
-------------------------------------------------------------------------------
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;  
use ieee.std_logic_signed.all;
use ieee.std_logic_arith.all;

use work.fp_m1_pkg.fp23_complex;

use ieee.std_logic_textio.all;
use std.textio.all;				

entity fp23_logic_m2 is
	generic(
		TD				: time:=1ns; 			--! Time delay for simulation
		USE_TAYLOR		: boolean:=TRUE;		--! Use taylor algorithm for twiddle factor in COE generator		
		USE_CONJ		: boolean:=TRUE;		--! Use conjugation for twiddle factor (COE)		
		USE_PAIR		: boolean:=TRUE; 		--! Bitreverse mode: Even/Odd - "TRUE" or Half Pair - "FALSE". For FFT: "TRUE"	
		DATATYPE		: integer:=23; 			--! Use integer (16) for twiddle instead of floating point (23)	
		XSERIES			: string:="ULTRA";	--! FPGA family: for 6/7 series: "7SERIES"; for ULTRASCALE: "ULTRA";
		NFFT			: integer :=13;			--! Number of FFT stages
		USE_DSP			: boolean:=TRUE; 		--! Use DSP48 for calculation PI * CNT				
		USE_SCALE		: boolean:=FALSE 		--! Use full scale rambs for twiddle factor		
	);														  
	port( 
		reset			: in  std_logic;						--! Global reset  															  
		clk				: in  std_logic;						--! DSP clock	           											  

		use_fly			: in  std_logic;		--! Use butterfly for FFT
		use_ifly		: in  std_logic;		--! Use butterfly for IFFT		

		din_re			: in  std_logic_vector(15 downto 0);	--! Re data input
		din_im			: in  std_logic_vector(15 downto 0);	--! Im data input
		din_en			: in  std_logic;						--! Data enable

		dt_rev			: in  std_logic;						--! FFT Bitreverse
		dt_mux			: in  std_logic_vector(01 downto 0); --! Data mux: "01" - Input, "10" - FFT, "11" - IFFT
		dt_fft			: in  std_logic;						--! IFFT Mux Source: '0' - from prev FFT, '1' - from IN 
		fpscale			: in  std_logic_vector(05 downto 0); --! Scale in Float2Fix
--		sf_re			: in  std_logic_vector(15 downto 0);	--! Re part of Support function
--		sf_im			: in  std_logic_vector(15 downto 0);	--! Im part of Support function		
--		sf_en			: in  std_logic;						--! SF enable
--		sf_rw			: in  std_logic;						--! SF read/write data

		d_re 			: out std_logic_vector(15 downto 0);--! Output data Even
		d_im 			: out std_logic_vector(15 downto 0);--! Output data Odd		
		d_vl			: out std_logic						--! Output valid data	
		);
end fp23_logic_m2;

architecture fp23_logic_m2 of fp23_logic_m2 is   		  

signal	din0_fft				: fp23_complex;  		
signal	din1_fft				: fp23_complex;  		   		
signal	din0_ifft				: fp23_complex;  		
signal	din1_ifft				: fp23_complex; 

signal	dout0_fft 				: fp23_complex; 		
signal	dout1_fft				: fp23_complex; 		
signal  dout0_ifft				: fp23_complex;	
signal  dout1_ifft				: fp23_complex;	

signal	ca_re					: std_logic_vector(15 downto 0);
signal	ca_im					: std_logic_vector(15 downto 0);
signal	cb_re					: std_logic_vector(15 downto 0);
signal	cb_im					: std_logic_vector(15 downto 0);		

signal	buf_en					: std_logic:='0'; 
signal	fft_en					: std_logic:='0';
signal	ifft_en					: std_logic:='0';
signal	fft_vl					: std_logic:='0';
signal  rstn					: std_logic:='0';

signal  valid_mux				: std_logic:='0';

signal d_out_val				: std_logic;
signal ifft_val					: std_logic;
signal d_val_bit				: std_logic;

signal dout0_mux, dout1_mux		: fp23_complex;	

signal val					: std_logic_vector(3 downto 0);
signal over					: std_logic_vector(3 downto 0);
  
signal fix_dout0_re			: std_logic_vector(15 downto 0);
signal fix_dout1_re			: std_logic_vector(15 downto 0);
signal fix_dout0_im			: std_logic_vector(15 downto 0);
signal fix_dout1_im			: std_logic_vector(15 downto 0);  
  
constant Nwidth				: integer:=16;	
	
signal dout_re 				: std_logic_vector(Nwidth-1 downto 0);
signal dout_im 				: std_logic_vector(Nwidth-1 downto 0);	
signal dout_en				: std_logic:='0';			

signal drev_re 				: std_logic_vector(Nwidth-1 downto 0);
signal drev_im 				: std_logic_vector(Nwidth-1 downto 0);
signal drev_en				: std_logic:='0';			
	
	

constant FPwidth		: integer:=23;		
type complex_WxN is array (NFFT-1 downto 0) of std_logic_vector(2*FPwidth-1 downto 0);
signal di_aa 			: complex_WxN;
signal di_bb 			: complex_WxN;  
signal do_aa 			: complex_WxN;
signal do_bb 			: complex_WxN; 	
signal del_en			: std_logic_vector(NFFT-1 downto 0);
signal del_vl			: std_logic_vector(NFFT-1 downto 0);   	
	
signal dt0_del 			: fp23_complex; 		
signal dt1_del			: fp23_complex; 	
signal ena_del			: std_logic; 		

begin	
	
rstn <= not reset when rising_edge(clk);
		
	
-------------------- INPUT BUFFER --------------------
xIN_BUF:  entity work.fp_Ndelay_in_m1
	generic map (
		td			=> td,
		STAGES 		=> NFFT,
		Nwidth		=> Nwidth
	)	
	port map (
		clk  		=> clk,
		reset 		=> reset,		
	
		din_re		=> din_re,
		din_im		=> din_im,
		din_en		=> din_en,

		ca_re		=> ca_re,		
		ca_im		=> ca_im,		
		cb_re		=> cb_re,		
		cb_im		=> cb_im,		
		dout_val	=> buf_en
	);
	
-------------------- FIX to FLOAT CONVERSION (on DSP or LUT) --------------------	
FIX0_IF: entity work.fp23_fix2float_m1 
	port map(
		din			=> ca_re,
		ena			=> buf_en,
		dout		=> din0_fft.re,
		vld			=> fft_en,
		clk			=> clk,
		reset		=> reset
	);					
FIX1_IF: entity work.fp23_fix2float_m1 
	port map(
		din			=> ca_im,
		ena			=> buf_en,
		dout		=> din0_fft.im,
		--dout_val	=> dout_val,
		clk			=> clk,
		reset		=> reset
	);	
FIX2_IF: entity work.fp23_fix2float_m1 
	port map(
		din			=> cb_re,
		ena			=> buf_en,
		dout		=> din1_fft.re,
		--dout_val	=> dout_val,
		clk			=> clk,
		reset		=> reset
	);			
FIX3_IF: entity work.fp23_fix2float_m1 
	port map(
		din			=> cb_im,
		ena			=> buf_en,
		dout		=> din1_fft.im,
		--dout_val	=> dout_val,
		clk			=> clk,
		reset		=> reset
	);

------------------ FPFFTK_N (FORWARD FFT) --------------------		
xFFT: entity work.fp23_fftNk_m2
	generic map (					
		NFFT		=> NFFT,				
		XSERIES		=> XSERIES,						
		USE_SCALE	=> USE_SCALE 
	)
	port map(						               
		data_mux	=> NFFT-1,
		use_fly		=> use_fly,
		
		data_in0	=> din0_fft,		
		data_in1	=> din1_fft,			   
		data_en		=> fft_en,		
    
		dout0 		=> dout0_fft,
		dout1 		=> dout1_fft,
		dout_val	=> fft_vl,
		
		reset  		=> reset, 
		clk 		=> clk
	);
 	
------------------ TEST IFFT MUX --------------------		
pr_ifft: process(clk) is
begin
	if (rising_edge(clk)) then
		if (dt_fft = '0') then
			din0_ifft 	<= dout0_fft;
			din1_ifft 	<= dout1_fft;
			ifft_en		<= fft_vl; 
		else
			din0_ifft 	<= din0_fft;
			din1_ifft 	<= din1_fft;
			ifft_en		<= fft_en;			     
		end if;	
	end if;
end process;	
	
 xIFFT: entity work.fp23_ifftNk_m2
	 generic map (
		NFFT		=> NFFT,
		XSERIES		=> XSERIES,				
		USE_SCALE	=> USE_SCALE,		
		USE_CONJ	=> USE_CONJ
	 )
	port map(						               
		data_mux	=> NFFT-1,
		use_fly		=> use_ifly,
		
		data_in0	=> din0_ifft,   	
		data_in1	=> din1_ifft,		   
		data_en		=> ifft_en, 

		dout0 		=> dout0_ifft,
		dout1 		=> dout1_ifft,
		dout_val	=> ifft_val,

		reset  		=> reset, 
		clk 		=> clk
	 ); 		
	
------------------ MUX xDATA --------------------		
pr_mux: process(clk) is
begin
	if (rising_edge(clk)) then
		case dt_mux is
			when "00" =>	
				dout0_mux <= (others => ("000000", '0', x"0000"));
				dout1_mux <= (others => ("000000", '0', x"0000"));
				valid_mux <= '0';			
			when "01" =>
				dout0_mux <= din0_fft;
				dout1_mux <= din1_fft;
				valid_mux <= fft_en;
			when "10" =>
				dout0_mux <= dout0_fft;
				dout1_mux <= dout1_fft;
				valid_mux <= fft_vl;
			when "11" =>			
				dout0_mux <= dout0_ifft;
				dout1_mux <= dout1_ifft;
				valid_mux <= ifft_val;				
			when others =>   
				null;        
		end case;		
	end if;
end process;	
	
------------------ FLOAT2FIX --------------------		
xFIX0RE: entity work.fp23_float2fix_m1
	port map (
		din			=> dout0_mux.re,	
		dout		=> fix_dout0_re,
		clk			=> clk,
		reset		=> reset,
		ena			=> valid_mux,
		scale		=> fpscale,  
		vld			=> val(0),                      
		overflow	=> over(0)                                       			
	);	
		
xFIX1RE: entity work.fp23_float2fix_m1
	port map (
		din			=> dout1_mux.re,	
		dout		=> fix_dout1_re,
		clk			=> clk,
		reset		=> reset,
		ena			=> valid_mux,
		scale		=> fpscale,  
		vld			=> val(2),                      
		overflow	=> over(2)                                       			
	);	
	
xFIX0IM: entity work.fp23_float2fix_m1
	port map (
		din			=> dout0_mux.im,	
		dout		=> fix_dout0_im,
		clk			=> clk,
		reset		=> reset,
		ena			=> valid_mux,
		scale		=> fpscale,  
		vld			=> val(1),                      
		overflow	=> over(1)                                       			
	);	
			
xFIX1IM: entity work.fp23_float2fix_m1
	port map (
		din			=> dout1_mux.im,	
		dout		=> fix_dout1_im,
		clk			=> clk,
		reset		=> reset,
		ena			=> valid_mux,
		scale		=> fpscale,  
		vld			=> val(3),                      
		overflow	=> over(3)                                       			
	);		
	
-------------------- OUTPUT BUFFER --------------------	
xOUT_BUF : entity work.fp_Ndelay_out
	generic map (
		stages 		=> NFFT,
		Nwidth		=> Nwidth
	)
	port map (
		clk 		=> clk,
		reset 		=> reset,		
		
		dout_re 	=> dout_re,
		dout_im 	=> dout_im,
		dout_val 	=> dout_en,
		
		ca_re 		=> fix_dout0_re,
		ca_im 		=> fix_dout0_im,
		cb_re 		=> fix_dout1_re,
		cb_im 		=> fix_dout1_im,
		din_en 		=> val(0)			
	);	
	
-------------------- BIT REVERSE ORDER --------------------			
xBITREV_RE : entity work.fp_bitrev_m1
	generic map (
		td			=> td,
		FWT			=> FALSE,
		PAIR		=> USE_PAIR,
		STAGES		=> NFFT,
		Nwidth		=> Nwidth	
	)
	port map (								
		clk 		=> clk,
		reset 		=> reset,		
				
		di_dt		=> dout_re,
		di_en		=> dout_en,

		do_dt		=> drev_re,
		do_vl		=> drev_en
	);	

xBITREV_IM : entity work.fp_bitrev_m1
	generic map (
		td			=> td,
		FWT			=> FALSE,
		PAIR		=> USE_PAIR,
		STAGES		=> NFFT,
		Nwidth		=> Nwidth	
	)
	port map (								
		clk 		=> clk,
		reset 		=> reset,		
				
		di_dt		=> dout_im,
		di_en		=> dout_en,

		do_dt		=> drev_im,
		do_vl		=> open
	);	

------------------ xDATA OUTPUT --------------------		
pr_rev: process(clk) is
begin
	if (rising_edge(clk)) then
		if (dt_rev = '0') then
			d_re <= dout_re;
			d_im <= dout_im;
			d_vl <= dout_en;
		else
			d_re <= drev_re;
			d_im <= drev_im;
			d_vl <= drev_en;
		end if;
	end if;
end process;	

end fp23_logic_m2;