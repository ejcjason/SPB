/*
 * $Id: gmx_trjconv.c,v 1.4.2.8 2008/02/29 07:02:59 spoel Exp $
 * 
 *                This source code is part of
 * 
 *                 G   R   O   M   A   C   S
 * 
 *          GROningen MAchine for Chemical Simulations
 * 
 *                        VERSION 3.3.3
 * Written by David van der Spoel, Erik Lindahl, Berk Hess, and others.
 * Copyright (c) 1991-2000, University of Groningen, The Netherlands.
 * Copyright (c) 2001-2008, The GROMACS development team,
 * check out http://www.gromacs.org for more information.

 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License
 * as published by the Free Software Foundation; either version 2
 * of the License, or (at your option) any later version.
 * 
 * If you want to redistribute modifications, please consider that
 * scientific software is very special. Version control is crucial -
 * bugs must be traceable. We will be happy to consider code for
 * inclusion in the official distribution, but derived work must not
 * be called official GROMACS. Details are found in the README & COPYING
 * files - if they are missing, get the official version at www.gromacs.org.
 * 
 * To help us fund GROMACS development, we humbly ask that you cite
 * the papers on the package - you can find them in the top README file.
 * 
 * For more info, check our website at http://www.gromacs.org
 * 
 * And Hey:
 * Groningen Machine for Chemical Simulation
 */
#ifdef HAVE_CONFIG_H
#include <config.h>
#endif

#include <string.h>
#include <math.h>
#include "macros.h"
#include "assert.h"
#include "sysstuff.h"
#include "smalloc.h"
#include "typedefs.h"
#include "copyrite.h"
#include "gmxfio.h"
#include "tpxio.h"
#include "trnio.h"
#include "statutil.h"
#include "futil.h"
#include "pdbio.h"
#include "confio.h"
#include "names.h"
#include "index.h"
#include "vec.h"
#include "xtcio.h"
#include "do_fit.h"
#include "rmpbc.h"
#include "wgms.h"
#include "magic.h"
#include "pbc.h"
#include "viewit.h"
#include "xvgr.h"

enum { euSel,euRect, euTric, euCompact, euNR};

static real calc_isquared(int nmol,rvec m_com[],rvec m_shift[],rvec clust_com)
{
  real Isq=0;
  int  i;
  rvec m0,dx;
  
  for(i=0; (i<nmol); i++) {
    rvec_add(m_com[i],m_shift[i],m0);
    rvec_sub(m0,clust_com,dx);
    Isq += iprod(dx,dx);
  }
  return Isq;
}

static void calc_pbc_cluster(int ecenter,int nrefat,t_topology *top,rvec x[],
			     atom_id index[],
			     rvec clust_com,matrix box)
{
  const   real tol=1e-3;
  bool    bChanged;
  int     m,i,j,j0,j1,jj,ai,iter,is;
  real    fac,Isq,min_dist2;
  rvec    dx,ddx,xtest,xrm,box_center;
  int     nmol,nmol_cl,imol_center;
  atom_id *molind,*mola;
  bool    *bMol,*bTmp;
  rvec    *m_com,*m_shift,m0;
  t_pbc   pbc;

  calc_box_center(ecenter,box,box_center);
  
  /* Initiate the pbc structure */
  memset(&pbc,0,sizeof(pbc));
  set_pbc(&pbc,box);
    
  /* Convert atom index to molecular */
  nmol   = top->blocks[ebMOLS].nr;
  molind = top->blocks[ebMOLS].index;
  mola   = top->blocks[ebMOLS].a;
  snew(bMol,nmol);
  snew(m_com,nmol);
  snew(m_shift,nmol);
  snew(bTmp,top->atoms.nr);
  nmol_cl = 0;
  for(i=0; (i<nrefat); i++) {
    /* Mark all molecules in the index */
    ai = index[i];
    bTmp[ai] = TRUE;
    /* Binary search assuming the molecules are sorted */
    j0=0;
    j1=nmol-1;
    while (j0 < j1) {
      if (ai < mola[molind[j0+1]]) 
	j1 = j0;
      else if (ai >= mola[molind[j1]]) 
	j0 = j1;
      else {
	jj = (j0+j1)/2;
	if (ai < mola[molind[jj+1]]) 
	  j1 = jj;
	else
	  j0 = jj;
      }
    }
    bMol[j0] = TRUE;
  }
  /* Double check whether all atoms in all molecules that are marked are part 
   * of the cluster. Simultaneously compute the center of geometry.
   */
  min_dist2   = 10*sqr(trace(box));
  imol_center = -1;
  for(i=0; (i<nmol); i++) {
    for(j=molind[i]; (j<molind[i+1]); j++) {
      if (bMol[i] && !bTmp[mola[j]])
	gmx_fatal(FARGS,"Molecule %d marked for clustering but not atom %d",
		  i,mola[j]);
      else if (!bMol[i] && bTmp[mola[j]])
	gmx_fatal(FARGS,"Atom %d marked for clustering but not molecule %d",
		  mola[j],i);
      else if (bMol[i]) {
	/* Compute center of geometry of molecule */
	rvec_inc(m_com[i],x[mola[j]]);
      }
    }
    if (bMol[i]) {
      /* Normalize center of geometry */
      fac = 1.0/(molind[i+1]-molind[i]);
      for(m=0; (m<DIM); m++) 
	m_com[i][m] *= fac;
      /* Determine which molecule is closest to the center of the box */
      pbc_dx(&pbc,box_center,m_com[i],dx);
      if (iprod(dx,dx) < min_dist2) {
	min_dist2   = iprod(dx,dx);
	imol_center = i;
      }
      nmol_cl++;
    }
  }
  sfree(bTmp);

  if (nmol_cl <= 0) {
    fprintf(stderr,"No molecules selected in the cluster\n");
    return;
  } else if (imol_center == -1) {
    fprintf(stderr,"No central molecules could be found\n");
    return;
  }
  
  
  /* First calculation is incremental */
  clear_rvec(clust_com);
  Isq = 0;
  for(i=m=0; (i<nmol); i++) {
    /* Check whether this molecule is part of the cluster */
    if (bMol[i]) {
      if ((i > 0) && (m > 0)) {
	/* Compute center of cluster by dividing by number of molecules */
	svmul(1.0/m,clust_com,xrm);
	/* Distance vector between molecular COM and cluster */
	pbc_dx(&pbc,m_com[i],xrm,dx);
	rvec_add(xrm,dx,xtest);
	/* xtest is now the image of m_com[i] that is closest to clust_com */
	rvec_inc(clust_com,xtest);
	rvec_sub(xtest,m_com[i],m_shift[i]);
      }
      else {
	rvec_inc(clust_com,m_com[i]);
      }
      m++;
    }
  }
  assert(m == nmol_cl);
  svmul(1/nmol_cl,clust_com,clust_com);
  put_atom_in_box(box,clust_com);

  /* Now check if any molecule is more than half the box from the COM */
  if (box) {
    iter = 0;
    do {
      bChanged = FALSE;
      for(i=0; (i<nmol) && !bChanged; i++) {
	if (bMol[i]) {
	  /* Sum com and shift from com */
	  rvec_add(m_com[i],m_shift[i],m0);
	  pbc_dx(&pbc,m0,clust_com,dx);
	  rvec_add(clust_com,dx,xtest);
	  rvec_sub(xtest,m0,ddx);
	  if (iprod(ddx,ddx) > tol) {
	    /* Here we have used the wrong image for contributing to the COM */
	    rvec_sub(xtest,m_com[i],m_shift[i]);
	    for(j=0; (j<DIM); j++) 
	      clust_com[j] += (xtest[j]-m0[j])/nmol_cl;
	    bChanged = TRUE;
	  }
	}
      }
      Isq = calc_isquared(nmol,m_com,m_shift,clust_com);
      put_atom_in_box(box,clust_com);

      if (bChanged && (iter > 0))
	printf("COM: %8.3f  %8.3f  %8.3f  iter = %d  Isq = %8.3f\n",
	       clust_com[XX],clust_com[YY],clust_com[ZZ],iter,Isq);
      iter++;
    } while (bChanged);
  }
  /* Now transfer the shift to all atoms in the molecule */
  for(i=0; (i<nmol); i++) {
    if (bMol[i]) {
      for(j=molind[i]; (j<molind[i+1]); j++)
	rvec_inc(x[mola[j]],m_shift[i]);
    }
  }
  sfree(bMol);
  sfree(m_com);
  sfree(m_shift);
}

static void put_molecule_com_in_box(int unitcell_enum,int ecenter,
				    t_block *mols,
				    int natoms,t_atom atom[],
				    matrix box,rvec x[])
{
  atom_id i,j;
  int     d;
  rvec    com,new_com,shift,dx,box_center;
  real    m;
  double  mtot;
  t_pbc   pbc;
  
  calc_box_center(ecenter,box,box_center);
  set_pbc(&pbc,box);
  
  for(i=0; (i<mols->nr); i++) {
    /* calc COM */
    clear_rvec(com);
    mtot = 0;
    for(j=mols->index[i]; (j<mols->index[i+1] && j<natoms); j++) {
      m = atom[j].m;
      for(d=0; d<DIM; d++)
	com[d] += m*x[j][d];
      mtot += m;
    }
    /* calculate final COM */
    svmul(1.0/mtot, com, com);
      
    /* check if COM is outside box */
    copy_rvec(com,new_com);
    switch (unitcell_enum) {
    case euRect: 
      put_atoms_in_box(box,1,&new_com);
      break;
    case euTric: 
      put_atoms_in_triclinic_unitcell(ecenter,box,1,&new_com);
      break;
    case euCompact:
      put_atoms_in_compact_unitcell(ecenter,box,1,&new_com);
      break;
    }
    rvec_sub(new_com,com,shift);
    if (norm2(shift) > 0) {
      if (debug)
	fprintf (debug,"\nShifting position of molecule %d "
		 "by %8.3f  %8.3f  %8.3f\n", i+1, PR_VEC(shift));
      for(j=mols->index[i]; (j<mols->index[i+1] && j<natoms); j++) {
	rvec_inc(x[j],shift);
      }
    }
  }
}

static void put_residue_com_in_box(int unitcell_enum,int ecenter,
				   int natoms,t_atom atom[],
				   matrix box,rvec x[])
{
  atom_id i, j, res_start, res_end, res_nat;
  int     d, presnr;
  real    m;
  double  mtot;
  rvec    box_center,com,new_com,shift;

  calc_box_center(ecenter,box,box_center);
  
  presnr = NOTSET;
  res_start = 0;
  clear_rvec(com);
  mtot = 0;
  for(i=0; i<natoms+1; i++) {
    if (i == natoms || (presnr != atom[i].resnr && presnr != NOTSET)) {
      /* calculate final COM */
      res_end = i;
      res_nat = res_end - res_start;
      svmul(1.0/mtot, com, com);
      
      /* check if COM is outside box */
      copy_rvec(com,new_com);
      switch (unitcell_enum) {
      case euRect: 
	put_atoms_in_box(box,1,&new_com);
	break;
      case euTric: 
	put_atoms_in_triclinic_unitcell(ecenter,box,1,&new_com);
	break;
      case euCompact:
	put_atoms_in_compact_unitcell(ecenter,box,1,&new_com);
	break;
      }
      rvec_sub(new_com,com,shift);
      if (norm2(shift)) {
	if (debug)
	  fprintf (debug,"\nShifting position of residue %d (atoms %u-%u) "
		   "by %g,%g,%g\n", atom[res_start].resnr+1, 
		   res_start+1, res_end+1, PR_VEC(shift));
	for(j=res_start; j<res_end; j++)
	  rvec_inc(x[j],shift);
      }
      clear_rvec(com);
      mtot = 0;

      /* remember start of new residue */
      res_start = i;
    }
    if (i < natoms) {
      /* calc COM */
      m = atom[i].m;
      for(d=0; d<DIM; d++)
	com[d] += m*x[i][d];
      mtot += m;

      presnr = atom[i].resnr;
    }
  }
}

static void center_x(int ecenter,rvec x[],matrix box,int n,int nc,atom_id ci[])
{
  int i,m,ai;
  rvec cmin,cmax,box_center,dx;

  if (nc > 0) {
    copy_rvec(x[ci[0]],cmin);
    copy_rvec(x[ci[0]],cmax);
    for(i=0; i<nc; i++) {
      ai=ci[i];
      for(m=0; m<DIM; m++) {
	if (x[ai][m] < cmin[m])
	  cmin[m]=x[ai][m];
	else if (x[ai][m] > cmax[m])
	  cmax[m]=x[ai][m];
      }
    }
    calc_box_center(ecenter,box,box_center);
    for(m=0; m<DIM; m++)
      dx[m] = box_center[m]-(cmin[m]+cmax[m])*0.5;
      
    for(i=0; i<n; i++)
      rvec_inc(x[i],dx);
  }
}


void check_trn(char *fn)
{
  if ((fn2ftp(fn) != efTRJ)  && (fn2ftp(fn) != efTRR))
    gmx_fatal(FARGS,"%s is not a trj file, exiting\n",fn);
}

#if (!defined WIN32 && !defined _WIN32 && !defined WIN64 && !defined _WIN64)
void do_trunc(char *fn, real t0)
{
  int          in;
  FILE         *fp;
  bool         bStop,bOK;
  t_trnheader  sh;
  off_t        fpos;
  char         yesno[256];
  int          j;
  real         t=0;
  
  if (t0 == -1)
    gmx_fatal(FARGS,"You forgot to set the truncation time");
  
  /* Check whether this is a .trj file */
  check_trn(fn);
  
  in   = open_trn(fn,"r");
  fp   = fio_getfp(in);
  if (fp == NULL) {
    fprintf(stderr,"Sorry, can not trunc %s, truncation of this filetype is not supported\n",fn);
    close_trn(in);
  } else {
    j    = 0;
    fpos = fio_ftell(in);
    bStop= FALSE;
    while (!bStop && fread_trnheader(in,&sh,&bOK)) {
      fread_htrn(in,&sh,NULL,NULL,NULL,NULL);
      fpos=ftell(fp);
      t=sh.t;
      if (t>=t0) {
#ifdef HAVE_FSEEKO	
	fseeko(fp,fpos,SEEK_SET);
#else
	fseek(fp,fpos,SEEK_SET);
#endif	
	bStop=TRUE;
      }
    }
    if (bStop) {
      fprintf(stderr,"Do you REALLY want to truncate this trajectory (%s) at:\n"
	      "frame %d, time %g, bytes %ld ??? (type YES if so)\n",
	      fn,j,t,(long int)fpos);
      scanf("%s",yesno);
      if (strcmp(yesno,"YES") == 0) {
	fprintf(stderr,"Once again, I'm gonna DO this...\n");
	close_trn(in);
	truncate(fn,fpos);
      }
      else {
	fprintf(stderr,"Ok, I'll forget about it\n");
      }
    }
    else {
      fprintf(stderr,"Already at end of file (t=%g)...\n",t);
      close_trn(in);
    }
  }
}
#endif

int gmx_trjconv(int argc,char *argv[])
{
  static char *desc[] = {
    "trjconv can convert trajectory files in many ways:[BR]",
    "[BB]1.[bb] from one format to another[BR]",
    "[BB]2.[bb] select a subset of atoms[BR]"
    "[BB]3.[bb] change the periodicity representation[BR]",
    "[BB]4.[bb] keep multimeric molecules together[BR]",
    "[BB]5.[bb] center atoms in the box[BR]",
    "[BB]6.[bb] fit atoms to reference structure[BR]",
    "[BB]7.[bb] reduce the number of frames[BR]",
    "[BB]8.[bb] change the timestamps of the frames ",
    "([TT]-t0[tt] and [TT]-timestep[tt])[BR]",
    "[BB]9.[bb] cut the trajectory in small subtrajectories according",
    "to information in an index file. This allows subsequent analysis of",
    "the subtrajectories that could, for example be the result of a",
    "cluster analysis. Use option [TT]-sub[tt].",
    "This assumes that the entries in the index file are frame numbers and",
    "dumps each group in the index file to a separate trajectory file.[BR]",
    "[BB]10.[bb] select frames within a certain range of a quantity given",
    "in an [TT].xvg[tt] file.[PAR]",
    "The program [TT]trjcat[tt] can concatenate multiple trajectory files.",
    "[PAR]",
    "Currently seven formats are supported for input and output:",
    "[TT].xtc[tt], [TT].trr[tt], [TT].trj[tt], [TT].gro[tt], [TT].g96[tt],",
    "[TT].pdb[tt] and [TT].g87[tt].",
    "The file formats are detected from the file extension.",
    "The precision of [TT].xtc[tt] and [TT].gro[tt] output is taken from the",
    "input file for [TT].xtc[tt], [TT].gro[tt] and [TT].pdb[tt],",
    "and from the [TT]-ndec[tt] option for other input formats. The precision",
    "is always taken from [TT]-ndec[tt], when this option is set.",
    "All other formats have fixed precision. [TT].trr[tt] and [TT].trj[tt]",
    "output can be single or double precision, depending on the precision",
    "of the trjconv binary.",
    "Note that velocities are only supported in",
    "[TT].trr[tt], [TT].trj[tt], [TT].gro[tt] and [TT].g96[tt] files.[PAR]",
    "Option [TT]-app[tt] can be used to",
    "append output to an existing trajectory file.",
    "No checks are performed to ensure integrity",
    "of the resulting combined trajectory file.[PAR]",
    "Option [TT]-sep[tt] can be used to write every frame to a seperate",
    ".gro, .g96 or .pdb file, default all frames all written to one file.",
    "[TT].pdb[tt] files with all frames concatenated can be viewed with",
    "[TT]rasmol -nmrpdb[tt].[PAR]",
    "It is possible to select part of your trajectory and write it out",
    "to a new trajectory file in order to save disk space, e.g. for leaving",
    "out the water from a trajectory of a protein in water.",
    "[BB]ALWAYS[bb] put the original trajectory on tape!",
    "We recommend to use the portable [TT].xtc[tt] format for your analysis",
    "to save disk space and to have portable files.[PAR]",
    "There are two options for fitting the trajectory to a reference",
    "either for essential dynamics analysis or for whatever.",
    "The first option is just plain fitting to a reference structure",
    "in the structure file, the second option is a progressive fit",
    "in which the first timeframe is fitted to the reference structure ",
    "in the structure file to obtain and each subsequent timeframe is ",
    "fitted to the previously fitted structure. This way a continuous",
    "trajectory is generated, which might not be the case when using the",
    "regular fit method, e.g. when your protein undergoes large",
    "conformational transitions.[PAR]",
    "Option [TT]-pbc[tt] sets the type of periodic boundary condition",
    "treatment:[BR]",
    "* [TT]mol[tt] puts the center of mass of molecules in the box.[BR]",
    "* [TT]res[tt] puts the center of mass of residues in the box.[BR]",
    "* [TT]atom[tt] puts all the atoms in the box.[BR]",
    "* [TT]nojump[tt] checks if atoms jump across the box and then puts",
    "them back. This has the effect that all molecules",
    "will remain whole (provided they were whole in the initial",
    "conformation), note that this ensures a continuous trajectory but",
    "molecules may diffuse out of the box. The starting configuration",
    "for this procedure is taken from the structure file, if one is",
    "supplied, otherwise it is the first frame.[BR]",
    "* [TT]cluster[tt] clusters all the atoms in the selected index",
    "such that they are all closest to the center of mass of the cluster",
    "which is iteratively updated. Note that this will only give meaningful",
    "results if you in fact have a cluster. Luckily that can be checked",
    "afterwards using a trajectory viewer. Note also that if your molecules",
    "are broken this will not work either.[BR]",
    "* [TT]whole[tt] only makes broken molecules whole.[PAR]",
    "Option [TT]-ur[tt] sets the unit cell representation for options",
    "[TT]mol[tt], [TT]res[tt] and [TT]atom[tt] of [TT]-pbc[tt].",
    "All three options give different results for triclinc boxes and",
    "identical results for rectangular boxes.",
    "[TT]rect[tt] is the ordinary brick shape.",
    "[TT]tric[tt] is the triclinic unit cell.", 
    "[TT]compact[tt] puts all atoms at the closest distance from the center",
    "of the box. This can be useful for visualizing e.g. truncated",
    "octahedrons. The center for options [TT]tric[tt] and [TT]compact[tt]",
    "is [TT]tric[tt] (see below), unless the option [TT]-center[tt]",
    "is set differently.[PAR]",
    "Option [TT]-center[tt] centers the system in the box. The user can",
    "select the group which is used to determine the geometrical center.",
    "The location of the center is set with [TT]-boxcenter[tt]:",
    "[TT]tric[tt]: half of the sum of the box vectors,",
    "[TT]rect[tt]: half of the box diagonal,",
    "[TT]zero[tt]: zero.",
    "Use option [TT]-pbc mol[tt] in addition to [TT]-center[tt] when you",
    "want all molecules in the box after the centering.[PAR]",
    "With [TT]-dt[tt] it is possible to reduce the number of ",
    "frames in the output. This option relies on the accuracy of the times",
    "in your input trajectory, so if these are inaccurate use the",
    "[TT]-timestep[tt] option to modify the time (this can be done",
    "simultaneously). For making smooth movies the program [TT]g_filter[tt]",
    "can reduce the number of frames while using low-pass frequency",
    "filtering, this reduces aliasing of high frequency motions.[PAR]",
    "Using [TT]-trunc[tt] trjconv can truncate [TT].trj[tt] in place, i.e.",
    "without copying the file. This is useful when a run has crashed",
    "during disk I/O (one more disk full), or when two contiguous",
    "trajectories must be concatenated without have double frames.[PAR]",
    "[TT]trjcat[tt] is more suitable for concatenating trajectory files.[PAR]",
    "Option [TT]-dump[tt] can be used to extract a frame at or near",
    "one specific time from your trajectory.[PAR]",
    "Option [TT]-drop[tt] reads an [TT].xvg[tt] file with times and values.",
    "When options [TT]-dropunder[tt] and/or [TT]-dropover[tt] are set,",
    "frames with a value below and above the value of the respective options",
    "will not be written."
  };
  
  int pbc_enum;
  enum
    { epSel,epNone, epComMol, epComRes, epComAtom, epNojump, epCluster, epWhole, epNR };
  static char *pbc_opt[epNR+1] = 
    { NULL, "none", "mol", "res", "atom", "nojump", "cluster", "whole", NULL };
  
  int unitcell_enum;
  static char *unitcell_opt[euNR+1] = 
    { NULL, "rect", "tric", "compact", NULL };

  enum
    { ecSel, ecTric, ecRect, ecZero, ecNR};
  static char *center_opt[ecNR+1] = 
    { NULL, "tric", "rect", "zero", NULL };
  int ecenter;
  
  int fit_enum;
  enum 
    { efSel, efNone , efFit,      efReset,       efPFit,      efNR };
  static char *fit[efNR+1] = 
    { NULL, "none", "rot+trans", "translation", "progressive", NULL };

  static bool  bAppend=FALSE,bSeparate=FALSE,bVels=TRUE,bForce=FALSE;
  static bool  bCenter=FALSE,bFit=FALSE,bPFit=FALSE,bReset=FALSE,bTer=FALSE;
  static int   skip_nr=1,ndec=3;
  static real  tzero=0,delta_t=0,timestep=0,ttrunc=-1,tdump=-1,split_t=0;
  static rvec  newbox = {0,0,0}, shift = {0,0,0};
  static char  *exec_command=NULL;
  static real  dropunder=0,dropover=0;

  t_pargs pa[] = {
    { "-skip", FALSE,  etINT, {&skip_nr},
      "Only write every nr-th frame" },
    { "-dt", FALSE,  etTIME, {&delta_t},
      "Only write frame when t MOD dt = first time (%t)" },
    { "-dump", FALSE, etTIME, {&tdump},
      "Dump frame nearest specified time (%t)" },
    { "-t0", FALSE,  etTIME, {&tzero},
      "Starting time (%t) (default: don't change)"},
    { "-timestep", FALSE,  etTIME, {&timestep},
      "Change time step between input frames (%t)" },
    { "-pbc", FALSE,  etENUM, {pbc_opt},
      "PBC treatment (see help text for full description)" },
    { "-ur", FALSE,  etENUM, {unitcell_opt},
      "Unit-cell representation" },
    { "-center", FALSE,  etBOOL, {&bCenter},
      "Center atoms in box" },
    { "-boxcenter", FALSE,  etENUM, {center_opt},
      "Center for -pbc and -center" },
    { "-box", FALSE, etRVEC, {newbox},
      "Size for new cubic box (default: read from input)" },
    { "-shift", FALSE, etRVEC, {shift},
      "All coordinates will be shifted by framenr*shift" },
    { "-fit",  FALSE, etENUM, {fit}, 
      "Fit molecule to ref structure in the structure file" },
    { "-ndec", FALSE,  etINT,  {&ndec},
      "Precision for .xtc and .gro writing in number of decimal places" },
    { "-vel", FALSE, etBOOL, {&bVels},
      "Read and write velocities if possible" },
    { "-force", FALSE, etBOOL, {&bForce},
      "Read and write forces if possible" },
#if (!defined WIN32 && !defined _WIN32 && !defined WIN64 && !defined _WIN64)
    { "-trunc", FALSE, etTIME, {&ttrunc},
      "Truncate input trj file after this time (%t)" },
#endif
    { "-exec", FALSE,  etSTR, {&exec_command},
      "Execute command for every output frame with the frame number "
      "as argument" },
    { "-app", FALSE,  etBOOL, {&bAppend},
      "Append output"},
    { "-split",FALSE, etTIME, {&split_t},
      "Start writing new file when t MOD split = first time (%t)" },
    { "-sep", FALSE,  etBOOL, {&bSeparate},
      "Write each frame to a separate .gro, .g96 or .pdb file"},
    { "-ter",  FALSE, etBOOL, {&bTer},
      "Use 'TER' in pdb file as end of frame in stead of default 'ENDMDL'" },
    { "-dropunder", FALSE, etREAL, {&dropunder},
      "Drop all frames below this value"},
    { "-dropover", FALSE, etREAL, {&dropover},
      "Drop all frames above this value"}
  };
#define NPA asize(pa)
      
  FILE         *out=NULL;
  int          trxout=NOTSET;
  int          status,ftp,ftpin=0,file_nr;
  t_trxframe   fr,frout;
  int          flags;
  rvec         *xmem=NULL,*vmem=NULL;
  rvec         *xp=NULL,x_shift,hbox,box_center,dx;
  real         xtcpr, lambda,*w_rls=NULL;
  int          m,i,d,frame,outframe,natoms,nout,ncent,nre,newstep=0,model_nr;
#define SKIP 10
  t_topology   top;
  t_atoms      *atoms=NULL,useatoms;
  matrix       top_box;
  atom_id      *index,*cindex;
  char         *grpnm;
  int          *frindex,nrfri;
  char         *frname;
  int          ifit,irms,my_clust=-1;
  atom_id      *ind_fit,*ind_rms;
  char         *gn_fit,*gn_rms;
  t_cluster_ndx *clust=NULL;
  int          *clust_status=NULL;
  int          ntrxopen=0;
  int          *nfwritten=NULL;
  int          ndrop=0,ncol,drop0=0,drop1=0,dropuse=0;
  double       **dropval;
  real         tshift=0,t0=-1,dt=0.001,prec;
  bool         bRmPBC,bPBCWhole,bPBCcomRes,bPBCcomMol,bPBCcomAtom,bNoJump,bCluster;
  bool         bCopy,bDoIt,bIndex,bTDump,bSetTime,bTPS=FALSE,bDTset=FALSE;
  bool         bExec,bTimeStep=FALSE,bDumpFrame=FALSE,bSetPrec,bNeedPrec;
  bool         bHaveFirstFrame,bHaveNextFrame,bSetBox,bSetUR,bSplit=FALSE;
  bool         bSubTraj=FALSE,bDropUnder=FALSE,bDropOver=FALSE;
  bool         bWriteFrame,bSplitHere;
  char         *top_file,*in_file,*out_file=NULL,out_file2[256],*charpt;
  char         *outf_base=NULL,*outf_ext=NULL;
  char         top_title[256],title[256],command[256],filemode[5];
  int          xdr=0;
  bool         bWarnCompact=FALSE;
  char         *warn;

  t_filenm fnm[] = {
    { efTRX, "-f",   NULL,      ffREAD  },
    { efTRX, "-o",   "trajout", ffWRITE },
    { efTPS, NULL,   NULL,      ffOPTRD },
    { efNDX, NULL,   NULL,      ffOPTRD },
    { efNDX, "-fr",  "frames",  ffOPTRD },
    { efNDX, "-sub", "cluster", ffOPTRD },
    { efXVG, "-drop","drop",    ffOPTRD }
  };
#define NFILE asize(fnm)
  
  CopyRight(stderr,argv[0]);
  parse_common_args(&argc,argv,
		    PCA_CAN_BEGIN | PCA_CAN_END | PCA_CAN_VIEW | PCA_TIME_UNIT | PCA_BE_NICE,
		    NFILE,fnm,NPA,pa,asize(desc),desc,
		    0,NULL);

  top_file = ftp2fn(efTPS,NFILE,fnm);

  /* Check command line */
  in_file=opt2fn("-f",NFILE,fnm);
  
  if (ttrunc != -1) {
#if (!defined WIN32 && !defined _WIN32 && !defined WIN64 && !defined _WIN64)
    do_trunc(in_file,ttrunc);
#endif
  }
  else {
    /* mark active cmdline options */
    bSetBox   = opt2parg_bSet("-box", NPA, pa);
    bSetTime  = opt2parg_bSet("-t0", NPA, pa);
    bSetPrec  = opt2parg_bSet("-ndec", NPA, pa);
    bSetUR    = opt2parg_bSet("-ur", NPA, pa);
    bExec     = opt2parg_bSet("-exec", NPA, pa);
    bTimeStep = opt2parg_bSet("-timestep", NPA, pa);
    bTDump    = opt2parg_bSet("-dump", NPA, pa);
    bDropUnder= opt2parg_bSet("-dropunder", NPA, pa);
    bDropOver = opt2parg_bSet("-dropover", NPA, pa);
    bSplit    = (split_t != 0);

    /* parse enum options */    
    fit_enum   = nenum(fit);
    bFit       = fit_enum==efFit;
    bReset     = fit_enum==efReset;
    bPFit      = fit_enum==efPFit;
    pbc_enum   = nenum(pbc_opt);
    bPBCWhole  = pbc_enum==epWhole;
    bPBCcomRes = pbc_enum==epComRes;
    bPBCcomMol = pbc_enum==epComMol;
    bPBCcomAtom= pbc_enum==epComAtom;
    bNoJump    = pbc_enum==epNojump;
    bCluster   = pbc_enum==epCluster;
    unitcell_enum = nenum(unitcell_opt);
    ecenter    = nenum(center_opt) - ecTric;

    /* set and check option dependencies */    
    if (bPFit) bFit = TRUE; /* for pfit, fit *must* be set */
    if (bFit) bReset = TRUE; /* for fit, reset *must* be set */
    bRmPBC = bFit || bPBCWhole || bPBCcomRes || bPBCcomMol;
    if (bSetUR) {
      if ( bNoJump || bCluster || bPBCWhole ) {
	fprintf(stderr,"Note: Option for unitcell representation (-ur %s) has "
		"no effect in\n"
		"      combination with -pbc %s; ingoring unitcell "
		"representation.\n\n", unitcell_opt[0], pbc_opt[0]);
	bSetUR = FALSE;
      }
    }
    /* set flag for pdbio to terminate frames at 'TER' (iso 'ENDMDL') */
    pdb_use_ter(bTer);

    /* ndec is in nr of decimal places, prec is a multiplication factor: */
    prec = 1;
    for (i=0; i<ndec; i++)
      prec *= 10;
    
    bIndex=ftp2bSet(efNDX,NFILE,fnm);

        
    /* Determine output type */ 
    out_file=opt2fn("-o",NFILE,fnm);
    ftp=fn2ftp(out_file);
    fprintf(stderr,"Will write %s: %s\n",ftp2ext(ftp),ftp2desc(ftp));
    bNeedPrec = (ftp==efXTC || ftp==efGRO);
    if (bVels) {
      /* check if velocities are possible in input and output files */
      ftpin=fn2ftp(in_file);
      bVels= (ftp==efTRR || ftp==efTRJ || ftp==efGRO || ftp==efG96) 
	&& (ftpin==efTRR || ftpin==efTRJ || ftpin==efGRO || ftpin==efG96);
    }
    if (bSeparate || bSplit) {
      outf_ext = strrchr(out_file,'.');
      if (outf_ext == NULL)
	gmx_fatal(FARGS,"Output file name '%s' does not contain a '.'",out_file);
      outf_base = strdup(out_file);
      outf_base[outf_ext - out_file] = '\0';
    }

    bSubTraj = opt2bSet("-sub",NFILE,fnm);
    if (bSubTraj) {
      if ((ftp != efXTC) && (ftp != efTRN))
	gmx_fatal(FARGS,"Can only use the sub option with output file types "
		  "xtc and trr");
      clust = cluster_index(opt2fn("-sub",NFILE,fnm));
      
      /* Check for number of files disabled, as FOPEN_MAX is not the correct
       * number to check for. In my linux box it is only 16.
       */
      if (0 && (clust->clust->nr > FOPEN_MAX-4))
	gmx_fatal(FARGS,"Can not open enough (%d) files to write all the"
		  " trajectories.\ntry splitting the index file in %d parts.\n"
		  "FOPEN_MAX = %d",
		  clust->clust->nr,1+clust->clust->nr/FOPEN_MAX,FOPEN_MAX);
      
      snew(clust_status,clust->clust->nr);
      snew(nfwritten,clust->clust->nr);
      for(i=0; (i<clust->clust->nr); i++)
	clust_status[i] = -1;
      bSeparate = bSplit = FALSE;
    }
    /* skipping */  
    if (skip_nr <= 0) {
    } 
    
    /* Determine whether to read a topology */
    bTPS = (ftp2bSet(efTPS,NFILE,fnm) ||
	    bRmPBC || bReset || bPBCcomMol ||
	    (ftp == efGRO) || (ftp == efPDB));

    /* Determine if when can read index groups */
    bIndex = (bIndex || bTPS);
    
    if (bTPS) {
      read_tps_conf(top_file,top_title,&top,&xp,NULL,top_box,
		    bReset || bPBCcomRes);
      atoms=&top.atoms;
      /* top_title is only used for gro and pdb,
       * the header in such a file is top_title t= ...
       * to prevent a double t=, remove it from top_title
       */
      if ((charpt=strstr(top_title," t= ")))
	charpt[0]='\0';
    }
    
    /* get frame number index */
    frindex=NULL;
    if (opt2bSet("-fr",NFILE,fnm)) {
      printf("Select groups of frame number indices:\n");
      rd_index(opt2fn("-fr",NFILE,fnm),1,&nrfri,(atom_id **)&frindex,&frname);
      if (debug)
	for(i=0; i<nrfri; i++)
	  fprintf(debug,"frindex[%4d]=%4d\n",i,frindex[i]);
    }
    
      /* get index groups etc. */
    if (bReset) {
      printf("Select group for %s fit\n",
	     bFit?"least squares":"translational");
      get_index(atoms,ftp2fn_null(efNDX,NFILE,fnm),
		1,&ifit,&ind_fit,&gn_fit);

      if (bFit) {
	if (ifit < 2) 
	  gmx_fatal(FARGS,"Need at least 2 atoms to fit!\n");
	else if (ifit == 3)
	  fprintf(stderr,"WARNING: fitting with only 2 atoms is not unique\n");
      }
    }
    else if (bCluster) {
      printf("Select group for clustering\n");
      get_index(atoms,ftp2fn_null(efNDX,NFILE,fnm),
		1,&ifit,&ind_fit,&gn_fit);
    }
    
    if (bIndex) {
      if (bCenter) {
	printf("Select group for centering\n");
	get_index(atoms,ftp2fn_null(efNDX,NFILE,fnm),
		  1,&ncent,&cindex,&grpnm);
      }
      printf("Select group for output\n");
      get_index(atoms,ftp2fn_null(efNDX,NFILE,fnm),
		1,&nout,&index,&grpnm);
    } else {
      /* no index file, so read natoms from TRX */
      if (!read_first_frame(&status,in_file,&fr,TRX_DONT_SKIP))
	gmx_fatal(FARGS,"Could not read a frame from %s",in_file);
      natoms = fr.natoms;
      close_trj(status);
      sfree(fr.x);
      snew(index,natoms);
      for(i=0;i<natoms;i++)
	index[i]=i;
      nout=natoms; 
      if (bCenter) {
	ncent = nout;
	cindex = index;
      }
    }
    
    if (bReset) {
      snew(w_rls,atoms->nr);
      for(i=0; (i<ifit); i++)
	w_rls[ind_fit[i]]=atoms->atom[ind_fit[i]].m;
      
      /* Restore reference structure and set to origin, 
         store original location (to put structure back) */
      if (bRmPBC)
	rm_pbc(&(top.idef),atoms->nr,top_box,xp,xp);
      copy_rvec(xp[index[0]],x_shift);
      reset_x(ifit,ind_fit,atoms->nr,NULL,xp,w_rls);
      rvec_dec(x_shift,xp[index[0]]);
    } else
      clear_rvec(x_shift);

    if (bDropUnder || bDropOver) {
      /* Read the xvg file with the drop values */
      fprintf(stderr,"\nReading drop file ...");
      ndrop = read_xvg(opt2fn("-drop",NFILE,fnm),&dropval,&ncol);
      fprintf(stderr," %d time points\n",ndrop);
      if (ndrop == 0 || ncol < 2)
	gmx_fatal(FARGS,"Found no data points in %s",
		  opt2fn("-drop",NFILE,fnm));
      drop0 = 0;
      drop1 = 0;
    }
    
    /* Make atoms struct for output in GRO or PDB files */
    if ((ftp == efGRO) || ((ftp == efG96) && bTPS) || (ftp == efPDB)) {
      /* get memory for stuff to go in pdb file */
      init_t_atoms(&useatoms,atoms->nr,FALSE);
      sfree(useatoms.resname);
      useatoms.resname=atoms->resname;
      for(i=0;(i<nout);i++) {
	useatoms.atomname[i]=atoms->atomname[index[i]];
	useatoms.atom[i]=atoms->atom[index[i]];
	useatoms.nres=max(useatoms.nres,useatoms.atom[i].resnr+1);
      }
      useatoms.nr=nout;
    }
    /* select what to read */
    if (ftp==efTRR || ftp==efTRJ)
      flags = TRX_READ_X; 
    else
      flags = TRX_NEED_X;
    if (bVels)
      flags = flags | TRX_READ_V;
    if (bForce)
      flags = flags | TRX_READ_F;

    /* open trx file for reading */
    bHaveFirstFrame = read_first_frame(&status,in_file,&fr,flags);
    if (fr.bPrec)
      fprintf(stderr,"\nPrecision of %s is %g (nm)\n",in_file,1/fr.prec);
    if (bNeedPrec) {
      if (bSetPrec || !fr.bPrec)
	fprintf(stderr,"\nSetting output precision to %g (nm)\n",1/prec);
      else
	fprintf(stderr,"Using output precision of %g (nm)\n",1/prec);
    }

    if (bHaveFirstFrame) {
      natoms = fr.natoms;
      
      if (bSetTime)
	tshift=tzero-fr.time;
      else
	tzero=fr.time;
      
      /* open output for writing */
      if ((bAppend) && (fexist(out_file))) {
	strcpy(filemode,"a");
	fprintf(stderr,"APPENDING to existing file %s\n",out_file);
      } else
	strcpy(filemode,"w");
      switch (ftp) {
      case efXTC:
      case efG87:
      case efTRR:
      case efTRJ:
	out=NULL;
	if (!bSplit && !bSubTraj)
	  trxout = open_trx(out_file,filemode);
	break;
      case efGRO:
      case efG96:
      case efPDB:
	if (( !bSeparate && !bSplit ) && !bSubTraj)
	  out=ffopen(out_file,filemode);
	break;
      }
      
      bCopy=FALSE;
      if (bIndex)
	/* check if index is meaningful */
	for(i=0; i<nout; i++) {
	  if (index[i] >= natoms)
	  gmx_fatal(FARGS,"Index[%d] %d is larger than the number of atoms in the trajectory file (%d)",i,index[i]+1,natoms);
	  bCopy = bCopy || (i != index[i]);
	}
      if (bCopy) {
	snew(xmem,nout);
	snew(vmem,nout);
      }
      
      if (ftp == efG87)
	fprintf(fio_getfp(trxout),"Generated by %s. #atoms=%d, a BOX is"
		" stored in this file.\n",Program(),nout);
    
      /* Start the big loop over frames */
      file_nr  =  0;  
      frame    =  0;
      outframe =  0;
      model_nr = -1;
      bDTset   = FALSE;
    
      /* Main loop over frames */
      do {
	if (!fr.bStep) {
	  /* set the step */
	  fr.step = newstep;
	  newstep++;
	}
	if (bSubTraj) {
	  /*if (frame >= clust->clust->nra)
	    gmx_fatal(FARGS,"There are more frames in the trajectory than in the cluster index file\n");*/
	  if (frame >= clust->maxframe)
	    my_clust = -1;
	  else
	    my_clust = clust->inv_clust[frame];
	  if ((my_clust < 0) || (my_clust >= clust->clust->nr) || 
	      (my_clust == NO_ATID))
	    my_clust = -1;
	}
	
	if (bSetBox) {
	  /* generate new box */
	  clear_mat(fr.box);
	  for (m=0; m<DIM; m++)
	    fr.box[m][m] = newbox[m];
	}
	
	if (bTDump) {
	  /* determine timestep */
	  if (t0 == -1) {
	    t0 = fr.time;
	  } else {
	    if (!bDTset) {
	      dt = fr.time-t0;
	      bDTset = TRUE;
	    }
	  }
	  /* This is not very elegant, as one can not dump a frame after
	   * a timestep with is more than twice as small as the first one. */
	  bDumpFrame = (fr.time > tdump-0.5*dt) && (fr.time <= tdump+0.5*dt);
	} else
	  bDumpFrame = FALSE;
	
	/* determine if an atom jumped across the box and reset it if so */
	if (bNoJump && (bTPS || frame!=0)) {
	  for(d=0; d<DIM; d++)
	    hbox[d] = 0.5*fr.box[d][d];
	  for(i=0; i<natoms; i++) {
	    if (bReset)
	      rvec_dec(fr.x[i],x_shift);
	    for(m=DIM-1; m>=0; m--)
	      if (hbox[m] > 0) {
		while (fr.x[i][m]-xp[i][m] <= -hbox[m])
		  for(d=0; d<=m; d++)
		    fr.x[i][d] += fr.box[m][d];
		while (fr.x[i][m]-xp[i][m] > hbox[m])
		  for(d=0; d<=m; d++)
		    fr.x[i][d] -= fr.box[m][d];
	      }
	  }
	}
	else if (bCluster && bTPS) {
	  rvec com;
	  
	  calc_pbc_cluster(ecenter,ifit,&top,fr.x,ind_fit,com,fr.box);
	}
      
	if (bPFit) {
	  /* Now modify the coords according to the flags,
	     for normal fit, this is only done for output frames */
	  if (bRmPBC)
	    rm_pbc(&(top.idef),natoms,fr.box,fr.x,fr.x);
	
	  reset_x(ifit,ind_fit,natoms,NULL,fr.x,w_rls);
	  do_fit(natoms,w_rls,xp,fr.x);
	}
      
	/* store this set of coordinates for future use */
	if (bPFit || bNoJump) {
	  if (xp == NULL)
	    snew(xp,natoms);
	  for(i=0; (i<natoms); i++) {
	    copy_rvec(fr.x[i],xp[i]);
	    rvec_inc(fr.x[i],x_shift);
	  }
	}
	
	if ( frindex )
	  /* see if we have a frame from the frame index group */
	  for(i=0; i<nrfri && !bDumpFrame; i++)
	    bDumpFrame = frame == frindex[i];
	if (debug && bDumpFrame)
	  fprintf(debug,"dumping %d\n",frame);

	bWriteFrame =
	  ( ( !bTDump && !frindex && frame % skip_nr == 0 ) || bDumpFrame );

	if (bWriteFrame && (bDropUnder || bDropOver)) {
	  while (dropval[0][drop1]<fr.time && drop1+1<ndrop) {
	    drop0 = drop1;
	    drop1++;
	  }
	  if (fabs(dropval[0][drop0] - fr.time)
	      < fabs(dropval[0][drop1] - fr.time)) {
	    dropuse = drop0;
	  } else {
	    dropuse = drop1;
	  }
	  if ((bDropUnder && dropval[1][dropuse] < dropunder) ||
	      (bDropOver && dropval[1][dropuse] > dropover))
	    bWriteFrame = FALSE;
	}
	
	if (bWriteFrame) {
	  
	  /* calc new time */
	  if (bTimeStep) 
	    fr.time = tzero+frame*timestep;
	  else
	    if (bSetTime)
	      fr.time += tshift;

	  if (bTDump)
	    fprintf(stderr,"\nDumping frame at t= %g %s\n",
		    convert_time(fr.time),time_unit());

	/* check for writing at each delta_t */
	  bDoIt=(delta_t == 0);
	  if (!bDoIt)
	    bDoIt=bRmod(fr.time,tzero, delta_t);
	
	  if (bDoIt || bTDump) {
	    /* print sometimes */
	    if ( ((outframe % SKIP) == 0) || (outframe < SKIP) )
	      fprintf(stderr," ->  frame %6d time %8.3f      \r",
		      outframe,convert_time(fr.time));
	  
	    if (!bPFit) {
	      /* Now modify the coords according to the flags,
		 for PFit we did this already! */
	    
	      if (bRmPBC)
		rm_pbc(&(top.idef),natoms,fr.box,fr.x,fr.x);
	  
	      if (bReset) {
		reset_x(ifit,ind_fit,natoms,NULL,fr.x,w_rls);
		if (bFit)
		  do_fit(natoms,w_rls,xp,fr.x);
		if (!bCenter)
		  for(i=0; i<natoms; i++)
		    rvec_inc(fr.x[i],x_shift);
	      }

	      if (bCenter)
		center_x(ecenter,fr.x,fr.box,natoms,ncent,cindex);
	    }

	    if (bPBCcomAtom) {
	      switch (unitcell_enum) {
	      case euRect:
		put_atoms_in_box(fr.box,natoms,fr.x);
		break;
	      case euTric:
		put_atoms_in_triclinic_unitcell(ecenter,fr.box,natoms,fr.x);
		break;
	      case euCompact:
		warn = put_atoms_in_compact_unitcell(ecenter,fr.box,
						     natoms,fr.x);
		if (warn && !bWarnCompact) {
		  fprintf(stderr,"\n%s\n",warn);
		  bWarnCompact = TRUE;
		}
		break;
	      }
	    }
	    if (bPBCcomRes) {
	      put_residue_com_in_box(unitcell_enum,ecenter,
				     natoms,atoms->atom,fr.box,fr.x);
	    }
	    if (bPBCcomMol) {
	      put_molecule_com_in_box(unitcell_enum,ecenter,
				      &top.blocks[ebMOLS],
				      natoms,atoms->atom,fr.box, fr.x);
	    }
	    /* Copy the input trxframe struct to the output trxframe struct */
	    frout = fr;
	    frout.natoms = nout;
	    if (bNeedPrec && (bSetPrec || !fr.bPrec)) {
	      frout.bPrec = TRUE;
	      frout.prec  = prec;
	    }
	    if (bCopy) {
	      frout.x = xmem;
	      frout.v = vmem;
	      for(i=0; i<nout; i++) {
		copy_rvec(fr.x[index[i]],frout.x[i]);
		if (bVels && fr.bV) copy_rvec(fr.v[index[i]],frout.v[i]);
	      }
	    }
	  
	    if (opt2parg_bSet("-shift",NPA,pa))
	      for(i=0; i<nout; i++)
		for (d=0; d<DIM; d++)
		  frout.x[i][d] += outframe*shift[d];
	  
	    bSplitHere = bSplit && bRmod(fr.time,tzero, split_t);
	    if (bSeparate || bSplitHere)
	      sprintf(out_file2,"%s_%d%s",outf_base,file_nr,outf_ext);
	    switch(ftp) {
	    case efTRJ:
	    case efTRR:
	    case efG87:
	    case efXTC:
	      if ( bSplitHere ) {
		if ( trxout >= 0 )
		  close_trx(trxout);
		trxout = open_trx(out_file2,filemode);
	      }
	      if (bSubTraj) {
		if (my_clust != -1) {
		  char buf[STRLEN];
		  if (clust_status[my_clust] == -1) {
		    sprintf(buf,"%s.%s",clust->grpname[my_clust],ftp2ext(ftp));
		    clust_status[my_clust] = open_trx(buf,"w");
		    ntrxopen++;
		  }
		  else if (clust_status[my_clust] == -2)
		    gmx_fatal(FARGS,"File %s.xtc should still be open (%d open xtc files)\n""in order to write frame %d. my_clust = %d",
			      clust->grpname[my_clust],ntrxopen,frame,
			      my_clust);
		  write_trxframe(clust_status[my_clust],&frout);
		  nfwritten[my_clust]++;
		  if (nfwritten[my_clust] == 
		      (clust->clust->index[my_clust+1]-
		       clust->clust->index[my_clust])) {
		    close_trx(clust_status[my_clust]);
		    clust_status[my_clust] = -2;
		    ntrxopen--;
		    if (ntrxopen < 0)
		      gmx_fatal(FARGS,"Less than zero open xtc files!");
		  }
		}
	      }
	      else
		write_trxframe(trxout,&frout);
	      break;
	    case efGRO:
	    case efG96:
	    case efPDB:
	      sprintf(title,"Generated by trjconv : %s t= %9.5f",
		      top_title,fr.time);
	      if (bSeparate || bSplitHere)
		out=ffopen(out_file2,"w");
	      switch(ftp) {
	      case efGRO: 
		write_hconf_p(out,title,&useatoms,prec2ndec(frout.prec),
			      frout.x,fr.bV?frout.v:NULL,frout.box);
		break;
	      case efPDB:
		fprintf(out,"REMARK    GENERATED BY TRJCONV\n");
		sprintf(title,"%s t= %9.5f",top_title,frout.time);
		/* if reading from pdb, we want to keep the original 
		   model numbering else we write the output frame
		   number plus one, because model 0 is not allowed in pdb */
		if (ftpin==efPDB && fr.bStep && fr.step > model_nr)
		  model_nr = fr.step;
		else
		  model_nr++;
		write_pdbfile(out,title,&useatoms,frout.x,frout.box,0,
			      model_nr);
		break;
	      case efG96:
		frout.title = title;
		if (bSeparate || bTDump) {
		  frout.bTitle = TRUE;
		  if (bTPS) 
		    frout.bAtoms = TRUE;
		  frout.atoms  = &useatoms;
		  frout.bStep  = FALSE;
		  frout.bTime  = FALSE;
		} else {
		  frout.bTitle = (outframe == 0);
		  frout.bAtoms = FALSE;
		  frout.bStep = TRUE;
		  frout.bTime = TRUE;
		}
		write_g96_conf(out,&frout,-1,NULL);
	      }
	      if (bSeparate) {
		ffclose(out);
		out = NULL;
	      }
	      break;
	    default:
	      gmx_fatal(FARGS,"DHE, ftp=%d\n",ftp);
	    }
	    if (bSeparate || bSplitHere)
	      file_nr++;
	  
	    /* execute command */
	    if (bExec) {
	      char c[255];
	      sprintf(c,"%s  %d",exec_command,file_nr-1);
	      /*fprintf(stderr,"Executing '%s'\n",c);*/
	      system(c);
	    }
	    outframe++;
	  }
	}
	frame++;
	bHaveNextFrame=read_next_frame(status,&fr);
      } while (!(bTDump && bDumpFrame) && bHaveNextFrame);
    }
    
    if (!bHaveFirstFrame || (bTDump && !bDumpFrame))
      fprintf(stderr,"\nWARNING no output, "
	      "trajectory ended at %g\n",fr.time);
    fprintf(stderr,"\n");
    
    close_trj(status);
    
    if (trxout >= 0)
      close_trx(trxout);
    else if (out != NULL)
      fclose(out);
    if (bSubTraj) {
      for(i=0; (i<clust->clust->nr); i++)
	if (clust_status[i] >= 0)
	  close_trx(clust_status[i]);
    }
  }
  
  do_view(out_file,NULL);
  
  thanx(stderr);
  
  return 0;
}
