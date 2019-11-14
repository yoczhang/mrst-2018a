function [L, x, y, Z_L, Z_V, rhoL, rhoV] = standaloneFlash(p, T, z, EOSModel)
% Utility for flashing without explicitly forming a state
%
% SYNOPSIS:
%   [L, x, y, Z_L, Z_V] = standaloneFlash(p, T, z, EOSModel)
%
% DESCRIPTION:
%   Wrapper function for solving a EOS flash without dealing with a state.
%
% PARAMETERS:
%   p   - Pressures as a column vector
%   T   - Temperatures as a column vector
%   z   - Composition as a matrix with number of rows equal to the number
%         of components.
%
% SEE ALSO:
%   `EquationOfStateModel`

%{
Copyright 2009-2017 SINTEF Digital, Mathematics & Cybernetics.

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
    solver = getDefaultFlashNonLinearSolver();
    
    state = struct();

    state.pressure = p;
    state.T = T;
    state.components = z;
    
    state = EOSModel.validateState(state);
    state = solver.solveTimestep(state, 1, EOSModel);
    
    L = state.L;
    x = state.x;
    y = state.y;
    Z_L = state.Z_L;
    Z_V = state.Z_V;
    
    rhoL = EOSModel.PropertyModel.computeDensity(p, x, Z_L, T, true);
    rhoV = EOSModel.PropertyModel.computeDensity(p, y, Z_V, T, false);
end
