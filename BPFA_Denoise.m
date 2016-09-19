function [IMin,NoiseVar,PSNR] = BPFA_Denoise(IMin,IMin0, Hyper)
%------------------------------------------------------------------
% Input:
%   IMin: noisy image.
%   PatchSize: patch size, 8 is commonly used.
%   K: predefined dic  tionary size.
%   DispPSNR: calculate and display the instant PSNR during learning if it is TRUE
%   IsSeparateAlpha: use a separate precision for each factor score vector if it is TRUE.
%   InitOption: 'SVD' or 'Rand';
%   LearningMode: 'online' or 'batch';
%   IterPerRound: maximum iteration in each round.
%   ReduceDictSize: reduce the dictionary size during learning if it is TRUE
%   IMin0: original noise-free image (only used for PSNR calculation and
%   would not affect the denoising results).
%   sigma: noise variance (has no effect on the denoising results).
%   IMname: image name (has no effect on the deoising results).
% Output:
%   ave: denoised image (averaged output)
%   Iout: denoised image (sample output)
%   D: dictionary learned from the noisy image
%   S: basis coefficients
%   Z: binary indicators for basis usage
%   idex: patch index
%   Pi: the probabilities for each dictionary entries to be used
%   NoiseVar: estimated noise variance
%   alpha: precision for S
%   phi: noise precision
%   PSNR: peak signal-to-noise ratio
%   PSNRave: PSNR of ave.Iout
%   Can't deal with spiky noise
%------------------------------------------------------------------
if nargin < 2
    IMin0=IMin;
end
if nargin < 3
    Hyper.PatchSize = 8;
    Hyper.nlsp = 6;
    Hyper.step = 3;
end
if nargin < 4
    %Initialization with 'SVD' or 'Rand'
    InitOption = 'Rand';
end
if nargin < 5
    %Reduce the ditionary size during training if it is TRUE,
    %can be used to reduce computational complexity
    ReduceDictSize = false;
    % use a separate precision for each factor score vector if it is TRUE.
    IsSeparateAlpha = true;
end

[h,w,ch] = size(IMin);
PSNR = csnr( IMin*255, IMin0*255, 0, 0 );
SSIM = cal_ssim( IMin*255, IMin0*255, 0, 0 );
fprintf('Initial value : PSNR = %2.4f, SSIM = %2.4f\n', PSNR(end),SSIM(end));

%% Set Hyperparameters
c0=Hyper.c0;
d0=Hyper.d0;
e0=Hyper.e0;
f0=Hyper.f0;

loop = 1;
PatchSize = Hyper.PatchSize;
nlsp = Hyper.nlsp;
step = Hyper.step;
cls_num = 24*ch;
Iteration = 0;

% end for spiky noise
while loop
    Iteration = Iteration + 1;
    %% Clustering via GMM
    [nDCSeedX,nDCnlX,blk_arr,DC] = CalNonLocal( IMin,PatchSize, step,nlsp);
        if Iteration ==1
    label = vbgm(nDCSeedX, cls_num);
    cls_num = max(label);
    fprintf('Iter %d : There are %d components.\n',Iteration, cls_num);
    label = emgm(nDCnlX, cls_num,nlsp);
        else
            label = emgm(nDCnlX, cls_num,nlsp);
        end
    % cluster segmentation
    [idx,  s_idx]    =  sort(label);
    idx2   =  idx(1:end-1) - idx(2:end);
    seq    =  find(idx2);
    seg    =  [0; seq; length(label)];
    NoiseVar = [];
    %% component-wise sampling and dictionary learning
    nlX = zeros(PatchSize^2*ch,(h-PatchSize+1)*(w-PatchSize+1),'double');
    nlW = zeros(PatchSize^2*ch,(h-PatchSize+1)*(w-PatchSize+1),'double');
    for   i = 1:length(seg)-1
        idx          =   s_idx(seg(i)+1:seg(i+1));
        %% from idx of DC to index of PGs
        index = [];
        for j = 1:nlsp
            index = [index (idx-1)*nlsp+j];
        end
        index = index';
        index = reshape(index,[1 length(index(:))]);
        Xc = nDCnlX(:,index);
        if length(idx)<= ceil(300^2/cls_num)
            K = 256;  %dictionary size
        else
            K = 512;
        end
        cls = label(idx(1));
        %%
        IterPerRound = ones(1,nlsp);
        IterPerRound(end) = 50;
        %%
        X_k=[];
        idex=[];
        for ite = 1:nlsp
            idexold = idex;
            idexNew = ite:nlsp:length(index);
            idex = [idexold idexNew];
            XNew = Xc(:,idexNew);
            X_k = [X_k,XNew];
            [P,N] = size(X_k);
            %Sparsity Priors
            if strcmp(InitOption,'SVD')==1
                a0=1;
                b0=N/8;
            else
                a0=1;
                b0=1;
            end
            if ite == 1
                % Random initialization
                phi = 1/((Hyper.RannSig/255)^2);
                [D,S,Z,phi,alpha,Pi] = InitMatrix_Denoise(X_k,K,InitOption,IsSeparateAlpha,phi);
            else
                % Initialize new added patches with their neighbours
                [S,Z] = SZUpdate(XNew,S,Z,K);
            end
            idext = N-length(idexNew)+1 : N;
            X_k(:,idext) = X_k(:,idext) - D*(S(idext,:).*Z(idext,:))';
            for iter=1:IterPerRound(ite)
                % Sample D, Z, and S
                if size(IMin,3)==1
                    Pi(1) = 1;
                end
                [X_k, D, Z, S] = SampleDZS(X_k, D, Z, S, Pi, alpha, phi, true, true, true);
                % Sample Pi
                Pi = SamplePi(Z,a0,b0);
                % Sample alpha
                alpha = Samplealpha(S,e0,f0,Z,alpha);
                % Sample phi
                phi = Samplephi(X_k,c0,d0);
                % estimate noise level
                NoiseVar(end+1) = sqrt(1/phi)*255;
                if ReduceDictSize
                    sumZ = sum(Z,1)';
                    if min(sumZ)==0
                        Pidex = sumZ==0;
                        D(:,Pidex)=[];
                        K = size(D,2);
                        S(:,Pidex)=[];
                        Z(:,Pidex)=[];
                        Pi(:,Pidex)=[];
                        alpha(Pidex)=[];
                    end
                end
            end
        end
        fprintf('Iter %d : The Noise Level of the %dth component is %2.4f\n',Iteration, cls, NoiseVar(end));
        Xc(:,idex) = D*S';
        %% add DC components and aggregation
        nlX(:,blk_arr(index)) = nlX(:,blk_arr(index)) + Xc + DC(:,index);
        nlW(:,blk_arr(index)) = nlW(:,blk_arr(index))+ones(PatchSize^2*ch,length(index));
    end
    %% Reconstruction
    Iout   =  zeros(h,w,ch,'double');
    im_wei   =  zeros(h,w,ch,'double');
    r = 1:h-PatchSize+1;
    c = 1:w-PatchSize+1;
    l = 0;
    for k = 1:ch
        for i = 1:PatchSize
            for j =1:PatchSize
                l    =  l+1;
                Iout(r-1+i,c-1+j,k)  =  Iout(r-1+i,c-1+j,k) + reshape( nlX(l,:)', [h-PatchSize+1 w-PatchSize+1]);
                im_wei(r-1+i,c-1+j,k)  =  im_wei(r-1+i,c-1+j,k) +reshape( nlW(l,:)', [h-PatchSize+1 w-PatchSize+1]);
            end
        end
    end
    IMin = Iout./(im_wei+realmin);
    %% calculate the PSNR
    PSNR = [PSNR csnr( IMin*255, IMin0*255, 0, 0 )];
    SSIM = [SSIM  cal_ssim( IMin*255, IMin0*255, 0, 0 )];
    fprintf('Iter %d : PSNR = %2.4f, SSIM = %2.4f\n',Iteration, PSNR(end),SSIM(end));
    if PSNR(end) - PSNR(end-1) < 0.02
        disp(['iter:', num2str(Iteration),'    ave_Z: ', num2str(full(mean(sum(Z,2)))),'    M:', num2str(nnz(mean(Z,1)>1/1000)),'    PSNR:',num2str(PSNR(end)),'   NoiseVar are from ',num2str(min(NoiseVar)), ' to ',num2str(max(NoiseVar)) ]);
        loop = 0;
    end
end
end