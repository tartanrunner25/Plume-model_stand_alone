import pandas as pd 
import numpy as np
import pandas as pd
import contextlib
import os
import subprocess
from io import StringIO
import scipy.interpolate as interp
import plume_rise_functions as prf

#This is a sample script for calling functions from setup_plume that setup and execute the Freitas
#plume rise model. Written by DVM 10/09/2024. This is nearly identicial to 'run_plume_rise.r, except it can be run on 
#multiple plumes

entrain_constants = [0.01,0.02,0.03,0.04,0.05,0.06,0.07,0.08,0.09,0.10]

for ec in entrain_constants:

    print('Working on entrainment constant = '+str(ec))

    #Freitas model input parameters that should be set by the user
    plume_ID = 'Creek_fire_09062020-00z_'+str(ec)   #Name of simulation, which is used to name model output. Should a string.
    heat_flux = 30                                  #Fire heat flux in kW/m2
    burn_area = 80937128                            #Burn area in m2
    wind_flag = 1                                   #Flag determining if we want to turn on wind shear effects on the 
                                                    #plume rise model. 1 = on, 0 = off
    entrain   = ec                                  #The entrainment coefficient. Generally leave this as .05.
    fuel_moist = 10                                 #Leave as is, not current used in the plume rise calculation in it
                                                    #its current formulation
    vertical_profile = np.arange(50,20000,100)      #Define heights for detrainment profile. Can be set to None if the
                                                    #user wants to stick with the default height profile
    output_directory = './output'                   #Path where output files will be placed.
    write_plume_evo = False                         #Do we want to write out the evolution of the plume rise by timestep?
                                                    #(True/False). If not, discard the results. File can be larger.
    create_image = True                             #Do we want to create a plot?

    #Merge namelist options together into a list of values
    plume_namelist = [heat_flux,burn_area,wind_flag,entrain,fuel_moist]

    #Where do we want to get our thermodynanic data from?
    thermo_file = '../model_input/sounding_REV_09-06-2020_0z.txt'

    #Format the data accordinly where we need columns for "HGHT","PRES","TEMP","RELH","DWPT","DRCT","WIND","THTA","MIXR".
    #Units are as follows: "HGHT" = mASL, "PRES" = hPa, "TEMP" = C, "RELH" = %, "DWPT" = C, "DRCT" = degrees, "WIND" = m/s
    #"THTA" = K, and MIXR = g/kg. This is where the user will need to make the biggest changes, potentially. The final order 
    #needs to be as follows: ["HGHT","PRES","TEMP","RELH","DWPT","DRCT","WIND","THTA","MIXR"]
    thermo_profile = pd.read_fwf(thermo_file, skiprows=5,header=None)
    thermo_profile = thermo_profile[[1,0,2,4,3,6,7,8,5]]
    column_names = ["HGHT","PRES","TEMP","RELH","DWPT","DRCT","WIND","THTA","MIXR"]
    thermo_profile.columns = column_names
    thermo_profile["WIND"] = thermo_profile["WIND"]*0.514444     #Convert wind from kts to m/s


    #Call the setup_plume_sim function. This will set up and run the plume rise model based on options selected for the
    #plume namelist options, the prescribed thermodynamic profile, and plume ID.
    plume_result = prf.setup_plume_sim(plume_namelist,plume_ID,thermo_profile)

    #Call our detrainment subroutine, which returns a normalized plume rise detrainment coefficient, and the corresponding
    #height. height will = vertical_profile unless the user options to go with the default configuration vertical_profile=None.
    detrain_profile  = prf.compute_smoke_profile(plume_result,vertical_profile)

    #Call subroutine 'clean_up_run', which moves the output file into an output directory specified by the user. Naming of 
    #the output files determined by plume_ID
    prf.clean_up_run(plume_ID,output_directory,detrain_profile,write_plume_evo)

    #If you want to create an image, set create image to true. This creates a quick detrainment profile file
    if(create_image ==True):

        import matplotlib.pyplot as plt

        #Create the plot
        fig, ax = plt.subplots(figsize=(6, 6))  # Square figure size (6x6 inches)
        ax.plot(detrain_profile['detrain(unitless)'], detrain_profile['height(mAGL)'],linestyle='-', color='blue')

        #Set axis labels
        ax.set_xlabel('Detrainment (unitless)', fontsize=14)
        ax.set_ylabel('Height (m AGL)', fontsize=14)

        #Add a title using plume ID
        ax.set_title(plume_ID, fontsize=16)

        #Add gridlines for readability
        ax.grid(True, linestyle='--', alpha=0.5)

        #Adjust layout to avoid cutting off labels
        plt.tight_layout()

        #Save plot as a png and save it to our output directory
        plt.savefig(f'{plume_ID}.png', dpi=300)  
        os.system('mv '+plume_ID+'.png '+output_directory+'/'+plume_ID)

    #End create image script
#End sensitivity test loop for the entrainment constant
    
#End script




