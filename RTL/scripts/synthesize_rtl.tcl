# Standalone synthesis of the bit-serial module

set part xcu280-fsvh2892-2L-e
set top bitserial_top

# DM DN DK ACT_LANES RESULT_LANES
set configurations {
    {4 32 64  8  8}
    {4 32 64 16  8}
    {4 32 64 16 16}
    {4 32 64 16 32}
    {4 32 64 32  8}
    {4 32 64 32 16}

    {4 16 128 16 16}
    {4 32 128  8  8}
    {4 32 128 16  8}
    {4 32 128 16 16}
    {4 32 128 32  8}
}

set source_files {
    src/bitserial_dpu.sv
    src/dot_product_array.sv
    src/activation_buffer.sv
    src/weight_rom.sv
    src/weighted_accummulator.sv
    src/accumulator_bank.sv
    src/result_buffer.sv
    src/bismo_controller.sv
    src/bitserial_top.sv
}

foreach configuration $configurations {
    lassign $configuration dm dn dk act_lanes result_lanes

    set name "DM${dm}_DN${dn}_DK${dk}_A${act_lanes}_R${result_lanes}"
    set result_directory "results/synthesis/$name"

    file mkdir $result_directory

    set weight_file [file normalize "weights/weights_ff1_DN${dn}_DK${dk}.mem"]

    if {![file exists $weight_file]} {
        puts "ERROR: Missing weight file: $weight_file"
        exit 1
    }

    puts ""
    puts "Synthesizing $name"
    puts "Weight file: $weight_file"
    puts ""

    # Create a temporary in-memory project
    create_project -in_memory -part $part

    # Read the SystemVerilog files
    foreach source_file $source_files {
        read_verilog -sv $source_file
    }

    # Read the clock constraint
    read_xdc constraints/bitserial_top.xdc

    # Override the top-level parameters
    set generics [list "DM=$dm" "DN=$dn" "DK=$dk" "ACT_LANES=$act_lanes" "RESULT_LANES=$result_lanes" "WEIGHT_FILE=$weight_file"]

    # Run synthesis
    synth_design -top $top -part $part -generic $generics

    # Generate resource report
    report_utilization -file "$result_directory/utilization.rpt"

    # Generate RAM report to make sure weights are in BRAM and not FF
    report_ram_utilization -file "$result_directory/ram_utilization.rpt"

    # Generate timing report  
    report_timing_summary -delay_type max -max_paths 10 -file "$result_directory/timing.rpt"

    write_checkpoint -force "$result_directory/bitserial_top_synth.dcp"

    close_project
}

puts ""
puts "All synthesis runs completed"
puts "Results are available in results/synthesis/"
