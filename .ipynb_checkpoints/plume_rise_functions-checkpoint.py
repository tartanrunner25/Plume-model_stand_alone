import pandas as pd 
import numpy as np
import pandas as pd
import contextlib
import os
import subprocess
from io import StringIO
import scipy.interpolate as interp

#This code contains a collection of subroutine functions that are responsible for setting up and executing
#the Freitas plume rise model and then post-processing the model results.


def setup_plume_sim(plume_namelist,plume_ID,thermo_profile):

    # Description: Sets up the Freitas plume rise model inputs and namelist and executes the model simulations.
    #
    # Function inputs
    # plume_namelist       - Namelist options for plume rise model, which includes a python 'list' of
    #                        the fire heat flux [0], burn area [1], wind flag [2], the entrainment
    #                        constant [3], and fuel moisture [4].
    # plume_ID             - This is the name of simulation, should have type 'string'
    # thermo_profile       - A n x 9 pandas dataframe where columns are named and ordered as follows:
    #                      - ["HGHT","PRES","TEMP","RELH","DWPT","DRCT","WIND","THTA","MIXR"]
    # 
    # Function outputs 
    # result               - returns information as string on the success of the plume rise simulation

    #Grab the first height in the thermodynamic profile and add it to the 3rd element of our plume_namelist
    plume_namelist.insert(2, thermo_profile["HGHT"].iloc[0])

    #Lets do some error handling to make sure our namelist is squared away.
    error_handling(plume_namelist,plume_ID,thermo_profile)

    #Open plume namelist file and write our plume_namelist values to this file
    print("Creating Freitas model namelist file")
    with open("plume_namelist", "w") as f:
        for option in plume_namelist:
            print(option, file=f)

    #Do the same for writing out the thermodyanic profile. To suppress the number of characters per line written,
    #we use contextlib module to redirect the output to os.devnull to discard the number of characters printed to
    #the screen.
    print("Formating input thermodynamic profile for the Freitas model")
    with open(os.devnull, 'w') as f, contextlib.redirect_stdout(f):
        with open('env_met_input.dat', 'w') as f_out:
            for index, row in thermo_profile.iterrows():
                formatted_line = "{:7d} {:7d} {:7.1f} {:7.1f} {:7.1f} {:7.1f} {:7.1f} {:7.1f} {:7.1f}\n".format(
                    int(row.iloc[0]), int(row.iloc[1]),
                    float(row.iloc[2]), float(row.iloc[3]), 
                    float(row.iloc[4]), float(row.iloc[5]), 
                    float(row.iloc[6]), float(row.iloc[7]), 
                    float(row.iloc[8])
                )
                f_out.write(formatted_line)


    #Run the plume rise model and save the model log to the result variable
    print("Executing plume_alone_module...")
    result = subprocess.run('./plume_alone_module', capture_output=True, text=True)

    #Write the result 'log' and any error messages for the Freitas model simulation to a log file
    with open(os.devnull, 'w') as f, contextlib.redirect_stdout(f):
        #Open the log file and write the output
        with open('plume_log', 'w') as log_file:
            
            #Write text printed by the Freitas model
            log_file.write("Freitas model log:\n")
            log_file.write(result.stdout)
        
            #Write any warning/error messages (stderr)
            log_file.write("\nWarning/error messages:\n")
            log_file.write(result.stderr)

    if(len(result.stderr)==0):
        print('Plume rise simulation for '+plume_ID+' successfully completed')
    else:
        print('Errors detected for '+plume_ID+'. Check log file for errors')

    return(result)



def compute_smoke_profile(result,vertical_profile=None):

    # Description: Estimates the the detrainment profile of the wildfire plume rise based on a simple mass balance
    # approach. Originally written by Wilmot et al. 2022, and converted from R to python code by DVM on 10/09/2024.
    #
    # Function inputs:
    # result               - Used to see if we can even do this calculation, if result had an error. Computed 
    #                        by Python code 
    # vertical_profile     - A sequence of heights (mAGL) that the user wants detrainment profiles for. Should be
    #                        provided as a 1-D numpy.array that starts from 0 and goes up to x altitude. If no value
    #                        is provided to the user, then just stick with model's default vertical profile.
    #
    # Function outputs:
    # height               - height of normalized vertical detrainment profile coefficient (mAGL)
    # detrain              - normalized vertical detrainment profile coefficient (unitless)


    #Read in the thermodynamic profile, selecting the necessary columns
    thermo = pd.read_csv('./final_plume.dat', sep='\s+', header=None, usecols=[0, 1, 2, 11, 12, 13, 14])

    #Rename columns
    thermo.columns = ["Z", "pres", "W", "rad", "entr", "Tplume", "Tenv"]

    #Lets do some quick unit conversions
    thermo["Z"] = thermo["Z"] * 1000        # Convert km to meters
    thermo["rad"] = thermo["rad"] * 1000     # Convert km to meters
    thermo["pres"] = thermo["pres"] * 100    # Convert mb to Pa

    #Set our model level
    model_level = thermo['Z']

    #Determine where the plume top height based on where W drops below 1 m/s
    pth = thermo.loc[thermo['W'] < 1, 'Z'].iloc[0]

    #Calculate entrainment, plume density, area, and mass
    thermo['entr'] = thermo['entr'] * -1 * thermo['W']
    thermo['rho_plume'] = thermo['pres'] / (thermo['Tplume'] * 287)  # Ideal gas law
    thermo['area'] = np.pi * (thermo['rad'] ** 2)
    thermo['mass'] = 100 * thermo['area'] * thermo['rho_plume']

    #Entrained mass in kg/s at the steady solution
    thermo['entr'] = thermo['entr'] * thermo['mass']

    #Create an interpolation function for vertical mass flux, which is very similar to l`interp.dataset` in R
    z_interp = np.concatenate(([25], np.arange(100, 19801, 100)))
    interp_func = interp.interp1d(thermo['Z'], thermo[['W', 'rho_plume', 'rad']], axis=0, fill_value="extrapolate")
    vert = pd.DataFrame(interp_func(z_interp), columns=['W', 'rho_plume', 'rad'])
    vert['Z'] = z_interp

    #Calculate vertical mass flux at layer interfaces
    vert['vert_flux'] = vert['rho_plume'] * vert['W'] * np.pi * (vert['rad'] ** 2)

    #Link vertical fluxes back to the thermo profile
    thermo['vert_in'] = np.concatenate(([0], vert['vert_flux']))
    thermo['vert_out'] = np.concatenate((vert['vert_flux'], [0]))

    #Limit thermodyanmic profile 'thermo' to the plume top height
    thermo = thermo[thermo['Z'] <= pth + 100]

    #Force remainder out at the returned plume top
    thermo.loc[thermo.index[-1], 'vert_out'] = 0

    #Calculate detrainment
    thermo['detr'] = (thermo['vert_in'] + thermo['entr']) - thermo['vert_out']

    #If the user provides their own vertical profile on where they need the
    #smoke detrainment vertical profile, interpolate to those levels, otherwise
    #just return the default vertical levels
    if(all(vertical_profile) == None):
        height = thermo['Z']
        detrain = thermo['detr']
    else:
        height = vertical_profile
        detrain = np.interp(vertical_profile, thermo['Z'], thermo['detr'])

    #Ensure all values are greater than 0, even if they are very small and negative. 
    detrain[detrain < 0] = 0

    #Normalize the coeffients between 0 and 1.
    detrain = detrain/np.sum(detrain)

    detrain_profile = pd.DataFrame({'height(mAGL)': height,'detrain(unitless)': detrain})

    return detrain_profile



def clean_up_run(plume_ID,output_directory,detrain_profile,write_plume_evo):

    # Description: Cleans up and moves files related to Freitas plume rise model simulation.
    # Function inputs
    # plume_ID             - This is the name of simulation, should have type 'string'
    # output_directory     - Path of the output directory to save run-related files in. Should have type 'string'
    # detrain_profile      - Detrainment profile, should be a dataframe with two columns 'height' & 'detrainment'
    # write_plume_evo      - Do we keep or discard the plume evolution file, which can be a few mb in size? Set to
    #                      - either True or False
    # Function outputs: None


    #Read in final plume file so we can add a header before moving it
    plume_profile = pd.read_csv('./final_plume.dat', sep='\s+', header=None)
    plume_profile.columns = ['height(km)','press(hPa)','W(M/S)','T(C)','T-TE(C)','QV(g/kg)','SAT(g/kg)','QC(g/kg)','QH(g/kg)','QI(g/kg)','Buoy(1e-2 m/s2)','radius(m)','dwdt_entr(unitless)','plumeT(K)','envT(K)'] 

    #Save the DataFrame to a CSV file with the specified format. 
    plume_profile.to_csv('./final_plume.dat', sep=' ', index=False, header=True, float_format='%.4f')

    #Also need to save the detrainment profile. Since the user could request to output the detrainment
    #profile at different vertical heights, we need to save this output seperately.
    detrain_profile.to_csv('./detrain_profile.dat', sep=' ', index=False, header=True, float_format='%.4f')

    #Create an output directory based on our plume ID name
    full_outdir_name = output_directory+'/'+plume_ID
    os.makedirs(full_outdir_name, exist_ok=True)

    #Move files to our output directory
    os.system('mv final_plume.dat '+full_outdir_name)
    os.system('mv detrain_profile.dat '+full_outdir_name)
    os.system('mv plume_log '+full_outdir_name)
    os.system('mv plume_namelist '+full_outdir_name)
    os.system('mv env_met_input.dat  '+full_outdir_name)
    if(write_plume_evo == True):
        os.system('mv plumegen.dat '+full_outdir_name)
    else:
        os.system('rm plumegen.dat')

    #Remove legacy output files. I think this is redundant with plumegen.dat anyways.
    os.system('rm plumegen.gra')



def error_handling(plume_namelist,plume_ID,thermo_profile):

    # Function inputs
    # plume_namelist       - Namelist options for plume rise model, which includes a python 'list' of
    #                        the fire heat flux [0], burn area [1], wind flag [2], the entrainment
    #                        constant [3], and fuel moisture [4].
    # plume_ID             - This is the name of simulation, should have type 'string'
    # thermo_profile       - A n x 9 pandas dataframe where columns are named and ordered as follows:
    #                      - ["HGHT","PRES","TEMP","RELH","DWPT","DRCT","WIND","THTA","MIXR"]
    # 

    #Do some error handling for the namelist options selected by the user. First see if the correct number of inputs were 
    #provided by the user. If the appropriate # of values are not assigned, kill the run.
    if len(plume_namelist) != 6:
        raise ValueError("Error: Namelist should contain 5 parameters. "+str(len(plume_namelist))+" parameters provided.")

    #Next, does the user provide a crazy high/low heat flux density value
    if plume_namelist[0] < 1e-6 or plume_namelist[0] > 10000:
        if plume_namelist[0] <1e-6:
            print('(WARNING) The heat flux provided is very small ('+str(plume_namelist[0])+' kW/m2)! Is this the correct value?')
        else:
            print('(WARNING) The heat flux provided is very large ('+str(plume_namelist[0])+' kW/m2)! Is this the correct value?')

    #Next, does the user provide a crazy high/low fire area
    if plume_namelist[1] < 4e4 or plume_namelist[1] > 4e8:

        #Converts to acres since m2 in meaningless to most people
        area_acres = plume_namelist[1]/4047

        if plume_namelist[1] <1e-6:
            print('(WARNING) The fire area provided is very small ('+str(area_acres)+' acres)! Is this the correct value?')
        else:
            print('(WARNING) The fire area provided is very large ('+str(area_acres)+' acres)! Is this the correct value?')


