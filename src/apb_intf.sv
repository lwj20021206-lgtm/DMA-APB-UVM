interface apb_intf(input logic pclk);
  parameter INPUT_DELAY = 1;
  parameter OUTPUT_DELAY = 1;

  logic presetn;
  logic [31:0] paddr, pwdata, prdata;
  logic pwrite, psel, penable, pready;
  logic interrupt;

  clocking master_cb @(posedge pclk);
    default input #INPUT_DELAY output #OUTPUT_DELAY;
    output paddr, pwrite, psel, penable, pwdata;
    input prdata, pready;
  endclocking

  clocking slave_cb @(posedge pclk);
    default input #INPUT_DELAY output #OUTPUT_DELAY;
    input paddr, pwrite, psel, penable, pwdata;
    output prdata, pready;
  endclocking

  clocking monitor_cb @(posedge pclk);
    default input #INPUT_DELAY;
    input paddr, pwrite, psel, penable, pwdata, prdata, pready, interrupt;
  endclocking
endinterface
