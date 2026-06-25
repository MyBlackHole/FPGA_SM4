# FPGA_SM4 - Build system for Tang Nano 20K (GW2AR-18C)
# Toolchain: yosys + nextpnr-himbaechel (gowin) + gowin_pack + openFPGALoader
#
# Targets:
#   all / serial        — serial SM4 engine (LED/key version)
#   uart                — SM4 with UART interface (USB-serial version)
#   program             — program bitstream (LED/key version)
#   program_uart        — program bitstream (UART version)
#   sim                 — simulation (sm4_top + tb_sm4_top)
#   sim_uart            — simulation (sm4_uart_top + tb_uart)
#   clean

TOP      ?= sm4_top_wrapper
DEVICE   ?= GW2AR-LV18QN88C8/I7
FAMILY   ?= gw2a

RTL_DIR   = RTL
CST_FILE  = tangnano20k.cst
CST_UART  = sm4_uart.cst

RTL_SRCS  = $(wildcard $(RTL_DIR)/*.v)
JSON_OUT  = $(TOP).json
PNR_OUT   = $(TOP)_pnr.json
FS_OUT    = $(TOP).fs

UART_TOP   = sm4_uart_top_synth
UART_JSON  = $(UART_TOP).json
UART_PNR   = $(UART_TOP)_pnr.json
UART_FS    = $(UART_TOP).fs

# List of all non-constraint RTL source files (excluding wrapper specifics)
# Used for UART build where we need all modules except sm4_top_wrapper
RTL_CORE   = $(filter-out $(RTL_DIR)/sm4_top_wrapper.v, $(RTL_SRCS))

# ============================================================================
# Target: serial SM4 (LED/key version) — default
# ============================================================================
all: $(FS_OUT)

$(JSON_OUT): $(RTL_SRCS) $(CST_FILE)
	@echo "=== Yosys Synthesis for $(TOP) ==="
	yosys -l yosys.log -p "\
		read_verilog -sv $(RTL_SRCS); \
		 synth_gowin -family $(FAMILY) -top $(TOP) -json $@; \
	"
	@echo "Synthesis complete. Output: $@"

$(PNR_OUT): $(JSON_OUT) $(CST_FILE)
	@echo "=== nextpnr Place & Route for $(DEVICE) ==="
	nextpnr-himbaechel \
		--device $(DEVICE) \
		--json $(JSON_OUT) \
		--write $(PNR_OUT) \
		--vopt cst=$(CST_FILE) \
		--vopt family=GW2A-18C \
		-l nextpnr.log
	@echo "P&R complete. Output: $@"

$(FS_OUT): $(PNR_OUT)
	@echo "=== gowin_pack Bitstream Generation ==="
	gowin_pack -d GW2A-18C -o $(FS_OUT) $(PNR_OUT)
	@echo "Bitstream generated: $@"

program: $(FS_OUT)
	@echo "=== Programming Tang Nano 20K ==="
	openFPGALoader -b tangnano20k $(FS_OUT)
	@echo "Programming complete."

flash: $(FS_OUT)
	@echo "=== Flashing to Tang Nano 20K ==="
	openFPGALoader -b tangnano20k -f $(FS_OUT)
	@echo "Flash complete."

# ============================================================================
# Target: SM4 with UART interface
# ============================================================================
uart: $(UART_FS)

.INTERMEDIATE: $(UART_JSON)
$(UART_JSON): $(RTL_CORE) $(CST_UART)
	@echo "=== Yosys Synthesis for $(UART_TOP) ==="
	yosys -l yosys_uart.log -p "\
		read_verilog -sv $(RTL_CORE); \
		 synth_gowin -family $(FAMILY) -top $(UART_TOP) -json $@; \
	"
	@echo "Synthesis complete. Output: $@"

$(UART_PNR): $(UART_JSON) $(CST_UART)
	@echo "=== nextpnr Place & Route for $(DEVICE) (UART) ==="
	nextpnr-himbaechel \
		--device $(DEVICE) \
		--json $(UART_JSON) \
		--write $(UART_PNR) \
		--vopt cst=$(CST_UART) \
		--vopt family=GW2A-18C \
		-l nextpnr_uart.log
	@echo "P&R complete. Output: $@"

$(UART_FS): $(UART_PNR)
	@echo "=== gowin_pack Bitstream Generation (UART) ==="
	gowin_pack -d GW2A-18C -o $(UART_FS) $(UART_PNR)
	@echo "UART bitstream generated: $@"

program_uart: $(UART_FS)
	@echo "=== Programming Tang Nano 20K (UART) ==="
	openFPGALoader -b tangnano20k $(UART_FS)
	@echo "Programming complete (UART)."

flash_uart: $(UART_FS)
	@echo "=== Flashing to Tang Nano 20K (UART) ==="
	openFPGALoader -b tangnano20k -f $(UART_FS)
	@echo "Flash complete (UART)."

# ============================================================================
# Simulation
# ============================================================================
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

sim_uart:
	@echo "=== Running SM4 UART Testbench Simulation ==="
	mkdir -p build
	iverilog -o build/sm4_uart_sim -g2012 \
		-I $(RTL_DIR) \
		$(RTL_DIR)/uart_rx.v \
		$(RTL_DIR)/uart_tx.v \
		$(RTL_DIR)/sm4_uart_top.v \
		$(RTL_DIR)/sm4_top.v \
		$(RTL_DIR)/sm4_encdec_serial.v \
		$(RTL_DIR)/key_expansion.v \
		$(RTL_DIR)/one_round_for_encdec.v \
		$(RTL_DIR)/one_round_for_key_exp.v \
		$(RTL_DIR)/sbox_replace.v \
		$(RTL_DIR)/transform_for_encdec.v \
		$(RTL_DIR)/transform_for_key_exp.v \
		$(RTL_DIR)/get_cki.v \
		TESTBENCH/tb_sm4_uart.v
	vvp build/sm4_uart_sim
	@echo "UART Simulation complete."

sim_view: sim
	@echo "Generating VCD waveform..."
	gtkwave build/sm4_sim.vcd 2>/dev/null || echo "gtkwave not installed"

sim_uart_view: sim_uart
	@echo "Generating UART VCD waveform..."
	gtkwave build/sm4_uart_sim.vcd 2>/dev/null || echo "gtkwave not installed"

# ============================================================================
# Resource usage
# ============================================================================
stats: $(JSON_OUT)
	@echo "=== Resource Usage (LED/key version) ==="
	yosys -p "read_json $(JSON_OUT); stat -width"

stats_uart: $(UART_JSON)
	@echo "=== Resource Usage (UART version) ==="
	yosys -p "read_json $(UART_JSON); stat -width"

# ============================================================================
# Utilities
# ============================================================================
clean:
	rm -f *.json *.fs *.log *.vcd
	rm -rf build

.PHONY: all uart program program_uart flash flash_uart \
        sim sim_uart sim_view sim_uart_view clean stats stats_uart
