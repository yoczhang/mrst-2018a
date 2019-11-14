function [problem, state] = equationsBlackOilDP(state0, state, model, dt, drivingForces, varargin)
% Generate linearized problem for the black-oil equations
%
% SYNOPSIS:
%   [problem, state] = equationsBlackOil(state0, state, model, dt, drivingForces)
%
% DESCRIPTION:
%   This is the core function of the black-oil solver. This function
%   assembles the residual equations for the conservation of water, oil and
%   gas, as well as required well equations. By default, Jacobians are also
%   provided by the use of automatic differentiation.
%
%   Oil can be vaporized into the gas phase if the model has the vapoil
%   property enabled. Analogously, if the disgas property is enabled, gas
%   is allowed to dissolve into the oil phase. Note that the fluid
%   functions change depending on vapoil/disgas being active and may have
%   to be updated when the property is changed in order to run a successful
%   simulation.
%
% REQUIRED PARAMETERS:
%   state0    - Reservoir state at the previous timestep. Assumed to have
%               physically reasonable values.
%
%   state     - State at the current nonlinear iteration. The values do not
%               need to be physically reasonable.
%
%   model     - ThreePhaseBlackOilModel-derived class. Typically,
%               equationsBlackOil will be called from the class
%               getEquations member function.
%
%   dt        - Scalar timestep in seconds.
%
%   drivingForces - Struct with fields:
%                   * W for wells. Can be empty for no wells.
%                   * bc for boundary conditions. Can be empty for no bc.
%                   * src for source terms. Can be empty for no sources.
%
% OPTIONAL PARAMETERS:
%   'Verbose'    -  Extra output if requested.
%
%   'reverseMode'- Boolean indicating if we are in reverse mode, i.e.
%                  solving the adjoint equations. Defaults to false.
%
%   'resOnly'    - Only assemble residual equations, do not assemble the
%                  Jacobians. Can save some assembly time if only the
%                  values are required.
%
%   'iterations' - Nonlinear iteration number. Special logic happens in the
%                  wells if it is the first iteration.
% RETURNS:
%   problem - LinearizedProblemAD class instance, containing the water, oil
%             and gas conservation equations, as well as well equations
%             specified by the WellModel class.
%
%   state   - Updated state. Primarily returned to handle changing well
%             controls from the well model.
%
% SEE ALSO:
%   equationsOilWater, ThreePhaseBlackOilModel

%{
Copyright 2009-2016 SINTEF ICT, Applied Mathematics.

This file is part of The MATLAB Reservoir Simulation Toolbox (MRST).

MRST is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

MRST is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with MRST.  If not, see <http://www.gnu.org/licenses/>.
%}
opt = struct('Verbose',     mrstVerbose,...
            'reverseMode', false,...
            'resOnly',     false,...
            'iteration',   -1);

opt = merge_options(opt, varargin{:});

% Shorter names for some commonly used parts of the model and forces.
s = model.operators;
f = model.fluid;
fm = model.fluid_matrix;
W = drivingForces.W;

% Properties of fracture at current timestep
[p, sW, sG, rs, rv, wellSol] = model.getProps(state, ...
    'pressure', 'water', 'gas', 'rs', 'rv', 'wellSol');
% Properties of fracture at previous timestep
[p0, sW0, sG0, rs0, rv0, wellSol0] = model.getProps(state0, ...
    'pressure', 'water', 'gas', 'rs', 'rv', 'wellSol');

% Properties of matrix at current timestep
[pom, swm, sgm, rsm, rvm] = model.getProps(state, ...
    'pom', 'swm', 'sgm', 'rsm', 'rvm');
% Properties of fracture at previous timestep
[pom0, swm0, sgm0, rsm0, rvm0] = model.getProps(state0, ...
    'pom', 'swm', 'sgm', 'rsm', 'rvm');


[wellVars, wellVarNames, wellMap] = model.FacilityModel.getAllPrimaryVariables(wellSol);


%Initialization of primary variables ----------------------------------
st  = model.getCellStatusVO(state,  1-sW-sG,   sW,  sG);
st0 = model.getCellStatusVO(state0, 1-sW0-sG0, sW0, sG0);

% Same for the matrix
stm  = model.getCellStatusVO(state,  1-swm-sgm,   swm,  sgm);
stm0 = model.getCellStatusVO(state0, 1-swm0-sgm0, swm0, sgm0);

if model.disgas || model.vapoil
    % X is either Rs, Rv or Sg, depending on each cell's saturation status
    x = st{1}.*rs + st{2}.*rv + st{3}.*sG;
    gvar = 'x';

    xm = stm{1}.*rsm + stm{2}.*rvm + stm{3}.*sgm;
    gvarm = 'xm';
else
    x = sG;
    gvar = 'sG';

    xm = sgm;
    gvarm = 'sgm';
end

if ~opt.resOnly
    if ~opt.reverseMode
        % define primary varible x and initialize
        [p, sW, x, pom, swm, xm, wellVars{:}] = ...
            initVariablesADI(p, sW, x, pom, swm, xm, wellVars{:});
    else
        x0 = st0{1}.*rs0 + st0{2}.*rv0 + st0{3}.*sG0;
        % Set initial gradient to zero
        wellVars0 = model.FacilityModel.getAllPrimaryVariables(wellSol0);
        [p0, sW0, wellVars0{:}] = ...
            initVariablesADI(p0, sW0, wellVars0{:}); %#ok
        clear zw
        [sG0, rs0, rv0] = calculateHydrocarbonsFromStatusBO(model, st0, 1-sW0, x0, rs0, rv0, p0);
    end
end

if ~opt.reverseMode
    % Compute values from status flags. If we are in reverse mode, these
    % values have already converged in the forward simulation.
    [sG, rs, rv, rsSat, rvSat] = calculateHydrocarbonsFromStatusBO(model, st, 1-sW, x, rs, rv, p);
    [sgm, rsm, rvm, rsSatm, rvSatm] = calculateHydrocarbonsFromStatusBO(model, stm, 1-swm, xm, rsm, rvm, pom);
end
% We will solve for pressure, water and gas saturation (oil saturation
% follows via the definition of saturations) and well rates + bhp.
primaryVars = {'pressure', 'sW', gvar, 'pom', 'swm', gvarm, wellVarNames{:}};

% Evaluate relative permeability
sO  = 1 - sW  - sG;
sO0 = 1 - sW0 - sG0;
[krW, krO, krG] = model.evaluateRelPerm({sW, sO, sG});

% Matrix oil saturations
som  = 1 - swm  - sgm;
som0 = 1 - swm0 - sgm0;

% Multipliers for properties
[pvMult, transMult, mobMult, pvMult0] = getMultipliers(model.fluid, p, p0);

% Modifiy relperm by mobility multiplier (if any)
krW = mobMult.*krW; krO = mobMult.*krO; krG = mobMult.*krG;

% Compute transmissibility
T = s.T.*transMult;

% Gravity gradient per face
gdz = model.getGravityGradient();

% Evaluate water properties
[vW, bW, mobW, rhoW, pW, upcw] = getFluxAndPropsWater_BO(model, p, sW, krW, T, gdz);
bW0 = f.bW(p0);

% Evaluate oil properties
[vO, bO, mobO, rhoO, p, upco] = getFluxAndPropsOil_BO(model, p, sO, krO, T, gdz, rs, ~st{1});
bO0 = getbO_BO(model, p0, rs0, ~st0{1});

% Evaluate gas properties
bG0 = getbG_BO(model, p0, rv0, ~st0{2});
[vG, bG, mobG, rhoG, pG, upcg] = getFluxAndPropsGas_BO(model, p, sG, krG, T, gdz, rv, ~st{2});

%% Properties for Matrix
pvMultm = pvMult;
pvMultm0 = pvMult0;

bWm = fm.bW(pom);bOm = getbO_BO(model, pom, rsm, ~stm{1});
bGm = getbO_BO(model, pom, rvm, ~stm{2});

bWm0 = fm.bW(pom0);
bOm0 = getbO_BO(model, pom0, rsm0, ~stm0{1});
bGm0 = getbO_BO(model, pom0, rvm0, ~stm0{2});

%% Transfer
vb = model.G.cells.volumes;

matrix_fields.pom = pom;
matrix_fields.swm = swm;
matrix_fields.sgm = sgm;

fracture_fields.pof = p;
fracture_fields.swf = sW;
fracture_fields.sgf = sG;

transfer_model = model.transfer_model_object;

[Talpha] = transfer_model.calculate_transfer(model,fracture_fields,matrix_fields);

Twm = vb.*Talpha{1};
Tom = vb.*Talpha{2};
Tgm = vb.*Talpha{3};

%% Store fluxes / properties for debugging / plotting, if requested.
if model.outputFluxes
    state = model.storeFluxes(state, vW, vO, vG);
end
if model.extraStateOutput
    state = model.storebfactors(state, bW, bO, bG);
    state = model.storeMobilities(state, mobW, mobO, mobG);
    state = model.storeUpstreamIndices(state, upcw, upco, upcg);

    state.Twm = double(Twm);
    state.Tom = double(Tom);
    state.Tgm = double(Tgm);
end


%% Upstream weight b factors and multiply by interface fluxes to obtain the
% fluxes at standard conditions.
bOvO = s.faceUpstr(upco, bO).*vO;
bWvW = s.faceUpstr(upcw, bW).*vW;
bGvG = s.faceUpstr(upcg, bG).*vG;

%% EQUATIONS -----------------------------------------------------------
% The first equation is the conservation of the water phase. This equation is
% straightforward, as water is assumed to remain in the aqua phase in the
% black oil model.
water_fracture = (s.pv/dt).*( pvMult.*bW.*sW - pvMult0.*bW0.*sW0 ) + s.Div(bWvW);
water_fracture = water_fracture + Twm;

% Second equation: mass conservation equation for the oil phase at surface
% conditions. This is any liquid oil at reservoir conditions, as well as
% any oil dissolved into the gas phase (if the model has vapoil enabled).
if model.vapoil
    % The model allows oil to vaporize into the gas phase. The conservation
    % equation for oil must then include the fraction present in the gas
    % phase.
    rvbGvG = s.faceUpstr(upcg, rv).*bGvG;
    % Final equation
    oil_fracture = (s.pv/dt).*( pvMult.* (bO.* sO  + rv.* bG.* sG) - ...
        pvMult0.*(bO0.*sO0 + rv0.*bG0.*sG0) ) + ...
        s.Div(bOvO + rvbGvG);
else
    oil_fracture = (s.pv/dt).*( pvMult.*bO.*sO - pvMult0.*bO0.*sO0 ) + s.Div(bOvO);
end
oil_fracture = oil_fracture + Tom;

% Conservation of mass for gas. Again, we have two cases depending on
% whether the model allows us to dissolve the gas phase into the oil phase.
if model.disgas
    % The gas transported in the oil phase.
    rsbOvO = s.faceUpstr(upco, rs).*bOvO;

    gas_fracture = (s.pv/dt).*( pvMult.* (bG.* sG  + rs.* bO.* sO) - ...
        pvMult0.*(bG0.*sG0 + rs0.*bO0.*sO0 ) ) + ...
        s.Div(bGvG + rsbOvO);
else
    gas_fracture = (s.pv/dt).*( pvMult.*bG.*sG - pvMult0.*bG0.*sG0 ) + s.Div(bGvG);
end
gas_fracture = gas_fracture + Tgm;

eqs = {water_fracture, oil_fracture, gas_fracture};

% Matrix
% Conservation of mass for water - matrix
water_matrix = (s.pv_matrix/dt).*( pvMultm.*bWm.*swm - pvMultm0.*bWm0.*swm0 );
water_matrix = water_matrix - Twm;

% Matrix
% Conservation of mass for oil - matrix
if model.vapoil
    % Final equation
    oil_matrix = (s.pv_matrix/dt).*( pvMultm.* (bOm.* som  + rvm.* bGm.* sgm) - ...
        pvMultm0.*(bOm0.*som0 + rvm0.*bGm0.*sgm0) );
else
    oil_matrix = (s.pv_matrix/dt).*( pvMultm.*bOm.*som - pvMultm0.*bOm0.*som0 );
end
oil_matrix = oil_matrix - Tom;

% Matrix
% Conservation of mass for gas - matrix
if model.disgas
    gas_matrix = (s.pv_matrix/dt).*( pvMultm.* (bGm.* sgm  + rsm.* bOm.* som) - ...
        pvMultm0.*(bGm0.*sgm0 + rsm0.*bOm0.*som0 ) );
else
    gas_matrix = (s.pv_matrix/dt).*( pvMultm.*bGm.*sgm - pvMultm0.*bGm0.*sgm0 );
end
gas_matrix = gas_matrix - Tgm;

eqs{4} = water_matrix;
eqs{5} = oil_matrix;
eqs{6} = gas_matrix;

% Put the set of equations into cell arrays along with their names/types.
names = {'water', 'oil', 'gas','water_matrix', 'oil_matrix', 'gas_matrix'};
types = {'cell', 'cell', 'cell', 'cell', 'cell','cell'};

dissolved = model.getDissolutionMatrix(rs, rv);
rho = {rhoW, rhoO, rhoG};
mob = {mobW, mobO, mobG};
sat = {sW, sO, sG};

[eqs, state] = addBoundaryConditionsAndSources(model, eqs, names, types, state, ...
                                                 {pW, p, pG}, sat, mob, rho, ...
                                                 dissolved, {}, ...
                                                 drivingForces);
% Add in and setup well equations
[eqs, names, types, state.wellSol] = model.insertWellEquations(eqs, names, types, wellSol0, wellSol, wellVars, wellMap, p, mob, rho, dissolved, {}, dt, opt);

problem = LinearizedProblem(eqs, types, names, primaryVars, state, dt);
end
