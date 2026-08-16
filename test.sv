class test extends uvm_test;
  apb_device_env apb_device_env_1;
  UVM_FILE f_dma_read = $fopen("dma_read.txt", "w");
  UVM_FILE f_dma_write = $fopen("dma_write.txt", "w");
  `uvm_component_utils(test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    apb_master_item::type_id::set_type_override(apb_device_master_item::get_type());
    apb_device_env_1 = apb_device_env::type_id::create("apb_device_env_1", this);
    uvm_config_db#(uvm_object_wrapper)::set(this,
      "apb_device_env_1.apb_master_agent_1.apb_master_sequencer_1.main_phase",
      "default_sequence", apb_master_basic_sequence::type_id::get());
    uvm_config_db#(uvm_object_wrapper)::set(this,
      "apb_device_env_1.apb_slave_agent_1.apb_slave_sequencer_1.run_phase",
      "default_sequence", apb_slave_basic_sequence::type_id::get());
  endfunction

  function void end_of_elaboration_phase(uvm_phase phase);
    super.end_of_elaboration_phase(phase);
    uvm_top.set_report_severity_id_file_hier(UVM_INFO, "DMA write", f_dma_write);
    uvm_top.set_report_severity_id_file_hier(UVM_INFO, "DMA read", f_dma_read);
    uvm_top.set_report_severity_id_action_hier(UVM_INFO, "DMA write", UVM_LOG | UVM_DISPLAY);
    uvm_top.set_report_severity_id_action_hier(UVM_INFO, "DMA read", UVM_LOG | UVM_DISPLAY);
  endfunction
endclass
