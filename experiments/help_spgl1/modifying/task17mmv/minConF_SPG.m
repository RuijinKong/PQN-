function [x,f,funEvals,projects] = minConf_SPG(funObj,x,funProj,options)
% function [x,f] = minConF_SPG(funObj,x,funProj,options)
%
% Function for using Spectral Projected Gradient to solve problems of the form
%   min funObj(x) s.t. x in C
%
%   @funObj(x): function to minimize (returns gradient as second argument)
%   @funProj(x): function that returns projection of x onto C
%
%   options:
%       verbose: level of verbosity (0: no output, 1: final, 2: iter (default), 3:
%       debug)
%       optTol: tolerance used to check for progress (default: 1e-6)
%       maxIter: maximum number of calls to funObj (default: 500)
%       numDiff: compute derivatives numerically (0: use user-supplied
%       derivatives (default), 1: use finite differences, 2: use complex
%       differentials)
%       suffDec: sufficient decrease parameter in Armijo condition (default
%       : 1e-4)
%       interp: type of interpolation (0: step-size halving, 1: quadratic,
%       2: cubic)
%       memory: number of steps to look back in non-monotone Armijo
%       condition
%       useSpectral: use spectral scaling of gradient direction (default:
%       1)
%       curvilinear: backtrack along projection Arc (default: 0)
%       testOpt: test optimality condition (default: 1)
%       feasibleInit: if 1, then the initial point is assumed to be
%       feasible
%       bbType: type of Barzilai Borwein step (default: 1)
%
%   Notes: 
%       - if the projection is expensive to compute, you can reduce the
%           number of projections by setting testOpt to 0


nVars = length(x);
lineSearchIters = 0;

% Set Parameters
if nargin < 4
    options = [];
end
[verbose,numDiff,optTol,maxIter,suffDec,interp,memory,useSpectral,curvilinear,feasibleInit,testOpt,bbType] = ...
    myProcessOptions(...
    options,'verbose',2,'numDiff',0,'optTol',1e-6,'maxIter',5000,'suffDec',1e-4,...
    'interp',2,'memory',10,'useSpectral',1,'curvilinear',1,'feasibleInit',0,...
    'testOpt',1,'bbType',1);

% Output Log
if verbose >= 2
    if testOpt
        fprintf('%10s %10s %10s %15s %15s %15s\n','Iteration','FunEvals','Projections','Step Length','Function Val','Opt Cond');
    else
        fprintf('%10s %10s %10s %15s %15s\n','Iteration','FunEvals','Projections','Step Length','Function Val');
    end
end

% Make objective function (if using numerical derivatives)
funEvalMultiplier = 1;
if numDiff
    if numDiff == 2
        useComplex = 1;
    else
        useComplex = 0;
    end
    funObj = @(x)autoGrad(x,useComplex,funObj);
    funEvalMultiplier = nVars+1-useComplex;
end

% Evaluate Initial Point
if ~feasibleInit
    x = funProj(x);
end
[f,g] = funObj(x);
projects = 1;
funEvals = 1;
finit = f;

% Optionally check optimality
if testOpt
    projects = projects+1;
    if sum(abs(funProj(x-g)-x)) < optTol
        if verbose >= 1
        fprintf('First-Order Optimality Conditions Below optTol at Initial Point\n');
        end
        return;
    end
end

i = 1;
while funEvals <= maxIter

    % Compute Step Direction
    if i == 1 || ~useSpectral
        alpha = 1;
    else
        y = g-g_old;
        s = x-x_old;
        if bbType == 1
            alpha = (s'*s)/(s'*y);
        else
            alpha = (s'*y)/(y'*y);
        end
        if alpha <= 1e-10 || alpha > 1e10
            alpha = 1;
        end
    end
    d = -alpha*g;
    f_old = f;
    x_old = x;
    g_old = g;
    
    % Compute Projected Step
    if ~curvilinear
        d = funProj(x+d)-x;
        projects = projects+1;
    end

    % Check that Progress can be made along the direction
    gtd = g'*d;
    if gtd > -optTol
        if verbose >= 1
            fprintf('Directional Derivative below optTol\n');
        end
        break;
    end

    % Select Initial Guess to step length
    if i == 1
        t = min(1,1/sum(abs(g)));
    else
        t = 1;
    end

    % Compute reference function for non-monotone condition

    if memory == 1
        funRef = f;
    else
        if i == 1
            old_fvals = repmat(-inf,[memory 1]);
        end

        if i <= memory
            old_fvals(i) = f;
        else
            old_fvals = [old_fvals(2:end);f];
        end
        funRef = max(old_fvals);
    end



     
    % spglinecurvy
    
    [f_new,x_new,g_new,~,nLine,t,lnErr,nfunEvals] = ...
        spgLineCurvy(x,-d,f,funObj,funProj);
    lineSearchIters = lineSearchIters + nLine;
    funEvals = funEvals + nfunEvals;
    
    %lnErr = 0;
    
    while lnErr && funEvals <= maxIter
%         Backtracking Line Search
%         Evaluate the Objective and Gradient at the Initial Step

         lnErr = 0;
        
         x_new = funProj(x + t*d);
         projects = projects+1;
        
       
        [f_new,g_new] = funObj(x_new);
        funEvals = funEvals+1;

        lineSearchIters = 1;
        while f_new > funRef + suffDec*g'*(x_new-x) || ~isLegal(f_new)
            temp = t;
            if interp == 0 || ~isLegal(f_new)
                if verbose == 3
                    fprintf('Halving Step Size\n');
                end
                t = t/2;
            elseif interp == 2 && isLegal(g_new)
                if verbose == 3
                    fprintf('Cubic Backtracking\n');
                end
                t = polyinterp([0 f gtd; t f_new g_new'*d]);
            elseif lineSearchIters < 2 || ~isLegal(f_prev)
                if verbose == 3
                    fprintf('Quadratic Backtracking\n');
                end
                t = polyinterp([0 f gtd; t f_new sqrt(-1)]);
            else
                if verbose == 3
                    fprintf('Cubic Backtracking on Function Values\n');
                end
                t = polyinterp([0 f gtd; t f_new sqrt(-1);t_prev f_prev sqrt(-1)]);
            end

            % Adjust if change is too small
            if t < temp*1e-3
                if verbose == 3
                    fprintf('Interpolated value too small, Adjusting\n');
                end
                t = temp*1e-3;
            elseif t > temp*0.6
                if verbose == 3
                    fprintf('Interpolated value too large, Adjusting\n');
                end
                t = temp*0.6;
            end

            % Check whether step has become too small
            if sum(abs(t*d)) < optTol || t == 0
                t = 0;
                f_new = f;
                g_new = g;
                %if verbose == 3
                fprintf('Line Search failed\n');
                %end
                lnErr = 1;
                break;
            end

            % Evaluate New Point
            f_prev = f_new;
            t_prev = temp;
            if curvilinear
                x_new = funProj(x + t*d);
                projects = projects+1;
            else
                x_new = x + t*d;
            end
            [f_new,g_new] = funObj(x_new);
            funEvals = funEvals+1;
            lineSearchIters = lineSearchIters+1;

        end
        if lnErr ==1 
            break
        end
    end


    while lnErr && funEvals <= maxIter % failed again
        lnErr = 0;
        curvilinear = 0;
        x_new = x + t*d;
        
        [f_new,g_new] = funObj(x_new);
        funEvals = funEvals+1;

        lineSearchIters = 1;
        while f_new > funRef + suffDec*g'*(x_new-x) || ~isLegal(f_new)
            temp = t;
            if interp == 0 || ~isLegal(f_new)
                if verbose == 3
                    fprintf('Halving Step Size\n');
                end
                t = t/2;
            elseif interp == 2 && isLegal(g_new)
                if verbose == 3
                    fprintf('Cubic Backtracking\n');
                end
                t = polyinterp([0 f gtd; t f_new g_new'*d]);
            elseif lineSearchIters < 2 || ~isLegal(f_prev)
                if verbose == 3
                    fprintf('Quadratic Backtracking\n');
                end
                t = polyinterp([0 f gtd; t f_new sqrt(-1)]);
            else
                if verbose == 3
                    fprintf('Cubic Backtracking on Function Values\n');
                end
                t = polyinterp([0 f gtd; t f_new sqrt(-1);t_prev f_prev sqrt(-1)]);
            end

            % Adjust if change is too small
            if t < temp*1e-3
                if verbose == 3
                    fprintf('Interpolated value too small, Adjusting\n');
                end
                t = temp*1e-3;
            elseif t > temp*0.6
                if verbose == 3
                    fprintf('Interpolated value too large, Adjusting\n');
                end
                t = temp*0.6;
            end

            % Check whether step has become too small
            if sum(abs(t*d)) < optTol || t == 0
                t = 0;
                f_new = f;
                g_new = g;
                %if verbose == 3
                fprintf('Line Search failed\n');
                %end
                lnErr = 1;
                break;
                %keyboard;
            end

            % Evaluate New Point
            f_prev = f_new;
            t_prev = temp;
            if curvilinear
                x_new = funProj(x + t*d);
                projects = projects+1;
            else
                x_new = x + t*d;
            end
            [f_new,g_new] = funObj(x_new);
            funEvals = funEvals+1;
            lineSearchIters = lineSearchIters+1;

        end
        if lnErr ==1 
            break
        end
    end
    
    
    
    % Take Step
    x = x_new;
    f = f_new;
    g = g_new;

    
    
    if lnErr == 1 && finit == f
        error('line search failed\n')
        %break
    end
    
    if lnErr == 1
        break
    end
    
    if testOpt
        optCond = sum(abs(funProj(x-g)-x));
        projects = projects+1;
    end

    % Output Log
    if verbose >= 2
        if testOpt
            fprintf('%10d %10d %10d %15.5e %15.5e %15.5e\n',i,funEvals*funEvalMultiplier,projects,t,f,optCond);
        else
            fprintf('%10d %10d %10d %15.5e %15.5e\n',i,funEvals*funEvalMultiplier,projects,t,f);
        end
    end

    % Check optimality
    if testOpt
        if optCond < optTol
            if verbose >= 1
            fprintf('First-Order Optimality Conditions Below optTol\n');
            end
            break;
        end
    end

    if sum(abs(t*d)) < optTol
        if verbose >= 1
            fprintf('Step size below optTol\n');
        end
        break;
    end

    if abs(f-f_old) < abs(1e-3*f)
        %abs(f-f_old) 
        if verbose >= 1
            fprintf('Function value changing by less than optTol\n');
        end
        break;
    end

    if funEvals*funEvalMultiplier > maxIter
        if verbose >= 1
            fprintf('Function Evaluations exceeds maxIter\n');
        end
        break;
    end

    i = i + 1;
end
end

function [fNew,xNew,gNew,nothing,iter,step,err,funEvals] = ...
    spgLineCurvy(x,g,fMax,funObj,funProj,params)
% Projected backtracking linesearch.
% On entry,
% g  is the (possibly scaled) steepest descent direction.
funEvals = 0;
nothing = 0;
EXIT_CONVERGED  = 0;
EXIT_ITERATIONS = 1;
EXIT_NODESCENT  = 2;
gamma  = 1e-4;
maxIts = 10;
step   =  1;
sNorm  =  0;
scale  =  1;      % Safeguard scaling.  (See below.)
nSafe  =  0;      % No. of safeguarding steps.
iter   =  0;
debug  =  false;  % Set to true to enable log.
n      =  length(x);

if debug
   fprintf(' %5s  %13s  %13s  %13s  %8s\n',...
           'LSits','fNew','step','gts','scale');  
end
   
while 1

    % Evaluate trial point and function value.
    xNew     = funProj(x - step*scale*g);
    [fNew,gNew] = funObj(xNew);
    funEvals = funEvals + 1;
    s        = xNew - x;
    gts      = scale * real(g' * s);
%   gts      = scale * (g' * s);
    if gts >= 0
       err = EXIT_NODESCENT;
       break
    end

    if debug
       fprintf(' LS %2i  %13.7e  %13.7e  %13.6e  %8.1e\n',...
               iter,fNew,step,gts,scale);
    end
    
    % 03 Aug 07: If gts is complex, then should be looking at -abs(gts).
    % 13 Jul 11: It's enough to use real part of g's (see above).
    if fNew < fMax + gamma*step*gts
%   if fNew < fMax - gamma*step*abs(gts)  % Sufficient descent condition.
       err = EXIT_CONVERGED;
       break
    elseif iter >= maxIts                 % Too many linesearch iterations.
       err = EXIT_ITERATIONS;
       break
    end
    
    % New linesearch iteration.
    iter = iter + 1;
    step = step / 2;

    % Safeguard: If stepMax is huge, then even damped search
    % directions can give exactly the same point after projection.  If
    % we observe this in adjacent iterations, we drastically damp the
    % next search direction.
    % 31 May 07: Damp consecutive safeguarding steps.
    sNormOld  = sNorm;
   sNorm     = norm(s) / sqrt(n);
    %   if sNorm >= sNormOld
    if abs(sNorm - sNormOld) <= 1e-6 * sNorm
       gNorm = norm(g) / sqrt(n);
       scale = sNorm / gNorm / (2^nSafe);
       nSafe = nSafe + 1;
    end
    
end % while 1

end % function spgLineCurvy

