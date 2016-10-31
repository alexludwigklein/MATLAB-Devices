classdef QuantelMVAT < handle
    %QuantelMVAT Class describing the serial connection to the motorized variable attenuator by Quantel
    %
    %   The class allows to connect to the attenuator and set its transmission
    %
    %   The object can be saved to disk, but it stores only the settings and not the actual data or
    %   user data. This can be used to quickly store the settings of the object to disk for a later
    %   recovery.
    %
    % Implementation notes:
    %
    %
    %----------------------------------------------------------------------------------
    %   Copyright 2016 Alexander Ludwig Klein, alexludwigklein@gmail.com
    %
    %   Physics of Fluids, University of Twente
    %----------------------------------------------------------------------------------
    
    %% Properties
    properties (GetAccess = public, SetAccess = public, Dependent = true)
        % Device Settings of the serial connection used to communicate with the hardware (structure)
        %
        % This property holds all settings of a serial device that can be changed and are not
        % read-only but constant over time (see MATLAB's documentation). In addition it holds a
        % setting called Delay that determines the delay in s between rapid write or read operations
        % (a dirty but simple fix required for some devices). Properties of the serial device that
        % are time-dependent are given by the property Status. The fields of the structure are:
        %   <all constant properties of a serial device>: see MATLAB's documentation
        %                                          Delay: delay in s between rapid read and write
        %                                                 operations to and from the hardware
        Device
        % System System settings of the QuantelMVAT hardware (structure)
        %
        % This property holds settings of and information on the QuantelMVAT device. The fields of
        % the structure are:
        %              version: string for the version of the software on the QuantelMVAT device (read-only)
        System
        % Transmission Transmission of the attenuator as double value in the range 0 to 1 (double)
        Transmission
        % MaxTransmission Maximum allowed value for the transmission (double)
        MaxTransmission
    end
    
    properties (GetAccess = public, SetAccess = protected, Dependent = true)
        % Status Status of the serial device (structure)
        %
        % This property holds all serial properties that can change over time (see MATLAB's
        % documentation). The fields of the structure are:
        %   <all varying properties of a serial device>: see MATLAB's documentation
        Status
    end
    
    properties (GetAccess = public, SetAccess = public, Transient = true)
        % Name A short name for the device (char)
        Name = 'QuantelMVAT';
        % UserData Userdata linked to the device (arbitrary)
        UserData = [];
    end
    
    properties (GetAccess = protected, SetAccess = protected, Transient = true)
        % sobj Serial device, i.e. the actual connection to the hardware (serial object)
        sobj
        % p_Device Storage for Device
        p_Device
        % p_System Storage for System
        p_System
        % p_System Storage for MaxTransmission
        p_MaxTransmission = 1;
    end
    
    %% Events
    events
        % newSettings Notify when settings are changed
        newSettings
    end
    
    %% Constructor and SET/GET
    methods
        function obj = QuantelMVAT(varargin)
            % QuantelMVAT Creates object that links to the device
            %
            % Options are supposed to be given in <propertyname> <propertyvalue> style
            
            %
            % get input with input parser, where inputs are mostly properties listed in MATLAB's
            % documentation on serial objects that can be changed, i.e. are not always read-only
            tmp               = inputParser;
            tmp.StructExpand  = true;
            tmp.KeepUnmatched = false;
            % communication properties
            tmp.addParameter('BaudRate', 19200, ...
                @(x) ~isempty(x) && isnumeric(x) && isscalar(x) && x > 0);
            tmp.addParameter('DataBits', 8, ...
                @(x) ~isempty(x) && isnumeric(x) && isscalar(x) && x > 0);
            tmp.addParameter('Parity', 'none', ...
                @(x) ~isempty(x) && ischar(x) && ismember(x,{'none','odd','even','mark','space'}));
            tmp.addParameter('StopBits', 1, ...
                @(x) ~isempty(x) && isnumeric(x) && isscalar(x) && ismember(x,[1 1.5 2]));
            tmp.addParameter('Terminator', 'CR', ...
                @(x) ~isempty(x) && (ischar(x) || (iscellstr(x) && isequal(size(x),[1 2]))));
            % write properties
            tmp.addParameter('OutputBufferSize', 512, ...
                @(x) ~isempty(x) && isnumeric(x) && isscalar(x) && x > 0);
            % read properties
            tmp.addParameter('InputBufferSize', 2^20, ...
                @(x) ~isempty(x) && isnumeric(x) && isscalar(x) && x > 0);
            tmp.addParameter('ReadAsyncMode', 'continuous', ...
                @(x) ~isempty(x) && ischar(x) && ismember(x,{'continuous','manual'}));
            tmp.addParameter('Timeout', 10, ...
                @(x) ~isempty(x) && isnumeric(x) && isscalar(x) && x > 0);
            % callback properties
            tmp.addParameter('BreakInterruptFcn', '', ...
                @(x) (ischar(x) && isempty(x)) || isa(x,'function_handle'));
            tmp.addParameter('BytesAvailableFcn', '', ...
                @(x) (ischar(x) && isempty(x)) || isa(x,'function_handle'));
            tmp.addParameter('BytesAvailableFcnCount', 26, ...
                @(x) ~isempty(x) && isnumeric(x) && isscalar(x));
            tmp.addParameter('BytesAvailableFcnMode', 'byte', ...
                @(x) ~isempty(x) && ischar(x) && ismember(x,{'byte','terminator'}));
            tmp.addParameter('ErrorFcn', '', ...
                @(x) (ischar(x) && isempty(x)) || isa(x,'function_handle'));
            tmp.addParameter('OutputEmptyFcn', '', ...
                @(x) (ischar(x) && isempty(x)) || isa(x,'function_handle'));
            tmp.addParameter('PinStatusFcn', '', ...
                @(x) (ischar(x) && isempty(x)) || isa(x,'function_handle'));
            tmp.addParameter('TimerFcn', '', ...
                @(x) (ischar(x) && isempty(x)) || isa(x,'function_handle'));
            tmp.addParameter('TimerPeriod', 1, ...
                @(x) ~isempty(x) && isnumeric(x) && isscalar(x) && x > 0);
            % control pin properties
            tmp.addParameter('DataTerminalReady', 'on', ...
                @(x) ~isempty(x) && ischar(x) && ismember(x,{'on','off'}));
            tmp.addParameter('FlowControl', 'none', ...
                @(x) ~isempty(x) && ischar(x));
            tmp.addParameter('RequestToSend', 'on', ...
                @(x) ~isempty(x) && ischar(x) && ismember(x,{'on','off'}));
            % recording properties
            tmp.addParameter('RecordDetail', 'compact', ...
                @(x) ~isempty(x) && ischar(x) && ismember(x,{'compact','verbose'}));
            tmp.addParameter('RecordMode', 'overwrite', ...
                @(x) ~isempty(x) && ischar(x) && ismember(x,{'overwrite','append','index'}));
            tmp.addParameter('RecordName', 'record.txt', ...
                @(x) ~isempty(x) && ischar(x));
            % general purpose properties
            tmp.addParameter('ByteOrder', 'littleEndian', ...
                @(x) ~isempty(x) && ischar(x) && ismember(x,{'littleEndian','bigEndian'}));
            tmp.addParameter('Port', 'COM0', ...
                @(x) ~isempty(x) && ischar(x));
            tmp.addParameter('Tag', '', ...
                @(x) ischar(x));
            tmp.addParameter('UserData', []);
            % additional settings apart from serial object
            tmp.addParameter('Delay', 0.01, ...
                @(x) ~isempty(x) && isnumeric(x) && isscalar(x) && x >= 0);
            tmp.addParameter('showInfoOnConstruction', true, ...
                @(x) islogical(x) && isscalar(x));
            tmp.parse(varargin{:});
            tmp = tmp.Results;
            showInfoOnConstruction = tmp.showInfoOnConstruction;
            tmp                    = rmfield(tmp,'showInfoOnConstruction');
            %
            % check if hardware is available
            hw = instrhwinfo('serial');
            if ~ismember(tmp.Port,hw.AvailableSerialPorts)
                if ismember(tmp.Port,hw.SerialPorts)
                    error(sprintf('%s:Input',mfilename),['Port ''%s'' is in principle available at ',...
                        'your system, but seems to be in use, see output of instrhwinfo'],tmp.Port);
                else
                    error(sprintf('%s:Input',mfilename),['Port ''%s'' seems not to be available at ',...
                        'all at your system, see output of instrhwinfo'],tmp.Port);
                end
            end
            %
            % construct serial object and open connection
            try
                % create object only specifying the port
                obj.sobj = serial(tmp.Port);
                % set all other settings
                fn = fieldnames(tmp);
                for i = 1:numel(fn)
                    switch fn{i}
                        case {'Port','Delay'}
                        otherwise
                            obj.sobj.(fn{i}) = tmp.(fn{i});
                    end
                end
                % open device
                fopen(obj.sobj);
            catch exception
                error(sprintf('%s:Input',mfilename),'Could not open device: %s',exception.getReport);
            end
            %
            % store device property names and delay
            obj.p_Device.Delay              = tmp.Delay;
            obj.p_Device.myDeviceProperties = setdiff(fieldnames(tmp),{'Delay'});
            % check if device is really open
            if obj.p_Device.Delay > 0, pause(obj.p_Device.Delay); end
            if ~isequal(obj.sobj.Status,'open')
                error(sprintf('%s:Input',mfilename),'Could not open device');
            end
            %
            % initialize system property
            obj.p_System = readSystem(obj);
            %
            % show information
            if showInfoOnConstruction
                showInfo(obj);
            end
        end
        
        function out = get.Device(obj)
            
            % add properties listed in myDeviceProperties
            for i = 1:numel(obj.p_Device.myDeviceProperties)
                out.(obj.p_Device.myDeviceProperties{i}) = obj.sobj.(obj.p_Device.myDeviceProperties{i});
            end
            %  add remaining properties stored in p_Device
            fn = fieldnames(obj.p_Device);
            fn = setdiff(fn,{'myDeviceProperties'});
            for i = 1:numel(fn)
                out.(fn{i}) = obj.p_Device.(fn{i});
            end
            out = orderfields(out);
        end
        
        function       set.Device(obj,value)
            
            % check if input is given as a structure, but only allow for changing specific settings
            if ~(isstruct(value) && isscalar(value) && all(ismember(fieldnames(value),fieldnames(obj.Device))))
                error(sprintf('%s:Input',mfilename),...
                    'Expected a scalar structure with device settings as input, please check input!');
            else
                curValue = obj.Device;
                fn       = fieldnames(value);
                anynew   = false;
                for i = 1:numel(fn)
                    tmp    = value.(fn{i});
                    if ~isequal(tmp,curValue.(fn{i})) % only process if it changed
                        anynew = true;
                        switch fn{i}
                            case 'Delay'
                                if isnumeric(tmp) && isscalar(tmp) && tmp >= 0
                                    obj.p_Device.Delay = tmp;
                                else
                                    error(sprintf('%s:Input',mfilename),...
                                        '%s is expected to be a scalar numeric value larger zero, please check input!',fn{i});
                                end
                            case 'BytesAvailableFcnCount'
                                if isnumeric(tmp) && isscalar(tmp) && tmp > 0
                                    fclose(obj.sobj);
                                    obj.sobj.(fn{i}) = tmp;
                                    fopen(obj.sobj);
                                else
                                    error(sprintf('%s:Input',mfilename),...
                                        '%s is expected to be a scalar numeric value larger zero, please check input!',fn{i});
                                end
                            case 'BytesAvailableFcnMode'
                                if ischar(tmp) && ismember(tmp,{'terminator','byte'})
                                    fclose(obj.sobj);
                                    obj.sobj.(fn{i}) = tmp;
                                    fopen(obj.sobj);
                                else
                                    error(sprintf('%s:Input',mfilename),...
                                        '%s is expected to be a certain char, please check input!',fn{i});
                                end
                            otherwise
                                error(sprintf('%s:Input',mfilename),...
                                    'Unknown or unchangeable serial setting ''%s'' for device of class ''%s''',fn{i},class(obj));
                        end
                    end
                end
                if anynew, notify(obj,'newSettings'); end
            end
        end
        
        function out = get.System(obj)
            
            out = obj.p_System;
        end
        
        function       set.System(obj,value)
            
            % check if input is given as a structure, but only allow for changing specific settings
            if ~(isstruct(value) && isscalar(value) && all(ismember(fieldnames(value),fieldnames(obj.System))))
                error(sprintf('%s:Input',mfilename),...
                    'Expected a scalar structure with system settings as input, please check input!');
            else
                curValue = obj.System;
                fn       = fieldnames(value);
                anynew   = false;
                for i = 1:numel(fn)
                    tmp    = value.(fn{i});
                    if ~isequal(tmp,curValue.(fn{i})) % only process if it changed
                        anynew = true; %#ok<NASGU>
                        switch fn{i}
                            otherwise
                                error(sprintf('%s:Input',mfilename),...
                                    'Unknown or unchangeable system setting ''%s'' for device of class ''%s''',fn{i},class(obj));
                        end
                    end
                end
                if anynew, notify(obj,'newSettings'); end %#ok<UNRCH>
            end
        end
        
        function out = get.Status(obj)
            
            % return all properties of the serial device that can change over time
            out.BytesToOutput  = obj.sobj.BytesToOutput;
            out.TransferStatus = obj.sobj.TransferStatus;
            out.ValuesSent     = obj.sobj.ValuesSent;
            out.BytesAvailable = obj.sobj.BytesAvailable;
            out.ValuesReceived = obj.sobj.ValuesReceived;
            out.RecordStatus   = obj.sobj.RecordStatus;
            out.Status         = obj.sobj.Status;
            out.PinStatus      = obj.sobj.PinStatus;
            out                = orderfields(out);
        end
        
        function       set.Name(obj,value)
            
            if ischar(value)
                obj.Name = value;
            else
                error(sprintf('%s:Input',mfilename),...
                    'Name is expected to be a char, please check input!');
            end
        end
        
        function out = get.Transmission(obj)
            out = str2double(mydo(obj,'TF?',1))/100;
        end
        
        function       set.Transmission(obj,value)
            if isfloat(value) && isscalar(value) && value >= 0 && value <= 1
                if value > obj.MaxTransmission
                    error(sprintf('%s:Input',mfilename),...
                        'Input for transmission exceeded maximum allowed value of %0.2f, please check!',...
                        obj.MaxTransmission);
                else
                    tmp = mydo(obj,sprintf('TF %0.2f',value*100),1);
                    if ~strcmpi(tmp,'ok')
                        error(sprintf('%s:Input',mfilename),...
                            'Setting transmission return unknown response: ''%s'' for device %s, please check',...
                            tmp,obj.Name);
                    end
                end
            else
                error(sprintf('%s:Input',mfilename),...
                    'Transmission is expected to be a float between 0 and 1, please check input!');
            end
        end
        
        function out = get.MaxTransmission(obj)
            out = obj.p_MaxTransmission;
        end
        
        function       set.MaxTransmission(obj,value)
            if isfloat(value) && isscalar(value) && value >= 0 && value <= 1
                obj.p_MaxTransmission = value;
                if obj.Transmission > obj.p_MaxTransmission
                    obj.Transmission = obj.p_MaxTransmission;
                end
            else
                error(sprintf('%s:Input',mfilename),...
                    'Maximum transmission is expected to be a float between 0 and 1, please check input!');
            end
        end
    end
    
    %% Methods
    methods (Access = public, Hidden = false)
        function                  disp(obj)
            % disp Displays object on command line
            
            %
            % use buildin disp to show properties in long format, otherwise just a short info
            spacing     = '     ';
            if ~isempty(obj) && ismember(get(0,'Format'),{'short','shortE','shortG','shortEng'}) && isvalid(obj)
                fprintf(['%s%s object, use class method ''showInfo'' to get the same\n%sinformation, ',...
                    'change command window to long output format,\n%si.e. ''format long'' or ',...
                    'use ''properties'' and ''doc'' to get\n%sa list of the object properties'],...
                    spacing,class(obj),spacing,spacing,spacing);
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
        
        function                  delete(obj)
            % delete Delete object and make sure serial connection is closed
            
            if isequal(obj.sobj.Status,'open')
                fclose(obj.sobj);
            end
            delete(obj.sobj);
        end
        
        function S              = saveobj(obj)
            % saveobj Supposed to be called by MATLAB's save function, stores settings of serial
            % connection and transmission to allow for a recovery during the load processs
            
            S.Device          = obj.Device;
            S.Transmission    = obj.Transmission;
            S.MaxTransmission = obj.MaxTransmission;
            S.System          = rmfield(obj.System,{'version'});
            S.Name            = obj.Name;
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
        
        function varargout      = syncSystem(obj)
            % syncSystem Checks if system settings (in class property System) match the status of
            % the hardware, which is returned as second ouput, the first output is true/false
            % whether the object was in sync, makes sure the class property is in sync
            
            isOK = true;
            stat = readSystem(obj);
            fn   = fieldnames(stat);
            for k = 1:numel(fn)
                if ~isequal(obj.p_System.(fn{k}),stat.(fn{k}))
                    warning(sprintf('%s:Check',mfilename),...
                        'Mismatch in setting ''%s'' for system, correcting class property accordingly',fn{k});
                    obj.p_System.(fn{k}) = stat.(fn{k});
                    isOK                 = false;
                end
            end
            if nargout > 0, varargout = {isOK, stat}; end
        end
        
        function                  home(obj)
            % home Moves device to home positition, i.e. transmission to 0
            
            obj.Transmission = 0;
        end
        
        function                  stop(obj)
            % stop Sets transmission to 0
            
            obj.Transmission = 0;
        end
        
        function varargout      = sync(obj)
            % sync Sync all properties that can be synced
            
            isOK = syncSystem(obj);
            if nargout > 0, varargout = {all(isOK)}; end
        end
        
        function varargout      = showInfo(obj,noPrint,noUpdate)
            % showInfo Shows information on device on command line and returns cellstr with info,
            % output to command line can be supressed by the noPrint input, the last input controls
            % whether the MATLAB object is synced before info is shown (default)
            
            if nargin < 2, noPrint = false; end
            if nargin < 3 || isempty(noPrint), noUpdate = false; end
            if ~(islogical(noPrint) && isscalar(noPrint))
                error(sprintf('%s:Input',mfilename),...
                    'Optional second input is expected to be a scalar logical, please check input!');
            elseif ~(islogical(noUpdate) && isscalar(noUpdate))
                error(sprintf('%s:Input',mfilename),...
                    'Optional third input is expected to be a scalar logical, please check input!');
            end
            %
            % check system and axis
            if ~noUpdate
                syncSystem(obj);
            end
            %
            % built information strings
            out        = cell(1);
            sep        = '  ';
            out{end+1} = sprintf('%s (%s) connected at ''%s''',obj.Name,obj.System.version,obj.sobj.Name);
            sep2       = repmat('-',1,numel(out{end}));
            out{end+1} = sep2;
            out{1}     = sep2;
            out{end} = out{1};
            out{end}(round([1:(end/3) (2*end/3):end])) = ' '; out{end}(end) = ' ';
            out{end+1} = sprintf('%sTransmission is %0.2f',sep,obj.Transmission);
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
        
        function out            = mydo(obj,cmd,len)
            % mydo Sends char command cmd to serial device and expects len number of output lines in
            % char representation, returns a cellstr if len is greater than 1, otherwise a char
            
            if nargin < 3, len = 0; end
            out = '';
            fprintf(obj.sobj,[';AT:' cmd]);
            if len > 0
                out = cell(len,1);
                for i = 1:len
                    nBytes = mywait(obj,2);
                    if nBytes < 1
                        warning(sprintf('%s:Reset',mfilename),['No data available from device ''%s'' ',...
                            'although an appropriate command ''%s'' was send, returning empty char'],obj.Name,cmd);
                        out{i} = '';
                    else
                        out{i} = fgetl(obj.sobj);
                    end
                end
                if len == 1, out = out{1}; end
            end
            [isData, data] = flushData(obj);
            if isData, warning(sprintf('%s:Reset',mfilename),['Bytes available for device ''%s'', ',...
                    'which is not expected. Cleared bytes: %s'],obj.Name,num2str(data));
            end
        end
    end
    
    methods (Access = private, Hidden = false)
        function out = readSystem(obj)
            % readSystem Reads all supported system settings from hardware and returns settings structure
            
            out.version = mydo(obj,'VN',1);
            out         = orderfields(out);
        end
        
        function out = mywait(obj,minbytes,maxwait)
            % mywait Waits for serial device until minbytes bytes are available to be read and
            % number of bytes does not increase any more or maxwait is reached, returns number of
            % bytes that are finally available
            
            if nargin < 2, minbytes = 1; end
            if nargin < 3, maxwait = 5; end
            delay     = max(0.01,obj.p_Device.Delay);
            counter   = 1;
            lastBytes = obj.sobj.BytesAvailable;
            while (obj.sobj.BytesAvailable < minbytes || lastBytes ~= obj.sobj.BytesAvailable) && ...
                    counter < maxwait/delay
                lastBytes = obj.sobj.BytesAvailable;
                counter   = counter + 1;
                pause(delay);
            end
            out = obj.sobj.BytesAvailable;
        end
    end
    
    %% Static Methods
    methods (Static = true, Access = public, Hidden = false, Sealed = true)
        function obj = loadobj(S)
            %loadobj Loads object and tries to re-connect to hardware
            
            try
                % try to connect
                for n = 1:numel(S)
                    S(n).Device.showInfoOnConstruction = false;
                    % create object
                    obj(n) = QuantelMVAT(S(n).Device); %#ok<AGROW>
                    % copy name
                    obj(n).Name = S(n).Name; %#ok<AGROW>
                    % set transmission
                    obj(n).Transmission    = S(n).Transmission; %#ok<AGROW>
                    obj(n).MaxTransmission = S(n).MaxTransmission; %#ok<AGROW>
                    showInfo(obj(n));
                end
            catch err
                warning(sprintf('%s:Input',mfilename),...
                    'Device could not be re-connected during load process: %s',err.getReport);
            end
        end
    end
end
