##
## $Id: nb_kernel111_x86_64_sse2.s,v 1.4.2.3 2006/09/22 08:40:32 lindahl Exp $
##
## Gromacs 4.0                         Copyright (c) 1991-2003 
## David van der Spoel, Erik Lindahl
##
## This program is free software; you can redistribute it and/or
## modify it under the terms of the GNU General Public License
## as published by the Free Software Foundation; either version 2
## of the License, or (at your option) any later version.
##
## To help us fund GROMACS development, we humbly ask that you cite
## the research papers on the package. Check out http://www.gromacs.org
## 
## And Hey:
## Gnomes, ROck Monsters And Chili Sauce
##





.globl nb_kernel111_x86_64_sse2
.globl _nb_kernel111_x86_64_sse2
nb_kernel111_x86_64_sse2:       
_nb_kernel111_x86_64_sse2:      
##      Room for return address and rbp (16 bytes)
.set nb111_fshift, 16
.set nb111_gid, 24
.set nb111_pos, 32
.set nb111_faction, 40
.set nb111_charge, 48
.set nb111_p_facel, 56
.set nb111_argkrf, 64
.set nb111_argcrf, 72
.set nb111_Vc, 80
.set nb111_type, 88
.set nb111_p_ntype, 96
.set nb111_vdwparam, 104
.set nb111_Vvdw, 112
.set nb111_p_tabscale, 120
.set nb111_VFtab, 128
.set nb111_invsqrta, 136
.set nb111_dvda, 144
.set nb111_p_gbtabscale, 152
.set nb111_GBtab, 160
.set nb111_p_nthreads, 168
.set nb111_count, 176
.set nb111_mtx, 184
.set nb111_outeriter, 192
.set nb111_inneriter, 200
.set nb111_work, 208
        ## stack offsets for local variables  
        ## bottom of stack is cache-aligned for sse2 use 
.set nb111_ixO, 0
.set nb111_iyO, 16
.set nb111_izO, 32
.set nb111_ixH1, 48
.set nb111_iyH1, 64
.set nb111_izH1, 80
.set nb111_ixH2, 96
.set nb111_iyH2, 112
.set nb111_izH2, 128
.set nb111_iqO, 144
.set nb111_iqH, 160
.set nb111_dxO, 176
.set nb111_dyO, 192
.set nb111_dzO, 208
.set nb111_dxH1, 224
.set nb111_dyH1, 240
.set nb111_dzH1, 256
.set nb111_dxH2, 272
.set nb111_dyH2, 288
.set nb111_dzH2, 304
.set nb111_qqO, 320
.set nb111_qqH, 336
.set nb111_c6, 352
.set nb111_c12, 368
.set nb111_six, 384
.set nb111_twelve, 400
.set nb111_vctot, 416
.set nb111_Vvdwtot, 432
.set nb111_fixO, 448
.set nb111_fiyO, 464
.set nb111_fizO, 480
.set nb111_fixH1, 496
.set nb111_fiyH1, 512
.set nb111_fizH1, 528
.set nb111_fixH2, 544
.set nb111_fiyH2, 560
.set nb111_fizH2, 576
.set nb111_fjx, 592
.set nb111_fjy, 608
.set nb111_fjz, 624
.set nb111_half, 640
.set nb111_three, 656
.set nb111_is3, 672
.set nb111_ii3, 676
.set nb111_nri, 692
.set nb111_iinr, 700
.set nb111_jindex, 708
.set nb111_jjnr, 716
.set nb111_shift, 724
.set nb111_shiftvec, 732
.set nb111_facel, 740
.set nb111_innerjjnr, 748
.set nb111_ntia, 756
.set nb111_innerk, 760
.set nb111_n, 764
.set nb111_nn1, 768
.set nb111_nouter, 772
.set nb111_ninner, 776
        push %rbp
        movq %rsp,%rbp
        push %rbx

        emms

        push %r12
        push %r13
        push %r14
        push %r15

        subq $792,%rsp          ## local variable stack space (n*16+8)

        ## zero 32-bit iteration counters
        movl $0,%eax
        movl %eax,nb111_nouter(%rsp)
        movl %eax,nb111_ninner(%rsp)

        movl (%rdi),%edi
        movl %edi,nb111_nri(%rsp)
        movq %rsi,nb111_iinr(%rsp)
        movq %rdx,nb111_jindex(%rsp)
        movq %rcx,nb111_jjnr(%rsp)
        movq %r8,nb111_shift(%rsp)
        movq %r9,nb111_shiftvec(%rsp)
        movq nb111_p_facel(%rbp),%rsi
        movsd (%rsi),%xmm0
        movsd %xmm0,nb111_facel(%rsp)

        ## create constant floating-point factors on stack
        movl $0x00000000,%eax   ## lower half of double half IEEE (hex)
        movl $0x3fe00000,%ebx
        movl %eax,nb111_half(%rsp)
        movl %ebx,nb111_half+4(%rsp)
        movsd nb111_half(%rsp),%xmm1
        shufpd $0,%xmm1,%xmm1  ## splat to all elements
        movapd %xmm1,%xmm3
        addpd  %xmm3,%xmm3      ## one
        movapd %xmm3,%xmm2
        addpd  %xmm2,%xmm2      ## two
        addpd  %xmm2,%xmm3      ## three
        movapd %xmm3,%xmm4
        addpd  %xmm4,%xmm4      ## six
        movapd %xmm4,%xmm5
        addpd  %xmm5,%xmm5      ## twelve
        movapd %xmm1,nb111_half(%rsp)
        movapd %xmm3,nb111_three(%rsp)
        movapd %xmm4,nb111_six(%rsp)
        movapd %xmm5,nb111_twelve(%rsp)

        ## assume we have at least one i particle - start directly 
        movq  nb111_iinr(%rsp),%rcx         ## rcx = pointer into iinr[]        
        movl  (%rcx),%ebx           ## ebx =ii 

        movq  nb111_charge(%rbp),%rdx
        movsd (%rdx,%rbx,8),%xmm3
        movsd 8(%rdx,%rbx,8),%xmm4
        movq nb111_p_facel(%rbp),%rsi
        movsd (%rsi),%xmm0
        movsd nb111_facel(%rsp),%xmm5
        mulsd  %xmm5,%xmm3
        mulsd  %xmm5,%xmm4

        shufpd $0,%xmm3,%xmm3
        shufpd $0,%xmm4,%xmm4
        movapd %xmm3,nb111_iqO(%rsp)
        movapd %xmm4,nb111_iqH(%rsp)

        movq  nb111_type(%rbp),%rdx
        movl  (%rdx,%rbx,4),%ecx
        shll  %ecx
        movq nb111_p_ntype(%rbp),%rdi
        imull (%rdi),%ecx     ## rcx = ntia = 2*ntype*type[ii0] 
        movl  %ecx,nb111_ntia(%rsp)
_nb_kernel111_x86_64_sse2.nb111_threadloop: 
        movq  nb111_count(%rbp),%rsi            ## pointer to sync counter
        movl  (%rsi),%eax
_nb_kernel111_x86_64_sse2.nb111_spinlock: 
        movl  %eax,%ebx                         ## ebx=*count=nn0
        addl  $1,%ebx                          ## ebx=nn1=nn0+10
        lock 
        cmpxchgl %ebx,(%rsi)                    ## write nn1 to *counter,
                                                ## if it hasnt changed.
                                                ## or reread *counter to eax.
        pause                                   ## -> better p4 performance
        jnz _nb_kernel111_x86_64_sse2.nb111_spinlock

        ## if(nn1>nri) nn1=nri
        movl nb111_nri(%rsp),%ecx
        movl %ecx,%edx
        subl %ebx,%ecx
        cmovlel %edx,%ebx                       ## if(nn1>nri) nn1=nri
        ## Cleared the spinlock if we got here.
        ## eax contains nn0, ebx contains nn1.
        movl %eax,nb111_n(%rsp)
        movl %ebx,nb111_nn1(%rsp)
        subl %eax,%ebx                          ## calc number of outer lists
        movl %eax,%esi                          ## copy n to esi
        jg  _nb_kernel111_x86_64_sse2.nb111_outerstart
        jmp _nb_kernel111_x86_64_sse2.nb111_end

_nb_kernel111_x86_64_sse2.nb111_outerstart: 
        ## ebx contains number of outer iterations
        addl nb111_nouter(%rsp),%ebx
        movl %ebx,nb111_nouter(%rsp)

_nb_kernel111_x86_64_sse2.nb111_outer: 
        movq  nb111_shift(%rsp),%rax        ## rax = pointer into shift[] 
        movl  (%rax,%rsi,4),%ebx        ## rbx=shift[n] 

        lea  (%rbx,%rbx,2),%rbx    ## rbx=3*is 
        movl  %ebx,nb111_is3(%rsp)      ## store is3 

        movq  nb111_shiftvec(%rsp),%rax     ## rax = base of shiftvec[] 

        movsd (%rax,%rbx,8),%xmm0
        movsd 8(%rax,%rbx,8),%xmm1
        movsd 16(%rax,%rbx,8),%xmm2

        movq  nb111_iinr(%rsp),%rcx         ## rcx = pointer into iinr[]        
        movl  (%rcx,%rsi,4),%ebx    ## ebx =ii 

        movapd %xmm0,%xmm3
        movapd %xmm1,%xmm4
        movapd %xmm2,%xmm5

        lea  (%rbx,%rbx,2),%rbx        ## rbx = 3*ii=ii3 
        movq  nb111_pos(%rbp),%rax      ## rax = base of pos[]  
        movl  %ebx,nb111_ii3(%rsp)

        addsd (%rax,%rbx,8),%xmm3
        addsd 8(%rax,%rbx,8),%xmm4
        addsd 16(%rax,%rbx,8),%xmm5
        shufpd $0,%xmm3,%xmm3
        shufpd $0,%xmm4,%xmm4
        shufpd $0,%xmm5,%xmm5
        movapd %xmm3,nb111_ixO(%rsp)
        movapd %xmm4,nb111_iyO(%rsp)
        movapd %xmm5,nb111_izO(%rsp)

        movsd %xmm0,%xmm3
        movsd %xmm1,%xmm4
        movsd %xmm2,%xmm5
        addsd 24(%rax,%rbx,8),%xmm0
        addsd 32(%rax,%rbx,8),%xmm1
        addsd 40(%rax,%rbx,8),%xmm2
        addsd 48(%rax,%rbx,8),%xmm3
        addsd 56(%rax,%rbx,8),%xmm4
        addsd 64(%rax,%rbx,8),%xmm5

        shufpd $0,%xmm0,%xmm0
        shufpd $0,%xmm1,%xmm1
        shufpd $0,%xmm2,%xmm2
        shufpd $0,%xmm3,%xmm3
        shufpd $0,%xmm4,%xmm4
        shufpd $0,%xmm5,%xmm5
        movapd %xmm0,nb111_ixH1(%rsp)
        movapd %xmm1,nb111_iyH1(%rsp)
        movapd %xmm2,nb111_izH1(%rsp)
        movapd %xmm3,nb111_ixH2(%rsp)
        movapd %xmm4,nb111_iyH2(%rsp)
        movapd %xmm5,nb111_izH2(%rsp)

        ## clear vctot and i forces 
        xorpd %xmm4,%xmm4
        movapd %xmm4,nb111_vctot(%rsp)
        movapd %xmm4,nb111_Vvdwtot(%rsp)
        movapd %xmm4,nb111_fixO(%rsp)
        movapd %xmm4,nb111_fiyO(%rsp)
        movapd %xmm4,nb111_fizO(%rsp)
        movapd %xmm4,nb111_fixH1(%rsp)
        movapd %xmm4,nb111_fiyH1(%rsp)
        movapd %xmm4,nb111_fizH1(%rsp)
        movapd %xmm4,nb111_fixH2(%rsp)
        movapd %xmm4,nb111_fiyH2(%rsp)
        movapd %xmm4,nb111_fizH2(%rsp)

        movq  nb111_jindex(%rsp),%rax
        movl  (%rax,%rsi,4),%ecx             ## jindex[n] 
        movl  4(%rax,%rsi,4),%edx            ## jindex[n+1] 
        subl  %ecx,%edx              ## number of innerloop atoms 

        movq  nb111_pos(%rbp),%rsi
        movq  nb111_faction(%rbp),%rdi
        movq  nb111_jjnr(%rsp),%rax
        shll  $2,%ecx
        addq  %rcx,%rax
        movq  %rax,nb111_innerjjnr(%rsp)       ## pointer to jjnr[nj0] 
        movl  %edx,%ecx
        subl  $2,%edx
        addl  nb111_ninner(%rsp),%ecx
        movl  %ecx,nb111_ninner(%rsp)
        addl  $0,%edx
        movl  %edx,nb111_innerk(%rsp)      ## number of innerloop atoms 
        jge   _nb_kernel111_x86_64_sse2.nb111_unroll_loop
        jmp   _nb_kernel111_x86_64_sse2.nb111_checksingle
_nb_kernel111_x86_64_sse2.nb111_unroll_loop: 
        ## twice unrolled innerloop here 
        movq  nb111_innerjjnr(%rsp),%rdx       ## pointer to jjnr[k] 
        movl  (%rdx),%eax
        movl  4(%rdx),%ebx

        addq $8,nb111_innerjjnr(%rsp)                   ## advance pointer (unrolled 2) 

        movq nb111_charge(%rbp),%rsi     ## base of charge[] 

        movlpd (%rsi,%rax,8),%xmm3
        movhpd (%rsi,%rbx,8),%xmm3
        movapd %xmm3,%xmm4
        mulpd  nb111_iqO(%rsp),%xmm3
        mulpd  nb111_iqH(%rsp),%xmm4

        movapd  %xmm3,nb111_qqO(%rsp)
        movapd  %xmm4,nb111_qqH(%rsp)

        movq nb111_type(%rbp),%rsi
        movl (%rsi,%rax,4),%r8d
        movl (%rsi,%rbx,4),%r9d
        movq nb111_vdwparam(%rbp),%rsi
        shll %r8d
        shll %r9d
        movl nb111_ntia(%rsp),%edi
        addl %edi,%r8d
        addl %edi,%r9d

        movlpd (%rsi,%r8,8),%xmm6       ## c6a
        movlpd (%rsi,%r9,8),%xmm7       ## c6b
        movhpd 8(%rsi,%r8,8),%xmm6      ## c6a c12a 
        movhpd 8(%rsi,%r9,8),%xmm7      ## c6b c12b 
        movapd %xmm6,%xmm4
        unpcklpd %xmm7,%xmm4
        unpckhpd %xmm7,%xmm6

        movapd %xmm4,nb111_c6(%rsp)
        movapd %xmm6,nb111_c12(%rsp)

        movq nb111_pos(%rbp),%rsi        ## base of pos[] 

        lea  (%rax,%rax,2),%rax     ## replace jnr with j3 
        lea  (%rbx,%rbx,2),%rbx

        ## move j coordinates to local temp variables 
    movlpd (%rsi,%rax,8),%xmm0
    movlpd 8(%rsi,%rax,8),%xmm1
    movlpd 16(%rsi,%rax,8),%xmm2
    movhpd (%rsi,%rbx,8),%xmm0
    movhpd 8(%rsi,%rbx,8),%xmm1
    movhpd 16(%rsi,%rbx,8),%xmm2

    ## xmm0 = jx
    ## xmm1 = jy
    ## xmm2 = jz

    movapd %xmm0,%xmm3
    movapd %xmm1,%xmm4
    movapd %xmm2,%xmm5
    movapd %xmm0,%xmm6
    movapd %xmm1,%xmm7
    movapd %xmm2,%xmm8

    subpd nb111_ixO(%rsp),%xmm0
    subpd nb111_iyO(%rsp),%xmm1
    subpd nb111_izO(%rsp),%xmm2
    subpd nb111_ixH1(%rsp),%xmm3
    subpd nb111_iyH1(%rsp),%xmm4
    subpd nb111_izH1(%rsp),%xmm5
    subpd nb111_ixH2(%rsp),%xmm6
    subpd nb111_iyH2(%rsp),%xmm7
    subpd nb111_izH2(%rsp),%xmm8

        movapd %xmm0,nb111_dxO(%rsp)
        movapd %xmm1,nb111_dyO(%rsp)
        movapd %xmm2,nb111_dzO(%rsp)
        mulpd  %xmm0,%xmm0
        mulpd  %xmm1,%xmm1
        mulpd  %xmm2,%xmm2
        movapd %xmm3,nb111_dxH1(%rsp)
        movapd %xmm4,nb111_dyH1(%rsp)
        movapd %xmm5,nb111_dzH1(%rsp)
        mulpd  %xmm3,%xmm3
        mulpd  %xmm4,%xmm4
        mulpd  %xmm5,%xmm5
        movapd %xmm6,nb111_dxH2(%rsp)
        movapd %xmm7,nb111_dyH2(%rsp)
        movapd %xmm8,nb111_dzH2(%rsp)
        mulpd  %xmm6,%xmm6
        mulpd  %xmm7,%xmm7
        mulpd  %xmm8,%xmm8
        addpd  %xmm1,%xmm0
        addpd  %xmm2,%xmm0
        addpd  %xmm4,%xmm3
        addpd  %xmm5,%xmm3
    addpd  %xmm7,%xmm6
    addpd  %xmm8,%xmm6

        ## start doing invsqrt for j atoms
    cvtpd2ps %xmm0,%xmm1
    cvtpd2ps %xmm3,%xmm4
    cvtpd2ps %xmm6,%xmm7
        rsqrtps %xmm1,%xmm1
        rsqrtps %xmm4,%xmm4
    rsqrtps %xmm7,%xmm7
    cvtps2pd %xmm1,%xmm1
    cvtps2pd %xmm4,%xmm4
    cvtps2pd %xmm7,%xmm7

        movapd  %xmm1,%xmm2
        movapd  %xmm4,%xmm5
    movapd  %xmm7,%xmm8

        mulpd   %xmm1,%xmm1 ## lu*lu
        mulpd   %xmm4,%xmm4 ## lu*lu
    mulpd   %xmm7,%xmm7 ## lu*lu

        movapd  nb111_three(%rsp),%xmm9
        movapd  %xmm9,%xmm10
    movapd  %xmm9,%xmm11

        mulpd   %xmm0,%xmm1 ## rsq*lu*lu
        mulpd   %xmm3,%xmm4 ## rsq*lu*lu 
    mulpd   %xmm6,%xmm7 ## rsq*lu*lu

        subpd   %xmm1,%xmm9
        subpd   %xmm4,%xmm10
    subpd   %xmm7,%xmm11 ## 3-rsq*lu*lu

        mulpd   %xmm2,%xmm9
        mulpd   %xmm5,%xmm10
    mulpd   %xmm8,%xmm11 ## lu*(3-rsq*lu*lu)

        movapd  nb111_half(%rsp),%xmm15
        mulpd   %xmm15,%xmm9 ## first iteration for rinvO
        mulpd   %xmm15,%xmm10 ## first iteration for rinvH1
    mulpd   %xmm15,%xmm11 ## first iteration for rinvH2

    ## second iteration step    
        movapd  %xmm9,%xmm2
        movapd  %xmm10,%xmm5
    movapd  %xmm11,%xmm8

        mulpd   %xmm2,%xmm2 ## lu*lu
        mulpd   %xmm5,%xmm5 ## lu*lu
    mulpd   %xmm8,%xmm8 ## lu*lu

        movapd  nb111_three(%rsp),%xmm1
        movapd  %xmm1,%xmm4
    movapd  %xmm1,%xmm7

        mulpd   %xmm0,%xmm2 ## rsq*lu*lu
        mulpd   %xmm3,%xmm5 ## rsq*lu*lu 
    mulpd   %xmm6,%xmm8 ## rsq*lu*lu

        subpd   %xmm2,%xmm1
        subpd   %xmm5,%xmm4
    subpd   %xmm8,%xmm7 ## 3-rsq*lu*lu

        mulpd   %xmm1,%xmm9
        mulpd   %xmm4,%xmm10
    mulpd   %xmm7,%xmm11 ## lu*(3-rsq*lu*lu)

        movapd  nb111_half(%rsp),%xmm15
        mulpd   %xmm15,%xmm9 ##  rinvO 
        mulpd   %xmm15,%xmm10 ##   rinvH1
    mulpd   %xmm15,%xmm11 ##   rinvH2

        ## interactions 
    movapd %xmm9,%xmm0
    movapd %xmm10,%xmm1
    movapd %xmm11,%xmm2
    mulpd  %xmm9,%xmm9   ## rinvsq
    mulpd  %xmm10,%xmm10
    mulpd  %xmm11,%xmm11
    movapd %xmm9,%xmm12
    mulpd  %xmm12,%xmm12 ## rinv4
    mulpd  %xmm9,%xmm12 ## rinv6
    mulpd  nb111_qqO(%rsp),%xmm0
    mulpd  nb111_qqH(%rsp),%xmm1
    mulpd  nb111_qqH(%rsp),%xmm2
    movapd %xmm12,%xmm13 ## rinv6
    mulpd  %xmm12,%xmm12 ## rinv12
        mulpd  nb111_c6(%rsp),%xmm13
        mulpd  nb111_c12(%rsp),%xmm12
    movapd %xmm12,%xmm14
    subpd  %xmm13,%xmm14

        addpd  nb111_Vvdwtot(%rsp),%xmm14
        mulpd  nb111_six(%rsp),%xmm13
        mulpd  nb111_twelve(%rsp),%xmm12
        movapd %xmm14,nb111_Vvdwtot(%rsp)
    subpd  %xmm13,%xmm12 ## LJ fscal        

    addpd  %xmm0,%xmm12

    mulpd  %xmm12,%xmm9
    mulpd  %xmm1,%xmm10
    mulpd  %xmm2,%xmm11

    addpd nb111_vctot(%rsp),%xmm0
    addpd %xmm2,%xmm1
    addpd %xmm1,%xmm0
    movapd %xmm0,nb111_vctot(%rsp)

    ## move j forces to xmm0-xmm2
    movq nb111_faction(%rbp),%rdi
        movlpd (%rdi,%rax,8),%xmm0
        movlpd 8(%rdi,%rax,8),%xmm1
        movlpd 16(%rdi,%rax,8),%xmm2
        movhpd (%rdi,%rbx,8),%xmm0
        movhpd 8(%rdi,%rbx,8),%xmm1
        movhpd 16(%rdi,%rbx,8),%xmm2

    movapd %xmm9,%xmm7
    movapd %xmm9,%xmm8
    movapd %xmm11,%xmm13
    movapd %xmm11,%xmm14
    movapd %xmm11,%xmm15
    movapd %xmm10,%xmm11
    movapd %xmm10,%xmm12

        mulpd nb111_dxO(%rsp),%xmm7
        mulpd nb111_dyO(%rsp),%xmm8
        mulpd nb111_dzO(%rsp),%xmm9
        mulpd nb111_dxH1(%rsp),%xmm10
        mulpd nb111_dyH1(%rsp),%xmm11
        mulpd nb111_dzH1(%rsp),%xmm12
        mulpd nb111_dxH2(%rsp),%xmm13
        mulpd nb111_dyH2(%rsp),%xmm14
        mulpd nb111_dzH2(%rsp),%xmm15

    addpd %xmm7,%xmm0
    addpd %xmm8,%xmm1
    addpd %xmm9,%xmm2
    addpd nb111_fixO(%rsp),%xmm7
    addpd nb111_fiyO(%rsp),%xmm8
    addpd nb111_fizO(%rsp),%xmm9

    addpd %xmm10,%xmm0
    addpd %xmm11,%xmm1
    addpd %xmm12,%xmm2
    addpd nb111_fixH1(%rsp),%xmm10
    addpd nb111_fiyH1(%rsp),%xmm11
    addpd nb111_fizH1(%rsp),%xmm12

    addpd %xmm13,%xmm0
    addpd %xmm14,%xmm1
    addpd %xmm15,%xmm2
    addpd nb111_fixH2(%rsp),%xmm13
    addpd nb111_fiyH2(%rsp),%xmm14
    addpd nb111_fizH2(%rsp),%xmm15

    movapd %xmm7,nb111_fixO(%rsp)
    movapd %xmm8,nb111_fiyO(%rsp)
    movapd %xmm9,nb111_fizO(%rsp)
    movapd %xmm10,nb111_fixH1(%rsp)
    movapd %xmm11,nb111_fiyH1(%rsp)
    movapd %xmm12,nb111_fizH1(%rsp)
    movapd %xmm13,nb111_fixH2(%rsp)
    movapd %xmm14,nb111_fiyH2(%rsp)
    movapd %xmm15,nb111_fizH2(%rsp)

    ## store back j forces from xmm0-xmm2
        movlpd %xmm0,(%rdi,%rax,8)
        movlpd %xmm1,8(%rdi,%rax,8)
        movlpd %xmm2,16(%rdi,%rax,8)
        movhpd %xmm0,(%rdi,%rbx,8)
        movhpd %xmm1,8(%rdi,%rbx,8)
        movhpd %xmm2,16(%rdi,%rbx,8)

        ## should we do one more iteration? 
        subl $2,nb111_innerk(%rsp)
        jl   _nb_kernel111_x86_64_sse2.nb111_checksingle
        jmp  _nb_kernel111_x86_64_sse2.nb111_unroll_loop
_nb_kernel111_x86_64_sse2.nb111_checksingle: 
        movl  nb111_innerk(%rsp),%edx
        andl  $1,%edx
        jnz  _nb_kernel111_x86_64_sse2.nb111_dosingle
        jmp  _nb_kernel111_x86_64_sse2.nb111_updateouterdata
_nb_kernel111_x86_64_sse2.nb111_dosingle: 
        movq  nb111_innerjjnr(%rsp),%rdx       ## pointer to jjnr[k] 
        movl  (%rdx),%eax
        addq $4,nb111_innerjjnr(%rsp)

        movq nb111_charge(%rbp),%rsi     ## base of charge[] 

        xorpd %xmm3,%xmm3
        movlpd (%rsi,%rax,8),%xmm3
        movapd %xmm3,%xmm4
        mulpd  nb111_iqO(%rsp),%xmm3
        mulpd  nb111_iqH(%rsp),%xmm4

        movapd  %xmm3,nb111_qqO(%rsp)
        movapd  %xmm4,nb111_qqH(%rsp)

        movq nb111_type(%rbp),%rsi
        movl (%rsi,%rax,4),%r8d
        movq nb111_vdwparam(%rbp),%rsi
        shll %r8d
        movl nb111_ntia(%rsp),%edi
        addl %edi,%r8d

        movlpd (%rsi,%r8,8),%xmm6       ## c6a
        movhpd 8(%rsi,%r8,8),%xmm6      ## c6a c12a 

        xorpd %xmm7,%xmm7
        movapd %xmm6,%xmm4
        unpcklpd %xmm7,%xmm4
        unpckhpd %xmm7,%xmm6

        movapd %xmm4,nb111_c6(%rsp)
        movapd %xmm6,nb111_c12(%rsp)

        movq nb111_pos(%rbp),%rsi        ## base of pos[] 

        lea  (%rax,%rax,2),%rax     ## replace jnr with j3 

        ## move coordinates to xmm0-xmm2        
        movlpd (%rsi,%rax,8),%xmm4
        movlpd 8(%rsi,%rax,8),%xmm5
        movlpd 16(%rsi,%rax,8),%xmm6
    movapd %xmm4,%xmm0
    movapd %xmm5,%xmm1
    movapd %xmm6,%xmm2

        ## calc dr 
        subsd nb111_ixO(%rsp),%xmm4
        subsd nb111_iyO(%rsp),%xmm5
        subsd nb111_izO(%rsp),%xmm6

        ## store dr 
        movapd %xmm4,nb111_dxO(%rsp)
        movapd %xmm5,nb111_dyO(%rsp)
        movapd %xmm6,nb111_dzO(%rsp)
        ## square it 
        mulsd %xmm4,%xmm4
        mulsd %xmm5,%xmm5
        mulsd %xmm6,%xmm6
        addsd %xmm5,%xmm4
        addsd %xmm6,%xmm4
        movapd %xmm4,%xmm7
        ## rsqO in xmm7 

        ## move j coords to xmm4-xmm6 
        movapd %xmm0,%xmm4
        movapd %xmm1,%xmm5
        movapd %xmm2,%xmm6

        ## calc dr 
        subsd nb111_ixH1(%rsp),%xmm4
        subsd nb111_iyH1(%rsp),%xmm5
        subsd nb111_izH1(%rsp),%xmm6

        ## store dr 
        movapd %xmm4,nb111_dxH1(%rsp)
        movapd %xmm5,nb111_dyH1(%rsp)
        movapd %xmm6,nb111_dzH1(%rsp)
        ## square it 
        mulsd %xmm4,%xmm4
        mulsd %xmm5,%xmm5
        mulsd %xmm6,%xmm6
        addsd %xmm5,%xmm6
        addsd %xmm4,%xmm6
        ## rsqH1 in xmm6 

        ## move j coords to xmm3-xmm5
        movapd %xmm0,%xmm3
        movapd %xmm1,%xmm4
        movapd %xmm2,%xmm5

        ## calc dr 
        subsd nb111_ixH2(%rsp),%xmm3
        subsd nb111_iyH2(%rsp),%xmm4
        subsd nb111_izH2(%rsp),%xmm5

        ## store dr 
        movapd %xmm3,nb111_dxH2(%rsp)
        movapd %xmm4,nb111_dyH2(%rsp)
        movapd %xmm5,nb111_dzH2(%rsp)
        ## square it 
        mulsd %xmm3,%xmm3
        mulsd %xmm4,%xmm4
        mulsd %xmm5,%xmm5
        addsd %xmm4,%xmm5
        addsd %xmm3,%xmm5
        ## rsqH2 in xmm5, rsqH1 in xmm6, rsqO in xmm7 

        ## start with rsqO - put seed in xmm2 
        cvtsd2ss %xmm7,%xmm2
        rsqrtss %xmm2,%xmm2
        cvtss2sd %xmm2,%xmm2

        movapd  %xmm2,%xmm3
        mulsd   %xmm2,%xmm2
        movapd  nb111_three(%rsp),%xmm4
        mulsd   %xmm7,%xmm2     ## rsq*lu*lu 
        subsd   %xmm2,%xmm4     ## 30-rsq*lu*lu 
        mulsd   %xmm3,%xmm4     ## lu*(3-rsq*lu*lu) 
        mulsd   nb111_half(%rsp),%xmm4   ## iter1 ( new lu) 

        movapd %xmm4,%xmm3
        mulsd %xmm4,%xmm4       ## lu*lu 
        mulsd %xmm4,%xmm7       ## rsq*lu*lu 
        movapd nb111_three(%rsp),%xmm4
        subsd %xmm7,%xmm4       ## 3-rsq*lu*lu 
        mulsd %xmm3,%xmm4       ## lu*( 3-rsq*lu*lu) 
        mulsd nb111_half(%rsp),%xmm4   ## rinv 
        movapd  %xmm4,%xmm7     ## rinvO in xmm7 

        ## rsqH1 - seed in xmm2 
        cvtsd2ss %xmm6,%xmm2
        rsqrtss %xmm2,%xmm2
        cvtss2sd %xmm2,%xmm2

        movapd  %xmm2,%xmm3
        mulsd   %xmm2,%xmm2
        movapd  nb111_three(%rsp),%xmm4
        mulsd   %xmm6,%xmm2     ## rsq*lu*lu 
        subsd   %xmm2,%xmm4     ## 30-rsq*lu*lu 
        mulsd   %xmm3,%xmm4     ## lu*(3-rsq*lu*lu) 
        mulsd   nb111_half(%rsp),%xmm4   ## iter1 ( new lu) 

        movapd %xmm4,%xmm3
        mulsd %xmm4,%xmm4       ## lu*lu 
        mulsd %xmm4,%xmm6       ## rsq*lu*lu 
        movapd nb111_three(%rsp),%xmm4
        subsd %xmm6,%xmm4       ## 3-rsq*lu*lu 
        mulsd %xmm3,%xmm4       ## lu*( 3-rsq*lu*lu) 
        mulsd nb111_half(%rsp),%xmm4   ## rinv 
        movapd  %xmm4,%xmm6     ## rinvH1 in xmm6 

        ## rsqH2 - seed in xmm2 
        cvtsd2ss %xmm5,%xmm2
        rsqrtss %xmm2,%xmm2
        cvtss2sd %xmm2,%xmm2

        movapd  %xmm2,%xmm3
        mulsd   %xmm2,%xmm2
        movapd  nb111_three(%rsp),%xmm4
        mulsd   %xmm5,%xmm2     ## rsq*lu*lu 
        subsd   %xmm2,%xmm4     ## 30-rsq*lu*lu 
        mulsd   %xmm3,%xmm4     ## lu*(3-rsq*lu*lu) 
        mulsd   nb111_half(%rsp),%xmm4   ## iter1 ( new lu) 

        movapd %xmm4,%xmm3
        mulsd %xmm4,%xmm4       ## lu*lu 
        mulsd %xmm4,%xmm5       ## rsq*lu*lu 
        movapd nb111_three(%rsp),%xmm4
        subsd %xmm5,%xmm4       ## 3-rsq*lu*lu 
        mulsd %xmm3,%xmm4       ## lu*( 3-rsq*lu*lu) 
        mulsd nb111_half(%rsp),%xmm4   ## rinv 
        movapd  %xmm4,%xmm5     ## rinvH2 in xmm5 

        ## do O interactions 
        movapd  %xmm7,%xmm4
        mulsd   %xmm4,%xmm4     ## xmm7=rinv, xmm4=rinvsq 
        movapd %xmm4,%xmm1
        mulsd  %xmm4,%xmm1
        mulsd  %xmm4,%xmm1      ## xmm1=rinvsix 
        movapd %xmm1,%xmm2
        mulsd  %xmm2,%xmm2      ## xmm2=rinvtwelve 
        mulsd  nb111_qqO(%rsp),%xmm7    ## xmm7=vcoul 

        mulsd  nb111_c6(%rsp),%xmm1
        mulsd  nb111_c12(%rsp),%xmm2
        movapd %xmm2,%xmm3
        subsd  %xmm1,%xmm3      ## Vvdw=Vvdw12-Vvdw6            
        addsd  nb111_Vvdwtot(%rsp),%xmm3
        mulsd  nb111_six(%rsp),%xmm1
        mulsd  nb111_twelve(%rsp),%xmm2
        subsd  %xmm1,%xmm2
        addsd  %xmm7,%xmm2
        mulsd  %xmm2,%xmm4      ## total fsO in xmm4 

        addsd  nb111_vctot(%rsp),%xmm7

        movsd %xmm3,nb111_Vvdwtot(%rsp)
        movsd %xmm7,nb111_vctot(%rsp)

        movapd nb111_dxO(%rsp),%xmm0
        movapd nb111_dyO(%rsp),%xmm1
        movapd nb111_dzO(%rsp),%xmm2
        mulsd  %xmm4,%xmm0
        mulsd  %xmm4,%xmm1
        mulsd  %xmm4,%xmm2

        ## update O forces 
        movapd nb111_fixO(%rsp),%xmm3
        movapd nb111_fiyO(%rsp),%xmm4
        movapd nb111_fizO(%rsp),%xmm7
        addsd  %xmm0,%xmm3
        addsd  %xmm1,%xmm4
        addsd  %xmm2,%xmm7
        movsd %xmm3,nb111_fixO(%rsp)
        movsd %xmm4,nb111_fiyO(%rsp)
        movsd %xmm7,nb111_fizO(%rsp)
        ## update j forces with water O 
        movsd %xmm0,nb111_fjx(%rsp)
        movsd %xmm1,nb111_fjy(%rsp)
        movsd %xmm2,nb111_fjz(%rsp)

        ## H1 interactions 
        movapd  %xmm6,%xmm4
        mulsd   %xmm4,%xmm4     ## xmm6=rinv, xmm4=rinvsq 
        mulsd  nb111_qqH(%rsp),%xmm6    ## xmm6=vcoul 
        mulsd  %xmm6,%xmm4              ## total fsH1 in xmm4 

        addsd  nb111_vctot(%rsp),%xmm6

        movapd nb111_dxH1(%rsp),%xmm0
        movapd nb111_dyH1(%rsp),%xmm1
        movapd nb111_dzH1(%rsp),%xmm2
        movsd %xmm6,nb111_vctot(%rsp)
        mulsd  %xmm4,%xmm0
        mulsd  %xmm4,%xmm1
        mulsd  %xmm4,%xmm2

        ## update H1 forces 
        movapd nb111_fixH1(%rsp),%xmm3
        movapd nb111_fiyH1(%rsp),%xmm4
        movapd nb111_fizH1(%rsp),%xmm7
        addsd  %xmm0,%xmm3
        addsd  %xmm1,%xmm4
        addsd  %xmm2,%xmm7
        movsd %xmm3,nb111_fixH1(%rsp)
        movsd %xmm4,nb111_fiyH1(%rsp)
        movsd %xmm7,nb111_fizH1(%rsp)
        ## update j forces with water H1 
        addsd  nb111_fjx(%rsp),%xmm0
        addsd  nb111_fjy(%rsp),%xmm1
        addsd  nb111_fjz(%rsp),%xmm2
        movsd %xmm0,nb111_fjx(%rsp)
        movsd %xmm1,nb111_fjy(%rsp)
        movsd %xmm2,nb111_fjz(%rsp)

        ## H2 interactions 
        movapd  %xmm5,%xmm4
        mulsd   %xmm4,%xmm4     ## xmm5=rinv, xmm4=rinvsq 
        mulsd  nb111_qqH(%rsp),%xmm5    ## xmm5=vcoul 
        mulsd  %xmm5,%xmm4              ## total fsH1 in xmm4 

        addsd  nb111_vctot(%rsp),%xmm5

        movapd nb111_dxH2(%rsp),%xmm0
        movapd nb111_dyH2(%rsp),%xmm1
        movapd nb111_dzH2(%rsp),%xmm2
        movsd %xmm5,nb111_vctot(%rsp)
        mulsd  %xmm4,%xmm0
        mulsd  %xmm4,%xmm1
        mulsd  %xmm4,%xmm2

        ## update H2 forces 
        movapd nb111_fixH2(%rsp),%xmm3
        movapd nb111_fiyH2(%rsp),%xmm4
        movapd nb111_fizH2(%rsp),%xmm7
        addsd  %xmm0,%xmm3
        addsd  %xmm1,%xmm4
        addsd  %xmm2,%xmm7
        movsd %xmm3,nb111_fixH2(%rsp)
        movsd %xmm4,nb111_fiyH2(%rsp)
        movsd %xmm7,nb111_fizH2(%rsp)

        movq nb111_faction(%rbp),%rdi
        ## update j forces 
        addsd  nb111_fjx(%rsp),%xmm0
        addsd  nb111_fjy(%rsp),%xmm1
        addsd  nb111_fjz(%rsp),%xmm2
        movlpd (%rdi,%rax,8),%xmm3
        movlpd 8(%rdi,%rax,8),%xmm4
        movlpd 16(%rdi,%rax,8),%xmm5
        addsd %xmm0,%xmm3
        addsd %xmm1,%xmm4
        addsd %xmm2,%xmm5
        movlpd %xmm3,(%rdi,%rax,8)
        movlpd %xmm4,8(%rdi,%rax,8)
        movlpd %xmm5,16(%rdi,%rax,8)

_nb_kernel111_x86_64_sse2.nb111_updateouterdata: 
        movl  nb111_ii3(%rsp),%ecx
        movq  nb111_faction(%rbp),%rdi
        movq  nb111_fshift(%rbp),%rsi
        movl  nb111_is3(%rsp),%edx

        ## accumulate  Oi forces in xmm0, xmm1, xmm2 
        movapd nb111_fixO(%rsp),%xmm0
        movapd nb111_fiyO(%rsp),%xmm1
        movapd nb111_fizO(%rsp),%xmm2

        movhlps %xmm0,%xmm3
        movhlps %xmm1,%xmm4
        movhlps %xmm2,%xmm5
        addsd  %xmm3,%xmm0
        addsd  %xmm4,%xmm1
        addsd  %xmm5,%xmm2 ## sum is in low xmm0-xmm2 

        ## increment i force 
        movsd  (%rdi,%rcx,8),%xmm3
        movsd  8(%rdi,%rcx,8),%xmm4
        movsd  16(%rdi,%rcx,8),%xmm5
        subsd  %xmm0,%xmm3
        subsd  %xmm1,%xmm4
        subsd  %xmm2,%xmm5
        movsd  %xmm3,(%rdi,%rcx,8)
        movsd  %xmm4,8(%rdi,%rcx,8)
        movsd  %xmm5,16(%rdi,%rcx,8)

        ## accumulate force in xmm6/xmm7 for fshift 
        movapd %xmm0,%xmm6
        movsd %xmm2,%xmm7
        unpcklpd %xmm1,%xmm6

        ## accumulate H1i forces in xmm0, xmm1, xmm2 
        movapd nb111_fixH1(%rsp),%xmm0
        movapd nb111_fiyH1(%rsp),%xmm1
        movapd nb111_fizH1(%rsp),%xmm2

        movhlps %xmm0,%xmm3
        movhlps %xmm1,%xmm4
        movhlps %xmm2,%xmm5
        addsd  %xmm3,%xmm0
        addsd  %xmm4,%xmm1
        addsd  %xmm5,%xmm2 ## sum is in low xmm0-xmm2 

        ## increment i force 
        movsd  24(%rdi,%rcx,8),%xmm3
        movsd  32(%rdi,%rcx,8),%xmm4
        movsd  40(%rdi,%rcx,8),%xmm5
        subsd  %xmm0,%xmm3
        subsd  %xmm1,%xmm4
        subsd  %xmm2,%xmm5
        movsd  %xmm3,24(%rdi,%rcx,8)
        movsd  %xmm4,32(%rdi,%rcx,8)
        movsd  %xmm5,40(%rdi,%rcx,8)

        ## accumulate force in xmm6/xmm7 for fshift 
        addsd %xmm2,%xmm7
        unpcklpd %xmm1,%xmm0
        addpd %xmm0,%xmm6

        ## accumulate H2i forces in xmm0, xmm1, xmm2 
        movapd nb111_fixH2(%rsp),%xmm0
        movapd nb111_fiyH2(%rsp),%xmm1
        movapd nb111_fizH2(%rsp),%xmm2

        movhlps %xmm0,%xmm3
        movhlps %xmm1,%xmm4
        movhlps %xmm2,%xmm5
        addsd  %xmm3,%xmm0
        addsd  %xmm4,%xmm1
        addsd  %xmm5,%xmm2 ## sum is in low xmm0-xmm2 

        ## increment i force 
        movsd  48(%rdi,%rcx,8),%xmm3
        movsd  56(%rdi,%rcx,8),%xmm4
        movsd  64(%rdi,%rcx,8),%xmm5
        subsd  %xmm0,%xmm3
        subsd  %xmm1,%xmm4
        subsd  %xmm2,%xmm5
        movsd  %xmm3,48(%rdi,%rcx,8)
        movsd  %xmm4,56(%rdi,%rcx,8)
        movsd  %xmm5,64(%rdi,%rcx,8)

        ## accumulate force in xmm6/xmm7 for fshift 
        addsd %xmm2,%xmm7
        unpcklpd %xmm1,%xmm0
        addpd %xmm0,%xmm6

        ## increment fshift force 
        movlpd (%rsi,%rdx,8),%xmm3
        movhpd 8(%rsi,%rdx,8),%xmm3
        movsd  16(%rsi,%rdx,8),%xmm4
        subpd  %xmm6,%xmm3
        subsd  %xmm7,%xmm4
        movlpd %xmm3,(%rsi,%rdx,8)
        movhpd %xmm3,8(%rsi,%rdx,8)
        movsd  %xmm4,16(%rsi,%rdx,8)

        ## get n from stack
        movl nb111_n(%rsp),%esi
        ## get group index for i particle 
        movq  nb111_gid(%rbp),%rdx              ## base of gid[]
        movl  (%rdx,%rsi,4),%edx                ## ggid=gid[n]

        ## accumulate total potential energy and update it 
        movapd nb111_vctot(%rsp),%xmm7
        ## accumulate 
        movhlps %xmm7,%xmm6
        addsd  %xmm6,%xmm7      ## low xmm7 has the sum now 

        ## add earlier value from mem 
        movq  nb111_Vc(%rbp),%rax
        addsd (%rax,%rdx,8),%xmm7
        ## move back to mem 
        movsd %xmm7,(%rax,%rdx,8)

        ## accumulate total lj energy and update it 
        movapd nb111_Vvdwtot(%rsp),%xmm7
        ## accumulate 
        movhlps %xmm7,%xmm6
        addsd  %xmm6,%xmm7      ## low xmm7 has the sum now 

        ## add earlier value from mem 
        movq  nb111_Vvdw(%rbp),%rax
        addsd (%rax,%rdx,8),%xmm7
        ## move back to mem 
        movsd %xmm7,(%rax,%rdx,8)

       ## finish if last 
        movl nb111_nn1(%rsp),%ecx
        ## esi already loaded with n
        incl %esi
        subl %esi,%ecx
        jz _nb_kernel111_x86_64_sse2.nb111_outerend

        ## not last, iterate outer loop once more!  
        movl %esi,nb111_n(%rsp)
        jmp _nb_kernel111_x86_64_sse2.nb111_outer
_nb_kernel111_x86_64_sse2.nb111_outerend: 
        ## check if more outer neighborlists remain
        movl  nb111_nri(%rsp),%ecx
        ## esi already loaded with n above
        subl  %esi,%ecx
        jz _nb_kernel111_x86_64_sse2.nb111_end
        ## non-zero, do one more workunit
        jmp   _nb_kernel111_x86_64_sse2.nb111_threadloop
_nb_kernel111_x86_64_sse2.nb111_end: 
        movl nb111_nouter(%rsp),%eax
        movl nb111_ninner(%rsp),%ebx
        movq nb111_outeriter(%rbp),%rcx
        movq nb111_inneriter(%rbp),%rdx
        movl %eax,(%rcx)
        movl %ebx,(%rdx)

        addq $792,%rsp
        emms


        pop %r15
        pop %r14
        pop %r13
        pop %r12

        pop %rbx
        pop    %rbp
        ret






.globl nb_kernel111nf_x86_64_sse2
.globl _nb_kernel111nf_x86_64_sse2
nb_kernel111nf_x86_64_sse2:     
_nb_kernel111nf_x86_64_sse2:    
##      Room for return address and rbp (16 bytes)
.set nb111nf_fshift, 16
.set nb111nf_gid, 24
.set nb111nf_pos, 32
.set nb111nf_faction, 40
.set nb111nf_charge, 48
.set nb111nf_p_facel, 56
.set nb111nf_argkrf, 64
.set nb111nf_argcrf, 72
.set nb111nf_Vc, 80
.set nb111nf_type, 88
.set nb111nf_p_ntype, 96
.set nb111nf_vdwparam, 104
.set nb111nf_Vvdw, 112
.set nb111nf_p_tabscale, 120
.set nb111nf_VFtab, 128
.set nb111nf_invsqrta, 136
.set nb111nf_dvda, 144
.set nb111nf_p_gbtabscale, 152
.set nb111nf_GBtab, 160
.set nb111nf_p_nthreads, 168
.set nb111nf_count, 176
.set nb111nf_mtx, 184
.set nb111nf_outeriter, 192
.set nb111nf_inneriter, 200
.set nb111nf_work, 208
        ## stack offsets for local variables  
        ## bottom of stack is cache-aligned for sse use 
.set nb111nf_ixO, 0
.set nb111nf_iyO, 16
.set nb111nf_izO, 32
.set nb111nf_ixH1, 48
.set nb111nf_iyH1, 64
.set nb111nf_izH1, 80
.set nb111nf_ixH2, 96
.set nb111nf_iyH2, 112
.set nb111nf_izH2, 128
.set nb111nf_iqO, 144
.set nb111nf_iqH, 160
.set nb111nf_qqO, 176
.set nb111nf_qqH, 192
.set nb111nf_c6, 208
.set nb111nf_c12, 224
.set nb111nf_vctot, 240
.set nb111nf_Vvdwtot, 256
.set nb111nf_half, 272
.set nb111nf_three, 288
.set nb111nf_is3, 304
.set nb111nf_ii3, 308
.set nb111nf_nri, 312
.set nb111nf_iinr, 320
.set nb111nf_jindex, 328
.set nb111nf_jjnr, 336
.set nb111nf_shift, 344
.set nb111nf_shiftvec, 352
.set nb111nf_facel, 360
.set nb111nf_innerjjnr, 368
.set nb111nf_ntia, 376
.set nb111nf_innerk, 380
.set nb111nf_n, 384
.set nb111nf_nn1, 388
.set nb111nf_nouter, 392
.set nb111nf_ninner, 396
        push %rbp
        movq %rsp,%rbp
        push %rbx

        emms

        push %r12
        push %r13
        push %r14
        push %r15

        subq $408,%rsp          ## local variable stack space (n*16+8)

        ## zero 32-bit iteration counters
        movl $0,%eax
        movl %eax,nb111nf_nouter(%rsp)
        movl %eax,nb111nf_ninner(%rsp)

        movl (%rdi),%edi
        movl %edi,nb111nf_nri(%rsp)
        movq %rsi,nb111nf_iinr(%rsp)
        movq %rdx,nb111nf_jindex(%rsp)
        movq %rcx,nb111nf_jjnr(%rsp)
        movq %r8,nb111nf_shift(%rsp)
        movq %r9,nb111nf_shiftvec(%rsp)
        movq nb111nf_p_facel(%rbp),%rsi
        movsd (%rsi),%xmm0
        movsd %xmm0,nb111nf_facel(%rsp)

        ## create constant floating-point factors on stack
        movl $0x00000000,%eax   ## lower half of double half IEEE (hex)
        movl $0x3fe00000,%ebx
        movl %eax,nb111nf_half(%rsp)
        movl %ebx,nb111nf_half+4(%rsp)
        movsd nb111nf_half(%rsp),%xmm1
        shufpd $0,%xmm1,%xmm1  ## splat to all elements
        movapd %xmm1,%xmm3
        addpd  %xmm3,%xmm3      ## one
        movapd %xmm3,%xmm2
        addpd  %xmm2,%xmm2      ## two
        addpd  %xmm2,%xmm3      ## three
        movapd %xmm1,nb111nf_half(%rsp)
        movapd %xmm3,nb111nf_three(%rsp)

        ## assume we have at least one i particle - start directly 
        movq  nb111nf_iinr(%rsp),%rcx         ## rcx = pointer into iinr[]      
        movl  (%rcx),%ebx           ## ebx =ii 

        movq  nb111nf_charge(%rbp),%rdx
        movsd (%rdx,%rbx,8),%xmm3
        movsd 8(%rdx,%rbx,8),%xmm4
        movq nb111nf_p_facel(%rbp),%rsi
        movsd (%rsi),%xmm0
        movsd nb111nf_facel(%rsp),%xmm5
        mulsd  %xmm5,%xmm3
        mulsd  %xmm5,%xmm4

        shufpd $0,%xmm3,%xmm3
        shufpd $0,%xmm4,%xmm4
        movapd %xmm3,nb111nf_iqO(%rsp)
        movapd %xmm4,nb111nf_iqH(%rsp)

        movq  nb111nf_type(%rbp),%rdx
        movl  (%rdx,%rbx,4),%ecx
        shll  %ecx
        movq nb111nf_p_ntype(%rbp),%rdi
        imull (%rdi),%ecx     ## rcx = ntia = 2*ntype*type[ii0] 
        movl  %ecx,nb111nf_ntia(%rsp)
_nb_kernel111nf_x86_64_sse2.nb111nf_threadloop: 
        movq  nb111nf_count(%rbp),%rsi          ## pointer to sync counter
        movl  (%rsi),%eax
_nb_kernel111nf_x86_64_sse2.nb111nf_spinlock: 
        movl  %eax,%ebx                         ## ebx=*count=nn0
        addl  $1,%ebx                           ## ebx=nn1=nn0+10
        lock 
        cmpxchgl %ebx,(%rsi)                    ## write nn1 to *counter,
                                                ## if it hasnt changed.
                                                ## or reread *counter to eax.
        pause                                   ## -> better p4 performance
        jnz _nb_kernel111nf_x86_64_sse2.nb111nf_spinlock

        ## if(nn1>nri) nn1=nri
        movl nb111nf_nri(%rsp),%ecx
        movl %ecx,%edx
        subl %ebx,%ecx
        cmovlel %edx,%ebx                       ## if(nn1>nri) nn1=nri
        ## Cleared the spinlock if we got here.
        ## eax contains nn0, ebx contains nn1.
        movl %eax,nb111nf_n(%rsp)
        movl %ebx,nb111nf_nn1(%rsp)
        subl %eax,%ebx                          ## calc number of outer lists
        movl %eax,%esi                          ## copy n to esi
        jg  _nb_kernel111nf_x86_64_sse2.nb111nf_outerstart
        jmp _nb_kernel111nf_x86_64_sse2.nb111nf_end

_nb_kernel111nf_x86_64_sse2.nb111nf_outerstart: 
        ## ebx contains number of outer iterations
        addl nb111nf_nouter(%rsp),%ebx
        movl %ebx,nb111nf_nouter(%rsp)

_nb_kernel111nf_x86_64_sse2.nb111nf_outer: 
        movq  nb111nf_shift(%rsp),%rax        ## rax = pointer into shift[] 
        movl  (%rax,%rsi,4),%ebx        ## rbx=shift[n] 

        lea  (%rbx,%rbx,2),%rbx    ## rbx=3*is 

        movq  nb111nf_shiftvec(%rsp),%rax     ## rax = base of shiftvec[] 

        movsd (%rax,%rbx,8),%xmm0
        movsd 8(%rax,%rbx,8),%xmm1
        movsd 16(%rax,%rbx,8),%xmm2

        movq  nb111nf_iinr(%rsp),%rcx         ## rcx = pointer into iinr[]      
        movl  (%rcx,%rsi,4),%ebx    ## ebx =ii 

        movapd %xmm0,%xmm3
        movapd %xmm1,%xmm4
        movapd %xmm2,%xmm5

        lea  (%rbx,%rbx,2),%rbx        ## rbx = 3*ii=ii3 
        movq  nb111nf_pos(%rbp),%rax      ## rax = base of pos[]  
        movl  %ebx,nb111nf_ii3(%rsp)

        addsd (%rax,%rbx,8),%xmm3
        addsd 8(%rax,%rbx,8),%xmm4
        addsd 16(%rax,%rbx,8),%xmm5
        shufpd $0,%xmm3,%xmm3
        shufpd $0,%xmm4,%xmm4
        shufpd $0,%xmm5,%xmm5
        movapd %xmm3,nb111nf_ixO(%rsp)
        movapd %xmm4,nb111nf_iyO(%rsp)
        movapd %xmm5,nb111nf_izO(%rsp)

        movsd %xmm0,%xmm3
        movsd %xmm1,%xmm4
        movsd %xmm2,%xmm5
        addsd 24(%rax,%rbx,8),%xmm0
        addsd 32(%rax,%rbx,8),%xmm1
        addsd 40(%rax,%rbx,8),%xmm2
        addsd 48(%rax,%rbx,8),%xmm3
        addsd 56(%rax,%rbx,8),%xmm4
        addsd 64(%rax,%rbx,8),%xmm5

        shufpd $0,%xmm0,%xmm0
        shufpd $0,%xmm1,%xmm1
        shufpd $0,%xmm2,%xmm2
        shufpd $0,%xmm3,%xmm3
        shufpd $0,%xmm4,%xmm4
        shufpd $0,%xmm5,%xmm5
        movapd %xmm0,nb111nf_ixH1(%rsp)
        movapd %xmm1,nb111nf_iyH1(%rsp)
        movapd %xmm2,nb111nf_izH1(%rsp)
        movapd %xmm3,nb111nf_ixH2(%rsp)
        movapd %xmm4,nb111nf_iyH2(%rsp)
        movapd %xmm5,nb111nf_izH2(%rsp)

        ## clear vctot 
        xorpd %xmm4,%xmm4
        movapd %xmm4,nb111nf_vctot(%rsp)
        movapd %xmm4,nb111nf_Vvdwtot(%rsp)

        movq  nb111nf_jindex(%rsp),%rax
        movl  (%rax,%rsi,4),%ecx             ## jindex[n] 
        movl  4(%rax,%rsi,4),%edx            ## jindex[n+1] 
        subl  %ecx,%edx              ## number of innerloop atoms 

        movq  nb111nf_pos(%rbp),%rsi
        movq  nb111nf_jjnr(%rsp),%rax
        shll  $2,%ecx
        addq  %rcx,%rax
        movq  %rax,nb111nf_innerjjnr(%rsp)       ## pointer to jjnr[nj0] 
        movl  %edx,%ecx
        subl  $2,%edx
        addl  nb111nf_ninner(%rsp),%ecx
        movl  %ecx,nb111nf_ninner(%rsp)
        addl  $0,%edx
        movl  %edx,nb111nf_innerk(%rsp)      ## number of innerloop atoms 
        jge   _nb_kernel111nf_x86_64_sse2.nb111nf_unroll_loop
        jmp   _nb_kernel111nf_x86_64_sse2.nb111nf_checksingle
_nb_kernel111nf_x86_64_sse2.nb111nf_unroll_loop: 
        ## twice unrolled innerloop here 
        movq  nb111nf_innerjjnr(%rsp),%rdx       ## pointer to jjnr[k] 
        movl  (%rdx),%eax
        movl  4(%rdx),%ebx

        addq $8,nb111nf_innerjjnr(%rsp)                 ## advance pointer (unrolled 2) 

        movq nb111nf_charge(%rbp),%rsi     ## base of charge[] 

        movlpd (%rsi,%rax,8),%xmm3
        movhpd (%rsi,%rbx,8),%xmm3
        movapd %xmm3,%xmm4
        mulpd  nb111nf_iqO(%rsp),%xmm3
        mulpd  nb111nf_iqH(%rsp),%xmm4

        movd  %eax,%mm0         ## use mmx registers as temp storage 
        movd  %ebx,%mm1

        movapd  %xmm3,nb111nf_qqO(%rsp)
        movapd  %xmm4,nb111nf_qqH(%rsp)

        movq nb111nf_type(%rbp),%rsi
        movl (%rsi,%rax,4),%eax
        movl (%rsi,%rbx,4),%ebx
        movq nb111nf_vdwparam(%rbp),%rsi
        shll %eax
        shll %ebx
        movl nb111nf_ntia(%rsp),%edi
        addl %edi,%eax
        addl %edi,%ebx

        movlpd (%rsi,%rax,8),%xmm6      ## c6a
        movlpd (%rsi,%rbx,8),%xmm7      ## c6b
        movhpd 8(%rsi,%rax,8),%xmm6     ## c6a c12a 
        movhpd 8(%rsi,%rbx,8),%xmm7     ## c6b c12b 
        movapd %xmm6,%xmm4
        unpcklpd %xmm7,%xmm4
        unpckhpd %xmm7,%xmm6

        movd  %mm0,%eax
        movd  %mm1,%ebx
        movapd %xmm4,nb111nf_c6(%rsp)
        movapd %xmm6,nb111nf_c12(%rsp)

        movq nb111nf_pos(%rbp),%rsi        ## base of pos[] 

        lea  (%rax,%rax,2),%rax     ## replace jnr with j3 
        lea  (%rbx,%rbx,2),%rbx

        ## move two coordinates to xmm0-xmm2 
        movlpd (%rsi,%rax,8),%xmm0
        movlpd 8(%rsi,%rax,8),%xmm1
        movlpd 16(%rsi,%rax,8),%xmm2
        movhpd (%rsi,%rbx,8),%xmm0
        movhpd 8(%rsi,%rbx,8),%xmm1
        movhpd 16(%rsi,%rbx,8),%xmm2

        ## move ixO-izO to xmm4-xmm6 
        movapd nb111nf_ixO(%rsp),%xmm4
        movapd nb111nf_iyO(%rsp),%xmm5
        movapd nb111nf_izO(%rsp),%xmm6

        ## calc dr 
        subpd %xmm0,%xmm4
        subpd %xmm1,%xmm5
        subpd %xmm2,%xmm6

        ## square it 
        mulpd %xmm4,%xmm4
        mulpd %xmm5,%xmm5
        mulpd %xmm6,%xmm6
        addpd %xmm5,%xmm4
        addpd %xmm6,%xmm4
        movapd %xmm4,%xmm7
        ## rsqO in xmm7 

        ## move ixH1-izH1 to xmm4-xmm6 
        movapd nb111nf_ixH1(%rsp),%xmm4
        movapd nb111nf_iyH1(%rsp),%xmm5
        movapd nb111nf_izH1(%rsp),%xmm6

        ## calc dr 
        subpd %xmm0,%xmm4
        subpd %xmm1,%xmm5
        subpd %xmm2,%xmm6

        ## square it 
        mulpd %xmm4,%xmm4
        mulpd %xmm5,%xmm5
        mulpd %xmm6,%xmm6
        addpd %xmm5,%xmm6
        addpd %xmm4,%xmm6
        ## rsqH1 in xmm6 

        ## move ixH2-izH2 to xmm3-xmm5  
        movapd nb111nf_ixH2(%rsp),%xmm3
        movapd nb111nf_iyH2(%rsp),%xmm4
        movapd nb111nf_izH2(%rsp),%xmm5

        ## calc dr 
        subpd %xmm0,%xmm3
        subpd %xmm1,%xmm4
        subpd %xmm2,%xmm5

        ## square it 
        mulpd %xmm3,%xmm3
        mulpd %xmm4,%xmm4
        mulpd %xmm5,%xmm5
        addpd %xmm4,%xmm5
        addpd %xmm3,%xmm5
        ## rsqH2 in xmm5, rsqH1 in xmm6, rsqO in xmm7 

        ## start with rsqO - put seed in xmm2 
        cvtpd2ps %xmm7,%xmm2
        rsqrtps %xmm2,%xmm2
        cvtps2pd %xmm2,%xmm2

        movapd  %xmm2,%xmm3
        mulpd   %xmm2,%xmm2
        movapd  nb111nf_three(%rsp),%xmm4
        mulpd   %xmm7,%xmm2     ## rsq*lu*lu 
        subpd   %xmm2,%xmm4     ## 30-rsq*lu*lu 
        mulpd   %xmm3,%xmm4     ## lu*(3-rsq*lu*lu) 
        mulpd   nb111nf_half(%rsp),%xmm4   ## iter1 ( new lu) 

        movapd %xmm4,%xmm3
        mulpd %xmm4,%xmm4       ## lu*lu 
        mulpd %xmm4,%xmm7       ## rsq*lu*lu 
        movapd nb111nf_three(%rsp),%xmm4
        subpd %xmm7,%xmm4       ## 3-rsq*lu*lu 
        mulpd %xmm3,%xmm4       ## lu*( 3-rsq*lu*lu) 
        mulpd nb111nf_half(%rsp),%xmm4   ## rinv 
        movapd  %xmm4,%xmm7     ## rinvO in xmm7 

        ## rsqH1 - seed in xmm2 
        cvtpd2ps %xmm6,%xmm2
        rsqrtps %xmm2,%xmm2
        cvtps2pd %xmm2,%xmm2

        movapd  %xmm2,%xmm3
        mulpd   %xmm2,%xmm2
        movapd  nb111nf_three(%rsp),%xmm4
        mulpd   %xmm6,%xmm2     ## rsq*lu*lu 
        subpd   %xmm2,%xmm4     ## 30-rsq*lu*lu 
        mulpd   %xmm3,%xmm4     ## lu*(3-rsq*lu*lu) 
        mulpd   nb111nf_half(%rsp),%xmm4   ## iter1 ( new lu) 

        movapd %xmm4,%xmm3
        mulpd %xmm4,%xmm4       ## lu*lu 
        mulpd %xmm4,%xmm6       ## rsq*lu*lu 
        movapd nb111nf_three(%rsp),%xmm4
        subpd %xmm6,%xmm4       ## 3-rsq*lu*lu 
        mulpd %xmm3,%xmm4       ## lu*( 3-rsq*lu*lu) 
        mulpd nb111nf_half(%rsp),%xmm4   ## rinv 
        movapd  %xmm4,%xmm6     ## rinvH1 in xmm6 

        ## rsqH2 - seed in xmm2 
        cvtpd2ps %xmm5,%xmm2
        rsqrtps %xmm2,%xmm2
        cvtps2pd %xmm2,%xmm2

        movapd  %xmm2,%xmm3
        mulpd   %xmm2,%xmm2
        movapd  nb111nf_three(%rsp),%xmm4
        mulpd   %xmm5,%xmm2     ## rsq*lu*lu 
        subpd   %xmm2,%xmm4     ## 30-rsq*lu*lu 
        mulpd   %xmm3,%xmm4     ## lu*(3-rsq*lu*lu) 
        mulpd   nb111nf_half(%rsp),%xmm4   ## iter1 ( new lu) 

        movapd %xmm4,%xmm3
        mulpd %xmm4,%xmm4       ## lu*lu 
        mulpd %xmm4,%xmm5       ## rsq*lu*lu 
        movapd nb111nf_three(%rsp),%xmm4
        subpd %xmm5,%xmm4       ## 3-rsq*lu*lu 
        mulpd %xmm3,%xmm4       ## lu*( 3-rsq*lu*lu) 
        mulpd nb111nf_half(%rsp),%xmm4   ## rinv 
        movapd  %xmm4,%xmm5     ## rinvH2 in xmm5 

        ## do O interactions 
        movapd  %xmm7,%xmm4
        mulpd   %xmm4,%xmm4     ## xmm7=rinv, xmm4=rinvsq 
        movapd %xmm4,%xmm1
        mulpd  %xmm4,%xmm1
        mulpd  %xmm4,%xmm1      ## xmm1=rinvsix 
        movapd %xmm1,%xmm2
        mulpd  %xmm2,%xmm2      ## xmm2=rinvtwelve 
        mulpd  nb111nf_qqO(%rsp),%xmm7          ## xmm7=vcoul 

        mulpd  nb111nf_c6(%rsp),%xmm1
        mulpd  nb111nf_c12(%rsp),%xmm2
        movapd %xmm2,%xmm3
        subpd  %xmm1,%xmm3      ## Vvdw=Vvdw12-Vvdw6            
        addpd  nb111nf_Vvdwtot(%rsp),%xmm3
        addpd  nb111nf_vctot(%rsp),%xmm7
        movapd %xmm3,nb111nf_Vvdwtot(%rsp)
        movapd %xmm7,nb111nf_vctot(%rsp)

        ## H1 interactions 
        mulpd  nb111nf_qqH(%rsp),%xmm6          ## xmm6=vcoul 
        addpd  nb111nf_vctot(%rsp),%xmm6
        movapd %xmm6,nb111nf_vctot(%rsp)

        ## H2 interactions 
        mulpd  nb111nf_qqH(%rsp),%xmm5          ## xmm5=vcoul 
        addpd  nb111nf_vctot(%rsp),%xmm5
        movapd %xmm5,nb111nf_vctot(%rsp)

        ## should we do one more iteration? 
        subl $2,nb111nf_innerk(%rsp)
        jl    _nb_kernel111nf_x86_64_sse2.nb111nf_checksingle
        jmp   _nb_kernel111nf_x86_64_sse2.nb111nf_unroll_loop
_nb_kernel111nf_x86_64_sse2.nb111nf_checksingle: 
        movl  nb111nf_innerk(%rsp),%edx
        andl  $1,%edx
        jnz   _nb_kernel111nf_x86_64_sse2.nb111nf_dosingle
        jmp   _nb_kernel111nf_x86_64_sse2.nb111nf_updateouterdata
_nb_kernel111nf_x86_64_sse2.nb111nf_dosingle: 
        movq  nb111nf_innerjjnr(%rsp),%rdx       ## pointer to jjnr[k] 
        movl  (%rdx),%eax
        addq $4,nb111nf_innerjjnr(%rsp)

        movq nb111nf_charge(%rbp),%rsi     ## base of charge[] 

        xorpd %xmm3,%xmm3
        movlpd (%rsi,%rax,8),%xmm3
        movapd %xmm3,%xmm4
        mulpd  nb111nf_iqO(%rsp),%xmm3
        mulpd  nb111nf_iqH(%rsp),%xmm4

        movd  %eax,%mm0         ## use mmx registers as temp storage 

        movapd  %xmm3,nb111nf_qqO(%rsp)
        movapd  %xmm4,nb111nf_qqH(%rsp)

        movq nb111nf_type(%rbp),%rsi
        movl (%rsi,%rax,4),%eax
        movq nb111nf_vdwparam(%rbp),%rsi
        shll %eax
        movl nb111nf_ntia(%rsp),%edi
        addl %edi,%eax

        movlpd (%rsi,%rax,8),%xmm6      ## c6a
        movhpd 8(%rsi,%rax,8),%xmm6     ## c6a c12a 

        xorpd %xmm7,%xmm7
        movapd %xmm6,%xmm4
        unpcklpd %xmm7,%xmm4
        unpckhpd %xmm7,%xmm6

        movd  %mm0,%eax
        movd  %mm1,%ebx
        movapd %xmm4,nb111nf_c6(%rsp)
        movapd %xmm6,nb111nf_c12(%rsp)

        movq nb111nf_pos(%rbp),%rsi        ## base of pos[] 

        lea  (%rax,%rax,2),%rax     ## replace jnr with j3 

        ## move coordinates to xmm0-xmm2 
        movlpd (%rsi,%rax,8),%xmm0
        movlpd 8(%rsi,%rax,8),%xmm1
        movlpd 16(%rsi,%rax,8),%xmm2

        ## move ixO-izO to xmm4-xmm6 
        movapd nb111nf_ixO(%rsp),%xmm4
        movapd nb111nf_iyO(%rsp),%xmm5
        movapd nb111nf_izO(%rsp),%xmm6

        ## calc dr 
        subsd %xmm0,%xmm4
        subsd %xmm1,%xmm5
        subsd %xmm2,%xmm6

        ## square it 
        mulsd %xmm4,%xmm4
        mulsd %xmm5,%xmm5
        mulsd %xmm6,%xmm6
        addsd %xmm5,%xmm4
        addsd %xmm6,%xmm4
        movapd %xmm4,%xmm7
        ## rsqO in xmm7 

        ## move ixH1-izH1 to xmm4-xmm6 
        movapd nb111nf_ixH1(%rsp),%xmm4
        movapd nb111nf_iyH1(%rsp),%xmm5
        movapd nb111nf_izH1(%rsp),%xmm6

        ## calc dr 
        subsd %xmm0,%xmm4
        subsd %xmm1,%xmm5
        subsd %xmm2,%xmm6

        ## square it 
        mulsd %xmm4,%xmm4
        mulsd %xmm5,%xmm5
        mulsd %xmm6,%xmm6
        addsd %xmm5,%xmm6
        addsd %xmm4,%xmm6
        ## rsqH1 in xmm6 

        ## move ixH2-izH2 to xmm3-xmm5  
        movapd nb111nf_ixH2(%rsp),%xmm3
        movapd nb111nf_iyH2(%rsp),%xmm4
        movapd nb111nf_izH2(%rsp),%xmm5

        ## calc dr 
        subsd %xmm0,%xmm3
        subsd %xmm1,%xmm4
        subsd %xmm2,%xmm5

        ## square it 
        mulsd %xmm3,%xmm3
        mulsd %xmm4,%xmm4
        mulsd %xmm5,%xmm5
        addsd %xmm4,%xmm5
        addsd %xmm3,%xmm5
        ## rsqH2 in xmm5, rsqH1 in xmm6, rsqO in xmm7 

        ## start with rsqO - put seed in xmm2 
        cvtsd2ss %xmm7,%xmm2
        rsqrtss %xmm2,%xmm2
        cvtss2sd %xmm2,%xmm2

        movapd  %xmm2,%xmm3
        mulsd   %xmm2,%xmm2
        movapd  nb111nf_three(%rsp),%xmm4
        mulsd   %xmm7,%xmm2     ## rsq*lu*lu 
        subsd   %xmm2,%xmm4     ## 30-rsq*lu*lu 
        mulsd   %xmm3,%xmm4     ## lu*(3-rsq*lu*lu) 
        mulsd   nb111nf_half(%rsp),%xmm4   ## iter1 ( new lu) 

        movapd %xmm4,%xmm3
        mulsd %xmm4,%xmm4       ## lu*lu 
        mulsd %xmm4,%xmm7       ## rsq*lu*lu 
        movapd nb111nf_three(%rsp),%xmm4
        subsd %xmm7,%xmm4       ## 3-rsq*lu*lu 
        mulsd %xmm3,%xmm4       ## lu*( 3-rsq*lu*lu) 
        mulsd nb111nf_half(%rsp),%xmm4   ## rinv 
        movapd  %xmm4,%xmm7     ## rinvO in xmm7 

        ## rsqH1 - seed in xmm2 
        cvtsd2ss %xmm6,%xmm2
        rsqrtss %xmm2,%xmm2
        cvtss2sd %xmm2,%xmm2

        movapd  %xmm2,%xmm3
        mulsd   %xmm2,%xmm2
        movapd  nb111nf_three(%rsp),%xmm4
        mulsd   %xmm6,%xmm2     ## rsq*lu*lu 
        subsd   %xmm2,%xmm4     ## 30-rsq*lu*lu 
        mulsd   %xmm3,%xmm4     ## lu*(3-rsq*lu*lu) 
        mulsd   nb111nf_half(%rsp),%xmm4   ## iter1 ( new lu) 

        movapd %xmm4,%xmm3
        mulsd %xmm4,%xmm4       ## lu*lu 
        mulsd %xmm4,%xmm6       ## rsq*lu*lu 
        movapd nb111nf_three(%rsp),%xmm4
        subsd %xmm6,%xmm4       ## 3-rsq*lu*lu 
        mulsd %xmm3,%xmm4       ## lu*( 3-rsq*lu*lu) 
        mulsd nb111nf_half(%rsp),%xmm4   ## rinv 
        movapd  %xmm4,%xmm6     ## rinvH1 in xmm6 

        ## rsqH2 - seed in xmm2 
        cvtsd2ss %xmm5,%xmm2
        rsqrtss %xmm2,%xmm2
        cvtss2sd %xmm2,%xmm2

        movapd  %xmm2,%xmm3
        mulsd   %xmm2,%xmm2
        movapd  nb111nf_three(%rsp),%xmm4
        mulsd   %xmm5,%xmm2     ## rsq*lu*lu 
        subsd   %xmm2,%xmm4     ## 30-rsq*lu*lu 
        mulsd   %xmm3,%xmm4     ## lu*(3-rsq*lu*lu) 
        mulsd   nb111nf_half(%rsp),%xmm4   ## iter1 ( new lu) 

        movapd %xmm4,%xmm3
        mulsd %xmm4,%xmm4       ## lu*lu 
        mulsd %xmm4,%xmm5       ## rsq*lu*lu 
        movapd nb111nf_three(%rsp),%xmm4
        subsd %xmm5,%xmm4       ## 3-rsq*lu*lu 
        mulsd %xmm3,%xmm4       ## lu*( 3-rsq*lu*lu) 
        mulsd nb111nf_half(%rsp),%xmm4   ## rinv 
        movapd  %xmm4,%xmm5     ## rinvH2 in xmm5 

        ## do O interactions 
        movapd  %xmm7,%xmm4
        mulsd   %xmm4,%xmm4     ## xmm7=rinv, xmm4=rinvsq 
        movapd %xmm4,%xmm1
        mulsd  %xmm4,%xmm1
        mulsd  %xmm4,%xmm1      ## xmm1=rinvsix 
        movapd %xmm1,%xmm2
        mulsd  %xmm2,%xmm2      ## xmm2=rinvtwelve 
        mulsd  nb111nf_qqO(%rsp),%xmm7          ## xmm7=vcoul 

        mulsd  nb111nf_c6(%rsp),%xmm1
        mulsd  nb111nf_c12(%rsp),%xmm2
        movapd %xmm2,%xmm3
        subsd  %xmm1,%xmm3      ## Vvdw=Vvdw12-Vvdw6            
        addsd  nb111nf_Vvdwtot(%rsp),%xmm3
        addsd  nb111nf_vctot(%rsp),%xmm7
        movsd %xmm3,nb111nf_Vvdwtot(%rsp)
        movsd %xmm7,nb111nf_vctot(%rsp)

        ## H1 interactions 
        mulsd  nb111nf_qqH(%rsp),%xmm6          ## xmm6=vcoul 
        addsd  nb111nf_vctot(%rsp),%xmm6
        movsd %xmm6,nb111nf_vctot(%rsp)

        ## H2 interactions 
        mulsd  nb111nf_qqH(%rsp),%xmm5          ## xmm5=vcoul 
        addsd  nb111nf_vctot(%rsp),%xmm5
        movsd %xmm5,nb111nf_vctot(%rsp)

_nb_kernel111nf_x86_64_sse2.nb111nf_updateouterdata: 
        ## get n from stack
        movl nb111nf_n(%rsp),%esi
        ## get group index for i particle 
        movq  nb111nf_gid(%rbp),%rdx            ## base of gid[]
        movl  (%rdx,%rsi,4),%edx                ## ggid=gid[n]

        ## accumulate total potential energy and update it 
        movapd nb111nf_vctot(%rsp),%xmm7
        ## accumulate 
        movhlps %xmm7,%xmm6
        addsd  %xmm6,%xmm7      ## low xmm7 has the sum now 

        ## add earlier value from mem 
        movq  nb111nf_Vc(%rbp),%rax
        addsd (%rax,%rdx,8),%xmm7
        ## move back to mem 
        movsd %xmm7,(%rax,%rdx,8)

        ## accumulate total lj energy and update it 
        movapd nb111nf_Vvdwtot(%rsp),%xmm7
        ## accumulate 
        movhlps %xmm7,%xmm6
        addsd  %xmm6,%xmm7      ## low xmm7 has the sum now 

        ## add earlier value from mem 
        movq  nb111nf_Vvdw(%rbp),%rax
        addsd (%rax,%rdx,8),%xmm7
        ## move back to mem 
        movsd %xmm7,(%rax,%rdx,8)

        ## finish if last 
        movl nb111nf_nn1(%rsp),%ecx
        ## esi already loaded with n
        incl %esi
        subl %esi,%ecx
        jz _nb_kernel111nf_x86_64_sse2.nb111nf_outerend

        ## not last, iterate outer loop once more!  
        movl %esi,nb111nf_n(%rsp)
        jmp _nb_kernel111nf_x86_64_sse2.nb111nf_outer
_nb_kernel111nf_x86_64_sse2.nb111nf_outerend: 
        ## check if more outer neighborlists remain
        movl  nb111nf_nri(%rsp),%ecx
        ## esi already loaded with n above
        subl  %esi,%ecx
        jz _nb_kernel111nf_x86_64_sse2.nb111nf_end
        ## non-zero, do one more workunit
        jmp   _nb_kernel111nf_x86_64_sse2.nb111nf_threadloop
_nb_kernel111nf_x86_64_sse2.nb111nf_end: 
        movl nb111nf_nouter(%rsp),%eax
        movl nb111nf_ninner(%rsp),%ebx
        movq nb111nf_outeriter(%rbp),%rcx
        movq nb111nf_inneriter(%rbp),%rdx
        movl %eax,(%rcx)
        movl %ebx,(%rdx)

        addq $408,%rsp
        emms


        pop %r15
        pop %r14
        pop %r13
        pop %r12

        pop %rbx
        pop    %rbp
        ret

