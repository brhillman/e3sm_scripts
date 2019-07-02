#!/bin/bash

# Set run options
resolution=ne4_ne4
compset=FC5AV1C-L
branch=master
compiler=intel
machine=cori-knl
pelayout=16x1
walltime=00:20:00
rad="rrtmgp"

do_newcase=true
do_setup=true
do_build=true
do_submit=true

# Set paths
datestring=`date +"%Y%m%d-%H%M"`
case_name=${branch}.${compset}.${resolution}.${machine}_${compiler}.${pelayout}.${datestring}
code_root=${HOME}/codes/e3sm/branches/${branch}
case_root=${HOME}/codes/e3sm/cases/${case_name}

# Create new case
if [ "${do_newcase}" == "true" ]; then
    ${code_root}/cime/scripts/create_newcase \
        --case ${case_root} \
        --compset ${compset} --res ${resolution} \
        --machine ${machine} --compiler ${compiler} \
        --pecount ${pelayout} --queue debug --walltime ${walltime}
fi

# Setup
if [ "${do_setup}" == "true" ]; then
    cd ${case_root}
    ./xmlchange STOP_OPTION=ndays
    ./xmlchange STOP_N=1
    if [ "${rad}" == "rrtmgp" ]; then
        ./xmlchange --append CAM_CONFIG_OPTS="-rad ${rad}"
    fi
    ./case.setup
    cat <<-EOF >> user_nl_cam
        mfilt = 1
        nhtfrq = -24
        fincl1 = 'PS', 'PSL', 'PHIS', 'PMID', 'T', 'TS'
EOF
fi

# Build
if [ "${do_build}" == "true" ]; then
    cd ${case_root}
    ./case.build
fi

# Run
if [ "${do_submit}" == "true" ]; then
    cd ${case_root}
    ./case.submit
fi

# Finish up
echo "Done working on case ${case_root}"
