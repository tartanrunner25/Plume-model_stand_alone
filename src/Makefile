PLUME=./

#What compiler do we want to use? Currently supports nvidia, gfortran, and intel
#F_COMP=nvfortran               #nvidia compiler
F_COMP=gfortran                 #gfortran compiler
#F_COMP=ifort                   #intel compiler

#What are our compiler options?
#F_OPTS=-O2 -g
F_OPTS=-O3 -g
#F_OPTS=-O3 -Munroll=c:1 -Mnoframe -mcmodel=medium -Mlarge_arrays -Mlre -Mvect=cachesize:1048576,sse,prefetch \

LOADER=${F_COMP} 
LOADER_OPTS= -v 

LIBS=

ARCHIVE=ar r

# Compiler commands.
F_COMMAND = $(F_COMP) -c $(F_OPTS)

# Define archive and executable names.
BASE=plume_alone_module
EXE=$(BASE)
ARC=$(BASE).a

# Define source.
F_SRC = \
	$(PLUME)/plume_alone_module.f90\
	$(PLUME)/run_plume_model.f90 


# Define targets.
all: $(EXE)

$(EXE): $(ARC) 
	$(LOADER) -o $(EXE) $(LOADER_OPTS) $(ARC) 
###	ln -fs $(EXE) $(BASE)
	rm -f *.o core.*

$(ARC): $(F_SRC)
	$(F_COMMAND) $(?)
	$(ARCHIVE) $(ARC) *.o
#	$(F_COMMAND) 
#	rm -f *.o core.*


install:
#	ln -fs `pwd`/$(EXE) ../run/$(BASE)
#	ln -fs `pwd`/$(EXE) ../test/$(BASE)

clean:
	rm -f $(ARC) $(EXE) $(BASE) *.o  ___* core* *.mod
