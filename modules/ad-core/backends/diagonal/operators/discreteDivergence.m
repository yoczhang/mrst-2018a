function v = discreteDivergence(N, v, nc, nf, sortIx, C)
% Discrete divergence for the NewAD library
    if isa(v, 'NewAD')
        for i = 1:numel(v.jac)
            v.jac{i} = divJac(v.jac{i}, N, nc, nf, sortIx, C);
        end
        v.val = accumulate(N, double(v), nc);
    else
        v = accumulate(N, double(v), nc);
    end
end

function v = accumulate(N, v, nc)
    v = accumarray(N(:, 1), v, [nc, 1]) - accumarray(N(:, 2), v, [nc, 1]);
end

function jac = divJac(jac, N, nc, nf, sortIx, C)
    useDivTerm = false;
    if issparse(jac)
        if nnz(jac) > 0
            if isempty(C)
                C  = sparse(N, [(1:nf)'; (1:nf)'], ones(nf,1)*[1 -1], nc, nf);
            end
            jac = C*jac;
        else
            if useDivTerm
                jac = DivergenceTerm([], [], [], nc, prod(jac.dim));
            else
                jac = sparse([], [], [], nc, matrixDims(jac, 2));
            end
        end
    elseif jac.isZero
        if useDivTerm
            jac = DivergenceTerm([], [], [], nc, prod(jac.dim));
        else
            jac = sparse([], [], [], nc, prod(jac.dim));
        end
        return
    else
        if useDivTerm
            % Manual version
            nD = jac.dim(2);

            if isempty(jac.subset)
                N = jac.map;
            else
                N = jac.map(jac.subset, :);
            end
            J = repmat(reshape(N, [], 1), 2, nD);

%             ix = sortIx.J_sorted_index;

            if nD > 1
                J = bsxfun(@plus, J, (0:nD-1)*jac.dim(1));
            end
            I = repmat(sortIx.I_base, 1, nD);
%             I = [N(:, 1); N(:, 1); N(:, 2); N(:, 2)];
%             I = repmat(repmat(reshape(N, [], 1), 2, 1), 1, nD);
            V = [jac.diagonal; -jac.diagonal];

%             V = V(ix, :);
%             J = J(ix, :);

%             act = V~=0;
% 
%             I = I(act);
%             J = J(act);
%             V = V(act);
            jac = DivergenceTerm(I, J, V, nc, prod(jac.dim));
        else
            % Sparse version
            jac = sortIx.C*jac.sparse();
        end
    end
end