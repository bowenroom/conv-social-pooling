%% Process dataset into mat files %%

clear;
clc;

%% Inputs:
% Locations of raw input files:
us101_1 = 'raw/i101_trajectories-0750am-0805am.txt';
us101_2 = 'raw/i101_trajectories-0805am-0820am.txt';
us101_3 = 'raw/i101_trajectories-0820am-0835am.txt';
i80_1 = 'raw/i80_trajectories-0400-0415.txt';
i80_2 = 'raw/i80_trajectories-0500-0515.txt';
i80_3 = 'raw/i80_trajectories-0515-0530.txt';


%% Fields: 

%{ 
1: Dataset Id
2: Vehicle Id
3: Frame Number
4: Local X
5: Local Y
6: Lane Id
7: Lateral maneuver
8: Longitudinal maneuver
9-47: Neighbor Car Ids at grid location
%}



%% Load data and add dataset id
disp('Loading data...')
traj{1} = load(us101_1);    
%size(X,1),返回矩阵X的行数；
traj{1} = single([ones(size(traj{1},1),1),traj{1}]);
traj{2} = load(us101_2);
traj{2} = single([2*ones(size(traj{2},1),1),traj{3}]);
traj{3} = load(us101_3);
traj{3} = single([3*ones(size(traj{3},1),1),traj{3}]);
traj{4} = load(i80_1);    
traj{4} = single([4*ones(size(traj{4},1),1),traj{4}]);
traj{5} = load(i80_2);
traj{5} = single([5*ones(size(traj{5},1),1),traj{6}]);
traj{6} = load(i80_3);
traj{6} = single([6*ones(size(traj{6},1),1),traj{6}]);

for k = 1:6
    traj{k} = traj{k}(:,[1,2,3,6,7,15]);
    if k <=3
        traj{k}(traj{k}(:,6)>=6,6) = 6;
    end
end



%% Parse fields (listed above):
disp('Parsing fields...')
poolobj = parpool(6);

parfor ii = 1:6
    for k = 1:length(traj{ii}(:,1));
        
        %对刚刚筛选出来的6列文件赋予header
        time = traj{ii}(k,3);
        dsId = traj{ii}(k,1);
        vehId = traj{ii}(k,2);
        %same dataset and same vehicle
        vehtraj = traj{ii}(traj{ii}(:,1)==dsId & traj{ii}(:,2)==vehId,:);
        %find()函数的基本功能是返回向量或者矩阵中不为0的元素的位置索引
        ind = find(vehtraj(:,3)==time);
        %ind指的是车辆行驶中的时间序列
        ind = ind(1);
        lane = traj{ii}(k,6);
        
        
        % Get lateral maneuver:获取水平方向的车辆动作信息
        %size(A,1)该语句返回的是矩阵A的行数
        % ub,lb: upper baseline and the lower baseline
        ub = min(size(vehtraj,1),ind+40);
        lb = max(1, ind-40);
        % 6:laneId,7:lateral maneuver,8:longitudinal maneuver;
        % lateral maneuver: left and right lane changing and lane keeping
        if vehtraj(ub,6)>vehtraj(ind,6) || vehtraj(ind,6)>vehtraj(lb,6)
            traj{ii}(k,7) = 3;
        elseif vehtraj(ub,6)<vehtraj(ind,6) || vehtraj(ind,6)<vehtraj(lb,6)
            traj{ii}(k,7) = 2;
        else
            traj{ii}(k,7) = 1;
        end
        
        
        % Get longitudinal maneuver:
        ub = min(size(vehtraj,1),ind+50);
        lb = max(1, ind-30);
        if ub==ind || lb ==ind
            traj{ii}(k,8) =1;
        else
            % actual speed
            vHist = (vehtraj(ind,5)-vehtraj(lb,5))/(ind-lb);
            % future position
            vFut = (vehtraj(ub,5)-vehtraj(ind,5))/(ub-ind);
            % 定义刹车的动作
            if vFut/vHist <0.8
                traj{ii}(k,8) =2;
            else
                traj{ii}(k,8) =1;
            end
        end
        
        
        % Get grid locations: 在文中的5.5 中有讲解
        frameEgo = traj{ii}(traj{ii}(:,1)==dsId & traj{ii}(:,3)==time & traj{ii}(:,6) == lane,:);
        frameL = traj{ii}(traj{ii}(:,1)==dsId & traj{ii}(:,3)==time & traj{ii}(:,6) == lane-1,:);
        frameR = traj{ii}(traj{ii}(:,1)==dsId & traj{ii}(:,3)==time & traj{ii}(:,6) == lane+1,:);
        if ~isempty(frameL)
            for l = 1:size(frameL,1)
                y = frameL(l,5)-traj{ii}(k,5);
                if abs(y) <90
                    gridInd = 1+round((y+90)/15);
                    traj{ii}(k,8+gridInd) = frameL(l,2);
                end
            end
        end
        for l = 1:size(frameEgo,1)
            y = frameEgo(l,5)-traj{ii}(k,5);
            if abs(y) <90 && y~=0
                gridInd = 14+round((y+90)/15);
                traj{ii}(k,8+gridInd) = frameEgo(l,2);
            end
        end
        if ~isempty(frameR)
            for l = 1:size(frameR,1)
                y = frameR(l,5)-traj{ii}(k,5);
                if abs(y) <90
                    gridInd = 27+round((y+90)/15);
                    traj{ii}(k,8+gridInd) = frameR(l,2);
                end
            end
        end
        
    end
end

delete(poolobj);

%% Split train, validation, test
disp('Splitting into train, validation and test sets...')

trajAll = [traj{1};traj{2};traj{3};traj{4};traj{5};traj{6}];
clear traj;

trajTr = [];
trajVal = [];
trajTs = [];
for k = 1:6
    ul1 = round(0.7*max(trajAll(trajAll(:,1)==k,2)));
    ul2 = round(0.8*max(trajAll(trajAll(:,1)==k,2)));
    
    trajTr = [trajTr;trajAll(trajAll(:,1)==k & trajAll(:,2)<=ul1, :)];
    trajVal = [trajVal;trajAll(trajAll(:,1)==k & trajAll(:,2)>ul1 & trajAll(:,2)<=ul2, :)];
    trajTs = [trajTs;trajAll(trajAll(:,1)==k & trajAll(:,2)>ul2, :)];
end

 tracksTr = {};
for k = 1:6
    trajSet = trajTr(trajTr(:,1)==k,:);
    carIds = unique(trajSet(:,2));
    for l = 1:length(carIds)
        %get the track of carId
        vehtrack = trajSet(trajSet(:,2) ==carIds(l),3:5)';
        tracksTr{k,carIds(l)} = vehtrack;
    end
end

tracksVal = {};
for k = 1:6
    trajSet = trajVal(trajVal(:,1)==k,:);
    carIds = unique(trajSet(:,2));
    for l = 1:length(carIds)
        vehtrack = trajSet(trajSet(:,2) ==carIds(l),3:5)';
        tracksVal{k,carIds(l)} = vehtrack;
    end
end

tracksTs = {};
for k = 1:6
    trajSet = trajTs(trajTs(:,1)==k,:);
    carIds = unique(trajSet(:,2));
    for l = 1:length(carIds)
        vehtrack = trajSet(trajSet(:,2) ==carIds(l),3:5)';
        tracksTs{k,carIds(l)} = vehtrack;
    end
end


%% Filter edge cases: 
% Since the model uses 3 sec of trajectory history for prediction, the initial 3 seconds of each trajectory is not used for training/testing

disp('Filtering edge cases...')

indsTr = zeros(size(trajTr,1),1);
for k = 1: size(trajTr,1)
    t = trajTr(k,3);
    if tracksTr{trajTr(k,1),trajTr(k,2)}(1,31) <= t && tracksTr{trajTr(k,1),trajTr(k,2)}(1,end)>t+1
        indsTr(k) = 1;
    end
end
trajTr = trajTr(find(indsTr),:);


indsVal = zeros(size(trajVal,1),1);
for k = 1: size(trajVal,1)
    t = trajVal(k,3);
    if tracksVal{trajVal(k,1),trajVal(k,2)}(1,31) <= t && tracksVal{trajVal(k,1),trajVal(k,2)}(1,end)>t+1
        indsVal(k) = 1;
    end
end
trajVal = trajVal(find(indsVal),:);


indsTs = zeros(size(trajTs,1),1);
for k = 1: size(trajTs,1)
    t = trajTs(k,3);
    if tracksTs{trajTs(k,1),trajTs(k,2)}(1,31) <= t && tracksTs{trajTs(k,1),trajTs(k,2)}(1,end)>t+1
        indsTs(k) = 1;
    end
end
trajTs = trajTs(find(indsTs),:);

%% Save mat files:
disp('Saving mat files...')

traj = trajTr;
tracks = tracksTr;
save('TrainSet','traj','tracks');

traj = trajVal;
tracks = tracksVal;
save('ValSet','traj','tracks');

traj = trajTs;
tracks = tracksTs;
save('TestSet','traj','tracks');











