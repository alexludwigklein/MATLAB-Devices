classdef QSmart < handle
    %QSmart Class describing the serial connection to the laser called QSmart by Quantel
    %
    % The class allows to connect to a laser by Quantel via a serial
    % connection (redirected over ethernet by a Lantronix server-client
    % system) and performs some error checking. Settings of the serial
    % connection need to be given to the class constructor.
    %
    %----------------------------------------------------------------------------------
    %   Copyright 2016 Alexander Ludwig Klein, alexludwigklein@gmail.com
    %
    %   Physics of Fluids, University of Twente
    %----------------------------------------------------------------------------------
    
    %% Properties
    properties (GetAccess = public, SetAccess = private)
        % sobj Serial device (serial object)
        sobj
        % opt Options used to initiate serial object, etc.
        opt
        % tmp Temporary storage, e.g. for listeners or timers
        tmp = [];
        % lastRun tic from last time the run command was send
        lastRun = [];
        % doActive True/false whether do is running
        doActive = false;
    end
    
    properties (GetAccess = public, SetAccess = private, Dependent = true)
        % STATE State of laser (double)
        STATE
        % STATUS State of laser (string)
        STATUS
        % PSVERS Power supply firmware version (double)
        PSVERS
        % LVERS Laser brain firmware version (double)
        LVERS
        % CGTEMP Cooling water temperature in degrees celsius (double)
        CGTEMP
        % TEMP1F Temperature of the 1st crystal in degrees celsius (double)
        TEMP1F
        % CAPVSET Flashlamp voltage in V (double)
        CAPVSET
        % LPW Flashlamp pulse width in ys (double)
        LPW
        % SSHOT Flashlamp shot counter (uint64)
        SSHOT
    end
    
    properties (GetAccess = public, SetAccess = public, Dependent = true)
        % TRIG Trigger settings (1x2 char)
        TRIG
        % USHOT User's shot counter (uint64)
        USHOT
        % QDLY Delay between the end of the flashlamp pulse and the beginning of Q-Switch pulse in ns (double)
        QDLY
        % QDLYO Delay between the Q-Switch pulse and Q-Switch sync out in ns (double)
        QDLYO
        % QSPAR1 Number of cycles for Burst/Scan mode (uint64)
        QSPAR1
        % QSPAR2 Number of passive pulses per cycle for Burst/Scan mode (uint64)
        QSPAR2
        % QSPAR3 Number of active Q-Switch pulses per cycle for Burst/Scan mode (uint64)
        QSPAR3
        % PRF Pulse repetition frequency in internal mode in Hz (double)
        PRF
        % TEMP1S Set point for the temperature of the 1st crystal in degrees celsius (double)
        TEMP1S
    end
    
    %% Events
    events
        % newState Notify when state changes due to flashlamp or Q-Switch start/stop
        newState
        % newSettings Notify if settings are changed
        newSettings
    end
    
    %% Constructor and SET/GET
    methods
        function obj = QSmart(varargin)
            % QSmart Create object that links to serial device
            %
            % Options are supposed to be given in <propertyname> <propertyvalue> style
            
            % get input with input parser
            tmp               = inputParser; %#ok<*PROP>
            tmp.StructExpand  = true;
            tmp.KeepUnmatched = false;
            % serial settings
            tmp.addParameter('Port', 'COM100', ...
                @(x) ~isempty(x) && ischar(x));
            tmp.addParameter('BaudRate', 115200, ...
                @(x) ~isempty(x) && isnumeric(x) && isscalar(x));
            tmp.addParameter('Terminator', {'LF' 'CR/LF'}, ...
                @(x) ~isempty(x) && (ischar(x) || (iscellstr(x) && isequal(size(x),[1 2]))));
            tmp.addParameter('StopBits', 1, ...
                @(x) ~isempty(x) && isnumeric(x) && isscalar(x));
            tmp.addParameter('DataBits', 8, ...
                @(x) ~isempty(x) && isnumeric(x) && isscalar(x));
            tmp.addParameter('Parity', 'none', ...
                @(x) ~isempty(x) && ischar(x));
            tmp.addParameter('FlowControl', 'none', ...
                @(x) ~isempty(x) && ischar(x));
            % additional settings
            tmp.addParameter('Delay', 0.1, ...
                @(x) ~isempty(x) && isnumeric(x) && isscalar(x));
            tmp.addParameter('InputBufferSize', 2^20, ...
                @(x) ~isempty(x) && isnumeric(x) && isscalar(x));
            tmp.addParameter('BytesAvailableFcnCount', 2^8, ...
                @(x) ~isempty(x) && isnumeric(x) && isscalar(x));
            tmp.addParameter('TimeWarmupNLO', 30, ...
                @(x) ~isempty(x) && isnumeric(x) && isscalar(x) && x > 0 && x < 60*30);
            tmp.addParameter('maxTempError', 0.05, ...
                @(x) ~isempty(x) && isnumeric(x) && isscalar(x) && x > 0 && x < 1);
            tmp.parse(varargin{:});
            tmp = tmp.Results;
            % construct serial object and open connection
            try
                obj.sobj = serial(tmp.Port,'BaudRate',tmp.BaudRate,...
                    'Terminator',tmp.Terminator,'StopBits',tmp.StopBits,...
                    'DataBits',tmp.DataBits,'Parity',tmp.Parity,...
                    'FlowControl',tmp.FlowControl);
                obj.sobj.InputBufferSize        = tmp.InputBufferSize;
                obj.sobj.BytesAvailableFcnCount = tmp.BytesAvailableFcnCount;
                fopen(obj.sobj);
            catch %#ok<CTCH>
                error(sprintf('%s:Input',mfilename),'Could not open device');
            end
            obj.opt = tmp;
            pause(obj.opt.Delay);
            if ~isequal(obj.sobj.Status,'open')
                error(sprintf('%s:Input',mfilename),'Could not open device');
            end
            % output information on device
            lvers   = obj.do('LVERS');
            psvers  = obj.do('PSVERS');
            model   = obj.do('MODEL');
            str = sprintf('Connected to device ''%s'':\n%s\n%s\n%s\n',...
                obj.sobj.Name,model, lvers,psvers);
            disp(str);
            % flush buffer 
            while obj.sobj.BytesAvailable > 0
                fscanf(obj.sobj);
            end
        end
        
        function out = get.STATE(obj)
            
            out = obj.do('STATE');
            out = obj.mystr2double(out);
            if isnan(out)
                warning(sprintf('%s:Input',mfilename),'Could not read STATE. Returning NaN!');
                out = NaN;
            end
        end
        
        function out = get.STATUS(obj)
            
            out = obj.do('STATUS');
        end
        
        function out = get.PSVERS(obj)
            
            out = obj.do('PSVERS');
            out = obj.mystr2double(out);
            if isnan(out)
                warning(sprintf('%s:Input',mfilename),'Could not read PSVERS. Returning ''PSVERS = ??''');
                out = 'PSVERS = ??';
            end
        end
        
        function out = get.LVERS(obj)
            
            out = obj.do('LVERS');
            out = obj.mystr2double(out);
            if isnan(out)
                warning(sprintf('%s:Input',mfilename),'Could not read LVERS. Returning ''LVERS = ??''');
                out = 'LVERS = ??';
            end
        end
        
        function out = get.CGTEMP(obj)
            
            out = obj.do('CGTEMP');
            out = obj.mystr2double(out);
            if isnan(out)
                warning(sprintf('%s:Input',mfilename),'Could not read CGTEMP. Returning NaN!');
                out = NaN;
            end
        end
        
        function out = get.TEMP1F(obj)
            
            out = obj.do('TEMP1F');
            out = obj.mystr2double(out);
            if isnan(out)
                warning(sprintf('%s:Input',mfilename),'Could not read TEMP1F. Returning NaN!');
                out = NaN;
            end
        end
        
        function out = get.CAPVSET(obj)
            
            out = obj.do('CAPVSET');
            out = obj.mystr2double(out);
            if isnan(out)
                warning(sprintf('%s:Input',mfilename),'Could not read CAPVSET. Returning NaN!');
                out = NaN;
            end
        end
        
        function out = get.LPW(obj)
            
            out = obj.do('LPW');
            out = obj.mystr2double(out);
            if isnan(out)
                warning(sprintf('%s:Input',mfilename),'Could not read LPW. Returning NaN!');
                out = NaN;
            end
        end
        
        function out = get.SSHOT(obj)
            
            out = obj.do('SSHOT');
            out = obj.mystr2double(out);
            if isnan(out)
                warning(sprintf('%s:Input',mfilename),'Could not read SSHOT. Returning 0!');
                out = NaN;
            end
            out = uint64(out);
        end
        
        function out = get.TRIG(obj)
            
            out = obj.do('TRIG');
            if numel(out) < 3
                warning(sprintf('%s:Input',mfilename),'Could not read TRIG. Returning ''??''!');
                out = '?? ';
            end
            out = out(end-2:end-1);
        end
        
        function set.TRIG(obj, value)
            
            if ~(ischar(value) && numel(value) == 2 && any(strcmp(value,{'II' 'EE' 'IE' 'EI'})) )
                error(sprintf('%s:Input',mfilename),'TRIG can only be ''II'', ''EE'', ''IE'' or ''EI''');
            end
            obj.do(sprintf('TRIG %s',value));
            % pause((obj.opt.Delay);
            if ~isequal(obj.TRIG,value)
                error(sprintf('%s:Input',mfilename),'Could not set TRIG to %s',value);
            end
            notify(obj,'newSettings');
        end
        
        function out = get.USHOT(obj)
            
            out = obj.do('USHOT');
            out = obj.mystr2double(out);
            if isnan(out)
                warning(sprintf('%s:Input',mfilename),'Could not read USHOT. Returning 0!');
                out = NaN;
            end
            out = uint64(out);
        end
        
        function set.USHOT(obj, value)
            
            if ~(isnumeric(value) && isscalar(value) && isequal(value,0))
                error(sprintf('%s:Input',mfilename),'USHOT can only be reset by setting to zero');
            end
            obj.do('USHOT 0');
            % pause((obj.opt.Delay);
            if ~isequal(obj.USHOT,0)
                error(sprintf('%s:Input',mfilename),'Could not reset USHOT to 0');
            end
            notify(obj,'newSettings');
        end
        
        function out = get.QSPAR1(obj)
            
            out = obj.do('QSPAR1');
            out = obj.mystr2double(out);
            if isnan(out)
                warning(sprintf('%s:Input',mfilename),'Could not read QSPAR1. Returning 0!');
                out = NaN;
            end
            out = uint64(out);
        end
        
        function set.QSPAR1(obj, value)
            
            state = obj.STATE;
            if state < 1 || state > 2
                error(sprintf('%s:Input',mfilename),'Bring laser to STATE 1 or 2 before changing this setting');
            end
            if ~(isnumeric(value) && isscalar(value) && round(value) >= 0 && round(value) <= 65535)
                error(sprintf('%s:Input',mfilename),'QSPAR1 must in range 0 to 65535');
            end
            obj.do(sprintf('QSPAR1 %d',round(value)));
            % pause((obj.opt.Delay);
            if ~isequal(obj.QSPAR1,round(value))
                error(sprintf('%s:Input',mfilename),'Could not set QSPAR1 to %d',round(value));
            end
            notify(obj,'newSettings');
        end
        
        function out = get.QSPAR2(obj)
            
            out = obj.do('QSPAR2');
            out = obj.mystr2double(out);
            if isnan(out)
                warning(sprintf('%s:Input',mfilename),'Could not read QSPAR2. Returning 0!');
                out = NaN;
            end
            out = uint64(out);
        end
        
        function set.QSPAR2(obj, value)
            
            state = obj.STATE;
            if state < 1 || state > 2
                error(sprintf('%s:Input',mfilename),'Bring laser to STATE 1 or 2 before changing this setting');
            end
            if ~(isnumeric(value) && isscalar(value) && round(value) >= 0 && round(value) <= 65535)
                error(sprintf('%s:Input',mfilename),'QSPAR2 must in range 0 to 65535');
            end
            obj.do(sprintf('QSPAR2 %d',round(value)));
            % pause((obj.opt.Delay);
            if ~isequal(obj.QSPAR2,round(value))
                error(sprintf('%s:Input',mfilename),'Could not set QSPAR2 to %d',round(value));
            end
            notify(obj,'newSettings');
        end
        
        function out = get.QSPAR3(obj)
            
            out = obj.do('QSPAR3');
            out = obj.mystr2double(out);
            if isnan(out)
                warning(sprintf('%s:Input',mfilename),'Could not read QSPAR3. Returning 0!');
                out = NaN;
            end
            out = uint64(out);
        end
        
        function set.QSPAR3(obj, value)
            
            state = obj.STATE;
            if state < 1 || state > 2
                error(sprintf('%s:Input',mfilename),'Bring laser to STATE 1 or 2 before changing this setting');
            end
            if ~(isnumeric(value) && isscalar(value) && round(value) >= 0 && round(value) <= 65535)
                error(sprintf('%s:Input',mfilename),'QSPAR3 must in range 0 to 65535');
            end
            obj.do(sprintf('QSPAR3 %d',round(value)));
            % pause((obj.opt.Delay);
            if ~isequal(obj.QSPAR3,round(value))
                error(sprintf('%s:Input',mfilename),'Could not set QSPAR3 to %d',round(value));
            end
            notify(obj,'newSettings');
        end
        
        function out = get.QDLY(obj)
            
            out = obj.do('QDLY');
            out = obj.mystr2double(out);
            if isnan(out)
                warning(sprintf('%s:Input',mfilename),'Could not read QDLY. Returning NaN!');
                out = NaN;
            end
        end
        
        function set.QDLY(obj, value)
            
            if ~(isnumeric(value) && isscalar(value) && round(value) >= 0 && round(value) <= 255)
                error(sprintf('%s:Input',mfilename),'QDLY must in range 0 to 255');
            end
            obj.do(sprintf('QDLY %d',round(value)));
            % pause((obj.opt.Delay);
            if ~isequal(obj.QDLY,round(value))
                error(sprintf('%s:Input',mfilename),'Could not set QDLY to %d',round(value));
            end
            notify(obj,'newSettings');
        end
        
        function out = get.QDLYO(obj)
            
            out = obj.do('QDLYO');
            out = obj.mystr2double(out);
            if isnan(out)
                warning(sprintf('%s:Input',mfilename),'Could not read QDLYO. Returning NaN!');
                out = NaN;
            end
        end
        
        function set.QDLYO(obj, value)
            
            if ~(isnumeric(value) && isscalar(value) && round(value) >= -500 && round(value) <= 500)
                error(sprintf('%s:Input',mfilename),'QDLYO must in range -500 to 500');
            end
            obj.do(sprintf('QDLYO %d',round(value)));
            % pause((obj.opt.Delay);
            if ~isequal(obj.QDLYO,round(value))
                error(sprintf('%s:Input',mfilename),'Could not set QDLYO to %d',round(value));
            end
            notify(obj,'newSettings');
        end
        
        function out = get.PRF(obj)
            
            out = obj.do('PRF');
            out = obj.mystr2double(out);
            if isnan(out)
                warning(sprintf('%s:Input',mfilename),'Could not read PRF. Returning NaN!');
                out = NaN;
            end
        end
        
        function set.PRF(obj, value)
            
            if ~(isnumeric(value) && isscalar(value) && value > 0.5 && value <= 2.0)
                error(sprintf('%s:Input',mfilename),'PRF must in range 0.5 to 2.0');
            end
            obj.do(sprintf('PRF %.1f',value));
            notify(obj,'newSettings');
        end
        
        function out = get.TEMP1S(obj)
            
            out = obj.do('TEMP1S');
            out = obj.mystr2double(out);
            if isnan(out)
                warning(sprintf('%s:Input',mfilename),'Could not read TEMP1S. Returning NaN!');
                out = NaN;
            end
        end
        
        function set.TEMP1S(obj, value)
            
            if ~(isnumeric(value) && isscalar(value) && value >= 45 && value <= 55)
                error(sprintf('%s:Input',mfilename),'TEMP1S must in range 45 to 55');
            end
            obj.do(sprintf('TEMP1S %.1f',value));
            notify(obj,'newSettings');
        end
    end
    
    %% Methods
    methods (Access = public, Hidden = false)
        function delete(obj)
            % delete Delete object and make sure serial connection is closed
            
            obj.stopFL;
            if isequal(obj.sobj.Status,'open')
                obj.do('SSWITCH 1');
                fclose(obj.sobj);
            end
            delete(obj.sobj);
        end
        
        function clearInput(obj)
            % clearInput Clears available bytes and show a warning if available lines are not a status line
           
             while obj.sobj.BytesAvailable > 0
                    tmp = fscanf(obj.sobj);
                    tmp = tmp(1:end-1); % remove LF
                    if ~strcmp(tmp(1:5),'OK : ')
                        warning(sprintf('%s:Input',mfilename),'Cleared bytes for ''%s'' are unknown: ''%s''',obj.sobj.Name,tmp);
                    end
             end
        end
        
        function out = do(obj, command)
            % do Send command and acquire return in case anything is available, otherwise return []
            %

            obj.doActive = true;
            % check input
            if ~ischar(command)
                obj.doActive = false;
                error(sprintf('%s:Input',mfilename),'Command (2nd input) must be a char');
            end
            % empty input buffer before writing a new command
            while obj.sobj.BytesAvailable > 0
                fscanf(obj.sobj);
            end
            % write command
            fprintf(obj.sobj,command);
            % read output, but give device some time to write
            counter = 0;
            while obj.sobj.BytesAvailable < 1 && counter < 10
                pause(obj.opt.Delay); % wait for response
                counter = counter + 1;
            end
            if obj.sobj.BytesAvailable > 0
                out = fscanf(obj.sobj);
                out = out(1:end-1); % remove LF
            else
                out = [];
            end
            % check output
            switch command
                case {'PSVERS', 'LVERS', 'CGTEMP', 'CHKSERIAL', 'STATE', ...
                        'CAPVSET', 'LPW', 'SSHOT', 'USHOT', 'TRIG',...
                        'QSPAR1', 'QSPAR2', 'QSPAR3', 'QDLY', 'QDLYO'}
                    % read again if it was a status line and output is
                    % still available
                    while numel(out) > 5 && strcmp(out(1:5),'OK : ') && obj.sobj.BytesAvailable > 0
                        out = fscanf(obj.sobj);
                        out = out(1:end-1); % remove LF
                    end
                    % check output
                    tmp = strfind(out,[command,' = ']); %#ok<PROPLC>
                    if isempty(tmp) || tmp ~= 1 %#ok<PROPLC>
                        warning(sprintf('%s:Input',mfilename),['Unexpected answer of ''%s'' for command ',...
                            '''%s'':\n''%s''\n. Clearing input from device and returning empty array.'],...
                            obj.sobj.Name,command,out);
                        while obj.sobj.BytesAvailable > 0
                            fscanf(obj.sobj);
                        end
                        out = [];
                    else
                        % clears available bytes and show a warning if available lines are not a status line
                        while obj.sobj.BytesAvailable > 0
                            tmp = fscanf(obj.sobj);%#ok<PROPLC>
                            tmp = tmp(1:end-1); %#ok<PROPLC>
                            if ~strcmp(tmp(1:5),'OK : ') %#ok<PROPLC>
                                warning(sprintf('%s:Input',mfilename),['Unexpected cleared bytes of ''%s'' ',...
                                    'for command ''%s'':\n''%s''\n. Clearing input from device and ',...
                                    'returning empty array.'],obj.sobj.Name,command,tmp); %#ok<PROPLC>
                            end
                        end
                    end
                case {'STOP'}
                    if isempty(out)
                        out = 'ERRROR: Empty read';
                    end
                    obj.lastRun = [];
                case {'RUN'}
                    if isempty(out)
                        out = 'ERRROR: Empty read';
                    end
                    obj.lastRun = tic;
                otherwise
            end
            % issue STATE command again if more than 5s have passed since
            % last time
            if ~isempty(obj.lastRun) && toc(obj.lastRun) > 5
                obj.do('STATE');
            end
            obj.doActive = false;
        end
        
        function keepFLRunning(obj)
            % keepFLRunning Make sure the STATE command is send if it was not
            % done recently (hopefully nothing interferes with this call)
            
            if ~isempty(obj.lastRun) && toc(obj.lastRun) > 7 && ~obj.doActive
                obj.do('STATE');
            end
        end
        
        function loadProfile(obj, profile)
            % loadProfile Load a common profile of settings
            
            if ~ischar(profile)
                error(sprintf('%s:Input',mfilename),'Profile (1st input) must be a char');
            end
            switch profile
                case 'II-01'
                    % Fully internal trigger, every pulse is output,
                    % delayed QS to get low output power (factory settings
                    % for QSmart 850 would be 7 ns for full power)
                    obj.TRIG   = 'II';
                    obj.QSPAR1 = 0;
                    obj.QSPAR2 = 1;
                    obj.QSPAR3 = 1;
                    obj.QDLY   = 180;
                    obj.QDLYO  = 0;
                case 'EE-01'
                    % Fully external trigger, every pulse is output,
                    % delayed QS to get low output power in case TRIG is
                    % set to 'II' (factory settings for QSmart 850 would be
                    % 7ns for full power)
                    obj.TRIG   = 'II';
                    obj.QSPAR1 = 0;
                    obj.QSPAR2 = 1;
                    obj.QSPAR3 = 1;
                    obj.QDLY   = 180;
                    obj.QDLYO  = 0;
                otherwise
                    error(sprintf('%s:Input',mfilename),'Unknown profile ''%s''',profile);
            end
        end
        
        function out = startFL(obj)
            % startFL Starts flashlamp and keeps it going by re-sending STATE command every 6s
            
            state = obj.STATE;
            switch state
                case 2
                    % laser is ready for RUN command
                    out = obj.do('RUN');
                    if isempty(out) || ~strcmp(out(1:2),'OK')
                        warning(sprintf('%s:Input',mfilename),'Run command for flashlamp returned an error');
                    end
                    % create a timer object to circumvent safety shut off
                    if ~isempty(obj.tmp) && isstruct(obj.tmp) && isfield(obj.tmp, 'timerFL')
                        warning(sprintf('%s:Input',mfilename),'Timer object for flash lamp already existing. Failed stop? Cleaning up!');
                        delete(obj.tmp.timerFL);
                    end
                    obj.tmp.timerFL = timer('BusyMode', 'drop',...
                        'ExecutionMode', 'fixedRate',...
                        'Period', 1,...
                        'StartDelay', 1,...
                        'StartFcn', '',...
                        'ErrorFcn', '',...
                        'TimerFcn', @(src,event) obj.keepFLRunning,...
                        'StopFcn','',...
                        'TasksToExecute', Inf);
                    start(obj.tmp.timerFL);
                case {3 4 5 6 7 8 9}
                    warning(sprintf('%s:Input',mfilename),'Laser is in STATE %d and should already be pulsing', state);
                otherwise
                    warning(sprintf('%s:Input',mfilename),'Laser is in STATE %d, starting flashlamp is not possible', state);
            end
        end
        
        function out = stopFL(obj)
            % stopFL Stops flashlamp and removes timer object (see startFL)
            
            state = obj.STATE;
            switch state
                case {0 1 2} 
                    % laser is not running, check timer
                    if ~isempty(obj.tmp) && isstruct(obj.tmp) && isfield(obj.tmp, 'timerFL')
                        stop(obj.tmp.timerFL);
                        delete(obj.tmp.timerFL);
                        obj.tmp = rmfield(obj.tmp,'timerFL');
                    end
                    out         = [];
                    obj.lastRun = [];
                case {3 4 5 6 7 8 9}
                    % already pulsing, send STOP command and remove timer
                    out = obj.do('STOP');
                    if isempty(out) || ~strcmp(out(1:2),'OK')
                        warning(sprintf('%s:Input',mfilename),'Stop command for flashlamp returned an error');
                    end
                    if ~isempty(obj.tmp) && isstruct(obj.tmp) && isfield(obj.tmp, 'timerFL')
                        stop(obj.tmp.timerFL);
                        if ~isempty(obj.tmp) && isstruct(obj.tmp) && isfield(obj.tmp, 'timerFL')
                            delete(obj.tmp.timerFL);
                            obj.tmp = rmfield(obj.tmp,'timerFL');
                        end
                        obj.lastRun = [];
                    end
                otherwise
                    warning(sprintf('%s:Input',mfilename),'Laser is in STATE %d, stopping flashlamp is not possible', state);
                    out = [];
            end
        end
        
        function out = startQS(obj)
            % startQS Opens Q-Switch
            
            state = obj.STATE;
            switch state
                case {0 1 2} 
                    % laser is not running
                    error(sprintf('%s:Input',mfilename),'Laser is not pulsing. Please enable flashlamp first!');
                case {3 4 5 6 7 8 9}
                    % open Q-Switch
                    out = obj.do('QSW 1');
                    if isempty(out) || ~strcmp(out(1:2),'OK')
                        warning(sprintf('%s:Input',mfilename),'Open Q-Switch command returned an error');
                    end
                otherwise
                    warning(sprintf('%s:Input',mfilename),'Laser is in STATE %d, opening Q-Switch is not possible', state);
                    out = [];
            end
        end
        
        function out = stopQS(obj)
            % startQS Closes Q-Switch
            
            state = obj.STATE;
            switch state
                case {0 1 2}
                    % do nothing
                case {3 4 5 6 7 8 9}
                    % close Q-Switch
                    out = obj.do('QSW 0');
                    if isempty(out) || ~strcmp(out(1:2),'OK')
                        warning(sprintf('%s:Input',mfilename),'Close Q-Switch command returned an error');
                    end
                otherwise
                    warning(sprintf('%s:Input',mfilename),'Laser is in STATE %d, opening Q-Switch is not possible', state);
                    out = [];
            end
        end
        
        function out = equalizeHG1(obj)
            % equalizeHG1 Equalize first harmonic generator (crystal) 
            
            % wait until crystal has reached temperature
            tStart  = tic;
            mydelay = 1/obj.PRF;
            myError = NaN(1,10);
            fprintf('Trying to equalize first harmonic generator, set point: Ts = %5.2f?C\n',obj.TEMP1S);
            while any(isnan(myError)) || max(myError) > obj.opt.maxTempError
                setT = obj.TEMP1S;
                tRun = toc(tStart);
                getT = obj.TEMP1F;
                if all(~isnan([setT getT]))
                    myError(end+1) = abs(setT-getT); %#ok<AGROW>
                    myError(1)     = [];
                end
                fprintf('   t= %6.1f s: Ts = %5.2f?C, Tm = %5.2f?C, err = %5.3f?C\n',tRun, setT, getT, abs(setT-getT));
                pause(mydelay);
            end
            % wait minimum time
            fprintf('  temperature within bounds for 10 measurements, starting minimum waiting time of %d s\n',round(obj.opt.TimeWarmupNLO));
            tStart  = tic;
            tRun    = toc(tStart);
            while tRun < obj.opt.TimeWarmupNLO
                setT = obj.TEMP1S;
                tRun = toc(tStart);
                getT = obj.TEMP1F; 
                pause(mydelay);
                fprintf('   t= %6.1f s: Ts = %5.2f?C, Tm = %5.2f?C, err = %5.3f?C\n',tRun, setT, getT, abs(setT-getT));
            end
            fprintf('  first harmonic generator is equalized, set point: Ts = %5.2f?C\n',setT);
            out = true;
        end
        
        function out = reset(obj)
            % reset Reset device
            
            obj.stopQS;
            obj.stopFL;
            fclose(obj.sobj);
            pause(obj.opt.Delay);
            fopen(obj.sobj);
            out = obj.do('CLRALARM');
            obj.loadProfile('II-01');
        end
    end
    
    methods (Access = private, Hidden = false)
        
    end
    
    %% Static Methods
    methods (Static = true, Access = public, Hidden = false, Sealed = true)
        
        function out = mystr2double(in)
            % mystr2double Returns numeric value from strings like 'VALUE = 38.0'
            % Returns NaN in case of an error
            
            [~,remain] = strtok(in,'=');
            out        = str2double(remain(2:end));
        end
    end
end
