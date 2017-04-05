function metric = crossvalid_rec(rec, mat, scoring, varargin)
% rec: recommendation method
% mat: matrix storing records
% mode of cross validation: 
%   un: user side normal 
%   in: item side normal
%   en: entry wise normal
%   u: user
%   i: item
[folds, fold_mode, rec_opt] = process_options(varargin, 'folds', 5, 'fold_mode', 'un');
[M, N] = size(mat);

mat_fold = kFolds(mat, folds, fold_mode);
metric = struct();
for i=1:folds
    test = mat_fold{i};
    train = sparse(M, N);
    for j=1:folds
        if j~=i
            train = train + mat_fold{i};
        end
    end
    [P, Q] = rec(train, rec_opt{:});
    if strcmp(fold_mode, 'i') % in this mode, only those items within the same fold are required for comparison
        ind = sum(test,2)>0;
        metric_fold = scoring(train, test(:,ind), P,  Q(:,ind));
    else
        metric_fold = scoring(train, test, P,  Q);
    end
    fns = fieldnames(metric_fold);
    for f=1:length(fns)
        fieldname = fns{f};
        if isfield(metric, fieldname)
            metric.(fieldname) = metric.(fieldname) + [metric_fold.(fieldname);(metric_fold.(fieldname)).^2];
        else
            metric.(fieldname) = [metric_fold.(fieldname);(metric_fold.(fieldname)).^2];
        end
    end
end
fns = fieldnames(metric);
for f=1:length(fns)
    fieldname = fns{f};
    field = metric.(fieldname);
    field_mean = field(1,:) / folds;
    field_std = field(2,:)./folds - field_mean .* field_mean;
    metric.(fieldname) = [field_mean; field_std];
end
end

