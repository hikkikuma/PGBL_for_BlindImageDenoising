clear;
warning off;
Original_image_dir  =    './RealNoisyImage/';
fpath = fullfile(Original_image_dir, '*.jpeg');
im_dir  = dir(fpath);
im_num = length(im_dir);
% set parameters
c0 = 1e-6;
d0 = 1e-6;
e0 = 1e-6;
f0  = 1e-6;
Hyper.c0=c0;
Hyper.d0=d0;
Hyper.e0=e0;
Hyper.f0=f0;
Hyper.PatchSize = 16;
Hyper.step = 4;
nlsp = 6;
Hyper.nlsp = nlsp;
Hyper.MaxIteration = 20;

for i = 1:im_num
    IMin=im2double(imread(fullfile(Original_image_dir, im_dir(i).name)));
    S = regexp(im_dir(i).name, '\.', 'split');
    IMname = S{1};
    % color or gray image
    [h,w,ch] = size(IMin);
    if h >= 600
        IMin = IMin(ceil(h/2)-300+1:ceil(h/2)+300,:,:);
    end
    if w >= 800
        IMin = IMin(:,ceil(w/2)-400+1:ceil(w/2)+400,:);
    end
    [h,w,ch] = size(IMin);
    if ch==1
        IMin_ycbcr = IMin;
        %% denoising
        Hyper.RannSig = NoiseLevel(IMin_ycbcr*255);
        fprintf('The noise level is %2.2f.\n',Hyper.RannSig);
        [Iout_ycbcr,NoiseVar,~] = BPFA_Denoise_Mixed_Real(IMin_ycbcr,IMin_ycbcr,Hyper);
        Iout_ycbcr(Iout_ycbcr>1)=1;
        Iout_ycbcr(Iout_ycbcr<0)=0;
        Iout = Iout_ycbcr;
    else
        % change color space, work on illuminance only
        IMin_ycbcr = rgb2ycbcr(IMin);
        for channel = 1:ch
            %% denoising
            Hyper.RannSig = NoiseLevel(IMin_ycbcr(:,:,channel)*255);
            fprintf('The noise level is %2.2f.\n',Hyper.RannSig);
            [Iout_y,NoiseVar,~] = BPFA_Denoise_Mixed_Real(IMin_ycbcr(:,:,channel),IMin_ycbcr(:,:,channel),Hyper);
            Iout_y(Iout_y>1)=1;
            Iout_y(Iout_y<0)=0;
            Iout_ycbcr(:,:,channel) = Iout_y;
        end
        Iout = ycbcr2rgb(Iout_ycbcr);
    end
    %% output
    imwrite(Iout, ['./Real/VBGMBPFA_32_Real2_' IMname '.png']);
end