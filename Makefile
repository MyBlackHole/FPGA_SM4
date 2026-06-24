# FPGA_SM4 - Build system for Tang Nano 20K (GW2AR-18C)
# Toolchain: yosys + nextpnr-himbaechel (gowin) + gowin_pack + openFPGALoader

TOP      ?= sm4_top_wrapper
DEVICE   ?= GW2AR-LV18QN88C8/I7
FAMILY   ?= gw2a

RTL_DIR   = RTL
CST_FILE  = tangnano20k.cst

RTL_SRCS  = $(wildcard $(RTL_DIR)/*.v)
JSON_OUT  = $(TOP).json
PNR_OUT   = $(TOP)_pnr.json
FS_OUT    = $(TOP).fs

# Default target: build bitstream
all: $(FS_OUT)

# 1) Synthesis with yosys (Gowin backend)
$(JSON_OUT): $(RTL_SRCS) $(CST_FILE)
	@echo "=== Yosys Synthesis for $(TOP) ==="
	yosys -l yosys.log -p "\
		read_verilog -sv $(RTL_SRCS); \
		 synth_gowin -family $(FAMILY) -top $(TOP) -json $@; \
	"
	@echo "Synthesis complete. Output: $@"

# 2) Place & Route with nextpnr-himbaechel (Gowin uarch)
$(PNR_OUT): $(JSON_OUT) $(CST_FILE)
	@echo "=== nextpnr Place & Route for $(DEVICE) ==="
	nextpnr-himbaechel \
		--device $(DEVICE) \
		--json $(JSON_OUT) \
		--write $(PNR_OUT) \
		--vopt cst=$(CST_FILE) \
		-l nextpnr.log
	@echo "P&R complete. Output: $@"

# 3) Bitstream generation with gowin_pack
$(FS_OUT): $(PNR_OUT)
	@echo "=== gowin_pack Bitstream Generation ==="
	gowin_pack -d GW2AR-18C -o $(FS_OUT) $(PNR_OUT)
	@echo "Bitstream generated: $@"

# 4) Program to Tang Nano 20K via openFPGALoader
program: $(FS_OUT)
	@echo "=== Programming Tang Nano 20K ==="
	openFPGALoader -b tangnano20k $(FS_OUT)
	@echo "Programming complete."

# 5) Program to flash (persistent storage)
flash: $(FS_OUT)
	@echo "=== Flashing to Tang Nano 20K ==="
	openFPGALoader -b tangnano20k -f $(FS_OUT)
	@echo "Flash complete."

# 6) Simulation with iverilog
sim:
	@echo "=== Running SM4 Testbench Simulation ==="
	mkdir -p build
	iverilog -o build/sm4_sim -g2012 \
		-I $(RTL_DIR) \
		$(RTL_DIR)/sm4_top.v \
		$(RTL_DIR)/sm4_encdec_serial.v \
		$(RTL_DIR)/key_expansion.v \
		$(RTL_DIR)/one_round_for_encdec.v \
		$(RTL_DIR)/one_round_for_key_exp.v \
		$(RTL_DIR)/sbox_replace.v \
		$(RTL_DIR)/transform_for_encdec.v \
		$(RTL_DIR)/transform_for_key_exp.v \
		$(RTL_DIR)/get_cki.v \
		TESTBENCH/tb_sm4_top.v
	vvp build/sm4_sim
	@echo "Simulation complete."

sim_view: sim
	@echo "Generating VCD waveform..."
	gtkwave build/sm4_sim.vcd 2>/dev/null || echo "gtkwave not installed"

# 7) Clean
clean:
	rm -f *.json *.fs *.log *.vcd
	rm -rf build

# 8) Show resource usage
stats: $(JSON_OUT)
	@echo "=== Resource Usage ==="
	yosys -p "read_json $(JSON_OUT); stat -width"

.PHONY: all program flash sim sim_view clean stats
