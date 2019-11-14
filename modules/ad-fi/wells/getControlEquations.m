function eq = getControlEquations(sol, pBH, q_s, status, mix_s, model)

[iw, io, ig] = getPhaseInx(model);
type = {sol.type}';
val  = vertcat(sol.val);
qt_s = q_s{1};
for ph = 2:numel(q_s)
    qt_s = qt_s + q_s{ph};
end

setToZeroRate = and(val ==0, ~cellfun(@(x)strcmp('bhp',x), type));

eq = pBH; %just to initialize to whatever class pBH is
% bhp (injector or producer)
inx = find(cellfun(@(x)strcmp('bhp',x), type));
if ~isempty(inx)
    eq(inx) = pBH(inx) - val(inx);
end

%rate (injector
inx = find(cellfun(@(x)strcmp('rate',x), type));
if ~isempty(inx)
    eq(inx) = qt_s(inx) - val(inx);
end

%orat (producer)
inx = find(cellfun(@(x)strcmp('orat',x), type));
if ~isempty(inx)
    eq(inx) = q_s{io}(inx)-val(inx);
    prob    = mix_s(inx,io)==0;
    setToZeroRate(inx(prob)) = true;
end

%wrat (producer)
inx = find(cellfun(@(x)strcmp('wrat',x), type));
if ~isempty(inx)
    eq(inx) = q_s{iw}(inx)-val(inx);
    prob    = mix_s(inx,iw)==0;
    setToZeroRate(inx(prob)) = true;
end

%grat (producer)
inx = find(cellfun(@(x)strcmp('grat',x), type));
if ~isempty(inx)
    eq(inx) = q_s{ig}(inx)-val(inx);
    prob    = mix_s(inx,ig)==0;
    setToZeroRate(inx(prob)) = true;
end

%lrat (producer)
inx = find(cellfun(@(x)strcmp('lrat',x), type));
if ~isempty(inx)
    eq(inx) = q_s{iw}(inx)+q_s{io}(inx)-val(inx);
    prob    = (mix_s(inx,iw)+mix_s(inx,io))==0;
    setToZeroRate(inx(prob)) = true;
end

%vrat (producer) - special volume rate
inx = find(cellfun(@(x)strcmp('vrat',x), type));
if ~isempty(inx)
    eq(inx) = qt_s(inx)-val(inx);
end

%rate is zero or control on phaserate impossible
if ~isempty(setToZeroRate)
    eq(setToZeroRate) = qt_s(setToZeroRate);
end

end
%--------------------------------------------------------------------------
function [iw, io, ig] = getPhaseInx(model)
switch model
    case 'OW'
        iw = 1; io = 2; ig = [];
    case 'WG'
        iw = 1; io = []; ig = 1;
    case {'3P', 'BO', 'VO'}
        iw = 1; io = 2; ig = 3;
end
end

