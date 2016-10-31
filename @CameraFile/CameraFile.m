classdef CameraFile < handle
    %CameraFile Helps to read images from a folder that is constantly filled by another program
    %   The purpose of the class is to handle a beam profiler that comes with its own software and
    %   cannot easily be integrated in MATLAB. Instead, the third party software is used to setup
    %   the beam profiler including triggering, etc. The third party software is configured to write
    %   each image, i.e. a beam profile, to a dedicated folder with sequential file naming, i.e.
    %   data_001.raw, data_002.raw, etc. This class can be used to check for new files and read them
    %   to memory, in principle it does not need to be images, any data is supported.
    %
    %   The object can be saved to disk, but it stores only the settings and not the actual data or
    %   user data. This can be used to quickly store the settings of the object to disk for a later
    %   recovery.
    %
    %----------------------------------------------------------------------------------
    %   Copyright 2016 Alexander Ludwig Klein, alexludwigklein@gmail.com
    %
    %   Physics of Fluids, University of Twente
    %----------------------------------------------------------------------------------
    
    %% Properties
    properties (GetAccess = public, SetAccess = public, Dependent = true)
        % Directory The directory that is checked for new files (char)
        %
        % The input is converted to a fullpath
        Directory
        % Filename The basename of the files this class should be looking for (char or function handle)
        %
        % This property is used to find new file, in case it is a char the directory is checked for
        % new files by dir('<Filename>*'), but it can also be a function handle in which case it is
        % called with the directory as first input and UserData as second input and should return a
        % structure as returned by the dir command, please note: no error checking for this so far
        Filename
        % CheckTime True/false whether to check for a change of time of already read files to
        % re-read them as new files into the Data property
        CheckTime
        % CheckSize True/false whether to check for a change of file size of already read files to
        % re-read them as new files into the Data property
        CheckSize
        % ProcessFcn A function called in order to read the data from a single file ('' or function_handle)
        %
        % The function is called with the fullpath to the file as first input and the UserData as
        % second input and should return the data
        ProcessFcn
        % StartFcn A function called with the object and event data at the beginning ('' or function_handle)
        StartFcn
        % TimerFcn A function called with the object and event data during logging ('' or function_handle)
        TimerFcn
        % FramesAcquiredFcn A function called with the object and event data during logging in case files are read ('' or function_handle)
        FramesAcquiredFcn
        % PreviewFcn A function to show a preview based on the last image read ('' or function_handle)
        %
        % The PreviewFcn is called with the object as first input and the last acquired data
        % structure as second input, for initialization of the preview the function is called with
        % the object as only input argument (that way the number of input arguments determines the
        % state, where two input arguments mean a display run and one input argument means an
        % initialization run, see obj.preview for an example)
        PreviewFcn
        % PreviewTransform A function to transform the preview data, i.e. the data field of the Data structure ('' or function_handle)
        PreviewTransform
        % StopFcn A function called with the object and event data at the end ('' or function_handle)
        StopFcn
        % ErrorFcn A function called with the object and event data during logging in case an error occurs ('' or function_handle)
        ErrorFcn
        % StopFile The basename of a stop file this class should be looking for (char or function_handle)
        %
        % This property is used to find file that - in case it is found - leads to a stop of the
        % timer, in case it is a char the directory is checked for stop files by dir('<Filename>*'),
        % but it can also be a function handle in which case it is called with the directory as
        % first input and UserData as second input and should return true if the timer should stop
        % otherwise false, empty value disables the feature
        StopFile
        % MemoryLimit Limit of memory usage in MiB to output a warning (double)
        MemoryLimit
        % Period The time intervall to check for new files in s (double)
        %
        % The value needs to be larger than 0.001, default is 1 s
        Period
        % NumberOfRuns Sets the number of runs (double)
        NumberOfRuns
        % Running True/false whether the object is armed and checks for new files at given Period (logical)
        Running
        % Logging True/false whether the object is logging data to memory, this is the same as running for this object (logical)
        %
        % This could be changed in the future to allow logging to disk, etc.
        Logging
        % Data The data recovered from the files (structure)
        %
        % This property is a structure array and holds the actual data acquired from each file. The
        % fields of the structure array are:
        %       data: The actual data, i.e the image data (arbitrary datatype)
        %   filename: The relative filename of the file the data was read from (char)
        %      bytes: The file size in bytes (double)
        %       time: The timestamp of the file (datetime)
        Data
        % Verbose Indicates how much to output (double)
        %
        %  <   0: Print no output to command line
        %  >   0: Print more information to commmand line
        %  > 100: Print all information to commmand line
        Verbose
    end
    
    properties (GetAccess = public, SetAccess = protected, Dependent = true)
        % RunningTimer char 'on' or 'off' whether the timer of the object is currently running (char)
        RunningTimer
        % AveragePeriod Information given by timer object (double)
        AveragePeriod
        % FramesAcquired Number of frames in data property (double)
        FramesAcquired
        % InstantPeriod Information given by timer object (double)
        InstantPeriod
        % Locked True/false whether the object is locked
        %
        % A very simple (and maybe not 100% safe) way to make sure no data is changed externally
        % during a run of the timer function
        Locked
        % Memory Memory usage in MiB of stored data (double)
        Memory
    end
    
    properties (GetAccess = public, SetAccess = public)
        % Name A short name for the device (char)
        Name = 'CameraFile';
    end
    
    properties (GetAccess = public, SetAccess = public, Transient = true)
        % UserData Userdata linked to the device (arbitrary)
        UserData = [];
    end
    
    properties (GetAccess = protected, SetAccess = protected, Transient = true)
        % p_Data Storage for Data
        p_Data = struct('data',{},'filename',{},'bytes',{},'time',{});
        % p_Timer Storage for timer object
        p_Timer = [];
        % p_Locked Storage for Locked
        p_Locked = false;
    end
    
    properties (GetAccess = protected, SetAccess = protected, Transient = false)
        % p_Disk Storage for Directory, Filename and helper(s)
        p_Disk = struct('directory','','filename','','period',1,'numberOfRuns',Inf,...
            'processfcn','','startfcn','','stopfcn','','timerfcn','','errorfcn','',...
            'framesfcn','','previewfcn','','previewtransform','','memorylimit',8192,...
            'stopfile','','verbose',100, 'checktime',true,'checksize',true,'pausepreview',false);
    end
    
    %% Events
    events
        % newData Notify when new data is added to the Data property
        newData
    end
    
    %% Constructor and SET/GET
    methods
        function obj = CameraFile(mydir)
            % CameraFile Class constructor that accepts a directory as input, takes the current
            % directory as default choice
            
            if nargin < 1, mydir = pwd; end
            if ~(ischar(mydir) && exist(mydir,'dir') == 7)
                error(sprintf('%s:Input',mfilename),...
                    'Input must be a path to an existing directory as char, please check input!');
            end
            % set directory
            obj.Directory = mydir;
            % set default process function
            obj.p_Disk.processfcn = @(fn,~) fprintf('Processing file %s\n',fn);
            showInfo(obj);
        end
        
        function                 disp(obj)
            % disp Displays object on command line
            
            %
            % use buildin disp to show properties in long format, otherwise just a short info
            spacing     = '     ';
            if ~isempty(obj) && ismember(get(0,'Format'),{'short','shortE','shortG','shortEng'}) && isvalid(obj)
                fprintf(['%s%s object, use class method ''showInfo'' to get more information,\n',...
                    '%schange command window to long output format, i.e. ''format long'' or\n',...
                    '%suse ''properties'' and ''doc'' to get a list of the object properties'],...
                    spacing,class(obj),spacing,spacing)
                fprintf('\n');
                str = obj.showInfo(true,true);
                fprintf([spacing '%s\n'],str{:});
                if ~isequal(get(0,'FormatSpacing'),'compact')
                    disp(' ');
                end
            else
                builtin('disp',obj);
            end
        end
        
        function       delete(obj)
            % delete Deletes object and make sure timer is deleted
            
            stop(obj);
            closepreview(obj);
            obj.p_Data = [];
            if ~isempty(obj.p_Timer) && isvalid(obj.p_Timer)
                delete(obj.p_Timer);
            end
        end
        
        function out = get.Data(obj)
            out = obj.p_Data;
        end
        
        function       set.Data(obj,value)
            if obj.Running
                error(sprintf('%s:Input',mfilename),...
                    ['The object is currently running and needs to be disabled before any change can be done, ',...
                    'use the getData method to read out and (partially) reset the data while the object is logging']);
            end
            if isempty(value)
                obj.p_Data = struct('data',{},'filename',{},'bytes',{},'time',{});
            else
                error(sprintf('%s:Input',mfilename),...
                    'Data can only be changed by a reset by supplying an empty value, please check input!');
            end
        end
        
        function out = get.FramesAcquired(obj)
            out = numel(obj.p_Data);
        end
        
        function out = get.Directory(obj)
            out = obj.p_Disk.directory;
        end
        
        function       set.Directory(obj,value)
            if obj.Running
                error(sprintf('%s:Input',mfilename),...
                    'The object is currently running and needs to be disabled before any change can be done');
            end
            if ischar(value) && exist(value,'dir') == 7
                obj.p_Disk.directory = fullpath(value);
            else
                error(sprintf('%s:Input',mfilename),...
                    'Directory must be a path to an existing directory as char, please check input!');
            end
        end
        
        function out = get.Filename(obj)
            out = obj.p_Disk.filename;
        end
        
        function       set.Filename(obj,value)
            if obj.Running
                error(sprintf('%s:Input',mfilename),...
                    'The object is currently running and needs to be disabled before any change can be done');
            end
            if ischar(value) || isa(value,'function_handle')
                obj.p_Disk.filename = value;
            else
                error(sprintf('%s:Input',mfilename),...
                    'Filename must be a char or a function handle, please check input!');
            end
        end
        
        function out = get.CheckTime(obj)
            out = obj.p_Disk.checktime;
        end
        
        function       set.CheckTime(obj,value)
            if islogical(value) && isscalar(value)
                obj.p_Disk.checktime = value;
            else
                error(sprintf('%s:Input',mfilename),...
                    'CheckTime must be a scalar logical, please check input!');
            end
        end
        
        function out = get.CheckSize(obj)
            out = obj.p_Disk.checksize;
        end
        
        function       set.CheckSize(obj,value)
            if islogical(value) && isscalar(value)
                obj.p_Disk.checksize = value;
            else
                error(sprintf('%s:Input',mfilename),...
                    'CheckSize must be a scalar logical, please check input!');
            end
        end
        
        function out = get.StopFile(obj)
            out = obj.p_Disk.stopfile;
        end
        
        function       set.StopFile(obj,value)
            if ischar(value)
                obj.p_Disk.stopfile = value;
            elseif isa(value,'function_handle')
                obj.p_Disk.stopfile = value;
            else
                error(sprintf('%s:Input',mfilename),...
                    'StopFile must be a char or a function handle, please check input!');
            end
        end
        
        function out = get.ProcessFcn(obj)
            out = obj.p_Disk.processfcn;
        end
        
        function       set.ProcessFcn(obj,value)
            if isa(value,'function_handle')
                obj.p_Disk.processfcn = value;
            else
                error(sprintf('%s:Input',mfilename),...
                    'ProcessFcn must be a function handle, please check input!');
            end
        end
        
        function out = get.StartFcn(obj)
            out = obj.p_Disk.startfcn;
        end
        
        function       set.StartFcn(obj,value)
            if obj.Running
                error(sprintf('%s:Input',mfilename),...
                    'The object is currently running and needs to be disabled before any change can be done');
            end
            if isempty(value)
                obj.p_Disk.startfcn = '';
            elseif isa(value,'function_handle')
                obj.p_Disk.startfcn = value;
            else
                error(sprintf('%s:Input',mfilename),...
                    'StartFcn must be a function handle or empty, please check input!');
            end
        end
        
        function out = get.TimerFcn(obj)
            out = obj.p_Disk.timerfcn;
        end
        
        function       set.TimerFcn(obj,value)
            if isempty(value)
                obj.p_Disk.timerfcn = '';
            elseif isa(value,'function_handle')
                obj.p_Disk.timerfcn = value;
            else
                error(sprintf('%s:Input',mfilename),...
                    'TimerFcn must be a function handle or empty, please check input!');
            end
        end
        
        function out = get.PreviewFcn(obj)
            out = obj.p_Disk.previewfcn;
        end
        
        function       set.PreviewFcn(obj,value)
            if isempty(value)
                obj.p_Disk.previewfcn = '';
            elseif isa(value,'function_handle')
                obj.p_Disk.previewfcn = value;
            else
                error(sprintf('%s:Input',mfilename),...
                    'PreviewFcn must be a function handle or empty, please check input!');
            end
        end
        
        function out = get.PreviewTransform(obj)
            out = obj.p_Disk.previewtransform;
        end
        
        function       set.PreviewTransform(obj,value)
            if isempty(value)
                obj.p_Disk.previewtransform = '';
            elseif isa(value,'function_handle')
                obj.p_Disk.previewtransform = value;
            else
                error(sprintf('%s:Input',mfilename),...
                    'PreviewTransform must be a function handle or empty, please check input!');
            end
        end
        
        function out = get.FramesAcquiredFcn(obj)
            out = obj.p_Disk.framesfcn;
        end
        
        function       set.FramesAcquiredFcn(obj,value)
            if isempty(value)
                obj.p_Disk.framesfcn = '';
            elseif isa(value,'function_handle')
                obj.p_Disk.framesfcn = value;
            else
                error(sprintf('%s:Input',mfilename),...
                    'FramesAcquiredFcn must be a function handle or empty, please check input!');
            end
        end
        
        function out = get.ErrorFcn(obj)
            out = obj.p_Disk.errorfcn;
        end
        
        function       set.ErrorFcn(obj,value)
            if isempty(value)
                obj.p_Disk.errorfcn = '';
            elseif isa(value,'function_handle')
                obj.p_Disk.errorfcn = value;
            else
                error(sprintf('%s:Input',mfilename),...
                    'ErrorFcn must be a function handle or empty, please check input!');
            end
        end
        
        function out = get.StopFcn(obj)
            out = obj.p_Disk.stopfcn;
        end
        
        function       set.StopFcn(obj,value)
            if isempty(value)
                obj.p_Disk.stopfcn = '';
            elseif isa(value,'function_handle')
                obj.p_Disk.stopfcn = value;
            else
                error(sprintf('%s:Input',mfilename),...
                    'StopFcn must be a function handle or empty, please check input!');
            end
        end
        
        function out = get.Period(obj)
            out = obj.p_Disk.period;
        end
        
        function       set.Period(obj,value)
            if obj.Running
                error(sprintf('%s:Input',mfilename),...
                    'The object is currently running and needs to be disabled before any change can be done');
            end
            if isnumeric(value) && isscalar(value) && value > 0.001
                obj.p_Disk.period = value;
            else
                error(sprintf('%s:Input',mfilename),...
                    'Period must be scalar double larger than 0.001, please check input!');
            end
        end
        
        function out = get.MemoryLimit(obj)
            out = obj.p_Disk.memorylimit;
        end
        
        function       set.MemoryLimit(obj,value)
            if isnumeric(value) && isscalar(value) && value > 0
                obj.p_Disk.memorylimit = value;
            else
                error(sprintf('%s:Input',mfilename),...
                    'MemoryLimit must be scalar double larger than zero, please check input!');
            end
        end
        
        function out = get.NumberOfRuns(obj)
            out = obj.p_Disk.numberOfRuns;
        end
        
        function       set.NumberOfRuns(obj,value)
            if obj.Running
                error(sprintf('%s:Input',mfilename),...
                    'The object is currently running and needs to be disabled before any change can be done');
            end
            if isnumeric(value) && isscalar(value) && value > 0
                obj.p_Disk.numberOfRuns = value;
            else
                error(sprintf('%s:Input',mfilename),...
                    'NumberOfRuns must be scalar double larger than zero, please check input!');
            end
        end
        
        function out = get.Verbose(obj)
            out = obj.p_Disk.verbose;
        end
        
        function       set.Verbose(obj,value)
            if isnumeric(value) && isscalar(value)
                obj.p_Disk.verbose = value;
            else
                error(sprintf('%s:Input',mfilename),...
                    'Verbose must be scalar double, please check input!');
            end
        end
        
        function out = get.Logging(obj)
            out = obj.Running;
        end
        
        function       set.Logging(obj,value)
            obj.Running = value;
        end
        
        function out = get.Running(obj)
            out = ~isempty(obj.p_Timer) && isvalid(obj.p_Timer);
        end
        
        function       set.Running(obj,value)
            if islogical(value) && isscalar(value)
                if isempty(obj.p_Timer) || ~isvalid(obj.p_Timer)
                    if value
                        %
                        % check directory
                        if isempty(obj.Directory) || ~(exist(obj.Directory,'dir') == 7)
                            error(sprintf('%s:Input',mfilename),...
                                'Directory ''%s'' must be a path to an existing directory, please check settings',obj.Directory);
                        end
                        %
                        % create a new timer
                        obj.p_Timer = timer('BusyMode','drop','ErrorFcn',@(~,event) timerErrorFcn(obj,event),...
                            'ExecutionMode','fixedRate','Name',sprintf('timer-%s',class(obj)),...
                            'ObjectVisibility','off','Period',obj.Period,...
                            'StartFcn',@(~,event) timerStartFcn(obj,event),'StopFcn',@(~,event) timerStopFcn(obj,event),...
                            'Tag',sprintf('timer-%s-%s',class(obj),obj.Directory),...
                            'TasksToExecute',obj.NumberOfRuns,'TimerFcn',@(~,event) timerRunFcn(obj,event));
                        start(obj.p_Timer);
                    else
                        obj.p_Timer = [];
                    end
                else
                    if value
                        % timer exists and should be running
                    else
                        % stop timer, cleanup via stopfunction
                        stop(obj.p_Timer);
                        % delete to be sure
                        delete(obj.p_Timer);
                        obj.p_Timer = [];
                        
                    end
                end
            else
                error(sprintf('%s:Input',mfilename),...
                    'Running must be scalar logical, please check input!');
            end
        end
        
        function out = get.RunningTimer(obj)
            if isempty(obj.p_Timer) || ~isvalid(obj.p_Timer)
                out = 'off';
            else
                out = obj.p_Timer.Running;
            end
        end
        
        function out = get.AveragePeriod(obj)
            if isempty(obj.p_Timer) || ~isvalid(obj.p_Timer)
                out = NaN;
            else
                out = obj.p_Timer.AveragePeriod;
            end
        end
        
        function out = get.InstantPeriod(obj)
            if isempty(obj.p_Timer) || ~isvalid(obj.p_Timer)
                out = NaN;
            else
                out = obj.p_Timer.InstantPeriod;
            end
        end
        
        function       set.Name(obj,value)
            
            if ischar(value)
                obj.Name = value;
            else
                error(sprintf('%s:Input',mfilename),...
                    'Name is expected to be a char, please check input!');
            end
        end
        
        function out = get.Locked(obj)
            
            out = obj.p_Locked;
        end
        
        function out = get.Memory(obj)
            
            nImage = numel(obj.p_Data);
            if nImage > 0
                curval   = obj.p_Data(1); %#ok<NASGU>
                fileInfo = whos('curval','bytes');
                out      = nImage*fileInfo.bytes/1024^2;
            else
                out = 0;
            end
        end
    end
    
    %% Methods
    methods (Access = public, Hidden = false)
        function varargout = runManual(obj)
            % runmanual Checks for new files and post processes them, use this to call a single post
            % processing run manually, returns the number files that were read
            
            nFiles = NaN;
            if ~obj.Running && obj.Locked
                warning(sprintf('%s:Input',mfilename),...
                    '%s is not running but locked, please check!',obj.Name);
            elseif ~obj.Locked
                nFiles = timerRunFcn(obj,[]);
            end
            if nargout > 0, varargout = {nFiles}; end
        end
        
        function varargout = showInfo(obj, noPrint, onlyState)
            % showInfo Shows information on device on command line and returns cellstr with info,
            % output to command line can be supressed by the logical noPrint input
            
            if nargin < 2 || isempty(noPrint),   noPrint   = false; end
            if nargin < 3 || isempty(onlyState), onlyState = false; end
            if ~(islogical(noPrint) && isscalar(noPrint))
                error(sprintf('%s:Input',mfilename),...
                    'Optional second input is expected to be a scalar logical, please check input!');
            end
            %
            % built top information strings
            out        = cell(1);
            sep        = '  ';
            lenChar    = 22;
            out{end+1} = sprintf('%s connected to directory ''%s'' ',...
                obj.Name,obj.Directory);
            sep2       = repmat('-',1,numel(out{end}));
            out{end+1} = sep2;
            out{1}     = sep2;
            fn         = properties(obj);
            %
            % add settings
            if ~onlyState
                out{end+1} = sprintf('%s%*s Settings',sep,lenChar,'CameraFile');
                out{end+1} = sprintf('%s%*s---------------',sep,lenChar,'--------------');
                for n = 1:numel(fn)
                    switch fn{n}
                        case {'Directory' 'Filename' 'StopFile'}
                            out{end+1} = sprintf('%s%*s: %s',sep,lenChar,fn{n},obj.(fn{n})); %#ok<AGROW>
                        case {'ProcessFcn' 'StartFcn' 'TimerFcn' 'FramesAcquiredFcn' 'PreviewFcn' 'PreviewTransform' ...
                                'StopFcn' 'ErrorFcn'}
                            if isempty(obj.(fn{n}))
                                out{end+1} = sprintf('%s%*s: %s',sep,lenChar,fn{n},obj.(fn{n})); %#ok<AGROW>
                            else
                                out{end+1} = sprintf('%s%*s: %s',sep,lenChar,fn{n},func2str(obj.(fn{n}))); %#ok<AGROW>
                            end
                        case {'CheckTime' 'CheckSize' 'MemoryLimit' 'Period' 'NumberOfRuns' 'Verbose'}
                            out{end+1} = sprintf('%s%*s: %s',sep,lenChar,fn{n},num2str(obj.(fn{n}))); %#ok<AGROW>
                    end
                end
            end
            %
            % state
            out{end+1} = ' ';
            out{end+1} = sprintf('%s%*s State',sep,lenChar,'CameraFile');
            out{end+1} = sprintf('%s%*s---------------',sep,lenChar,'--------------');
            for n = 1:numel(fn)
                switch fn{n}
                    case {'error','warning','timestampmode'}
                        out{end+1} = sprintf('%s%*s: %s',sep,lenChar,fn{n},obj.(fn{n})); %#ok<AGROW>
                    case {'temperatureccd','temperaturecamera','temperaturepower'}
                        out{end+1} = sprintf('%s%*s: %s',sep,lenChar,fn{n},num2str(myh.(fn{n}))); %#ok<AGROW>
                end
            end
            out{end+1} = sprintf('%s%*s: %s',sep,lenChar,'AveragePeriod',num2str(obj.AveragePeriod));
            out{end+1} = sprintf('%s%*s: %s',sep,lenChar,'InstantPeriod',num2str(obj.InstantPeriod));
            out{end+1} = sprintf('%s%*s: %d',sep,lenChar,'FramesAcquired',obj.FramesAcquired);
            out{end+1} = sprintf('%s%*s: %d',sep,lenChar,'Locked',obj.Locked);
            out{end+1} = sprintf('%s%*s: %d',sep,lenChar,'Logging',obj.Logging);
            out{end+1} = sprintf('%s%*s: %d',sep,lenChar,'Running',obj.Running);
            out{end+1} = sprintf('%s%*s: %.2f MiB',sep,lenChar,'ComputerRAM',obj.Memory);
            %
            % Finishing
            idxEmpty      = cellfun('isempty',out);
            nMax          = max(cellfun(@(x) numel(x),out));
            out(idxEmpty) = {repmat('-',1,nMax)};
            out{end+1}    = out{1};
            %
            % output to command line and as argument
            if ~noPrint
                for i = 1:numel(out)
                    fprintf('%s\n',out{i});
                end
            end
            if nargout > 0, varargout = {out}; end
        end
        
        function             start(obj)
            % start Starts checking for files
            
            obj.Running = true;
        end
        
        function             stop(obj)
            % stop Stops checking for files
            
            if isempty(obj.p_Timer) || ~isvalid(obj.p_Timer)
                obj.p_Timer = [];
            elseif isvalid(obj.p_Timer)
                stop(obj.p_Timer);
            end
            obj.Running = false;
        end
        
        function             resetData(obj)
            % resetData Reset Data property and delete any existing data
            
            obj.Data = [];
        end
        
        function data      = getData(obj,idx)
            % getData Returns data of given index (or all data in case the optional argument is
            % omitted) and sets the corresponding data field in the class property to empty. For
            % example: getData(obj,1) returns obj.Data(1) and sets obj.Data(1).data = []; Note:
            % this function can be called while new files are still being read from disk.
            
            while obj.p_Locked, pause(max(0.001,obj.Period/2)); end
            obj.p_Locked = true;
            if nargin < 2, idx = 1:numel(obj.p_Data);end
            assert(isempty(idx) || (isnumeric(idx) && min(idx) > 0 && max(idx) <= numel(obj.p_Data)),...
                sprintf('%s:Input',mfilename),...
                'Given index is out of bounds or wrong data type, please check!');
            if isempty(idx)
                data = obj.p_Data([]);
            else
                data = obj.p_Data(idx);
                for idx = reshape(idx,1,[])
                    obj.p_Data(idx).data = [];
                end
            end
            obj.p_Locked = false;
        end
        
        function             flushData(obj)
            % flushData Removes data from object
            
            maxCounter = 10;
            counter    = 0;
            while obj.p_Locked && counter < maxCounter
                pause(max(0.001,obj.p_Disk.period/2)); 
                counter = counter + 1;
            end
            if obj.Locked
                warning(sprintf('%s:Input',mfilename),...
                    '%s is locked, could not flush the data!',obj.Name);
            end
            obj.Data = [];
        end
        
        function             flushFiles(obj)
            % flushFiles Removes files from disk
            
            tmp = fullfile(obj.Directory,[obj.Filename, '*.*']);
            % disable warning in case a file is tried to be removed while being written, which
            % should throw a permission denied warning, restore warning state after delete
            warnStruct = warning('off','MATLAB:DELETE:Permission');
            delete(tmp);
            warning(warnStruct);
        end
                
        function             fixLock(obj)
            % fixLock Disabled lock
            
            if obj.Locked
                warning(sprintf('%s:Input',mfilename),...
                    'Removing lock from object %s',obj.Name);
            end
            obj.p_Locked = false;
        end
        
        function             preview(obj,img)
            % preview Function that can be used to show a preview during logging
            %
            % Depending on the input arguments the function reacts differently
            %  * Two inputs (object, data): the function updates the preview graphics if all
            %    information is available, i.e. due to an initialization, otherwise the preview is
            %    disabled
            %  * Two inputs (object, image): the second input is expected to be an image object,
            %    which will be updated during consecutive calls of this function with three inputs,
            %    the title of the parent axes of the image object will also be updated
            %  * One input (object): a new figure, axes and image object are created for a live
            %    preview
            
            %
            if nargin == 2 && isstruct(img) &&  isfield(obj.UserData,'Preview') && ...
                    isvalid(obj.UserData.Preview.hImg)
                %
                % should be an update run, no further error checking
                %
                obj.UserData.Preview.hImg.CData    = img.data;
                obj.UserData.Preview.hTitle.String = {strrep(obj.p_Disk.directory,'\','\\'), ...
                    sprintf('%s %s',datestr(img.time),strrep(img.filename,'_','\_')),...
                    sprintf('Memory usage %.2f MiB',obj.Memory)};
                drawnow;
            elseif nargin <= 2
                %
                % initialization of graphics
                %
                imgPix = zeros(1360,1024,'uint16');
                if nargin < 2
                    % no image object was given, check UserData for existing one, otherwise build
                    % figure from scratch
                    if ~(isfield(obj.UserData,'Preview') && isstruct(obj.UserData.Preview) && ...
                            all(isfield(obj.UserData.Preview,{'hFig','hImg'})) && ...
                            isvalid(obj.UserData.Preview.hImg))
                        % no previous image object seems to be valid, build figure from scratch
                        hFig = figure('numbertitle', 'off', 'Visible','on',...
                            'name', sprintf('%s: Preview', obj.Name), ...
                            'menubar','none', ...
                            'toolbar','figure', ...
                            'resize', 'on', ...
                            'HandleVisibility','callback',...
                            'tag','PCO Preview', ...
                            'DeleteFcn', @(src,dat) closepreview(obj));
                        hAx = axes('Parent',hFig);
                        img = imshow(imgPix,'Parent',hAx,'InitialMagnification','fit');
                        obj.UserData.Preview.hFig   = hFig;
                        obj.UserData.Preview.hImg   = img;
                        obj.UserData.Preview.hTitle = img.Parent.Title;
                    end
                elseif ~isnumeric(img) && isgraphics(img,'image') && isvalid(img)
                    % image was given as input, remove existing figure
                    if isfield(obj.UserData,'Preview') && isstruct(obj.UserData.Preview) && ...
                            all(isfield(obj.UserData.Preview,{'hFig','hImg'})) && ~isempty(obj.UserData.Preview.hFig)
                        close(obj.UserData.Preview.hFig);
                    end
                    obj.UserData.Preview.hFig   = [];
                    obj.UserData.Preview.hImg   = img;
                    obj.UserData.Preview.hTitle = img.Parent.Title;
                else
                    error(sprintf('%s:Input',mfilename),...
                        '%s received unexpected input for the preview function, please check',obj.Name);
                end
                % prepare preview with an example image of the object
                obj.UserData.Preview.hImg.CData    = imgPix;
                obj.UserData.Preview.hTitle.String = {strrep(obj.p_Disk.directory,'\','\\'), ...
                    sprintf('%s %s',datestr(datetime('now')),'example image 1360x1024'),...
                    sprintf('Memory usage %.2f MiB',obj.Memory)};
                drawnow;
                %
                % enable preview function for object
                %
                obj.p_Disk.pausepreview = false;
                obj.p_Disk.previewfcn   = @preview;
            else
                %
                % unexpected input, close preview
                %
                closepreview(obj);
            end
        end
        
        function             stoppreview(obj)
            % stoppreview Stops the previewing during logging
            
            
            obj.p_Disk.previewfcn = '';
            
        end
        
        function pausepreview(obj)
            % pausepreview Makes sure the preview function is not called during a logging run until
            % resumepreview is called or the logging is restarted
            
            obj.p_Disk.pausepreview = true;
            if isfield(obj.UserData,'Preview') && isvalid(obj.UserData.Preview.hImg)
                obj.UserData.Preview.hTitle.String = {strrep(obj.p_Disk.directory,'\','\\'), ...
                    'Preview is paused',...
                    sprintf('Memory usage %.2f MiB',obj.Memory)};
            end
        end
        
        function resumepreview(obj)
            % resumepreview Makes sure the preview function is called during a logging run until
            % pausepreview is called
            
            obj.p_Disk.pausepreview = false;
        end
        
        function             closepreview(obj)
            % closepreview Stops the previewing during logging and closes the figure, the function
            % does not delete an image object if it was given during initialization
            
            stoppreview(obj);
            if isfield(obj.UserData,'Preview') && isstruct(obj.UserData.Preview) && ...
                    all(isfield(obj.UserData.Preview,{'hFig','hImg'}))
                if ~isempty(obj.UserData.Preview.hFig) && isvalid(obj.UserData.Preview.hFig)
                    close(obj.UserData.Preview.hFig);
                end
                if isfield(obj.UserData,'Preview')
                    obj.UserData = rmfield(obj.UserData,'Preview');
                end
            end
        end
    end
    
    methods (Access = private, Hidden = false)
        function out = timerRunFcn(obj,event)
            % timerRunFcn Performs an actual run to find files and load data
            
            if obj.p_Disk.verbose > 100, fprintf('%s: %s Logging, ', obj.Name, datestr(now)); end
            if nargin < 2, event = []; end
            if obj.p_Locked
                out = 0;
                if obj.p_Disk.verbose > 0, fprintf('Object is currently locked, no images can be read\n'); end
                return;
            end % wait for the next call of the timer
            obj.p_Locked = true;
            %
            % look for new files that have not been processed already
            if ischar(obj.p_Disk.filename)
                filesAll = dir(fullfile(obj.p_Disk.directory,[obj.p_Disk.filename '*']));
                filesAll = filesAll(~[filesAll.isdir]);
                idxNew   = reshape(false(size(filesAll)),1,[]);
                % check for new filenames
                fnAll  = {filesAll.name};
                fnDone = {obj.p_Data.filename};
                isDone = ismember(fnAll,fnDone);
                isDone = reshape(isDone,1,[]);
                idxNew = idxNew | ~isDone;
                % check for file size
                if obj.p_Disk.checksize && ~all(idxNew)
                    linDone = find(isDone);
                    for i = 1:numel(linDone)
                        idx = ismember(fnDone,fnAll{linDone(i)});
                        if all((abs([obj.p_Data(idx).bytes]-filesAll(linDone(i)).bytes) > 0))
                            idxNew(linDone(i)) = true;
                        end
                    end
                end
                % check for creation time
                if obj.p_Disk.checktime && ~all(idxNew)
                    linDone = find(isDone);
                    for i = 1:numel(linDone)
                        idx = ismember(fnDone,fnAll{linDone(i)});
                        if all((abs(datenum([obj.p_Data(idx).time])-filesAll(linDone(i)).datenum) > 1e-7))
                            idxNew(linDone(i)) = true;
                        end
                    end
                end
                filesNew  = filesAll(idxNew);
            else
                filesNew = obj.p_Disk.filename(obj.p_Disk.directory,obj.UserData);
            end
            out = numel(filesNew);
            if obj.p_Disk.verbose > 100, fprintf('%d file(s), ',out); end
            %
            % call processing step
            idx = numel(obj.p_Data) + 1;
            for i = 1:out
                obj.p_Data(idx).data     = obj.p_Disk.processfcn(fullfile(obj.p_Disk.directory,filesNew(i).name),obj.UserData);
                obj.p_Data(idx).filename = filesNew(i).name;
                obj.p_Data(idx).bytes    = filesNew(i).bytes;
                obj.p_Data(idx).time     = datetime(filesNew(i).datenum,'ConvertFrom','datenum');
                idx = idx + 1;
            end
            %
            % check for a stop file
            if ~isempty(obj.p_Disk.stopfile)
                if ischar(obj.p_Disk.stopfile)
                    filesAll  = dir(fullfile(obj.p_Disk.directory,[obj.p_Disk.stopfile '*']));
                    filesAll  = filesAll(~[filesAll.isdir]);
                    stopTimer = numel(filesAll) > 0;
                else
                    stopTimer = obj.p_Disk.stopfile(obj.p_Disk.directory,obj.UserData);
                end
                if stopTimer, stop(obj.p_Timer); end
            end
            %
            % check memory usage
            sizMiB = obj.Memory;
            if sizMiB > obj.p_Disk.memorylimit
                warning(sprintf('%s:Input',mfilename),...
                    'Data property exceeds %f MiB, please be careful',sizMiB);
            end
            %
            % perform steps in case actual images were found
            if out > 0
                %
                % run preview function
                if ~isempty(obj.p_Disk.previewfcn) && ~obj.p_Disk.pausepreview
                    dat = obj.p_Data(idx-1);
                    if ~isempty(obj.p_Disk.previewtransform)
                        dat.data = obj.p_Disk.previewtransform(dat.data);
                    end
                    obj.p_Disk.previewfcn(obj,dat);
                end
                %
                % run user processing
                if ~isempty(obj.p_Disk.framesfcn)
                    obj.p_Disk.framesfcn(obj,event);
                end
            end
            if ~isempty(obj.p_Disk.timerfcn)
                obj.p_Disk.timerfcn(obj,event);
            end
            %
            % output
            if obj.p_Disk.verbose > 100
                fprintf('%s Logging run is finished for %d files in the directory ''%s''\n',...
                    datestr(now),out,obj.p_Disk.directory);
            end
            obj.p_Locked = false;
            if out > 0, notify(obj,'newData'); end
        end
        
        function timerStartFcn(obj,event)
            % timerStartFcn Should be called when timer is started
            
            if obj.p_Disk.verbose > 0, fprintf('%s: %s Starting logging, ', obj.Name, datestr(now)); end
            if nargin < 2, event = []; end
            %
            % run pre processing
            if ~isempty(obj.p_Disk.startfcn)
                obj.p_Disk.startfcn(obj,event);
            end
            %
            % run preview function
            obj.p_Disk.pausepreview = false;
            if ~isempty(obj.p_Disk.previewfcn)
                obj.p_Disk.previewfcn(obj);
            end
            %
            % output
            if obj.p_Disk.verbose > 0
                fprintf('%s Logging is started for directory ''%s''\n',datestr(now),obj.p_Disk.directory);
            end
        end
        
        function timerStopFcn(obj,event)
            % timerStopFcn Should be called when timer stoped
            
            if obj.p_Disk.verbose > 0, fprintf('%s: %s Stopping logging, ', obj.Name, datestr(now)); end
            if nargin < 2, event = []; end
            %
            % take care of the timer object
            % Calling delete function may throw a warning
            %if isempty(obj.p_Timer) || ~isvalid(obj.p_Timer)
            %    obj.p_Timer = [];
            %elseif isvalid(obj.p_Timer)
            %    delete(obj.p_Timer);
            %    obj.p_Timer = [];
            %end
            
            %if strcmpi(obj.p_Timer.Running,'off')
            %    delete(obj.p_Timer);
            %end
            obj.p_Timer = [];
            %
            % run post processing
            if ~isempty(obj.p_Disk.stopfcn)
                obj.p_Disk.stopfcn(obj,event);
            end
            %
            % output
            if obj.p_Disk.verbose > 0
                fprintf('%s Logging is stopped for directory ''%s''\n',datestr(now),obj.p_Disk.directory);
            end
        end
        
        function timerErrorFcn(obj,event)
            % timerErrorFcn Called when an error occurred when the timer was running
            
            if nargin < 2, event = []; end
            %
            % run user specified function
            if ~isempty(obj.p_Disk.errorfcn)
                obj.p_Disk.errorfcn(obj,event);
            end
            %
            % output
            if obj.p_Disk.verbose > 0
                fprintf('%s: %s An error occured during logging in the directory ''%s'' \n', ...
                    obj.Name,datestr(now),obj.p_Disk.directory);
            end
        end
    end
    
    %% Static Methods
    methods (Static = true, Access = public, Hidden = false, Sealed = true)
        function obj = loadobj(obj)
            %loadobj Loads object and check settings
            
            for n = 1:numel(obj)
                if ~(ischar(obj(n).p_Disk.directory) && exist(obj(n).p_Disk.directory,'dir') == 7)
                    warning(sprintf('%s:Input',mfilename),['Directory ''%s'' that was stored with the ',...
                        'object does not seem to exist, using current working directory instead'],obj(n).p_Disk.directory);
                    obj(n).p_Disk.directory = pwd;
                end
                showInfo(obj(n));
            end
        end
    end
end
