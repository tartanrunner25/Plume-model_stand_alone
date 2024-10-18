This Freitas plume rise model was originally developed by Saul Freitas. See Freitas
et al. (2007) and (2010) for more details on the model methodology. Modifications
to this code was made by DVM in 2018 and 2024 to improve the portability and 
flexibility of this code so that it can be compiled on any machine, and most Fortran
compilers. Compilers that have been tested include: gfortran, intel, and nvidia.

To compile this code, edit the F_COMP within your Makefile so that is set equal your 
fortran compiler of choice. Three choices are currently provided in the ./Makefile so
just remove the comment character # for the option you would like to select. For 
example, if the user want to use gfortran, edit the file as follows:

#F_COMP=nvfortran               #nvidia
F_COMP=gfortran                 #gfortran
#F_COMP=ifort                   #intel

While the code has only been tested for nvidia, gfortran, and intel, other compilers 
could also work.

Once the code Makefile fortran compiler has been set, following the instructions above,
type 'make' in your command line. If you have already compiled the code, and wish to 
recompile it, type 'make clean' before running 'make'.



References-------------------------------------------------------------------------------
Freitas, S. R., Longo, K. M., Chatfield, R., Latham, D., Silva Dias, M. A. F., Andreae, 
M. O., Prins, E., Santos, J. C., Gielow, R., and Carvalho Jr., J. A.: Including the 
sub-grid scale plume rise of vegetation fires in low resolution atmospheric transport 
models, Atmos. Chem. Phys., 7, 3385–3398, https://doi.org/10.5194/acp-7-3385-2007, 2007.

Freitas, S. R., Longo, K. M., Trentmann, J., and Latham, D.: Technical Note: Sensitivity 
of 1-D smoke plume rise models to the inclusion of environmental wind drag, Atmos. 
Chem. Phys., 10, 585–594, https://doi.org/10.5194/acp-10-585-2010, 2010.


