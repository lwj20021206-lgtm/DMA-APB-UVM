class apb_master_basic_sequence extends uvm_sequence #(apb_master_item);
  int unsigned expected_interrupt_services;
  `uvm_object_utils(apb_master_basic_sequence)
  `uvm_declare_p_sequencer(apb_master_sequencer)

  function new(string name = "apb_master_basic_sequence");
    super.new(name);
  endfunction

  task automatic wait_for_interrupt_service();
    uvm_wait_for_nba_region();
    wait (!p_sequencer.interrupt_pending);
  endtask

  task automatic wait_for_next_interrupt();
    expected_interrupt_services++;
    wait (p_sequencer.serviced_interrupt_count >=
          expected_interrupt_services);
  endtask

  task automatic cpu_transfer(
    input  bit        write,
    input  bit [31:0] address,
    input  bit [31:0] write_data,
    output bit [31:0] read_data
  );
    apb_master_item item;

    wait_for_interrupt_service();
    item = apb_master_item::type_id::create("item");
    start_item(item);
    item.addr = address;
    item.write = write;
    item.data = write_data;
    item.addr_delay = 0;
    item.ready_delay = 0;
    finish_item(item);
    read_data = item.data;
  endtask

  task body();
    bit [31:0] read_data;

    expected_interrupt_services =
      p_sequencer.serviced_interrupt_count;

    if (starting_phase != null)
      starting_phase.raise_objection(this);

    // Direct data path smoke test.
    cpu_transfer(1'b1, 32'h0000_0010, 32'hdead_beef, read_data);
    cpu_transfer(1'b0, 32'h0000_0010, 32'h0, read_data);

    // INIT four locations and let the high-priority interrupt sequence clear
    // the completion interrupt before normal CPU traffic resumes.
    cpu_transfer(1'b1, 32'h1000_0000, 32'h0000_0100, read_data);
    cpu_transfer(1'b1, 32'h3000_0000, 32'd4, read_data);
    cpu_transfer(1'b1, 32'h4000_0000, 32'ha5a5_5a5a, read_data);
    wait_for_next_interrupt();

    // Copy the initialized range and read the destination back through the
    // DUT's direct-access window.
    cpu_transfer(1'b1, 32'h1000_0000, 32'h0000_0100, read_data);
    cpu_transfer(1'b1, 32'h2000_0000, 32'h0000_0200, read_data);
    cpu_transfer(1'b1, 32'h3000_0000, 32'd4, read_data);
    cpu_transfer(1'b1, 32'h8000_0000, 32'h0, read_data);
    wait_for_next_interrupt();

    cpu_transfer(1'b0, 32'h0000_0200, 32'h0, read_data);
    cpu_transfer(1'b0, 32'h0000_0201, 32'h0, read_data);
    cpu_transfer(1'b0, 32'h0000_0202, 32'h0, read_data);
    cpu_transfer(1'b0, 32'h0000_0203, 32'h0, read_data);

    // Negative paths: invalid length and reserved register region.
    cpu_transfer(1'b1, 32'h3000_0000, 32'd0, read_data);
    wait_for_next_interrupt();
    cpu_transfer(1'b0, 32'h5000_0000, 32'h0, read_data);
    wait_for_next_interrupt();

    // The ISR should have cleared every accumulated W1C status bit.
    cpu_transfer(1'b0, 32'hf000_0000, 32'h0, read_data);

    if (starting_phase != null)
      starting_phase.drop_objection(this);
  endtask
endclass
