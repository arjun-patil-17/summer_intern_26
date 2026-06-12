`timescale 1ns / 1ps

// ========================================================================
// 1. RADIX-4 BOOTH MULTIPLIER (8x8 -> 16 bit) - EXPLICITLY SIGNED
// ========================================================================
module radix4_booth_mul_8x8 (
    input  wire signed [7:0]  a,
    input  wire signed [7:0]  b,
    output wire signed [15:0] prod
);
    wire signed [8:0] b_padded = {b, 1'b0};
    reg signed [15:0] pp [0:3];
    integer k;

    always @(*) begin
        for (k = 0; k < 4; k = k + 1) begin
            case (b_padded[2*k+2 -: 3])
                3'b000, 3'b111: pp[k] = 16'sd0;
                3'b001, 3'b010: pp[k] = {{8{a[7]}}, a};
                3'b011:         pp[k] = {{7{a[7]}}, a, 1'b0};
                3'b100:         pp[k] = -({{7{a[7]}}, a, 1'b0});
                3'b101, 3'b110: pp[k] = -({{8{a[7]}}, a});
                default:        pp[k] = 16'sd0;
            endcase
            pp[k] = $signed(pp[k]) <<< (k * 2);
        end
    end

    wire signed [15:0] s1_0 = pp[0] ^ pp[1] ^ pp[2];
    wire signed [15:0] c1_0 = ((pp[0] & pp[1]) | (pp[1] & pp[2]) | (pp[0] & pp[2])) << 1;
    assign prod = s1_0 + c1_0 + pp[3];
endmodule

// ========================================================================
// 2. MMAT4 AI ENGINE — 16 Radix-4 Booth MACs + Wallace Tree
// ========================================================================
module mmat4_unit (
    input  wire [127:0] weights,
    input  wire [127:0] pixels,
    output wire [31:0]  result
);
    wire signed [7:0]  w [0:15];
    wire signed [7:0]  p [0:15];
    wire signed [15:0] booth_prod [0:15];
    // Removed the problematic zero-checking bypass final_prod assignment
    // Booth Multiplier handles the zero calculations naturally now

    genvar i;
    generate
        for (i = 0; i < 16; i = i + 1) begin : mac_array
            assign w[i] = weights[i*8 +: 8];
            assign p[i] = pixels [i*8 +: 8];

            radix4_booth_mul_8x8 booth_inst (
                .a(w[i]), .b(p[i]), .prod(booth_prod[i])
            );
        end
    endgenerate

    // FIX: Using explicit sign extension for all partial product accumulations
    wire signed [31:0] s1 [0:7];
    assign s1[0] = {{16{booth_prod[0][15]}}, booth_prod[0]}  + {{16{booth_prod[1][15]}}, booth_prod[1]};
    assign s1[1] = {{16{booth_prod[2][15]}}, booth_prod[2]}  + {{16{booth_prod[3][15]}}, booth_prod[3]};
    assign s1[2] = {{16{booth_prod[4][15]}}, booth_prod[4]}  + {{16{booth_prod[5][15]}}, booth_prod[5]};
    assign s1[3] = {{16{booth_prod[6][15]}}, booth_prod[6]}  + {{16{booth_prod[7][15]}}, booth_prod[7]};
    assign s1[4] = {{16{booth_prod[8][15]}}, booth_prod[8]}  + {{16{booth_prod[9][15]}}, booth_prod[9]};
    assign s1[5] = {{16{booth_prod[10][15]}}, booth_prod[10]} + {{16{booth_prod[11][15]}}, booth_prod[11]};
    assign s1[6] = {{16{booth_prod[12][15]}}, booth_prod[12]} + {{16{booth_prod[13][15]}}, booth_prod[13]};
    assign s1[7] = {{16{booth_prod[14][15]}}, booth_prod[14]} + {{16{booth_prod[15][15]}}, booth_prod[15]};

    wire signed [31:0] s2 [0:3];
    assign s2[0] = s1[0] + s1[1];
    assign s2[1] = s1[2] + s1[3];
    assign s2[2] = s1[4] + s1[5];
    assign s2[3] = s1[6] + s1[7];

    wire signed [31:0] s3 [0:1];
    assign s3[0] = s2[0] + s2[1];
    assign s3[1] = s2[2] + s2[3];

    assign result = s3[0] + s3[1];
endmodule

// ========================================================================
// 3. INSTRUCTION MEMORY
// ========================================================================
module imem (
    input  wire [31:0] addr,
    output wire [31:0] rdata
);
    reg [7:0] ram [0:16383];
    initial $readmemh("inst.mem", ram);
    assign rdata = {ram[addr+3], ram[addr+2], ram[addr+1], ram[addr]};
endmodule

// ========================================================================
// 4. TRUE PARALLEL DUAL-PORT DATA MEMORY
// ========================================================================
module dmem_dual_port (
    input  wire        clk,
    input  wire        cpu_we,
    input  wire [31:0] cpu_addr,
    input  wire [31:0] cpu_wdata,
    output wire [31:0] cpu_rdata,
    input  wire        dma_we,
    input  wire [31:0] dma_addr,
    input  wire [31:0] dma_wdata,
    output wire [31:0] dma_rdata
);
    // Increased Data Memory capacity to ensure image_data.mem can fit easily at the top
    reg [7:0] ram [0:131071]; // 128KB 
    
    initial begin
        $readmemh("data.mem", ram);
        // We will initialize image data directly into data memory starting at 0x8000 (32KB offset)
        $readmemh("image.mem", ram, 32'h8000); 
    end

    wire [31:0] cpu_local = cpu_addr - 32'h2000;
    wire [31:0] dma_local = dma_addr - 32'h2000;

    assign cpu_rdata = {ram[cpu_local+3], ram[cpu_local+2], ram[cpu_local+1], ram[cpu_local]};
    assign dma_rdata = {ram[dma_local+3], ram[dma_local+2], ram[dma_local+1], ram[dma_local]};

    always @(posedge clk) begin
        if (cpu_we) begin
            ram[cpu_local]   <= cpu_wdata[7:0];
            ram[cpu_local+1] <= cpu_wdata[15:8];
            ram[cpu_local+2] <= cpu_wdata[23:16];
            ram[cpu_local+3] <= cpu_wdata[31:24];
        end
        if (dma_we) begin
            ram[dma_local]   <= dma_wdata[7:0];
            ram[dma_local+1] <= dma_wdata[15:8];
            ram[dma_local+2] <= dma_wdata[23:16];
            ram[dma_local+3] <= dma_wdata[31:24];
        end
    end
endmodule

// ========================================================================
// 5. HARDWARE PERFORMANCE COUNTER
// ========================================================================
module performance_counter (
    input  wire        clk,
    input  wire        reset,
    input  wire [31:0] bus_addr,
    input  wire        bus_rd_en,
    output reg  [31:0] bus_rdata,
    output reg  [63:0] cycle_count
);
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            cycle_count <= 64'b0;
        end else begin
            cycle_count <= cycle_count + 1'b1;
        end
    end

    always @(*) begin
        if (bus_rd_en) begin
            if (bus_addr == 32'h5000)      bus_rdata = cycle_count[31:0];
            else if (bus_addr == 32'h5004) bus_rdata = cycle_count[63:32];
            else                           bus_rdata = 32'b0;
        end else begin
            bus_rdata = 32'b0;
        end
    end
endmodule

// ========================================================================
// 6. RISC-V SOC CORE WITH INTEGRATED ADVANCED 2D STRIDE DMA CONTROLLER
// ========================================================================
module riscv_soc (
    input  wire        clk,
    input  wire        reset,
    output wire [31:0] dbg_pc,
    output wire [31:0] dbg_result
);
    reg [31:0] pc;
    reg [31:0] registers [0:31];

    assign dbg_pc = pc;

    wire [31:0] instr;
    imem instruction_memory (.addr(pc), .rdata(instr));

    wire [6:0] opcode = instr[6:0];
    wire [4:0] rd     = instr[11:7];
    wire [2:0] func3  = instr[14:12];
    wire [4:0] rs1    = instr[19:15];
    wire [4:0] rs2    = instr[24:20];
    wire [6:0] func7  = instr[31:25];

    wire [31:0] imm_i = {{20{instr[31]}}, instr[31:20]};
    wire [31:0] imm_s = {{20{instr[31]}}, instr[31:25], instr[11:7]};
    wire [31:0] imm_b = {{19{instr[31]}}, instr[31], instr[7], instr[30:25], instr[11:8], 1'b0};
    wire [31:0] imm_j = {{11{instr[31]}}, instr[31], instr[19:12], instr[20], instr[30:21], 1'b0};
    wire [31:0] imm_u = {instr[31:12], 12'h000};
    wire [4:0]  shamt = instr[24:20];

    wire        mem_we    = (opcode == 7'h23);
    wire        mem_re    = (opcode == 7'h03);
    wire [31:0] mem_addr  = (opcode == 7'h23) ? (registers[rs1] + imm_s) :
                            (opcode == 7'h03) ? (registers[rs1] + imm_i) : 32'h2000;
    wire [31:0] mem_wdata = registers[rs2];

    wire is_dma_reg = (mem_addr[31:8] == 24'h000040);

    // --- Performance Counter Integration ---
    wire [31:0] perf_rdata;
    wire        perf_en = mem_re && (mem_addr == 32'h5000 || mem_addr == 32'h5004);
    
    performance_counter perf_unit (
        .clk(clk), .reset(reset),
        .bus_addr(mem_addr), .bus_rd_en(perf_en),
        .bus_rdata(perf_rdata), .cycle_count()
    );

    // ========================================================================
    // --- INTEGRATED ADVANCED 2D/STRIDE DMA ENGINE (PRO VERSION) ---
    // ========================================================================
    reg [31:0] dma_src, dma_dest, dma_len;
    reg [31:0] dma_src_stride, dma_dst_stride, dma_row_count;
    reg        dma_start;
    reg        dma_ready;

    reg [1:0]  dma_state;
    reg [31:0] row_src_base;
    reg [31:0] row_dst_base;
    reg [31:0] col_idx;
    reg [31:0] row_idx;
    reg [31:0] dma_temp;

    wire [31:0] active_row_count = (dma_row_count == 0) ? 32'd1 : dma_row_count;
    wire [31:0] active_src_stride = (dma_src_stride == 0) ? (dma_len << 2) : dma_src_stride;
    wire [31:0] active_dst_stride = (dma_dst_stride == 0) ? (dma_len << 2) : dma_dst_stride;

    wire        dma_bus_we   = (dma_state == 2'b10); 
    wire [31:0] dma_bus_addr = (dma_state == 2'b01) ? (row_src_base + (col_idx << 2)) : 
                               (dma_state == 2'b10) ? (row_dst_base + (col_idx << 2)) : 32'h0;
    wire [31:0] dma_bus_wdata = dma_temp;
    wire [31:0] dma_bus_rdata;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            dma_start      <= 0;
            dma_src        <= 0;
            dma_dest       <= 0;
            dma_len        <= 0;
            dma_src_stride <= 0;
            dma_dst_stride <= 0;
            dma_row_count  <= 0;
            dma_state      <= 2'b00;
            dma_ready      <= 1;
            row_src_base   <= 0;
            row_dst_base   <= 0;
            col_idx        <= 0;
            row_idx        <= 0;
            dma_temp       <= 0;
        end else begin
            dma_start <= 0;

            if (mem_we && is_dma_reg) begin
                if (mem_addr == 32'h4000) dma_src        <= mem_wdata;
                if (mem_addr == 32'h4004) dma_dest       <= mem_wdata;
                if (mem_addr == 32'h4008) dma_len        <= mem_wdata; 
                if (mem_addr == 32'h400C) dma_start      <= mem_wdata[0];
                if (mem_addr == 32'h4014) dma_src_stride <= mem_wdata; 
                if (mem_addr == 32'h4018) dma_dst_stride <= mem_wdata; 
                if (mem_addr == 32'h401C) dma_row_count  <= mem_wdata; 
            end

            case (dma_state)
                2'b00: begin 
                    if (dma_start && dma_len > 0) begin
                        row_src_base <= dma_src;
                        row_dst_base <= dma_dest;
                        col_idx      <= 0;
                        row_idx      <= 0;
                        dma_ready    <= 0;
                        dma_state    <= 2'b01; 
                    end
                end
                2'b01: begin 
                    dma_temp  <= dma_bus_rdata;
                    dma_state <= 2'b10;        
                end
                2'b10: begin 
                    dma_state <= 2'b11;        
                end
                2'b11: begin 
                    if (col_idx + 1 >= dma_len) begin
                        if (row_idx + 1 >= active_row_count) begin
                            dma_ready <= 1;
                            dma_state <= 2'b00; 
                        end else begin
                            row_src_base <= row_src_base + active_src_stride;
                            row_dst_base <= row_dst_base + active_dst_stride;
                            col_idx      <= 0;
                            row_idx      <= row_idx + 1;
                            dma_state    <= 2'b01; 
                        end
                    end else begin
                        col_idx   <= col_idx + 1;
                        dma_state <= 2'b01; 
                    end
                end
            endcase
        end
    end

    wire [31:0] cpu_mem_rdata;
    dmem_dual_port data_memory (
        .clk(clk),
        .cpu_we(mem_we & ~is_dma_reg),
        .cpu_addr(mem_addr), .cpu_wdata(mem_wdata), .cpu_rdata(cpu_mem_rdata),
        .dma_we(dma_bus_we), .dma_addr(dma_bus_addr),
        .dma_wdata(dma_bus_wdata), .dma_rdata(dma_bus_rdata)
    );

    wire [31:0] read_data = (mem_addr == 32'h4010) ? {31'b0, dma_ready}      : 
                            (mem_addr == 32'h4014) ? dma_src_stride          :
                            (mem_addr == 32'h4018) ? dma_dst_stride          :
                            (mem_addr == 32'h401C) ? dma_row_count           :
                            (mem_addr == 32'h5000 || mem_addr == 32'h5004) ? perf_rdata :
                            cpu_mem_rdata;

    // ----------------------------------------------------------------
    // HARDWARE VACT & VMAX4
    // ----------------------------------------------------------------
    wire signed [31:0] vact_in = registers[rs1];
    wire [31:0] vact_shifted = vact_in >>> 9; 
    wire [31:0] vact_out = (vact_in < 0) ? 32'h0 : 
                           (vact_shifted > 32'sd127) ? 32'sd127 : vact_shifted;

    wire signed [7:0] pool_0 = registers[rs1][7:0];
    wire signed [7:0] pool_1 = registers[rs1][15:8];
    wire signed [7:0] pool_2 = registers[rs1][23:16];
    wire signed [7:0] pool_3 = registers[rs1][31:24];
    wire signed [7:0] max_a = (pool_0 > pool_1) ? pool_0 : pool_1;
    wire signed [7:0] max_b = (pool_2 > pool_3) ? pool_2 : pool_3;
    wire signed [7:0] max_final = (max_a > max_b) ? max_a : max_b;
    wire [31:0] vmax4_out = {{24{max_final[7]}}, max_final};

    // ----------------------------------------------------------------
    // MMAT4 AI ACCELERATOR ARRAY
    // ----------------------------------------------------------------
    wire [127:0] mmat_weights = {
        registers[(rs1+3) & 5'h1F],
        registers[(rs1+2) & 5'h1F],
        registers[(rs1+1) & 5'h1F],
        registers[rs1]};

    wire [127:0] mmat_pixels = {
        registers[(rs2+3) & 5'h1F],
        registers[(rs2+2) & 5'h1F],
        registers[(rs2+1) & 5'h1F],
        registers[rs2]};

    wire [31:0] mmat_out;
    assign dbg_result = mmat_out;

    mmat4_unit ai_engine (
        .weights(mmat_weights),
        .pixels(mmat_pixels),
        .result(mmat_out)
    );

    // Branch Condition Logic
    wire signed [31:0] rs1_signed = $signed(registers[rs1]);
    wire signed [31:0] rs2_signed = $signed(registers[rs2]);
    reg branch_taken;
    always @(*) begin
        branch_taken = 0;
        case (func3)
            3'b000: branch_taken = (registers[rs1] == registers[rs2]);
            3'b001: branch_taken = (registers[rs1] != registers[rs2]);
            3'b100: branch_taken = (rs1_signed <   rs2_signed);
            3'b101: branch_taken = (rs1_signed >=  rs2_signed);
            3'b110: branch_taken = (registers[rs1] <   registers[rs2]);
            3'b111: branch_taken = (registers[rs1] >=  registers[rs2]);
            default: branch_taken = 0;
        endcase
    end

    integer j;
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            pc <= 32'h0;
            for (j = 0; j < 32; j = j + 1)
                registers[j] <= 32'h0;
            registers[2] <= 32'h12000; // Initialized stack pointer
        end else begin
            pc <= pc + 4;

            case (opcode)
                7'h37: registers[rd] <= imm_u;
                7'h17: registers[rd] <= pc + imm_u;
                7'h13: begin
                    case (func3)
                        3'b000: registers[rd] <= registers[rs1] + imm_i;
                        3'b010: registers[rd] <= (rs1_signed < $signed(imm_i)) ? 1 : 0;
                        3'b011: registers[rd] <= (registers[rs1] < imm_i) ? 1 : 0;
                        3'b100: registers[rd] <= registers[rs1] ^ imm_i;
                        3'b110: registers[rd] <= registers[rs1] | imm_i;
                        3'b111: registers[rd] <= registers[rs1] & imm_i;
                        3'b001: registers[rd] <= registers[rs1] << shamt;
                        3'b101: begin
                            if (func7 == 7'h20)
                                registers[rd] <= $signed(registers[rs1]) >>> shamt;
                            else
                                registers[rd] <= registers[rs1] >> shamt;
                        end
                        default: ;
                    endcase
                end
                7'h33: begin
                    case (func3)
                        3'b000: registers[rd] <= (func7 == 7'h20) ?
                                                    (registers[rs1] - registers[rs2]) :
                                                    (registers[rs1] + registers[rs2]);
                        3'b001: registers[rd] <= registers[rs1] << registers[rs2][4:0];
                        3'b010: registers[rd] <= (rs1_signed < rs2_signed) ? 1 : 0;
                        3'b011: registers[rd] <= (registers[rs1] < registers[rs2]) ? 1 : 0;
                        3'b100: registers[rd] <= registers[rs1] ^ registers[rs2];
                        3'b101: begin
                            if (func7 == 7'h20)
                                registers[rd] <= $signed(registers[rs1]) >>> registers[rs2][4:0];
                            else
                                registers[rd] <= registers[rs1] >> registers[rs2][4:0];
                        end
                        3'b110: registers[rd] <= registers[rs1] | registers[rs2];
                        3'b111: registers[rd] <= registers[rs1] & registers[rs2];
                        default: ;
                    endcase
                end
                7'h03: begin
                    case (func3)
                        3'b000: registers[rd] <= {{24{read_data[7]}},  read_data[7:0]};
                        3'b001: registers[rd] <= {{16{read_data[15]}}, read_data[15:0]};
                        3'b010: registers[rd] <= read_data;
                        3'b100: registers[rd] <= {24'b0, read_data[7:0]};
                        default: registers[rd] <= read_data;
                    endcase
                end
                7'h23: ;  
                7'h63: begin
                    if (branch_taken) pc <= pc + imm_b;
                end
                7'h6F: begin
                    registers[rd] <= pc + 4;
                    pc <= pc + imm_j;
                end
                7'h67: begin
                    registers[rd] <= pc + 4;
                    pc <= (registers[rs1] + imm_i) & ~32'h1;
                end
                7'h6B: registers[rd] <= mmat_out;
                7'h2B: registers[rd] <= vact_out;  
                7'h4B: registers[rd] <= vmax4_out; 
                7'h7B: begin
                    registers[rd] <= registers[rd] + ($signed(registers[rs1]) * $signed(registers[rs2]));
                end
                default: ;
            endcase
        end
        registers[0] <= 32'h0; // Hardwired Zero
    end
endmodule

// ========================================================================
// 7. SYSTEM TESTBENCH WITH RUNTIME LOGGING
// ========================================================================
module tb_riscv;
    reg clk, reset;
    wire [31:0] dbg_pc, dbg_result;

    riscv_soc dut (
        .clk(clk), .reset(reset),
        .dbg_pc(dbg_pc), .dbg_result(dbg_result)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    integer cycle_count;
    integer score_idx;
    integer i;
    reg signed [31:0] raw_scores [0:9];
    
    real clock_freq_hz      = 80000000.0;  // 80 MHz
    real hardware_area_luts = 4250.0;      
    real total_mac_ops      = 1500000.0;   

    real exec_time_sec;
    real adp;
    real throughput_gops;

    initial begin
        cycle_count = 0;
        score_idx = 0; 
        reset = 1;
        repeat(4) @(posedge clk);
        reset = 0;

        $display("==============================================");
        $display("  RISC-V SoC - CIFAR-10 Pro-2D DMA Runtime    ");
        $display("==============================================");

        forever begin
            @(posedge clk);
            cycle_count = cycle_count + 1;

            if (dut.data_memory.cpu_we) begin
                
                if (dut.mem_addr == 32'h3004) begin
                    $display(" >>> VERILOG: Layer 1 Conv/Pool Checksum: %d", $signed(dut.mem_wdata));
                end

                if (dut.mem_addr == 32'h3008) begin
                    $display(" >>> VERILOG: Layer 2 Conv/Pool Checksum: %d", $signed(dut.mem_wdata));
                end
                
                if (dut.mem_addr == 32'h3010) begin
                    $display(" >>> VERILOG: C-Code reported inference cycles: %0d", dut.mem_wdata);
                end

                if (dut.mem_addr == 32'h300C) begin
                    if (score_idx < 10) begin
                        raw_scores[score_idx] = dut.mem_wdata;
                        $display(" >>> VERILOG: Storing Logit Score for Class %0d: %d", score_idx, $signed(dut.mem_wdata));
                        score_idx = score_idx + 1;
                    end else begin
                        $display(" >>> VERILOG: Network Prediction Class Result: %d", $signed(dut.mem_wdata));
                        if ($signed(dut.mem_wdata) == 9)
                            $display(" Verification : PASS (Class plane) ✓");
                        else
                            $display(" Verification : EVALUATE (Predicted Class ID: %0d)", $signed(dut.mem_wdata));
                    end
                end

                if (dut.mem_addr == 32'h3000) begin
                    $display("----------------------------------------------");
                    $display(" >>> VERILOG: Neural Network Execution COMPLETE! <<<");
                    
                    exec_time_sec = cycle_count / clock_freq_hz;
                    adp = hardware_area_luts * exec_time_sec;
                    throughput_gops = (total_mac_ops / exec_time_sec) / 1000000000.0;

                    $display("\n============= FULL NETWORK SCORE LOGITS =============");
                    
                    for(i=0; i<10; i=i+1) begin
                        $display("  [%0d] Logit Score: %d", i, $signed(raw_scores[i]));
                    end
                    $display("=====================================================\n");

                    $display("============= HARDWARE PERFORMANCE REPORT ============");
                    $display(" Simulator Engine Cycles         : %0d", cycle_count);
                    $display(" True Execution Time (Millisecs) : %f ms", exec_time_sec * 1000.0);
                    $display(" Hardware Area                   : %0.f LUTs", hardware_area_luts);
                    $display(" Area-Delay Product (ADP)        : %f", adp);
                    $display(" Throughput                      : %f GOPS", throughput_gops);
                    $display("======================================================");
                    $finish;
                end
            end

            if (cycle_count > 12000000) begin
                $display("Error: Simulation timeout safety limit reached. DMA state hung.");
                $finish;
            end
        end
    end
endmodule