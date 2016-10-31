classdef KeysightWG < handle
    %KeysightWG Class describing the visa connection to the waveform generator 33600A by Keysight,
    % but in principle it should work for many other similar Keysight devices.
    %
    % The class allows to connect to the device via VISA and perform very basic operations, such as
    % loading a profile that is stored on the device and disable/enable the output of the channels.
    %
    %   The object can be saved to disk, but it stores only the settings and not the actual data or
    %   user data. This can be used to quickly store the settings of the object to disk for a later
    %   recovery.
    %
    % Implementation notes:
    %   * The visa object can be accessed via obj.sobj to send commands directly to the device
    %
    %----------------------------------------------------------------------------------
    %   Copyright 2016 Alexander Ludwig Klein, alexludwigklein@gmail.com
    %
    %   Physics of Fluids, University of Twente
    %----------------------------------------------------------------------------------
    
    %% Properties
    properties (GetAccess = public, SetAccess = protected, Transient = true)
        % sobj Visa device, i.e. the actual connection to the hardware (visa object)
        sobj
    end
    
    properties (GetAccess = public, SetAccess = public, Transient = true)
        % Name A short name for the device (char)
        Name = 'KeysightWG';
        % UserData Userdata linked to the device (arbitrary)
        UserData = [];
    end
    
    properties (GetAccess = protected, SetAccess = protected, Transient = true)
        % Recover Settings needed when the object is loaded from disk
        Recover
    end
    
    %% Constructor and SET/GET
    methods
        function obj = KeysightWG(varargin)
            % KeysightWG Creates object that links to the device
            %
            % Options are supposed to be given for MATLAB's visa command
            
            %
            % construct visa object and open connection
            try
                % create object only specifying the port
                obj.sobj = visa(varargin{:});
                % open device
                fopen(obj.sobj);
                % save input for recover
                obj.Recover = varargin;
            catch exception
                error(sprintf('%s:Input',mfilename),'Could not open device: %s',exception.getReport);
            end
            showInfo(obj);
        end
        
        function       set.Name(obj,value)
            
            if ischar(value)
                obj.Name = value;
            else
                error(sprintf('%s:Input',mfilename),...
                    'Name is expected to be a char, please check input!');
            end
        end
    end
    
    %% Methods
    methods (Access = public, Hidden = false)
        function             disp(obj)
            % disp Displays object on command line
            
            %
            % use buildin disp to show properties in long format, otherwise just a short info
            spacing     = '     ';
            if ~isempty(obj) && ismember(get(0,'Format'),{'short','shortE','shortG','shortEng'}) && isvalid(obj)
                fprintf(['%s%s object, use class method ''showInfo'' to get the same information, ',...
                    'change command window to long\n%soutput format, i.e. ''format long'' or ',...
                    'use ''properties'' and ''doc'' to get a list of the object properties'],...
                    spacing,class(obj),spacing)
                fprintf('\n');
                str = obj.showInfo(true);
                fprintf([spacing '%s\n'],str{:});
                if ~isequal(get(0,'FormatSpacing'),'compact')
                    disp(' ');
                end
            else
                builtin('disp',obj);
            end
        end
        
        function             delete(obj)
            % delete Delete object and make sure serial connection is closed
            
            if isequal(obj.sobj.Status,'open')
                fclose(obj.sobj);
            end
        end
        
        function S         = saveobj(obj)
            % saveobj Supposed to be called by MATLAB's save function, stores settings for visa
            % connection and position to allow for a recovery during the load processs
            
            S.Name    = obj.Name;
            S.Recover = obj.Recover;
        end
        
        
        function             store(obj,idx)
            % store Stores current settings at given memory block
            
            if nargin < 2, idx = 1; end
            if ~(isnumeric(idx) && isscalar(idx) && idx >= 0 && idx <= 4)
                error(sprintf('%s:Input',mfilename),...
                    'Index is expected to be a scalar numeric value between 0 and 4, please check input!');
            end
            idx = round(idx);
            mydo(obj,sprintf('*SAV %d',idx'));
        end
        
        function             recall(obj,idx)
            % recall Recalls given memory block
            
            if nargin < 2, idx = 1; end
            if ~(isnumeric(idx) && isscalar(idx) && idx >= 0 && idx <= 4)
                error(sprintf('%s:Input',mfilename),...
                    'Index is expected to be a scalar numeric value between 0 and 4, please check input!');
            end
            idx = round(idx);
            mydo(obj,sprintf('*RCL %d',idx'));
        end
        
        function             wait(obj)
            % wait Waits until object has completed the current operation
            
            status = mydo(obj,'*OPC?',false); %#ok<NASGU>
        end
        
        function             abort(obj)
            % abort Halts a sequence, list, sweep, or burst, even an infinite burst. Also causes
            % trigger subsystem to return to idle state
            
            mydo(obj,'ABOR');
        end
        
        function             clear(obj)
            % clear Clears the event registers in all register groups. Also clears the error queue
            
            mydo(obj,'*CLS');
        end
        
        function             stop(obj)
            % stop Wrapper for abort + off function
            
            abort(obj);
            off(obj);
        end
        
        function             off(obj)
            % off Turns channel 1, 2 and SYNC off
            
            mydo(obj,'OUTP1 0');
            mydo(obj,'OUTP2 0');
            mydo(obj,'OUTP:SYNC 0');
        end
        
        function             start(obj)
            % start Wrapper for on function
            
            on(obj);
        end
        
        function             on(obj)
            % on Turns channel 1, 2 and SYNC on
            
            mydo(obj,'OUTP1 1');
            mydo(obj,'OUTP2 1');
            mydo(obj,'OUTP:SYNC 1');
        end
        
        function             beep(obj,nBeep,delay)
            % beep Generates one or multiple a beeps on the device separated by given delay in s
            
            narginchk(1,3)
            if nargin < 2 || isempty(nBeep), nBeep = 1; end
            if nargin < 3 || isempty(delay), delay = 0.5; end
            nBeep = round(nBeep);
            assert(isnumeric(nBeep) && isscalar(nBeep) && nBeep >= 0,...
                'input for number of beeps is unexpected');
            assert(isnumeric(delay) && isscalar(delay) && delay > 0,...
                'input for number of beeps is unexpected');
            if nBeep == 1
                mydo(obj,'SYST:BEEP:IMM');
            else
                for i = 1:round(nBeep)
                    mydo(obj,'SYST:BEEP:IMM');
                    if i < nBeep
                        pause(delay);
                    end
                end
            end
            
        end
        
        function             setTrigger(obj,setting,value,idx)
            % setTrigger Sets given trigger setting to a given value and a given channel (optional,
            % channel 1 by default)
            
            narginchk(3,4);
            if nargin < 4; idx = 1; end
            if ~(isnumeric(idx) && isscalar(idx) && ismember(idx,[1 2]))
                error(sprintf('%s:Input',mfilename),'Channel index (4th input) must be 1 or 2');
            end
            if ischar(setting)
                switch setting
                    case 'delay'
                        if isnumeric(value) && isscalar(value) &&  value >= 0
                            mydo(obj,sprintf('TRIG%d:DEL %e',idx,value));
                        else
                            error(sprintf('%s:Input',mfilename),...
                                'Value (3rd input) is not allowed for command ''%s''',setting);
                        end
                    case 'level'
                        if isnumeric(value) && isscalar(value) && value >= 0.9 && value  <= 3.8
                            mydo(obj,sprintf('TRIG%d:LEV %e',idx,value));
                        else
                            error(sprintf('%s:Input',mfilename),...
                                'Value (3nd input) is not allowed for command ''%s''',setting);
                        end
                    case 'source'
                        if ischar(value) && ismember(value,{'EXT' 'BUS'})
                            mydo(obj,sprintf('TRIG%d:SOUR %s',idx,value));
                        else
                            error(sprintf('%s:Input',mfilename),...
                                'Value (3nd input) is not allowed for command ''%s''',setting);
                        end
                    otherwise
                        error(sprintf('%s:Input',mfilename),...
                            'Command (2nd input) is expected to be a known char, please check!');
                end
            else
                error(sprintf('%s:Input',mfilename),...
                    'Command (2nd input) is expected to be a known char, please check!');
            end
        end
        
        function varargout = getTrigger(obj,setting,idx)
            % getTrigger Gets given trigger setting from a given channel (optional, channel 1 by
            % default)
            
            narginchk(2,3);
            nargoutchk(0,1);
            if nargin < 3; idx = 1; end
            if ~(isnumeric(idx) && isscalar(idx) && ismember(idx,[1 2]))
                error(sprintf('%s:Input',mfilename),'Channel index (4th input) must be 1 or 2');
            end
            if ischar(setting)
                switch setting
                    case 'delay'
                        tmp = mydo(obj,sprintf('TRIG%d:DEL?',idx),false);
                        tmp = str2double(tmp);
                    case 'level'
                        tmp = mydo(obj,sprintf('TRIG%d:LEV?',idx),false);
                        tmp = str2double(tmp);
                    case 'source'
                        tmp = mydo(obj,sprintf('TRIG%d:SOUR?',idx),false);
                    otherwise
                        error(sprintf('%s:Input',mfilename),...
                            'Command (2nd input) is expected to be a known char, please check!');
                end
                varargout = {tmp};
            else
                error(sprintf('%s:Input',mfilename),...
                    'Command (2nd input) is expected to be a known char, please check!');
            end
        end
        
        function varargout = getError(obj)
            % getError Gets and clears one error from error queue
            
            narginchk(1,1);
            nargoutchk(0,1);
            tmp = mydo(obj,'SYST:ERR?',false);
            varargout = {tmp};
        end        
        
        function             setSync(obj,setting,value)
            % setSync Configures the sync output
            
            if ischar(setting)
                switch setting
                    case 'source'
                        if isnumeric(value) && isscalar(value) && value >= 1 &&  value <= 2
                            mydo(obj,sprintf('OUTP:SYNC:SOUR CH%d',round(value)));
                        else
                            error(sprintf('%s:Input',mfilename),...
                                'Value (3rd input) is not allowed for command ''%s''',setting);
                        end
                    case 'enable'
                        if (islogical(value) && isscalar(value)) || ...
                                (ischar(value) && ismember(lower(value),{'on' 'off'}))
                            if (islogical(value) && value) || strcmpi(value,'on')
                                mydo(obj,'OUTP:SYNC ON');
                            else
                                mydo(obj,'OUTP:SYNC OFF');
                            end
                        else
                            error(sprintf('%s:Input',mfilename),...
                                'Value (3nd input) is not allowed for command ''%s''',setting);
                        end
                    otherwise
                        error(sprintf('%s:Input',mfilename),...
                            'Command (2nd input) is expected to be a known char, please check!');
                end
            else
                error(sprintf('%s:Input',mfilename),...
                    'Command (2nd input) is expected to be a known char, please check!');
            end
        end
        
        function             trig(obj)
            % trig Sends trigger command, only works if channel is set to manual/BUS source
            
            % option 1: generates an error on the device if wrong trigger source selected
            mydo(obj,'*TRG');
            % option 2: trigger each channel manually
            % mydo(obj,'TRIG1');
            % mydo(obj,'TRIG2');
        end
        
        function varargout = showInfo(obj,noPrint)
            
            if nargin < 2, noPrint = false; end
            if ~(islogical(noPrint) && isscalar(noPrint))
                error(sprintf('%s:Input',mfilename),...
                    'Optional second input is expected to be a scalar logical, please check input!');
            end
            %
            % built information strings
            out        = cell(1);
            sep        = '  ';
            tmp        = query(obj.sobj,'*IDN?');
            out{end+1} = sprintf('%s (%s) connected at ''%s''',obj.Name,tmp(1:end-1),obj.sobj.Name);
            sep2       = repmat('-',1,numel(out{end}));
            out{end+1} = sep2;
            out{1}     = sep2;
            out{end+1} = sprintf('%s%s This is a basic class to control the device',sep,sep);
            out{end+1} = out{1};
            %
            % output to command line and as argument
            if ~noPrint
                for i = 1:numel(out)
                    fprintf('%s\n',out{i});
                end
            end
            if nargout > 0, varargout = {out}; end
        end
    end
    
    methods (Access = private, Hidden = false)
        function out = mydo(obj,cmd,noOutput)
            % mydo Sends char command cmd to visa device and expects no answer from the device
            % unless noOutput is false
            
            if nargin < 3, noOutput = true; end
            if noOutput
                fprintf(obj.sobj,cmd);
                % check if input buffer is empty
                [isData, data] = flushData(obj);
                if isData, warning(sprintf('%s:Run',mfilename),['Bytes available for device ''%s'', ',...
                        'which is not expected. Cleared bytes: %s'],obj.Name,num2str(data));
                end
            else
                out = query(obj.sobj,cmd);
            end
        end
        
        function [out, data]    = flushData(obj)
            % flushData Remove all data in input buffer of serial device, return true if any data
            % was actually flushed from the input buffer, return flushed data as well
            
            out  = false;
            data = [];
            while obj.sobj.BytesAvailable > 0
                tmp  = fread(obj.sobj,obj.sobj.BytesAvailable);
                data = cat(2,data,reshape(tmp,1,[]));
                out  = true;
            end
        end
    end
    
    %% Static Methods
    methods (Static = true, Access = public, Hidden = false, Sealed = true)
        function obj = loadobj(S)
            %loadobj Loads object and tries to re-connect to hardware
            
            try
                % try to connect and set name
                for n = 1:numel(S)
                    obj(n)      = KeysightWG(S(n).Recover{:}); %#ok<AGROW>
                    obj(n).Name = S(n).Name; %#ok<AGROW>
                end
            catch err
                warning(sprintf('%s:Input',mfilename),...
                    'Device could not be re-connected during load process: %s',err.getReport);
            end
        end
    end
end
