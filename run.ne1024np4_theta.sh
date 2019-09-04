#!/bin/bash

# Set run options
resolution=ne1024np4_360x720cru_oRRS15to5
compset=FC5AV1C-H01A
branch=add-ne1024-grid-old
machine=cori-knl
compiler=intel
stop_option="nhours"
stop_n="1"
walltime="04:00:00"
queue="regular"
nnodes_atm=2048
#nnodes_ocn=256
nnodes_ocn=2048
#nnodes=4352
nthreads=16
mpi_tasks_per_node=8
#ntasks=16384
ntasks_atm=$(expr ${nnodes_atm} \* ${mpi_tasks_per_node})
ntasks_ocn=$(expr ${nnodes_ocn} \* ${mpi_tasks_per_node})
total_tasks_per_node=$(expr ${mpi_tasks_per_node} \* ${nthreads})
if [ ${ntasks_ocn} -ne ${ntasks_atm} ]; then
    nnodes=$(expr ${nnodes_atm} + ${nnodes_ocn})
else
    nnodes=${nnodes_atm}
fi
pelayout=${nnodes}x${mpi_tasks_per_node}x${nthreads}
chem="none"

# Set flags
do_newcase=true
do_setup=true
do_build=true
do_submit=true

# Set paths
datestring=`date +"%Y%m%d-%H%M"`
case_name=${branch}.${compset}.${resolution}.${machine}_${compiler}.${pelayout}.theta.ifs-hindcast.${datestring}
code_root=${HOME}/codes/e3sm/branches/${branch}
case_root=${HOME}/codes/e3sm/cases/${case_name}

# Create new case
if [ "${do_newcase}" == "true" ]; then
    ${code_root}/cime/scripts/create_newcase \
        --case ${case_root} \
        --compset ${compset} --res ${resolution} \
        --machine ${machine} --compiler ${compiler} \
        --queue ${queue} \
        --walltime ${walltime}
fi

# Setup
if [ "${do_setup}" == "true" ]; then
    cd ${case_root}
    ./xmlchange STOP_OPTION=${stop_option},STOP_N=${stop_n}
    if [ ${ntasks_ocn} -ne ${ntasks_atm} ]; then
        ./xmlchange NTASKS=${ntasks_ocn}
        ./xmlchange NTASKS_ATM=${ntasks_atm}
        ./xmlchange ROOTPE_ATM=${ntasks_ocn}
    else
        ./xmlchange NTASKS=${ntasks_atm}
    fi
    ./xmlchange NTHRDS_ATM=${nthreads}
    ./xmlchange MAX_MPITASKS_PER_NODE=${mpi_tasks_per_node}
    ./xmlchange MAX_TASKS_PER_NODE=${total_tasks_per_node}

    # Run with prescribed aerosol, so set CAM_CONFIG_OPTS by hand
    if [ "${chem}" == "none" ]; then
        ./xmlchange CAM_CONFIG_OPTS="-phys cam5 -clubb_sgs -microphys mg2 -chem none -nlev 72"
    fi

    # Loosen tolerances on grid lat/lon
    ./xmlchange EPS_AGRID="1.0e-10"

    # Change start date for hindcast
    ./xmlchange RUN_STARTDATE=2016-08-01

    # Fix PIO format
    ./xmlchange PIO_NETCDF_FORMAT="64bit_data"

    # Change timestep
    ./xmlchange ATM_NCPL=720

    # Change map type for LND2ATM maps
    ./xmlchange LND2ATM_FMAPTYPE="X"
    ./xmlchange LND2ATM_SMAPTYPE="X"

    # Change dycore to theta model
    ./xmlchange CAM_TARGET=theta-l

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

    # Edit CAM namelist to set dycore options for new grid
    cat <<EOF >> user_nl_cam
    !
    !  for SL transport:  keep rsplit=1, and adjust se_nsplit and qsplit
    !  to get the correct dt_dyn and dt_tracers
    !
    !  dt_dyn should be the same as with the v1 code
    !  dt_tracers should be up to 6x larger than dt_dyn
    !
    se_ne                 = 1024
    transport_alg         = 0  ! 12 for semi-lagrangian
    semi_lagrange_cdr_alg = 20 
    se_ftype              = 4 

    ! Set timesteps
    se_nsplit             = 12  ! Set for a 10s timestep
    rsplit                = 1
    qsplit                = 1
    se_limiter_option     = 9  
    semi_lagrange_nearest_point_lev = 100 

    ! Set hyperviscosity
    hypervis_order        = 2
    hypervis_scaling      = 0
    hypervis_subcycle     = 2  ! Set to make dt_vis ~ 0.5s
    hypervis_subcycle_tom = 32 ! Set to make dt_vis ~ 0.5s
    hypervis_subcycle_q   = 1
    nu_div                = 2.5e10  !6.25e10
    nu                    = 2.5e10
    nu_p                  = 2.5e10
    nu_top                = 2.5e5
    nu_q                  = -1  ! 0 ! No hypervisocity for semi-lagrangian tracers
    se_partmethod         = 4
    se_phys_tscale        = 0

    ! Use hydrostatic mode
    theta_hydrostatic_mode=.true. 
    tstep_type=5 
    theta_advect_form=1 

    ! Using Tempest maps, need element local projection from reference element space
    ! to the sphere
    cubed_sphere_map = 2

    ! Paths to new input data
    drydep_srf_file = '/project/projectdirs/acme/inputdata/atm/cam/chem/trop_mam/atmsrf_ne1024np4_20190621.nc'
    ncdata = '/global/cscratch1/sd/wlin/DYAMOND/inputdata/ifs_oper_T1279_2016080100_mod_subset_to_e3sm_ne1024np4_topoadj_L72.nc'

    ! Timestep output for debugging
    !nhtfrq = 0,1
    !mfilt  = 1,48
    !avgflag_pertape = 'A', 'I'
    !fincl2 = 'OMEGA500', 'TMQ', 'PRECT', 'PSL', 'TGCLDLWP'

    ! Write initial conditions more frequently
    inithist = 'DAILY'

EOF

    # Edit CLM namelist to set land initial condition
    cat <<EOF >> user_nl_clm
    finidat = '/global/cscratch1/sd/wlin/acme_scratch/cori-knl/ICRUCLM45-360x720cru/run/ICRUCLM45-360x720cru.clm2.r.2016-08-01-00000.nc'
EOF

    # Finally, run setup
    ./case.setup

#   # Configure branch run
#   refcase="add-ne512-grids.FC5AV1C-H01A.ne512np4_360x720cru_ne512np4.cori-knl_intel.1024x17x8.ifs-hindcast.20190617-1655"
#   ./xmlchange RUN_TYPE="branch"
#   ./xmlchange RUN_REFCASE="${refcase}"
#   ./xmlchange RUN_REFDATE="2016-08-03"
#   for file in ${CSCRATCH}/acme_scratch/${machine}/${refcase}/run/*.r.*.nc; do
#       ln -vs ${file} `./xmlquery -value RUNDIR`/`basename ${file}`
#   done

    # Link to run directory
    ln -s `./xmlquery -value RUNDIR` run

    # This disables the logic that sets tprof_n and tprof_options internally.
    ./xmlchange --file env_run.xml TPROF_TOTAL=-1
    echo "tprof_n = 1" >> user_nl_cpl
    echo "tprof_option = 'nsteps'" >> user_nl_cpl

fi


# Build
if [ "${do_build}" == "true" ]; then
    cd ${case_root}
    ./case.build
fi

# Run
if [ "${do_submit}" == "true" ]; then
    cd ${case_root}
    ./case.submit --batch-args="--mail-type=ALL --mail-user=bhillma@sandia.gov"
fi
