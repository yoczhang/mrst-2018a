function [problem, state] = pressureEquationBlackOil(state0, state, model, dt, drivingForces, varargin)

opt = struct('Verbose', mrstVerbose, ...
             'reverseMode', false,...
             'resOnly', false,...
             'staticWells',  false, ...
             'propsPressure', [], ...
             'iteration', -1);

opt = merge_options(opt, varargin{:});

W = drivingForces.W;

s = model.operators;
f = model.fluid;

disgas = model.disgas;
vapoil = model.vapoil;

% Properties at current timestep
[p, sW, sO, sG, rs, rv, wellSol] = model.getProps(state, ...
                                'pressure', 'water', 'oil', 'gas', 'rs', 'rv', 'wellSol');
% Properties at previous timestep
[p0, sW0, sO0, sG0, rs0, rv0, wellSol0] = model.getProps(state0, ...
                                'pressure', 'water', 'oil', 'gas', 'rs', 'rv', 'wellSol');


[wellVars, wellVarNames, wellMap] = model.FacilityModel.getAllPrimaryVariables(wellSol);



%Initialization of independent variables ----------------------------------
st  = model.getCellStatusVO(state,  sO,   sW,  sG);
st0 = model.getCellStatusVO(state0, sO0, sW0, sG0);
p_prop = opt.propsPressure;
otherPropPressure = ~isempty(p_prop);
if ~opt.resOnly
    if ~opt.reverseMode
        % define primary varible x and initialize
        if disgas || vapoil
            x = st{1}.*rs + st{2}.*rv + st{3}.*sG;
        end

        [p, wellVars{:}] = model.AutoDiffBackend.initVariablesAD(p, wellVars{:});
        if ~otherPropPressure
            p_prop = p;
        end
        if disgas || vapoil
            % define sG, rs and rv in terms of x
            sG = st{2}.*(1-sW) + st{3}.*x;
            if disgas
                rsSat = f.rsSat(p_prop);
                rs = (~st{1}).*rsSat + st{1}.*x;
            end
            if vapoil
                rvSat = f.rvSat(p_prop);
                rv = (~st{2}).*rvSat + st{2}.*x;
            end
        end
    else
        assert(0, 'Backwards solver not supported for splitting');
    end
else % resOnly-case compute rsSat and rvSat for use in well eqs
    if isempty(p_prop)
        p_prop = p;
    end
end

primaryVars = {'pressure', wellVarNames{:}};

% FLIUD PROPERTIES ---------------------------------------------------
[krW, krO, krG] = model.evaluateRelPerm({sW, sO, sG});

% Multipliers for properties
[pvMult, transMult, mobMult, pvMult0] = getMultipliers(model.fluid, p_prop, p0);

% Modifiy relperm by mobility multiplier (if any)
krW = mobMult.*krW; krO = mobMult.*krO; krG = mobMult.*krG;

% Compute transmissibility
T = s.T.*transMult;

% Gravity gradient per face
gdz = model.getGravityGradient();

% Evaluate water properties
[vW, bW, mobW, rhoW, pW, upcw, dpW] = getFluxAndPropsWater_BO(model, p_prop, sW, krW, T, gdz);
bW0 = f.bW(p0);

% Evaluate oil properties
[vO, bO, mobO, rhoO, pO, upco, dpO] = getFluxAndPropsOil_BO(model, p_prop, sO, krO, T, gdz, rs, ~st{1});
bO0 = getbO_BO(model, p0, rs0, ~st0{1});

% Evaluate gas properties
bG0 = getbG_BO(model, p0, rv0, ~st0{2});
[vG, bG, mobG, rhoG, pG, upcg, dpG] = getFluxAndPropsGas_BO(model, p_prop, sG, krG, T, gdz, rv, ~st{2});

if otherPropPressure
    % We have used a different pressure for property evaluation, undo the
    % effects of this on the fluxes.
    dp_diff = s.Grad(p) - s.Grad(p_prop);
    
    vW = -s.faceUpstr(upcw, mobW).*s.T.*(dpW + dp_diff);
    vO = -s.faceUpstr(upco, mobO).*s.T.*(dpO + dp_diff);
    vG = -s.faceUpstr(upcg, mobG).*s.T.*(dpG + dp_diff);
end


% These are needed in transport solver, so we output them regardless of
% any flags set in the model.
state = model.storeFluxes(state, vW, vO, vG);
state = model.storeUpstreamIndices(state, upcw, upco, upcg);
if model.extraStateOutput
    state = model.storebfactors(state, bW, bO, bG);
    state = model.storeMobilities(state, mobW, mobO, mobG);
end
% EQUATIONS -----------------------------------------------------------

% Upstream weight b factors and multiply by interface fluxes to obtain the
% fluxes at standard conditions.
bOvO = s.faceUpstr(upco, bO).*vO;
bWvW = s.faceUpstr(upcw, bW).*vW;
bGvG = s.faceUpstr(upcg, bG).*vG;

% The first equation is the conservation of the water phase. This equation is
% straightforward, as water is assumed to remain in the aqua phase in the
% black oil model.
wat = (s.pv/dt).*( pvMult.*bW.*sW - pvMult0.*bW0.*sW0 ) + s.Div(bWvW);

% Second equation: mass conservation equation for the oil phase at surface
% conditions. This is any liquid oil at reservoir conditions, as well as
% any oil dissolved into the gas phase (if the model has vapoil enabled).
if model.vapoil
    % The model allows oil to vaporize into the gas phase. The conservation
    % equation for oil must then include the fraction present in the gas
    % phase.
    rvbGvG = s.faceUpstr(upcg, rv).*bGvG;
    % Final equation
    oil = (s.pv/dt).*( pvMult.* (bO.* sO  + rv.* bG.* sG) - ...
        pvMult0.*(bO0.*sO0 + rv0.*bG0.*sG0) ) + ...
        s.Div(bOvO + rvbGvG);
else
    oil = (s.pv/dt).*( pvMult.*bO.*sO - pvMult0.*bO0.*sO0 ) + s.Div(bOvO);
end

% Conservation of mass for gas. Again, we have two cases depending on
% whether the model allows us to dissolve the gas phase into the oil phase.
if model.disgas
    % The gas transported in the oil phase.
    rsbOvO = s.faceUpstr(upco, rs).*bOvO;
    
    gas = (s.pv/dt).*( pvMult.* (bG.* sG  + rs.* bO.* sO) - ...
        pvMult0.*(bG0.*sG0 + rs0.*bO0.*sO0 ) ) + ...
        s.Div(bGvG + rsbOvO);
else
    gas = (s.pv/dt).*( pvMult.*bG.*sG - pvMult0.*bG0.*sG0 ) + s.Div(bGvG);
end
eqs = {wat, oil, gas};
names = {'water', 'oil', 'gas'};
types = {'cell', 'cell', 'cell'};

rho = {rhoW, rhoO, rhoG};
mob = {mobW, mobO, mobG};
sat = {sW, sO, sG};
dissolved = model.getDissolutionMatrix(rs, rv);

[eqs, state] = addBoundaryConditionsAndSources(model, eqs, names, types, state, ...
                                             {pW, p, pG}, sat, mob, rho, ...
                                             dissolved, {}, ...
                                             drivingForces);

% Finally, add in and setup well equations
[eqs, names, types, state.wellSol] = model.insertWellEquations(eqs, names, types, wellSol0, wellSol, wellVars, wellMap, p, mob, rho, dissolved, {}, dt, opt);

% Create actual pressure equation
cfac = 1./(1 - disgas*vapoil*rs.*rv);

a_w = 1./bW;
a_o = cfac.*(1./bO - disgas*rs./bG);
a_g = cfac.*(1./bG - vapoil*rv./bO);

wat = eqs{1};
oil = eqs{2};
gas = eqs{3};

eqs{1} = (dt./s.pv).*(oil.*a_o + wat.*a_w + gas.*a_g);
names{1} = 'pressure';
types{1} = 'cell';

% Strip phase equations
eqs = eqs([1, 4:end]);
names = names([1, 4:end]);
types = types([1, 4:end]);

state.timestep = dt;
problem = LinearizedProblem(eqs, types, names, primaryVars, state, dt);
end

%{
Copyright 2009-2018 SINTEF ICT, Applied Mathematics.

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

