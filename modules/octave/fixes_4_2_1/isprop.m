## Copyright (C) 2010-2017 Ben Abbott
##
## This file is part of Octave.
##
## Octave is free software; you can redistribute it and/or modify it
## under the terms of the GNU General Public License as published by
## the Free Software Foundation; either version 3 of the License, or (at
## your option) any later version.
##
## Octave is distributed in the hope that it will be useful, but
## WITHOUT ANY WARRANTY; without even the implied warranty of
## MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
## General Public License for more details.
##
## You should have received a copy of the GNU General Public License
## along with Octave; see the file COPYING.  If not, see
## <http://www.gnu.org/licenses/>.

## -*- texinfo -*-
## @deftypefn {} {@var{res} =} isprop (@var{obj}, "@var{prop}")
## Return true if @var{prop} is a property of the object @var{obj}.
##
## @var{obj} may also be an array of objects in which case @var{res} will be a
## logical array indicating whether each handle has the property @var{prop}.
##
## For plotting, @var{obj} is a handle to a graphics object.  Otherwise,
## @var{obj} should be an instance of a class.
## @seealso{get, set, ismethod, isobject}
## @end deftypefn

## Author: Ben Abbott  <bpabbott@mac.com>

function res = isprop (obj, prop)

  if (nargin != 2)
    print_usage ();
  elseif (! ischar (prop))
    error ("isprop: PROP name must be a string");
  endif

  res = false (size (obj));
  for i = 1:numel (res)
    try
        v = obj(i).(prop);
        res(i) = true;
    end_try_catch
  endfor

endfunction
