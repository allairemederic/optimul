#!/usr/bin/env tcsh

setenv PROJECT_HOME `pwd`

if ( ! -f ${PROJECT_HOME}/setup.csh) then
	echo "ERROR: setup.csh should be sourced from the root of the project... exiting"
	exit 1
endif

# SOURCES
setenv CMC_HOME /CMC
setenv SCRIPTS_HOME ${PROJECT_HOME}/scripts
setenv CONF_HOME ${PROJECT_HOME}/configs
setenv RESULTS_HOME ${PROJECT_HOME}/results

# HLS
setenv HLS_HOME ${PROJECT_HOME}/hls_projects
setenv HLS_TINY ${HLS_HOME}/tiny_l5
setenv HLS_SMALL ${HLS_HOME}/small_l5
setenv HLS_MEDIUM ${HLS_HOME}/medium_l5

# PYTHON COMPILER
setenv COMPILER_HOME ${PROJECT_HOME}/Pipeline

# MICROBLAZE PLATFORM
setenv PLATFORM_HOME ${PROJECT_HOME}/fpga
setenv VIVADO_HOME ${PLATFORM_HOME}/vivado
setenv VIVADO_BUILDS ${VIVADO_HOME}/builds
setenv VITIS_HOME ${PLATFORM_HOME}/Vitis
setenv VITIS_PLATFORMS ${VITIS_HOME}/platforms


# XILINX
source ${CMC_HOME}/scripts/xilinx.2017.csh > /dev/null

if ( $status != 0 ) then
    echo "ERROR: Failed to configure the Xilinx environment."
    exit 1
endif

# VITIS
source ${XILINX_TOP_DIR}/Vitis_2022.2/Vitis/2022.2/settings64.csh ${XILINX_TOP_DIR}/Vitis_2022.2/Vitis/2022.2 > /dev/null

if ( $status != 0 ) then
    echo "ERROR: Failed to configure Vitis 2022.2."
    exit 1
endif

# XILINX RUNTIME (XRT)
source /opt/xilinx/xrt/setup.csh > /dev/null

if ( $status != 0 ) then
    echo "ERROR: Failed to configure XRT."
    exit 1
endif

# VCS
source /CMC/scripts/synopsys.vcs_verdi.2022.06-SP2.csh > /dev/null

if ( $status != 0 ) then
    echo "ERROR: Failed to configure VCS."
    exit 1
endif