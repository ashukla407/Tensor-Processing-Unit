// 1. INTERFACE: Bundles signals between class-based UVM world and module-based DUT
interface fp32_if (input logic clk);
  logic        n_rst, en;
  logic [31:0] fp_1, fp_2;
  logic        overflow, underflow, nv;
  logic [31:0] fp_out;
endinterface

// 2. SEQUENCE ITEM: A single transaction packet (inputs + observed outputs)
class fp32_item extends uvm_sequence_item;
  `uvm_object_utils(fp32_item)

  rand logic [31:0] fp_1, fp_2;
  rand logic        en;
  // Outputs sampled by monitor
  logic [31:0] fp_out;
  logic        overflow, underflow, nv;

  // Constraint to hit IEEE-754 corner cases frequently!
  constraint c_fp_corners {
    fp_1[30:23] dist {
      8'h00       := 15, // Zero / Subnormals
      [8'h01:8'hFE] :/ 70, // Normals
      8'hFF       := 15  // Inf / NaN
    };
    fp_2[30:23] dist { 8'h00 := 15, [8'h01:8'hFE] :/ 70, 8'hFF := 15 };
    en dist { 1'b1 := 85, 1'b0 := 15 }; // Test pipeline stalls (en=0) 15% of the time!
  }

  function new(string name = "fp32_item");
    super.new(name);
  endfunction
endclass

// 3. SEQUENCE: Generates N random fp32_items and sends them to the Driver
class fp32_seq extends uvm_sequence #(fp32_item);
  `uvm_object_utils(fp32_seq)
  function new(string name = "fp32_seq"); super.new(name); endfunction

  virtual task body();
    repeat (1000) begin
      fp32_item req = fp32_item::type_id::create("req");
      start_item(req);
      assert(req.randomize());
      finish_item(req);
    end
  endtask
endclass

// 4. DRIVER: Pulls items from Sequencer and wiggles pin-level interface signals
class fp32_driver extends uvm_driver #(fp32_item);
  `uvm_component_utils(fp32_driver)
  virtual fp32_if vif;

  function new(string name, uvm_component parent); super.new(name, parent); endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual fp32_if)::get(this, "", "vif", vif))
      `uvm_fatal("DRV", "Could not get vif")
  endfunction

  virtual task run_phase(uvm_phase phase);
    forever begin
      seq_item_port.get_next_item(req); // 1. Pull transaction from sequencer
      @(posedge vif.clk);
      vif.en   <= req.en;               // 2. Drive pins using non-blocking <=
      vif.fp_1 <= req.fp_1;
      vif.fp_2 <= req.fp_2;
      seq_item_port.item_done();        // 3. Tell sequencer we drove it
    end
  endtask
endclass

// 5. MONITOR: Passively watches the 3-stage pipeline and broadcasts to Scoreboard
class fp32_monitor extends uvm_monitor;
  `uvm_component_utils(fp32_monitor)
  virtual fp32_if vif;
  uvm_analysis_port #(fp32_item) ap; // Broadcast port to Scoreboard & Coverage

  function new(string name, uvm_component parent);
    super.new(name, parent);
    ap = new("ap", this);
  endfunction

  // Track the 3-stage pipeline shift register when 'en' is high!
  fp32_item pipe_q[$]; // Queue modeling the 3 pipeline stages

  virtual task run_phase(uvm_phase phase);
    forever begin
      @(posedge vif.clk);
      if (!vif.n_rst) begin
        pipe_q.delete();
      end else if (vif.en) begin
        // Push newly sampled input into our 3-stage tracking queue
        fp32_item in_tr = fp32_item::type_id::create("in_tr");
        in_tr.fp_1 = vif.fp_1;
        in_tr.fp_2 = vif.fp_2;
        pipe_q.push_back(in_tr);

        // Once 3 'en' cycles have elapsed, the oldest input's result is at fp_out!
        if (pipe_q.size() == 3) begin
          fp32_item completed_tr = pipe_q.pop_front();
          completed_tr.fp_out    = vif.fp_out;
          completed_tr.overflow  = vif.overflow;
          completed_tr.underflow = vif.underflow;
          completed_tr.nv        = vif.nv;
          ap.write(completed_tr); // Broadcast completed transaction to Scoreboard!
        end
      end
    end
  endtask
endclass

// 6. SCOREBOARD: Receives transactions from Monitor and checks against Golden Model
import "DPI-C" function int unsigned c_fp32_add_golden(int unsigned a, int unsigned b);

class fp32_scoreboard extends uvm_scoreboard;
  `uvm_component_utils(fp32_scoreboard)
  uvm_analysis_imp #(fp32_item, fp32_scoreboard) imp;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    imp = new("imp", this);
  endfunction

  // Called automatically whenever Monitor calls ap.write(tr)
  virtual function void write(fp32_item tr);
    logic [31:0] expected = c_fp32_add_golden(tr.fp_1, tr.fp_2);
    // Allow 1-ULP tolerance since RTL truncates instead of Round-to-Nearest-Even
    if (tr.fp_out !== expected && (tr.fp_out - expected > 1) && (expected - tr.fp_out > 1)) begin
      `uvm_error("SCB", $sformatf("MISMATCH! fp1=%h fp2=%h | Exp=%h Got=%h",
                                  tr.fp_1, tr.fp_2, expected, tr.fp_out))
    end
  endfunction
endclass