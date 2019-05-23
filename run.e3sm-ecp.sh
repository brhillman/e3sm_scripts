#!/bin/bash

# Where code and data are stored
code_root=${HOME}/codes/e3sm-ecp/branches
scratch_root=${HOME}/codes/e3sm-ecp
script_root=${PWD}

# Branch tag name (subdirectory within ${code_root}, should also correspond to 
# branch name on github repository)
branch_name=add-sp-rrtmgp-again

# Strip leading directory paths from branch name
branch_shortname=`basename ${branch_name}`

# Compiler to use
machine=sandiatoss3
compiler=intel

# Compset and resolution
compset=FSP1V1-TEST
res=ne4_ne4

datestring=`date +"%Y%m%d"`

# Name of this specific case
case_name=${branch_shortname}.${compset}.${res}.${datestring}
case_root=${scratch_root}/cases/${case_name}

# Load modules needed for this machine
if [ ${machine} == 'sandiatoss3' ]; then
    module load sems-python/2.7.9
elif [ ${machine} == 'titan' ]; then
    module load python/2.7.9
else
    echo "Machine not recognized."
    exit 1
fi

# Create case; if this case has already been created, then fail and exit.
if [ -e ${case_root} ]; then
    echo "Directory ${case_root} already exists"
    exit 1
fi

cd ${code_root}/${branch_name}/cime/scripts
./create_newcase \
    --res ${res} --compset ${compset} \
    --case ${case_root} --compiler ${compiler} \
    --machine ${machine}

# Move to new case directory to execute case commands
cd ${case_root}

# Define executable and run directories; alternatively, we could put these
# elsewhere, and then just create symbolic links in the case directory.
# Regardless, it is nice having access to them all in the same spot.
#./xmlchange --id EXEROOT --val "${case_root}/bld"
#./xmlchange --id RUNDIR --val "${case_root}/run"
ln -s `./xmlquery --value EXEROOT` ${case_root}/bld
ln -s `./xmlquery --value RUNDIR`  ${case_root}/run

# Set chemistry/aerosol option
chem="none"

# Fix build options
if [ "$compset" == "FSP1V1" ]; then
    ./xmlchange CAM_CONFIG_OPTS="-phys cam5 -use_SPCAM -crm_adv MPDATA -nlev 72 -crm_nz 58 -crm_dx 1000 -crm_dt 5  -microphys mg2  -crm_nx 64 -crm_ny 1 -rad rrtmgp -chem none -SPCAM_microp_scheme sam1mom -cppdefs '-DAPPLY_POST_DECK_BUGFIXES -DSP_DIR_NS -DSP_TK_LIM'" 
elif [ "$compset" == "FSP1V1-TEST" ]; then
    ./xmlchange CAM_CONFIG_OPTS="-phys cam5 -use_SPCAM -crm_adv MPDATA -nlev 72 -crm_nz 58 -crm_dx 1000 -crm_dt 5  -microphys mg2  -crm_nx 8 -crm_ny 1 -rad rrtmgp -chem none -SPCAM_microp_scheme sam1mom -cppdefs '-DAPPLY_POST_DECK_BUGFIXES -DSP_DIR_NS -DSP_TK_LIM'" 
fi

# Fix namelist options for prescribed aerosol
input_data_dir=`./xmlquery -value DIN_LOC_ROOT`
if [ "${chem}" == "none" ]; then
    prescribed_aero_path="atm/cam/chem/trop_mam/aero"
    prescribed_aero_file="mam4_0.9x1.2_L72_2000clim_c170323.nc"
    cat <<EOF >> user_nl_cam
        use_hetfrz_classnuc = .false.
        aerodep_flx_type = 'CYCLICAL'
        aerodep_flx_datapath = '$input_data_dir/$prescribed_aero_path' 
        aerodep_flx_file = '$prescribed_aero_file'
        aerodep_flx_cycle_yr = 01
        prescribed_aero_type = 'CYCLICAL'
        prescribed_aero_datapath='$input_data_dir/$prescribed_aero_path'
        prescribed_aero_file='$prescribed_aero_file'
        prescribed_aero_cycle_yr = 01
EOF
fi

# Add history fields
cat <<EOF >> user_nl_cam
    mfilt = 1,24
    nhtfrq = 0,-1
    fincl2 = 'FUS', 'FDS', 'QRS',
             'FUL', 'FDL', 'QRL'
EOF

# Change options
./xmlchange NTASKS=16,NTASKS_ESP=1
./xmlchange STOP_OPTION=ndays,STOP_N=1,RESUBMIT=0
./xmlchange JOB_WALLCLOCK_TIME=00:30:00

# Setup and build case
./case.setup
./case.build
./case.submit
