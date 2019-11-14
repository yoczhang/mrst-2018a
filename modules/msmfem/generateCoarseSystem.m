function CS = generateCoarseSystem(G, rock, S, CG, mob, varargin)
%Construct coarse system component matrices from fine grid model.
%
% SYNOPSIS:
%   CS = generateCoarseSystem(G, rock, S, CG, Lt)
%   CS = generateCoarseSystem(G, rock, S, CG, Lt, 'pn1', pv1, ...)
%
% PARAMETERS:
%   G       - Grid structure as described by grid_structure.
%
%   rock    - Rock data structure with valid field 'perm'. If the basis
%             functions are to be weighted by porosity, rock must also
%             contain a valid field 'poro'.
%
%   S       - System struture describing the underlying fine grid model,
%             particularly the individual cell flux inner products.
%
%   CG      - Coarse grid structure as defined by generateCoarseGrid.
%
%   mob     - Total mobility.  One scalar value for each cell in the
%             underlying (fine) model.
%
%   'pn'/pv - List of 'key'/value pairs defining optional parameters.  The
%             supported options are:
%               - Verbose --
%                        Whether or not to emit progress reports while
%                        computing basis functions.
%                        Logical.  Default value dependent upon global
%                        verbose setting in function 'mrstVerbose'.
%
%               - bc  -- Boundary condtion structure as defined by function
%                        'addBC'.  This structure accounts for all external
%                        boundary contributions to the reservoir flow.
%                        Default value: bc = [] meaning all external
%                        no-flow (homogeneous Neumann) conditions.
%
%               - src -- Explicit source contributions as defined by
%                        function 'addSource'.
%                        Default value: src = [] meaning no explicit
%                        sources exist in the model.
%
%               - global_inf --
%                        global information from fine scale solution
%                        (fineSol.faceFlux) to be used as boundary
%                        condition when calculating basis for coarse faces
%                        in the interior of the domain.
%
%               - Overlap --
%                        Number of fine-grid cells in each physical
%                        direction with which to extend the supporting
%                        domain of any given basis functions.
%
%                        Using overlapping domains enables capturing more
%                        complex flow patterns, particularly for very
%                        coarse grids, at the expense of increased coupling
%                        in the resulting systems of linear equations.
%                        Non-negative integers.  Default value = 0.
%
%               - BasisWeighting --
%                        Basis function driving source term as supported by
%                        function 'evalBasisSource'.
%
%               - ActiveBndFaces --
%                        Vector of active coarse boundary faces.
%                        Default value=[] (only no-flow BC).  We remark
%                        that coarse faces with prescribed fine-scale BC's
%                        are always considered active.
%
% RETURNS:
%   CS - System structure having the following fields:
%          - basis   - Flux basis functions as generated by function
%                      evalBasisFunc.
%          - basisP  - Pressure basis functions as generated by function
%                      evalBasisFunc.
%          - C       - C in coarse hybrid system.
%          - D       - D in coarse hybrid system.
%          - sizeC   - size of C (== size(CS.C))
%          - sizeD   - size of D (== size(CS.D))
%
% SEE ALSO:
%   `computeMimeticIP`, `generateCoarseGrid`, `evalBasisFunc`, `mrstVerbose`.

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

mrstNargInCheck(5, [], nargin);

[verbose, weight, weighting, overlap, activeBnd, ...
   src, bc, global_inf] = parse_args(G, CG, rock, varargin{:});

% Determine boundary faces for which basis functions will be assigned.
%
if ~isempty(bc),
   activeBnd = unique([activeBnd; has_bc(G, CG, bc)]);
end

%% Generate basis (method dependent upon system type)
%
activeFaces = [find(all(CG.faces.neighbors > 0, 2)); activeBnd];
CS.basis    = cell([CG.faces.num, 1]);
CS.basisP   = cell([CG.faces.num, 1]);

cellNo  = rldecode(1:G.cells.num, diff(G.cells.facePos), 2) .';
C       = sparse(1:numel(cellNo), cellNo, 1);
D       = sparse(1:numel(cellNo), double(G.cells.faces(:,1)), 1, ...
                 numel(cellNo), G.faces.num);

if isempty(global_inf),
   [V, P] = evalBasisFunc(activeFaces, G, CG, S.BI, C, D,    ...
                          weight, mob, 'src', src, 'bc', bc, ...
                          'Verbose', verbose, 'Overlap', overlap);
else
   [V, P] = evalBasisFuncGlobal(activeFaces, G, CG, S.BI, C, D,      ...
                                weight, mob, global_inf, 'src', src, ...
                                'bc', bc, 'Verbose', verbose,        ...
                                'Overlap', overlap);
end

CS = assignBasisFuncs(CS, V, P);


%% Define coarse system structure 'CS'.
%
% 1) Compute coarse grid matrices C and D.
% Note: The saturation dependent coarse mass matrix B is evaluated in
%       function 'solveIncompFlowMS'

% Compute sizes for matrices 'B', 'C', and 'D'.  Includes all faces, even
% faces for which there are no associated degrees of freedom.
sizeB    = size(CG.cells.faces, 1) * [1, 1];
sizeC    = [sizeB(1), double(CG.cells.num)];
sizeD    = [sizeB(1), double(CG.faces.num)];

% Compute topology matrices (C and D).
topo_mat = @(j,n) sparse(1:numel(j), double(j), 1, numel(j), n);
cellNo   = rldecode(1:CG.cells.num, diff(CG.cells.facePos), 2).';
CS.C     = topo_mat(cellNo             , sizeC(2));
CS.D     = topo_mat(CG.cells.faces(:,1), sizeD(2));

% 2) Define degrees of freedom and basis function weighting scheme.
%
CS.basisWeighting  = weighting;
CS.activeFaces     = activeFaces;
CS.activeCellFaces = find(sum(CS.D(:,activeFaces), 2));

% 3) Assign system matrix sizes for ease of implementation elsewhere.
CS.type  = S.type;
CS.sizeB = sizeB;
CS.sizeC = sizeC;
CS.sizeD = sizeD;

%-----------------------------------------------------------------------
% Private helpers follow
%-----------------------------------------------------------------------


function [verbose, weight, weighting, overlap, activeBnd, ...
      src, bc, global_inf] = parse_args(G, CG, rock, varargin)
opt = struct('Verbose',        false,  ...
             'BasisWeighting', 'perm', ...
             'Overlap',        0,      ...
             'ActiveBndFaces', [],     ...
             'src', [], 'bc', [],      ...
             'global_inf', []);
opt = merge_options(opt, varargin{:});

verbose    = opt.Verbose;
weighting  = opt.BasisWeighting;
overlap    = opt.Overlap;
activeBnd  = opt.ActiveBndFaces;
src        = opt.src;
bc         = opt.bc;
global_inf = opt.global_inf;

weight     = evalBasisSource(G, weighting, rock);

if any(activeBnd > CG.faces.num),
   nonext = activeBnd(activeBnd > CG.faces.num);
   s = ''; if numel(nonext) > 1, s = 's'; end
   error(id('CoarseFace:NonExistent'), ...
         ['Cowardly refusing to assign basis function on ', ...
          'non-existent coarse face%s: [%s].'], s, int2str(nonext));
elseif any(~any(CG.faces.neighbors(activeBnd,:) == 0, 2)),
   error(id('ActiveBndFaces:NotBoundary'), ...
        ['I am confused. At least one of the purported ', ...
         '''activeBndFaces'' isn''t. A boundary face, that is...']);
end

%-----------------------------------------------------------------------

function ix = has_bc(g, cg, bc)
[nsub, sub] = subFaces(g, cg);
f2c         = sparse(sub, 1, rldecode((1 : double(cg.faces.num)) .', nsub));

% Note:
%   This code assumes that any Neumann conditions specified on the fine
%   scale grid amounts to flow only one way across a coarse face.  If the
%   Neumann conditions amount to zero net flow across a coarse face, the
%   resulting flux basis function is undefined...
%
flow_support                 = false([cg.faces.num, 1]);
flow_support(f2c([bc.face])) = true;

ix = find(flow_support);

%-----------------------------------------------------------------------

function s = id(s)
s = ['generateCoarseSystem:', s];
