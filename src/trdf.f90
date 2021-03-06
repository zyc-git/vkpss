module trdf

  implicit none

  ! PARAMETERS

  integer, parameter :: NMAX = 1000
  integer, parameter :: MMAX = 1000
  integer, parameter :: JCNNZMAX = NMAX * MMAX
  integer, parameter :: HCNNZMAX = NMAX ** 2 * (1 + MMAX)
  integer, parameter :: MAXXEL = 3
  integer, parameter :: INN = 1000

  ! COMMON SCALARS

  integer :: IC,MAXIC
  real(8) :: VQUAD,VQUAD_A

  ! COMMON ARRAYS

  real(8) :: XBASE_A(INN), GOPT_A(INN), HQ_A(INN ** 2), XOPT_A(INN)

  ! COMMON SUBROUTINES

  pointer :: evalf,evalc,evaljac,evalhc

  ! INTERFACES

  interface

     subroutine evalf(n,x,f,flag)
       ! SCALAR ARGUMENTS
       integer :: flag,n
       real(8) :: f
       ! ARRAY ARGUMENTS
       real(8) :: x(n)

       intent(in ) :: n,x
       intent(out) :: f,flag
     end subroutine evalf

     subroutine evalc(n,x,ind,c,flag)
       ! SCALAR ARGUMENTS
       integer :: flag,ind,n
       real(8) :: c
       ! ARRAY ARGUMENTS
       real(8) :: x(n)

       intent(in ) :: ind,n,x
       intent(out) :: c,flag
     end subroutine evalc

     subroutine evaljac(n,x,ind,jcvar,jcval,jcnnz,lim,lmem,flag)
       ! SCALAR ARGUMENTS
       integer :: flag,ind,jcnnz,lim,n
       logical :: lmem
       ! ARRAY ARGUMENTS
       integer :: jcvar(lim)
       real(8) :: jcval(lim),x(n)

       intent(in ) :: ind,lim,n,x
       intent(out) :: flag,jcnnz,jcval,jcvar,lmem
     end subroutine evaljac

      subroutine evalhc(n,x,ind,hcrow,hccol,hcval,hcnnz,lim,lmem,flag)
        ! SCALAR ARGUMENTS
        logical :: lmem
        integer :: flag,hcnnz,ind,lim,n
        ! ARRAY ARGUMENTS
        integer :: hccol(lim),hcrow(lim)
        real(8) :: hcval(lim),x(n)

        intent(in ) :: ind,lim,n,x
        intent(out) :: flag,hccol,hcrow,hcval,hcnnz,lmem
      end subroutine evalhc

  end interface

  private

  public :: TRDFSUB

contains

  SUBROUTINE TRDFSUB(N,NPT,X,XL,XU,M,EQUATN,LINEAR,CCODED,EVALF_,EVALC_, &
       EVALJAC_,EVALHC_,MAXFCNT,RBEG,REND,XEPS,SVREPSINI,SVREPSMIN,      &
       SVRPENINI,SVRPENMAX,OUTPUT,F,FEAS,FCNT)

    ! This subroutine is the implementation of the Derivative-free
    ! Trust-region algorithm for constrained optimization described in
    !
    !     P. D. Conejo, E. W. Karas, L. G. Pedroso, "A trust-region
    !     derivative-free algorithm for constrained optimization".
    !     Optimization Methods & Software, to appear, 2015.
    !
    ! For more information on configurations, recommended values of
    ! the parameters and examples, please read the documentation
    ! provided with the method.
    !
    !     The INPUT parameters are
    ! N - dimension of the problem
    !
    ! NPT - number of points used in the quadratic interpolation
    !
    ! X(N) - inital point
    !
    ! XL(N) - lower bounds on the variables
    !
    ! XU(N) - upper bounds on the variables
    !
    ! M - number of constraints
    !
    ! EQUATN(M) - a logical vector such that EQUATN(i) = .true. if and
    !             only if constraint 'i' is an equality constraint
    !
    ! LINEAR(M) - a logical vector such that LINEAR(i) = .true. if and
    !             only if constraint 'i' is a linear constraint
    !
    ! CCODED(2) - a logical vector indicating whether or not the
    !             Jacobian (CCODED(1)) and the Hessian (CCODED(2)) of
    !             the constraints are provided by the user
    !
    ! EVALF_ - the user-defined objective function
    !
    ! EVALC_ - the user-defined constraints
    !
    ! EVALJAC_ - the user-defined Jacobian of the constraints
    !
    ! EVALHC_ - the user defined Hessian of the constraints
    !
    ! MAXFCNT - maximum number of function evaluations
    !
    ! RBEG - initial value for the trust region radius and interpolation
    !
    ! REND - smallest trust-region radius for declaring convergence of
    !        the method
    !
    ! XEPS - feasibility/optimality tolerance for solving the subproblems
    !
    ! OUTPUT - a logical variable indicating if the method has or has not
    !          to display information
    !
    ! The OUTPUT parameters are
    !
    ! X(N) - the final point
    !
    ! F - objective function value at the final point
    !
    ! FEAS - sup-norm of the infeasibility at the final point
    !
    ! FCNT - number of function evaluations

    use svrmod

    IMPLICIT NONE

    ! SCALAR ARGUMENTS
    logical :: OUTPUT
    integer :: m,maxfcnt,N,NPT,FCNT
    real(8) :: F,FEAS,RBEG,REND,SVREPSINI,SVREPSMIN,SVRPENINI,SVRPENMAX, &
               XEPS

    ! ARRAY ARGUMENTS
    REAL(8) :: X(N),XL(N),XU(N)
    logical :: ccoded(2),equatn(m),linear(m)

    ! EXTERNAL SUBROUTINES
    external :: evalf_,evalc_,evaljac_,evalhc_

    intent(in   ) :: m,maxfcnt,n,npt,rbeg,rend,xeps,xl,xu,ccoded, &
                     equatn,linear,svrepsini,svrepsmin,svrpenini, &
                     svrpenmax
    intent(out  ) :: f,feas,fcnt
    intent(inout) :: x

    ! LOCAL ARRAYS
    REAL(8) :: FF(NPT),D(INN),Y(NPT,N),Q(1+N+N*(N+1)/2), &
         H(NPT+N+1,NPT+N+1),XNOVO(INN),SL(INN),SU(INN),  &
         VETOR1(NPT+N+1), HQ(N, N), G(N)

    ! LOCAL SCALARS
    integer :: i,it,j,k,kn,flag
    real(8) :: alfa,beta,c,cnorm,delta,distsq,dsq,fopt,gama, &
         mindelta,rho,rhobeg,rhoend,sigm,sum,tau,tempofinal, &
         tempoinicial, b, MOD_A, c_svr, eps_svr

    IF ( OUTPUT ) WRITE(*,3000)

    evalf   => evalf_
    evalc   => evalc_
    evaljac => evaljac_
    evalhc  => evalhc_

    F      = 1.0D300
    IC     = 0
    MAXIC  = maxfcnt ! MAXIMUM NUMBER OF FUNCTION EVALUATIONS
    RHOBEG = RBEG
    RHO    = RHOBEG
    DELTA  = RHO
    RHOEND = REND
    GAMA   = 0.1D0
    IT     = 1

    call svr_set_output(OUTPUT)

    c_svr = SVRPENINI

    !     ---------------------------
    !     Feasibility phase - Phase 0
    !     ---------------------------

    CALL SOLVER(N, XL, XU, X, M, EQUATN, LINEAR, CCODED, &
         mevalf, mevalg, mevalh, mevalc, mevaljac, mevalhc, &
         .true., XEPS, CNORM, FLAG)

    IF ( FLAG .NE. 0 ) GOTO 31
    IF (OUTPUT) WRITE(*,1000) CNORM,X

    !     ------------------------
    !     End of feasibility phase
    !     ------------------------

    IF (OUTPUT) WRITE(*,1001)

    DO I = 1, N
       XNOVO(I)   = X(I)
       XBASE_A(I) = X(I)            
    END DO

    GO TO 5
4   CONTINUE     
    DO I = 1, N
       X(I)       =  XNOVO(I)      
       XBASE_A(I) =  XNOVO(I)
    END DO

    IT = 1

5   continue

    ! Building initial sampling set

    call fromScratch(n, x, npt, rho, calfun, H, Y, FF, flag)

    IF ( OUTPUT ) WRITE(*,1002) RHO,DELTA,FF(1),IC,MIN(N,MAXXEL), &
                  (X(I), I=1,MIN(N,MAXXEL))

    IF ( FLAG .NE. 0 ) GOTO 31

    FOPT = FF(1)

    ! Build SVR Model

11  continue

    eps_svr = max(SVREPSMIN, min(5.0D-1 * rho * rho, SVREPSINI))

    c_svr   = min(SVRPENMAX, max(c_svr, SVRPENINI / eps_svr))

    call qsvm(Y, FF, n, npt, c_svr, eps_svr, HQ, g, b, flag)

    ! TODO: Use the correct flag according the output
    if ( flag .ne. 0 ) GOTO 31

    ! Initialize TRDF's structure

    call svrToTRDF(n, HQ, g, b, XBASE_A, HQ_A, GOPT_A, MOD_A, Q)

    CALL SUBPROBLEMA(N, NPT, Q, DELTA, D, X, XL, XU, DSQ, &
         M, EQUATN, LINEAR, CCODED, XEPS, FLAG) 

    IF ( OUTPUT ) WRITE(*,1003) RHO, DELTA, VQUAD_A, FOPT, IC
    IF ( FLAG .NE. 0 ) GOTO 31

    DISTSQ = (10.D0 * RHO)**2                 
    IF ( SQRT(DSQ) .LT. 0.5D0 * RHO ) THEN 

       KN = 0
       DO K = 1, NPT
          SUM=0.0D0
          DO J = 1, N
             SUM = SUM + (Y(K,J) - X(J))**2.0D0
          END DO
          IF ( SUM .GT. DISTSQ ) THEN
             KN = K
             exit
          END IF
       END DO

       IF ( RHO .LE. RHOEND ) GO TO 31
       IF ( KN .EQ. 0 ) RHO = GAMA * RHO              

       GO TO 4
    END IF

    CALL CALFUN(N,X,F,FLAG)

    IF ( FLAG .NE. 0 ) GOTO 31

    IF ( OUTPUT ) WRITE(*,1006) F

    IF ( (F - FOPT) .GT. (0.1D0 * VQUAD) ) THEN
       DELTA = 0.5D0 * DELTA                 
    ELSE IF ( (F - FOPT) .GE. (0.7D0 * VQUAD) ) THEN
       DELTA = DELTA  
    ELSE
       DELTA = 2.0D0 * DELTA
    END IF

    ! CHOOSE WHO LEAVE Y CALCULATING THE VALUE OF SIGMA. THE VARIABLE
    ! 'IT' IS CHOOSEN FOR DEFINE WHO LEAVE.

    ! TODO: Take a close look at IT when there is no update
    CALL SIGMA(H,N,NPT,Y,X,VETOR1,SIGM,ALFA,BETA,TAU,IT,DELTA)         

    ! IF ANY REDUCTION IN F, PUT X IN INTERPOLATION SET.

    IF (F .LE. FOPT) THEN  
       IF ( OUTPUT ) WRITE(*,1005) IT
       DO I = 1, N            
          Y(IT,I) = X(I) 
       END DO
       FF(IT) = F
    ELSE
       GO TO 23
    END IF

    ! UPDATE H              

    CALL INVERSAH(H, N, NPT, VETOR1, SIGM, IT, ALFA, BETA,TAU)

    ! ! Update SVR Model

    ! call qsvm(Y, FF, n, npt, HQ, g, b)

    ! ! Update TRDF's data

    ! call svrToTRDF(n, HQ, g, b, XBASE_A, HQ_A, GOPT_A, MOD_A, Q)

23  IF ( F .LE. FOPT + 0.1D0 * VQUAD ) THEN                 
       FOPT = F
       DO I = 1, N
          XNOVO(I) = X(I) 
       END DO
       GO TO 11  
    END IF

    IF ( sigm .le. 0.0d0 ) go to 4

    IF ( (RHO .LE. RHOEND) .OR. (IC == MAXIC) ) GO TO 31

    KN=0
    DO K = 1,NPT
       SUM = 0.0D0
       DO J = 1,N
          SUM = SUM + (Y(K,J) - X(J))**2.0D0
       END DO

       IF ( SUM .GT. DISTSQ ) THEN
          KN = K
          exit
       END IF
    END DO

    IF ( KN .GT. 0 )  GOTO 4       

    DELTA = RHO  
    RHO   = GAMA * RHO      

    GO TO 11    

    ! OUTPUT DATA
31  continue           

    if ( OUTPUT .and. flag .eq.  0 ) write(*,1020)
    if ( OUTPUT .and. flag .eq. -1 ) write(*,1021)
    if ( OUTPUT .and. flag .eq.  2 ) write(*,1022)
    if ( OUTPUT .and. flag .eq.  3 ) write(*,1023) MAXIC

    F = FOPT

    do i = 1,n
       x(i) = XNOVO(i)
    end do

    FEAS = 0.0D0
    do I = 1,M
       ! TODO: Test FLAG
       CALL EVALC(N,X,I,C,FLAG)
       IF ( EQUATN(I) ) THEN
          FEAS = MAX(FEAS,ABS(C))
       ELSE
          FEAS = MAX(FEAS,MAX(0.0D0,C))
       END IF
    end do

    FCNT = IC

    IF ( OUTPUT ) THEN
       call cpu_time(tempofinal)
       write(*,2000) F,FEAS,RHO,DELTA,IC,(tempofinal - tempoinicial), &
                     MIN(N,MAXXEL),(X(I), I=1,MIN(N,MAXXEL))
    END IF

    ! FORMATS

1000 FORMAT(/,'PHASE 0',/,7('-'),/,/,'FEASIBILITY =',36X,D23.8,/, &
              'NEW POINT',/,3(1X,D23.8))
1001 FORMAT(/,'PHASE 1',/,7('-'))
1002 FORMAT(/,'(RE)BUILDING MODEL from scratch.',/, &
            5X,'RHO =',50X,D12.5,/,                 &
            5X,'Delta =',48X,D12.5,/,               &
            5X,'Objective function =',24X,D23.8,/,  &
            5X,'Function evaluations =',35X,I10,/,  &
            5X,'Current model center (first ',I3,' elements)',/,6X, &
            3(1X,D21.8))
1003 FORMAT(/,'SOLVED TR SUBPROBLEM.',/,           &
            5X,'RHO =',50X,D12.5,/,                &
            5X,'Delta =',48X,D12.5,/,              &
            5X,'Model value =',31X,D23.8,/,        &
            5X,'Objective function =',24X,D23.8,/, &
            5X,'Function evaluations =',35X,I10)
1004 FORMAT(5X,'Objective function =',24X,D23.8)
1005 FORMAT(/,'REMOVING sampling point',1X,I4,'.')
1006 FORMAT(5X,'Objective function (at trial point) =',&
         7X,D23.8)

1020 FORMAT(/,'Solution was found!',/)
1021 FORMAT(/,'Flag -1: Error while evaluating functions.',/)
1022 FORMAT(/,'Flag 2: Error in the internal solver.',/)
1023 FORMAT(/,'Flag 3: Reached the maximum of',1X,I10,1X, &
          'function evaluations.',/)

2000 FORMAT(/,'Final Iteration',/,15('-'),2/,          &
            'Objective function =',29X,D23.8,/,        &
            'Feasibility =',36X,D23.8,/,               &
            'RHO =',55X,D12.5,/,                       &
            'Delta =',53X,D12.5,/,                     &
            'Function evaluations =',40X,I10,/,        &
            'CPU time =',30X,1PD23.8,1X,'seconds.',/,  &
            'Solution (first ',I3,' elements)',/,3(1X,D23.8))

3000 FORMAT(/,'Welcome to TRDF Algorithm!',/,                   &
          'This algorithm was based on paper',/,                &
          'P.D. Conejo, E.W. Karas, and L.G. Pedroso',/,        &
          '"A trust-region derivative-free algorithm for',/,    &
          'constrained problems", to appear in Optimization',/, &
          'Methods & Software.',/)
  END SUBROUTINE TRDFSUB

  ! ******************************************************************
  ! ******************************************************************

  SUBROUTINE SIGMA(H,N,NPT,Y,X,VETOR1,SIGM,ALFA,BETA,TAU,IT,DELTA)

    implicit none

    ! SCALAR ARGUMENTS
    integer :: IT,N,NPT
    real(8) :: alfa,beta,delta,sigm,tau

    ! ARRAY ARGUMENTS
    real(8) :: X(*), VETOR1(*), H(NPT+N+1,NPT+N+1), Y(NPT,N)

    ! WW STORAGE THE VETOR1 IN W TO PRODUCE ALFA BETA TAU HOW IN
    ! DEFINITION.  SIGMA = ALFA BETA + TAU**2. ALFA = ET^T H ET,
    ! NAMELY, HTT (T = IT) IT INDICATE THAT THE VETOR1 IN POSITION TWO
    ! (SECOND LINE OF Y) LEAVE OF Y CHOOSE THE LARGEST SIGMA (AND
    ! THEREFORE IT) UNLESS DE CURRENT POINT (IT CURRENT)

    ! LOCAL SCALARS
    integer :: i,IAUXILIAR,ITT,j,k,kkk
    real(8) :: AGUARD,CONT,SIGMI

    ! LOCAL ARRAYS
    real(8) :: WW(NPT+N+1,1),AUXILIAR(4)           

    ITT=IT    ! STORAGE THE POSITION OF BEST ITERATING YET.          
    IT =1
    SIGMI = -1.0D100

    ! Creating vector 'w'

    WW(NPT+1,1) = 1.0D0
    DO I=1, N
       WW(I+NPT+1, 1) =  X(I)- XBASE_A(I)
    END DO
    DO I=1, NPT
       CONT = 0.0D0
       DO K=1, N         
          CONT = CONT +  (Y(I,K) - XBASE_A(K)) * (X(K) - XBASE_A(K))          
       END DO
       WW(I, 1) = 0.5D0*CONT**2
    END DO

    ! CALCULATING ALL SIGMA AND CHOOSE IT FOR THE GREATER
    ! SIGMA. MULTIPLY T-th LINE OF H FOR W FOR OBTAIN TAU.

    ! Calculating w^T * H * w

    DO KKK = 1, NPT ! Changed from NPT - 1 to NPT
       CONT=0.0D0
       DO I=1, NPT+ N +1
          CONT = CONT +  H(IT, I) * WW(I,1)
       END DO
       TAU = CONT
       ! CALCULUS OF BETA = 0.5||X^+-XBASE||-WHW                  
       DO I=1, NPT+N+1
          CONT = 0.0D0 
          DO K=1, NPT+N+1
             CONT = CONT + H(I,K) * WW(K,1)
             VETOR1(I) = CONT                  
          END DO
       END DO

       CONT = 0.0D0
       DO I=1,  NPT+N+1
          CONT = CONT+WW(I,1)*VETOR1(I)
          AGUARD = CONT
       END DO

       ! CALCULUS  OF X-XB^4
       CONT = 0.0D0
       DO I=1, N
          CONT = CONT + (X(I)-XBASE_A(I))**2
       END DO

       BETA =   0.5D0 * CONT**2 - AGUARD
       ALFA = H(IT,IT) 
       SIGM = ALFA * BETA + TAU**2  

       IF (SIGM .GE. SIGMI .AND. IT .NE. ITT) THEN
          SIGMI = SIGM
          IAUXILIAR  =  IT                
          AUXILIAR(1) = ALFA
          AUXILIAR(2) = BETA
          AUXILIAR(3) = TAU
          AUXILIAR(4) = SIGM                           
       END IF
       IT = IT + 1
    END DO

    ! CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC

    IT   = IAUXILIAR  
    ALFA = AUXILIAR(1) 
    BETA = AUXILIAR(2)
    TAU  = AUXILIAR(3) 
    SIGM = AUXILIAR(4)

    CONT=0.0D0
    DO I=1, NPT+ N +1
       CONT = CONT +  H(IT, I) * WW(I,1)
    END DO
    TAU = CONT

    RETURN
  END SUBROUTINE SIGMA

  ! ******************************************************************
  ! ******************************************************************

  ! **************** UPDAT THE INVERSE H ******************************
  SUBROUTINE INVERSAH(H, N, NPT, VETOR1, SIGM, IT, ALFA, BETA, TAU)

    implicit none

    ! SCALAR ARGUMENTS
    integer :: IT,N,NPT
    real(8) :: alfa,beta,sigm,tau

    ! ARRAY ARGUMENTS
    real(8) :: VETOR1(*),H(NPT+N+1,NPT+N+1)

    ! ALFA*(E-MM) * (E-MM)'- BETA* H * E * E'*H+TAU*H*E*(E-MM)'+ (E-MM)* E'* H
    ! MM = H*WW THAT IS STORED IN VETOR1 

    ! LOCAL SCALARS
    integer :: i,j

    ! LOCAL ARRAYS
    real(8) :: P1(NPT+N+1,NPT+N+1),P2(NPT+N+1,NPT+N+1),P3(NPT+N+1,NPT+N+1)

    VETOR1(IT) = VETOR1(IT)-1.0D0              
    DO I=1, N+NPT+1
       DO J=1, N+NPT+1
          P1(I,J)= VETOR1(I) * VETOR1(J)
          P2(I,J)= H(I, IT) * H(J, IT)
          P3(I,J)= (H(IT, I)*(-VETOR1(J)))+(H(IT,J)*(-VETOR1(I)))
       END DO
    END DO
    DO I=1, N+NPT+1
       DO J=1, N+NPT+1
          if (sigm .eq. 0d0) return
          H(I,J)=H(I,J)+(1/SIGM)*(ALFA*P1(I,J)-BETA*P2(I,J)+TAU*P3(I,J)) 
       END DO
    END DO
    RETURN
  END SUBROUTINE INVERSAH

  ! ******************************************************************
  ! ******************************************************************

  SUBROUTINE  SUBPROBLEMA(N, NPT, Q, DELTA, D, X, XL, XU, DSQ, M, &
       EQUATN, LINEAR, CCODED, XEPS, FLAG)

    implicit none

    ! SCALAR ARGUMENTS
    integer :: flag,m,N,NPT
    real(8) :: delta,dsq,xeps

    ! ARRAY ARGUMENTS
    real(8) :: Q(*), X(*), XL(*),XU(*),D(INN)
    logical :: ccoded(2),equatn(m), linear(m)

    ! LOCAL SCALARS
    integer :: i
    real(8) :: cnorm,f,sum

    ! LOCAL ARRAYS
    real(8) ::  XANTIGO(INN),L(N),H(NPT+N+1,NPT+N+1),U(N) 

    DO I = 1,N
       L(I)=  DMAX1(XL(I) - XBASE_A(I),X(I) - XBASE_A(I)-DELTA) 
       U(I)=  DMIN1(XU(I) - XBASE_A(I),X(I) - XBASE_A(I)+DELTA)           
       XANTIGO(I) = X(I)
    END DO

    DO I = 1, N        
       D(I) = X(I) - XBASE_A(I)
    END DO

    CALL MEVALF(N,D,F,FLAG)

    IF ( FLAG .NE. 0 ) RETURN

    VQUAD =  F + Q(1)

    CALL SOLVER(N, L, U, D, M, EQUATN, LINEAR, CCODED, &
         mevalf, mevalg, mevalh, mevalc, mevaljac, mevalhc, &
         .false., XEPS, CNORM, FLAG)

    IF ( FLAG .NE. 0 ) RETURN

    ! CALCULUS THE STEP LENGTH 
    SUM = 0.0D0
    DO I=1, N
       SUM = SUM + (X(I)-(D(I)+XBASE_A(I)))**2
    END DO
    DSQ = SUM
    DO I=1, N
       X(I)= D(I) +  XBASE_A(I)   
    END DO

    CALL MEVALF(N,D,F,FLAG)

    IF ( FLAG .NE. 0 ) RETURN

    VQUAD_A = F + Q(1) ! Model in the new point
    VQUAD   = VQUAD_A - VQUAD ! Denominator for the sufficient decrease test

    IF (VQUAD .GE. 0.D0 .or. cnorm .gt. xeps)  THEN
       DO I=1, N
          X(I) = XANTIGO(I) 
       END DO
       DSQ = 0D0
    END IF

    RETURN
  END SUBROUTINE SUBPROBLEMA

  ! ******************************************************************
  ! ****************************************************************** 

  SUBROUTINE  ATUALIZAQ(H, N, NPT, Q, DELTA, Y, X, F, IT)

    implicit none

    ! SCALAR ARGUMENTS
    integer :: IT,N,NPT
    real(8) :: delta,f

    ! ARRAY ARGUMENTS
    REAL(8) :: Q(*),X(*),Y(NPT,N),H(NPT+N+1,NPT+N+1)

    ! LOCAL SCALARS
    integer :: i,ii,j,jj,k

    ! LOCAL ARRAYS
    real(8) :: VETORAUX(INN),DD(N,N),QQ((N+1)*(N+2)/2),TEMP(1+N+NPT)

    DO I=1, 1+N+NPT
       TEMP(I) =  (F - VQUAD_A)* H(I, IT) ! IS LAMBDA 
    END DO
    DO I=1, N 
       DO J=1, N
          DD(I,J)=0.0D0
       END DO
    END DO
    ! M=M+     LAMBCG(J)*((Y(:,J)-XB') * ( Y(: ,J)-XB')')  
    DO I=1, NPT
       DO JJ=1, N
          VETORAUX(JJ) =  Y(I,JJ)-XBASE_A(JJ)  
       END DO
       DO K=1, N                    
          DO J=1, N
             DD(K,J) = DD(K,J)+ TEMP(I)* VETORAUX(K) * VETORAUX(J)  
             ! DDEH IS THE GRADIENT OF QUADRATIC D                               
          END DO
       END DO
    END DO
    ! N+1 FIRST ELEMENTS OF THE QQ (PARAMETER OF THE NEW MODEL)
    QQ(1) = TEMP(NPT+1)
    DO I=2, N+1 
       QQ(I) = TEMP(NPT+I)
    END DO
    ! PUT IN THE QQ FOR SYMMETRY OF DD
    II=1
    J=1
    ! DO WHILE (II .LE.  (N+1)*N/2 ) 
    DO WHILE (II .LE. N) 
       DO I=1, II 
          QQ(J+1+N) = DD(II,I) 
          J=J+1
       END DO
       II = II + 1
    END  DO
    ! ADD Q TO QQ.  Q IS THE OLD MODEL, QQ IS THE MODEL D, AND Q + D = Q+    
    DO I=1, 1+N+ (N+1)*N/2
       Q(I) = Q(I) + QQ(I)
    END DO
    ! UPDAT THE MODEL IN THE FILE INIP FOR COMMON FUNCTION 
    DO I=1, N      
       GOPT_A(I) = Q(I+1)
    END DO
    DO J=1, (N+1)*N/2 
       HQ_A(J) =  Q(1+N+J) 
    END DO
    RETURN
  END SUBROUTINE  ATUALIZAQ

  ! ******************************************************************
  ! ******************************************************************

  subroutine mvv(v1,v2,n, gradd)

    implicit none

    ! multiplica vetor por vetor

    ! SCALAR ARGUMENTS
    real(8) :: gradd

    ! ARRAY ARGUMENTS
    real(8) :: v1(INN),v2(INN)

    ! LOCAL SCALARS
    real(8) :: soma
    integer :: j,n

    soma=0
    do j=1 , n
       soma=soma +  v1(j)*v2(j)
       gradd=soma
    end do
    return
  end subroutine mvv

  ! ******************************************************************
  ! ******************************************************************

  subroutine  mmv(HQ, S,n, v)

    implicit none

    ! multiplica matriz simetrica (dada como vetor) por vetor
    ! estava com hs, e troquei para hss para nao atualizar hs desnec

    ! ARRAY ARGUMENTS
    real(8) :: S(INN), HQ(INN ** 2),v(INN)

    ! LOCAL ARRAYS
    real(8) :: HSS(INN)

    ! LOCAL SCALARS
    integer :: n,i,IH,j

    IH=0
    DO J=1,N
       HSS(J)= 0
       DO I=1,J
          IH=IH+1
          IF (I .LT. J) HSS(J)=HSS(J)+HQ(IH)*S(I)
          HSS(I)=HSS(I)+HQ(IH)*S(J)
          v(I)=HSS(I)
       end DO
    end DO
    return
  end subroutine mmv
  
  ! ******************************************************************
  ! ******************************************************************

  subroutine calfun(n,x,f,flag)

    implicit none

    ! SCALAR ARGUMENTS
    integer :: flag,n
    real(8) :: f

    ! ARRAY ARGUMENTS
    real(8) :: x(n)

    flag = 0

    ! Returns flag = 3 if reached the maximum of function evaluations
    if ( IC .eq. MAXIC ) then 
       flag = 3
       return
    end if

    ! TODO: add 'flag' to calobjf
    call evalf(n,x,f,flag)

    IC = IC + 1

  end subroutine calfun

  subroutine mevalf(n,x,f,flag)

    implicit none

    ! SCALAR ARGUMENTS
    integer :: flag,n
    real(8) :: f

    ! ARRAY ARGUMENTS
    real(8) :: x(n)

    ! LOCAL ARRAYS
    real(8) :: hqd(n)

    ! LOCAL SCALARS
    real(8) :: gradd,dhqd

    flag = 0

    ! avalia o modelo quadratico f, no ponto d

    ! definindo o modelo quadratico f
    call mvv(GOPT_a,x, n, gradd)
    call mmv(HQ_a, x, n, hqd)
    call mvv(x, hqd, n, dhqd)

    f = gradd + dhqd / 2.0D0

  end subroutine mevalf

  !     ******************************************************************
  !     ******************************************************************

  subroutine mevalg(n,x,g,flag)

    implicit none

    ! SCALAR ARGUMENTS
    integer :: flag,n

    ! ARRAY ARGUMENTS
    real(8) :: g(n),x(n)

    ! LOCAL ARRAYS
    real(8) :: hqd(n)

    ! LOCAL SCALARS
    integer :: i

    flag = 0

    ! avalia o gradiente do modelo quadratico g, no ponto d
    call mmv(HQ_a, x, n, hqd)
    do i=1, n
       g(i)=  GOPT_a(i) + hqd(i)
    end do

  end subroutine mevalg

  ! ******************************************************************
  ! ******************************************************************

  subroutine mevalh(n,x,hrow,hcol,hval,hnnz,lim,lmem,flag)

    implicit none

    ! SCALAR ARGUMENTS
    logical :: lmem
    integer :: flag,n,hnnz,lim

    ! ARRAY ARGUMENTS
    integer :: hcol(lim),hrow(lim)
    real(8) :: hval(lim),x(n)

    ! LOCAL SCALARS
    integer :: i,iii,j

    flag = 0
    lmem = .false.

    hnnz = (N + 1) * N / 2

    ! cria hlin e hcol com as coordenadas da triangular inferior

    III=1
    DO WHILE (III .LE.  (N+1)*N/2 )
       do I=1, N
          DO J= 1, I
             hrow(III) = I
             hcol(III) = J
             III= III + 1
          end do
       end do
    END DO

    do i=1,(N+1)*N/2
       hval(i) = HQ_a(i)
    end do

  end subroutine mevalh

  !     ******************************************************************
  !     ******************************************************************

  subroutine mevalc(n,x,ind,c,flag)

    implicit none

    ! SCALAR ARGUMENTS
    integer :: ind,flag,n
    real(8) :: c

    ! ARRAY ARGUMENTS
    real(8) :: x(n)

    ! LOCAL ARRAYS
    real(8) :: XA(NMAX)

    ! LOCAL SCALARS
    integer :: i

    flag = -1

    DO I=1, N
       XA(I) = X(I) + XOPT_A(I) + XBASE_A(I)
    END DO

    call evalc(n,XA,ind,c,flag)

  end subroutine mevalc

  ! ******************************************************************
  ! ******************************************************************

  subroutine mevaljac(n,x,ind,jcvar,jcval,jcnnz,lim,lmem,flag)

    implicit none

    ! SCALAR ARGUMENTS
    logical :: lmem
    integer :: flag,ind,jcnnz,lim,n

    ! ARRAY ARGUMENTS
    integer :: jcvar(lim)
    real(8) :: x(n),jcval(lim)

    ! LOCAL ARRAYS
    real(8) :: XA(NMAX)

    ! LOCAL SCALARS
    integer :: i

    flag = -1

    DO I=1, N
       XA(I) = X(I) + XOPT_A(I) + XBASE_A(I)
    END DO

    call evaljac(n,XA,ind,jcvar,jcval,jcnnz,lim,lmem,flag)

  end subroutine mevaljac

  ! ******************************************************************
  ! ******************************************************************

  subroutine mevalhc(n,x,ind,hcrow,hccol,hcval,hcnnz,lim,lmem,flag)

    implicit none

    ! SCALAR ARGUMENTS
    logical :: lmem
    integer :: flag,hcnnz,ind,lim,n

    ! ARRAY ARGUMENTS
    integer :: hccol(lim),hcrow(lim)
    real(8) :: hcval(lim),x(n)

    ! LOCAL ARRAYS
    real(8) :: XA(NMAX)

    ! LOCAL SCALARS
    integer :: i

    flag = -1

    DO i = 1,n
       XA(I) = X(I) + XOPT_A(I) + XBASE_A(I)
    END DO

    call evalhc(n,XA,ind,hcrow,hccol,hcval,hcnnz,lim,lmem,flag)

  end subroutine mevalhc

end module trdf
