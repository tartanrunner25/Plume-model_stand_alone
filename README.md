<h2>Stand-alone Freitas Model User Guide:</h2>

_Written by Derek V. Mallia and contributions from Kai Wilmot. Plume rise source code originally developed by Saulo R. Freitas_
<br><br>

**Introduction:**<br>
Welcome! If you are reading this guide, you are likely interested in generating some wildfire plume rises using the 1-D cloud resolving smoke plume model 
developed in Freitas et al. (2007; 2010). Further details behind the model physics can be found in Freitas et al. (2007; 2010). This code further expands 
upon the original Freitas model by including updates from Mallia et al. (2018) and Wilmot et al. (2022). This model computes the height of the wildfire
plume rise using fire characteristic data provided by the user (heat flux and active burning area), along with meteorological environmental conditions. This
model outputs a plume steady-state thermodynamic profile, along with the detrainment profile, which is used to partition smoke emissions based on a vertical 
profile provided by the user.
<br><br>

**Installation instructions:**<br>
Before installing this code, users should should ensure that they have a local installation of fortran, e.g., `which gfortran`, along with python version >3.6. 
For your python installation, users are recommended to have commonly used modules such as numpy and pandas. If the user plans on using meteorological data from
a host weather prediction model or reanalysis, users might also want to install a library that can read grib and/or netcdf files. No additional library or 
dependencies are needed required.<br><br>

First, locate the directory on your machine where you would like to install the plume rise model.<br>

To clone the repository, run the command:<br>
`git clone https://github.com/tartanrunner25/Plume-model_stand_alone.git`.

In your directory, you will have several files, along with a model input and output directory, and another directory with the fortran source code `src` which will 
need to be installed by the user. The fortran executable `plume_alone_module` may not work on your machine, so it is best for the user to create their own 
fortran executable. To do this, change in the src directory:<br><br>
`cd ./src`
<br>
<br>
and then we will need to edit the makefile in this directory. Open up the Makefile with your favorite text editor, e.g., `vi Makefile` and then uncomment one of the
three `F_COMP` lines in the Makefile. Each of these is set to a different fortran compiler, so uncomment the line which corresponds to the fortran compiler you plan 
to use. For example, most of my machines have `gfortran` installed, so I went ahead and uncommented the line for gfortran:<br>

```
#F_COMP=nvfortran               #nvidia
F_COMP=gfortran                 #gfortran
#F_COMP=ifort                   #intel
```

Once the code Makefile fortran compiler has been set, clean the existing installation by typing `make clean`. Next, compile the Freitas plume rise code by typing
`make`. If the code successfully compiles, you should see a new executable called `plume_alone_module`. You should now be ready to run the Freitas model code!
<br><br>

**Running the model**<br>
To run the Freitas model, simply enter python `run_plume_rise.py`. This will use the default model parameters set in the run_plume_rise.py script, and meteorological
data located in `./model_input/sounding_OTX_08-09-2019_0z.txt`. Output from this simulation will be stored in `./model_output`. Users should edit `run_plume_rise.py`
when trying to run their own wildfire plume rises. Model parameters, including model input and output paths are set at the top of the script:<br>
# Freitas Model Input Parameters

The following parameters should be set by the user for the Freitas model:

```python
plume_ID = 'williams_flat_08092019-00z'             # Name of simulation, which is used to name model output. Should be a string.
heat_flux = 2.56                                    # Fire heat flux in kW/m²
burn_area = 7500000                                 # Burn area in m²
wind_flag = 1                                       # Flag determining if we want to turn on wind shear effects on the 
                                                    # plume rise model. 1 = on, 0 = off
entrain = 0.05                                      # The entrainment coefficient. Generally leave this as 0.05.
fuel_moist = 10                                     # Leave as is; not currently used in the plume rise calculation.
                                                    # its current formulation.
vertical_profile = np.arange(50, 20000, 100)        # Define heights for the detrainment profile. Can be set to None if the
                                                    # user wants to stick with the default height profile.
output_directory = './model_output'                 # Path where output files will be placed.
write_plume_evo = False                             # Do we want to write out the evolution of the plume rise by timestep?
                                                    # (True/False). If not, discard the results. File can be larger.
create_image = True                                 # Do we want to create a plot?

# Merge namelist options together into a list of values
plume_namelist = [heat_flux, burn_area, wind_flag, entrain, fuel_moist]

# Where do we want to get our thermodynamic data from?
thermo_file = './model_input/sounding_OTX_08-09-2019_0z.txt'
```





