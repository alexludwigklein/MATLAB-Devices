classdef NewportESP < handle
    %NewportESP Class describing the serial connection to the Newport motion controller ESP301 or similar
    %
    %   The class allows to connect to one motion controller via a virtual COM port using a USB
    %   connection. The controller is supposed to have three motors connected, which can be accessed
    %   via the class object. Only a limited number of commands are supported by this class to allow
    %   for basic motion control. However, it is possible to send direct commands to the device with
    %   the mydo method of the class. For example, most configuration settings are not directly
    %   accessible in the class and assumed to be set on the hardware panel manually or by sending
    %   the corresponding command with mydo.
    %
    %   The object can be saved to disk, but it stores only the settings and not the actual data or
    %   user data. This can be used to quickly store the settings of the object to disk for a later
    %   recovery.
    %
    % Implementation notes:
    %   * The System and Axis properties keep a copy of the hardware settings in the MATLAB
    %     object and do not sync with the hardware (slows down due to the many commands that need to
    %     be transferred via a serial connection). The functions syncSystem and syncAxis can be used
    %     to force a sync. The most important values can be accessed in sync by using their root
    %     properties, i.e. obj.Axis.position can be accessed also by obj.Position, where the later
    %     directly reads from the hardware. The following values are available in direct sync:
    %           obj.Axis(i).position:  obj.Position(i)
    %             obj.Axis(i).moving:  obj.Moving(i)
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
        % System System settings of the NewportESP hardware (structure)
        %
        % This property holds settings of and information on the NewportESP device. The fields of
        % the structure are:
        %   controllerActivity: string for the controller activity byte(s) (read-only)
        %     controllerStatus: string for the controller status byte(s) (read-only)
        %        deviceAddress: double scalar for the device address (read-only)
        %            espConfig: string for the ESP system configuration byte(s) (read-only)
        %       hardwareStatus: string for the two hardware status registers (read-only)
        %               locked: true/false whether the keypad is locked
        %         systemConfig: string for the system configuration bit (read-only)
        %              version: string for the version of the software on the NewportESP device (read-only)
        System
        % Axis Axis of the device (structure)
        %
        % This property is a structure array with information and settings for each axis of the
        % device. The fields of the structure array are:
        %      acceleration: scalar double for the acceleration in units/s^2 (read-only)
        %   amplifierConfig: string for the amplifier configuration bit (read-only)
        %      deceleration: scalar double for the deceleration in units/s^2 (read-only)
        %   emergencyConfig: string for the emergency configuration bit (read-only)
        %      emergencyDec: scalar double for the emergency deceleration in units/s^2 (read-only)
        %    feedBackConfig: string for the feedback configuration bit (read-only)
        %   followingConfig: string for the following error configuration bit (read-only)
        %             limit: double array with two elements for the left and right software travel limit (read-only)
        %      limitSConfig: string for the software limit configuration bit (read-only)
        %      limitHConfig: string for the hardware limit configuration bit (read-only)
        %             model: string for the model and serial number (read-only)
        %            moving: logical scalar to indicate whether the axis is moving currently (read-only)
        %          position: double scalar for the current position
        %             power: logical scalar to indicate whether the axis is powered
        %              type: string for the type of motor (read-only)
        %              unit: string for the axis displacement unit (read-only)
        %          velocity: scalar double for the velocity in units/s
        Axis
        % Position Synced version of obj.Axis.position (see implementation notes at the top)
        Position
    end
    
    properties (GetAccess = public, SetAccess = protected, Dependent = true)
        % Status Status of the serial device (structure)
        %
        % This property holds all serial properties that can change over time (see MATLAB's
        % documentation). The fields of the structure are:
        %   <all varying properties of a serial device>: see MATLAB's documentation
        Status
        % Moving True\false whether an axis is moving (logical array)
        Moving
    end
    
    properties (GetAccess = public, SetAccess = public, Transient = true)
        % Name A short name for the device (char)
        Name = 'NewportESP';
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
        % p_Axis Storage for Axis
        p_Axis
    end
    
    properties (Constant = true)
        % UnitTable Conversion table from numerical value to human readable unit string
        UnitTable = {
            0  'encoder count'
            1  'motor step'
            2  'millimeter'
            3  'micrometer'
            4  'inches'
            5  'milli-inches'
            6  'micro-inches'
            7  'degree'
            8  'gradian'
            9  'radian'
            10 'milliradian'
            11 'microradian'
            };
        % TypeTable Conversion table from numerical value to human readable motor type
        TypeTable = {
            0  'motor type undefined'
            1  'DC servo motor (single analog channel)'
            2  'step motor (digital control)'
            3  'commutated step motor (analog control)'
            4  'commutated brushless DC servo motor'
            };
    end
    
    %% Events
    events
        % newSettings Notify when settings are changed
        newSettings
    end
    
    %% Constructor and SET/GET
    methods
        function obj = NewportESP(varargin)
            % NewportESP Creates object that links to the device
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
            % reset device, initialize remaining properties and show info
            reset(obj);
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
        
        function out = get.Axis(obj)
            
            out = obj.p_Axis;
        end
        
        function       set.Axis(obj,value)
            
            % check if input is given as a structure, but only allow for changing specific settings
            if ~(isstruct(value) && numel(value) == numel(obj.p_Axis) && all(ismember(fieldnames(value),fieldnames(obj.p_Axis))))
                error(sprintf('%s:Input',mfilename),...
                    'Expected a structure array with settings for each axis as input, please check input!');
            else
                fn     = fieldnames(value);
                anynew = false;
                for iAx = 1:numel(obj.p_Axis)     % loop over axes
                    for i = 1:numel(fn)           % loop over settings
                        tmp = value(iAx).(fn{i}); % get value of current setting
                        if ~isequal(tmp,obj.p_Axis(iAx).(fn{i})) % only process if it changed
                            anynew = true;
                            switch fn{i}
                                case 'position'
                                    if isfloat(tmp) && isscalar(tmp)
                                        % prepare value
                                        tmp = num2str(tmp);
                                        % communicate to hardware
                                        mydo(obj,sprintf('%dPA%s',iAx,tmp));
                                        % store value
                                        obj.p_Axis(iAx).(fn{i}) = str2double(tmp);
                                    else
                                        error(sprintf('%s:Input',mfilename),...
                                            '%s is expected to be a scalar float, please check input!',fn{i});
                                    end
                                case 'velocity'
                                    if isfloat(tmp) && isscalar(tmp) && abs(tmp) > 0
                                        if obj.Moving
                                            warning(sprintf('%s:Input',mfilename),['%s is moving, ',...
                                                'waiting for motion to stop before settings the ',...
                                                'velocity'],obj.Name);
                                            waitStop(obj);
                                        end
                                        % prepare value
                                        tmp = num2str(tmp);
                                        % communicate to hardware
                                        mydo(obj,sprintf('%dVA%s',iAx,tmp));
                                        % store value
                                        obj.p_Axis(iAx).(fn{i}) = str2double(tmp);
                                    else
                                        error(sprintf('%s:Input',mfilename),...
                                            '%s is expected to be a scalar float larger zero, please check input!',fn{i});
                                    end
                                case 'power'
                                    if islogical(tmp) && isscalar(tmp)
                                        % communicate to hardware
                                        if tmp
                                            mydo(obj,sprintf('%dMO',iAx,tmp));
                                        else
                                            mydo(obj,sprintf('%dMF',iAx,tmp));
                                        end
                                        % store value
                                        obj.p_Axis(iAx).(fn{i}) = tmp;
                                    else
                                        error(sprintf('%s:Input',mfilename),...
                                            '%s is expected to be a scalar logical, please check input!',fn{i});
                                    end
                                case 'unit'
                                    error(sprintf('%s:Input',mfilename), ['%s is interpreted by the hardware ',...
                                        'as a label only. As a consequence, all affected parameters, such as ',...
                                        'velocity and acceleration, need to be resend. Changing this setting ',...
                                        'is therefore disabled for now to avoid any related issue'],fn{i});
                                    % if ischar(tmp) && ismember(tmp,obj.UnitTable(:,2))
                                    %     [~, idx] = ismember(tmp,obj.UnitTable(:,2));
                                    %     % communicate to hardware
                                    %     mydo(obj,sprintf('%dSN%d',iAx,obj.UnitTable{idx,1}));
                                    %     % store value
                                    %     obj.p_Axis(iAx).(fn{i}) = tmp;
                                    % else
                                    %     error(sprintf('%s:Input',mfilename),...
                                    %         '%s is expected to be a single char, please check input!',fn{i});
                                    % end
                                otherwise
                                    error(sprintf('%s:Input',mfilename),...
                                        'Unknown or unchangeable axis setting ''%s'' for device of class ''%s''',fn{i},class(obj));
                            end
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
                        anynew = true;
                        switch fn{i}
                            case 'locked'
                                if islogical(tmp) && isscalar(tmp)
                                    % communicate to hardware
                                    mydo(obj,sprintf('LC%d',tmp));
                                    % store value
                                    obj.p_System.(fn{i}) = tmp;
                                else
                                    error(sprintf('%s:Input',mfilename),...
                                        '%s is expected to be a scalar logical, please check input!',fn{i});
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
        
        function out = get.Position(obj)
            out = NaN(size(obj.p_Axis));
            for i = 1:numel(out)
                out(i) = str2double(mydo(obj,sprintf('%dTP',i),1));
                obj.p_Axis(i).position = out(i);
            end
        end
        
        function       set.Position(obj,value)
            if isfloat(value) && numel(value) == numel(obj.p_Axis)
                for i = 1:numel(value)
                    mydo(obj,sprintf('%dPA%s',i,num2str(value(i))));
                    obj.p_Axis(i).position = value(i);
                end
            else
                error(sprintf('%s:Input',mfilename),...
                    'Position is expected to be a float with the position of each axis, please check input!');
            end
        end
        
        function out = get.Moving(obj)
            out = false(size(obj.p_Axis));
            for i = 1:numel(out)
                out(i) = ~logical(str2double(mydo(obj,sprintf('%dMD?',i),1)));
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
                str = obj.showInfo(true,true);
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
                fclose(obj.sobj);
            end
            delete(obj.sobj);
        end
        
        function S = saveobj(obj)
            % saveobj Supposed to be called by MATLAB's save function, stores settings of serial
            % connection and axis to allow for a recovery during the load processs
            
            S.Device  = obj.Device;
            S.Axis    = obj.Axis;
            S.System  = rmfield(obj.System,{'version'});
            S.Name    = obj.Name;
        end
        
        function resetController(obj)
            % resetController Resets the controller hardware including a reboot that takes up to 20s
            
            %
            % reset device, but note: seems to need a close and open afterwards
            mydo(obj,'RS');
            fclose(obj.sobj);
            % wait for 20 s, which should be the maximum time for a reboot according to the manual
            fprintf('%s: Waiting 20 seconds for hardware to reboot\n',obj.Name)
            pause(20.5);
            fopen(obj.sobj);
            obj.syncSystem;
            obj.syncAxis;
        end
        
        function reset(obj)
            % reset Resets device or rather the connection to the device, see also resetController
            
            %
            % disable any logging function
            obj.sobj.BytesAvailableFcn = '';
            %
            % open device
            if ~isequal(obj.sobj.Status,'open')
                fopen(obj.sobj);
            end
            %
            % flush input buffer
            flushData(obj);
            %
            % read NewportESP version and initialize the System property
            obj.p_System = orderfields(struct('version',mydo(obj,'VE?',1)));
            obj.p_System = readSystem(obj);
            %
            % initialize for three axis and read axis information
            obj.p_Axis = struct('position',{ 0 0 0 });
            obj.p_Axis = readAxis(obj);
            %
            % read status and extract current settings
            syncSystem(obj);
            syncAxis(obj);
            %
            % send newSettings event and reset data
            notify(obj,'newSettings');
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
        
        function varargout = syncSystem(obj)
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
        
        function varargout = syncAxis(obj,idxAx)
            % syncAxis Checks if axis settings (in class property Axis) match the status of
            % the hardware, which is returned as second ouput, the first output is true/false
            % whether the object was in sync, makes sure the class property is in sync
            
            if nargin < 2,
                idxAx = 1:numel(obj.p_Axis);
            elseif ~(isnumeric(idxAx) &&  min(round(idxAx)) > 0 && max(round(idxAx)) <= numel(obj.p_Axis))
                error(sprintf('%s:Input',mfilename),'Optional index is out opf bounds, please check!');
            end
            isOK  = true;
            idxAx = reshape(unique(round(idxAx)),1,[]);
            stat  = readAxis(obj,idxAx);
            fn    = fieldnames(stat);
            for i = 1:numel(idxAx)
                for k = 1:numel(fn)
                    if ~isequal(obj.p_Axis(idxAx(i)).(fn{k}),stat(i).(fn{k}))
                        warning(sprintf('%s:Check',mfilename),...
                            'Mismatch in setting ''%s'' for axis %d, correcting class property accordingly',fn{k},i);
                        obj.p_Axis(idxAx(i)).(fn{k}) = stat(i).(fn{k});
                        isOK                         = false;
                    end
                end
            end
            if nargout > 0, varargout = {isOK, stat}; end
        end
        
        function varargout = sync(obj)
            % sync Sync all properties that can be synced
            
            isOK    = syncSystem(obj);
            isOK(2) = syncAxis(obj);
            if nargout > 0, varargout = {all(isOK)}; end
        end
        
        function [isOK, errList] = errorMessage(obj,doMessage,delay)
            % errorMessage Checks for error messages and can print them to the command line
            % First return is true/false whether no error is found, second output is a cellstr with
            % available error messages (if any) as returned from the device
            %
            % Note: code avoids using mydo function to prevent any recursion, allows for the option
            % to suppress the output to the command line and an optional delay to wait for the
            % device to respond (i.e. required when the device waits for any motion stop)
            
            isOK    = false;
            doAgain = true;
            errList = {};
            counter = 1;
            if nargin < 2 || isempty(doMessage), doMessage = true; end
            if nargin < 3 || isempty(delay), delay = 5; end
            while doAgain
                fprintf(obj.sobj,'TB');
                nBytes = mywait(obj,2,delay);
                if nBytes < 1
                    warning(sprintf('%s:Reset',mfilename),['No data available from device ''%s'' ',...
                        'although an appropriate command ''%s'' was send to read the error buffer'],...
                        obj.Name,'TB')
                    errList{counter} = ''; %#ok<AGROW>
                else
                    errList{counter} = fgetl(obj.sobj); %#ok<AGROW>
                end
                if isempty(errList{counter}) || strcmp(errList{counter}(1),'0')
                    errList(counter) = []; %#ok<AGROW>
                    doAgain = false;
                end
                counter = counter + 1;
            end
            if numel(errList) > 0
                if doMessage
                    warning(sprintf('%s:Reset',mfilename),['''%s'' returned %d error(s), ',...
                        'see output to command line'],obj.Name,numel(errList));
                    for i = 1:numel(errList)
                        fprintf('%s, error %d: ''%s''\n',obj.Name,i,errList{i});
                    end
                end
            else
                isOK = true;
            end
        end
        
        function             home(obj,varargin)
            % home Moves all or given axes to its home position with current home method, wrapper
            % for homeGo
            
            homeGo(obj,varargin{:});
        end
        
        function homeGo(obj,iAx)
            % homeGo Moves all or given axes to its home position with current home method
            % The current home method is a hardware settings, check the manual for more information
            % and how to change it
            
            %
            % check and prepare input
            if nargin < 2 || isempty(iAx), iAx = 1:numel(obj.p_Axis); end
            assert(isnumeric(iAx) && min(round(iAx)) > 0 && max(round(iAx)) <= numel(obj.p_Axis),...
                'Given axis index is out of bound, please check!');
            iAx = reshape(unique(round(iAx)),1,[]);
            %
            % send individual command for each axis
            for i = iAx, mydo(obj,sprintf('%dOR',i)); end
        end
        
        function homeSet(obj,iAx)
            % homeSet Sets the current position as new home and origin position for all or given axes
            
            %
            % check and prepare input
            if nargin < 2 || isempty(iAx), iAx = 1:numel(obj.p_Axis); end
            assert(isnumeric(iAx) && min(round(iAx)) > 0 && max(round(iAx)) <= numel(obj.p_Axis),...
                'Given axis index is out of bound, please check!');
            iAx   = reshape(unique(round(iAx)),1,[]);
            if any(obj.Moving(iAx))
                error(sprintf('%s:Input',mfilename),['Axis is currently moving and a home ',...
                    'reset is aborted, please wait until axis is not moving anymore']);
            end
            %
            % send commands to device
            for i = iAx
                mydo(obj,sprintf('%dDH',i));
            end
        end
        
        function stop(obj,iAx)
            % stop Stops all or given axes motion in progress using deceleration rate programmed
            
            %
            % check and prepare input
            if nargin < 2 || isempty(iAx), iAx = 1:numel(obj.p_Axis); end
            assert(isnumeric(iAx) && min(round(iAx)) > 0 && max(round(iAx)) <= numel(obj.p_Axis),...
                'Given axis index is out of bound, please check!');
            iAx = reshape(unique(round(iAx)),1,[]);
            %
            % send individual command for each axis
            for i = iAx, mydo(obj,sprintf('%dST',i)); end
        end
        
        function stopNow(obj)
            % stopNow Aborts all axes motion using an emergency stop
            
            %
            % send command to device
            mydo(obj,'AB');
        end
        
        function waitStop(obj,iAx,delay)
            % waitStop Waits for all or given axes motion in progress before executing the next command
            
            %
            % check and prepare input
            if nargin < 2 || isempty(iAx), iAx = 1:numel(obj.p_Axis); end
            if nargin < 3 || isempty(delay), delay = 60; end
            assert(isnumeric(iAx) && min(round(iAx)) > 0 && max(round(iAx)) <= numel(obj.p_Axis),...
                'Given axis index is out of bound, please check!');
            iAx = reshape(unique(round(iAx)),1,[]);
            %
            % send individual command for each axis
            for i = iAx
                % run mydo with very long wait
                mydo(obj,sprintf('%dWS',i),0,delay);
            end
        end
        
        function             wait(obj,varargin)
            % wait Wrapper for waitStop
            
            waitStop(obj,varargin{:});
        end
        
        function move(obj,iAx,pos)
            % move Moves given axis to an absolute position
            % Similar to the Position property of the object, but allows to send only individual
            % commands to a specific axis
            
            %
            % check and prepare input
            if nargin < 2 || isempty(iAx), iAx = 1:numel(obj.p_Axis); end
            if nargin < 3 || isempty(pos), pos = 0; end
            assert(isnumeric(iAx) && min(round(iAx)) > 0 && max(round(iAx)) <= numel(obj.p_Axis),...
                'Given axis index is out of bound, please check!');
            iAx   = reshape(unique(round(iAx)),1,[]);
            assert(isfloat(pos) && (isscalar(pos) || numel(pos) == numel(iAx)),...
                'Given position is out of bound, please check!');
            if isscalar(pos), pos = repmat(pos,size(iAx)); end
            if any(obj.Moving(iAx))
                error(sprintf('%s:Input',mfilename),['Axis is currently moving and a relative ',...
                    'move is aborted, please wait until axis is not moving anymore']);
            end
            %
            % send commands to device
            for i = 1:numel(iAx)
                mydo(obj,sprintf('%dPA%s',iAx(i),num2str(pos(i))));
            end
        end
        
        function moveRelative(obj,iAx,pos)
            % moveRelative Moves given axis by a relative position
            
            %
            % check and prepare input
            if nargin < 2 || isempty(iAx), iAx = 1:numel(obj.p_Axis); end
            if nargin < 3 || isempty(pos), pos = 0; end
            assert(isnumeric(iAx) && min(round(iAx)) > 0 && max(round(iAx)) <= numel(obj.p_Axis),...
                'Given axis index is out of bound, please check!');
            iAx   = reshape(unique(round(iAx)),1,[]);
            assert(isfloat(pos) && (isscalar(pos) || numel(pos) == numel(iAx)),...
                'Given position is out of bound, please check!');
            if isscalar(pos), pos = repmat(pos,size(iAx)); end
            if any(obj.Moving(iAx))
                error(sprintf('%s:Input',mfilename),['Axis is currently moving and a relative ',...
                    'move is aborted, please wait until axis is not moving anymore']);
            end
            %
            % send commands to device
            for i = 1:numel(iAx)
                mydo(obj,sprintf('%dPR%s',iAx(i),num2str(pos(i))));
            end
        end
        
        function saveHardwareSettings(obj)
            % saveSettings Saves hardware settings to non-volatile flash memory on device
            
            mydo(obj,'SM');
        end
        
        function varargout = showInfo(obj,noPrint,noUpdate)
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
                syncAxis(obj);
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
            if obj.System.locked
                out{end+1} = sprintf('%sKeypad is currently locked',sep);
            else
                out{end+1} = sprintf('%sKeypad is currently unlocked',sep);
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
        
        function out = mydo(obj,cmd,len,delay)
            % mydo Sends char command cmd to serial device and expects len number of output lines in
            % char representation, returns a cellstr if len is greater than 1, otherwise a char
            
            narginchk(2,4);
            if nargin < 3 || isempty(len), len   = 0; end
            if nargin < 4 || isempty(delay), delay = 5; end
            %
            % check if input buffer is empty
            [isData, data] = flushData(obj);
            if isData, warning(sprintf('%s:Run',mfilename),['Bytes available for device ''%s'', ',...
                    'which is not expected. Cleared bytes (including line feed and carriage return):\n%s'],...
                    obj.Name,char(reshape(data,1,[])));
            end
            %
            % run command
            out = '';
            fprintf(obj.sobj,cmd);
            if len > 0
                out = cell(len,1);
                for i = 1:len
                    nBytes = mywait(obj,2,delay);
                    if nBytes < 1
                        warning(sprintf('%s:Reset',mfilename),['No data available from device ''%s'' ',...
                            'although an appropriate command ''%s'' was send, returning empty char'],...
                            obj.Name,cmd)
                        out{i} = '';
                    else
                        out{i} = fgetl(obj.sobj);
                    end
                end
                if len == 1, out = out{1}; end
            end
            [isData, data] = flushData(obj);
            if isData, warning(sprintf('%s:Reset',mfilename),['Bytes available for device ''%s'', ',...
                    'which is not expected after command ''%s''. Cleared bytes: %s'],...
                    obj.Name,num2str(data),cmd);
            end
            % check error buffer
            [isOK, errList] = errorMessage(obj,false,delay);
            if ~isOK
                warning(sprintf('%s:Reset',mfilename),['''%s'' returned %d errors after ',...
                    'executing command ''%s'', see output to command line'],...
                    obj.Name,numel(errList),cmd);
                for i = 1:numel(errList)
                    fprintf('%s, error %d: ''%s''\n',obj.Name,i,errList{i});
                end
            end
        end
    end
    
    methods (Access = private, Hidden = false)
        function out = readSystem(obj)
            % readSystem Reads all supported system settings from hardware and returns settings structure
            
            out.locked             = logical(str2double(mydo(obj,'LC?',1)));
            out.version            = mydo(obj,'VE?',1);
            out.deviceAddress      = str2double(mydo(obj,'SA?',1));
            % controller bytes are returned as ASCII char
            out.controllerStatus   = dec2bin(mydo(obj,'TS',1),8);
            out.controllerActivity = dec2bin(mydo(obj,'TX',1),8);
            % hardware status is returned as two hex values, e.g. '18000200H, 702H', where the
            % trailing H indicates that it is a hex value
            tmp                = NewportESP.strHEX2BIN(strsplit(mydo(obj,'PH',1),','),32);
            out.hardwareStatus = cat(1,tmp{:});
            % ESP and system config are returned as a single hex values
            out.espConfig    = NewportESP.strHEX2BIN(mydo(obj,'ZU',1),32);
            out.systemConfig = NewportESP.strHEX2BIN(mydo(obj,'ZZ?',1),32);
            % order output
            out = orderfields(out);
        end
        
        function out = readAxis(obj,idxAx)
            % readAxis Reads all supported axis settings from hardware and returns settings structure
            
            if nargin < 2, idxAx = 1:numel(obj.p_Axis); end
            out = struct;
            for iAx = 1:numel(idxAx)
                out(iAx).acceleration    = str2double(mydo(obj,sprintf('%dAC?',idxAx(iAx)),1));
                out(iAx).deceleration    = str2double(mydo(obj,sprintf('%dAG?',idxAx(iAx)),1));
                out(iAx).emergencyDec    = str2double(mydo(obj,sprintf('%dAE?',idxAx(iAx)),1));
                out(iAx).velocity        = str2double(mydo(obj,sprintf('%dVA?',idxAx(iAx)),1));
                out(iAx).position        = str2double(mydo(obj,sprintf('%dTP',idxAx(iAx)),1));
                out(iAx).moving          = ~logical(str2double(mydo(obj,sprintf('%dMD?',idxAx(iAx)),1)));
                out(iAx).power           = logical(str2double(mydo(obj,sprintf('%dMO?',idxAx(iAx)),1)));
                out(iAx).model           = mydo(obj,sprintf('%dID?',idxAx(iAx)),1);
                % return values for the following configs are returned as hex values
                out(iAx).amplifierConfig = NewportESP.strHEX2BIN(mydo(obj,sprintf('%dZA?',idxAx(iAx)),1),32);
                out(iAx).feedbackConfig  = NewportESP.strHEX2BIN(mydo(obj,sprintf('%dZB?',idxAx(iAx)),1),32);
                out(iAx).followingConfig = NewportESP.strHEX2BIN(mydo(obj,sprintf('%dZF?',idxAx(iAx)),1),32);
                out(iAx).emergencyConfig = NewportESP.strHEX2BIN(mydo(obj,sprintf('%dZE?',idxAx(iAx)),1),32);
                out(iAx).limitSConfig    = NewportESP.strHEX2BIN(mydo(obj,sprintf('%dZS?',idxAx(iAx)),1),32);
                out(iAx).limitHConfig    = NewportESP.strHEX2BIN(mydo(obj,sprintf('%dZH?',idxAx(iAx)),1),32);
                % unit
                tmp        = round(str2double(mydo(obj,sprintf('%dSN?',idxAx(iAx)),1)));
                [isOK,idx] = ismember(tmp,cell2mat(obj.UnitTable(:,1)));
                if ~isOK
                    error(sprintf('%s:Input',mfilename),['%s: Unknown unit value %d for axis %d, ',...
                        'please check!'],obj.Name,tmp,idxAx(iAx));
                else
                    out(iAx).unit = obj.UnitTable{idx,2};
                end
                % type
                tmp        = round(str2double(mydo(obj,sprintf('%dQM?',idxAx(iAx)),1)));
                [isOK,idx] = ismember(tmp,cell2mat(obj.TypeTable(:,1)));
                if ~isOK
                    error(sprintf('%s:Input',mfilename),['%s: Unknown motor type %d for axis %d, ',...
                        'please check!'],obj.Name,tmp,idxAx(iAx));
                else
                    out(iAx).type = obj.TypeTable{idx,2};
                end
                % limit
                tmp    = str2double(mydo(obj,sprintf('%dSL?',idxAx(iAx)),1));
                tmp(2) = str2double(mydo(obj,sprintf('%dSR?',idxAx(iAx)),1));
                out(iAx).limit = reshape(tmp,1,[]);
                
            end
            out = orderfields(out);
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
        function out = strHEX2BIN(in,n)
            % strHEX2BIN Converts the string of hex value to the binary representation with n bits as string
            % A last char 'H' in the input to indicate a hex value is removed automatically
            
            % convert cellstr
            if iscellstr(in)
                if nargin > 1
                    out = cellfun(@(in) NewportESP.strHEX2BIN(in,n),in,'un',false);
                else
                    out = cellfun(@(in) NewportESP.strHEX2BIN(in),in,'un',false);
                end
                return;
            end
            % convert single string
            in = strtrim(in);
            if strcmpi(in(end),'h'), in = in(1:end-1); end
            if nargin > 1
                out = dec2bin(hex2dec(in),n);
            else
                out = dec2bin(hex2dec(in));
            end
        end
        
        function obj = loadobj(S)
            %loadobj Loads object and tries to re-connect to hardware
            
            try
                % only try to set settings that can be changed
                axisSet   = {'power','position'};
                systemSet = {'locked'};
                % try to connect
                for n = 1:numel(S)
                    S(n).Device.showInfoOnConstruction = false;
                    % create object
                    obj(n) = NewportESP(S(n).Device); %#ok<AGROW>
                    % copy name
                    obj(n).Name = S(n).Name; %#ok<AGROW>
                    % copy system settings
                    for k = 1:numel(systemSet)
                        for l = 1:numel(obj(n).System)
                            obj(n).System(l).(systemSet{k}) = S(n).System(l).(systemSet{k});
                        end
                    end
                    % copy axis settings
                    for k = 1:numel(axisSet)
                        for l = 1:numel(obj(n).Axis)
                            obj(n).Axis(l).(axisSet{k}) = S(n).Axis(l).(axisSet{k});
                        end
                    end
                    showInfo(obj(n));
                end
            catch err
                warning(sprintf('%s:Input',mfilename),...
                    'Device could not be re-connected during load process: %s',err.getReport);
            end
        end
    end
end
