function vesicle_detect_wrapper(service_location,img_token, anno_token, query_file, use_semaphore,...
        template, anno_id, padX,padY,...
        neighborhood_size, neighbor_dist, threshold, data_set, ...
        error_page_location)
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% © [2014] The Johns Hopkins University / Applied Physics Laboratory All Rights Reserved. Contact the JHU/APL Office of Technology Transfer for any additional rights.  www.jhuapl.edu/ott
% 
% Licensed under the Apache License, Version 2.0 (the "License");
% you may not use this file except in compliance with the License.
% You may obtain a copy of the License at
% 
%    http://www.apache.org/licenses/LICENSE-2.0
% 
% Unless required by applicable law or agreed to in writing, software
% distributed under the License is distributed on an "AS IS" BASIS,
% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
% See the License for the specific language governing permissions and
% limitations under the License.
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

    
    %% Check inputs       
    if ~exist('template','var')
        error('vesicle_detect:param_error','You must provide a template generated by "get_template.m"');
    end
    
    if ~exist('padX','var')
        padX = 0;
    end
    if ~exist('padY','var')
        padY = 0;
    end

    
    if ~exist('neighborhood_size','var')
        neighborhood_size = 3;
    end
    if ~exist('neighbor_dist','var')
        neighbor_dist = 120;
    end
    if ~exist('threshold','var')
        threshold = 1.25;    
    end    
    
    validateattributes(img_token,{'char'},{'row'});
    validateattributes(anno_token,{'char'},{'row'});
    validateattributes(query_file,{'char'},{'row'});  
    validateattributes(template,{'char'},{'row'});  
    validateattributes(use_semaphore,{'numeric'},{'scalar','>=',0,'<=',1});   
    validateattributes(anno_id,{'numeric'},{'scalar','>',0});  
    
    %% Setup OCP  
    if use_semaphore == 1
        oo = OCP('semaphore');
    else
        oo = OCP();
    end
    oo.setServerLocation(service_location);
    
    oo.setImageToken(img_token);
    %%%%%%%%oo.setAnnoToken(anno_token);
    
     
    if ~exist('error_page_location','var')
        % set to server default
        oo.setErrorPageLocation('/mnt/pipeline/errorPages');
    else
        oo.setErrorPageLocation(error_page_location);
    end

    
    %% Load Query
    load(query_file);
       
    %% Get Data   
    cube = oo.query(query);  
    
    if sum(cube.data(:)) == 0
        fprintf('Empty Block! Exiting wrapper.');
        return
    end
     
 
    %% Run Detector   
    data = vesicle_detect_quick2(cube.data,template, neighborhood_size, neighbor_dist, threshold, data_set);

    
    if isempty(data)
        % no detections
        fprintf('No detections. Skipping upload.\n');
        return
    end
    
    
    %% Upload Block of data    
 
    fprintf('Uploading vesicle block\n');
    t_total = tic;    
    
    span = 12; % # of slices per upload
    
    img_size = oo.imageInfo.DATASET.IMAGE_SIZE(query.resolution);
    
    % Compute padding offsets
    if padX ~= 0 || padY ~=0
        
        if (query.xRange(1) == 0) && (query.yRange(1) == 0)
            % No x or y start padding
            xstart = 1;
            ystart = 1;
            xend = size(data,2) - padX;
            yend = size(data,1) - padY;   
            xyzOffset = '[query.xRange(1), query.yRange(1), query.zRange(1) + ii - 1]';
           
        elseif query.xRange(1) == 0
            % No x start padding
            xstart = 1;
            ystart = padY + 1;
            xend = size(data,2) - padX;
            yend = size(data,1) - padY;   
            xyzOffset = '[query.xRange(1), query.yRange(1) + padY, query.zRange(1) + ii - 1]';
            
        elseif query.yRange(1) == 0
            % No y start padding
            xstart = padX + 1;
            ystart = 1;
            xend = size(data,2) - padX;
            yend = size(data,1) - padY;   
            xyzOffset = '[query.xRange(1) + padX, query.yRange(1), query.zRange(1) + ii - 1]';
            
        elseif (query.xRange(2) == img_size(1)) && (query.yRange(2) == img_size(2))
            % No x or y end padding
            xstart = padX + 1;
            ystart = padY + 1;
            xend = size(data,2);
            yend = size(data,1);   
            xyzOffset = '[query.xRange(1) + padX, query.yRange(1) + padY, query.zRange(1) + ii - 1]';
            
        elseif query.xRange(2) == img_size(1)
            % No x end padding
            xstart = padX + 1;
            ystart = padY + 1;
            xend = size(data,2);
            yend = size(data,1) - padY;   
            xyzOffset = '[query.xRange(1) + padX, query.yRange(1) + padY, query.zRange(1) + ii - 1]';
            
        elseif query.yRange(2) == img_size(2)
            % No y end padding
            xstart = padX + 1;
            ystart = padY + 1;
            xend = size(data,2) - padX;
            yend = size(data,1);   
            xyzOffset = '[query.xRange(1) + padX, query.yRange(1) + padY, query.zRange(1) + ii - 1]';
            
        else
            % Normal padding sitution
            xstart = padX + 1;
            ystart = padY + 1;
            xend = size(data,2) - padX;
            yend = size(data,1) - padY;   
            xyzOffset = '[query.xRange(1) + padX, query.yRange(1) + padY, query.zRange(1) + ii - 1]';
        end
    else
        xstart = 1;
        xend = size(data,2);
        ystart = 1;
        yend = size(data,1);
        xyzOffset = '[query.xRange(1),query.yRange(1),query.zRange(1) + ii - 1]';
    end
    
   
    size(data)
    block_up_times = [];
    
    %%%%% TEMPORARY HARD CODE
    %oo.setServerLocation('http://dsp061.pha.jhu.edu/');
    oo.setAnnoToken(anno_token);
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    for ii = 1:span:size(data,3)
        if (ii + span - 1) > size(data,3)
            end_ind = size(data,3);
        else
            end_ind = ii + span - 1;
        end
        
        % Create RAMONVolume to block upload
        v = RAMONVolume();
        fprintf('ii: %d, end_ind: %d\n',ii,end_ind);
        v.setCutout(data(ystart:yend,xstart:xend,ii:end_ind));
        v.setResolution(query.resolution);
        v.setXyzOffset(eval(xyzOffset));
        v.setDataType(eRAMONDataType.anno32);
              
        
        % Upload
        t_up = tic;
        oo.createAnnotation(v);   
        block_up_times = cat(1,block_up_times,toc(t_up));
    end    

        
    fprintf('Uploading complete\n');
    fprintf('Max block time: %f seconds\n',max(block_up_times));
    fprintf('Min block time: %f seconds\n',min(block_up_times));
    fprintf('Average block time: %f seconds\n',mean(block_up_times));    
    fprintf('Total upload time:');
    toc(t_total)    
end

