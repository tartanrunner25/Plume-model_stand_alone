!-------------------------------------------------------------------------------------------!
! Plume rise model for vegetation fires (CPTEC/INPE 2005-2006,2009)			    !
! Refs.:										    !
! Freitas, S. R., K. M. Longo, J. Trentmann, D. Latham. Technical Note: Sensitivity         !
! of 1D smoke plume rise models to the inclusion of environmental wind drag.                !
! Atmospheric Chemistry  and Physics, 2010.                                                 !
!                                                                                           !
! Freitas, S. R., K. M. Longo, R. Chatfield, D. Latham, M. A. F. Silva Dias, M. O. Andreae, !
! E. Prins, J. C. Santos, R. Gielow and J. A. Carvalho Jr.: Including the sub-grid scale    !
! plume rise of vegetation fires in low resolution atmospheric transport models. 	    !
!  Atmospheric Chemistry and Physics,2007.				                    !
!-											    !
! Freitas, S. R.; Longo, K. M.; M. Andreae. Impact of including the plume rise of vegetation! 
! fires in numerical simulations of associated atmospheric pollutants. Geophys. Res. Lett., !
! 33, L17808, doi:10.1029/2006GL026608, 2006.                                               !
!                                                                                           !
! Questions/bugs/comments: Saulo Freitas (saulo.freitas@cptec.inpe.br) 	                    !
!		                                                                            !
!-------------------------------------------------------------------------------------------!

Module smk_plumerise
		 
implicit none


integer, parameter :: N_BIOME = 4
integer, parameter :: TROPICAL_FOREST = 1
integer, parameter :: BOREAL_FOREST = 2
integer, parameter :: SAVANNA = 3
integer, parameter :: GRASSLAND = 4

!---------------------------------------------------------------------------
! Module plumegen_coms
integer, parameter :: nkp = 200, ntime = 200

real,dimension(nkp) ::  w,t,theq,qv,qc,qh,qi,sc,  &  
                        vth,vti,rho,txs,qt,       &
                        est,qsat,qpas,qtotal,td,vel_p,rad_p

real,dimension(nkp) ::  wc,wt,tt,qvt,qct,qht,qit,sct,vel_t,rad_t
real,dimension(nkp) ::  dzm,dzt,zm,zt,vctr1,vctr2   &
                        ,vt3dc,vt3df,vt3dk,vt3dg,scr1&
                        ,vt3dj,vt3dn,vt3do,vt3da,scr2&
                        ,vt3db,vt3dd,vt3dl,vt3dm,vt3di,vt3dh,vt3de, rbuoy,dwdt_entr

real,dimension(nkp) ::  pke,the,thve,thee,pe,te,qvenv,rhe,dne,sce,tde,upe,vpe,vel_e ! environment at plume grid
real,dimension(1200) :: ucon,vcon,wcon,thtcon ,rvcon,picon,tmpcon,dncon,prcon &
                        ,zcon,zzcon,scon,urcon,tdcon ! environment at RAMS  grid
integer MTT
 
real :: DZ,DQSDZ,VISC(nkp),VISCOSITY,TSTPF   
integer :: N,NM1,L
 
real :: ADVW,ADVT,ADVV,ADVC,ADVH,ADVI,CVH(nkp),CVI(nkp),ADIABAT,&
                        WBAR,ALAST(10),VHREL,VIREL  ! advection
 
real :: ZSURF,ZBASE,ZTOP
integer :: LBASE
 
real :: AREA,RSURF,ALPHA,RADIUS(nkp)  ! entrain
 
real :: HEATING(ntime),FMOIST,BLOAD,heat_fluxW   ! heating
 
real :: DT,TIME,TDUR
integer :: MINTIME,MDUR,MAXTIME
 
real :: ztop_(ntime)

real :: value1
integer :: iunit

!- turn ON (=1), OFF (=0) the env wind effect on plume rise, Depcreciated, DVM 10/3/2024, use wind_flag
integer, parameter :: wind_eff = 1

!---------------------------------------------------------------------------
!Module rconstants
real, parameter ::                    &
        rgas     = 287.05             &
    ,   cp       = 1004.              &
    ,   cv       = 717.               &
    ,   rm       = 461.               &
    ,   p00      = 1.e5               &
    ,   t00      = 273.16             &
    ,   g        = 9.80               &
    ,   pi180    = 3.1415927 / 180.   &
    ,   pi4      = 3.1415927 * 4.     &
    ,   spcon    = 111120.            &
    ,   erad     = 6367000.           &
    ,   vonk     = 0.40               &
    ,   tkmin    = 5.e-4              &
    ,   alvl     = 2.50e6             &
    ,   alvi     = 2.834e6            &
    ,   alli     = 0.334e6            &
    ,   alvl2    = 6.25e12            &
    ,   alvi2    = 8.032e12           &
    ,   solar    = 1.3533e3           &
    ,   stefan   = 5.6696e-8          &
    ,   cww      = 4218.              &
    ,   c0       = 752.55 * 4.18684e4 &
    ,   viscos   = .15e-4             &
    ,   rowt     = 1.e3               &
    ,   dlat     = 111120.            &
    ,   omega    = 7.292e-5           &
    ,   rocp     = rgas / cp          &
    ,   p00i     = 1. / p00           &
    ,   cpor     = cp / rgas          &
    ,   rocv     = rgas / cv          &
    ,   cpi      = 1. / cp            &
    ,   cpi4     = 4. * cpi           &
    ,   cp253i   = cpi / 253.         & 
    ,   allii    = 1. / alli          &
    ,   aklv     = alvl / cp          &
    ,   akiv     = alvi / cp          &
    ,   gama     = cp / cv            &
    ,   gg       = .5 * g             &
    ,   ep       = rgas / rm          & 
    ,   p00k     = 26.870941          &  !  = p00 ** rocp  
    ,   p00ki    = 1. / p00k
!---------------------------------------------------------------------------


contains

! First, we need to define the smk_pr_driver subroutine, since this is what is driving
! the Freitas et al. plume rise model. Next we define subroutines that are essential
! for a number of calculations throughout the model. Next we grab the environmental
! conditions with the 'get_env_condition' subroutine, set the model grid 'set_grid' & 
! 'set_flam_vert', define the fire properties '', and then call the subroutines needed 
! for the dynamical modeling of the plume rise.


!******************************************************************
subroutine  smk_pr_driver(    )

   integer                 :: m1,m2,m3,ia,iz,ja,jz,ibcon,mynum,i,j,k,iveg_ag,&
                                 k_CO_smold,k_PM25_smold,imm,k1,k2,kmt,use_sound,kk,wind_flag
   real                    :: burnt_area,STD_burnt_area,heat_input,dz_flam,rhodzi
   real                    :: topo,entrain_constant,fuel_moist
   real,    dimension(2)   :: ztopmax


   ! Initial settings (should be changed for the coupling with 3d host model)
   ia=1;iz=1;ja=1;jz=1; m1=38
  	      
   ! Flag to define if the attached sounding will (=1) or not (=0) used
   ! Set it to zero for the coupling with 3d host model 
   use_sound=1
 
   ! Initialize several parameters (only need to be done at the 1st time)
   call zero_plumegen_coms

   ! Assign a unit number and open the file
   iunit = 10
   open(unit=iunit, file='plume_namelist', status='old', action='read')

   ! Read the values from the file
   read(iunit, *) heat_input
   read(iunit, *) burnt_area
   read(iunit, *) topo
   read(iunit, *) wind_flag
   read(iunit, *) entrain_constant
   read(iunit, *) fuel_moist

   ! Close the file
   close(iunit)

   ! Print the values to verify
   print *, 'Model parameters set by the user in the plume_namelist file:' 
   print *, 'Heat flux:', heat_input
   print *, 'Burned area:', burnt_area
   print *, 'mAGL:', topo
   print *, 'Wind effects on/off:', wind_flag
   print *, 'Entrainment constant:', entrain_constant
   print *, 'Fuel moisture:', fuel_moist
   print *, ''
   print *, ''
  
   ! Get envinronmental state (temp, water vapor mix ratio, ...)
   call get_env_condition(1,m1-1,kmt,use_sound,topo,wind_flag)

   ! Determine fire heat flux based on veg type and create plume. Not directly used but needs to 
   ! be set for the get_fire_properties subroutine to work correctly. Might need to figure out
   ! how to remove these later on DVM 08/27/2024
   iveg_ag=1
   imm=1
    
   ! Get fire properties (burned area, plume radius, heating rates ...)
   print*,'Initializing the fire properties...'   
   call get_fire_properties(imm,iveg_ag,burnt_area,heat_input,entrain_constant,fuel_moist)
       
   ! Generate plume rise    ------
   print*,'Executing the plume rise simulation...'    
   call makeplume (kmt,ztopmax(imm),imm)    

   print*,' burnt_area (ha) - top cloud(km)- power (W m^2)' 
   print*,burnt_area/10000.,ztopmax(imm)/1000.,heat_fluxW

      
end subroutine smk_pr_driver

!******************************************************************
!******************************************************************
real function  esat(t)

! This script computes esat(millibars) based on t(kelvin)   

   implicit none
   real :: t
   real, parameter :: abz=273.15
   real :: tc

   tc=t-abz
   esat=6.1078*exp((17.2693882*tc)/(tc+237.3))

   return

end function  esat
!******************************************************************
!******************************************************************
real function rslf(p,t)

! This function calculates the liquid saturation vapor mixing ratio as
! a function of pressure and Kelvin temperature

   implicit none
   real esl,x,t,p,c0,c1,c2,c3,c4,c5,c6,c7,c8
   parameter (c0= .6105851e+03,c1= .4440316e+02,c2= .1430341e+01)
   parameter (c3= .2641412e-01,c4= .2995057e-03,c5= .2031998e-05)
   parameter (c6= .6936113e-08,c7= .2564861e-11,c8=-.3704404e-13)

   x=max(-80.,t-273.15)

   esl=c0+x*(c1+x*(c2+x*(c3+x*(c4+x*(c5+x*(c6+x*(c7+x*c8)))))))
   rslf=.622*esl/(p-esl)

   return

end function rslf
!******************************************************************
!******************************************************************
real function rsif(p,t)

   ! This function calculates the ice saturation vapor mixing ratio as a
   ! function of pressure and Kelvin temperature

   implicit none
   real esi,x,t,p,c0,c1,c2,c3,c4,c5,c6,c7,c8
   parameter (c0= .6114327e+03,c1= .5027041e+02,c2= .1875982e+01)
   parameter (c3= .4158303e-01,c4= .5992408e-03,c5= .5743775e-05)
   parameter (c6= .3566847e-07,c7= .1306802e-09,c8= .2152144e-12)

   x=max(-80.,t-273.15)
   esi=c0+x*(c1+x*(c2+x*(c3+x*(c4+x*(c5+x*(c6+x*(c7+x*c8)))))))
   rsif=.622*esi/(p-esi)

return
end Function rsif

!******************************************************************
!******************************************************************
subroutine get_env_condition(k1,k2,kmt,use_sound,topo,wind_flag)

   !use plumegen_coms
   !use rconstants
   implicit none
   integer :: k2,k,kcon,klcl,kmt,nk,nkmid,i,kk,use_sound,k2a, ios
   integer :: nlines, maxcols, wind_flag
   integer, intent(in) :: k1
   real :: znz,themax,tlll,plll,rlll,zlll,dzdd,dzlll,tlcl,plcl,dzlcl,dummy
   integer :: n_setgrid = 0
   real, allocatable :: x(:,:)
   real topo,es  

   if(n_setgrid == 0) then
      n_setgrid = 1
      call set_grid ! define vertical grid of plume model
   endif

   if(use_sound==1) then 
      print*,'Reading in the environmental input file' 
      open(13,file='./env_met_input.dat') !wet case

      maxcols = 9  ! Assuming 9 columns
      !topo = 136.0

      ! Open the file. Made this code more flexible than original
      ! sounding file reader so it can read in a sounding of any
      ! length. Can be obtained from a sounding, any NWP model, and
      ! so on. Edited by DVM 8/29/2024
      open(13, file='env_met_input.dat',iostat=ios)
      if (ios /= 0) then
         print *, 'Error opening file', ios
         stop
      endif

      ! Determine the number of lines in our input file
      nlines = 0
      do
         read(13, *, iostat=ios)
         if (ios /= 0) exit
         nlines = nlines + 1
      end do

      ! Rewind the file to read the data again
      rewind(13)

      ! Allocate memory for x based on the number of lines. This gives the code
      allocate(x(maxcols, nlines))

      ! Read the data into the array x
      do i = 1, nlines
         read(13, *) (x(k,i), k=1, maxcols)
      end do

      ! Close the file
      close(13)

      ! Process the data
      k = 0
      do i = 1, nlines, 1
         k = k + 1
         zcon(k)  = x(1,i) - topo
         prcon(k) = x(2,i) * 100.
         tmpcon(k) = x(3,i) + 273.15
         urcon(k) = x(4,i)
         tdcon(k) = x(5,i)
         thtcon(k) = x(8,i)
         rvcon(k) = x(9,i)
         ucon(k) = - x(7,i) * sin(3.1416 * x(6,i) / 180.)
         vcon(k) = - x(7,i) * cos(3.1416 * x(6,i) / 180.)
         !print*,'height =',k,zcon(k)
         !print*,'layer=',k,zcon(k),tmpcon(k),prcon(k)
      end do

      !print*,'line #',nlines
      k2a=nlines            !Change recommended by nvidia developers
      znz=zcon(k2a)

      do k=nkp,1,-1
         if(zt(k).lt.znz)go to 13
      enddo

      stop ' envir stop 12'
      13 continue

      kmt=k      !Sets the number of model levels
      !print*,'kmt=',kmt,znz
      nk=nlines  ! number of vertical levels of the 'input' sounding

      !Call htint(nk, wcon,zzcon,kmt,wpe,zt)
      call htint(nk,  ucon,zcon,kmt,upe,zt)
      call htint(nk,  vcon,zcon,kmt,vpe,zt)
      call htint(nk,thtcon,zcon,kmt,the  ,zt)
      call htint(nk, rvcon,zcon,kmt,qvenv,zt)
      call htint(nk,tmpcon,zcon,kmt,te  ,zt)
      call htint(nk, prcon,zcon,kmt,pe,zt)
      call htint(nk, urcon,zcon,kmt,rhe,zt)


      do k=1,kmt
         
         !print*,'layer=',k,zt(k),the(k),pe(k)

         ! PE esta em kPa  - ESAT do RAMS esta em mbar = 100 Pa = 0.1 kPa
         ES = 0.1*ESAT (TE(k)) !blob saturation vapor pressure, em kPa
         
         ! rotina do plumegen calcula em kPa
         ! ES       = ESAT_PR (T(k))  !blob saturation vapor pressure, em kPa
         QSAT (k) = (.622 * ES) / (PE (k)*1.e-3 - ES) !saturation lwc g/g
         
         ! Calculate qvenv
         qvenv(k)=0.01*rhe(k)*QSAT (k)
         qvenv(k)=max(qvenv(k),1e-8)
         !print*,k,QSAT (k),rhe(k),qvenv(k),rhe(k)*QSAT (k)
      enddo

      do k=1,kmt
         thve(k)=the(k)*(1.+.61*qvenv(k)) ! virtual pot temperature
      enddo
   
      do k=1,kmt
         dne(k)= pe(k)/(rgas*te(k)*(1.+.61*qvenv(k))) !  dry air density (kg/m3)
         vel_e(k) = sqrt(upe(k)**2+vpe(k)**2)
      enddo
   endif


   !ewe - env wind effect
   if(wind_flag < 1)  vel_e = 0.
   
   do k=1,kmt
      !print*,k,' ',zcon(k),pe(k),te(k),qvenv(k),thee(k),tde(k)
      call thetae(pe(k),te(k),qvenv(k),thee(k),tde(k))
   enddo

   ! Converte press de Pa para kPa para uso modelo de plumerise
   do k=1,kmt
      pe(k) = pe(k)*1.e-3
   enddo 

end subroutine get_env_condition

!******************************************************************
!******************************************************************
subroutine set_grid()
   
   !use plumegen_coms  
   implicit none
   integer :: k,mzp

   dz=100. ! set constant grid spacing of plume grid model(meters)

   mzp=nkp
   zt(1) = zsurf
   zm(1) = zsurf
   zt(2) = zt(1) + 0.5*dz
   zm(2) = zm(1) + dz
   do k=3,mzp
      zt(k) = zt(k-1) + dz ! thermo and water levels
      zm(k) = zm(k-1) + dz ! dynamical levels	
   enddo
   !print*,zsurf
   !print*,zt(:)
   do k = 1,mzp-1
      dzm(k) = 1. / (zt(k+1) - zt(k))
   enddo 
   
   dzm(mzp)=dzm(mzp-1)

   do k = 2,mzp
      dzt(k) = 1. / (zm(k) - zm(k-1))
   enddo
   dzt(1) = dzt(2) * dzt(2) / dzt(3)  
   !dzm(1) = 0.5/dz
   !dzm(2:mzp) = 1./dz
   
   return

end subroutine set_grid

!******************************************************************
!******************************************************************
subroutine set_flam_vert(ztopmax,k1,k2)
   
   !use plumegen_coms, only : nkp,zzcon
   implicit none
   integer imm,k,k1,k2
   real,    dimension(2)  :: ztopmax
   integer, dimension(2)  :: k_lim

   do imm=1,2
      do k=1,nkp-1
              if(zzcon(k) > ztopmax(imm) ) exit
      enddo
      k_lim(imm) = k
   enddo           
   k1=max(3,k_lim(1))
   k2=max(3,k_lim(2))
  
   if(k2 < k1) then
      !print*,'1: ztopmax k=',ztopmax(1), k1
      !print*,'2: ztopmax k=',ztopmax(2), k2
      k2=k1
      !stop 1234
   endif
    
end subroutine set_flam_vert

!******************************************************************
!******************************************************************
subroutine get_fire_properties(imm,iveg_ag,burnt_area,heat_input,entrain_const,fuel_moist)

   !use plumegen_coms  
   implicit none
   integer ::  moist,  i,  icount,imm,iveg_ag
   real::   bfract,  effload,  heat,  hinc, burnt_area, heat_input, entrain_const, fuel_moist
   real,    dimension(2,4) :: heat_flux


   data heat_flux/  &
   !---------------------------------------------------------------------
   !  heat flux      !IGBP Land Cover	    ! 
   !  min  ! max     !Legend and reference !
   !  kW/m^2         !description  	       ! 
   !--------------------------------------------------------------------
   30.0,	 80.0,   &! Tropical Forest         ! igbp 2 & 4
   30.0,  80.0,   &! Boreal forest           ! igbp 1 & 3
   4.4,	 23.0,   &! cerrado/woody savanna   | igbp  5 thru 9
   3.3,	  3.3    /! Grassland/cropland      ! igbp 10 thru 17
   !--------------------------------------------------------------------

   !-- fire at the surface
   !
   !area = 20.e+4   ! area of burn, m^2
   area = burnt_area! area of burn, m^2

   !- heat flux
   !heat_fluxW = heat_flux(imm,iveg_ag) * 1000. ! convert to W/m^2
   heat_fluxW = heat_input * 1000.              ! convert to W/m^2

   mdur = 53          ! duration of burn, minutes
   bload = 10.        ! total loading, kg/m**2 
   moist = fuel_moist ! fuel moisture, %. average fuel moisture,percent dry

   !maxtime =mdur+2  ! model time, min
   maxtime =mdur-1   ! model time, min

   !heat = 21.e6         !- joules per kg of fuel consumed                   
   !heat = 15.5e6        !- joules/kg - cerrado/savannah
   heat = 19.3e6         !- joules/kg - tropical forest (mt)
   !alpha = 0.1          !- entrainment constant
   !alpha = 0.05         !- entrainment constant
   alpha = entrain_const !- entrainment constant

   !-------------------- printout ----------------------------------------
   !!WRITE ( * ,  * ) ' SURFACE =', ZSURF, 'M', '  LCL =', ZBASE, 'M'  
   !
   !PRINT*,'======================================================='
   !print * , ' FIRE BOUNDARY CONDITION   :'  
   !print * , ' DURATION OF BURN, MINUTES =',MDUR  
   !print * , ' AREA OF BURN, HA	      =',AREA*1.e-4
   !print * , ' HEAT FLUX, kW/m^2	      =',heat_fluxW*1.e-3
   !print * , ' TOTAL LOADING, KG/M**2    =',BLOAD  
   !print * , ' FUEL MOISTURE, %	      =',MOIST !average fuel moisture,percent dry
   !print * , ' MODEL TIME, MIN.	      =',MAXTIME  
   !
   ! ******************** fix up inputs *********************************

                                             
   IF (MOD (MAXTIME, 2) .NE.0) MAXTIME = MAXTIME+1  !make maxtime even
                                               
   MAXTIME = MAXTIME * 60  ! and put in seconds

   RSURF = SQRT (AREA / 3.14159) !- entrainment surface radius (m)

   FMOIST   = MOIST / 100.       !- fuel moisture fraction

   ! Calculate the energy flux and water content at lower boundary.
   ! Fills heating() on a minute basis. Could ask for a file at this po
   ! in the program. Whatever is input has to be adjusted to a one
   ! minute timescale.
                        
   DO I = 1, ntime         !- make sure of energy release
      HEATING (I) = 0.0001  !- avoid possible divide by 0
   enddo  

   TDUR = MDUR * 60.       !- number of seconds in the burn

   bfract = 1.             !- combustion factor

   EFFLOAD = BLOAD * BFRACT  !- patchy burning
  
   ! Spread the burning evenly over the interval except for the first 
   ! few minutes for stability
   ICOUNT = 1  

   if(MDUR > NTIME) STOP 'Increase time duration (ntime) in min - see file "plumerise_mod.f90"'

   DO WHILE (ICOUNT.LE.MDUR)                             
      !  HEATING (ICOUNT) = HEAT * EFFLOAD / TDUR  ! W/m**2 
      !  HEATING (ICOUNT) = 80000.  * 0.55         ! W/m**2 

         HEATING (ICOUNT) = heat_fluxW  * 0.55     ! W/m**2 (0.55 converte para energia convectiva)
         ICOUNT = ICOUNT + 1  
   ENDDO  
   !     ramp for 5 minutes
  
   HINC = HEATING (1) / 4.  
   HEATING (1) = 0.1  
   HEATING (2) = HINC  
   HEATING (3) = 2. * HINC  
   HEATING (4) = 3. * HINC 

   return

end subroutine get_fire_properties

!******************************************************************
!******************************************************************
SUBROUTINE MAKEPLUME ( kmt,ztopmax,imm)  
   
   ! *********************************************************************
   !
   !    EQUATION SOURCE--Kessler Met.Monograph No. 32 V.10 (K)
   !    Alan Weinstein, JAS V.27 pp 246-255. (W),
   !    Ogura and Takahashi, Monthly Weather Review V.99,pp895-911 (OT)
   !    Roger Pielke,Mesoscale Meteorological Modeling,Academic Press,1984
   !    Originally developed by: Don Latham (USFS)
   !
   !
   ! ************************ VARIABLE ID ********************************
   !
   !     DT=COMPUTING TIME INCREMENT (SEC)
   !     DZ=VERTICAL INCREMENT (M)
   !     LBASE=LEVEL ,CLOUD BASE
   !
   !     CONSTANTS:
   !       G = GRAVITATIONAL ACCELERATION 9.80796 (M/SEC/SEC).
   !       R = DRY AIR GAS CONSTANT (287.04E6 JOULE/KG/DEG K)
   !       CP = SPECIFIC HT. (1004 JOULE/KG/DEG K)
   !       HEATCOND = HEAT OF CONDENSATION (2.5E6 JOULE/KG)
   !       HEATFUS = HEAT OF FUSION (3.336E5 JOULE/KG)
   !       HEATSUBL = HEAT OF SUBLIMATION (2.83396E6 JOULE/KG)
   !       EPS = RATIO OF MOL.WT. OF WATER VAPOR TO THAT OF DRY AIR (0.622)
   !       DES = DIFFERENCE BETWEEN VAPOR PRESSURE OVER WATER AND ICE (MB)
   !       TFREEZE = FREEZING TEMPERATURE (K)
   !
   !
   !     PARCEL VALUES:
   !       T = TEMPERATURE (K)
   !       TXS = TEMPERATURE EXCESS (K)
   !       QH = HYDROMETEOR WATER CONTENT (G/G DRY AIR)
   !       QHI = HYDROMETEOR ICE CONTENT (G/G DRY AIR)
   !       QC = WATER CONTENT (G/G DRY AIR)
   !       QVAP = WATER VAPOR MIXING RATIO (G/G DRY AIR)
   !       QSAT = SATURATION MIXING RATIO (G/G DRY AIR)
   !       RHO = DRY AIR DENSITY (G/M**3) MASSES = RHO*Q'S IN G/M**3
   !        ES = SATURATION VAPOR PRESSURE (kPa)
   !
   !     ENVIRONMENT VALUES:
   !       TE = TEMPERATURE (K)
   !       PE = PRESSURE (kPa)
   !       QVENV = WATER VAPOR (G/G)
   !       RHE = RELATIVE HUMIDITY FRACTION (e/esat)
   !       DNE = dry air density (kg/m^3)
   !
   !     HEAT VALUES:
   !       HEATING = HEAT OUTPUT OF FIRE (WATTS/M**2)
   !       MDUR = DURATION OF BURN, MINUTES
   !
   !       W = VERTICAL VELOCITY (M/S)
   !       RADIUS=ENTRAINMENT RADIUS (FCN OF Z)
   !	RSURF = ENTRAINMENT RADIUS AT GROUND (SIMPLE PLUME, TURNER)
   !	ALPHA = ENTRAINMENT CONSTANT
   !       MAXTIME = TERMINATION TIME (MIN)
   !
   !
   !**********************************************************************
   !**********************************************************************               
   !use plumegen_coms 
   implicit none 
   !logical :: endspace  
   character (len=10) :: varn
   integer ::  izprint, iconv,  itime, k, kk, kkmax, deltak,ilastprint,kmt &
               ,nrectotal,i_micro,n_sub_step,finalout
   real ::  vc, g,  r,  cp,  eps,  &
               tmelt,  heatsubl,  heatfus,  heatcond, tfreeze, &
               ztopmax, wmax, rmaxtime, es, ESAT_PR, heat,dt_save

   integer :: imm

   !
   ! ******************* SOME CONSTANTS **********************************
   !      XNO=10.0E06 median volume diameter raindrop (K table 4)
   !      VC = 38.3/(XNO**.125) mean volume fallspeed eqn. (K)
   
   parameter (vc = 5.107387)  
   parameter (g = 9.80796, r = 287.04, cp = 1004., eps = 0.622,  tmelt = 273.3)
   parameter (heatsubl = 2.834e6, heatfus = 3.34e5, heatcond = 2.501e6)
   parameter (tfreeze = 269.3)  

   tstpf = 2.0  	! timestep factor
   finalout = 0   ! boolean, when this is set to 1, save last plume output
   nrectotal=150

   !*************** PROBLEM SETUP AND INITIAL CONDITIONS *****************
   mintime = 1  
   ztopmax = 0. 
   ztop    = 0. 
   time = 0.  
   dt = 1.
   wmax = 1. 
   kkmax   = 10
   deltaK  = 20
   ilastprint=0
   L       = 1   ! L initialization

   viscosity = 500.!- viscosity constant (original value: 0.001)


   ! Initialize the model
   CALL INITIAL(kmt)  

   ! Initial print fields:
   izprint  = 1          ! if = 0 => no printout
   if (izprint.ne.0) then
      open(2, file = 'plumegen.dat')  
      open(19,file='plumegen.gra',         &
      form='unformatted',access='direct',status='unknown',  &
      recl=4*nrectotal)  !PC   
      call printout (izprint,nrectotal,finalout)
      ilastprint=2
   endif     

   !******************* model evolution ******************************
   rmaxtime = float(maxtime)

   DO WHILE (TIME.LE.RMAXTIME)  !beginning of time loop

      ! do itime=1,120

      ! Set model top integration
      nm1 = min(kmt, kkmax + deltak)
   
      ! Set timestep
      ! dt = (zm(2)-zm(1)) / (tstpf * wmax)  
      dt = min(5.,(zm(2)-zm(1)) / (tstpf * wmax))
                                
      ! Elapsed time, sec
      time = time+dt 

      ! Elapsed time, minutes                                      
      mintime = 1 + int (time) / 60     
      wmax = 1.  !no zeroes allowed.

      !************************** BEGIN SPACE LOOP **************************

      !    print*,'======================================',time/60.,' mn'
      ! Zero out all model tendencies
      call tend0_plumerise

      ! Surface bounday conditions (k=1)
      L=1
      call lbound_mtt()

      ! Dynamics for the level k>1 

      ! W advection 
      ! call vel_advectc_plumerise(NM1,WC,WT,DNE,DZM)
      call vel_advectc_plumerise(NM1,WC,WT,RHO,DZM)
  
      ! Scalars advection 1
      call scl_advectc_plumerise('SC',NM1)

      ! Scalars advection 2
      !call scl_advectc_plumerise2('SC',NM1)

      ! Scalars entrainment, adiabatic
      call scl_misc(NM1)

      ! Scalars dinamic entrainment
      call  scl_dyn_entrain(NM1)
    
      !-- gravity wave damping using Rayleigh friction layer fot T
      call damp_grav_wave(1,nm1,deltak,dt,zt,zm,w,t,tt,qv,qh,qi,qc,te,pe,qvenv&
                       ,vel_p,vel_t,vel_e)

      ! Microphysics
      ! goto 101 ! bypass microphysics
      dt_save=dt
      n_sub_step=3
      dt=dt/float(n_sub_step)

      do i_micro=1,n_sub_step
   
         ! Sedim ?
         call fallpart(NM1)
         ! Microphysics
         do L=2,nm1-1
            WBAR    = 0.5*(W(L)+W(L-1))
            es      = 0.1*esat (t(L)) !blob saturation vapor pressure, em kPa
            qsat(L) = (eps * es) / (pe(L) - es)  !blob saturation lwc g/g dry air
            EST (L) = ES  
            RHO (L) = 3483.8 * PE (L) / T (L) ! AIR PARCEL DENSITY , G/M**3
            !srf18jun2005
            !	IF (W(L) .ge. 0.) DQSDZ = (QSAT(L  ) - QSAT(L-1)) / (ZT(L  ) -ZT(L-1))
            !	IF (W(L) .lt. 0.) DQSDZ = (QSAT(L+1) - QSAT(L  )) / (ZT(L+1) -ZT(L  ))
	         IF (W(L) .ge. 0.) then 
	            DQSDZ = (QSAT(L+1) - QSAT(L-1)) / (ZT(L+1 )-ZT(L-1))
	         ELSE
	            DQSDZ = (QSAT(L+1) - QSAT(L-1)) / (ZT(L+1) -ZT(L-1))
	         ENDIF 
	
	         call waterbal  
         enddo
      enddo
      dt=dt_save

      101 continue
    
      ! W-viscosity for stability 
      call visc_W(nm1,deltak,kmt)

      ! Update scalars
      call update_plumerise(nm1,'S')
      !print*,'wi apos update=',w(1:nm1)
      !print*,'Ti apos update=',T(1:nm1)

      call hadvance_plumerise(1,nm1,dt,WC,WT,W,mintime) 

      ! Buoyancy
      call buoyancy_plumerise(NM1, T, TE, QV, QVENV, QH, QI, QC, WT, SCR1)
 
      ! Entrainment 
      call entrainment(NM1,W,WT,RADIUS,ALPHA)

      ! Update W
      call update_plumerise(nm1,'W')

      call hadvance_plumerise(2,nm1,dt,WC,WT,W,mintime) 


      !-- misc
      do k=2,nm1
         !    pe esta em kpa  - esat do rams esta em mbar = 100 Pa = 0.1 kpa
         es       = 0.1*esat (t(k)) !blob saturation vapor pressure, em kPa
         !    rotina do plumegen calcula em kPa
         !    es       = esat_pr (t(k))  !blob saturation vapor pressure, em kPa
         qsat(k) = (eps * es) / (pe(k) - es)  !blob saturation lwc g/g dry air
         est (k) = es  
         txs (k) = t(k) - te(k)
         rho (k) = 3483.8 * pe (k) / t (k) ! air parcel density , g/m**3
                                       ! no pressure diff with radius
				       
         if((abs(wc(k))).gt.wmax) wmax = abs(wc(k)) ! keep wmax largest w

         !srf-27082005
         !     if((abs(wt(k))).gt.wtmax) wtmax = abs(wt(k)) ! keep wmax largest w
      enddo  

      ! Gravity wave damping using Rayleigh friction layer for W
      call damp_grav_wave(2,nm1,deltak,dt,zt,zm,w,t,tt,qv,qh,qi,qc,te,pe,qvenv&
                       ,vel_p,vel_t,vel_e)


      ! Update radius (para versao original do modelo, comente as 3 linhas abaixo
      do k=2,nm1
         radius(k) = rad_p(k)
      enddo
   

      ! Try to find the plume top (above surface height)
    	kk = 1
    	do while (w (kk) .gt. 1.)  
    	   kk = kk + 1  
    	   ztop =  zm(kk) 
    	   !print*,'W=',w (kk)
    	enddo  

      ztop_(mintime) = ztop
      ztopmax = max (ztop, ztopmax) 
      kkmax   = max (kk  , kkmax  ) 
      !print * ,'ztopmax=', mintime,'mn ',ztop_(mintime), ztopmax!,wtmax

      ! If the solution is going to a stationary phase, exit
      if(mintime > 40) then
         if( abs(ztop_(mintime)-ztop_(mintime-10)) < DZ ) exit
      endif
   
      if(ilastprint == mintime) then
         call printout (izprint,nrectotal,finalout)  
         ilastprint = mintime+1
      endif      

    
   ENDDO   !do next timestep

   !print * ,' ztopmax=',ztopmax,'m',mintime,'mn '
   !print*,'======================================================='

   !the last printout
   !if (izprint.ne.0) then
   !   call printout (izprint,nrectotal)  
   !   close (2) ; close (19)           
   !endif
   if (izprint.ne.0) then
      print * ,'Writing final output for simulation'
      finalout = 1
      open(5, file = 'final_plume.dat')
      call printout (izprint,nrectotal,finalout)
      close (2) ; close (19) ; close(5)
   endif

   RETURN  
END SUBROUTINE MAKEPLUME

!******************************************************************
!******************************************************************
SUBROUTINE BURN(EFLUX, WATER)  
	
   ! Calculates the energy flux and water content at lboundary
   ! use plumegen_coms                               
   ! real, parameter :: HEAT = 21.E6 !Joules/kg
   ! real, parameter :: HEAT = 15.5E6 !Joules/kg - cerrado
   real, parameter :: HEAT = 19.3E6 !Joules/kg - floresta em Alta Floresta (MT)
   real :: eflux,water

   ! The emission factor for water is 0.5. The water produced, in kg,
   ! is then  fuel mass*0.5 + (moist/100)*mass per square meter.
   ! The fire burns for DT out of TDUR seconds, the total amount of
   ! fuel burned is AREA*BLOAD*(DT/TDUR) kg. this amount of fuel is
   ! considered to be spread over area AREA and so the mass burned per
   ! unit area is BLOAD*(DT/TDUR), and the rate is BLOAD/TDUR.
        
   IF (TIME.GT.TDUR) THEN !is the burn over?   
      EFLUX = 0.000001    !prevent a potential divide by zero
      WATER = 0.  
      RETURN  
   ELSE                                                    
      EFLUX = HEATING (MINTIME)                          ! Watts/m**2                                                   
      !  WATER = EFLUX * (DT / HEAT) * (0.5 + FMOIST)       ! kg/m**2 
      WATER = EFLUX * (DT / HEAT) * (0.5 + FMOIST) /0.55 ! kg/m**2 
      WATER = WATER * 1000.                              ! g/m**2
      !print*,'BURN:',time,EFLUX/1.e+9
   ENDIF  

   RETURN  
END SUBROUTINE BURN

!******************************************************************
!******************************************************************
SUBROUTINE LBOUND_MTT ()  
!
! ********** BOUNDARY CONDITIONS AT ZSURF FOR PLUME AND CLOUD ********
!
! source of equations: J.S. Turner Buoyancy Effects in Fluids
!                      Cambridge U.P. 1973 p.172,
!                      G.A. Briggs Plume Rise, USAtomic Energy Commissio
!                      TID-25075, 1969, P.28
!
! fundamentally a point source below ground. at surface, this produces
! a velocity w(1) and temperature T(1) which vary with time. There is
! also a water load which will first saturate, then remainder go into
! QC(1).
! EFLUX = energy flux at ground,watt/m**2 for the last DT
!
!use plumegen_coms  
implicit none
real, parameter :: g = 9.80796, r = 287.04, cp = 1004.6, eps = 0.622,tmelt = 273.3
real, parameter :: tfreeze = 269.3, pi = 3.14159, e1 = 1./3., e2 = 5./3.
real :: es,  eflux, water,  pres, c1,  c2, f, zv,  denscor, xwater ,ESAT_PR
!            
QH (1) = QH (2)   !soak up hydrometeors
QI (1) = QI (2)              
QC (1) = 0.       !no cloud here
!
!
   CALL BURN (EFLUX, WATER)  
!
!  calculate parameters at boundary from a virtual buoyancy point source
!
   PRES = PE (1) * 1000.   !need pressure in N/m**2
                              
   C1 = 5. / (6. * ALPHA)  !alpha is entrainment constant

   C2 = 0.9 * ALPHA  

   F = EFLUX / (PRES * CP * PI)  
                             
   F = G * R * F * AREA  !buoyancy flux
                 
   ZV = C1 * RSURF  !virtual boundary height
                                   
   W (1) = C1 * ( (C2 * F) **E1) / ZV**E1  !boundary velocity
                                         
   DENSCOR = C1 * F / G / (C2 * F) **E1 / ZV**E2   !density correction

   T (1) = TE (1) / (1. - DENSCOR)    !temperature of virtual plume at zsurf
   
!-- para testes
!   W(1)=-W(1)/100.
!   T(1)=TE(1)+13.5
!

   WC(1) = W(1)
   
   VEL_P(1) = 0.
   rad_p(1) = rsurf

   SC(1) = 1000.!SCE(1)+F/1000.*dt  ! gas/particle (g/g)

! %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
!     match dw/dz,dt/dz at the boundary. F is conserved.
!
   !WBAR = W (1) * (1. - 1. / (6. * ZV) )  
   !ADVW = WBAR * W (1) / (3. * ZV)  
   !ADVT = WBAR * (5. / (3. * ZV) ) * (DENSCOR / (1. - DENSCOR) )  
   !ADVC = 0.  
   !ADVH = 0.  
   !ADVI = 0.  
   !ADIABAT = - WBAR * G / CP  
   VTH (1) = - 4.  
   VTI (1) = - 3.  
   TXS (1) = T (1) - TE (1)  

   VISC (1) = VISCOSITY  

   RHO (1) = 3483.8 * PE (1) / T (1)   !air density at level 1, g/m**3

   XWATER = WATER / (W (1) * DT * RHO (1) )   !firewater mixing ratio
                                            
   QV (1) = XWATER + QVENV (1)  !plus what's already there 

!  PE esta em kPa  - ESAT do RAMS esta em mbar = 100 Pa = 0.1 kPa
   ES       = 0.1*ESAT (T(1)) !blob saturation vapor pressure, em kPa
!  rotina do plumegen ja calcula em kPa
!  ES       = ESAT_PR (T(1))  !blob saturation vapor pressure, em kPa

   EST  (1)  = ES                                  
   QSAT (1) = (EPS * ES) / (PE (1) - ES)   !blob saturation lwc g/g dry air
  
   IF (QV (1) .gt. QSAT (1) ) THEN  
       QC (1) = QV   (1) - QSAT (1) + QC (1)  !remainder goes into cloud drops
       QV (1) = QSAT (1)  
   ENDIF  
!
   CALL WATERBAL  
!
RETURN  
END SUBROUTINE LBOUND_MTT
!-------------------------------------------------------------------------------
!
SUBROUTINE INITIAL ( kmt)  
!
! ************* SETS UP INITIAL CONDITIONS FOR THE PROBLEM ************
!use plumegen_coms 
implicit none 
real, parameter :: tfreeze = 269.3
integer ::  isub,  k,  n1,  n2,  n3,  lbuoy,  itmp,  isubm1 ,kmt
real ::     xn1,  xi,  es,  ESAT_PR
!
N=kmt
! initialize temperature structure,to the end of equal spaced sounding,
  do k = 1, N			  
  TXS (k) = 0.0  
    W (k) = 0.0             
    T (k) = TE(k) !blob set to environment		  
    WC(k) = 0.0
    WT(k) = 0.0
    QV(k) = QVENV (k)                      
   VTH(k) = 0.		!initial rain velocity = 0	                     
   VTI(k) = 0.		!initial ice  velocity = 0	                     
    QH(k) = 0.		     !no rain				  
    QI(k) = 0.		     !no ice				  
    QC(k) = 0.		!no cloud drops	                     
!  PE esta em kPa  - ESAT do RAMS esta em mbar = 100 Pa = 0.1 kPa
   ES       = 0.1*ESAT (T(k)) !blob saturation vapor pressure, em kPa
!  rotina do plumegen calcula em kPa
!  ES       = ESAT_PR (T(k))  !blob saturation vapor pressure, em kPa
   EST  (k) = ES  
   QSAT (k) = (.622 * ES) / (PE (k) - ES) !saturation lwc g/g
   RHO  (k) = 3483.8 * PE (k) / T (k) 	!dry air density g/m**3    
  
   VEL_P(k) = 0.
   rad_p(k) = 0.
  enddo  

! Initialize the entrainment radius, Turner-style plume
  radius(1) = rsurf
  do k=2,N
     radius(k) = radius(k-1)+(6./5.)*alpha*(zt(k)-zt(k-1))
     rad_p(k)  = radius(k)
  enddo
    
  rad_p(1) = rsurf

!  Initialize the viscosity
   VISC (1) = VISCOSITY
   do k=2,N
     VISC (k) = max(1.e-3,visc(k-1) - 1.* VISCOSITY/float(nkp))
   enddo

   call LBOUND_MTT()

!
!**********************************************************************
!	Initialize non-temperature variables
!
   !print*,' INITIAL:::::::::::::::::::::::::::::::::'
   !print*,' k,es,qsat(i)*1000,qv(i)*1000,pe(i),t(i),rho(i)    '

!  DO k = 2, N  
                          
!  PE esta em kPa  - ESAT do RAMS esta em mbar = 100 Pa = 0.1 kPa
!   ES       = 0.1*ESAT (T(k)) !blob saturation vapor pressure, em kPa
!  rotina do plumegen calcula em kPa
!  ES       = ESAT_PR (T(k))  !blob saturation vapor pressure, em kPa

!   EST (k) = ES  

!   QSAT (k) = (.622 * ES) / (PE (k) - ES) !saturation lwc g/g
!   print*,'sat=',k,T(k),pe(k), QSAT (k)
!   QV   (k) = QVENV (k)                      
!   VTH  (k) = 0.		!initial rain velocity = 0	                     
!   QC   (k) = 0.		!no cloud drops	                     
!   QH   (k) = 0.		!no rain	                     
!   QI   (k) = 0.		!no ice	                                  

!   RHO  (k) = 3483.8 * PE (k) / T (k) 	!dry air density g/m**3    
   

   !write(*,111) k,es,qsat(k)*1000,qv(k)*1000,pe(k),t(k),rho(k)                                    
!111 format(1x,i4,6f10.2)
   
   !VISC (k) = VISCOSITY  
 !  VISC (k) = max(1.e-3,visc(k-1) - 1.* VISCOSITY/float(nkp))
 !  print*,k,VISC (k) 

   !SC   (k) = SCE(k)  ! (g/g) - gas/particle, mixing ratio
!  ENDDO  



!  stop 4333
!--   Initialize gas/concentration
  !DO k =10,20
  !   SC(k) = 20.
  !ENDDO
  !stop 333
RETURN  
END SUBROUTINE INITIAL
!-------------------------------------------------------------------------------
!
subroutine damp_grav_wave(ifrom,nm1,deltak,dt,zt,zm,w,t,tt,qv,qh,qi,qc,te,pe,qvenv&
                         ,vel_p,vel_t,vel_e)
implicit none
integer nm1,ifrom,deltak
real dt
real, dimension(nm1) :: w,t,tt,qv,qh,qi,qc,te,pe,qvenv,dummy,zt,zm&
                       ,vel_p,vel_t,vel_e

!return
if(ifrom==1) then
 call friction(ifrom,nm1,deltak,dt,zt,zm,t,tt    ,te)
! call friction(ifrom,nm1,deltak,dt,zt,zm,vel_p,vel_t,vel_e)
! call friction(ifrom,nm1,dt,zt,zm,qv,qvt,qvenv)
 return
endif 

dummy(:) = 0.
if(ifrom==2) call friction(ifrom,nm1,deltak,dt,zt,zm,w,dummy ,dummy)
!call friction(ifrom,nm1,dt,zt,zm,qi,qit ,dummy)
!call friction(ifrom,nm1,dt,zt,zm,qh,qht ,dummy)
!call friction(ifrom,nm1,dt,zt,zm,qc,qct ,dummy)
return
end subroutine damp_grav_wave
!-------------------------------------------------------------------------------
!
subroutine friction(ifrom,nm1,deltak,dt,zt,zm,var1,vart,var2)
implicit none
real, dimension(nm1) :: var1,var2,vart,zt,zm
integer k,nfpt,kf,nm1,ifrom,deltak
real zmkf,ztop,distim,c1,c2,dt
!nfpt=50
!kf = nm1 - nfpt
!kf = nm1 - int(deltak/2) ! orig
kf = nm1 - int(deltak)
!if( kf < 10) return !ver necessidade

zmkf = zm(kf) !old: float(kf )*dz
ztop = zm(nm1)

!distim = 60. ! orig
distim = min(3.*dt,60.)


c1 = 1. / (distim * (ztop - zmkf))
c2 = dt * c1

if(ifrom == 1) then  
  do k = nm1,2,-1
   if (zt(k) .le. zmkf) cycle  ! exit ???
   vart(k) = vart(k)   + c1 * (zt(k) - zmkf)*(var2(k) - var1(k))
  enddo
elseif(ifrom == 2) then
  do k = nm1,2,-1
   if (zt(k) .le. zmkf) cycle  ! exit ???
   var1(k) =  var1(k) + c2 * (zt(k) - zmkf)*(var2(k) - var1(k))
  enddo
endif
return
end subroutine friction
!-------------------------------------------------------------------------------
!
subroutine vel_advectc_plumerise(m1,wc,wt,rho,dzm)

implicit none
integer :: k,m1
real, dimension(m1) :: wc,wt,flxw,dzm,rho
real, dimension(m1) :: dn0 ! var local
real :: c1z

!dzm(:)= 1./dz

dn0(1:m1)=rho(1:m1)*1.e-3 ! converte de cgs para mks

flxw(1) = wc(1) * dn0(1) 

do k = 2,m1-1
   flxw(k) = wc(k) * .5 * (dn0(k) + dn0(k+1))
enddo

! Compute advection contribution to W tendency

c1z = .5 

do k = 2,m1-2

   wt(k) = wt(k)  &
      + c1z * dzm(k) / (dn0(k) + dn0(k+1)) *     (   &
	(flxw(k) + flxw(k-1))  * (wc(k) + wc(k-1))   &
      - (flxw(k) + flxw(k+1))  * (wc(k) + wc(k+1))   &
      + (flxw(k+1) - flxw(k-1)) * 2.* wc(k)       )

enddo

return
end subroutine vel_advectc_plumerise
!-------------------------------------------------------------------------------
!
subroutine hadvance_plumerise(iac,m1,dt,wc,wt,wp,mintime)

implicit none
integer :: k,iac
integer :: m1,mintime
real, dimension(m1) :: dummy, wc,wt,wp
real eps,dt
!     It is here that the Asselin filter is applied.  For the velocities
!     and pressure, this must be done in two stages, the first when
!     IAC=1 and the second when IAC=2.


eps = .2
if(mintime == 1) eps=0.5

!     For both IAC=1 and IAC=2, call PREDICT for U, V, W, and P.
!
call predict_plumerise(m1,wc,wp,wt,dummy,iac,2.*dt,eps)
!print*,'mintime',mintime,eps
!do k=1,m1
!   print*,'W-HAD',k,wc(k),wp(k),wt(k)
!enddo
return
end subroutine hadvance_plumerise
!-------------------------------------------------------------------------------
!
subroutine predict_plumerise(npts,ac,ap,fa,af,iac,dtlp,epsu)
implicit none
integer :: npts,iac,m
real :: epsu,dtlp
real, dimension(*) :: ac,ap,fa,af

!     For IAC=3, this routine moves the arrays AC and AP forward by
!     1 time level by adding in the prescribed tendency. It also
!     applies the Asselin filter given by:

!              {AC} = AC + EPS * (AP - 2 * AC + AF)

!     where AP,AC,AF are the past, current and future time levels of A.
!     All IAC=1 does is to perform the {AC} calculation without the AF
!     term present.  IAC=2 completes the calculation of {AC} by adding
!     the AF term only, and advances AC by filling it with input AP
!     values which were already updated in ACOUSTC.
!

if (iac .eq. 1) then
   do m = 1,npts
      ac(m) = ac(m) + epsu * (ap(m) - 2. * ac(m))
   enddo
   return
elseif (iac .eq. 2) then
   do m = 1,npts
      af(m) = ap(m)
      ap(m) = ac(m) + epsu * af(m)
   enddo
!elseif (iac .eq. 3) then
!   do m = 1,npts
!      af(m) = ap(m) + dtlp * fa(m)
!   enddo
!   if (ngrid .eq. 1 .and. ipara .eq. 0) call cyclic(nzp,nxp,nyp,af,'T')
!   do m = 1,npts
!      ap(m) = ac(m) + epsu * (ap(m) - 2. * ac(m) + af(m))
!   enddo
endif

do m = 1,npts
  ac(m) = af(m)
enddo
return
end subroutine predict_plumerise
!-------------------------------------------------------------------------------
!
subroutine  buoyancy_plumerise(m1, T, TE, QV, QVENV, QH, QI, QC, WT, scr1)
  !use plumegen_coms, only : rbuoy
implicit none
integer :: k,m1
real, parameter :: g = 9.8, eps = 0.622, gama = 0.5 ! mass virtual coeff.
real, dimension(m1) :: T, TE, QV, QVENV, QH, QI, QC, WT, scr1
real :: TV,TVE,QWTOTL,umgamai
real, parameter :: mu = 0.15 

!- orig
umgamai = 1./(1.+gama) ! compensa a falta do termo de aceleracao associado `as
                       ! das pertubacoes nao-hidrostaticas no campo de pressao

!- new                 ! Siesbema et al, 2004
!umgamai = 1./(1.-2.*mu)

do k = 2,m1-1

    TV =   T(k) * (1. + (QV(k)   /EPS))/(1. + QV(k)   )  !blob virtual temp.                                        	   
    TVE = TE(k) * (1. + (QVENV(k)/EPS))/(1. + QVENV(k))  !and environment

    QWTOTL = QH(k) + QI(k) + QC(k)                       ! QWTOTL*G is drag
!- orig
   !scr1(k)= G*( umgamai*(  TV - TVE) / TVE   - QWTOTL) 
    scr1(k)= G*  umgamai*( (TV - TVE) / TVE   - QWTOTL) 

    !if(k .lt. 10)print*,'BT',k,TV,TVE,TVE,QWTOTL
enddo

do k = 2,m1-2

!srf- just for output
    rbuoy(k)=0.5*(scr1(k)+scr1(k+1))

    wt(k) = wt(k)+0.5*(scr1(k)+scr1(k+1))
!   print*,'W-BUO',k,wt(k),scr1(k),scr1(k+1)
enddo
!srf- just for output
    rbuoy(1)=rbuoy(2)
    
end subroutine  buoyancy_plumerise
!-------------------------------------------------------------------------------
!
subroutine ENTRAINMENT(m1,w,wt,radius,ALPHA)
!use plumegen_coms, only : vel_p,vel_e,dwdt_entr
implicit none
integer :: k,m1
real, dimension(m1) :: w,wt,radius
real DMDTM,ALPHA,WBAR,RADIUS_BAR,umgamai,DYN_ENTR
real, parameter :: mu = 0.15 ,gama = 0.5 ! mass virtual coeff.

!- new - Siesbema et al, 2004
!umgamai = 1./(1.-2.*mu)

!- orig
umgamai = 1./(1.+gama) ! compensa a falta do termo de aceleracao associado `as
                       !  pertubacoes nao-hidrostaticas no campo de pressao

!
!-- ALPHA/RADIUS(L) = (1/M)DM/DZ  (W 14a)
  do k=2,m1-1

!-- for W: WBAR is only W(k)
!     WBAR=0.5*(W(k)+W(k-1))           
      WBAR=W(k)          
      RADIUS_BAR = 0.5*(RADIUS(k) + RADIUS(k-1))

! orig plump model
    ! DMDTM =           2. * ALPHA * ABS (WBAR) / RADIUS_BAR  != (1/M)DM/DT
      DMDTM = umgamai * 2. * ALPHA * ABS (WBAR) / RADIUS_BAR  != (1/M)DM/DT

!--  DMDTM*W(L) entrainment,
      wt(k) = wt(k)  - DMDTM*ABS (WBAR) !- DMDTM*ABS (WBAR)*1.875*0.5

     !if(VEL_P (k) - VEL_E (k) > 0.) cycle

!-   diynamic entrainment
     DYN_ENTR =  (2./3.1416)*0.5*ABS (VEL_P(k)-VEL_E(k)+VEL_P(k-1)-VEL_E(k-1)) /RADIUS_BAR

     wt(k) = wt(k)  - DYN_ENTR*ABS (WBAR)

!- entraiment acceleration for output only
    dwdt_entr(k) =  - DMDTM*ABS (WBAR)- DYN_ENTR*ABS (WBAR)

  enddo
!- entraiment acceleration for output only
    dwdt_entr(1) = dwdt_entr(2)


end subroutine  ENTRAINMENT
!     ****************************************************************

subroutine scl_misc(m1)
!use plumegen_coms
implicit none
real, parameter :: g = 9.81, cp=1004.
integer m1,k
real dmdtm

 do k=2,m1-1
      WBAR    = 0.5*(W(k)+W(k-1))  
!-- dry adiabat
      ADIABAT = - WBAR * G / CP 
!      
!-- entrainment     
      DMDTM = 2. * ALPHA * ABS (WBAR) / RADIUS (k)  != (1/M)DM/DT
      
!-- tendency temperature = adv + adiab + entrainment
      TT(k) = TT(K) + ADIABAT - DMDTM * ( T  (k) -    TE (k) ) 

!-- tendency water vapor = adv  + entrainment
      QVT(K) = QVT(K)         - DMDTM * ( QV (k) - QVENV (k) )

      QCT(K) = QCT(K)	      - DMDTM * ( QC (k)  )
      QHT(K) = QHT(K)	      - DMDTM * ( QH (k)  )
      QIT(K) = QIT(K)	      - DMDTM * ( QI (k)  )

!-- tendency horizontal speed = adv  + entrainment
      VEL_T(K) = VEL_T(K)     - DMDTM * ( VEL_P (k) - VEL_E (k) )

!-- tendency horizontal speed = adv  + entrainment
      rad_t(K) = rad_t(K)     + 0.5*DMDTM*(6./5.)*RADIUS (k)

!-- tendency gas/particle = adv  + entrainment
      SCT(K) = SCT(K)         - DMDTM * ( SC (k) -   SCE (k) )

enddo
end subroutine scl_misc

!     ****************************************************************

subroutine scl_dyn_entrain(m1)
!use plumegen_coms
implicit none
real, parameter :: g = 9.81, cp=1004., pi=3.1416
integer m1,k
real dmdtm

 do k=2,m1-1
!      
!-- tendency horizontal radius from dyn entrainment
     !rad_t(K) = rad_t(K)   +     (vel_e(k)-vel_p(k)) /pi
      rad_t(K) = rad_t(K)   + ABS((vel_e(k)-vel_p(k)))/pi

!-- entrainment     
     !DMDTM = (2./3.1416)  *     (VEL_E (k) - VEL_P (k)) / RADIUS (k)  
      DMDTM = (2./3.1416)  *  ABS(VEL_E (k) - VEL_P (k)) / RADIUS (k)  

!-- tendency horizontal speed  from dyn entrainment
      VEL_T(K) = VEL_T(K)     - DMDTM * ( VEL_P (k) - VEL_E (k) )

!     if(VEL_P (k) - VEL_E (k) > 0.) cycle

!-- tendency temperature  from dyn entrainment
      TT(k) = TT(K)           - DMDTM * ( T (k) - TE  (k) ) 

!-- tendency water vapor  from dyn entrainment
      QVT(K) = QVT(K)         - DMDTM * ( QV (k) - QVENV (k) )

      QCT(K) = QCT(K)	      - DMDTM * ( QC (k)  )
      QHT(K) = QHT(K)	      - DMDTM * ( QH (k)  )
      QIT(K) = QIT(K)	      - DMDTM * ( QI (k)  )

!-- tendency gas/particle  from dyn entrainment
      SCT(K) = SCT(K)         - DMDTM * ( SC (k) - SCE (k) )

enddo
end subroutine scl_dyn_entrain

!-------------------------------------------------------------------------------
!
subroutine scl_advectc_plumerise(varn,mzp)
!use plumegen_coms
implicit none
integer :: mzp
character(len=*) :: varn
real :: dtlto2
integer :: k

!  wp => w
!- Advect  scalars
   dtlto2   = .5 * dt
!  vt3dc(1) =      (w(1) + wc(1)) * dtlto2 * dne(1)
   vt3dc(1) =      (w(1) + wc(1)) * dtlto2 * rho(1)*1.e-3!converte de CGS p/ MKS
   vt3df(1) = .5 * (w(1) + wc(1)) * dtlto2 * dzm(1)

   do k = 2,mzp
!     vt3dc(k) =  (w(k) + wc(k)) * dtlto2 *.5 * (dne(k) + dne(k+1))
      vt3dc(k) =  (w(k) + wc(k)) * dtlto2 *.5 * (rho(k) + rho(k+1))*1.e-3
      vt3df(k) =  (w(k) + wc(k)) * dtlto2 *.5 *  dzm(k)
     !print*,'vt3df-vt3dc',k,vt3dc(k),vt3df(k)
   enddo

 
!  do k = 1,mzp-1
  do k = 1,mzp
     vctr1(k) = (zt(k+1) - zm(k)) * dzm(k)
     vctr2(k) = (zm(k)   - zt(k)) * dzm(k)
!    vt3dk(k) = dzt(k) / dne(k)
     vt3dk(k) = dzt(k) /(rho(k)*1.e-3)
     !print*,'VT3dk',k,dzt(k) , dne(k)
  enddo

!      scalarp => scalar_tab(n,ngrid)%var_p
!      scalart => scalar_tab(n,ngrid)%var_t

!- temp advection tendency (TT)
   scr1=T
   call fa_zc_plumerise(mzp                   &
             	       ,T	  ,scr1  (1)  &
             	       ,vt3dc (1) ,vt3df (1)  &
             	       ,vt3dg (1) ,vt3dk (1)  &
             	       ,vctr1,vctr2	      )

   call advtndc_plumerise(mzp,T,scr1(1),TT,dt)

!- water vapor advection tendency (QVT)
   scr1=QV
   call fa_zc_plumerise(mzp                  &
             	       ,QV	  ,scr1  (1)  &
             	       ,vt3dc (1) ,vt3df (1)  &
             	       ,vt3dg (1) ,vt3dk (1)  &
             	       ,vctr1,vctr2	     )

   call advtndc_plumerise(mzp,QV,scr1(1),QVT,dt)

!- liquid advection tendency (QCT)
   scr1=QC
   call fa_zc_plumerise(mzp                  &
             	       ,QC	  ,scr1  (1)  &
             	       ,vt3dc (1) ,vt3df (1)  &
             	       ,vt3dg (1) ,vt3dk (1)  &
             	       ,vctr1,vctr2	     )

   call advtndc_plumerise(mzp,QC,scr1(1),QCT,dt)

!- ice advection tendency (QIT)
   scr1=QI
   call fa_zc_plumerise(mzp                  &
             	       ,QI	  ,scr1  (1)  &
             	       ,vt3dc (1) ,vt3df (1)  &
             	       ,vt3dg (1) ,vt3dk (1)  &
             	       ,vctr1,vctr2	     )

   call advtndc_plumerise(mzp,QI,scr1(1),QIT,dt)

!- hail/rain advection tendency (QHT)
!   if(ak1 > 0. .or. ak2 > 0.) then

      scr1=QH
      call fa_zc_plumerise(mzp                  &
             	          ,QH	    ,scr1  (1)  &
             	          ,vt3dc (1) ,vt3df (1)  &
             	          ,vt3dg (1) ,vt3dk (1)  &
             	          ,vctr1,vctr2	       )

      call advtndc_plumerise(mzp,QH,scr1(1),QHT,dt)
!   endif


!- horizontal wind advection tendency (VEL_T)

      scr1=VEL_P
      call fa_zc_plumerise(mzp                  &
             	          ,VEL_P     ,scr1  (1)  &
             	          ,vt3dc (1) ,vt3df (1)  &
             	          ,vt3dg (1) ,vt3dk (1)  &
             	          ,vctr1,vctr2	       )

      call advtndc_plumerise(mzp,VEL_P,scr1(1),VEL_T,dt)

!- vertical radius transport

      scr1=rad_p
      call fa_zc_plumerise(mzp                  &
             	          ,rad_p     ,scr1  (1)  &
             	          ,vt3dc (1) ,vt3df (1)  &
             	          ,vt3dg (1) ,vt3dk (1)  &
             	          ,vctr1,vctr2	       )

      call advtndc_plumerise(mzp,rad_p,scr1(1),rad_t,dt)
!   return

!- gas/particle advection tendency (SCT)
!    if(varn == 'SC')return
   scr1=SC
   call fa_zc_plumerise(mzp		    &
   	     	       ,SC	 ,scr1  (1)  &
   	     	       ,vt3dc (1) ,vt3df (1)  &
   	     	       ,vt3dg (1) ,vt3dk (1)  &
   	     	       ,vctr1,vctr2	     )
   
   call advtndc_plumerise(mzp,SC,scr1(1),SCT,dt)


return
end subroutine scl_advectc_plumerise
!-------------------------------------------------------------------------------
!
subroutine fa_zc_plumerise(m1,scp,scr1,vt3dc,vt3df,vt3dg,vt3dk,vctr1,vctr2)

implicit none
integer :: m1,k
real :: dfact
real, dimension(m1) :: scp,scr1,vt3dc,vt3df,vt3dg,vt3dk
real, dimension(m1) :: vctr1,vctr2

dfact = .5

! Compute scalar flux VT3DG
      do k = 1,m1-1
         vt3dg(k) = vt3dc(k)                   &
                  * (vctr1(k) * scr1(k)        &
                  +  vctr2(k) * scr1(k+1)      &
                  +  vt3df(k) * (scr1(k) - scr1(k+1)))
      enddo
      
! Modify fluxes to retain positive-definiteness on scalar quantities.
!    If a flux will remove 1/2 quantity during a timestep,
!    reduce to first order flux. This will remain positive-definite
!    under the assumption that ABS(CFL(i)) + ABS(CFL(i-1)) < 1.0 if
!    both fluxes are evacuating the box.

do k = 1,m1-1
 if (vt3dc(k) .gt. 0.) then
   if (vt3dg(k) * vt3dk(k)    .gt. dfact * scr1(k)) then
	 vt3dg(k) = vt3dc(k) * scr1(k)
   endif
 elseif (vt3dc(k) .lt. 0.) then
   if (-vt3dg(k) * vt3dk(k+1) .gt. dfact * scr1(k+1)) then
	 vt3dg(k) = vt3dc(k) * scr1(k+1)
   endif
 endif

enddo

! Compute flux divergence

do k = 2,m1-1
    scr1(k) = scr1(k)  &
            + vt3dk(k) * ( vt3dg(k-1) - vt3dg(k) &
            + scp  (k) * ( vt3dc(k)   - vt3dc(k-1)))
enddo
return
end subroutine fa_zc_plumerise
!-------------------------------------------------------------------------------
!
subroutine advtndc_plumerise(m1,scp,sca,sct,dtl)
implicit none
integer :: m1,k
real :: dtl,dtli
real, dimension(m1) :: scp,sca,sct

dtli = 1. / dtl
do k = 2,m1-1
   sct(k) = sct(k) + (sca(k)-scp(k)) * dtli
enddo
return
end subroutine advtndc_plumerise
!-------------------------------------------------------------------------------
!
subroutine tend0_plumerise
!use plumegen_coms, only: nm1,wt,tt,qvt,qct,qht,qit,sct,vel_t,rad_t
 wt  (1:nm1)  = 0.
 tt  (1:nm1)  = 0.
qvt  (1:nm1)  = 0.
qct  (1:nm1)  = 0.
qht  (1:nm1)  = 0.
qit  (1:nm1)  = 0.
vel_t(1:nm1)  = 0.
rad_t(1:nm1)  = 0.
sct  (1:nm1)  = 0.
end subroutine tend0_plumerise

!-------------------------------------------------------------------------------
subroutine visc_W(m1,deltak,kmt)
!use plumegen_coms
implicit none
integer m1,k,deltak,kmt,m2
real dz1t,dz1m,dz2t,dz2m,d2wdz,d2tdz  ,d2qvdz ,d2qhdz ,d2qcdz ,d2qidz ,d2scdz&
    ,d2vel_pdz,d2rad_dz
integer mI,mF,deltaM

  mI = 2
  mF = min(m1,kmt-1)
  deltaM = 1

do k=mI,mF,deltaM !v2
!do k=2,m2-1 !orig
 DZ1T   = 0.5*(ZT(K+1)-ZT(K-1))
 DZ2T   = VISC (k) / (DZ1T * DZ1T)  
 DZ1M   = 0.5*(ZM(K+1)-ZM(K-1))
 DZ2M   = VISC (k) / (DZ1M * DZ1M)  
 D2WDZ  = (W  (k + 1) - 2 * W  (k) + W  (k - 1) ) * DZ2M  
 D2TDZ  = (T  (k + 1) - 2 * T  (k) + T  (k - 1) ) * DZ2T  
 D2QVDZ = (QV (k + 1) - 2 * QV (k) + QV (k - 1) ) * DZ2T  
 D2QHDZ = (QH (k + 1) - 2 * QH (k) + QH (k - 1) ) * DZ2T 
 D2QCDZ = (QC (k + 1) - 2 * QC (k) + QC (k - 1) ) * DZ2T  
 D2QIDZ = (QI (k + 1) - 2 * QI (k) + QI (k - 1) ) * DZ2T  
 D2SCDZ = (SC (k + 1) - 2 * SC (k) + SC (k - 1) ) * DZ2T 
 d2vel_pdz=(vel_P  (k + 1) - 2 * vel_P  (k) + vel_P  (k - 1) ) * DZ2T
 d2rad_dz =(rad_p  (k + 1) - 2 * rad_p  (k) + rad_p  (k - 1) ) * DZ2T
 
  WT(k) =   WT(k) + D2WDZ
  TT(k) =   TT(k) + D2TDZ
			   
! print*,'V=',k,D2TDZ,T  (k + 1) - 2 * T  (k) + T  (k - 1),DZ2T		   
			   
 QVT(k) =  QVT(k) + D2QVDZ 
 QCT(k) =  QCT(k) + D2QCDZ
 QHT(k) =  QHT(k) + D2QHDZ 
 QIT(k) =  QIT(k) + D2QIDZ     

 VEL_T(k) =   VEL_T(k) + d2vel_pdz

 rad_t(k) =   rad_t(k) + d2rad_dz

 SCT(k) =  SCT(k) + D2SCDZ
 !print*,'W-VISC=',k,D2WDZ
enddo  

end subroutine visc_W

!     ****************************************************************

subroutine update_plumerise(m1,varn)
!use plumegen_coms
integer m1,k
character(len=*) :: varn
 
if(varn == 'W') then

 do k=2,m1-1
   W(k) =  W(k) +  WT(k) * DT  
 enddo
 return

else 
do k=2,m1-1
   T(k) =  T(k) +  TT(k) * DT  

  QV(k) = QV(k) + QVT(k) * DT  

  QC(k) = QC(k) + QCT(k) * DT !cloud drops travel with air 
  QH(k) = QH(k) + QHT(k) * DT  
  QI(k) = QI(k) + QIT(k) * DT 

  QV(k) = max(0., QV(k))
  QC(k) = max(0., QC(k))
  QH(k) = max(0., QH(k))
  QI(k) = max(0., QI(k))


  VEL_P(k) =  VEL_P(k) + VEL_T(k) * DT  

  rad_p(k) =  rad_p(k) + rad_t(k) * DT  

  SC(k)    =  SC(k)    + SCT(k)  * DT 

 enddo
endif
end subroutine update_plumerise
!-------------------------------------------------------------------------------
!
subroutine fallpart(m1)
!use plumegen_coms
integer m1,k
real vtc, dfhz,dfiz,dz1
!srf==================================
!   verificar se o gradiente esta correto 
!  
!srf==================================
!
!     XNO=1.E7  [m**-4] median volume diameter raindrop,Kessler
!     VC = 38.3/(XNO**.125), median volume fallspeed eqn., Kessler
!     for ice, see (OT18), use F0=0.75 per argument there. rho*q
!     values are in g/m**3, velocities in m/s

real, PARAMETER :: VCONST = 5.107387, EPS = 0.622, F0 = 0.75  
real, PARAMETER :: G = 9.81, CP = 1004.
! 

 do k=2,m1-1

   VTC = VCONST * RHO (k) **.125   ! median volume fallspeed (KTable4)
                                
!  hydrometeor assembly velocity calculations (K Table4)
!  VTH(k)=-VTC*QH(k)**.125  !median volume fallspeed, water            
   VTH (k) = - 4.	    !small variation with qh
   
   VHREL = W (k) + VTH (k)  !relative to surrounding cloud
 
!  rain ventilation coefficient for evaporation
   CVH(k) = 1.6 + 0.57E-3 * (ABS (VHREL) ) **1.5  
!
!  VTI(k)=-VTC*F0*QI(k)**.125    !median volume fallspeed,ice             
   VTI (k) = - 3.                !small variation with qi

   VIREL = W (k) + VTI (k)       !relative to surrounding cloud
!
!  ice ventilation coefficient for sublimation
   CVI(k) = 1.6 + 0.57E-3 * (ABS (VIREL) ) **1.5 / F0  
!
!
   IF (VHREL.GE.0.0) THEN  
    DFHZ=QH(k)*(RHO(k  )*VTH(k  )-RHO(k-1)*VTH(k-1))/RHO(k-1)
   ELSE  
    DFHZ=QH(k)*(RHO(k+1)*VTH(k+1)-RHO(k  )*VTH(k  ))/RHO(k)
   ENDIF  
   !
   !
   IF (VIREL.GE.0.0) THEN  
    DFIZ=QI(k)*(RHO(k  )*VTI(k  )-RHO(k-1)*VTI(k-1))/RHO(k-1)
   ELSE  
    DFIZ=QI(k)*(RHO(k+1)*VTI(k+1)-RHO(k  )*VTI(k  ))/RHO(k)
   ENDIF
   
   DZ1=ZM(K)-ZM(K-1)
   
!    print*,k, qht(k) , DFHZ / DZ1,qit(k) , DFIZ / DZ1
!     print*,k,VTI(k),VTH(k)
   qht(k) = qht(k) - DFHZ / DZ1 !hydrometeors don't
   		  
   qit(k) = qit(k) - DFIZ / DZ1  !nor does ice? hail, what about



enddo
end subroutine fallpart
!-------------------------------------------------------------------------------
!
subroutine printout (izprint,nrectotal,finalout)  
!use plumegen_coms
implicit none
real, parameter :: tmelt = 273.3
integer, save :: nrec,nrecx
data nrec/0/,nrecx/0/
integer :: ko,izprint,interval,nrectotal,ii,k_initial,k_final,KK4,kl,ix,&
          imax(1),irange,k,finalout
real :: pea, btmp,etmp,vap1,vap2,gpkc,gpkh,gpki,deficit
real mass(nkp),xx(nkp),xxx, w_thresold
interval = 1              !debug time interval,min
!
IF (IZPRINT.EQ.0) RETURN  


do k=1,nrectotal
  call thetae(pe(k)*1000.,t(k),qv(k),theq(k),td(k))
enddo


!- vertical mass distribution
xx=0.
xxx=0.
k_initial= 0
k_final  = 0
w_thresold = 1.

!- define range of the upper detrainemnt layer
do ko=nkp-10,2,-1
 
 if(w(ko) < w_thresold) cycle
 
 if(k_final==0) k_final=ko
 
 if(w(ko)-1. > w(ko-1)) then
   k_initial=ko
   exit
  endif
  xxx=xxx+mass(ko)
enddo
!print*,'ki kf=',k_initial,k_final

!- if there is a non zero depth layer, make the mass vertical distribution 
if(k_final > 0 .and. k_initial > 0) then 
    
     k_initial=int((k_final+k_initial)*0.5)
    
    
     !- get the normalized mass distribution
     do ko=nkp-10,1,-1
        if(w(ko) < w_thresold) cycle
      
        if(w(ko)-1.0 > w(ko-1)) exit
        xx(ko) = mass(ko)/xxx
     enddo
   
    !v-2.5
    !- parabolic vertical distribution between k_initial and k_final
    xx=0.
    KK4 = k_final-k_initial+2
    do ko=1,kk4-1
      kl=ko+k_initial-1
      xx(kl) = 6.* float(ko)/float(kk4)**2 * (1. - float(ko)/float(kk4))
    enddo
    mass=xx
    !print*,'ki kf=',int(k_initial+k_final)/2,k_final,sum(mass)*100.
    
    !- check if the integral is 1 (normalized)
    if(sum(mass) .ne. 1.) then
 	xxx= ( 1.- sum(mass) )/float(k_final-k_initial+1)
 	do ko=k_initial,k_final
 	  mass(ko) = mass(ko)+ xxx !- values between 0 and 1.
 	enddo
      ! print*,'new mass=',sum(mass)*100.,xxx
      !pause
    endif
    
endif !k_final > 0 .and. k_initial > 


!- vertical mass distribution (horizontally integrated : kg/m)
!mass=3.14*rad_p**2*dne*sc*100.
!mass=mass/sum(mass)


  !
IF(MINTIME == 1) nrec = 0
  !
WRITE (2, 430) MINTIME, DT, TIME  
WRITE (2, 431) ZTOP  
WRITE (2, 380)  
!
! do the print
!
! DO 390 KO = 1, nrectotal, interval  
 DO 390 KO = 1, 200, interval  
                             
   PEA = PE (KO) * 10.       !pressure is stored in decibars(kPa),print in mb;
   BTMP = T (KO) - TMELT     !temps in Celsius
   ETMP = T (KO) - TE (KO)   !temperature excess
   VAP1 = QV (KO)   * 1000.  !printout in g/kg for all water,
   VAP2 = QSAT (KO) * 1000.  !vapor (internal storage is in g/g)
   GPKC = QC (KO)   * 1000.  !cloud water
   GPKH = QH (KO)   * 1000.  !raindrops
   GPKI = QI (KO)   * 1000.  !ice particles 
   DEFICIT = VAP2 - VAP1     !vapor deficit
!
   WRITE (2, 400) zt(KO)/1000., PEA, W (KO), BTMP, ETMP, VAP1, &
    VAP2, GPKC, GPKH, GPKI, rbuoy(KO)*100. !, VTH (KO), SC(KO)

   IF(finalout == 1) then
      WRITE (5, 400) zt(KO)/1000., PEA, W (KO), BTMP, ETMP, VAP1, &
       VAP2, GPKC, GPKH, GPKI, rbuoy(KO)*100., radius(KO)/1000., dwdt_entr(KO), T(KO),TE(KO)
   endif


  !end of printout
   
  390 CONTINUE		  

   nrec=nrec+1
   write (19,rec=nrec) (W (KO), KO=1,nrectotal)
   nrec=nrec+1
   write (19,rec=nrec) (T (KO), KO=1,nrectotal)
   nrec=nrec+1
   write (19,rec=nrec) (TE(KO), KO=1,nrectotal)
   nrec=nrec+1
   write (19,rec=nrec) (QV(KO)*1000., KO=1,nrectotal)
   nrec=nrec+1
   write (19,rec=nrec) ((QC(KO)+QI(ko))*1000., KO=1,nrectotal)
   nrec=nrec+1
   write (19,rec=nrec) (QH(KO)*1000., KO=1,nrectotal)
   nrec=nrec+1
!   write (19,rec=nrec) (rbuoy(KO), KO=1,nrectotal)
   write (19,rec=nrec) (QI(KO)*1000., KO=1,nrectotal)
!   nrec=nrec+1
!   write (19,rec=nrec) (dwdt_entr(KO), KO=1,nrectotal)
!   write (19,rec=nrec) (100.*QV(KO)/QSAT(KO), KO=1,nrectotal)
!   write (19,rec=nrec) (THEE(KO), KO=1,nrectotal)
!   write (19,rec=nrec) (radius(KO), KO=1,nrectotal)
!   nrec=nrec+1
!   write (19,rec=nrec) (QVENV(KO)*1000., KO=1,nrectotal)
!   write (19,rec=nrec) (THEQ(KO), KO=1,nrectotal)
!   write (19,rec=nrec) (upe(KO), KO=1,nrectotal)
!   write (19,rec=nrec) (mass(kO), KO=1,nrectotal)
   nrec=nrec+1
!   write (19,rec=nrec) (tde(KO), KO=1,nrectotal)
   write (19,rec=nrec) (vel_e(KO), KO=1,nrectotal)
   nrec=nrec+1
   write (19,rec=nrec) (vel_p(KO), KO=1,nrectotal) ! Pa
!   write (19,rec=nrec) (rbuoy(KO), KO=1,nrectotal) ! Pa
!   write (19,rec=nrec) (dne(KO), KO=1,nrectotal) ! Pa
!   write (19,rec=nrec) (vt3dh(KO), KO=1,nrectotal) ! Pa
!   write (19,rec=nrec) (pe(KO)*1000., KO=1,nrectotal) ! Pa


!
RETURN  
!
! ************** FORMATS *********************************************
!
!  380 FORMAT(/,' Z(KM) P(MB) W(M/S) T(C)  T-TE   VAP   SAT   QC    QH' &
!'     QI    VTH(MPS) SCAL'/)
  380 FORMAT(/,' Z(KM) P(MB) W(M/S) T(C)  T-TE   QV(g/kg)   SAT(g/kg)   QC(g/kg)    QH(g/kg)' &
'     QI(g/kg) Buoy(1e-2 m/s2)' /)
!
!  380 FORMAT('     Z(km)    P(mbar)    W(m/s)     T(C)      T-TE    QV(g/kg)  SAT(g/kg)  QC(g/kg)  QH(g/kg)  QI(g/kg) Buoy(1e-2 m/s2)')


   400 FORMAT(15F10.4)
!  400 FORMAT(1H , F4.1, F10.4,F-7.4, F6.4, 6F7.4, F7.4,1X, F7.4)  
!
  430 format(i5,' minutes       dt= ',f6.2,' seconds   time= ' &
        ,f8.2,' seconds')
  431 format('    Ztop= ',f10.2, ' meters')  
!
end subroutine printout
!
! *********************************************************************
SUBROUTINE WATERBAL  
!use plumegen_coms  

!
                                        
IF (QC (L) .LE.1.0E-10) QC (L) = 0.  !DEFEAT UNDERFLOW PROBLEM
IF (QH (L) .LE.1.0E-10) QH (L) = 0.  
IF (QI (L) .LE.1.0E-10) QI (L) = 0.  
!
CALL EVAPORATE    !vapor to cloud,cloud to vapor  
                             
CALL SUBLIMATE    !vapor to ice  
                            
CALL GLACIATE     !rain to ice 
                         
CALL MELT         !ice to rain
       
!if(ak1 > 0. .or. ak2 > 0.) &
CALL CONVERT () !(auto)conversion and accretion 
!CALL CONVERT2 () !(auto)conversion and accretion 
!
RETURN  
END SUBROUTINE WATERBAL
! *********************************************************************
SUBROUTINE EVAPORATE  
!
!- evaporates cloud,rain and ice to saturation
!
!use plumegen_coms  
implicit none
!
!     XNO=10.0E06
!     HERC = 1.93*1.E-6*XN035        !evaporation constant
!
real, PARAMETER :: HERC = 5.44E-4, CP = 1.004, HEATCOND = 2.5E3  
real, PARAMETER :: HEATSUBL = 2834., TMELT = 273., TFREEZE = 269.3

real, PARAMETER :: FRC = HEATCOND / CP, SRC = HEATSUBL / CP

real :: evhdt, evidt, evrate, evap, sd,	quant, dividend, divisor, devidt

!
!
SD = QSAT (L) - QV (L)  !vapor deficit
IF (SD.EQ.0.0)  RETURN  
!IF (abs(SD).lt.1.e-7)  RETURN  



EVHDT = 0.  
EVIDT = 0.  
!evrate =0.; evap=0.; sd=0.0; quant=0.0; dividend=0.0; divisor=0.0; devidt=0.0
                                 
EVRATE = ABS (WBAR * DQSDZ)   !evaporation rate (Kessler 8.32)
EVAP = EVRATE * DT   !what we can get in DT
                                  

IF (SD.LE.0.0) THEN  !     condense. SD is negative

   IF (EVAP.GE.ABS (SD) ) THEN    !we get it all
                                  
      QC (L) = QC  (L) - SD  !deficit,remember?
      QV (L) = QSAT(L)       !set the vapor to saturation  
      T  (L) = T   (L) - SD * FRC  !heat gained through condensation
                                   !per gram of dry air
      RETURN  

   ELSE  
                                 
      QC (L) = QC (L) + EVAP         !get what we can in DT 
      QV (L) = QV (L) - EVAP         !remove it from the vapor
      T  (L) = T  (L) + EVAP * FRC   !get some heat

      RETURN  

   ENDIF  
!
ELSE                                !SD is positive, need some water
!
! not saturated. saturate if possible. use everything in order
! cloud, rain, ice. SD is positive
                                         
   IF (EVAP.LE.QC (L) ) THEN        !enough cloud to last DT  
!
                                         
      IF (SD.LE.EVAP) THEN          !enough time to saturate
                                         
         QC (L) = QC (L) - SD       !remove cloud                                          
         QV (L) = QSAT (L)          !saturate
         T (L) = T (L) - SD * FRC   !cool the parcel                                          
         RETURN  !done
!
                                         
      ELSE   !not enough time
                                        
         SD = SD-EVAP               !use what there is
         QV (L) = QV (L) + EVAP     !add vapor
         T (L) = T (L) - EVAP * FRC !lose heat
         QC (L) = QC (L) - EVAP     !lose cloud
	                            !go on to rain.                                      
      ENDIF     
!
   ELSE                !not enough cloud to last DT
!      
      IF (SD.LE.QC (L) ) THEN   !but there is enough to sat
                                          
         QV (L) = QSAT (L)  !use it
         QC (L) = QC (L) - SD  
         T  (L) = T (L) - SD * FRC  
         RETURN  
	                              
      ELSE            !not enough to sat
         SD = SD-QC (L)  
         QV (L) = QV (L) + QC (L)  
         T  (L) = T (L) - QC (L) * FRC         
         QC (L) = 0.0  !all gone
                                          
      ENDIF       !on to rain                          
   ENDIF          !finished with cloud
!
!  but still not saturated, so try to use some rain
!  this is tricky, because we only have time DT to evaporate. if there
!  is enough rain, we can evaporate it for dt. ice can also sublimate
!  at the same time. there is a compromise here.....use rain first, then
!  ice. saturation may not be possible in one DT time.
!  rain evaporation rate (W12),(OT25),(K Table 4). evaporate rain first
!  sd is still positive or we wouldn't be here.
  
  IF (QH (L) .LE.1.E-10) GOTO 33                                  

!srf-25082005
!  QUANT = (QC (L) + QV (L) - QSAT (L) ) * RHO (L)   !g/m**3
   QUANT = ( QSAT (L)-QC (L) - QV (L)  ) * RHO (L)   !g/m**3

!
   EVHDT = (DT * HERC * (QUANT) * (QH (L) * RHO (L) ) **.65) / RHO (L)
!             rain evaporation in time DT
                                      
   IF (EVHDT.LE.QH (L) ) THEN           !enough rain to last DT

      IF (SD.LE.EVHDT) THEN  		!enough time to saturate	  
         QH (L) = QH (L) - SD   	!remove rain	  
         QV (L) = QSAT (L)  		!saturate	  
         T (L) = T (L) - SD * FRC  	!cool the parcel		  
         !if(mintime>40) print*,'1',L,T(L)-273.15,QV(L)*1000,QH(L)*1000
         
	 RETURN  			!done
!                       
      ELSE                               !not enough time

         SD = SD-EVHDT  		 !use what there is
         QV (L) = QV (L) + EVHDT  	 !add vapor
         T (L) = T (L) - EVHDT * FRC  	 !lose heat
         QH (L) = QH (L) - EVHDT  	 !lose rain
         !if(mintime>40.and. L<40) print*,'2',L,T(L)-273.15,QV(L)*1000,QH(L)*1000
         !if(mintime>40.and. L<40) print*,'3',L,EVHDT,QUANT
         !if(mintime>40.and. L<40) print*,'4',L,QC (L)*1000. , QV (L)*1000. , QSAT (L)*1000.
                                        		    
      ENDIF  				  !go on to ice.
!                                    
   ELSE  !not enough rain to last DT
!
      IF (SD.LE.QH (L) ) THEN             !but there is enough to sat
         QV (L) = QSAT (L)                !use it
         QH (L) = QH (L) - SD  
         T (L) = T (L) - SD * FRC  
         RETURN  
!                            
      ELSE                              !not enough to sat
         SD = SD-QH (L)  
         QV (L) = QV (L) + QH (L)  
         T (L) = T (L) - QH (L) * FRC    
         QH (L) = 0.0                   !all gone
                                          
      ENDIF                             !on to ice
!
                                          
   ENDIF                                !finished with rain
!
!
!  now for ice
!  equation from (OT); correction factors for units applied
!
   33    continue

   IF (QI (L) .LE.1.E-10) RETURN            !no ice there
!
   DIVIDEND = ( (1.E6 / RHO (L) ) **0.475) * (SD / QSAT (L) &
            - 1) * (QI (L) **0.525) * 1.13
   DIVISOR = 7.E5 + 4.1E6 / (10. * EST (L) )  
                                                 
   DEVIDT = - CVI(L) * DIVIDEND / DIVISOR   !rate of change
                                                  
   EVIDT = DEVIDT * DT                      !what we could get
!
! logic here is identical to rain. could get fancy and make subroutine
! but duplication of code is easier. God bless the screen editor.
!
                                         
   IF (EVIDT.LE.QI (L) ) THEN             !enough ice to last DT
!
                                         
      IF (SD.LE.EVIDT) THEN  		  !enough time to saturate
         QI (L) = QI (L) - SD   	  !remove ice
         QV (L) = QSAT (L)  		  !saturate
         T (L) = T (L) - SD * SRC  	  !cool the parcel

         RETURN  			  !done
!
                                          
      ELSE                                !not enough time
                                          
         SD = SD-EVIDT  		  !use what there is
         QV (L) = QV (L) + EVIDT  	  !add vapor
          T (L) =  T (L) - EVIDT * SRC  	  !lose heat
         QI (L) = QI (L) - EVIDT  	  !lose ice
                                          
      ENDIF  				  !go on,unsatisfied
!                                          
   ELSE                                   !not enough ice to last DT
!                                         
      IF (SD.LE.QI (L) ) THEN             !but there is enough to sat
                                          
         QV (L) = QSAT (L)                !use it
         QI (L) = QI   (L) - SD  
          T (L) =  T   (L) - SD * SRC  
	  
         RETURN  
!
      ELSE                                 !not enough to sat
         SD = SD-QI (L)  
         QV (L) = QV (L) + QI (L)  
         T (L) = T (L) - QI (L) * SRC             
         QI (L) = 0.0                      !all gone

      ENDIF                                !on to better things
                                           !finished with ice
   ENDIF  
!                                 
ENDIF                                      !finished with the SD decision
!
RETURN  
!
END SUBROUTINE EVAPORATE
!
! *********************************************************************
SUBROUTINE CONVERT ()  
!
!- ACCRETION AND AUTOCONVERSION
!
!use plumegen_coms
!
real,      PARAMETER ::  AK1 = 0.001    !conversion rate constant
real,      PARAMETER ::  AK2 = 0.0052   !collection (accretion) rate
real,      PARAMETER ::  TH  = 0.5      !Kessler threshold
integer,   PARAMETER ::iconv = 1        !Kessler conversion
                                      
!real, parameter :: ANBASE =  50.!*1.e+6 !Berry-number at cloud base #/m^3(maritime)
 real, parameter :: ANBASE =100000.!*1.e+6 !Berry-number at cloud base #/m^3(continental)
! na formulacao abaixo use o valor em #/cm^3  
!real, parameter :: BDISP = 0.366       !Berry--size dispersion (maritime)
 real, parameter :: BDISP = 0.146       !Berry--size dispersion (continental)
real, parameter :: TFREEZE = 269.3  !ice formation temperature
!
real ::   accrete, con, q, h, bc1,   bc2,  total

!     selection rules
!                         

IF (T (L)  .LE. TFREEZE) RETURN  !process not allowed above ice
!
IF (QC (L) .EQ. 0.     ) RETURN  
!srf IF (QC (L) .lt. 1.e-3     ) RETURN  

ACCRETE = 0.  
CON = 0.  
Q = RHO (L) * QC (L)  
H = RHO (L) * QH (L)  
!
!            
IF (QH (L) .GT. 0.     ) ACCRETE = AK2 * Q * (H**.875)  !accretion, Kessler
!
IF (ICONV.NE.0) THEN   !select Berry or Kessler
!
!old   BC1 = 120.  
!old   BC2 = .0266 * ANBASE * 60.  
!old   CON = BDISP * Q * Q * Q / (BC1 * Q * BDISP + BC2) 	  

   CON = Q*Q*Q*BDISP/(60.*(5.*Q*BDISP+0.0366*ANBASE))
!
ELSE  
!                             
!   CON = AK1 * (Q - TH)   !Kessler autoconversion rate
!      
!   IF (CON.LT.0.0) CON = 0.0   !havent reached threshold
 
   CON = max(0.,AK1 * (Q - TH)) ! versao otimizada
!
ENDIF  
!
!

TOTAL = (CON + ACCRETE) * DT / RHO (L)  
!
IF (TOTAL.LT.QC (L) ) THEN  
!
   QC (L) = QC (L) - TOTAL  
   QH (L) = QH (L) + TOTAL    !no phase change involved
   RETURN  
!
ELSE  
!              
   QH (L) = QH (L) + QC (L)    !uses all there is
   QC (L) = 0.0  
!
ENDIF  
!
RETURN  
!
END SUBROUTINE CONVERT
!
!**********************************************************************
!
SUBROUTINE CONVERT2 ()  
!use plumegen_coms  
implicit none
LOGICAL  AEROSOL
parameter(AEROSOL=.true.)
!
real, parameter :: TNULL=273.16, LAT=2.5008E6 &
                  ,EPSI=0.622 ,DB=1. ,NB=1500. !ALPHA=0.2 
real :: KA,KEINS,KZWEI,KDREI,VT	
real :: A,B,C,D, CON,ACCRETE,total 
      
real Y(6),ROH
      
A=0.
B=0.
Y(1) = T(L)
Y(4) = W(L)
y(2) = QC(L)
y(3) = QH(L)
Y(5) = RADIUS(L)
ROH =  RHO(L)*1.e-3 ! dens (MKS) ??


! autoconversion

KA = 0.0005 
IF( Y(1) .LT. 258.15 )THEN
!   KEINS=0.00075
    KEINS=0.0009 
    KZWEI=0.0052
    KDREI=15.39
ELSE
    KEINS=0.0015
    KZWEI=0.00696
    KDREI=11.58
ENDIF
      
!   ROH=PE/RD/TE
VT=-KDREI* (Y(3)/ROH)**0.125

 
IF (Y(4).GT.0.0 ) THEN
 IF (AEROSOL) THEN
   A = 1/y(4)  *  y(2)*y(2)*1000./( 60. *( 5. + 0.0366*NB/(y(2)*1000.*DB) )  )
 ELSE
   IF (y(2).GT.(KA*ROH)) THEN
   !print*,'1',y(2),KA*ROH
   A = KEINS/y(4) *(y(2) - KA*ROH )
   ENDIF
 ENDIF
ELSE
   A = 0.0
ENDIF

! accretion

IF(y(4).GT.0.0) THEN
   B = KZWEI/(y(4) - VT) * MAX(0.,y(2)) *   &
       MAX(0.001,ROH)**(-0.875)*(MAX(0.,y(3)))**(0.875)
ELSE
   B = 0.0
ENDIF
   
   
      !PSATW=610.7*EXP( 17.25 *( Y(1) - TNULL )/( Y(1)-36. ) )
      !PSATE=610.7*EXP( 22.33 *( Y(1) - TNULL )/( Y(1)- 2. ) )

      !QSATW=EPSI*PSATW/( PE-(1.-EPSI)*PSATW )
      !QSATE=EPSI*PSATE/( PE-(1.-EPSI)*PSATE )
      
      !MU=2.*ALPHA/Y(5)

      !C = MU*( ROH*QSATW - ROH*QVE + y(2) )
      !D = ROH*LAT*QSATW*EPSI/Y1/Y1/RD *DYDX1

      
      !DYDX(2) = - A - B - C - D  ! d rc/dz
      !DYDX(3) = A + B            ! d rh/dz
 
 
      ! rc=rc+dydx(2)*dz
      ! rh=rh+dydx(3)*dz
 
CON      = A
ACCRETE  = B



!!!!
 
TOTAL = (CON + ACCRETE) *(1/DZM(L))    ! DT / RHO (L)  

!print*,'L=',L,total,QC(L),dzm(l)

!
IF (TOTAL.LT.QC (L) ) THEN  
!
   QC (L) = QC (L) - TOTAL  
   QH (L) = QH (L) + TOTAL    !no phase change involved
   RETURN  
!
ELSE  
!              
   QH (L) = QH (L) + QC (L)    !uses all there is
   QC (L) = 0.0  
!
ENDIF  
!
RETURN  
!
END SUBROUTINE CONVERT2
! ice - effect on temperature
!      TTD = 0.0 
!      TTE = 0.0  
!       CALL ICE(QSATW,QSATE,Y(1),Y(2),Y(3), &
!               TTA,TTB,TTC,DZ,ROH,D,C,TTD,TTE)
!       DYDX(1) = DYDX(1) + TTD  + TTE ! DT/DZ on Temp
!
!**********************************************************************
!
SUBROUTINE SUBLIMATE  
!
! ********************* VAPOR TO ICE (USE EQUATION OT22)***************
!use plumegen_coms  
!
real, PARAMETER :: EPS = 0.622, HEATFUS = 334., HEATSUBL = 2834., CP = 1.004
real, PARAMETER :: SRC = HEATSUBL / CP, FRC = HEATFUS / CP, TMELT = 273.3
real, PARAMETER :: TFREEZE = 269.3

real ::dtsubh,  dividend,divisor, subl
!
DTSUBH = 0.  
!
!selection criteria for sublimation
IF (T (L)  .GT. TFREEZE  ) RETURN  
IF (QV (L) .LE. QSAT (L) ) RETURN  
!
!     from (OT); correction factors for units applied
!
 DIVIDEND = ( (1.E6 / RHO (L) ) **0.475) * (QV (L) / QSAT (L) &
            - 1) * (QI (L) **0.525) * 1.13
 DIVISOR = 7.E5 + 4.1E6 / (10. * EST (L) )  
!
                                         
 DTSUBH = ABS (DIVIDEND / DIVISOR)   !sublimation rate
 SUBL = DTSUBH * DT                  !and amount possible
!
!     again check the possibilities
!
IF (SUBL.LT.QV (L) ) THEN  
!
   QV (L) = QV (L) - SUBL             !lose vapor
   QI (L) = QI (L) + SUBL  	      !gain ice
   T (L) = T (L) + SUBL * SRC         !energy change, warms air

	 !print*,'5',l,qi(l),SUBL

   RETURN  
!
ELSE  
!                                     
   QI (L) = QV (L)                    !use what there is
   T  (L) = T (L) + QV (L) * SRC      !warm the air
   QV (L) = 0.0  
	 !print*,'6',l,qi(l)
!
ENDIF  
!
RETURN  
END SUBROUTINE SUBLIMATE
!
! *********************************************************************
!
SUBROUTINE GLACIATE  
!
! *********************** CONVERSION OF RAIN TO ICE *******************
!     uses equation OT 16, simplest. correction from W not applied, but
!     vapor pressure differences are supplied.
!
!use plumegen_coms  
!
real, PARAMETER :: HEATFUS = 334., CP = 1.004, EPS = 0.622, HEATSUBL = 2834.
real, PARAMETER :: FRC = HEATFUS / CP, FRS = HEATSUBL / CP, TFREEZE =  269.3
real, PARAMETER :: GLCONST = 0.025   !glaciation time constant, 1/sec
real dfrzh
!
                                    
 DFRZH = 0.    !rate of mass gain in ice
!
!selection rules for glaciation
IF (QH (L) .LE. 0.       ) RETURN  
IF (QV (L) .LT. QSAT (L) ) RETURN                                        
IF (T  (L) .GT. TFREEZE  ) RETURN  
!
!      NT=TMELT-T(L)
!      IF (NT.GT.50) NT=50
!
                                    
 DFRZH = DT * GLCONST * QH (L)    ! from OT(16)
!
IF (DFRZH.LT.QH (L) ) THEN  
!
   QI (L) = QI (L) + DFRZH  
   QH (L) = QH (L) - DFRZH  
   T (L) = T (L) + FRC * DFRZH  !warms air
   
   	 !print*,'7',l,qi(l),DFRZH

   
   RETURN  
!
ELSE  
!
   QI (L) = QI (L) + QH (L)  
   T  (L) = T  (L) + FRC * QH (L)  
   QH (L) = 0.0  

 !print*,'8',l,qi(l), QH (L)  
!
ENDIF  
!
RETURN  
!
END SUBROUTINE GLACIATE
!
!
! *********************************************************************
SUBROUTINE MELT  
!
! ******************* MAKES WATER OUT OF ICE **************************
!use plumegen_coms  
!                                              
real, PARAMETER :: FRC = 332.27, TMELT = 273., F0 = 0.75   !ice velocity factor
real DTMELT
!                                    
 DTMELT = 0.   !conversion,ice to rain
!
!selection rules
IF (QI (L) .LE. 0.0  ) RETURN  
IF (T (L)  .LT. TMELT) RETURN  
!
                                                      !OT(23,24)
 DTMELT = DT * (2.27 / RHO (L) ) * CVI(L) * (T (L) - TMELT) * ( (RHO(L)  &
         * QI (L) * 1.E-6) **0.525) * (F0** ( - 0.42) )
                                                      !after Mason,1956
!
!     check the possibilities
!
IF (DTMELT.LT.QI (L) ) THEN  
!
   QH (L) = QH (L) + DTMELT  
   QI (L) = QI (L) - DTMELT  
   T  (L) = T (L) - FRC * DTMELT     !cools air
   	 !print*,'9',l,qi(l),DTMELT

   
   RETURN  
!
ELSE  
!
   QH (L) = QH (L) + QI (L)   !get all there is to get
   T  (L) = T (L) - FRC * QI (L)  
   QI (L) = 0.0  
   	 !print*,'10',l,qi(l)
!
ENDIF  
!
RETURN  
!
END SUBROUTINE MELT
!-----------------------------------------------------------------------------
FUNCTION ESAT_PR (TEM)  
!
! ******* Vapor Pressure  A.L. Buck JAM V.20 p.1527. (1981) ***********
!
real, PARAMETER :: CI1 = 6.1115, CI2 = 22.542, CI3 = 273.48
real, PARAMETER :: CW1 = 6.1121, CW2 = 18.729, CW3 = 257.87, CW4 = 227.3
real, PARAMETER :: TMELT = 273.3

real ESAT_PR,temc , tem,esatm
!
!     formulae from Buck, A.L., JAM 20,1527-1532
!     custom takes esat wrt water always. formula for h2o only
!     good to -40C so:
!
!
TEMC = TEM - TMELT  
IF (TEMC.GT. - 40.0) GOTO 230  
ESATM = CI1 * EXP (CI2 * TEMC / (TEMC + CI3) )  !ice, millibars  
ESAT_PR = ESATM / 10.	!kPa			  

RETURN  
!
230 ESATM = CW1 * EXP ( ( (CW2 - (TEMC / CW4) ) * TEMC) / (TEMC + CW3))
                          
ESAT_PR = ESATM / 10.	!kPa			  
RETURN  
END function ESAT_PR

subroutine zero_plumegen_coms
!use plumegen_coms
implicit none
w=0.0;t=0.0;td=0.;theq=0.
qv=0.0;qc=0.0;qh=0.0;qi=0.0;sc=0.0;vel_p=0.;rad_p=0.;rad_t=0.
vth=0.0;vti=0.0;rho=0.0;txs=0.0
vt3dc=0.;vt3df=0.;vt3dk=0.;vt3dg=0.;scr1=0.;vt3dj=0.;vt3dn=0.;vt3do=0.
vt3da=0.;scr2=0.;vt3db=0.;vt3dd=0.;vt3dl=0.;vt3dm=0.;vt3di=0.;vt3dh=0.;vt3de=0.
wc=0.0;wt=0.0;tt=0.0;qvt=0.0;qct=0.0;qht=0.0;qit=0.0;sct=0.0;vel_t=0.
est=0.0;qsat=0.0;qpas=0.0;qtotal=0.0
dzm=0.0;dzt=0.0;zm=0.0;zt=0.0;vctr1=0.0;vctr2=0.0
vel_e=0.
pke=0.0;the=0.0;thve=0.0;thee=0.0;pe=0.0;te=0.0;qvenv=0.0;rhe=0.0;dne=0.0;sce=0.0;upe=0.;vpe=0.
ucon=0.0;vcon=0.0;wcon=0.0;thtcon =0.0;rvcon=0.0;picon=0.0;tmpcon=0.0;dncon=0.0;prcon=0.0 
zcon=0.0;zzcon=0.0;scon=0.0 
dz=0.0;dqsdz=0.0;visc=0.0;viscosity=0.0;tstpf=0.0
advw=0.0;advt=0.0;advv=0.0;advc=0.0;advh=0.0;advi=0.0;cvh=0.0;cvi=0.0;adiabat=0.0
wbar=0.0;alast=0.0;vhrel=0.0;virel=0.0  
zsurf=0.0;zbase=0.0;ztop=0.0;area=0.0;rsurf=0.0;alpha=0.0;radius=0.0;heating=0.0
fmoist=0.0;bload=0.0;dt=0.0;time=0.0;tdur=0.0
ztop_=0.0
n=0;nm1=0;l=0;lbase=0;mintime=0;mdur=0;maxtime=0
dwdt_entr=0.
end subroutine zero_plumegen_coms
!     ******************************************************************

subroutine thetae(p,t,rv,the,tdd)
implicit none
real :: p,t,rv,the,tdd

real, parameter :: cp=1004.,g=9.8,r=287.,alvl=2.35e6,cpg=cp/g
real :: pit,tupo,ttd,dz,tupn,tmn
integer :: itter
!real, external :: td

pit=p
tupo=t
ttd=ftd(p,rv)
tdd=ttd
dz=cpg*(t-ttd)
if(dz.le.0.) goto 20
do itter=1,50
   tupn=t-g/cp*dz
   tmn=(tupn+t)*.5*(1.+.61*rv)
   pit=p*exp(-g*dz/(r*tmn))
   if(abs(tupn-tupo).lt.0.001) goto 20
   ttd=ftd(pit,rv)
   tupo=tupn
   dz=dz+cpg*(tupn-ttd)
enddo
stop 'stop: problems with thetae calculation'
20 continue
the=tupo*(1e5/pit)**.286*exp(alvl*rv/(cp*tupo))

return
end subroutine thetae
!     ******************************************************************

real function ftd(p,rs)

implicit none
real :: rr,rs,es,esln,p

rr=rs+1e-8
es=p*rr/(.622+rr)
esln=log(es)
ftd=(35.86*esln-4947.2325)/(esln-23.6837)

return
end function ftd
!     ******************************************************************

SUBROUTINE htint (nzz1, vctra, eleva, nzz2, vctrb, elevb)
  IMPLICIT NONE
  INTEGER, INTENT(IN ) :: nzz1
  INTEGER, INTENT(IN ) :: nzz2
  REAL,    INTENT(IN ) :: vctra(nzz1)
  REAL,    INTENT(OUT) :: vctrb(nzz2)
  REAL,    INTENT(IN ) :: eleva(nzz1)
  REAL,    INTENT(IN ) :: elevb(nzz2)

  INTEGER :: l
  INTEGER :: k
  INTEGER :: kk
  REAL    :: wt

  l=1

  DO k=1,nzz2
     DO
        IF ( (elevb(k) <  eleva(1)) .OR. &
             ((elevb(k) >= eleva(l)) .AND. (elevb(k) <= eleva(l+1))) ) THEN
           wt       = (elevb(k)-eleva(l))/(eleva(l+1)-eleva(l))
           vctrb(k) = vctra(l)+(vctra(l+1)-vctra(l))*wt
           EXIT
        ELSE IF ( elevb(k) >  eleva(nzz1))  THEN
           wt       = (elevb(k)-eleva(nzz1))/(eleva(nzz1-1)-eleva(nzz1))
           vctrb(k) = vctra(nzz1)+(vctra(nzz1-1)-vctra(nzz1))*wt
           EXIT
        END IF

        l=l+1
        IF(l == nzz1) THEN
           PRINT *,'htint:nzz1',nzz1
           DO kk=1,l
              PRINT*,'kk,eleva(kk),elevb(kk)',eleva(kk),elevb(kk)
           END DO
           STOP 'htint'
        END IF
     END DO
  END DO
END SUBROUTINE htint
!      ------------------------------------------------------------------------

subroutine mrsl(n1,p,t,rsl)

implicit none
integer :: n,n1
real :: rsl(n1),p(n1),t(n1)

do n=1,n1
   rsl(n)=rslf(p(n),t(n))
enddo

return
end subroutine mrsl

!     ******************************************************************

subroutine mrsi(n1,p,t,rsi)

implicit none
integer :: n,n1
real :: rsi(n1),p(n1),t(n1)

do n=1,n1
   rsi(n)=rsif(p(n),t(n))
enddo

return
end subroutine mrsi

!     ******************************************************************

END MODULE smk_plumerise


