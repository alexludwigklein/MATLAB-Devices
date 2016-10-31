classdef SLink < handle
    %SLink Class describing the serial connection to the energy meter(s) at an SLink by gentec-eo
    %
    %   The class allows to connect to one or two energy meters by gentec-eo connected to an SLink
    %   device and acquire data from the energy meters. So far, it only accepts energy meters as
    %   detector and not power meters.
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
        % System System settings of the SLink hardware (structure)
        %
        % This property holds settings of and information on the SLink device. The fields of the
        % structure are:
        %   version: the version of the software on the SLink device (read-only)
        %   logging: true/false whether the input buffer is streamed to the Data property
        System
        % Channel Energy meter(s) connected to channel one and two of the SLink device (structure)
        %
        % This property is a structure array with information and settings for the two channels of
        % the SLink device. The fields of the structure array are:
        %        attenuator: true/false whether an attenuator is used
        %       calibration: this can be used to transform the data read from the energy meter in
        %                    order to consider a calibration curve. The input should be a function
        %                    handle that accepts one numeric input (scalar or vector). Default is an
        %                    empty string, which means no calibration curve is used.
        %              mode: char 'Binary' or 'ASCII' for the data mode
        %              name: char for the name of the detector (read-only)
        %             scale: double scalar for the scale index of the channel
        %          scaleMax: double scalar for the upper value of the range (read-only)
        %          scaleMin: double scalar for the lower value of the range (read-only)
        %        scaleValue: double scalar for the nominal value of the scale (read-only)
        %      serialnumber: char for the serial number of the detector (read-only)
        %           running: true/false whether the channel is sending data to input buffer
        %   triggerExternal: true/false whether the external trigger is used
        %      triggerLevel: scalar double for the relative trigger level (between 0 and 1)
        %        wavelength: scalar double for the wavelength in nm
        Channel
        % Logging A shortcut for obj.System.logging, i.e. data is written to the Data property
        Logging
        % Running True/false whether any channel is running, i.e. waits for trigger and reads data
        % to its input buffer
        Running
        % Data Data read from each channel (structure)
        %
        % This property is a structure array and holds the actual data acquired by each channel. The
        % fields of the structure array are:
        %   energy: double for energy in J (a calibration may change the unit)
        %     time: datetime for estimated time of measurement (time it was converted by readData)
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
        Name = 'SLink';
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
    
    properties (Constant = true)
        % ScaleTable SLink's conversion from scale index to the nominal value in J
        ScaleTable = [
            0    1e-12
            1    3e-12
            2   10e-12
            3   30e-12
            4  100e-12
            5  300e-12
            6    1e-9
            7    3e-9
            8   10e-9
            9   30e-9
            10 100e-9
            11 300e-9
            12   1e-6
            13   3e-6
            14  10e-6
            15  30e-6
            16 100e-6
            17 300e-6
            18   1e-3
            19   3e-3
            20  10e-3
            21  30e-3
            22 100e-3
            23 300e-3
            24   1e-0
            25   3e-0
            26  10e-0
            27  30e-0
            28 100e-0
            29 300e-0
            30   1e+3
            31   3e+3
            32  10e+3
            33  30e+3
            34 100e+3
            35 300e+3
            36   1e+6
            37   3e+6
            38  10e+6
            39  30e+6
            40 100e+6
            41 300e+6
            ];
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
        function obj = SLink(varargin)
            % SLink Creates object that links to the device
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
                        anynew = true;
                        switch fn{i}
                            case 'logging'
                                if ~any([obj.p_Channel.running])
                                    error(sprintf('%s:Input',mfilename),...
                                        'None of the channels is running, please enable running for at least one channel');
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
            if ~(isstruct(value) && numel(value) == 2 && all(ismember(fieldnames(value),fieldnames(obj.Channel))))
                error(sprintf('%s:Input',mfilename),...
                    'Expected a structure array with 2 elements with channel settings as input, please check input!');
            else
                if obj.System.logging
                    error(sprintf('%s:Input',mfilename),'System is logging input buffer to Data property. Please stop logging first!');
                end
                fn     = fieldnames(value);
                anynew = false;
                for iCH = 1:numel(obj.p_Channel)  % loop over channels
                    for i = 1:numel(fn)           % loop over settings
                        tmp = value(iCH).(fn{i}); % get value of current setting
                        if ~isequal(tmp,obj.p_Channel(iCH).(fn{i})) % only process if it changed
                            if any([obj.p_Channel.running]) && ~strcmp(fn{i},'running')
                                error(sprintf('%s:Input',mfilename),'At least one channel is running. Please stop it first!');
                            end
                            anynew = true;
                            switch fn{i}
                                case 'wavelength'
                                    if isnumeric(tmp) && isscalar(tmp) && tmp >= 0
                                        % prepare value
                                        tmp = round(tmp);
                                        % communicate to hardware
                                        str = sprintf('%0.5d',tmp);
                                        if numel(str) ~= 5
                                            error(sprintf('%s:Input',mfilename),...
                                                '%s is expected to be converted to five characters, but it was ''%s'', please check!',fn{i},str);
                                        end
                                        mydo(obj,sprintf('*PW%d%s',iCH,str));
                                        % store value
                                        obj.p_Channel(iCH).(fn{i}) = tmp;
                                    else
                                        error(sprintf('%s:Input',mfilename),...
                                            '%s is expected to be a scalar numeric value larger zero, please check input!',fn{i});
                                    end
                                case 'attenuator'
                                    if islogical(tmp) && isscalar(tmp)
                                        % communicate to hardware
                                        mydo(obj,sprintf('*AT%d%d',iCH,tmp));
                                        % store value
                                        obj.p_Channel(iCH).(fn{i}) = tmp;
                                    else
                                        error(sprintf('%s:Input',mfilename),...
                                            '%s is expected to be a scalar logical, please check input!',fn{i});
                                    end
                                case 'triggerLevel'
                                    if isnumeric(tmp) && isscalar(tmp) && tmp > 0 && tmp < 1
                                        % communicate to hardware
                                        str = sprintf('%0.3f',tmp*100);
                                        str = str(1:4);
                                        if numel(str) ~= 4
                                            error(sprintf('%s:Input',mfilename),...
                                                '%s is expected to be converted to four characters, but it was ''%s'', please check!',fn{i},str);
                                        end
                                        mydo(obj,sprintf('*TL%d%s',iCH,str));
                                        % store value
                                        obj.p_Channel(iCH).(fn{i}) = str2double(str)/100;
                                    else
                                        error(sprintf('%s:Input',mfilename),...
                                            '%s is expected to be a scalar numeric value between zero and one, please check input!',fn{i});
                                    end
                                case 'triggerExternal'
                                    if islogical(tmp) && isscalar(tmp)
                                        % communicate to hardware
                                        mydo(obj,sprintf('*ET%d%d',iCH,tmp));
                                        % store value
                                        obj.p_Channel(iCH).(fn{i}) = tmp;
                                    else
                                        error(sprintf('%s:Input',mfilename),...
                                            '%s is expected to be a scalar logical, please check input!',fn{i});
                                    end
                                case 'mode'
                                    if ischar(tmp) && ismember(tmp,{'Binary','ASCII'})
                                        % communicate to hardware
                                        if strcmp(tmp,'Binary')
                                            mydo(obj,sprintf('*SS%d000',iCH));
                                        else
                                            mydo(obj,sprintf('*SS%d001',iCH));
                                        end
                                        % store value
                                        obj.p_Channel(iCH).(fn{i}) = tmp;
                                    else
                                        error(sprintf('%s:Input',mfilename),...
                                            '%s is expected to be a char (''Binary'' or ''ASCII''), please check input!',fn{i});
                                    end
                                case 'calibration'
                                    if isempty(tmp) || isa(tmp,'function_handle')
                                        % prepare value
                                        if isempty(value), value = ''; end
                                        % store value
                                        obj.p_Channel(iCH).(fn{i}) = tmp;
                                    else
                                        error(sprintf('%s:Input',mfilename),...
                                            '%s is expected to be a function handle or empty char, please check input!',fn{i});
                                    end
                                case 'scale'
                                    if isnumeric(tmp) && isscalar(tmp) && tmp >= 0 && tmp <= 41
                                        % prepare value
                                        tmp = round(tmp);
                                        if obj.ScaleTable(tmp,2) < obj.p_Channel(iCH).scaleMin || ...
                                                obj.ScaleTable(tmp,2) > obj.p_Channel(iCH).scaleMax
                                            error(sprintf('%s:Input',mfilename),...
                                                'The requested scale %d does not seem to be supported by the detector at channel %d, please check!',tmp,iCH);
                                        end
                                        % communicate to hardware
                                        str = sprintf('%0.2d',tmp);
                                        if numel(str) ~= 2
                                            error(sprintf('%s:Input',mfilename),...
                                                '%s is expected to be converted to two characters, but it was ''%s'', please check!',fn{i},str);
                                        end
                                        mydo(obj,sprintf('*SC%d%s',iCH,str));
                                        % store value
                                        obj.p_Channel(iCH).(fn{i}) = tmp;
                                        % update scaleValue
                                        obj.p_Channel(iCH).scaleValue = obj.ScaleTable(tmp+1,2);
                                        % read min and max scale
                                        sc                          = getScale(obj,iCH);
                                        obj.p_Channel(iCH).scaleMin = sc(1);
                                        obj.p_Channel(iCH).scaleMax = sc(2);
                                        % and also update value not to trigger a change request
                                        value(iCH).scaleMin   = obj.p_Channel(iCH).scaleMin;
                                        value(iCH).scaleMax   = obj.p_Channel(iCH).scaleMax;
                                        value(iCH).scaleValue = obj.p_Channel(iCH).scaleValue;
                                    else
                                        error(sprintf('%s:Input',mfilename),...
                                            '%s is expected to be a scalar numeric value between zero and 41, please check input!',fn{i});
                                    end
                                case 'running'
                                    if islogical(tmp) && isscalar(tmp)
                                        % communicate to hardware
                                        if tmp
                                            mydo(obj,sprintf('*CA%d',iCH));
                                        else
                                            mydo(obj,sprintf('*CS%d',iCH));
                                            readData(obj);
                                        end
                                        % store value
                                        obj.p_Channel(iCH).(fn{i}) = tmp;
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
                tmp(2)     = tmp;
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
            
            out = any([obj.p_Channel.running]);
        end
        
        function       set.Running(obj,value)
            
            if islogical(value) && numel(value) <= 2
                if isscalar(value), value = repmat(value,2,1); end
                for n = 1:numel(obj.p_Channel)
                    obj.Channel(n).running = value(n);
                end
            else
                error(sprintf('%s:Input',mfilename),...
                    'Running is expected to be a logical array with one or two entries, please check input!');
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
                fprintf(['%s%s object, use class method ''showInfo'' to get the same\n%sinformation, ',...
                    'change command window to long output format,\n%si.e. ''format long'' or ',...
                    'use ''properties'' and ''doc'' to get\n%sa list of the object properties'],...
                    spacing,class(obj),spacing,spacing,spacing);
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
        
        function delete(obj)
            % delete Delete object and make sure serial connection is closed
            
            if isequal(obj.sobj.Status,'open')
                obj.System.logging = false;
                for i = 1:numel(obj.p_Channel)
                    obj.Channel(i).running = false;
                end
                for i = 1:numel(obj.p_Channel)
                    obj.Channel(i).mode   = 'Binary';
                end
                fclose(obj.sobj);
            end
            delete(obj.sobj);
        end
        
        function S = saveobj(obj)
            % saveobj Supposed to be called by MATLAB's save function, stores settings of serial
            % connection and channels to allow for a recovery during the load processs
            
            S.Device  = obj.Device;
            S.Channel = obj.Channel;
            S.Name    = obj.Name;
        end
        
        function reset(obj)
            % reset Resets device
            
            %
            % disable any logging function
            obj.sobj.BytesAvailableFcn = '';
            %
            % reset device
            if ~isequal(obj.sobj.Status,'open')
                fopen(obj.sobj);
            else
                % stop any channel and reset device
                mydo(obj,'*CS1');
                mydo(obj,'*CS2');
            end
            mydo(obj,'*RST',1);
            if obj.p_Device.Delay > 0, pause(obj.p_Device.Delay); end
            %
            % flush input buffer
            flushData(obj);
            %
            % read SLink version and initialize the System property
            obj.p_System = orderfields(struct('logging',false,'version',mydo(obj,'*Ver',1)));
            %
            % deactivate acknowledge mode and polling mode
            mydo(obj,'*NMQ');
            mydo(obj,'*VNP');
            %
            % read detectors and initialize channel structure
            tmp = struct;
            for i = 1:2
                % no calibration by default
                tmp(i).calibration  = '';
                % stop any channel
                mydo(obj,sprintf('*CS%d',i));
                tmp(i).running = false;
                % switch to Binary mode
                mydo(obj,sprintf('*SS%d000',i));
                tmp(i).mode = 'Binary';
                % get name and serial number
                tmp(i).name         = mydo(obj,sprintf('*NA%d',i),1);
                tmp(i).serialnumber = mydo(obj,sprintf('*SN%d',i),1);
                % read status and extract current settings
                status = mydoBin(obj,sprintf('*ST%d',i),108);
                status = obj.status2struct(status);
                fn     = fieldnames(status);
                for k = 1:numel(fn)
                    tmp(i).(fn{k}) = status.(fn{k});
                end
                % initialize scale value with NaN, read later after the
                % channel is setup
                tmp(i).scaleValue = NaN;
                tmp(i).scaleMin   = NaN;
                tmp(i).scaleMax   = NaN;
            end
            obj.p_Channel = orderfields(tmp);
            %
            % read scale
            for i = 1:2
                % get scale value
                obj.p_Channel(i).scaleValue = obj.ScaleTable(obj.p_Channel(i).scale+1,2);
                % get scale range
                sc                        = getScale(obj,i);
                obj.p_Channel(i).scaleMin = sc(1);
                obj.p_Channel(i).scaleMax = sc(2);
            end
            %
            % read status and extract current settings
            syncChannel(obj);
            %
            % send newSettings event and reset data
            notify(obj,'newSettings');
            obj.resetData;
        end
        
        function isOK           = syncChannel(obj)
            % syncChannel Checks if channel settings (in class property Channel) match the status of
            % the hardware. In case it does not match the class property is corrected.
            
            if any([obj.p_Channel.running])
                error(sprintf('%s:Input',mfilename),'At least one channel is running. Please stop it first!');
            end
            isOK = true;
            for i = 1:numel(obj.p_Channel)
                % read status and extract current settings
                tmp       = mydoBin(obj,sprintf('*ST%d',i),108);
                status(i) = obj.status2struct(tmp); %#ok<AGROW>
                fn        = fieldnames(status);
                for k = 1:numel(fn)
                    if ~isequal(obj.p_Channel(i).(fn{k}),status(i).(fn{k}))
                        warning(sprintf('%s:Check',mfilename),...
                            'Mismatch in setting ''%s'' for channel %d, correcting class property Channel accordingly',fn{k},i);
                        obj.p_Channel(i).(fn{k}) = status(i).(fn{k});
                        isOK                     = false;
                    end
                end
            end
        end
        
        function varargout = sync(obj)
            % sync Sync all properties that can be synced
            
            isOK    = syncChannel(obj);
            if nargout > 0, varargout = {all(isOK)}; end
        end
        
        function                  resetData(obj)
            % resetData Reset Data property and delete any existing data
            
            obj.Data = [];
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
        
        function out            = readData(obj)
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
            tNow = datetime('now');
            in   = fread(obj.sobj,bytesAvailable);
            %
            % check if any channel is set to ASCII mode
            anyASCII = false;
            for i = 1:numel(obj.p_Channel)
                anyASCII = anyASCII || strcmp(obj.p_Channel(i).mode,'ASCII');
            end
            %
            % scan new data
            data1  = []; % data of channel 1
            data2  = []; % data of channel 2
            sc     = [obj.p_Channel.scaleValue];
            while numel(in) > 0
                if anyASCII && numel(in) > 12 && in(2) == 58 && any(in(1) == [49 50]) && ...
                        any(in(12) == [10 13]) && any(in(13) == [10 13])
                    % SLink: ASCII lines start with '1:' or '2:', which is [49 58] or [50 58] in
                    % numeric representation. A single ASCII data record should be 11 bytes without
                    % the line feed (10 in numeric) and carriage return (13 in numeric), so one
                    % ASCII data set should have 13 bytes
                    tmp = str2double(char(reshape(in(3:11),1,[])));
                    if in(1) == 49
                        data1(end+1) = tmp; %#ok<AGROW>
                    else
                        data2(end+1) = tmp; %#ok<AGROW>
                    end
                    in(1:13) = [];
                elseif numel(in) > 1 && diff(bitget(uint8(in([1 2])),8)) == 0 && diff(bitget(uint8(in([2 1])),7))==1
                    % a single binary record consists of two bytes, the last bit in each byte is
                    % the channel number and the second last bit the reverse order, see SLink manual
                    % on the binary format and note: bitget(A,1) returns the least significant bit
                    %
                    % option 1:
                    tmpIn = dec2bin(in([1 2]),8);
                    tmp   = bin2dec([tmpIn(1,3:8) tmpIn(2,3:8)]);
                    % option 2:
                    % tmpIn    = uint8(in([1 2]));
                    % tmpIn(1) = bitset(bitset(tmpIn(1),7,0),8,0);
                    % tmpIn(2) = bitset(bitset(tmpIn(2),7,0),8,0);
                    % tmp      = (tmpIn(1) * 2^6) + tmpIn(2);
                    if strcmp(tmpIn(1,1),'0') % option 2: bitget(tmpIn(1),8) == 0
                        data1(end+1) = tmp/4096 * sc(1); %#ok<AGROW>
                    else
                        data2(end+1) = tmp/4096 * sc(2); %#ok<AGROW>
                    end
                    in([1 2]) = [];
                else
                    warning(sprintf('%s:Read',mfilename),'Data record seems to be incomplete (stopped reading): %s',num2str(in));
                    break;
                end
            end
            %
            % apply calibration
            if ~isempty(data1) && ~isempty(obj.p_Channel(1).calibration)
                data1 = obj.p_Channel(1).calibration(data1);
            end
            if ~isempty(data2) && ~isempty(obj.p_Channel(2).calibration)
                data2 = obj.p_Channel(2).calibration(data2);
            end
            %
            % append data to Data property
            if ~isempty(data1)
                obj.p_Data(1).energy = cat(1,obj.p_Data(1).energy,reshape(data1,[],1));
                obj.p_Data(1).time   = cat(1,obj.p_Data(1).time,repmat(tNow,numel(data1),1));
            end
            if ~isempty(data2)
                obj.p_Data(2).energy = cat(1,obj.p_Data(2).energy,reshape(data2,[],1));
                obj.p_Data(2).time   = cat(1,obj.p_Data(2).time,repmat(tNow,numel(data2),1));
            end
            out = true;
            notify(obj,'newData');
        end
        
        function varargout      = showInfo(obj,noPrint)
            % showInfo Shows information on device on command line and returns cellstr with info,
            % output to command line can be supressed by the noPrint input
            
            if nargin < 2, noPrint = false; end
            if ~(islogical(noPrint) && isscalar(noPrint))
                error(sprintf('%s:Input',mfilename),...
                    'Optional second input is expected to be a scalar logical, please check input!');
            end
            %
            % check channels if possible
            if all(~[obj.p_Channel.running]) && ~obj.p_System.logging
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
            for i = 1:numel(obj.p_Channel)
                out{end+1} = sprintf('%s%s         Channel %d: ''%s'' (S/N: %s)',sep,sep,i,obj.p_Channel(i).name,obj.p_Channel(i).serialnumber); %#ok<AGROW>
                out{end+1} = sprintf('%s%s        wavelength: %d nm',sep,sep,obj.p_Channel(i).wavelength); %#ok<AGROW>
                out{end+1} = sprintf('%s%s        attenuator: %d',sep,sep,obj.p_Channel(i).attenuator); %#ok<AGROW>
                out{end+1} = sprintf('%s%s  external trigger: %d',sep,sep,obj.p_Channel(i).triggerExternal); %#ok<AGROW>
                out{end+1} = sprintf('%s%s       scale index: %d',sep,sep,obj.p_Channel(i).scale); %#ok<AGROW>
                out{end+1} = sprintf('%s%scalibration in use: %d',sep,sep,~isempty(obj.p_Channel(i).calibration)); %#ok<AGROW>
                out{end+1} = sprintf('%s%s  acquisition mode: %s',sep,sep,obj.p_Channel(i).mode); %#ok<AGROW>
                out{end+1} = sprintf('%s%s           running: %d',sep,sep,obj.p_Channel(i).running); %#ok<AGROW>
                out{end+1} = ''; %#ok<AGROW>
            end
            out{end} = out{1};
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
        
        function out            = scaleLookup(obj,energy)
            % scaleLookup Looks up the scale to use for a given energy in J
            
            if nargin < 2 || ~(isnumeric(energy) && isscalar(energy) && energy > 0)
                error(sprintf('%s:Input',mfilename),...
                    'Expected a scalar double greater than zero for the energy in J to look up, please check input!');
            end
            [minE, idxMin] = min(obj.ScaleTable(:,2));
            [maxE, idxMax] = max(obj.ScaleTable(:,2));
            if energy < minE
                warning(sprintf('%s:Input',mfilename),...
                    'Energy %e J is smaller than lower bound %e J, returning index of lower bound', energy, minE);
                out = obj.ScaleTable(idxMin,1);
            elseif energy > max(obj.ScaleTable)
                warning(sprintf('%s:Input',mfilename),...
                    'Energy %e J is greater than upper bound %e J, returning index of upper bound', energy, maxE);
                out = obj.ScaleTable(idxMax,1);
            else
                idxOK    = find(obj.ScaleTable(:,2) >= energy);
                [~, idx] = min(obj.ScaleTable(idxOK,2));
                out      = obj.ScaleTable(idxOK(idx),1);
            end
        end
        
        function varargout      = start(obj,idx)
            % start Makes sure that the energy meter(s) start to stream data to the input buffer and
            % that the input buffer is converted to energy values in the Data property. The function
            % is a single command to get started. The optional second input is the indices of the
            % channel(s) that should be started (does not stop any channel if they are already
            % running), returns true if all went fine otherwise false
            
            %
            % check input
            nCh = numel(obj.p_Channel);
            if nargin < 2 || isempty(idx), idx = 1:nCh; end
            if ~(isnumeric(idx) && numel(idx) <= nCh && min(idx) >= 1 && max(idx) <= nCh)
                error(sprintf('%s:Input',mfilename),...
                    'Index (2nd input) is unexpected, please check input!');
            end
            %
            % enable channels
            allGood = true;
            if obj.p_System.logging
                % system is already logging, check if channels are activated
                for i = reshape(idx,1,[]), if ~obj.p_Channel(i).running, allGood = false; end; end
                if ~allGood
                    warning(sprintf('%s:Reset',mfilename),...
                        'Device ''%s'' is already logging, but the requested channels are not running, please check manually!',obj.Name)
                end
            else
                % activate channels to start streaming to input buffer
                for i = reshape(idx,1,[])
                    if ~obj.p_Channel(i).running, obj.Channel(i).running = true; end
                end
                % activate post processing of data to Data property
                obj.System.logging = true;
            end
            if nargout > 0, varargout = {allGood}; end
        end
        
        function varargout      = stop(obj)
            % stop Stops all data acquisition, in addition it checks if all channels required the
            % same amount of data (number of measurements), it returns true if all went fine and
            % channels have the same amount of data
            
            %
            % check channels channels
            if obj.p_System.logging, obj.System.logging = false; end
            % de-activate channels
            nData = NaN(size(obj.p_Channel));
            nCh   = numel(obj.p_Channel);
            for i = 1:nCh
                if obj.p_Channel(i).running, obj.Channel(i).running = false; end
            end
            % de-activate post processing of data to Data property
            obj.System.logging = false;
            % check all channels
            for i = 1:nCh
                nData(i) = numel(obj.p_Data(i).energy);
            end
            allGood = all(nData == nData(1));
            if ~allGood
                warning(sprintf('%s:Reset',mfilename),...
                    'Channels of device ''%s'' contain data of different length',obj.Name)
            end
            if nargout > 0, varargout = {allGood}; end
        end
    end
    
    methods (Access = private, Hidden = false)
        function out = mydo(obj,cmd,len)
            % mydo Sends char command cmd to serial device and expects len number of output lines in
            % char representation, returns a cellstr if len is greater than 1, otherwise a char
            
            if nargin < 3, len = 0; end
            out = '';
            fprintf(obj.sobj,cmd);
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
        
        function out = mydoBin(obj,cmd,len)
            % mydoBin Sends char command cmd to serial device and expects binar return of a given
            % length len. Read all available data for len < 0.
            
            if nargin < 3, len = -1; end
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
        end
        
        function out = getScale(obj,ch)
            % getScale Gets the range for the current set scale excluding calibration
            
            if any([obj.p_Channel.running])
                error(sprintf('%s:Input',mfilename),'At least one channel is running. Please stop it first!');
            end
            out = NaN(1,2);
            tmp = mydo(obj,sprintf('*RG%d',ch),3);
            % see the return expected from SLink in manual
            if iscellstr(tmp) && numel(tmp) == 3 && all(cellfun(@(x) numel(x),tmp) == 10) && ...
                    strcmp(tmp{3},':100000000') && strcmp(tmp{1}(1:6),':00000') && strcmp(tmp{2}(1:6),':00001')
                out = reshape(obj.ScaleTable([hex2dec(tmp{1}(7:end)) hex2dec(tmp{2}(7:end))]+1,2),1,[]);
            else
                warning(sprintf('%s:Input',mfilename),'Could not read scale for channel %d, returning NaN',ch);
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
                myset = {'attenuator','calibration','mode','scale','triggerExternal','triggerLevel','wavelength'};
                for n = 1:numel(S)
                    S(n).Device.showInfoOnConstruction = false;
                    obj(n)      = SLink(S(n).Device); %#ok<AGROW>
                    obj(n).Name = S(n).Name; %#ok<AGROW>
                    tmp         = obj(n).Channel;
                    for k = 1:numel(myset)
                        for l = 1:numel(tmp)
                            tmp(l).(myset{k}) = S(n).Channel(l).(myset{k});
                        end
                    end
                    obj(n).Channel = tmp; %#ok<AGROW>
                    showInfo(obj(n));
                end
            catch err
                warning(sprintf('%s:Input',mfilename),...
                    'Device could not be re-connected during load process: %s',err.getReport);
            end
        end
        
        function out = status2struct(data)
            % status2struct Converts binary status information to structure
            
            out.attenuator      = false;
            out.triggerExternal = false;
            out.scale           = NaN;
            out.triggerLevel    = NaN;
            out.wavelength      = NaN;
            % see the return expected from SLink in manual, each line (in total 9) has 12 bytes and
            % should start with a ':' (58 in numeric representation), each line ends with LF and CR
            % (10 and 13 in numeric representation) and the address counts 0 to 7 and 0 again
            data = reshape(data,1,[]);
            if numel(data) == 108 && all(data(1:12:end) == 58) && all(data(1:12:end) == 58) && ...
                    all(data(11:12:end) == 13) && all(data(12:12:end) == 10) && all(data(6:12:end) == [48:55 48])
                for i = 0:7
                    myValue = data((7:10) + i*12);
                    switch i
                        case 0 % wavelength
                            out.wavelength = hex2dec(char(myValue));
                        case 1 % scale
                            out.scale = hex2dec(char(myValue));
                        case 2 % trigger level
                            out.triggerLevel = (hex2dec(char(myValue))/20.48)/100;
                        case 3 % reserved
                        case 4 % attenuator
                            out.attenuator = ~(hex2dec(char(myValue)) < 1);
                        case 5 % external trigger
                            out.triggerExternal = ~(hex2dec(char(myValue)) < 1);
                        case 6 % anticipation (only for power meters)
                        case 7 % energy mode (only for power meters)
                    end
                end
            else
                warning(sprintf('%s:Input',mfilename),'Could not read status, returning default values');
            end
        end
    end
end
