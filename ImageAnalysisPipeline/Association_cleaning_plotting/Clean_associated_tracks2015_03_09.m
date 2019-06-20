 % Read in imaris result file exported as csv.
% Let users determine the shown tracks are good for further analysis.
% The results are saved as text file.
%
%
%      Sun Hae Hong
%      David Drubin lab
%      University of  California, Berkeley
%
%      Copyright 2013
%
% Log
% 12/18/2014
% 
%  Added in part for SNR cut. Based on Analysis_SNR_good_Tracks.m
%  (See Microscopy note book)

% MA try different SNRs


function Clean_associated_tracks2015_03_09(data)
snrCutoffRef = 0.05;
snrCutoffCor = 0.05;

if (nargin == 0)
    data.mode = 'manual';
else
    data.mode = 'sequence';
end

%% choose associated_track file

if strcmp(data.mode, 'sequence')
    track_file = 'associated_tracks_ref_cor.mat';
    track_folder_name = data.source(1:end - 4);
else load('previous_file.mat')
    %disp('Pick mat file of associated tracks.')
    if (exist('continued_use', 'var') ~= 0)
        track_file = 'associated_tracks_ref_cor.mat';
        track_folder_name = cor_folder_name;
    else
        [track_file, track_folder_name] = uigetfile('*.mat','Pick mat file of associated tracks.',previous_file);
    end
    
    if isdir(track_folder_name)
        previous_file = fullfile(track_folder_name, track_file);
        save('previous_file', 'previous_file')
    else
        display('You did not pick a folder.')
        return
    end
end

%% Load track results
load(fullfile(track_folder_name, track_file));

%% Parameter to use
pixel_size = analysis_info.pixel_size; % in nm
shift_y = analysis_info.shift_y;
shift_x = analysis_info.shift_x;
shift_y_nm = analysis_info.shift_y_nm;
shift_x_nm = analysis_info.shift_x_nm;
ref_channel = analysis_info.ref_channel;
cor_channel = analysis_info.cor_channel;
extra_tp = analysis_info.extra_tp;
spot_size = 350;
%% parameters for cleaning
search_range = 1.5*spot_size;
%% Read in reference and corresponding raw image.
if exist(analysis_info.cor_image_name, 'file') && exist(analysis_info.ref_image_name, 'file')
    cor_stack_3D = openTiffStack(analysis_info.cor_image_name);
    ref_stack_3D = openTiffStack(analysis_info.ref_image_name);
elseif (nargin > 0)
    cor_stack_3D = openTiffStack(data.cor_img);
    ref_stack_3D = openTiffStack(data.ref_img);
else
    %% choose reference images
    load('previous_file.mat')
    [ref_img_file, ref_img_folder_name] = uigetfile('*.tif','Pick reference images plotting.',previous_file);
    if isdir(ref_img_folder_name)
        previous_file = fullfile(ref_img_folder_name, ref_img_file);
        save('previous_file', 'previous_file')
    else
        display('You did not pick a folder.')
        return
    end
    
    %% choose corresponding images
    load('previous_file.mat')
    [cor_img_file, cor_img_folder_name] = uigetfile('*.tif','Pick corresponding images plotting.',previous_file);
    if isdir(cor_img_folder_name)
        previous_file = fullfile(cor_img_folder_name, cor_img_file);
        save('previous_file', 'previous_file')
    else
        display('You did not pick a folder.')
        return
    end
    cor_stack_3D = openTiffStack(fullfile(cor_img_folder_name,cor_img_file));
    ref_stack_3D = openTiffStack(fullfile(ref_img_folder_name,ref_img_file));
end


%% Retrieve variables from the saved results
ref_primary_track = track_stat_ref.ref_primary_track;
xcoord_ref = track_stat_ref.xcoord + shift_x_nm;
ycoord_ref = track_stat_ref.ycoord + shift_y_nm;
xcoord_cor = track_stat_cor.xcoord;
ycoord_cor = track_stat_cor.ycoord;

position_data_ref_original(:,3) = position_data_ref_original(:,3) + shift_x_nm;
position_data_ref_original(:,4) = position_data_ref_original(:,4) + shift_y_nm;

%% Make a file to save manual decision
machine_pick_file_name = 'cleaned_track_list.txt';
fid = fopen(fullfile(track_folder_name, machine_pick_file_name), 'w');
fprintf(fid, '%s\n%s\n%s\n%s\n\n', ['ref csv file:', analysis_info.ref_csv_name],...
    ['cor csv file:', analysis_info.cor_csv_name],...
    ['ref image:', analysis_info.ref_image_name],...
    ['cor image:', analysis_info.cor_image_name]);
fprintf(fid,'%s\n', 'Column 1: Track group. 1 for associated tracks, 2 for unassociated reference tracks, 3 for unassociated corresponding tracks');
fprintf(fid,'%s\n', 'Column 2: Track number.');
fprintf(fid,'%s\n', 'Column 3: Descision. 1 for good tracks to be further analyzed. 0 for bad tracks that are discarded.');
fprintf(fid,'%s\n\t%s\n\t%s\n\t%s\n\t%s\n\t%s\n\t%s\n\n', 'Column 4: Reason for discarding.',...
    '0 for good tracks (not discarded).',...
    '1 for tracks that were incomplete or touching the boundary.',...
    '2 for tracks that were shorter than 3 time points.',...
    '3 for tracks that were interfered by nearby tracks.',...
    '4 for tracks with low signal to noise ratio.',...
    '5 for other.');
fprintf(fid, '%s\t%s\t%s\t%s\n',...
    'Track group', 'Track number', 'Decision','Reason');
fclose(fid);
%% Group description
% Track group 1 is for reference tracks with associated corresponding tracks.
% Track group 2 is for reference tracks with associated corresponding tracks.
% Track group 3 is for corresponding without associated with reference tracks.
track_group = 1;
first_track = 1;
% end
%% clean up corresponding track.
% In the following circumstances, the tracks are discarded.
% i) There is another spot within 350nm during the track lifetime.
% ii) SNR is not good.
% iii) The track started at least 5 time points after the beginning of the movie.
% iv) The track should not touch the edges

asso_track_num = numel(track_stat_ref.ref_tracks_associated);
ref_track_num = numel(track_stat_ref.ref_tracks_unassociated);
cor_track_num = numel(track_stat_cor.cor_tracks_unassociated);

% group numbers
track_flag_list = NaN*ones(asso_track_num + ref_track_num + cor_track_num, 4);
track_flag_list(1:asso_track_num,1) = 1;
track_flag_list((asso_track_num + 1):(asso_track_num + ref_track_num),1) = 2;
track_flag_list((asso_track_num  + ref_track_num +1):(asso_track_num + ref_track_num + cor_track_num),1) = 3;

for i = 1:asso_track_num
    ref_track = track_stat_ref.ref_tracks_associated(i);
    profile_length = ROI_track_ref(ref_track, 1).tp_post_all - ROI_track_ref(ref_track, 1).tp_prev_all + 1;

    
    % profile_length needs to be at least 3 time points.
    if profile_length < 3
        clean_track_flag =  false;
        track_flag_list(i, 2:3) = [ref_track, clean_track_flag];
        track_flag_list(i, 4) = 2;
        continue
    end

    % If part of data is missing for any reason, the track is not
    % considered.
    if any(any(isnan(associated_tracks(ref_track, 1).cor_montage))) ||any(any(isnan(associated_tracks(ref_track, 1).ref_montage)))
        clean_track_flag =  false;
        track_flag_list(i, 2:3) = [ref_track, clean_track_flag];
        track_flag_list(i, 4) = 5;
        continue
    end

    tp_prev = ROI_track_ref(ref_track).tp_prev_all;
    tp_post = ROI_track_ref(ref_track).tp_post_all;
    
    %% See if there are any spots that are too close to the track within the
    % duration of the movie.
    ref_coord_extrapol = ROI_track_ref(ref_track).ref_coord_extrapol;
    ref_coord_extrapol(:,1) = ref_coord_extrapol(:,1) +shift_x_nm;
    ref_coord_extrapol(:,2) = ref_coord_extrapol(:,2) +shift_y_nm;
    cor_coord_extrapol = ROI_track_ref(ref_track).cor_coord_extrapol;
    
    clean_track_flag = true;
    % see if there is an nearby spot in the reference channel.
    tp = tp_prev;
    while tp <= tp_post && clean_track_flag
        current_rows = find(position_data_ref_original(:, 2) == tp);
        % first see if any spot can be close
        if any(and(abs(position_data_ref_original(current_rows, 3) - ref_coord_extrapol(tp-tp_prev+1,1)) < search_range,...
                abs(position_data_ref_original(current_rows, 4) - ref_coord_extrapol(tp-tp_prev+1,2)) < search_range))
            
            close_spot_row_num2 = find(and(abs(position_data_ref_original(current_rows, 3) - ref_coord_extrapol(tp-tp_prev+1,1)) < search_range,...
                abs(position_data_ref_original(current_rows, 4) - ref_coord_extrapol(tp-tp_prev+1,2)) < search_range));
            close_spot_row_num2 = unique(close_spot_row_num2);
            close_spot_row_num = current_rows(close_spot_row_num2);
            % Calculate the eucledian distance of the candidate spots.
            sq_dist_matrix = ((position_data_ref_original(close_spot_row_num, 3) - ref_coord_extrapol(tp-tp_prev+1,1)).^2+...
                (position_data_ref_original(close_spot_row_num, 4) - ref_coord_extrapol(tp-tp_prev+1,2)).^2);
            % It is OK to overlap with itself.
            sq_dist_matrix = setdiff(sq_dist_matrix, [0]);
            if any(sq_dist_matrix < search_range^2)
                clean_track_flag =  false;
                continue
            end
        end
        tp = tp + 1;
    end
    % see if there is an nearby spot in the corresponding channel.
    tp = tp_prev;
    while tp <= tp_post && clean_track_flag
        current_rows = find(position_data_cor_original(:, 2) == tp);
        % first see if any spot can be close
        if any(and(abs(position_data_cor_original(current_rows, 3) - cor_coord_extrapol(tp-tp_prev+1,1)) < search_range,...
                abs(position_data_cor_original(current_rows, 4) - cor_coord_extrapol(tp-tp_prev+1,2)) < search_range))
            
            close_spot_row_num2 = find(and(abs(position_data_cor_original(current_rows, 3) - cor_coord_extrapol(tp-tp_prev+1,1)) < search_range,...
                abs(position_data_cor_original(current_rows, 4) - cor_coord_extrapol(tp-tp_prev+1,2)) < search_range));
            close_spot_row_num2 = unique(close_spot_row_num2);
            close_spot_row_num = current_rows(close_spot_row_num2);
            
            sq_dist_matrix = ((position_data_cor_original(close_spot_row_num, 3) - cor_coord_extrapol(tp-tp_prev+1,1)).^2+...
                (position_data_cor_original(close_spot_row_num, 4) - cor_coord_extrapol(tp-tp_prev+1,2)).^2);
            % It is OK to overlap with itself.
            sq_dist_matrix = setdiff(sq_dist_matrix, [0]);
            if any(sq_dist_matrix < search_range^2)
                clean_track_flag =  false;
                continue
            end
        end
        tp = tp + 1;
    end
    if ~clean_track_flag
        track_flag_list(i, 2:4) = [ref_track, clean_track_flag, 3];
        continue
    end
    
    % Test if SNR is good.
    ref_spot_stack = reshape(associated_tracks(ref_track, 1).ref_montage, [7,7,profile_length]);
    sum_center = reshape(sum(sum(ref_spot_stack(3:5, 3:5, :),1),2), [profile_length, 1,1]);
    bg_mean = mean([sum_center(1:5); sum_center(end-4:end)]);
    bg_std = mean([sum_center(1:5); sum_center(end-4:end)]);
    spot_intensity = (sum_center(6:end-5)-bg_mean)/bg_std;

    if max(spot_intensity) < snrCutoffRef
        clean_track_flag =  false;
        track_flag_list(i, 2:3) = [ref_track, clean_track_flag];
        track_flag_list(i, 4) = 14;
        continue
    end

    cor_spot_stack = reshape(associated_tracks(ref_track, 1).cor_montage, [7,7,profile_length]);
    sum_center = reshape(sum(sum(ref_spot_stack(3:5, 3:5, :),1),2), [profile_length, 1,1]);
    bg_mean = mean([sum_center(1:5); sum_center(end-4:end)]);
    bg_std = mean([sum_center(1:5); sum_center(end-4:end)]);
    spot_intensity = (sum_center(6:end-5)-bg_mean)/bg_std;

    if max(spot_intensity) < snrCutoffCor
        clean_track_flag =  false;
        track_flag_list(i, 2:4) = [ref_track, clean_track_flag, 4];
        continue
    end
    
    track_flag_list(i, 2:4) = [ref_track, clean_track_flag, 0];
    
end

for i = 1:ref_track_num
    ref_track = track_stat_ref.ref_tracks_unassociated(i);
    
    profile_length = ROI_track_ref(ref_track, 1).tp_post_all - ROI_track_ref(ref_track, 1).tp_prev_all + 1;
    
    % profile_length needs to be at least 3 time points.
    if profile_length < 3
        clean_track_flag =  false;
        track_flag_list(asso_track_num + i, 2:4) = [ref_track, clean_track_flag, 2];
        continue
    end

    if any(any(isnan(associated_tracks(ref_track, 1).cor_montage))) ||any(any(isnan(associated_tracks(ref_track, 1).ref_montage)))
        clean_track_flag =  false;
        track_flag_list(asso_track_num + i, 2:4) = [ref_track, clean_track_flag, 5];
        continue
    end

    tp_prev = ROI_track_ref(ref_track).tp_prev_all;
    tp_post = ROI_track_ref(ref_track).tp_post_all;
    
    %% See if there are any spots that are too close to the track within the
    % duration of the movie.
    ref_coord_extrapol = ROI_track_ref(ref_track).ref_coord_extrapol;
    ref_coord_extrapol(:,1) = ref_coord_extrapol(:,1) +shift_x_nm;
    ref_coord_extrapol(:,2) = ref_coord_extrapol(:,2) +shift_y_nm;
    cor_coord_extrapol = ROI_track_ref(ref_track).cor_coord_extrapol;
    
    clean_track_flag = true;
    tp = tp_prev;
    while tp <= tp_post && clean_track_flag
        current_rows = find(position_data_ref_original(:, 2) == tp);
        % first see if any spot can be close
        if any(and(abs(position_data_ref_original(current_rows, 3) - ref_coord_extrapol(tp-tp_prev+1,1)) < search_range,...
                abs(position_data_ref_original(current_rows, 4) - ref_coord_extrapol(tp-tp_prev+1,2)) < search_range))
            
            close_spot_row_num2 = find(and(abs(position_data_ref_original(current_rows, 3) - ref_coord_extrapol(tp-tp_prev+1,1)) < search_range,...
                abs(position_data_ref_original(current_rows, 4) - ref_coord_extrapol(tp-tp_prev+1,2)) < search_range));
            close_spot_row_num2 = unique(close_spot_row_num2);
            close_spot_row_num = current_rows(close_spot_row_num2);
            
            sq_dist_matrix = ((position_data_ref_original(close_spot_row_num, 3) - ref_coord_extrapol(tp-tp_prev+1,1)).^2+...
                (position_data_ref_original(close_spot_row_num, 4) - ref_coord_extrapol(tp-tp_prev+1,2)).^2);
            % It is OK to overlap with itself.
            sq_dist_matrix = setdiff(sq_dist_matrix, [0]);
            if any(sq_dist_matrix < search_range^2)
                clean_track_flag =  false;
                continue
            end
        end
        tp = tp + 1;
    end
    % see if there is an nearby spot in the corresponding channel.
    tp = tp_prev;
    while tp <= tp_post && clean_track_flag
        current_rows = find(position_data_cor_original(:, 2) == tp);
        % first see if any spot can be close
        if any(and(abs(position_data_cor_original(current_rows, 3) - ref_coord_extrapol(tp-tp_prev+1,1)) < search_range,...
                abs(position_data_cor_original(current_rows, 4) - ref_coord_extrapol(tp-tp_prev+1,2)) < search_range))
            
            close_spot_row_num2 = find(and(abs(position_data_cor_original(current_rows, 3) - ref_coord_extrapol(tp-tp_prev+1,1)) < search_range,...
                abs(position_data_cor_original(current_rows, 4) - ref_coord_extrapol(tp-tp_prev+1,2)) < search_range));
            close_spot_row_num2 = unique(close_spot_row_num2);
            close_spot_row_num = current_rows(close_spot_row_num2);
            
            sq_dist_matrix = ((position_data_cor_original(close_spot_row_num, 3) - ref_coord_extrapol(tp-tp_prev+1,1)).^2+...
                (position_data_cor_original(close_spot_row_num, 4) - ref_coord_extrapol(tp-tp_prev+1,2)).^2);
            % It is OK to overlap with itself.
            sq_dist_matrix = setdiff(sq_dist_matrix, [0]);
            if any(sq_dist_matrix < search_range^2)
                clean_track_flag =  false;
                continue
            end
        end
        tp = tp + 1;
    end
    if ~clean_track_flag
        track_flag_list(asso_track_num + i, 2:4) = [ref_track, clean_track_flag, 3];
        continue
    end

    % Test if SNR is good.
    ref_spot_stack = reshape(associated_tracks(ref_track, 1).ref_montage, [7,7,profile_length]);
    sum_center = reshape(sum(sum(ref_spot_stack(3:5, 3:5, :),1),2), [profile_length, 1,1]);
    bg_mean = mean([sum_center(1:5); sum_center(end-4:end)]);
    bg_std = mean([sum_center(1:5); sum_center(end-4:end)]);
    spot_intensity = (sum_center(6:end-5)-bg_mean)/bg_std;

    if max(spot_intensity) < snrCutoffRef
        clean_track_flag =  false;
        track_flag_list(asso_track_num + i, 2:4) = [ref_track, clean_track_flag, 4];
        continue
    end
    track_flag_list(asso_track_num + i, 2:4) = [ref_track, clean_track_flag,0];
end


cor_track_num = numel(track_stat_cor.cor_tracks_unassociated);
for i = 1:cor_track_num
    cor_track = track_stat_cor.cor_tracks_unassociated(i);
    
    tp_prev = ROI_track_cor(cor_track).tp_prev;
    tp_post = ROI_track_cor(cor_track).tp_post;
    profile_length = tp_post - tp_prev + 1;
    
    % profile_length needs to be at least 3 time points.
    if profile_length < 3
        clean_track_flag =  false;
        track_flag_list(asso_track_num+ref_track_num + i, 2:4) = [cor_track, clean_track_flag, 2];
        continue
    end
    
    if any(any(isnan(unassociated_tracks(cor_track, 1).ref_montage))) || any(any(isnan(unassociated_tracks(cor_track, 1).cor_montage)))
        clean_track_flag =  false;
        track_flag_list(asso_track_num+ref_track_num + i, 2:4) = [cor_track, clean_track_flag, 5];
        continue
    end

    
    %% See if there are any spots that are too close to the track within the
    % duration of the movie.
    cor_coord_extrapol = ROI_track_cor(cor_track).cor_coord_extrapol;
    cor_coord_extrapol = ROI_track_cor(cor_track).cor_coord_extrapol;
    
    clean_track_flag = true;
    tp = tp_prev;
    while tp <= tp_post && clean_track_flag
         current_rows = find(position_data_ref_original(:, 2) == tp);
        % first see if any spot can be close
        if any(and(abs(position_data_ref_original(current_rows, 3) - cor_coord_extrapol(tp-tp_prev+1,1)) < search_range,...
                abs(position_data_ref_original(current_rows, 4) - cor_coord_extrapol(tp-tp_prev+1,2)) < search_range))
            
            close_spot_row_num2 = find(and(abs(position_data_ref_original(current_rows, 3) - cor_coord_extrapol(tp-tp_prev+1,1)) < search_range,...
                abs(position_data_ref_original(current_rows, 4) - cor_coord_extrapol(tp-tp_prev+1,2)) < search_range));
            close_spot_row_num2 = unique(close_spot_row_num2);
            close_spot_row_num = current_rows(close_spot_row_num2);
            
            sq_dist_matrix = ((position_data_ref_original(close_spot_row_num, 3) - cor_coord_extrapol(tp-tp_prev+1,1)).^2+...
                (position_data_ref_original(close_spot_row_num, 4) - cor_coord_extrapol(tp-tp_prev+1,2)).^2);
            % It is OK to overlap with itself.
            sq_dist_matrix = setdiff(sq_dist_matrix, [0]);
            if any(sq_dist_matrix < search_range^2)
                clean_track_flag =  false;
                continue
            end
        end
        tp = tp + 1;
    end
    % see if there is an nearby spot in the corresponding channel.
    tp = tp_prev;
    while tp <= tp_post && clean_track_flag
        current_rows = find(position_data_cor_original(:, 2) == tp);
        % first see if any spot can be close
        if any(and(abs(position_data_cor_original(current_rows, 3) - cor_coord_extrapol(tp-tp_prev+1,1)) < search_range,...
                abs(position_data_cor_original(current_rows, 4) - cor_coord_extrapol(tp-tp_prev+1,2)) < search_range))
            
            close_spot_row_num2 = find(and(abs(position_data_cor_original(current_rows, 3) - cor_coord_extrapol(tp-tp_prev+1,1)) < search_range,...
                abs(position_data_cor_original(current_rows, 4) - cor_coord_extrapol(tp-tp_prev+1,2)) < search_range));
            close_spot_row_num2 = unique(close_spot_row_num2);
            close_spot_row_num = current_rows(close_spot_row_num2);
            
            sq_dist_matrix = ((position_data_cor_original(close_spot_row_num, 3) - cor_coord_extrapol(tp-tp_prev+1,1)).^2+...
                (position_data_cor_original(close_spot_row_num, 4) - cor_coord_extrapol(tp-tp_prev+1,2)).^2);
            % It is OK to overlap with itself.
            sq_dist_matrix = setdiff(sq_dist_matrix, [0]);
            if any(sq_dist_matrix < search_range^2)
                clean_track_flag =  false;
                continue
            end
        end
        tp = tp + 1;
    end
    if ~clean_track_flag
        track_flag_list(asso_track_num+ref_track_num + i, 2:4) = [cor_track, clean_track_flag, 3];
        continue
    end

    % Test if SNR is good.
    ref_spot_stack = reshape(unassociated_tracks(cor_track, 1).cor_montage, [7,7,profile_length]);
    sum_center = reshape(sum(sum(ref_spot_stack(3:5, 3:5, :),1),2), [profile_length, 1,1]);
    bg_mean = mean([sum_center(1:5); sum_center(end-4:end)]);
    bg_std = mean([sum_center(1:5); sum_center(end-4:end)]);
    spot_intensity = (sum_center(6:end-5)-bg_mean)/bg_std;

    if max(spot_intensity) < snrCutoffCor
        clean_track_flag =  false;
        track_flag_list(asso_track_num+ref_track_num + i, 2:4) = [cor_track, clean_track_flag, 4];
        continue
    end

    track_flag_list(asso_track_num+ref_track_num + i, 2:4) = [cor_track, clean_track_flag, 0];
    
end

dlmwrite(fullfile(track_folder_name, machine_pick_file_name), track_flag_list, 'delimiter', '\t', '-append')
save(fullfile(track_folder_name, 'cleaned_track_list.mat'), 'track_flag_list');
disp('Done.')
%%
% [y, Fs] = audioread('notify.wav');
% sound(y, Fs);