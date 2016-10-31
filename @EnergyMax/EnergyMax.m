classdef EnergyMax < handle
    %EnergyMax Class describing the serial connection to the energy meter EnergyMax by coherent
    %
    %   The class allows to connect to the energy meter EnergyMax by coherent connected to a serial
    %   port and acquire data from the energy meter. So far, it only supports the energy mode
    %   without built-in statistics. The gain compensation is disabled as well. Triggering via a bus
    %   is not yet supported, too.
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
        % System System settings of the EnergyMax hardware (structure)
        %
        % This property holds settings of and information on the EnergyMax device. The fields of the
        % structure are:
        %   version: the version of the software on the EnergyMax device (read-only)
        %   logging: true/false whether the input buffer is streamed to the Data property
        System
        % Channel Channel of the EnergyMax device (structure)
        %
        % This property is a structure with information and settings for the single channel of the
        % EnergyMax device. The fields of the structure array are:
        %       calibration: this can be used to transform the data read from the energy meter in
        %                    order to consider a calibration curve. The input should be a function
        %                    handle that accepts one numeric input (scalar or vector). Default is an
        %                    empty string, which means no calibration curve is used.
        %          diameter: double scalar for the diameter of the sensor in m
        %              name: char for the name of the detector (read-only)
        %             scale: char 'max' or 'min for the scale of the channel
        %          scaleMax: double scalar for the upper value of the range (read-only)
        %          scaleMin: double scalar for the lower value of the range (read-only)
        %      serialnumber: char for the serial number of the detector (read-only)
        %           running: true/false whether the channel is sending data to input buffer
        %      triggerDelay: double scalar for the delay in s (between 0 and 1000e-6)
        %   triggerExternal: true/false whether the external trigger is used
        %      triggerLevel: scalar double for the relative trigger level (between 0 and 0.3)
        %      triggerSlope: char 'pos' or 'neg' for the edge slop of the trigger
        %        wavelength: scalar double for the wavelength in nm
        Channel
        % Logging a shortcut for obj.System.logging, i.e. data is written to the Data property
        Logging
        % Running True/false whether the channel is running, i.e. waits for trigger and reads data
        % to its input buffer
        Running
        % Data Data read from each channel (structure)
        %
        % This property is a structure array and holds the actual data acquired by each channel. The
        % fields of the structure array are:
        %   energy: double for energy in J (a calibration may change the unit)
        %       id: uint64 for a sequence ID as returned by the energy meter
        %     flag: uint8 for a qualification: 0 means no qualification, 1 means peak clip error, 2
        %           means baseline clip error and 3 means missed pulse
        %   period: double for period in s
        %     time: datetime for time based on the period returned by enegy meter plus reference
        %           time to get absolute time of measurement (estimate)
        Data
    end
    
    properties (GetAccess = public, SetAccess = protected, Dependent = true)
        % Status Status of the serial device (structure)
        %
        % This property holds all serial properties that can change over time (see MATLAB's
        % documentation). The fields of the structure are:
        %   <all varying properties of a serial device>: see MATLAB's documentation
        Status
        % Memory Memory usage in MiB of stored data (double)
        Memory
    end
    
    properties (GetAccess = public, SetAccess = public, Transient = true)
        % Name A short name for the device (char)
        Name = 'EnergyMax';
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
        % p_Channel Storage for Channel
        p_Channel
        % p_Data Storage for Data
        p_Data
    end
    
    %% Events
    events
        % newData Notify when new data is added to the Data property
        newData
        % newSettings Notify when settings are changed
        newSettings
    end
    
    %% Constructor and SET/GET
    methods
        function obj = EnergyMax(varargin)
            % EnergyMax Creates object that links to the device
            %
            % Options are supposed to be given in <propertyname> <propertyvalue> style
            
            %
            % get input with input parser, where inputs are mostly properties listed in MATLAB's
            % documentation on serial objects that can be changed, i.e. are not always read-only
            tmp               = inputParser;
            tmp.StructExpand  = true;
            tmp.KeepUnmatched = false;
            % communication properties
            tmp.addParameter('BaudRate', 921600, ...
                @(x) ~isempty(x) && isnumeric(x) && isscalar(x) && x > 0);
            tmp.addParameter('DataBits', 8, ...
                @(x) ~isempty(x) && isnumeric(x) && isscalar(x) && x > 0);
            tmp.addParameter('Parity', 'none', ...
                @(x) ~isempty(x) && ischar(x) && ismember(x,{'none','odd','even','mark','space'}));
            tmp.addParameter('StopBits', 1, ...
                @(x) ~isempty(x) && isnumeric(x) && isscalar(x) && ismember(x,[1 1.5 2]));
            tmp.addParameter('Terminator', 'CR/LF', ...
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
            tmp.addParameter('BytesAvailableFcnCount', 48, ...
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
                    error(sprintf('%s:Input',mfilename),...
                        'Port ''%s'' is in principle available at your system, but seems to be in use, see output of instrhwinfo',tmp.Port);
                else
                    error(sprintf('%s:Input',mfilename),...
                        'Port ''%s'' seems not to be available at all at your system, see output of instrhwinfo',tmp.Port);
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
            % reset device, initialize remaining properties and show info
            reset(obj);
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
            
            obj.p_System.logging = ~isempty(obj.sobj.BytesAvailableFcn);
            out                  = obj.p_System;
        end
        
        function       set.System(obj,value)
            curValue = obj.System;
            % check if input is given as a structure, but only allow for changing specific settings
            if ~(isstruct(value) && isscalar(value) && all(ismember(fieldnames(value),fieldnames(curValue))))
                error(sprintf('%s:Input',mfilename),...
                    'Expected a scalar structure with system settings as input, please check input!');
            else
                fn       = fieldnames(value);
                anynew   = false;
                for i = 1:numel(fn)
                    tmp    = value.(fn{i});
                    if ~isequal(tmp,curValue.(fn{i})) % only process if it changed
                        anynew = true;
                        switch fn{i}
                            case 'logging'
                                if ~obj.p_Channel.running
                                    error(sprintf('%s:Input',mfilename),...
                                        'The channel is not running, please enable it first');
                                end
                                % communicate to hardware
                                if tmp
                                    obj.sobj.BytesAvailableFcn = @(src,event) readData(obj);
                                    obj.p_System.logging       = true;
                                else
                                    obj.sobj.BytesAvailableFcn = '';
                                    obj.p_System.logging       = false;
                                    readData(obj);
                                end
                            otherwise
                                error(sprintf('%s:Input',mfilename),...
                                    'Unknown or unchangeable system setting ''%s'' for device of class ''%s''',fn{i},class(obj));
                        end
                    end
                end
                if anynew, notify(obj,'newSettings'); end
            end
        end
        
        function out = get.Channel(obj)
            
            out = obj.p_Channel;
        end
        
        function       set.Channel(obj,value)
            
            % check if input is given as a structure, but only allow for changing specific settings
            if ~(isstruct(value) && numel(value) == 1 && all(ismember(fieldnames(value),fieldnames(obj.Channel))))
                error(sprintf('%s:Input',mfilename),...
                    'Expected a scalar structure with channel settings as input, please check input!');
            else
                if obj.System.logging
                    error(sprintf('%s:Input',mfilename),'System is logging input buffer to Data property. Please stop it first!');
                end
                fn     = fieldnames(value);
                anynew = false;
                for i = 1:numel(fn)                        % loop over settings
                    tmp = value.(fn{i});                   % get value of current setting
                    if ~isequal(tmp,obj.p_Channel.(fn{i})) % only process if it changed
                        if obj.p_Channel.running && ~strcmp(fn{i},'running')
                            error(sprintf('%s:Input',mfilename),'Channel is running. Please stop it first!');
                        end
                        anynew = true;
                        switch fn{i}
                            case 'wavelength'
                                if isnumeric(tmp) && isscalar(tmp) && tmp >= 0
                                    % prepare value
                                    tmp = round(tmp);
                                    % communicate to hardware
                                    mydo(obj,sprintf('CONF:WAVE %d',tmp));
                                    % store value
                                    obj.p_Channel.(fn{i}) = tmp;
                                else
                                    error(sprintf('%s:Input',mfilename),...
                                        '%s is expected to be a scalar numeric value larger zero, please check input!',fn{i});
                                end
                            case 'diameter'
                                if isnumeric(tmp) && isscalar(tmp) && tmp > 0 && tmp < 0.5
                                    % communicate to hardware
                                    str = sprintf('%.2e',tmp*1e3);
                                    mydo(obj,sprintf('CONF:DIAM %s',str));
                                    % store value
                                    obj.p_Channel.(fn{i}) = str2double(str)*1e-3;
                                else
                                    error(sprintf('%s:Input',mfilename),...
                                        '%s is expected to be a scalar numeric value between 0 and 0.5, please check input!',fn{i});
                                end
                            case 'triggerLevel'
                                if isnumeric(tmp) && isscalar(tmp) && tmp > 0 && tmp < 0.3
                                    % communicate to hardware
                                    str = sprintf('%.2e',tmp*1e2);
                                    mydo(obj,sprintf('TRIG:LEV %s',str));
                                    % store value
                                    obj.p_Channel.(fn{i}) = str2double(str)*1e-2;
                                else
                                    error(sprintf('%s:Input',mfilename),...
                                        '%s is expected to be a scalar numeric value between 0 and 0.3, please check input!',fn{i});
                                end
                            case 'triggerExternal'
                                if islogical(tmp) && isscalar(tmp)
                                    % communicate to hardware
                                    if tmp
                                        mydo(obj,'TRIG:SOUR EXT');
                                    else
                                        mydo(obj,'TRIG:SOUR INT');
                                    end
                                    % store value
                                    obj.p_Channel.(fn{i}) = tmp;
                                else
                                    error(sprintf('%s:Input',mfilename),...
                                        '%s is expected to be a scalar logical, please check input!',fn{i});
                                end
                            case 'triggerSlope'
                                if ischar(tmp) && ismember(tmp,{'pos','neg'})
                                    % communicate to hardware
                                    mydo(obj,sprintf('TRIG:SLOP %s',upper(tmp)))
                                    % store value
                                    obj.p_Channel.(fn{i}) = tmp;
                                else
                                    error(sprintf('%s:Input',mfilename),...
                                        '%s is expected to be a char (''pos'' or ''neg''), please check input!',fn{i});
                                end
                            case 'triggerDelay'
                                if isnumeric(tmp) && isscalar(tmp) && tmp > 0 && tmp < 1000e-6
                                    % prepare value
                                    tmp = round(tmp*1e6)*1e-6;
                                    % communicate to hardware
                                    mydo(obj,sprintf('TRIG:DEL %d',tmp*1e6));
                                    % store value
                                    obj.p_Channel.(fn{i}) = tmp;
                                else
                                    error(sprintf('%s:Input',mfilename),...
                                        '%s is expected to be a scalar numeric value between 0 and 1000e-6, please check input!',fn{i});
                                end
                            case 'calibration'
                                if isempty(tmp) || isa(tmp,'function_handle')
                                    % prepare value
                                    if isempty(value), value = ''; end
                                    % store value
                                    obj.p_Channel.(fn{i}) = tmp;
                                else
                                    error(sprintf('%s:Input',mfilename),...
                                        '%s is expected to be a function handle or empty char, please check input!',fn{i});
                                end
                            case 'scale'
                                if ischar(tmp) && ismember(tmp,{'max','min'})
                                    % communicate to hardware
                                    mydo(obj,sprintf('CONF:RANG:SEL %s',upper(tmp)));
                                    % store value
                                    obj.p_Channel.(fn{i}) = tmp;
                                    % read min and max scale
                                    obj.p_Channel.scaleMin = str2double(mydo(obj,'CONF:RANG:SEL? MIN',1));
                                    obj.p_Channel.scaleMax = str2double(mydo(obj,'CONF:RANG:SEL? MAX',1));
                                    % and also update value not to trigger a change request
                                    value.scaleMin   = obj.p_Channel.scaleMin;
                                    value.scaleMax   = obj.p_Channel.scaleMax;
                                else
                                    error(sprintf('%s:Input',mfilename),...
                                        '%s is expected to be a char (''max'' or ''min''), please check input!',fn{i});
                                end
                            case 'running'
                                if islogical(tmp) && isscalar(tmp)
                                    % communicate to hardware
                                    if tmp
                                        mydo(obj,'INIT');
                                    else
                                        mydo(obj,'ABOR');
                                        readData(obj);
                                    end
                                    % store value
                                    obj.p_Channel.(fn{i}) = tmp;
                                else
                                    error(sprintf('%s:Input',mfilename),...
                                        '%s is expected to be a scalar logical, please check input!',fn{i});
                                end
                            otherwise
                                error(sprintf('%s:Input',mfilename),...
                                    'Unknown or unchangeable channel setting ''%s'' for device of class ''%s''',fn{i},class(obj));
                        end
                    end
                end
                if anynew, notify(obj,'newSettings'); end
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
        
        function out = get.Data(obj)
            
            out = obj.p_Data;
        end
        
        function       set.Data(obj,value)
            if obj.Logging
                error(sprintf('%s:Input',mfilename),...
                    'The object is currently logging and needs to be disabled before any change can be done');
            end
            if isempty(value)
                tmp.time   = datetime.empty;
                tmp.energy = [];
                tmp.period = [];
                tmp.flag   = uint8.empty;
                tmp.id     = uint64.empty;
                obj.p_Data = orderfields(tmp);
                notify(obj,'newData');
            else
                error(sprintf('%s:Input',mfilename),...
                    'Data can only be changed by a reset by supplying an empty value, please check input!');
            end
        end
        
        function out = get.Memory(obj)
            
            curval   = obj.p_Data; %#ok<NASGU>
            fileInfo = whos('curval','bytes');
            out      = fileInfo.bytes/1024^2;
        end
        
        function       set.Name(obj,value)
            
            if ischar(value)
                obj.Name = value;
            else
                error(sprintf('%s:Input',mfilename),...
                    'Name is expected to be a char, please check input!');
            end
        end
        
        function out = get.Logging(obj)
            
            out = obj.p_System.logging;
        end
        
        function       set.Logging(obj,value)
            
            obj.System.logging = value;
        end
        
        function out = get.Running(obj)
            
            out = obj.p_Channel.running;
        end
        
        function       set.Running(obj,value)
            
            obj.Channel.running = value;
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
                    'change\n%scommand window to long output format, i.e. ''format long'' or ',...
                    'use ''properties'' and\n%s''doc'' to get a list of the object properties'],...
                    spacing,class(obj),spacing,spacing);
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
        
        function               delete(obj)
            % delete Delete object and make sure serial connection is closed
            
            if isequal(obj.sobj.Status,'open')
                obj.System.logging = false;
                for i = 1:numel(obj.p_Channel)
                    obj.p_Channel(i).running = false;
                end
                fclose(obj.sobj);
            end
            delete(obj.sobj);
        end
        
        function S = saveobj(obj)
            % saveobj Supposed to be called by MATLAB's save function, stores settings of serial
            % connection and channel to allow for a recovery during the load processs
            
            S.Device  = obj.Device;
            S.Channel = obj.Channel;
            S.Name    = obj.Name;
        end
        
        function               reset(obj)
            % reset Resets device
            
            %
            % disable any logging function
            obj.sobj.BytesAvailableFcn = '';
            %
            % reset device
            if ~isequal(obj.sobj.Status,'open')
                fopen(obj.sobj);
            else
                % stop channel
                mydo(obj,'ABOR');
            end
            mydo(obj,'*RST');
            mydo(obj,sprintf('SYST:COMM:SER:BAUD %d',obj.sobj.BaudRate));
            if obj.p_Device.Delay > 0, pause(obj.p_Device.Delay); end
            %
            % set hand shacking
            mydo(obj,'SYST:COMM:HAND OFF');
            %
            % stop any channel, clear errors and flush input buffer
            mydo(obj,'ABOR');
            mydo(obj,'SYST:ERR:CLE');
            flushData(obj);
            %
            % read EnergyMax version and initialize the System property
            obj.p_System = orderfields(struct('logging',false,'version',mydo(obj,'*IDN?',1)));
            %
            % initialize channel structure
            % no calibration by default
            tmp.calibration = '';
            % channel should be off
            tmp.running = false;
            % set energy mode, turn statistics, gain and bus mode off
            mydo(obj,'CONF:MEAS:TYPE J');
            mydo(obj,'CONF:MEAS:STAT OFF');
            mydo(obj,'CONF:DEC 1');
            mydo(obj,'CONF:ITEM PULS,PER,FLAG,SEQ');
            mydo(obj,'CONF:GAIN:COMP OFF');
            mydo(obj,'CONF:GAIN:FACT 1');
            mydo(obj,'TRIG:BUS:PMOD NBUS');
            % get name and serial number
            tmp.name         = mydo(obj,'SYST:INF:MOD?',1);
            tmp.serialnumber = mydo(obj,'SYST:INF:SNUM?',1);
            % get remaining settings of channel and store everything to Channel property
            status = readChannel(obj);
            fn     = fieldnames(status);
            for i = 1:numel(fn), tmp.(fn{i}) = status.(fn{i});end
            % set scale to max
            tmp.scale = 'max';
            mydo(obj,sprintf('CONF:RANG:SEL %s',upper(tmp.scale)));
            % store information to class property
            obj.p_Channel = orderfields(tmp);
            %
            % read status and extract current settings
            syncChannel(obj);
            %
            % send newSettings event and reset data
            notify(obj,'newSettings');
            obj.resetData;
        end
        
        function varargout   = syncChannel(obj)
            % syncChannel Checks if channel settings (in class property Channel) match the status
            % of the hardware, which is returned as second ouput, the first output is true/false
            % whether the object was in sync, makes sure the class property is in sync
            
            if obj.p_Channel.running
                error(sprintf('%s:Input',mfilename),'Channel is running. Please stop it first!');
            end
            isOK   = true;
            status = readChannel(obj);
            fn     = fieldnames(status);
            for k = 1:numel(fn)
                if ~isequal(obj.p_Channel.(fn{k}),status.(fn{k}))
                    warning(sprintf('%s:Check',mfilename),...
                        'Mismatch in setting ''%s'', correcting class property accordingly',fn{k});
                    obj.p_Channel.(fn{k}) = status.(fn{k});
                    isOK                  = false;
                end
            end
            if nargout > 0, varargout = {isOK, stat}; end
        end
        
        function varargout = sync(obj)
            % sync Sync all properties that can be synced
            
            isOK    = syncChannel(obj);
            if nargout > 0, varargout = {all(isOK)}; end
        end
        
        function               resetData(obj)
            % resetData Reset Data property and delete any existing data
            
            obj.Data = [];
        end
        
        function [out, data] = flushData(obj)
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
        
        function out         = readData(obj)
            % readData Reads data from input buffer, applies calibration curve and adds it to the
            % Data property. The function stops reading data when all bytes available at the
            % beginning have been read. Returns true/false whether any data was read.
            
            %
            % read data from device and use current time as timestamp (a very rough estimate)
            out            = false;
            bytesAvailable = obj.sobj.BytesAvailable;
            if ~(bytesAvailable > 0)
                return;
            end
            in   = fread(obj.sobj,bytesAvailable);
            tNow = datetime('now');
            %
            % The energy meter sends ASCII with the highest bit set to 1 as control flag. Therefore,
            % the data is checked for this bit, transformed to the actual lower part of the ASCII
            % table and then to numeric data if possible. It expect four values (see Data Item
            % Select in the manual 'CONF:ITEM PULS,PER,FLAG,SEQ'), which are the pulse energy,
            % period, flag and sequence number. The values are seperated by commata (char(44)) and
            % each data record by a CR/LF Terminator (char(13) and char(10)). Output is a cell with
            % n x 4, where n is the number of data records in the iunput data.
            %
            % transform to uint8 and check highest bit of each byte
            in      = uint8(in);
            % disp(char(reshape(in-128,1,[])));
            testBit = logical(bitget(in,8));
            if ~all(testBit)
                warning(sprintf('%s:Input',mfilename),'Input data has at least one wrong check bit. Removing faulty ones.');
                in = in(testBit);
            end
            % unset highest bit
            in = bitset(in,8,0);
            % complete data set should end with CR/LF, but should not start with it,
            % also a comma should not be the first char in the data or the
            % third last
            if any(in([1 2]) == 10 | in([1 2]) == 13) || ...
                    in(end) ~= 10 || in(end-1) ~= 13 ||...
                    in(1) == 44 || in(end-2) == 44
                error(sprintf('%s:Input',mfilename),'Input data ends or starts with incomplete data record');
            end
            % seperate data records by checking for char(13) and char(10)
            % and process one by one
            idxEnd   = find(in(1:end-1)==13 & in(2:end)==10)-1;
            idxStart = [1; idxEnd(1:end-1)+3];
            for i = 1:numel(idxEnd)
                % get currend data record, convert to numeric and append data to class property
                [tmpE, tmpT, tmpF, tmpID] = obj.data2num(in(idxStart(i):idxEnd(i)));
                obj.p_Data.energy(end+1) = tmpE;
                obj.p_Data.period(end+1) = tmpT;
                obj.p_Data.flag(end+1)   = tmpF;
                obj.p_Data.id(end+1)     = tmpID;
                if i == 1
                    obj.p_Data.time(end+1) = tNow;
                else
                    obj.p_Data.time(end+1) = obj.p_Data.time(end) + duration(0,0,tmpT);
                end
            end
            obj.p_Data.energy = reshape(obj.p_Data.energy,[],1);
            obj.p_Data.period = reshape(obj.p_Data.period,[],1);
            obj.p_Data.flag   = reshape(obj.p_Data.flag,[],1);
            obj.p_Data.id     = reshape(obj.p_Data.id,[],1);
            obj.p_Data.time   = reshape(obj.p_Data.time,[],1);
            out = true;
            notify(obj,'newData');
        end
        
        function varargout   = showInfo(obj,noPrint)
            % showInfo Shows information on device on command line and returns cellstr with info,
            % output to command line can be supressed by the noPrint input
            
            if nargin < 2, noPrint = false; end
            if ~(islogical(noPrint) && isscalar(noPrint))
                error(sprintf('%s:Input',mfilename),...
                    'Optional second input is expected to be a scalar logical, please check input!');
            end
            %
            % check channels if possible
            if ~obj.p_Channel.running && ~obj.p_System.logging
                syncChannel(obj);
            end
            %
            % built information strings
            out        = cell(1);
            sep        = '  ';
            out{end+1} = sprintf('%s (%s) connected at ''%s''',obj.Name,obj.System.version,obj.sobj.Name);
            sep2       = repmat('-',1,numel(out{end}));
            out{end+1} = sep2;
            out{1}     = sep2;
            out{end+1} = sprintf('%s%s         Channel %d: ''%s'' (S/N: %s)',sep,sep,1,obj.p_Channel.name,obj.p_Channel.serialnumber);
            out{end+1} = sprintf('%s%s        wavelength: %d nm',sep,sep,obj.p_Channel.wavelength);
            out{end+1} = sprintf('%s%s          diameter: %.2f mm',sep,sep,obj.p_Channel.diameter*1e3);
            out{end+1} = sprintf('%s%s  external trigger: %d',sep,sep,obj.p_Channel.triggerExternal);
            out{end+1} = sprintf('%s%s     trigger delay: %.3e s',sep,sep,obj.p_Channel.triggerDelay);
            out{end+1} = sprintf('%s%s             scale: %s',sep,sep,obj.p_Channel.scale);
            out{end+1} = sprintf('%s%s          scaleMin: %.3e J',sep,sep,obj.p_Channel.scaleMin);
            out{end+1} = sprintf('%s%s          scaleMax: %.3e J',sep,sep,obj.p_Channel.scaleMax);
            out{end+1} = sprintf('%s%scalibration in use: %d',sep,sep,~isempty(obj.p_Channel.calibration));
            out{end+1} = sprintf('%s%s           running: %d',sep,sep,obj.p_Channel.running);
            out{end+1} = out{1};
            out{end}(round([1:(end/3) (2*end/3):end])) = ' '; out{end}(end) = ' ';
            if obj.System.logging
                out{end+1} = sprintf('%sSystem is currently logging',sep);
            else
                out{end+1} = sprintf('%sSystem is currently NOT logging',sep);
            end
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
        
        function varargout      = start(obj)
            % start Makes sure that the energy meter starts to stream data to the input buffer and
            % that the input buffer is converted to energy values in the Data property. The function
            % is a single command to get started. returns true if all went fine otherwise false
            
            %
            % enable channel
            allGood = true;
            if obj.p_System.logging
                % system is already logging, check if channel is activated
                allGood = obj.p_Channel.running;
                if ~allGood
                    warning(sprintf('%s:Reset',mfilename),...
                        'Device ''%s'' is already logging, but its channel is not running, please check manually!',obj.Name)
                end
            else
                % activate channel to start streaming to input buffer
                if ~obj.p_Channel.running, obj.Channel.running = true; end
                % activate post processing of data to Data property
                obj.System.logging = true;
            end
            if nargout > 0, varargout = {allGood}; end
        end
        
        function varargout      = stop(obj)
            % stop Stops all data acquisition, in addition it checks if all channels required the
            % same amount of data (number of measurements), it returns true if all went fine and
            % channels have the same amount of data, since the EnergyMax only exhibits one channel,
            % the function returns true in case no error occurs
            
            %
            % check channels channels
            if obj.p_System.logging, obj.System.logging = false; end
            % de-activate channel
            if obj.p_Channel.running, obj.Channel.running = false; end
            % de-activate post processing of data to Data property
            obj.System.logging = false;
            % check all channels
            allGood = true;
            if nargout > 0, varargout = {allGood}; end
        end
    end
    
    methods (Access = private, Hidden = false)
        function [energy, period, flag, seq] = data2num(obj,data)
            % data2num Converts data record string to energy, period, flag and sequence number
            
            if isempty(data)
                energy = [];
                period = [];
                flag   = uint8.empty;
                seq    = uint64.empty;
                return;
            end
            data = data(:);
            % split up in values by checing for char(44)
            curIdxEnd   = [find(data==44)-1; numel(data)];
            curIdxStart = [1; curIdxEnd(1:end-1)+2];
            if numel(curIdxEnd) ~= 4
                error(sprintf('%s:Input',mfilename),'Input data contains data record with less than four values');
            end
            % energy as double, apply calibration
            energy = str2double(char(reshape(data(curIdxStart(1):curIdxEnd(1)),1,[])));
            if isnan(energy)
                error(sprintf('%s:Input',mfilename),'Could not convert char to numeric');
            end
            if ~isempty(obj.p_Channel.calibration)
                energy = obj.p_Channel.calibration(energy);
            end
            % periodas double and in seconds (EnergyMax returns time as counts of microseconds)
            period = str2double(char(reshape(data(curIdxStart(2):curIdxEnd(2)),1,[])))*1e-6;
            if isnan(period)
                error(sprintf('%s:Input',mfilename),'Could not convert char to numeric');
            end
            % flag as uint8
            tmp = char(reshape(data(curIdxStart(3):curIdxEnd(3)),1,[]));
            switch tmp
                case '0'
                    flag = uint8(0);
                case 'P'
                    flag = uint8(1);
                case 'B'
                    flag = uint8(2);
                case 'M'
                    flag = uint8(3);
                otherwise
                    error(sprintf('%s:Input',mfilename),'Unknown flag');
            end
            % sequence number as uint64
            seq = str2double(char(reshape(data(curIdxStart(4):curIdxEnd(4)),1,[])));
            if isnan(seq)
                error(sprintf('%s:Input',mfilename),'Could not convert char to numeric');
            end
            seq = uint64(seq);
        end
        
        function out = readChannel(obj)
            % readChannel Reads all supported settings from hardware and returns settings structure
            
            out.diameter        = str2double(mydo(obj,'CONF:DIAM?',1))*1e-3;
            out.wavelength      = str2double(mydo(obj,'CONF:WAVE?',1));
            % the scale in terms of CHAR cannot be queried, but the min and max value of the range
            % out.scale         = lower(mydo(obj,'CONF:RANG:SEL?',1));
            out.scaleMin        = str2double(mydo(obj,'CONF:RANG:SEL? MIN',1));
            out.scaleMax        = str2double(mydo(obj,'CONF:RANG:SEL? MAX',1));
            out.triggerExternal = strcmp(mydo(obj,'TRIG:SOUR?',1),'EXT');
            out.triggerLevel    = str2double(mydo(obj,'TRIG:LEV?',1))*1e-2;
            out.triggerSlope    = lower(mydo(obj,'TRIG:SLOP?',1));
            out.triggerDelay    = str2double(mydo(obj,'TRIG:DEL?',1))*1e-6;
            out                 = orderfields(out);
        end
        
        function out = mydo(obj,cmd,len,noCheck)
            % mydo Sends char command cmd to serial device and expects len number of output lines in
            % char representation, returns a cellstr if len is greater than 1, otherwise a char.
            % Input noCheck can be used to disable error checking.
            
            if nargin < 3, len = 0; end
            if nargin < 4, noCheck = false; end
            %
            % error checking before command
            if ~noCheck, checkError(obj); end
            %
            % run command
            out = '';
            fprintf(obj.sobj,cmd);
            if len > 0
                out = cell(len,1);
                for i = 1:len
                    nBytes = mywait(obj,2);
                    if nBytes < 1
                        warning(sprintf('%s:Run',mfilename),['No data available from device ''%s'' ',...
                            'although an appropriate command ''%s'' was send, returning empty char'],obj.Name,cmd);
                        out{i} = '';
                    else
                        out{i} = fgetl(obj.sobj);
                    end
                end
                if len == 1, out = out{1}; end
            end
            [isData, data] = flushData(obj);
            if isData, warning(sprintf('%s:Run',mfilename),['Bytes available for device ''%s'', ',...
                    'which is not expected. Cleared bytes: %s'],obj.Name,num2str(data));
            end
            %
            % error checking after command
            if ~noCheck, checkError(obj); end
        end
        
        function out = mydoBin(obj,cmd,len,noCheck)
            % mydoBin Sends char command cmd to serial device and expects binar return of a given
            % length len. Read all available data for len < 0. Input noCheck can be used to disable
            % error checking.
            
            if nargin < 3, len = -1; end
            if nargin < 4, noCheck = false; end
            %
            % error checking before command
            if ~noCheck, checkError(obj); end
            %
            % run command
            fprintf(obj.sobj,cmd);
            nBytes = mywait(obj,abs(len));
            if nBytes < abs(len)
                warning(sprintf('%s:Reset',mfilename),...
                    'No data with %d bytes available from device ''%s'' although an appropriate command was send, returning %d bytes available',len,obj.Name,nBytes)
                if nBytes > 0
                    out = fread(obj.sobj,obj.sobj.BytesAvailable);
                else
                    out = [];
                end
            else
                if len < 0, len = obj.sobj.BytesAvailable; end
                out             = fread(obj.sobj,len);
            end
            [isData, data] = flushData(obj);
            if isData, warning(sprintf('%s:Reset',mfilename),...
                    'Bytes available for device ''%s'', which is not expected. Cleared bytes: %s',obj.Name,num2str(data));
            end
            %
            % error checking after command
            if ~noCheck, checkError(obj); end
        end
        
        function out = checkError(obj)
            % checkError Checks device for errors in queue, return true if an error was in the queue
            
            out = false;
            fprintf(obj.sobj,'SYST:ERR:COUN?');
            nBytes = mywait(obj,2);
            if nBytes > 0
                nErr = str2double(fgetl(obj.sobj));
                if nErr > 0
                    fprintf(obj.sobj,'SYST:ERR:ALL?');
                    nBytes = mywait(obj,2);
                    out    = true;
                    if nBytes > 0
                        str = fscanf(obj.sobj);
                        warning(sprintf('%s:Check',mfilename),...
                            'Device ''%s'' had %d error(s) in queue, error message: %s',obj.Name,nErr,str);
                    else
                        error(sprintf('%s:Check',mfilename),'Device ''%s'' does not seem to respond in time, please check!',obj.Name);
                    end
                end
            else
                error(sprintf('%s:Check',mfilename),'Device ''%s'' does not seem to respond in time, please check!',obj.Name);
            end
            
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
                % try to connect and set channel settings (the ones that can be changed)
                myset = {'calibration','diameter','scale','triggerDelay','triggerExternal','triggerLevel','triggerSlope','wavelength'};
                for n = 1:numel(S)
                    S(n).Device.showInfoOnConstruction = false;
                    obj(n)      = EnergyMax(S(n).Device); %#ok<AGROW>
                    obj(n).Name = S(n).Name; %#ok<AGROW>
                    tmp         = obj(n).Channel;
                    for k = 1:numel(myset)
                        tmp.(myset{k}) = S(n).Channel.(myset{k});
                    end
                    obj(n).Channel = tmp; %#ok<AGROW>
                    showInfo(obj(n));
                end
            catch err
                warning(sprintf('%s:Input',mfilename),...
                    'Device could not be re-connected during load process: %s',err.getReport);
            end
        end
    end
end
