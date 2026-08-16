// Legacy minimal coverage example.  The environment uses
// apb_device_coverage_full instead.
class coverage extends uvm_component;


    uvm_analysis_export #(apb_master_item) aExport;
    uvm_tlm_analysis_fifo #(apb_master_item) fifo;
    apb_master_item item;
    bit [4:0] apb_device_feature;

    covergroup cov_apb_device_feature;
        FEATURE: coverpoint apb_device_feature {
            bins dma_direct_read = {5'b00000};
            bins dma_direct_write = {5'b00001};
            wildcard bins dma_source = {5'b0001?};
            wildcard bins dma_destination = {5'b0010?};
            wildcard bins dma_length = {5'b0011?};
            bins dma_initialization = {5'b01001};
            bins dma_copy = {5'b10001};
            wildcard bins dma_interrupt = {5'b1111?};
    }
    endgroup

endclass
