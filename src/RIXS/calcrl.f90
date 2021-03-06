! Written by Josh Kas 9/1/2010
subroutine CalcRl ( dx, x0, ri, ne, em,                             &
     &            ixc, rmt, rnrm,                                 &
     &            vtot, vvalgs, dgcn, dpcn, eref,                 &
     &            adgc, adpc, xrhole, xrhoce, ph,                 &
     &            iz, xion, iunf, ihole, lmaxsc, xbruce,          &
     &            xnval, rl)

  use DimsMod, only: nrptx, nex, lx
  use constants
  implicit none

  ! INPUT
  !   dx, x0, ri(nr)  Loucks r-grid, ri=exp((i-1)*dx-x0)
  !   ne, em(ne)      number of energy points,  complex energy grid
  !   ixc             0  Hedin-Lunqist + const real & imag part
  !                   1  Dirac-Hara + const real & imag part
  !                   2  ground state + const real & imag part
  !                   3  Dirac-Hara + HL imag part + const real & imag part
  !                   5  Dirac-Fock exchange with core electrons +
  !                     ixc=0 for valence electron density
  !   rmt             r muffin tin
  !   rnrm            r norman
  !   vtot(nr)        total potential, including gsxc, final state
  !   dgcn(dpcn)      large (small) dirac components for central atom
  !   adgc(adpc)      their development coefficients
  !
  ! OUTPUT
  !   xrhole(0:lx,nex) integral over r of density function
  !   xrhoce(nex)      integral over r of density function for embedded atom
  !   ph(nex,lx+1)

  ! max number allowed in xsect r-grid
  integer, parameter :: nrx = nrptx

  ! Input
  integer, intent(in) :: ne,ixc,iz,iunf,ihole,lmaxsc
  real*8,  intent(in) :: dx,x0,rmt,rnrm,xion
  real*8,  intent(in), dimension(10,30) :: adgc, adpc
  real*8,  intent(in), dimension(nrptx,30) :: dgcn, dpcn
  real*8,  intent(in), dimension(nrptx) ::  vtot,vvalgs,ri
  real*8,  intent(in) :: xnval(30)
  complex*16, intent(in) :: em(nex), eref, rl(nrptx)

  ! Output
  complex*16, intent(out), dimension(0:lx,nex) :: xrhole, xbruce
  real*8,     intent(out), dimension(0:lx,nex) :: xrhoce
  complex*16, intent(out) :: ph(nex, lx+1)


  ! Local variables

  ! Added to satisfy implicit none:
  integer :: lmax,imt,jri,inrm,jnrm,ikap,i0,irr,ic3,i,ilast,ie,ncycle,lll
  real*8  :: dx05


  real*8 :: ri05(251)
  complex*16 :: vtotc(nrptx), vvalc(nrptx)
 
  !     work space for dfovrg: regular and irregular solutions
  complex*16 pr(nrx), qr(nrx), pn(nrx), qn(nrx)

  complex*16  p2, xkmt, ck, xck
  complex*16  pu, qu
  complex*16  xfnorm, xirf
  complex*16  temp,  phx

  complex*16 jl,jlp1,nl,nlp1
  complex*16  xpc(nrx)

  !     initialize
  !     make  radial grid with 0.05 step
  dx05=0.05d0
  do i=1,251
     ri05(i) = exp(-8.8+dx05*(i-1))
  enddo

  lmax=lmaxsc
  if (lmax.gt.lx) lmax = lx
  if (iz.le.4) lmax=2
  if (iz.le.2) lmax=1
  do i = 1, nrptx
     vtotc(i)=vtot(i)
     vvalc(i)= vvalgs(i)
  enddo

  !     set imt and jri (use general Loucks grid)
  !     rmt is between imt and jri (see function ii(r) in file xx.f)
  imt  = (log(rmt) + x0) / dx  +  1
  jri  = imt+1
  if (jri .gt. nrptx)  call par_stop('jri .gt. nrptx in phase')
  inrm = (log(rnrm) + x0) / dx  +  1
  jnrm = inrm+1
  !     ilast is the last integration point
  !      it is larger than jnrm for better interpolations
  ilast = jnrm + 6
  if (ilast.gt.nrptx) ilast = nrptx

  IE_LOOP: do ie = 1, ne
     !       p2 is (complex momentum)**2 referenced to energy dep xc
     p2 = em(ie) - eref
     if (mod(ixc,10) .lt. 5) then
        ncycle = 0
     else
        ncycle = 3
     endif
     ck = sqrt(2*p2+ (p2*alphfs)**2)
     xkmt = rmt * ck

     LLL_LOOP: do lll=0,lx
        if (lll.gt.lmax) then
           ph(ie, lll+1) = 0
           xrhoce(lll,ie) = 0
           xrhole(lll,ie) = 0
           xbruce(lll,ie) = 0
           cycle LLL_LOOP
        endif

        ! may want to use ihole=0 for new screening. 
        ! don't want ro use it now
        ! ihole = 0
        ikap = -1-lll
        irr = -1
        ic3 = 1
        if (lll.eq.0) ic3 = 0
        call dfovrg ( ncycle, ikap, rmt, ilast, jri, p2, dx,          &
             &        ri, vtotc, vvalc, dgcn, dpcn, adgc, adpc,       &
             &        xnval, pu, qu, pn, qn,                          &
             &        iz, ihole, xion, iunf, irr, ic3,0)

        !  phx = pu
        call exjlnl (xkmt, lll, jl, nl)
        call exjlnl (xkmt, lll+1, jlp1, nlp1)
        call phamp (rmt, pu, qu, ck,  jl, nl, jlp1, nlp1, ikap,       &
             &                  phx, temp)
        ph(ie, lll+1)=phx

        ! Normalize final state  at rmt to
        ! rmt*(jl*cos(delta) - nl*sin(delta))
        xfnorm = 1 / temp
        ! xfnorm = 1
        ! normalize regular solution
        do i = 1,ilast
           pr(i)=pn(i)*xfnorm
           qr(i)=qn(i)*xfnorm
        enddo
        rl(:) = pr(:)
        return ! Josh - For now leave the stuff for finding the irregular solution since we might want that later.

        ! find irregular solution
        irr = 1
        pu = ck*alphfs
        pu = - pu/(1+sqrt(1+pu**2))
        ! set pu, qu - initial condition for irregular solution at ilast
        ! qu=(nlp1*cos(phx)+jlp1*sin(phx))*pu *rmt
        ! pu = (nl*cos(phx)+jl*sin(phx)) *rmt
        qu=(nlp1*cos(phx)+jlp1*sin(phx))*pu *rmt 
        pu = (nl*cos(phx)+jl*sin(phx)) *rmt 

        call dfovrg (ncycle, ikap, rmt, ilast, jri, p2, dx,           &
             &       ri, vtotc,vvalc, dgcn, dpcn, adgc, adpc,         &
             &       xnval, pu, qu, pn, qn,                           &
             &       iz, ihole, xion, iunf, irr, ic3,0)
        !c set N- irregular solution , which is outside
        !c N=(nlp1*cos(ph0)+jlp1*sin(ph0))*factor *rmt * dum1
        !c N = i*R - H*exp(i*ph0)
        temp = exp(coni*phx)
        !       calculate wronskian (qu)
        qu = 2 * alpinv * temp * ( pn(jri)*qr(jri) - pr(jri)*qn(jri) )
        qu = 1 /qu / ck
        !       qu should be close to 1
        do i = 1, ilast
           !         pr(i) = pr(i)*qu
           !         qr(i) = qr(i)*qu
           pn(i) = coni * pr(i) - temp * pn(i)*qu
           qn(i) = coni * qr(i) - temp * qn(i)*qu
        enddo

        ! ATOM,  dgc0 is large component, ground state hole orbital
        !         dpc0 is small component, ground state hole orbital
        ! FOVRG, p    is large component, final state photo electron
        ! .      q    is small component, final state photo electron


        !  Use exact solution to continue solutions beyond rmt
        pu = ck*alphfs
        pu = - pu/(1+sqrt(1+pu**2))
        do i=jri,ilast
           xck = ck * ri(i)
           temp = xck
           call exjlnl (temp, lll, jl, nl)
           call exjlnl (temp, lll+1, jlp1, nlp1)
           pr(i)= (jl*cos(phx)-nl*sin(phx)) *ri(i)
           qr(i)=(jlp1*cos(phx)-nlp1*sin(phx))*pu *ri(i)
           pn(i)= (nl*cos(phx)+jl*sin(phx)) *ri(i)
           qn(i)=(nlp1*cos(phx)+jlp1*sin(phx))*pu *ri(i)
        enddo

        !    combine all constant factors to temp
        !    add relativistic correction to normalization, factor 2*lll+1,
        !    2*ck for G.F., factor 2 for spin, and hart to transform to eV
        pu = ck*alphfs
        pu = - pu/(1+sqrt(1+pu**2))
        temp = (2*lll+1.0d0)/(1+pu**2) /pi *ck*4 / hart
        do i = 1, ilast
           xpc(i) = pr(i) * pr(i) + qr(i) * qr(i) 
        enddo


        xirf = lll*2 + 2
        !         i0 should be less or equal to  ilast
        i0=jnrm+1
        call csomm2 (ri, xpc, dx, xirf, rnrm, i0)
        !         print out xirf for Bruce
        xbruce(lll,ie) = xirf
        xrhole(lll,ie) = xirf*temp

        !     only central atom contribution needs irregular solution
        do i = 1, ilast
           xpc(i) = pn(i)*pr(i)-coni*pr(i)*pr(i)                       &
                &             + qn(i)*qr(i)-coni*qr(i)*qr(i)
        enddo


        xirf =  1
        call csomm2 (ri, xpc, dx, xirf, rnrm, i0)
        xrhoce(lll, ie) =  - dimag(xirf* temp)
     enddo LLL_LOOP
  enddo IE_LOOP

  return
end subroutine rhol
