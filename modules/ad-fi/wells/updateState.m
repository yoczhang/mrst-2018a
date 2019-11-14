function [state, nInc] = updateState(W, state, dx, f, system)
stepOpts = system.stepOptions;

dpMax = stepOpts.dpMax;
dp  = dx{1};
dp = sign(dp).*min(abs(dp), abs(dpMax.*state.pressure));

dsMax = stepOpts.dsMax;
dsw = dx{2};
dsw = sign(dsw).*min(abs(dsw), dsMax);

dsg = dx{3};
dsg = sign(dsg).*min(abs(dsg), dsMax);

drsMax = stepOpts.drsMax;
drs = dx{4};
drs = sign(drs).*min(abs(drs), abs(drsMax.*state.rs));

cap = @(x) max(x, 0);
capone = @(x) min(x, 1);

nInc = max( [norm(dp,'inf')/norm(state.pressure, 'inf'), ...
             norm(dsw,'inf'), ...
             norm(dsg,'inf'), ...
             norm(drs,'inf')/norm(state.rs, 'inf')] );

% state0 = state;
assert(all(isfinite(nInc)))
% relax = min([2./max(abs([dx{2}, dx{3}])), 1]);

pressure = cap(state.pressure + dp);

sg0 = state.s(:,3);
sg = sg0 + dsg;


rs       = cap(state.rs + drs);
rsSat    = f.rsSat(pressure);
rsSat    = cap(rsSat); % nothing guarantees (use of interpolation) that
                       % rsSat(p)<0.

% Appleyard process:
% sg = 0        -> rs > rsSat || sg > 0 => sg = eps, rs = rsMax
% sg > eps      -> sg <= 0              => sg = eps, rs = rsMax
% 0 < sg <= eps -> sg <= 0              => sg = 0,   rs = rsMax
epsilon = sqrt(eps);
% An "above" epsilon value to use to handle the scaling of the total
% saturations. If we set a value directly to epsilon it may be scaled away
% from the accurate value due to the scaling of total saturations (sum -> 1)
aboveEpsilon = 2*epsilon;

rsAdjust = 1.0;

sat2usat = and(sg0 > 0, sg <= 0);
overSaturated = (sg > 0 | rs > rsSat*rsAdjust) & ~sat2usat;

usat2sat = and(sg0 < epsilon, overSaturated);

sg( and(sat2usat, sg0 <= aboveEpsilon) ) = 0;
sg( and(sat2usat, sg0 >  epsilon) ) = epsilon;


sg(usat2sat) = aboveEpsilon;
rs(sg>0) = rsSat(sg>0);

rs(rs > rsSat*rsAdjust) = rsSat(rs > rsSat*rsAdjust);

sw       = cap(state.s(:,1) + dsw);
sw       = capone(sw);

sg       = cap(sg);
sg       = capone(sg);

so = cap(1-sw-sg);
so = capone(so);

%Update state:
state.s = bsxfun(@rdivide, [sw so sg], sw + so + sg);

state.pressure = pressure;
state.rs       = rs;

state.rs(sw == 1) = rsSat(sw == 1);

% Basic consistency checks
assert(all(abs(sum(state.s, 2) - 1) < 1e-8))
assert(all(rs - rsSat <= eps(rs - rsSat)))
assert(all(rs >= 0))
assert(all(state.s(:) >= 0))

%wells:
if ~stepOpts.solveWellEqs
    dpBH = dx{8};
    dpBH = sign(dpBH).*min(abs(dpBH), abs(dpMax.*vertcat(state.wellSol.bhp)));

    dqWs  = dx{5};
    dqOs  = dx{6};
    dqGs  = dx{7};

    for w = 1:numel(state.wellSol)
        state.wellSol(w).bhp = state.wellSol(w).bhp + dpBH(w);
        state.wellSol(w).qWs      = state.wellSol(w).qWs + dqWs(w);
        state.wellSol(w).qOs      = state.wellSol(w).qOs + dqOs(w);
        state.wellSol(w).qGs      = state.wellSol(w).qGs + dqGs(w);
    end
end
end
