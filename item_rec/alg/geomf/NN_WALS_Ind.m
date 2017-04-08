function [ U, V, X ] = NN_WALS_Ind(  R, Y, K, varargin )
%Non-negative Weighted Alternative Least Square for POI recommendation with
%activity information, in particular, 
% L = 1/2 * || W .* (R - PQ' - XY') ||_F^2 + reg_u / 2 * ||P||_F^2 + ...
% reg_i /2 * ||Q||_F^2 + reg_1 ||X||_1 , subject to X >= 0
%   R: user-item rating matrix
%   U, V: user and item latent vectors
%   Y: activity vectors for items(POIs)
%   X: activity vectors for users
%   K: dimension of latent vectors
%   num_iter: the maximal iteration
%   tol: tolerance for a relative stopping condition
%   reg_u, reg_i: regularization for users latent vectors and items latent
%   vectors; reg_1: regularization for users' activity vectors
%   init_std: latent factors are initialized as samples of zero-mean and 
%       init_std standard-deviation Gaussian distribution

[num_iter, alpha,  tol, reg_u, reg_i, reg_1, init_std] = ...
   process_options(varargin, 'max_iter', 10, 'alpha', 2, 'tol', 1e-3, 'reg_u', 0.01, ...
                   'reg_i', 0.01, 'reg_1', 0.01, 'inid_std', 0.01);

[M, N] = size(R);
%U = randn(M, K) * init_std;
%V = randn(N, K) * init_std;
load uv.mat
X = sparse(M, size(Y, 2));
W = R * alpha;
% alternatively, we can set it as 
% W = log(1+ R/epsilon); where epsilon = 1e-8;
gradUV = 0;
for iter = 1: 1
    %[U, V, gradUV ] = Optimize_Latent(W, U, V, X, Y, reg_u, reg_i, num_iter);
    [X, gradX] = Optimize_Activity(W', X, Y, U, V, reg_1);
    grad = sqrt(gradX + gradUV);
    fprintf('Iteration=%d, gradient norm %f\n', iter, grad);
    if iter == 1
        initgrad = grad;
    elseif grad < tol * initgrad
        break;
    end
end

end
function [U, V, gradUV] = Optimize_Latent(W, U, V, X, Y, reg_u, reg_i, num_iter)
Wt = W.';
for iter = 1:num_iter
    VtV = V.' * V + reg_u * eye(size(U,2));
    VtY = V.' * Y;
    [U, gradU ] = Optimize(Wt, U, V, VtV, VtY, X, Y);
    UtU = U.' * U + reg_i * eye(size(U,2));
    UtX = U.' * X;
    [V, gradV ] = Optimize(W, V, U, UtU, UtX, Y, X);
    grad = sqrt(gradU + gradV); %norm([gradU; gradV], 'fro');
    fprintf('Sub iteration for latent vector, Iteration=%d, gradient norm %f\n', iter, gradnorm);
    if iter == 1
        initgrad = grad;
    elseif grad < tol * initgrad
            break;
    end
end
gradUV = grad ^2;
end

function [U, gradU] = Optimize(W, Uinit, V, VtV, VtY, X, Y)
[~, M] = size(W);
U = zeros(size(Uinit));
gradU = 0;
Vt = V.';
for i = 1 : M
    fprintf('%d\n',i);
    w = W(:,i);
    if nnz(w) == 0
        continue;
    end
    Ind = w>0; Wi = diag(w(Ind));    %Wi = repmat(w(Ind), 1, size(V, 2));
    sub_V = V(Ind,:);
    sub_Y = Y(Ind,:);
    VCV = sub_V.' * Wi * sub_V + VtV; %Vt_minus_V = sub_V.' * (Wi .* sub_V) + invariant;
    VCY = sub_V.' * Wi * sub_Y + VtY;
    Estimate = Vt * w - VCY * (X(i,:))';
    u = VCV \ Estimate;
    grad = (Uinit(i,:) - u') * VCV ;
    U(i,:) = u;
    gradU = gradU + sum(grad .^2);
end

end


function [X, gradX] = Optimize_Activity(W, Xinit, Y, U, V, reg)
YtY = Y.' * Y;
YtV = Y.' * V;
[~, M] = size(W);
gradX = 0;
Yt = Y.';
user_cell = cell(M,1);
item_cell = cell(M,1);
val_cell = cell(M,1);
Ut = U.';
parfor u = 1:M
    fprintf('%d\n', u);
    x = (Xinit(u, :))';
    w = W(:,u);
    Ind = w>0; wu = w(Ind); Wu = spdiags(wu, 0, length(wu), length(wu));
    sub_Y = Y(Ind, :);
    sub_Yt = Yt(:, Ind);
    sub_V = V(Ind, :);
    YC = sub_Yt * Wu;
    YCY = YC * sub_Y + YtY;
    YCV = YC * sub_V + YtV;
    grad_invariant =  YCV * Ut(:,u) - sub_Yt * wu + reg;
    x = LineSearch(YCY, grad_invariant, x);
    [loc, I, val ] = find(x);
    user_cell{u} = u * I;
    item_cell{u} = loc;
    val_cell{u} = val;
    %X = X + sparse(u*I, loc, val, M, len(x));
    %gradX = gradX + projnorm ^2;
end
X = sparse(cell2mat(user_cell), cell2mat(item_cell), cell2mat(val_cell), M, size(Xinit, 2));
end
function x = LineSearch(YCY, grad_invariant, x)
alpha = 1; beta = 0.1;
%prevnorm = inf;
for iter = 1:5
    grad = grad_invariant + YCY * x;
    %projnorm = norm(grad(grad<0 | x > 0), 'fro');
    %if projnorm < prevnorm && (prevnorm - projnorm) < tol * prevnorm
    %    break;
    %end
    %prevnorm = projnorm;
    for step =1:20 % search step size
        xn = sparse(max(x - alpha * grad, 0)); d = xn - x;
        gradd = dot(grad, d); dQd = d.' * YCY * d;
        suff_decr = 0.99 * gradd + 0.5 * dQd < 0;
        if step == 1
            decr_alpha = ~suff_decr; xp = x;
        end
        if decr_alpha
            if suff_decr
                x = xn; break;
            else
                alpha = alpha * beta;
            end
        else
            if ~suff_decr | xp == xn
                x = xp; break;
            else
                alpha = alpha / beta; xp = xn;
            end
        end
    end
end
end
