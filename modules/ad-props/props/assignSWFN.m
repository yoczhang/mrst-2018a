function f = assignSWFN(f, swfn, reg)
f.krW  = @(sw, varargin)krW(sw, swfn, reg, varargin{:});
f.pcOW = @(sw, varargin)pcOW(sw, swfn, reg, varargin{:});
swcon = cellfun(@(x)x(1,1), swfn);
ntsat = numel(reg.SATINX);
if ntsat == 1
    f.sWcon = swcon(1);
else
    f.sWcon = swcon(reg.SATNUM);
end

if isfield(reg, 'SURFNUM')
   % Assign miscible relperm for surfactant
   f.krWSft  = @(sw, varargin)krWSft(sw, swfn, reg, varargin{:});
   % Assign residual water saturation for surfactant
   f.sWconSft = swcon(reg.SURFNUM);
   % Assign residual oil saturation
   sOres  = cellfun(@(x)x(end, 1), swfn);
   f.sOres = 1 - sOres(reg.SATNUM);
   f.sOresSft = 1 - sOres(reg.SURFNUM);
end

end

function v = krW(sw, swfn, reg, varargin)
satinx = getRegMap(sw, reg.SATNUM, reg.SATINX, varargin{:});
T = cellfun(@(x)x(:,[1,2]), swfn, 'UniformOutput', false);
T = extendTab(T);
v = interpReg(T, sw, satinx);
end

function v = pcOW(sw, swfn, reg, varargin)
satinx = getRegMap(sw, reg.SATNUM, reg.SATINX, varargin{:});
T = cellfun(@(x)x(:,[1,3]), swfn, 'UniformOutput', false);
T = extendTab(T);
v = interpReg(T, sw, satinx);
end

function v = krWSft(sw, swfn, reg, varargin)
surfinx = getRegMap(sw, reg.SURFNUM, reg.SURFINX, varargin{:});
T = cellfun(@(x)x(:,[1,2]), swfn, 'UniformOutput', false);
T = extendTab(T);
v = interpReg(T, sw, surfinx);
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
