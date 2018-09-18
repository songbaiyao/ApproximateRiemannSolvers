function res = FV_WENO_EE2d_CharactRecon(q,a,nx,ny,dx,dy,t,fluxMethod,Recon,Test)
% Compute RHS of the semi-discrete form of the Euler equations.
global preshock postshock mesh_wedge_position

%   Flux at j+1/2
% 
%     j+1/2    Cell's grid: (assuming WENO5, R=3)
%   |   |   |                   {x=0}             {x=L}
%   | wL|   |                     |                 |
%   |  /|wR |           1   2   3 | 4   5        N-3|N-2 N-1  N
%   | / |\  |         |-o-|-o-|-o-|-o-|-o-| ... |-o-|-o-|-o-|-o-|---> j
%   |/  | \ |             1   2   3   4   6    N-4 N-3 N-2 N-1  
%   |   |  \|                    {1} {2} {3}  ...  {nf}
%   |   |   |       NC: Here cells 1 to 3 and N-2 to N are ghost cells
%     j  j+1            faces 3 and N-3, are the real boundary faces.
%
%   q = cat(3, r, ru, rv, E);
%   F = cat(3, ru, ru^2+p, ruv, u(E+p));
%   G = cat(3, rv, ruv, rv^2+p, v(E+p));

% Identify number of gost cells
switch Recon
    case {'WENO5','Poly5'}, R=3; % R: stencil size and number of gost cells
    case {'WENO7','Poly7'}, R=4;
    otherwise, error('reconstruction not available ;P');
end

switch Test
    case 'Smooth' % Set Periodic BCs
        for i=1:R
            q(:,i,:)=q(:,nx-R+i,:); q(:,nx-2*R+i,:)=q(:,R+i,:);	% Periodic BCs
        end
        for j=1:R
            q(j,:,:)=q(ny-R+i,:,:); q(ny-2*R+j,:,:)=q(R+j,:,:);	% Periodic BCs
        end
    case 'Riemann' % Set outflow BCs
        for i=1:R
            q(:,i,:)=q(:,R+1,:); q(:,nx+1-i,:)=q(:,nx-R,:);	% Neumann BCs
        end
        for j=1:R
            q(j,:,:)=q(R+1,:,:); q(ny+1-j,:,:)=q(ny-R,:,:);	% Neumann BCs
        end
    case 'DMR' % Set DMR test BCs
        % Static BCs
        for i=1:R
            q(:,i,:)=q(:,R+1,:); q(:,nx+1-i,:)=q(:,nx-R,:);	% Neumann BCs
        end
        % Static BCs at the bottom of domain
        for j=1:R
            for i=R+1:nx-R
                if i<(R+mesh_wedge_position)
                    q(j,i,:)=q(R+1,i,:); % outflow condition : Neumann BC
                else
                    q(j,i,:)=q(R+1,i,:); q(j,i,3)=-q(R+1,i,3); % EE reflective BC
                end
            end
        end
        % Time dependent BCs at the top of domain: moving shock
        for j=ny+1-R:ny % only gosht cells at the top
            for i=R+1:nx-R % evaluate all x domain
                if distance_to_shock(i*dx+dx/2,(j+R)*dy+dy/2,t) < -3*dx % mesh_shock
                    q(j,i,:)=q(ny-R,i,:); % Neumann BC
                elseif distance_to_shock(i*dx+dx/2,(j+R)*dy+dy/2,t) > 3*dx % mesh_shock
                    q(j,i,:)=q(ny-R,i,:); % Neumann BC
                elseif distance_to_shock(i*dx+dx/2,(j+R)*dy+dy/2,t) < 0 % mesh_shock
                    q(j,i,:)=postshock; % Dirichlet BCs
                else
                    q(j,i,:)=preshock; % Dirichlet BCs
                end
            end
        end
    otherwise, error('Test boundaries not set!');
end

% internal cells and primitives array
ic=R+1:ny-R;  %w=zeros(numel(ic),nx,4);

% Trim Domain
%w = q(ic,:,:);

% 1. Reconstruct interface values: qL=q_{i+1/2}^{-} and qR=q_{i-1/2}^{+}
E=4; % numer of components or layers
parfor e=1:E
    switch Recon
        case 'WENO5', [qL(e,:),qR(e,:)] = WENO5charWiseRecon_X(q(ic,:,e),nx);
        %case 'WENO7', [qL(e,:),qR(e,:)] = WENO7charWiseRecon_X(q(ic,:,e),nx);
        otherwise, error('reconstruction not available ;P');
    end
end

% 2. Compute finite volume residual term, df/dx.
res=zeros(size(q)); flux=zeros(size(qR)); nc=ny-2*R; nf=nx+1-2*R; N=nc*nf;

% Normal unitary face vectors: (nx,ny)
% normals = {[1,0], [0,1]}; % i.e.: x-axis, y-axis

% compute flux at (i+1/2,j)
for c=1:N
    switch fluxMethod
        case 'LF',  flux(:,c) = LFflux(qL(:,c),qR(:,c),[1,0],a); % Lax Friedrichs
        case 'ROE', flux(:,c) = ROEflux(qL(:,c),qR(:,c),[1,0]);  % Roe
        case 'RUS', flux(:,c) = RUSflux(qL(:,c),qR(:,c),[1,0]);  % Rusanov
        case 'HLLE',flux(:,c) = HLLEflux(qL(:,c),qR(:,c),[1,0]); % HLLE
        case 'HLLC',flux(:,c) = HLLCflux(qL(:,c),qR(:,c),[1,0]); % HLLC
        otherwise, error('flux method not available ;P');
    end
end

% Flux contribution to the residual of every cell
for e=1:E
    for j=1:nc % for all interior cells
        res(j+R,R+1,e) = res(j+R,R+1,e) - flux(e,j+nc*(1-1))/dx; % left face of cell j=4.
        for i = 2:nf-1 % for all interior faces
            res(j+R,i+R-1,e) = res(j+R,i+R-1,e) + flux(e,j+nc*(i-1))/dx;
            res(j+R, i+R ,e) = res(j+R, i+R ,e) - flux(e,j+nc*(i-1))/dx;
        end
        res(j+R,nx-R,e) = res(j+R,nx-R,e) + flux(e,j+nc*(nf-1))/dx; % right face of cell j=N-3.
    end
end

% Compute primitive variables at solution points (they still in memory)
clear qL qR wL wR flux;

% internal cells and primitives array
ic=R+1:nx-R;  %w=zeros(ny,numel(ic),4);

% Compute primitive variables at solution points
% w = q(:,ic,:);

% 1. Reconstruct interface values: qL=q_{j+1/2}^{-} and qR=q_{j-1/2}^{+}
parfor e=1:E
    switch Recon
        case 'WENO5', [qL(e,:),qR(e,:)] = WENO5charWiseRecon_Y(q(ic,:,e),ny);
        %case 'WENO7', [qL(e,:),qR(e,:)] = WENO7charWiseRecon_Y(q(ic,:,e),ny);
    end
end

% 2. Compute finite volume residual term, df/dx.
flux=zeros(size(qL)); nc=nx-2*R; nf=ny+1-2*R; N=nc*nf;

% compute flux at (i,j+1/2)
for c=1:N
    switch fluxMethod
        case 'LF',  flux(:,c) = LFflux(qL(:,c),qR(:,c),[0,1],a); % Lax Friedrichs
        case 'ROE', flux(:,c) = ROEflux(qL(:,c),qR(:,c),[0,1]);  % Roe
        case 'RUS', flux(:,c) = RUSflux(qL(:,c),qR(:,c),[0,1]);  % Rusanov
        case 'HLLE',flux(:,c) = HLLEflux(qL(:,c),qR(:,c),[0,1]); % HLLE
        case 'HLLC',flux(:,c) = HLLCflux(qL(:,c),qR(:,c),[0,1]); % HLLC
    end
end

% Flux contribution to the residual of every cell
for e=1:E
    for i=1:nc % for all interior cells
        res(R+1,i+R,e) = res(R+1,i+R,e) - flux(e,1+nf*(i-1))/dy;
        for j=2:nf-1 % for all interior cells
            res(j+R-1,i+R,e) = res(j+R-1,i+R,e) + flux(e,j+nf*(i-1))/dy;
            res( j+R ,i+R,e) = res( j+R ,i+R,e) - flux(e,j+nf*(i-1))/dy;
        end
        res(ny-R,i+R,e) = res(ny-R,i+R,e) + flux(e,nf+nf*(i-1))/dy;
    end
end

end % FVM WENO

%%%%%%%%%%%%%%%%%%%
% Distance to shock (for Double Mach Reflection)
%%%%%%%%%%%%%%%%%%%

function distance = distance_to_shock(x,y,t)
    global shock_speed
    shock_slope = 1/tan(pi/6); % from problem definition
    wedge_position = 1/6; % from problem definition
    distance = (shock_slope*(x-wedge_position-shock_speed*t)-y) / sqrt((shock_slope)^2+1);
end

%%%%%%%%%%%%%%%%%
% Flux functions
%%%%%%%%%%%%%%%%%

function LF = LFflux(qL,qR,normal,smax)
    % Lax-Friedrichs flux
    global gamma

    % Normal vectors
    nx = normal(1);
    ny = normal(2);
    
    % Left state
    rL = qL(1);
    uL = qL(2)/rL;
    vL = qL(3)/rL;
    vnL= uL*nx + vL*ny;
    pL = (gamma-1)*( qL(4) - 0.5*rL*(uL^2+vL^2) );
    HL = ( qL(4) + pL ) / rL;
    
    % Right state
    rR = qR(1);
    uR = qR(2)/rR;
    vR = qR(3)/rR;
    vnR= uR*nx + vR*ny;
    pR = (gamma-1)*( qR(4) - 0.5*rR*(uR^2+vR^2) );
    HR = ( qR(4) + pR ) / rR;
    
    % Left and Right fluxes
    FL=[rL*vnL; rL*vnL*uL + pL*nx; rL*vnL*vL + pL*ny; rL*vnL*HL];
    FR=[rR*vnR; rR*vnR*uR + pR*nx; rR*vnR*vR + pR*ny; rR*vnR*HR];
    
    % Rusanov numerical flux
    LF = 0.5*( FR + FL + smax*(qL-qR) );
end

function Rusanov = RUSflux(qL,qR,normal)
    % Rusanov flux 
    global gamma
    
    % Normal vectors
    nx = normal(1);
    ny = normal(2);
    
    % Left state
    rL = qL(1);
    uL = qL(2)/rL;
    vL = qL(3)/rL;
    vnL= uL*nx + vL*ny;
    pL = (gamma-1)*( qL(4) - 0.5*rL*(uL^2+vL^2) );
    HL = ( qL(4) + pL ) / rL;

    % Right state
    rR = qR(1);
    uR = qR(2)/rR;
    vR = qR(3)/rR;
    vnR= uR*nx + vR*ny;
    pR = (gamma-1)*( qR(4) - 0.5*rR*(uR^2+vR^2) );
    HR = ( qR(4) + pR ) / rR;
    
    % First compute the Roe Averages
    RT = sqrt(rR/rL);
    %r= RT*rL;
    u = (uL+RT*uR)/(1+RT);
    v = (vL+RT*vR)/(1+RT);
    H = ( HL+RT* HR)/(1+RT);
    a = sqrt( (gamma-1)*(H-(u^2+v^2)/2) );
    
    % Left and Right fluxes
    FL=[rL*vnL; rL*vnL*uL + pL*nx; rL*vnL*vL + pL*ny; rL*vnL*HL];
    FR=[rR*vnR; rR*vnR*uR + pR*nx; rR*vnR*vR + pR*ny; rR*vnR*HR];
    
    % Rusanov numerical flux
    smax = abs(sqrt(u^2+v^2))+a; Rusanov = 0.5*( FR + FL + smax*(qL-qR) );
end

function Roe = ROEflux(qL,qR,normal)
    % Compute Roe flux
    global gamma
    
    % normal vectors
    nx = normal(1);
    ny = normal(2);
    
    % Tangent vectors
    tx = -ny;
    ty = nx;
    
    % Left state
    rL = qL(1);
    uL = qL(2)/rL;
    vL = qL(3)/rL;
    vnL = uL*nx+vL*ny;
    vtL = uL*tx+vL*ty;
    pL = (gamma-1)*( qL(4) - rL*(uL^2+vL^2)/2 );
    %aL = sqrt(gamma*pL/rL);
    HL = ( qL(4) + pL ) / rL;
    
    % Right state
    rR = qR(1);
    uR = qR(2)/rR;
    vR = qR(3)/rR;
    vnR = uR*nx+vR*ny;
    vtR = uR*tx+vR*ty;
    pR = (gamma-1)*( qR(4) - rR*(uR^2+vR^2)/2 );
    %aR = sqrt(gamma*pR/rR);
    HR = ( qR(4) + pR ) / rR;
    
    % First compute the Roe Averages
    RT = sqrt(rR/rL);
    r = RT*rL;
    u = (uL+RT*uR)/(1+RT);
    v = (vL+RT*vR)/(1+RT);
    H = ( HL+RT* HR)/(1+RT);
    a = sqrt( (gamma-1)*(H-(u^2+v^2)/2) );
    vn = u*nx+v*ny;
    vt = u*tx+v*ty;
    
    % Wave Strengths
    dr = rR - rL;     dp = pR - pL;     dvn= vnR - vnL;     dvt= vtR - vtL;
    dV = [(dp-r*a*dvn )/(2*a^2); r*dvt/a; dr-dp/(a^2); (dp+r*a*dvn)/(2*a^2)];
    
    % Wave Speed
    ws = [abs(vn-a); abs(vn); abs(vn); abs(vn+a)];
    
    % Harten's Entropy Fix JCP(1983), 49, pp357-393:
    % only for the nonlinear fields.
    dws(1)=1/5; if ws(1)<dws(1); ws(1)=( ws(1)*ws(1)/dws(1)+dws(1) )/2; end
    dws(4)=1/5; if ws(4)<dws(4); ws(4)=( ws(4)*ws(4)/dws(4)+dws(4) )/2; end
    
    % Right Eigenvectors       
    Rv = [  1   ,  0   ,    1      ,  1   ;
          u-a*nx, a*tx ,    u      ,u+a*nx;
          u-a*ny, a*ty ,    u      ,u+a*ny;
          H-vn*a, vt*a ,(u^2+v^2)/2,H+vn*a];
    
    % Left and Right fluxes
    FL=[rL*vnL; rL*vnL*uL + pL*nx; rL*vnL*vL + pL*ny; rL*vnL*HL];
    FR=[rR*vnR; rR*vnR*uR + pR*nx; rR*vnR*vR + pR*ny; rR*vnR*HR];
    
    % Dissipation Term
    Roe = (FL + FR - Rv*(ws.*dV))/2;

end

function HLLE = HLLEflux(qL,qR,normal)
    % Compute HLLE flux
    global gamma

    % normal vectors
    nx = normal(1);
    ny = normal(2);
       
    % Left state
    rL = qL(1);
    uL = qL(2)/rL;
    vL = qL(3)/rL;
    vnL = uL*nx+vL*ny;
    pL = (gamma-1)*( qL(4) - rL*(uL^2+vL^2)/2 );
    aL = sqrt(gamma*pL/rL);
    HL = ( qL(4) + pL ) / rL;
    
    % Right state
    rR = qR(1);
    uR = qR(2)/rR;
    vR = qR(3)/rR;
    vnR = uR*nx+vR*ny;
    pR = (gamma-1)*( qR(4) - rR*(uR^2+vR^2)/2 );
    aR = sqrt(gamma*pR/rR);
    HR = ( qR(4) + pR ) / rR;
    
    % First compute the Roe Averages
    RT = sqrt(rR/rL); % r = RT*rL;
    u = (uL+RT*uR)/(1+RT);
    v = (vL+RT*vR)/(1+RT);
    H = ( HL+RT* HR)/(1+RT);
    a = sqrt( (gamma-1)*(H-(u^2+v^2)/2) );
    vn = u*nx+v*ny;
    
    % Wave speed estimates
    SLm = min([ vnL-aL, vn-a, 0]);
    SRp = max([ vnR+aR, vn+a, 0]);
    
    % Left and Right fluxes
    FL=[rL*vnL; rL*vnL*uL + pL*nx; rL*vnL*vL + pL*ny; rL*vnL*HL];
    FR=[rR*vnR; rR*vnR*uR + pR*nx; rR*vnR*vR + pR*ny; rR*vnR*HR];
    
    % Compute the HLL flux.
    HLLE = ( SRp*FL - SLm*FR + SLm*SRp*(qR-qL) )/(SRp-SLm);
end

function HLLC = HLLCflux(qL,qR,normal)
    % Compute HLLC flux
    global gamma

    % normal vectors
    nx = normal(1);
    ny = normal(2);
    
    % Left state
    rL = qL(1);
    uL = qL(2)/rL;
    vL = qL(3)/rL;
    vnL = uL*nx+vL*ny;
    pL = (gamma-1)*( qL(4) - rL*(uL^2+vL^2)/2 );
    aL = sqrt(gamma*pL/rL);
    HL = ( qL(4) + pL ) / rL;
    
    % Right state
    rR = qR(1);
    uR = qR(2)/rR;
    vR = qR(3)/rR;
    vnR = uR*nx+vR*ny;
    pR = (gamma-1)*( qR(4) - rR*(uR^2+vR^2)/2 );
    aR = sqrt(gamma*pR/rR);
    HR = ( qR(4) + pR ) / rR;
       
    % Left and Right fluxes
    FL=[rL*vnL; rL*vnL*uL + pL*nx; rL*vnL*vL + pL*ny; rL*vnL*HL];
    FR=[rR*vnR; rR*vnR*uR + pR*nx; rR*vnR*vR + pR*ny; rR*vnR*HR];

    % Compute guess pressure from PVRS Riemann solver
    PPV  = max(0 , 0.5*(pL+pR) + 0.5*(vnL-vnR) * (0.25*(rL+rR)*(aL+aR)));
    pmin = min(pL,pR);
    pmax = max(pL,pR);
    Qmax = pmax/pmin;
    Quser= 2.0; % <--- parameter manually set (I don't like this!)
    
     if (Qmax <= Quser) && (pmin <= PPV) && (PPV <= pmax)
     % Select PRVS Riemann solver
         pM = PPV;
      else
         if PPV < pmin
         % Select Two-Rarefaction Riemann solver
            PQ  = (pL/pR)^(gamma - 1.0)/(2.0*gamma);
            uM  = (PQ*vnL/aL + vnR/aR + 2/(gamma-1)*(PQ-1.0))/(PQ/aL+1.0/aR);
            PTL = 1 + (gamma-1)/2.0*(vnL - uM)/aL;
            PTR = 1 + (gamma-1)/2.0*(uM - vnR)/aR;
            pM  = 0.5*(pL*PTL^(2*gamma/(gamma-1)) + pR*PTR^(2*gamma/(gamma-1)));
         else 
         % Use Two-Shock Riemann solver with PVRS as estimate
            GEL = sqrt((2/(gamma+1)/rL)/((gamma-1)/(gamma+1)*pL + PPV));
            GER = sqrt((2/(gamma+1)/rR)/((gamma-1)/(gamma+1)*pR + PPV));
            pM  = (GEL*pL + GER*pR - (vnR - vnL))/(GEL + GER);
         end
      end

    % Estimate wave speeds: SL, SR and SM (Toro, 1994)
    if pM>pL; zL=sqrt(1+(gamma+1)/(2*gamma)*(pM/pL-1)); else, zL=1; end    
    if pM>pR; zR=sqrt(1+(gamma+1)/(2*gamma)*(pM/pR-1)); else, zR=1; end
  
	SL = vnL - aL*zL;
    SR = vnR + aR*zR;
    SM = (pL-pR + rR*vnR*(SR-vnR) - rL*vnL*(SL-vnL))/(rR*(SR-vnR) - rL*(SL-vnL));
    
    % Compute the HLL flux.
    if (0 <= SL)  % Right-going supersonic flow
        HLLC = FL;
    elseif (SL <= 0) && (0 <= SM)	% Subsonic flow to the right
        qsL = rL*(SL-vnL)/(SL-SM)*[1; SM*nx+uL*abs(ny); SM*ny+vL*abs(nx); qL(4)/rL + (SM-vnL)*(SM+pL/(rL*(SL-vnL)))];
        HLLC = FL + SL*(qsL - qL);
    elseif (SM <= 0) && (0 <= SR)	% Subsonic flow to the Left
        qsR = rR*(SR-vnR)/(SR-SM)*[1; SM*nx+uR*abs(ny); SM*ny+vR*abs(nx); qR(4)/rR + (SM-vnR)*(SM+pR/(rR*(SR-vnR)))];
        HLLC = FR + SR*(qsR - qR);
    elseif	(0 >= SR) % Left-going supersonic flow
        HLLC = FR;
    end
end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% WENO and Polynomail reconstructions
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

function [qL,qR] = WENO5charWiseRecon_X(q,N)
% *************************************************************************
% Based on:
% [1] Jiang, Guang-Shan, and Cheng-chin Wu. "A high-order WENO finite
%     difference scheme for the equations of ideal magnetohydrodynamics."
%     Journal of Computational Physics 150.2 (1999): 561-594.
%
% coded by Manuel Diaz, 02.10.2012, NTU Taiwan.
% last update on 2016.04.29, NHRI Taiwan.
% *************************************************************************
%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
global gamma

R=3; EE=4; I=R:N-R; % R: substencil size, E: system components;
epweno=1E-40; gamma1=gamma-1;

evr=zeros(4,4,N-1);
evl=zeros(4,4,N-1);
h=zeros(2,N-1);

% compute and store the differences for the entire domain
dq = q(:,2:N,:)-q(:,1:N-1,:); % dq_{j+1/2}
    
% Compute the part of the reconstruction that is stencil-independent
qL = (-q(:,I-1,:)+7*(q(:,I,:)+q(:,I+1,:))-q(:,I+2,:))/12; qR = qL; % dq_{j+1/2}

% Compute eigenvectors at the cell interfaces j+1/2
for i = 2:N
    % Using simple mean
    r = (q(1,i-1)+q(1,i))/2;
    u = (q(2,i-1)+q(2,i))/(2*r);
    v = (q(3,i-1)+q(3,i))/(2*r);
    E = (q(4,i-1)+q(4,i))/2;
    U = 0.5*(u^2+v^2);
    p = gamma1*(E - 0.5*r*U^2);
    H = (E+p)/r;
    c2 = gamma1*(H - 0.5*U^2);
    c = sqrt(gamma*p/r);
    
    % Compute properties at cell interfaces using Roe avegares
    
    % Construct matrix of right eigenvectors
    %      _                     _ 
    %     |                       |
    %     |   1     1    0    1   |
    %     |                       |
    % R = |  u-c    u    0   u+c  |
    %     |                       |
    %     |   v     v    1    v   |
    %     |                       |
    %     |  H-uc   q    v   H+uc |
    %     |_                     _|
    %
    % where q = 0.5*(u^2+v^2) 
    
    evr(:,:,i-1) = [...
          1  , 1 , 0 ,  1  ;...
         u-c , u , 0 , u+c ;...
          v  , v , 1 ,  v  ;...
        H-u*c, U , v ,H+u*c];

    % Construct matrix of left eigenvectors
    %         _                                        _ 
    %        |                                          |
    %        | (g-1)*q+c*u  -(g-1)*u-c  -(g-1)*v  (g-1) |
    %        |  ----------   ---------   -------  ----- |
    %        |    2*c^2        2*c^2       2*c^2  2*c^2 |
    %        |                                          |
    % R^{-1}=| c^2-(g-1)*q    (g-1)*u    (g-1)*v -(g-1) |
    %        |  ----------    -------    -------  ----- |
    %        |      c^2         c^2        c^2     c^2  |
    %        |                                          |
    %        |      -v          0          1       0    |
    %        |                                          |
    %        | (g-1)*q-c*u  -(g-1)*u+c  -(g-1)*v  (g-1) |
    %        |  ----------   ---------   -------  ----- |
    %        |    2*c^2        2*c^2       2*c^2  2*c^2 |
    %        |_                                        _|
    %
    % where q = 0.5*(u^2+v^2) 

    evl(:,:,i-1) = [...
         (U*gamma1+c*u)/(2*c2),-(c+u*gamma1)/(2*c2),-(v*gamma1)/(2*c2), gamma1/(2*c2);...
         (c2 - U*gamma1)/c2   ,   (u*gamma1)/c2    , (v*gamma1)/c2    ,-(gamma1)/c2  ;...
                -v            ,         0          ,         1        ,        0     ;...
         (U*gamma1-c*u)/(2*c2), (c-u*gamma1)/(2*c2),-(v*gamma1)/(2*c2), gamma1/(2*c2)];
end

% Produce the WENO reconstruction
for ip=1:EE
    
    % Project the jumps at faces to the left characteristic space: qs
    for m2 =-2:2
       for i = I
          qs(m2+R,i) = 0;
          for e=1:EE      
            qs(m2+R,i) = qs(m2+R,i) + evl(ip,e,i)*dq(e,i+m2);
          end
       end
    end

    % the reconstruction
    for idx=1:2

        % idx=1: construct hn (qL)
        % idx=2: construct hp (qR)

        im=(-1)^(idx+1); i1=im+R; in1=-im+R; in2=-2*im+R;

        for i=I

            AmB=im*(qs(in2,i)-qs(in1,i));
            BmC=im*(qs(in1,i)-qs( R ,i));
            CmD=im*(qs( R ,i)-qs( i1,i));

            IS1=13*AmB^2+3*(  qs(in2,i)-3*qs(in1,i))^2;
            IS2=13*BmC^2+3*(  qs(in1,i)+  qs( R ,i))^2;
            IS3=13*CmD^2+3*(3*qs( R ,i)-  qs( i1,i))^2;

            IS1=(epweno+IS1)^2;
            IS2=(epweno+IS2)^2;
            IS3=(epweno+IS3)^2;
            s1=IS2*IS3; s2=6*IS1*IS3; s3=3*IS1*IS2;
            st0=1/(s1+s2+s3); s1=s1*st0; s3=s3*st0;

            h(idx,i) = (s1*(BmC-AmB)+(0.5*s3-0.25)*(CmD-BmC))/3;

        end % loop over interfaces
    end % loop over each side of interface

    % Project to the physical space:
    for e=1:EE
        for i=I
            qL(e,i+1-R) = qL(e,i+1-R) + evr(e,ip,i)*h(1,i);
            qR(e,i+1-R) = qR(e,i+1-R) + evr(e,ip,i)*h(2,i);
        end
    end
end

end

function [qL,qR] = WENO5charWiseRecon_Y(q,N)
% *************************************************************************
% Based on:
% [1] Jiang, Guang-Shan, and Cheng-chin Wu. "A high-order WENO finite
%     difference scheme for the equations of ideal magnetohydrodynamics."
%     Journal of Computational Physics 150.2 (1999): 561-594.
%
% coded by Manuel Diaz, 02.10.2012, NTU Taiwan.
% last update on 2016.04.29, NHRI Taiwan.
% *************************************************************************
%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
global gamma

R=3; EE=4; I=R:N-R; % R: substencil size, E: system components;
epweno=1E-40; gamma1=gamma-1;

evr=zeros(4,4,N-1);
evl=zeros(4,4,N-1);
h=zeros(2,N-1);

% compute and store the differences for the entire domain
dq = q(2:N,:,:)-q(1:N-1,:,:); % dq_{j+1/2}
    
% Compute the part of the reconstruction that is stencil-independent
qL = (-q(I-1,:,:)+7*(q(I,:,:)+q(I+1,:,:))-q(I+2,:,:))/12; qR = qL; % dq_{j+1/2}

% Compute eigenvectors at the cell interfaces j+1/2
for i = 2:N
    % Using simple mean
    r = (q(1,i-1)+q(1,i))/2;
    u = (q(2,i-1)+q(2,i))/(2*r);
    v = (q(3,i-1)+q(3,i))/(2*r);
    E = (q(4,i-1)+q(4,i))/2;
    U = 0.5*(u^2+v^2);
    p = gamma1*(E - 0.5*r*U^2);
    H = (E+p)/r;
    c2 = gamma1*(H - 0.5*U^2);
    c = sqrt(gamma*p/r);
    
    % Compute properties at cell interfaces using Roe avegares
    
    % Construct matrix of right eigenvectors
    %      _                    _ 
    %     |                      |
    %     |   1    0   1    1    |
    %     |                      |
    %     |   u    1   u    u    |
    %     |                      |
    % R = |  v-c   0   v   v+c   |
    %     |                      |
    %     |  H-vc  u   q   H+vc  |
    %     |_                    _|
    %
    % where q = 0.5*(u^2+v^2) 
    
    evr(:,:,i-1) = [...
          1  , 0 , 1 ,  1   ;...
          u  , 1 , u ,  u   ;...
         v-c , 0 , v , v+c  ;...
        H-v*c, u , U ,H+v*c];

    % Construct matrix of left eigenvectors
    %         _                                        _ 
    %        |                                          |
    %        | (g-1)*q+c*v  -(g-1)*u  -(g-1)*v-c  (g-1) |
    %        |  ----------   -------   ---------  ----- |
    %        |    2*c^2       2*c^2      2*c^2    2*c^2 |
    %        |                                          |
    % R^{-1}=|      -u          1          0       0    |
    %        |                                          |
    %        | c^2-(g-1)*q   (g-1)*u    (g-1)*v  -(g-1) |
    %        |  ----------   -------    -------   ----- |
    %        |      c^2        c^2        c^2      c^2  |
    %        |                                          |
    %        | (g-1)*q-c*v  -(g-1)*u  -(g-1)*v+c  (g-1) |
    %        |  ----------   -------   ---------  ----- |
    %        |    2*c^2       2*c^2      2*c^2    2*c^2 |
    %        |_                                        _|
    %
    % where q = 0.5*(u^2+v^2) 

    evl(:,:,i-1) = [...
         (U*gamma1+c*v)/(2*c2),-(u*gamma1)/(2*c2),-(c+v*gamma1)/(2*c2), gamma1/(2*c2);...
                -u            ,         1        ,         0          ,        0     ;...
         (c2 - U*gamma1)/c2   ,   (u*gamma1)/c2  ,   (v*gamma1)/c2    ,-(gamma1)/c2  ;...
         (U*gamma1-c*v)/(2*c2), (u*gamma1)/(2*c2), (c+v*gamma1)/(2*c2), gamma1/(2*c2)];
end

% Produce the WENO reconstruction
for ip=1:EE
    
    % Project the jumps at faces to the left characteristic space: qs
    for m2 =-2:2
       for i = I
          qs(m2+R,i) = 0;
          for e=1:EE      
            qs(m2+R,i) = qs(m2+R,i) + evl(ip,e,i)*dq(e,i+m2);
          end
       end
    end

    % the reconstruction
    for idx=1:2

        % idx=1: construct hn (qL)
        % idx=2: construct hp (qR)

        im=(-1)^(idx+1); i1=im+R; in1=-im+R; in2=-2*im+R;

        for i=I

            AmB=im*(qs(in2,i)-qs(in1,i));
            BmC=im*(qs(in1,i)-qs( R ,i));
            CmD=im*(qs( R ,i)-qs( i1,i));

            IS1=13*AmB^2+3*(  qs(in2,i)-3*qs(in1,i))^2;
            IS2=13*BmC^2+3*(  qs(in1,i)+  qs( R ,i))^2;
            IS3=13*CmD^2+3*(3*qs( R ,i)-  qs( i1,i))^2;

            IS1=(epweno+IS1)^2;
            IS2=(epweno+IS2)^2;
            IS3=(epweno+IS3)^2;
            s1=IS2*IS3; s2=6*IS1*IS3; s3=3*IS1*IS2;
            st0=1/(s1+s2+s3); s1=s1*st0; s3=s3*st0;

            h(idx,i) = (s1*(BmC-AmB)+(0.5*s3-0.25)*(CmD-BmC))/3;

        end % loop over interfaces
    end % loop over each side of interface

    % Project to the physical space:
    for e=1:EE
        for i=I
            qL(e,i+1-R) = qL(e,i+1-R) + evr(e,ip,i)*h(1,i);
            qR(e,i+1-R) = qR(e,i+1-R) + evr(e,ip,i)*h(2,i);
        end
    end
end

end