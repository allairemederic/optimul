# Check the argument
if {$argc != 1} {
    puts "Usage:"
    puts "  tclsh scripts/simulate_rtl.tcl bitserial_dpu"
    puts "  tclsh scripts/simulate_rtl.tcl bitserial_top"
    exit 1
}

set module [lindex $argv 0]

# Compile and run one simulation
proc run_simulation {simulation_name top files parameters} {

    set original_directory [pwd]
    set simulation_directory "simulations/$simulation_name"

    file mkdir $simulation_directory
    cd $simulation_directory

    puts ""
    puts "Simulation: $simulation_name"

    set command [concat \
        [list vcs -full64 -sverilog -timescale=1ns/1ps] \
        $files \
        [list -top $top] \
        $parameters \
        [list -debug_access+all -Mdir=csrc -o simv] \
    ]

    if {[catch {exec {*}$command >@ stdout 2>@ stderr}]} {
        puts stderr "Compilation failed: $simulation_name"
        cd $original_directory
        return 0
    }

    puts ""

    if {[catch {exec ./simv >@ stdout 2>@ stderr}]} {
        puts stderr "Simulation failed: $simulation_name"
        cd $original_directory
        return 0
    }

    cd $original_directory
    return 1
}


# Select the testbench
switch $module {

    bitserial_dpu {
        set top tb_bitserial_dpu

        set files [list \
            ../../src/bitserial_dpu.sv \
            ../../verif/bitserial_dpu_tb.sv \
        ]

        set success [run_simulation \
            bitserial_dpu \
            $top \
            $files \
            [list] \
        ]

        if {!$success} {
            exit 1
        }
    }

    bitserial_top {
        set top tb_bitserial_top

        set files [list \
            ../../src/bitserial_dpu.sv \
            ../../src/dot_product_array.sv \
            ../../src/activation_buffer.sv \
            ../../src/weight_rom.sv \
            ../../src/weighted_accummulator.sv \
            ../../src/accumulator_bank.sv \
            ../../src/result_buffer.sv \
            ../../src/bismo_controller.sv \
            ../../src/bitserial_top.sv \
            ../../verif/bitserial_top_tb.sv \
        ]

        # Configurations (DM DN DK)
        set configurations {
            {1 1 32}
            {1 2 32}
            {1 4 32}
            {2 4 32}
            {4 4 32}
            {4 8 32}
        }

        set failed_configurations 0

        foreach configuration $configurations {
            lassign $configuration dm dn dk

            set simulation_name "bitserial_top_DM${dm}_DN${dn}_DK${dk}"

            # Override the testbench parameters during elaboration
            set parameters [list "-pvalue+${top}.DM=${dm}" "-pvalue+${top}.DN=${dn}" "-pvalue+${top}.DK=${dk}"]

            set success [run_simulation $simulation_name $top $files $parameters]

            if {!$success} { 
                incr failed_configurations
            }
        }

        puts ""
        puts "Configurations tested: [llength $configurations]"
        puts "Failed configurations: $failed_configurations"

        if {$failed_configurations != 0} {
            exit 1
        }
    }

    default {
        puts stderr "Unknown module: $module"
        exit 1
    }
}