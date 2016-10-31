classdef BNC575 < handle
    %BNC575 Class describing the serial connection to the BNC575 by Berkeley Nucleonics Corp.
    %
    % The class allows to connect to the device and configure the sytem and channel timers, send a
    % software trigger, etc. The class supports the firmware extensions for dual trigger and
    % increment modes.
    %
    % Implementation notes:
    %   * The System, T0 and Channel properties keep a copy of the hardware settings in the MATLAB
    %     object and do not sync with the hardware (slows down due to the many commands that need to
    %     be transferred via a serial connection). The functions syncSystem, syncT0 and syncChannel
    %     can be used to force a sync. The most important values can be accessed in sync by using
    %     their root properties, i.e. obj.T0.run can be accessed also by obj.Running, where the
    %     later directly reads from the hardware. The following values are available in direct sync:
    %                obj.System.live: obj.Live
    %              obj.System.locked: obj.Locked
    %                     obj.T0.run: obj.Running
    %            obj.T0.countTrigger: obj.CountTrigger
    %               obj.T0.countGate: obj.CountGate
    %         obj.Channel(i).enabled: obj.Enabled(i)
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
        %                                                 operations to and from the hardware (can
        %                                                 be changed)
        Device
        % System System settings of the BNC575 hardware (structure)
        %
        % This property holds system settings of and information on the BNC575 device. The fields of
        % the structure are:
        % brightness: double scalar for the brightness of the display between 0 and 4
        %       live: true/false whether the front display is updated with each serial command (slows down)
        %      light: true/false whether the display and front panel lights are enabled
        %     locked: true/false whether the keypad is locked
        %     status: true/false whether the machine is armed and/or generating pulses (true) or
        %             if the machine has been disarmed (false) (read-only)
        %    version: the version of the software on the device (read-only)
        %     volume: double scalar for the volume of the beep between 0 and 100
        System
        % T0 Settings of the sytem pulse
        %
        % This property holds system pulse settings. The fields of the structure are:
        %   burstCounter: double scalar for the burst counter
        %        clockIN: double scalar from [0 10 20 25 40 50 80 100] for the source of the rate
        %                 generator, where 0 means internal system clock and anything else refers to
        %                 an external source from 10MHz to 100MHz
        %       clockOUT: double scalar from [0 10 11 12 14 16 20 25 33 50 100] for the external
        %                 clock output, where 0 means T0 pulses and anything else refers to 10MHz to
        %                 100MHz TTL output
        %        counter: true/false whether the counter function is enabled
        %      countGate: double scalar for the gate counter (mainly read-only, set to empty or 0 for reset)
        %   countTrigger: double scalar for the trigger counter (mainly read-only, set to empty or 0 for reset)
        %          cycle: double scalar for number of cycle in duty cycle increment mode (if supported by device)
        %           mode: char 'normal', 'single', 'burst' or 'cycle' ('incBurst' and 'incCycle' for increment modes) for the T0 mode
        %      gateLevel: double scalar for the gate threshold in V with a range of 0.20 to 15
        %      gateLogic: char 'high' or 'low' for the gate logic
        %       gateMode: char 'disabled', pulse', 'output' or 'channel' for global gate mode
        %     offCounter: double scalar for the off counter
        %         period: double scalar for the T0 period in s
        %   pulseCounter: double scalar for the pulse counter
        %            run: true/false for the state of the run/stop button of the device
        %    triggerEdge: char 'rising' or 'falling' for the trigger edge
        %   triggerLevel: double scalar for the trigger threshold in V with a range of 0.20 to 15
        %    triggerMode: char 'enabled', 'disabled' or 'dual' for the trigger mode
        T0
        % Channel Channels of the BNC575 device (structure)
        %
        % This property is a structure array with information and settings for each channel of the
        % device. The fields of the structure array are:
        %      burstCounter: double scalar for the burst counter
        %             delay: double scalar for the pulse delay in s of the channel
        %           enabled: true/false whether the channel output is enabled
        %         gateLogic: char 'high' or 'low' for the gate logic of the channel
        %          gateMode: char 'disabled', 'pulse' or 'output' for the gate mode of the channel
        %          incDelay: double scalar for the pulse increment delay in s of the channel
        %          incWidth: double scalar for the pulse increment width in s of the channel
        %              mode: char 'normal', 'single', 'burst' or 'cycle' for the channel mode
        %               mux: double scalar from 0 to 255 for the multiplexer of the channel
        %        offCounter: double scalar for the off counter
        %   outputAmplitude: double scalar for the adjustable output voltage in V with a range of 2.0 to 20
        %        outputMode: char 'TTL' or 'adjustable' for the output mode of the channel
        %          polarity: char 'normal', complement' or 'inverted' for the polarity of the channel
        %      pulseCounter: double scalar for the pulse counter
        %              sync: double scalar from [0 1 2 ... n] for the sync source of the channel
        %      triggerInput: char 'trig' or 'gate' for the trigger input in case the device supports dual trigger
        %       waitCounter: double scalar for the delay counter
        %             width: double scalar for the pulse width in s of the channel
        Channel
        % CountTrigger Synced version of obj.T0.countTrigger (see implementation notes at the top)
        CountTrigger
        % CountGate Synced version of obj.T0.countGate (see implementation notes at the top)
        CountGate
        % Enabled Synced version of obj.Channel.enabled (see implementation notes at the top)
        Enabled
        % Live Synced version of obj.System.live (see implementation notes at the top)
        Live
        % Locked Synced version of obj.System.locked (see implementation notes at the top)
        Locked
        % Running Synced version of obj.T0.run (see implementation notes at the top)
        Running
        % isGUI True/false whether the GUI is currently open (logical)
        isGUI
    end
    
    properties (GetAccess = public, SetAccess = protected, Dependent = true)
        % Status Status of the serial device (structure)
        %
        % This property holds all serial properties that can change over time (see MATLAB's
        % documentation). The fields of the structure are:
        %   <all varying properties of a serial device>: see MATLAB's documentation
        Status
    end
    
    properties (GetAccess = protected, SetAccess = protected, Transient = true)
        % sobj Serial device, i.e. the actual connection to the hardware (serial object)
        sobj
        % supportDT true/false whether the model supports dual trigger
        supportDT
        % supportIM true/false whether the model supports increment modes
        supportIM
        % p_Device Storage for Device
        p_Device
        % p_System Storage for System
        p_System
        % p_T0 Storage for T0
        p_T0
        % p_Channel Storage for Channel
        p_Channel
        % p_gui Storage for GUI elements (struct)
        %
        % This property is a structure to hold figure objects, etc.
        p_gui = struct
    end
    
    properties (GetAccess = public, SetAccess = public, Transient = true)
        % Name A short name for the device (char)
        Name = 'BNC575';
        % UserData Userdata linked to the device (arbitrary
        UserData = [];
    end
    
    properties (Constant = true, Hidden = true)
        % ErrorTable Conversion from error index to text message
        ErrorTable = {
            1 'Incorrect prefix, i.e. no colon or star to start command'
            2 'Missing command keyword'
            3 'Invalid command keyword'
            4 'Missing parameter'
            5 'Invalid parameter'
            6 'Query only, command needs a question mark'
            7 'Invalid query, command does not have a query form'
            8 'Command unavailable in current system state'
            };
        % ModeTable Allowed modes of the system pulse and the command send to the device
        ModeTable = {
            'normal'   'NORM'
            'single'   'SING'
            'burst'    'BURS'
            'cycle'    'DCYC'
            'incburst' 'BINCR'
            'inccycle' 'DCINCR'
            };
        % TriggerModeTable Allowed modes of the gate and the command send to the device
        TriggerModeTable = {
            'enabled'  'TRIG'
            'disabled' 'DIS'
            'dual'     'DUAL'
            };
        % TriggerInputTable Allowed inputs for the trigger (part of dual trigger option) the command send to the device
        TriggerInputTable = {
            'trig'     'TRIG'
            'gate'     'GAT'
            };
        % TriggerEdgeTable Allowed logic of the trigger and the command send to the device
        TriggerEdgeTable = {
            'rising'  'RIS'
            'falling' 'FALL'
            };
        % GateModeTable Allowed modes of the gate and the command send to the device
        GateModeTable = {
            'disabled' 'DIS'
            'pulse'    'PULS'
            'output'   'OUTP'
            'channel'  'CHAN'
            };
        % GateLogicTable Allowed logic of the gate and the command send to the device
        GateLogicTable = {
            'low'  'LOW'
            'high' 'HIGH'
            };
        % ChannelTable Channel numbers and their string representation
        ChannelTable = {
            0 'T0'
            1 'CHA'
            2 'CHB'
            3 'CHC'
            4 'CHD'
            5 'CHE'
            6 'CHF'
            7 'CHG'
            8 'CHH'
            };
        % ChannelPolarity Allowed polarity of a channel and the command send to the device
        ChannelPolarity = {
            'normal'     'NORM'
            'complement' 'COMP'
            'inverted'   'INV'
            };
        % ChannelOutputMode Allowed output modes of a channel and the command send to the device
        ChannelOutputMode = {
            'ttl'        'TTL'
            'adjustable' 'ADJ'
            };
        % ChannelGateMode Allowed gate modes of a channel and the command send to the device
        ChannelGateMode = {
            'disabled' 'DIS'
            'pulse'    'PULS'
            'output'   'OUTP'
            };
        % ChannelModeTable Allowed modes of a channel and the command send to the device
        ChannelModeTable = {
            'normal' 'NORM'
            'single' 'SING'
            'burst'  'BURS'
            'cycle'  'DCYC'
            };
    end
    
    %% Events
    events
        % newSettings Notify when settings are changed
        newSettings
    end
    
    %% Constructor and SET/GET
    methods
        function obj = BNC575(varargin)
            % BNC575 Creates object that links to the device
            %
            % Options are supposed to be given in <propertyname> <propertyvalue> style
            
            %
            % get input with input parser, where inputs are mostly properties listed in MATLAB's
            % documentation on serial objects that can be changed, i.e. are not always read-only
            tmp               = inputParser;
            tmp.StructExpand  = true;
            tmp.KeepUnmatched = false;
            % communication properties
            tmp.addParameter('BaudRate', 38400, ...
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
            tmp.addParameter('Delay', 0.05, ...
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
                        'Port ''%s'' is in principle available at your system, but seems to be in use, see output of instrhwinfo(''serial'')',tmp.Port);
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
            if ~(isstruct(value) && isscalar(value) && all(ismember(fieldnames(value),fieldnames(obj.p_System))))
                error(sprintf('%s:Input',mfilename),...
                    'Expected a scalar structure with system settings as input, please check input!');
            else
                curValue = obj.p_System;
                fn       = fieldnames(value);
                anynew   = false;
                for i = 1:numel(fn)
                    tmp    = value.(fn{i});
                    if ~isequal(tmp,curValue.(fn{i})) % only process if it changed
                        anynew = true;
                        switch fn{i}
                            case 'brightness'
                                if isnumeric(tmp) && isscalar(tmp) && tmp >= 0 && tmp <= 4
                                    % prepare value
                                    tmp = round(tmp);
                                    % communicate to hardware
                                    mydo(obj,sprintf(':DISP:BRIG %d',tmp));
                                    % store value
                                    obj.p_System.(fn{i}) = tmp;
                                    % update keypad lock, since it may change
                                    tmp2                = logical(str2double(mydo(obj,':SYST:KLOC?',1)));
                                    obj.p_System.locked = tmp2;
                                    value.locked        = tmp2;
                                else
                                    error(sprintf('%s:Input',mfilename),...
                                        '%s is expected to be a scalar numeric value between 0 and 4, please check input!',fn{i});
                                end
                            case 'live'
                                obj.Live   = tmp;
                                value.live = obj.p_System.live;
                            case 'light'
                                if islogical(tmp) && isscalar(tmp)
                                    % communicate to hardware
                                    mydo(obj,sprintf(':DISP:ENABLE %d',tmp));
                                    % store value
                                    obj.p_System.(fn{i}) = tmp;
                                    % update keypad lock, since it may change
                                    tmp2                = logical(str2double(mydo(obj,':SYST:KLOC?',1)));
                                    obj.p_System.locked = tmp2;
                                    value.locked        = tmp2;
                                else
                                    error(sprintf('%s:Input',mfilename),...
                                        '%s is expected to be a scalar logical, please check input!',fn{i});
                                end
                            case 'locked'
                                obj.Locked   = tmp;
                                value.locked = obj.p_System.locked;
                            case 'volume'
                                if isnumeric(tmp) && isscalar(tmp) && tmp >= 0 && tmp <= 100
                                    % prepare value
                                    tmp = round(tmp);
                                    % communicate to hardware
                                    mydo(obj,sprintf(':SYST:BEEP:VOL %d',tmp));
                                    if tmp > 0
                                        mydo(obj,':SYST:BEEP:STAT 1');
                                    else
                                        mydo(obj,':SYST:BEEP:STAT 0');
                                    end
                                    % store value
                                    obj.p_System.(fn{i}) = tmp;
                                else
                                    error(sprintf('%s:Input',mfilename),...
                                        '%s is expected to be a scalar numeric value between 0 and 100, please check input!',fn{i});
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
        
        function out = get.T0(obj)
            
            out = obj.p_T0;
        end
        
        function       set.T0(obj,value)
            
            % check if input is given as a structure, but only allow for changing specific settings
            if ~(isstruct(value) && isscalar(value) && all(ismember(fieldnames(value),fieldnames(obj.p_T0))))
                error(sprintf('%s:Input',mfilename),...
                    'Expected a scalar structure with settings for the sytem pulse T0 as input, please check input!');
            else
                curValue = obj.p_T0;
                fn       = fieldnames(value);
                anynew   = false;
                for i = 1:numel(fn)
                    tmp    = value.(fn{i});
                    if ~isequal(tmp,curValue.(fn{i})) % only process if it changed
                        anynew = true;
                        switch fn{i}
                            case 'run'
                                obj.Running = tmp;
                                value.run   = obj.p_T0.run;
                            case 'counter'
                                if islogical(tmp) && isscalar(tmp)
                                    % communicate to hardware
                                    mydo(obj,sprintf(':PULS0:COUN:STAT %d',tmp));
                                    % store value
                                    obj.p_T0.(fn{i}) = tmp;
                                else
                                    error(sprintf('%s:Input',mfilename),...
                                        '%s is expected to be a scalar logical, please check input!',fn{i});
                                end
                            case 'countTrigger'
                                obj.CountTrigger   = tmp;
                                value.countTrigger = obj.p_T0.countTrigger;
                            case 'countGate'
                                obj.CountGate   = tmp;
                                value.countGate = obj.p_T0.countGate;
                            case 'cycle'
                                if ~obj.supportIM
                                    error(sprintf('%s:Input',mfilename),...
                                        'Increment options are not supported by device, please check!');
                                elseif isnumeric(tmp) && isscalar(tmp) && tmp > 0
                                    % prepare value
                                    tmp = round(tmp);
                                    % communicate to hardware
                                    mydo(obj,sprintf(':PULS0:CYCL %d',tmp));
                                    % store value
                                    obj.p_T0.(fn{i}) = tmp;
                                else
                                    error(sprintf('%s:Input',mfilename),...
                                        '%s is expected to be a double scalar larger or equal to zero, please check input!',fn{i});
                                end
                            case 'period'
                                if isnumeric(tmp) && isscalar(tmp) && tmp >= 100e-9 && tmp <= 5000
                                    % prepare value
                                    tmp = sprintf('%e',tmp);
                                    % communicate to hardware
                                    mydo(obj,sprintf(':PULS0:PER %s',tmp));
                                    % store value
                                    obj.p_T0.(fn{i}) = str2double(tmp);
                                else
                                    error(sprintf('%s:Input',mfilename),...
                                        '%s is expected to be a double scalar between 100e-9 and 5000, please check input!',fn{i});
                                end
                            case 'mode'
                                if ischar(tmp) && ismember(lower(tmp),obj.ModeTable(:,1))
                                    tmp      = lower(tmp);
                                    [~, idx] = ismember(tmp,obj.ModeTable(:,1));
                                    if ~obj.supportIM && ismember(obj.ModeTable{idx,1},{'incburst' 'inccycle'})
                                        error(sprintf('%s:Input',mfilename),...
                                            'Increment options are not supported by device, please check!');
                                    end
                                    % communicate to hardware
                                    mydo(obj,sprintf(':PULS0:MOD %s',obj.ModeTable{idx,2}));
                                    % store value
                                    obj.p_T0.(fn{i}) = tmp;
                                else
                                    error(sprintf('%s:Input',mfilename),...
                                        '%s is expected to be a single char, please check input!',fn{i});
                                end
                            case 'burstCounter'
                                if isnumeric(tmp) && isscalar(tmp) && tmp >= 1 && tmp <= 9999999
                                    % prepare value
                                    tmp = round(tmp);
                                    % communicate to hardware
                                    mydo(obj,sprintf(':PULS0:BCO %d',tmp));
                                    % store value
                                    obj.p_T0.(fn{i}) = tmp;
                                else
                                    error(sprintf('%s:Input',mfilename),...
                                        '%s is expected to be a double scalar between 1 and 9,999,999, please check input!',fn{i});
                                end
                            case 'pulseCounter'
                                if isnumeric(tmp) && isscalar(tmp) && tmp >= 1 && tmp <= 9999999
                                    % prepare value
                                    tmp = round(tmp);
                                    % communicate to hardware
                                    mydo(obj,sprintf(':PULS0:PCO %d',tmp));
                                    % store value
                                    obj.p_T0.(fn{i}) = tmp;
                                else
                                    error(sprintf('%s:Input',mfilename),...
                                        '%s is expected to be a double scalar between 1 and 9,999,999, please check input!',fn{i});
                                end
                            case 'offCounter'
                                if isnumeric(tmp) && isscalar(tmp) && tmp >= 1 && tmp <= 9999999
                                    % prepare value
                                    tmp = round(tmp);
                                    % communicate to hardware
                                    mydo(obj,sprintf(':PULS0:OCO %d',tmp));
                                    % store value
                                    obj.p_T0.(fn{i}) = tmp;
                                else
                                    error(sprintf('%s:Input',mfilename),...
                                        '%s is expected to be a double scalar between 1 and 9,999,999, please check input!',fn{i});
                                end
                            case 'clockIN'
                                if isnumeric(tmp) && isscalar(tmp) && ismember(tmp,[0 10 20 25 40 50 80 100])
                                    % communicate to hardware
                                    switch tmp
                                        case 0
                                            str = 'SYS';
                                        otherwise
                                            str = sprintf('EXT%d',tmp);
                                    end
                                    mydo(obj,sprintf(':PULS0:ICL %s',str));
                                    % store value
                                    obj.p_T0.(fn{i}) = tmp;
                                else
                                    error(sprintf('%s:Input',mfilename),...
                                        '%s is expected to be a double scalar from [0 10 20 25 40 50 80 100], please check input!',fn{i});
                                end
                            case 'clockOUT'
                                if isnumeric(tmp) && isscalar(tmp) && ismember(tmp,[0 10 11 12 14 16 20 25 33 50 100])
                                    % communicate to hardware
                                    switch tmp
                                        case 0
                                            str = 'TO';
                                        otherwise
                                            str = sprintf('%d',tmp);
                                    end
                                    mydo(obj,sprintf(':PULS0:OCL %s',str));
                                    % store value
                                    obj.p_T0.(fn{i}) = tmp;
                                else
                                    error(sprintf('%s:Input',mfilename),...
                                        '%s is expected to be a double scalar from [0 10 11 12 14 16 20 25 33 50 100], please check input!',fn{i});
                                end
                            case 'gateMode'
                                if ischar(tmp) && ismember(lower(tmp),obj.GateModeTable(:,1))
                                    tmp      = lower(tmp);
                                    [~, idx] = ismember(tmp,obj.GateModeTable(:,1));
                                    % communicate to hardware
                                    mydo(obj,sprintf(':PULS0:GAT:MOD %s',obj.GateModeTable{idx,2}));
                                    % store value
                                    obj.p_T0.(fn{i}) = tmp;
                                else
                                    error(sprintf('%s:Input',mfilename),...
                                        '%s is expected to be a single char, please check input!',fn{i});
                                end
                            case 'gateLogic'
                                if ischar(tmp) && ismember(lower(tmp),obj.GateLogicTable(:,1))
                                    tmp      = lower(tmp);
                                    [~, idx] = ismember(tmp,obj.GateLogicTable(:,1));
                                    % communicate to hardware
                                    mydo(obj,sprintf(':PULS0:GAT:LOG %s',obj.GateLogicTable{idx,2}));
                                    % store value
                                    obj.p_T0.(fn{i}) = tmp;
                                else
                                    error(sprintf('%s:Input',mfilename),...
                                        '%s is expected to be a single char, please check input!',fn{i});
                                end
                            case 'gateLevel'
                                if isnumeric(tmp) && isscalar(tmp) && tmp >= 0.2 && tmp <= 15
                                    % prepare value
                                    tmp = sprintf('%.2f',tmp);
                                    % communicate to hardware
                                    mydo(obj,sprintf(':PULS0:GAT:LEV %s',tmp));
                                    % store value
                                    obj.p_T0.(fn{i}) = str2double(tmp);
                                else
                                    error(sprintf('%s:Input',mfilename),...
                                        '%s is expected to be a double scalar between 0.20 and 15, please check input!',fn{i});
                                end
                            case 'triggerMode'
                                if ischar(tmp) && ismember(lower(tmp),obj.TriggerModeTable(:,1))
                                    tmp      = lower(tmp);
                                    [~, idx] = ismember(tmp,obj.TriggerModeTable(:,1));
                                    if ~obj.supportDT && strcmp(obj.TriggerModeTable{idx,1},'dual')
                                        error(sprintf('%s:Input',mfilename),...
                                            'Dual trigger options are not supported by device, please check!');
                                    end
                                    % communicate to hardware
                                    mydo(obj,sprintf(':PULS0:TRIG:MOD %s',obj.TriggerModeTable{idx,2}));
                                    % store value
                                    obj.p_T0.(fn{i}) = tmp;
                                else
                                    error(sprintf('%s:Input',mfilename),...
                                        '%s is expected to be a single char, please check input!',fn{i});
                                end
                            case 'triggerEdge'
                                if ischar(tmp) && ismember(lower(tmp),obj.TriggerEdgeTable(:,1))
                                    tmp      = lower(tmp);
                                    [~, idx] = ismember(tmp,obj.TriggerEdgeTable(:,1));
                                    % communicate to hardware
                                    mydo(obj,sprintf(':PULS0:TRIG:EDG %s',obj.TriggerEdgeTable{idx,2}));
                                    % store value
                                    obj.p_T0.(fn{i}) = tmp;
                                else
                                    error(sprintf('%s:Input',mfilename),...
                                        '%s is expected to be a single char, please check input!',fn{i});
                                end
                            case 'triggerLevel'
                                if isnumeric(tmp) && isscalar(tmp) && tmp >= 0.2 && tmp <= 15
                                    % prepare value
                                    tmp = sprintf('%.2f',tmp);
                                    % communicate to hardware
                                    mydo(obj,sprintf(':PULS0:TRIG:LEV %s',tmp));
                                    % store value
                                    obj.p_T0.(fn{i}) = str2double(tmp);
                                else
                                    error(sprintf('%s:Input',mfilename),...
                                        '%s is expected to be a double scalar between 0.20 and 15, please check input!',fn{i});
                                end
                            otherwise
                                error(sprintf('%s:Input',mfilename),...
                                    'Unknown or unchangeable system pulse setting ''%s'' for device of class ''%s''',fn{i},class(obj));
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
            if ~(isstruct(value) && numel(value) == numel(obj.p_Channel) && all(ismember(fieldnames(value),fieldnames(obj.p_Channel))))
                error(sprintf('%s:Input',mfilename),...
                    'Expected a structure array with settings for each channel as input, please check input!');
            else
                fn     = fieldnames(value);
                anynew = false;
                for iCH = 1:numel(obj.p_Channel)  % loop over channels
                    for i = 1:numel(fn)           % loop over settings
                        tmp = value(iCH).(fn{i}); % get value of current setting
                        if ~isequal(tmp,obj.p_Channel(iCH).(fn{i})) % only process if it changed
                            anynew = true;
                            switch fn{i}
                                case 'burstCounter'
                                    if isnumeric(tmp) && isscalar(tmp) && tmp >= 1 && tmp <= 9999999
                                        % prepare value
                                        tmp = round(tmp);
                                        % communicate to hardware
                                        mydo(obj,sprintf(':PULS%d:BCO %d',iCH,tmp));
                                        % store value
                                        obj.p_Channel(iCH).(fn{i}) = tmp;
                                    else
                                        error(sprintf('%s:Input',mfilename),...
                                            '%s is expected to be a double scalar between 1 and 9,999,999, please check input!',fn{i});
                                    end
                                case 'delay'
                                    if isnumeric(tmp) && isscalar(tmp) && tmp >= -999.99999999975 && tmp <= 999.99999999975
                                        % prepare value
                                        tmp = sprintf('%.11f',tmp);
                                        % communicate to hardware
                                        mydo(obj,sprintf(':PULS%d:DEL %s',iCH,tmp));
                                        % store value
                                        obj.p_Channel(iCH).(fn{i}) = str2double(tmp);
                                    else
                                        error(sprintf('%s:Input',mfilename),...
                                            '%s is expected to be a double scalar between  -999.99999999975 and 999.99999999975, please check input!',fn{i});
                                    end
                                case 'incDelay'
                                    if ~obj.supportIM
                                        error(sprintf('%s:Input',mfilename),...
                                            'Increment options are not supported by device, please check!');
                                    elseif isnumeric(tmp) && isscalar(tmp)
                                        % prepare value
                                        if abs(tmp) >= 10e-9
                                            tmp = sprintf('%.11f',tmp);
                                        else
                                            if abs(tmp) > eps
                                                warning(sprintf('%s:Input',mfilename),...
                                                    'A value for %s with an absolute value smaller than 10e-9 disables the feature on the device, please check!',fn{i});
                                            end
                                            tmp = '0';
                                        end
                                        % communicate to hardware
                                        mydo(obj,sprintf(':PULS%d:IDEL %s',iCH,tmp));
                                        % store value
                                        obj.p_Channel(iCH).(fn{i}) = str2double(tmp);
                                    else
                                        error(sprintf('%s:Input',mfilename),...
                                            '%s is expected to be a double scalar with an absolute value larger than or equal to 10e-9, please check input!',fn{i});
                                    end
                                case 'incWidth'
                                    if ~obj.supportIM
                                        error(sprintf('%s:Input',mfilename),...
                                            'Increment options are not supported by device, please check!');
                                    elseif isnumeric(tmp) && isscalar(tmp) && abs(tmp) >= 10e-9
                                        % prepare value
                                        if abs(tmp) >= 10e-9
                                            tmp = sprintf('%.11f',tmp);
                                        else
                                            if abs(tmp) > eps
                                                warning(sprintf('%s:Input',mfilename),...
                                                    'A value for %s with an absolute value smaller than 10e-9 disables the feature on the device, please check!',fn{i});
                                            end
                                            tmp = '0';
                                        end
                                        % communicate to hardware
                                        mydo(obj,sprintf(':PULS%d:IWID %s',iCH,tmp));
                                        % store value
                                        obj.p_Channel(iCH).(fn{i}) = str2double(tmp);
                                    else
                                        error(sprintf('%s:Input',mfilename),...
                                            '%s is expected to be a double scalar with an absolute value larger than or equal to 10e-9, please check input!',fn{i});
                                    end
                                case 'waitCounter'
                                    if isnumeric(tmp) && isscalar(tmp) && tmp >= 0 && tmp <= 9999999
                                        % prepare value
                                        tmp = round(tmp);
                                        % communicate to hardware
                                        mydo(obj,sprintf(':PULS%d:WCO %d',iCH,tmp));
                                        % store value
                                        obj.p_Channel(iCH).(fn{i}) = tmp;
                                    else
                                        error(sprintf('%s:Input',mfilename),...
                                            '%s is expected to be a double scalar between 0 and 9,999,999, please check input!',fn{i});
                                    end
                                case 'enabled'
                                    if islogical(tmp) && isscalar(tmp)
                                        % communicate to hardware
                                        mydo(obj,sprintf(':PULS%d:STAT %d',iCH,tmp));
                                        % store value
                                        obj.p_Channel(iCH).(fn{i}) = tmp;
                                    else
                                        error(sprintf('%s:Input',mfilename),...
                                            '%s is expected to be a scalar logical, please check input!',fn{i});
                                    end
                                case 'gateLogic'
                                    if ischar(tmp) && ismember(lower(tmp),obj.GateLogicTable(:,1))
                                        tmp      = lower(tmp);
                                        [~, idx] = ismember(tmp,obj.GateLogicTable(:,1));
                                        % communicate to hardware
                                        mydo(obj,sprintf(':PULS%d:CLOG %s',iCH,obj.GateLogicTable{idx,2}));
                                        % store value
                                        obj.p_Channel(iCH).(fn{i}) = tmp;
                                    else
                                        error(sprintf('%s:Input',mfilename),...
                                            '%s is expected to be a single char, please check input!',fn{i});
                                    end
                                case 'gateMode'
                                    if ischar(tmp) && ismember(lower(tmp),obj.ChannelGateMode(:,1))
                                        tmp      = lower(tmp);
                                        [~, idx] = ismember(tmp,obj.ChannelGateMode(:,1));
                                        % communicate to hardware
                                        mydo(obj,sprintf(':PULS%d:CGAT %s',iCH,obj.ChannelGateMode{idx,2}));
                                        % store value
                                        obj.p_Channel(iCH).(fn{i}) = tmp;
                                    else
                                        error(sprintf('%s:Input',mfilename),...
                                            '%s is expected to be a single char, please check input!',fn{i});
                                    end
                                case 'mode'
                                    if ischar(tmp) && ismember(lower(tmp),obj.ChannelModeTable(:,1))
                                        tmp      = lower(tmp);
                                        [~, idx] = ismember(tmp,obj.ChannelModeTable(:,1));
                                        % communicate to hardware
                                        mydo(obj,sprintf(':PULS%d:CMOD %s',iCH,obj.ChannelModeTable{idx,2}));
                                        % store value
                                        obj.p_Channel(iCH).(fn{i}) = tmp;
                                    else
                                        error(sprintf('%s:Input',mfilename),...
                                            '%s is expected to be a single char, please check input!',fn{i});
                                    end
                                case 'mux'
                                    if isnumeric(tmp) && isscalar(tmp) && tmp >= 0 && tmp <= 255
                                        % prepare value
                                        tmp = round(tmp);
                                        % communicate to hardware
                                        mydo(obj,sprintf(':PULS%d:MUX %d',iCH,tmp));
                                        % store value
                                        obj.p_Channel(iCH).(fn{i}) = tmp;
                                    else
                                        error(sprintf('%s:Input',mfilename),...
                                            '%s is expected to be a double scalar between 0 and 255, please check input!',fn{i});
                                    end
                                case 'offCounter'
                                    if isnumeric(tmp) && isscalar(tmp) && tmp >= 1 && tmp <= 9999999
                                        % prepare value
                                        tmp = round(tmp);
                                        % communicate to hardware
                                        mydo(obj,sprintf(':PULS%d:OCO %d',iCH,tmp));
                                        % store value
                                        obj.p_Channel(iCH).(fn{i}) = tmp;
                                    else
                                        error(sprintf('%s:Input',mfilename),...
                                            '%s is expected to be a double scalar between 1 and 9,999,999, please check input!',fn{i});
                                    end
                                case 'outputAmplitude'
                                    if isnumeric(tmp) && isscalar(tmp) && tmp >= 2 && tmp <= 20
                                        % prepare value
                                        tmp = sprintf('%.2f',tmp);
                                        % communicate to hardware
                                        mydo(obj,sprintf(':PULS%d:OUTP:AMPL %s',iCH,tmp));
                                        % store value
                                        obj.p_Channel(iCH).(fn{i}) = str2double(tmp);
                                    else
                                        error(sprintf('%s:Input',mfilename),...
                                            '%s is expected to be a double scalar between 0.20 and 15, please check input!',fn{i});
                                    end
                                case 'outputMode'
                                    if ischar(tmp) && ismember(lower(tmp),obj.ChannelOutputMode(:,1))
                                        tmp      = lower(tmp);
                                        [~, idx] = ismember(tmp,obj.ChannelOutputMode(:,1));
                                        % communicate to hardware
                                        mydo(obj,sprintf(':PULS%d:OUTP:MOD %s',iCH,obj.ChannelOutputMode{idx,2}));
                                        % store value
                                        obj.p_Channel(iCH).(fn{i}) = tmp;
                                    else
                                        error(sprintf('%s:Input',mfilename),...
                                            '%s is expected to be a single char, please check input!',fn{i});
                                    end
                                case 'polarity'
                                    if ischar(tmp) && ismember(lower(tmp),obj.ChannelPolarity(:,1))
                                        tmp      = lower(tmp);
                                        [~, idx] = ismember(tmp,obj.ChannelPolarity(:,1));
                                        % communicate to hardware
                                        mydo(obj,sprintf(':PULS%d:POL %s',iCH,obj.ChannelPolarity{idx,2}));
                                        % store value
                                        obj.p_Channel(iCH).(fn{i}) = tmp;
                                    else
                                        error(sprintf('%s:Input',mfilename),...
                                            '%s is expected to be a single char, please check input!',fn{i});
                                    end
                                case 'pulseCounter'
                                    if isnumeric(tmp) && isscalar(tmp) && tmp >= 1 && tmp <= 9999999
                                        % prepare value
                                        tmp = round(tmp);
                                        % communicate to hardware
                                        mydo(obj,sprintf(':PULS%d:PCO %d',iCH,tmp));
                                        % store value
                                        obj.p_Channel(iCH).(fn{i}) = tmp;
                                    else
                                        error(sprintf('%s:Input',mfilename),...
                                            '%s is expected to be a double scalar between 1 and 9,999,999, please check input!',fn{i});
                                    end
                                case 'sync'
                                    if isnumeric(tmp) && isscalar(tmp) && tmp >= 0 && tmp <= numel(obj.p_Channel)
                                        % prepare value
                                        tmp = round(tmp);
                                        % communicate to hardware
                                        idx = find(cell2num(obj.ChannelTable(:,1)) == tmp,1,'first');
                                        mydo(obj,sprintf(':PULS%d:SYNC %s',iCH,obj.ChannelTable{idx,2}));
                                        % store value
                                        obj.p_Channel(iCH).(fn{i}) = tmp;
                                    else
                                        error(sprintf('%s:Input',mfilename),...
                                            '%s is expected to be a double scalar between 1 and 9,999,999, please check input!',fn{i});
                                    end
                                case 'triggerInput'
                                    if ~obj.supportDT
                                        error(sprintf('%s:Input',mfilename),...
                                            'Dual trigger options are not supported by device, please check!');
                                    elseif ischar(tmp) && ismember(lower(tmp),obj.TriggerInputTable(:,1))
                                        tmp      = lower(tmp);
                                        [~, idx] = ismember(tmp,obj.TriggerInputTable(:,1));
                                        % communicate to hardware
                                        mydo(obj,sprintf(':PULS%d:CTRIG %s',iCH,obj.TriggerInputTable{idx,2}));
                                        % store value
                                        obj.p_Channel(iCH).(fn{i}) = tmp;
                                    else
                                        error(sprintf('%s:Input',mfilename),...
                                            '%s is expected to be a single char, please check input!',fn{i});
                                    end
                                case 'width'
                                    if isnumeric(tmp) && isscalar(tmp) && tmp >= 10e-9 && tmp <= 999.99999999975
                                        % prepare value
                                        tmp = sprintf('%.11f',tmp);
                                        % communicate to hardware
                                        mydo(obj,sprintf(':PULS%d:WIDT %s',iCH,tmp));
                                        % store value
                                        obj.p_Channel(iCH).(fn{i}) = str2double(tmp);
                                    else
                                        error(sprintf('%s:Input',mfilename),...
                                            '%s is expected to be a double scalar between  10e-9 and 999.99999999975, please check input!',fn{i});
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
        
        function out = get.Running(obj)
            out          = logical(str2double(mydo(obj,':PULS0:STAT?',1)));
            obj.p_T0.run = out;
        end
        
        function       set.Running(obj,value)
            if islogical(value) && isscalar(value)
                mydo(obj,sprintf(':PULS0:STAT %d',value));
                obj.p_T0.run = value;
            else
                error(sprintf('%s:Input',mfilename),...
                    'Running is expected to be a scalar logical, please check input!');
            end
        end
        
        function out = get.Live(obj)
            out               = logical(str2double(mydo(obj,':DISP:MOD?',1)));
            obj.p_System.live = out;
        end
        
        function       set.Live(obj,value)
            if islogical(value) && isscalar(value)
                mydo(obj,sprintf(':DISP:MOD %d',value));
                obj.p_System.live = value;
            else
                error(sprintf('%s:Input',mfilename),...
                    'Live is expected to be a scalar logical, please check input!');
            end
        end
        
        function out = get.Locked(obj)
            out                 = logical(str2double(mydo(obj,':SYST:KLOC?',1)));
            obj.p_System.locked = out;
        end
        
        function       set.Locked(obj,value)
            if islogical(value) && isscalar(value)
                mydo(obj,sprintf(':SYST:KLOC %d',value));
                obj.p_System.locked = value;
            else
                error(sprintf('%s:Input',mfilename),...
                    'Locked is expected to be a scalar logical, please check input!');
            end
        end
        
        function out = get.CountTrigger(obj)
            out                   = str2double(mydo(obj,':PULS0:COUN:COUN? TCNTS',1));
            obj.p_T0.countTrigger = out;
        end
        
        function       set.CountTrigger(obj,value)
            if isempty(value) || (isnumeric(value) && abs(value) < eps)
                mydo(obj,':PULS0:COUN:CL TCNTS');
            else
                error(sprintf('%s:Input',mfilename),...
                    'CountTrigger is expected to be a zero or empty to reset counter, please check input!');
            end
        end
        
        function out = get.CountGate(obj)
            out                = str2double(mydo(obj,':PULS0:COUN:COUN? GCNTS',1));
            obj.p_T0.countGate = out;
        end
        
        function       set.CountGate(obj,value)
            if isempty(value) || (isnumeric(value) && abs(value) < eps)
                mydo(obj,':PULS0:COUN:CL GCNTS');
            else
                error(sprintf('%s:Input',mfilename),...
                    'CountGate is expected to be a zero or empty to reset counter, please check input!');
            end
        end
        
        function out = get.Enabled(obj)
            out = false(size(obj.p_Channel));
            for i = 1:numel(out)
                out(i) =  logical(str2double(mydo(obj,sprintf(':PULS%d:STAT?',i),1)));
                obj.p_Channel(i).enabled = out(i);
            end
        end
        
        function       set.Enabled(obj,value)
            if islogical(value) && numel(value) == numel(obj.p_Channel)
                for i = 1:numel(value)
                    mydo(obj,sprintf(':PULS%d:STAT %d',i,value(i)));
                    obj.p_Channel(i).enabled = value(i);
                end
            else
                error(sprintf('%s:Input',mfilename),...
                    'Enabled is expected to be a logical with the enabled state of each channel, please check input!');
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
        
        function out = get.isGUI(obj)
            out = ~isempty(obj.p_gui) && isfield(obj.p_gui,'fig') && any(isvalid(obj.p_gui.fig));
            if ~out, obj.p_gui = struct; end
        end
    end
    
    %% Methods
    methods (Access = public, Hidden = false)
        function                 disp(obj)
            % disp Displays object on command line
            
            %
            % use buildin disp to show properties in long format, otherwise just a short info
            spacing     = '     ';
            if ~isempty(obj) && ismember(get(0,'Format'),{'short','shortE','shortG','shortEng'}) && isvalid(obj)
                fprintf(['%s%s object (settings as stored in the object), use class method ''showInfo'' to query live information from the hardware,\n',...
                    '%schange command window to long output format, i.e. ''format long'' or ',...
                    'use ''properties'' and ''doc'' to get a list of the object properties'],...
                    spacing,class(obj),spacing)
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
        
        function             delete(obj)
            % delete Deletes object and make sure serial connection is closed
            
            if isequal(obj.sobj.Status,'open')
                fclose(obj.sobj);
            end
            delete(obj.sobj);
        end
        
        function S         = saveobj(obj)
            % saveobj Supposed to be called by MATLAB's save function, stores settings for serial
            % connection and settings to allow for a recovery during the load processs
            
            % remove read-only settings
            S.Device  = obj.Device;
            S.System  = rmfield(obj.System,{'status','version'});
            S.T0      = rmfield(obj.T0,{'countGate','countTrigger'});
            S.Channel = obj.Channel;
            S.Name    = obj.Name;
        end
        
        function             reset(obj)
            % reset Resets device and object
            
            %
            % disable any streaming function
            obj.sobj.BytesAvailableFcn = '';
            %
            % reset device
            if ~isequal(obj.sobj.Status,'open')
                fopen(obj.sobj);
            end
            % mydo(obj,'*IDN?',1);
            mydo(obj,'*RST');
            mydo(obj,sprintf(':SYST:COMM:SER:BAUD %d',obj.sobj.BaudRate));
            mydo(obj,sprintf(':SYST:COMM:SER:USB %d',obj.sobj.BaudRate));
            % mydo(obj,sprintf(':SYST:SER:BAUD %d',obj.sobj.BaudRate));
            % mydo(obj,sprintf(':SYST:SER:USB %d',obj.sobj.BaudRate));
            % mydo(obj,':SYST:COMM:SER:ECH 0');
            mydo(obj,':DISP:MOD 0');
            mydo(obj,':SYST:KLOC 0');
            mydo(obj,':SYST:CAPS 0');
            mydo(obj,':SYST:AUT 0');
            if obj.p_Device.Delay > 0, pause(obj.p_Device.Delay); end
            %
            % check if device support dual trigger and increment mode by running a command that
            % should be unique to each mode, Note: checking available commands on the device does
            % not work, since the firmware seems to return commands of unsupported modes
            %
            % allCMD = mydo(obj,':INST:COMM?',1);
            % obj.supportIM = ~isempty(strfind(allCMD,'IDELay'));
            % obj.supportDT = ~isempty(strfind(allCMD,'CTRIg'));
            obj.supportIM = false;%~isempty(strfind(allCMD,'IDELay'));
            obj.supportDT = false;%~isempty(strfind(allCMD,'CTRIg'));
            % check increment modes
            try  %#ok<TRYNC>
                tmp = mydo(obj,':PULS1:IDEL?',1);
                if ~isnan(str2double(tmp))
                    obj.supportIM = true;
                end
            end
            % check dual triger, by trying to set it to dual trigger
            tmp = mydo(obj,':PULS0:TRIG:MOD?',1);
            try  %#ok<TRYNC>
                mydo(obj,':PULS0:TRIG:MOD DUAL');
                obj.supportDT = true;
            end
            mydo(obj,sprintf(':PULS0:TRIG:MOD %s',tmp));
            %
            % initialize System property
            obj.p_System = readSystem(obj);
            %
            % initialize T0 property
            obj.p_T0 = readT0(obj);
            %
            % create minimal structure for the Channel property and update afterwards
            strCh         = mydo(obj,':INST:CAT?',1);
            obj.p_Channel = repmat(struct('enabled',{false}),sum(strCh==','),1);
            obj.p_Channel = readChannel(obj);
            %
            % read status and extract current settings
            sync(obj);
            %
            % reload settings
            recall(obj,0);
        end
        
        function varargout = sync(obj)
            % sync Sync all properties that can be synced
            
            isOK    = syncSystem(obj);
            isOK(2) = syncT0(obj);
            isOK(3) = syncChannel(obj);
            if nargout > 0, varargout = {all(isOK)}; end
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
        
        function varargout = syncT0(obj)
            % syncT0 Checks if system pulse settings (in class property T0) match the status of the
            % hardware, which is returned as second ouput, the first output is true/false
            % whether the object was in sync, makes sure the class property is in sync
            
            isOK = true;
            stat = readT0(obj);
            fn   = fieldnames(stat);
            for k = 1:numel(fn)
                if ~isequal(obj.p_T0.(fn{k}),stat.(fn{k}))
                    warning(sprintf('%s:Check',mfilename),...
                        'Mismatch in setting ''%s'' for system pulse T0, correcting class property accordingly',fn{k});
                    obj.p_T0.(fn{k}) = stat.(fn{k});
                    isOK             = false;
                end
            end
            if nargout > 0, varargout = {isOK, stat}; end
        end
        
        function varargout = syncChannel(obj,idxCh)
            % syncChannel Checks if channel settings (in class property Channel) match the status of
            % the hardware, which is returned as second ouput, the first output is true/false
            % whether the object was in sync, makes sure the class property is in sync
            
            if nargin < 2
                idxCh = 1:numel(obj.p_Channel);
            elseif ~(isnumeric(idxCh) &&  min(round(idxCh)) > 0 && max(round(idxCh)) <= numel(obj.p_Channel))
                error(sprintf('%s:Input',mfilename),'Optional index is out opf bounds, please check!');
            end
            isOK  = true;
            idxCh = reshape(unique(round(idxCh)),1,[]);
            stat  = readChannel(obj,idxCh);
            fn    = fieldnames(stat);
            for i = 1:numel(idxCh)
                for k = 1:numel(fn)
                    if ~isequal(obj.p_Channel(idxCh(i)).(fn{k}),stat(i).(fn{k}))
                        warning(sprintf('%s:Check',mfilename),...
                            'Mismatch in setting ''%s'' for channel %d, correcting class property accordingly',fn{k},i);
                        obj.p_Channel(idxCh(i)).(fn{k}) = stat(i).(fn{k});
                        isOK                            = false;
                    end
                end
            end
            if nargout > 0, varargout = {isOK, stat}; end
        end
        
        function varargout = showInfo(obj, noPrint, noUpdate)
            % showInfo Shows information on device on command line and returns cellstr with info,
            % output to command line can be supressed by the logical noPrint input, the last input
            % controls whether the MATLAB object is synced before info is shown (default)
            
            if nargin < 2 || isempty(noPrint), noPrint  = false; end
            if nargin < 3 || isempty(noPrint), noUpdate = false; end
            if ~(islogical(noPrint) && isscalar(noPrint))
                error(sprintf('%s:Input',mfilename),...
                    'Optional second input is expected to be a scalar logical, please check input!');
            elseif ~(islogical(noUpdate) && isscalar(noUpdate))
                error(sprintf('%s:Input',mfilename),...
                    'Optional third input is expected to be a scalar logical, please check input!');
            end
            %
            % check system, T0 and channels
            if ~noUpdate, sync(obj); end
            %
            % built information strings
            out        = {''};
            %
            % System part
            out{end+1} = sprintf('%s (%s) connected at ''%s''',obj.Name,obj.p_System.version,obj.sobj.Name);
            if obj.supportDT
                out{end} = [out{end} ', with Dual Trigger'];
            end
            if obj.supportDT
                out{end} = [out{end} ', with Increment Modes'];
            end
            if obj.System.live, strL = ''; else, strL = 'NOT'; end
            if obj.System.locked, strK = ''; else, strK = 'NOT'; end
            out{end+1} = sprintf('Display is %s live and keypad is %s locked',strL,strK);
            out{end+1} = '';
            %
            % Channel part
            strEnabled = {'[ ]' '[*]'};
            units      = { -9 'ns'; -6 'us'; -3 'ms'; 0 's'; 3 'ks'; 6 'Ms' };
            out{end+1} = sprintf('<--Sync--><------Pulse Timing----><------><------Counters-----><------Electronics-----><------------->');
            out{end+1} = sprintf('ON? CH->CH       Delay       Width    Mode     B    P    O    W      Output    Polarity           Gate');
            if obj.supportDT
                out{5}   = [out{5}   sprintf('<-Dual-->')];
                out{end} = [out{end} sprintf('  Trigger')];
            end
            if obj.supportIM
                out{5}   = [out{5}   sprintf('<----Increment Modes--->')];
                out{end} = [out{end} sprintf('    incDelay    incWidth')];
            end
            out{5}     = [out{5}     sprintf('<---MUX-->')];
            out{end}   = [out{end} sprintf('  HGFEDCBA')];
            out{end+1} = '';
            for i = 1:numel(obj.p_Channel)
                ch   = obj.Channel(i);
                idxD = find(abs(ch.delay)>=10.^cell2mat(units(:,1)),1,'last');
                if isempty(idxD) || idxD == size(units,1), idxD = size(units,1); end
                if ch.delay == 0, idxD = find(cell2mat(units(:,1))==0); end
                idxW = find(abs(ch.width)>=10.^cell2mat(units(:,1)),1,'last');
                if isempty(idxW) || idxW == size(units,1), idxW = size(units,1); end
                if ch.width == 0, idxW = find(cell2mat(units(:,1))==0); end
                out{end+1} = sprintf('%s %s -> %s%+10.3f%2s%+10.3f%2s%8s%6d%5d%5d%5d %11s%12s%15s',...
                    strEnabled{ch.enabled+1},...
                    obj.ChannelTable{i+1,2}(end),...
                    obj.ChannelTable{ch.sync+1,2}(end),...
                    ch.delay*10^(-1*units{idxD,1}), units{idxD,2},...
                    ch.width*10^(-1*units{idxW,1}), units{idxW,2},...
                    ch.mode, ...
                    ch.burstCounter,ch.pulseCounter,ch.offCounter,ch.waitCounter,...
                    upper(ch.outputMode),...
                    ch.polarity,...
                    [upper(ch.gateMode) sprintf('(%s)',ch.gateLogic)]); %#ok<AGROW>
                if obj.supportDT
                    out{end} = [out{end} sprintf('%9s',upper(ch.triggerInput))];
                end
                if obj.supportIM
                    idxD = find(abs(ch.incDelay)>=10.^cell2mat(units(:,1)),1,'last');
                    if isempty(idxD) || idxD == size(units,1), idxD = size(units,1); end
                    if ch.incDelay == 0, idxD = find(cell2mat(units(:,1))==0); end
                    idxW = find(abs(ch.incWidth)>=10.^cell2mat(units(:,1)),1,'last');
                    if isempty(idxW) || idxW == size(units,1), idxW = size(units,1); end
                    if ch.incWidth == 0, idxW = find(cell2mat(units(:,1))==0); end
                    out{end} = [out{end} sprintf('%+10.3f%2s%+10.3f%2s',...
                        ch.incDelay*10^(-1*units{idxD,1}), units{idxD,2},...
                        ch.incWidth*10^(-1*units{idxW,1}), units{idxW,2}...
                        )];
                end
                out{end} = [out{end} sprintf('%10s',dec2bin(ch.mux,8))];
            end
            out{end+1} = '';
            %
            % T0 part
            idxT = find(abs(obj.T0.period)>=10.^cell2mat(units(:,1)),1,'last');
            if isempty(idxT) || idxT == size(units,1), idxT = size(units,1); end
            if obj.T0.period == 0, idxT = find(cell2mat(units(:,1))==0); end
            if obj.T0.clockIN == 0, strClock = 'internal clock'; else, strClock = sprintf('EXT%d',obj.T0.clockIN); end
            if obj.T0.clockOUT == 0, strClockOut = 'T0'; else, strClockOut = sprintf('%dMHz',obj.T0.clockIN); end
            if obj.T0.counter, strCount = sprintf('counters are enabled (TRIG:%d, GATE:%d)',obj.T0.countTrigger,obj.T0.countGate);
            else, strCount = 'counters are disabled';
            end
            out{end+1} = sprintf('T0: Period of %.3f%s synced to %s, output clock synced to %s, %s',...
                obj.T0.period*10^(-1*units{idxT,1}), units{idxT,2},...
                strClock, strClockOut, strCount);
            out{end+1} = sprintf('    Mode is %s, counters are set to %d BURST, %d PULSE, %d OFF',...
                obj.T0.mode,obj.T0.burstCounter,obj.T0.pulseCounter,obj.T0.offCounter);
            if obj.supportIM
                out{end} = [out{end} sprintf(', DCIncrement cycle is set to %d',obj.T0.cycle')];
            end
            out{end+1} = sprintf('    Trigger mode is %s on %s edge at %.2fV, gate mode is %s with %s logic at %.2fV',...
                obj.T0.triggerMode,obj.T0.triggerEdge,obj.T0.triggerLevel,obj.T0.gateMode,obj.T0.gateLogic,obj.T0.gateLevel);
            if obj.Running
                out{end+1} = '    System is currently armed or generating pulses';
            else
                out{end+1} = '    System is currently NOT armed or generating pulses';
            end
            %
            % Finishing
            idxEmpty = cellfun('isempty',out);
            nMax     = max(cellfun(@(x) numel(x),out));
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
        
        function             store(obj,idx,str)
            % store Stores current settings at given memory block with given name
            
            if nargin < 2, idx = 1; end
            if nargin < 3, str ='MATLAB0'; end
            if ~(isnumeric(idx) && isscalar(idx) && idx >= 1 && idx <= 12)
                error(sprintf('%s:Input',mfilename),...
                    'Index is expected to be a scalar numeric value between 1 and 12, please check input!');
            elseif ~(ischar(str) && numel(str) > 0 && numel(str) <= 12)
                error(sprintf('%s:Input',mfilename),...
                    'char must be a char with 12 elements at max');
            end
            idx = round(idx);
            mydo(obj,sprintf('*LBL "%s"',str'));
            mydo(obj,sprintf('*SAV %d',idx'));
        end
        
        function             recall(obj,idx)
            % recall Recalls given memory block
            
            if nargin < 2, idx = 1; end
            if ~(isnumeric(idx) && isscalar(idx) && idx >= 0 && idx <= 12)
                error(sprintf('%s:Input',mfilename),...
                    'Index is expected to be a scalar numeric value between 0 and 12, please check input!');
            end
            idx = round(idx);
            mydo(obj,sprintf('*RCL %d',idx'));
            notify(obj,'newSettings');
        end
        
        function             trig(obj)
            % trig Sends trigger command (same as receiving external trigger at device)
            
            mydo(obj,'*TRG');
        end
        
        function             arm(obj)
            % arm Sends arm command (same as pressing FUNC + RUN/STOP button of device)
            
            mydo(obj,'*ARM');
        end
        
        function             dualTrig(obj)
            % dualTrig Sends trigger command to TRIG in dual trigger mode (same as receiving external trigger at device)
            
            if obj.supportDT && strcmp(obj.T0.triggerMode,'dual')
                mydo(obj,'*TTG');
            else
                error(sprintf('%s:Input',mfilename),...
                    'Dual trigger must be enabled, please check!');
            end
        end
        
        function             incReset(obj)
            % incReset Resets the width and delay increment on all channels
            
            if obj.supportIM % && ismember(obj.T0.mode,{'incburst','inccycle'})
                mydo(obj,':PULS0:IRES 1');
            else
                error(sprintf('%s:Input',mfilename),...
                    'Increment modes must be supported, please check!');
            end
        end
        
        function             dualGate(obj)
            % dualGate Sends trigger command to GATE in dual trigger mode (same as receiving external trigger at device)
            
            if obj.supportDT && strcmp(obj.T0.triggerMode,'dual')
                mydo(obj,'*GTG');
            else
                error(sprintf('%s:Input',mfilename),...
                    'Dual trigger must be enabled, please check!');
            end
        end
        
        function             update(obj)
            % update Updates display of device
            
            mydo(obj,':DISP:UPD?');
        end
        
        function varargout = start(obj)
            % start Same as pressing the RUN/STOP button in case it was off, function does not
            % switch off in case the device is already running, if an output is requested the
            % function checks the status with the hardware again (true if starting worked)
            
            obj.Running = true;
            if nargout > 0, varargout = {obj.Running}; end
        end
        
        function varargout = stop(obj)
            % stop Same as pressing the RUN/STOP button in case it was on, function does not
            % switch on in case the device is already off, if an output is requested the
            % function checks the status with the hardware again (true if stopping worked)
            
            obj.Running = false;
            if nargout > 0, varargout = {~obj.Running}; end
        end
        
        function             show(obj)
            % show Show a GUI to control the device, wrapper for gui method
            
            gui(obj);
        end
        
        function             createGUI(obj)
            % createGUI Show a GUI to control the device, wrapper for gui method
            
            gui(obj);
        end
        
        function             gui(obj)
            % gui Show a GUI to control the device (preliminary code)
            
            if obj.isGUI
                % show first valid figure
                idx = find(isvalid(obj.p_gui.fig));
                for i = reshape(idx,1,[])
                    obj.p_gui.fig(i).Visible = 'on';
                end
                figure(obj.p_gui.fig(idx(1)));
                return;
            end
            %
            % create a new figure
            pos = get(groot,'DefaultFigurePosition');
            obj.p_gui.fig  = figure('numbertitle', 'off', 'Visible','off',...
                'name', sprintf('%s: Pulse delay generator control (preliminary)',obj.Name), ...
                'menubar','none', ...
                'toolbar','figure', ...
                'resize', 'on', ...
                'HandleVisibility','callback',...
                'tag','BNC575', ...
                'CloseRequestFcn', @(src,dat) gui_closeFigure(obj,src,dat),...
                'position',pos);
            % create tabs for channels
            obj.p_gui.tabgroup = uitabgroup(obj.p_gui.fig,'Position',[0 0 1 1],'Units','Normalized',...
                'Tag','tabgroup');
            obj.p_gui.tabChannel = struct;
            nRows = 2;
            for i = 1:numel(obj.p_Channel)
                iRow = 1;
                % tab
                obj.p_gui.tabChannel(i).tab = uitab(obj.p_gui.tabgroup, 'Tag',sprintf('BNC_Channel_%d',i),...
                    'Units','Normalized','Title', sprintf('Channel %d',i));
                % uipanel and children for delay
                obj.p_gui.tabChannel(i).uipDelay = uipanel(obj.p_gui.tabChannel(i).tab,'Title','Delay in s',...
                    'Units','Normalized','Position',[0 (iRow-1)/nRows 1 1/nRows]); iRow = iRow + 1;
                obj.p_gui.tabChannel(i).eDelay = uicontrol(obj.p_gui.tabChannel(i).uipDelay,...
                    'Units','Normalized','style','edit','string',num2str(obj.p_Channel(i).delay),...
                    'tag','eDelay','callback', @(src,dat) callbackMain(obj,src,dat),'UserData',i,...
                    'Position',[0 0 0.2 1],...
                    'ToolTipString',sprintf('Current delay of channel %d',i));
                obj.p_gui.tabChannel(i).sDelay = uicontrol(obj.p_gui.tabChannel(i).uipDelay,...
                    'Units','Normalized','style','slider','string','Delay in s',...
                    'tag','sDelay', 'Min',min(0,obj.p_Channel(i).delay),'Max',max(1e-3,obj.p_Channel(i).delay),...
                    'SliderStep',[0.05 0.100 ],'Value',obj.p_Channel(i).delay,'UserData',i,...
                    'Position',[0.2 0 0.6 1],'callback', @(src,dat) callbackMain(obj,src,dat),...
                    'ToolTipString',sprintf('Current delay of channel %d',i));
                obj.p_gui.tabChannel(i).bDelayMin = uicontrol(obj.p_gui.tabChannel(i).uipDelay,...
                    'Units','Normalized','style','pushbutton','string','<',...
                    'tag','bDelayMin','callback', @(src,dat) callbackMain(obj,src,dat),'UserData',i,...
                    'Position',[0.8 0 0.1 1],...
                    'ToolTipString','Set slider minimum to current value');
                obj.p_gui.tabChannel(i).bDelayMax = uicontrol(obj.p_gui.tabChannel(i).uipDelay,...
                    'Units','Normalized','style','pushbutton','string','>',...
                    'tag','bDelayMax','callback', @(src,dat) callbackMain(obj,src,dat),'UserData',i,...
                    'Position',[0.9 0 0.1 1],...
                    'ToolTipString','Set slider maximum to current value');
                % uipanel and children for width
                obj.p_gui.tabChannel(i).uipWidth = uipanel(obj.p_gui.tabChannel(i).tab,'Title','Width in s',...
                    'Units','Normalized','Position',[0 (iRow-1)/nRows 1 1/nRows]); iRow = iRow + 1;
                obj.p_gui.tabChannel(i).eWidth = uicontrol(obj.p_gui.tabChannel(i).uipWidth,...
                    'Units','Normalized','style','edit','string',num2str(obj.p_Channel(i).width),...
                    'tag','eWidth','callback', @(src,dat) callbackMain(obj,src,dat),'UserData',i,...
                    'Position',[0 0 0.2 1],...
                    'ToolTipString',sprintf('Current width of channel %d',i));
                obj.p_gui.tabChannel(i).sWidth = uicontrol(obj.p_gui.tabChannel(i).uipWidth,...
                    'Units','Normalized','style','slider','string','Width in s',...
                    'tag','sWidth', 'Min',min(0,obj.p_Channel(i).width),'Max',max(1e-3,obj.p_Channel(i).width),...
                    'SliderStep',[0.05 0.100 ],'Value',obj.p_Channel(i).width,'UserData',i,...
                    'Position',[0.2 0 0.6 1],'callback', @(src,dat) callbackMain(obj,src,dat),...
                    'ToolTipString',sprintf('Current width of channel %d',i));
                obj.p_gui.tabChannel(i).bWidthMin = uicontrol(obj.p_gui.tabChannel(i).uipWidth,...
                    'Units','Normalized','style','pushbutton','string','<',...
                    'tag','bWidthMin','callback', @(src,dat) callbackMain(obj,src,dat),'UserData',i,...
                    'Position',[0.8 0 0.1 1],...
                    'ToolTipString','Set slider minimum to current value');
                obj.p_gui.tabChannel(i).bWidthMax = uicontrol(obj.p_gui.tabChannel(i).uipWidth,...
                    'Units','Normalized','style','pushbutton','string','>',...
                    'tag','bWidthMax','callback', @(src,dat) callbackMain(obj,src,dat),'UserData',i,...
                    'Position',[0.9 0 0.1 1],...
                    'ToolTipString','Set slider maximum to current value');
                
            end
            %
            % show figure
            obj.p_gui.fig.Visible = 'on';
        end
        
        function             closeGUI(obj)
            % closeGUI Close any open GUI
            
            if obj.isGUI
                delete(obj.p_gui.fig(isvalid(obj.p_gui.fig)));
            end
            obj.p_gui = struct;
        end
    end
    
    methods (Access = private, Hidden = false)
        function out = readSystem(obj)
            % readSystem Reads all supported system settings from hardware and returns settings structure
            
            out.brightness = round(str2double(mydo(obj,':DISP:BRIG?',1)));
            out.live       = logical(str2double(mydo(obj,':DISP:MOD?',1)));
            out.light      = logical(str2double(mydo(obj,':DISP:ENAB?',1)));
            out.locked     = logical(str2double(mydo(obj,':SYST:KLOC?',1)));
            out.version    = mydo(obj,':SYST:INFO?',1);
            out.status     = logical(str2double(mydo(obj,':SYST:STAT?',1)));
            tmp            = logical(str2double(mydo(obj,':SYST:BEEP:STAT?',1)));
            if tmp
                out.volume = round(str2double(mydo(obj,':SYST:BEEP:VOL?',1)));
            else
                out.volume = 0;
            end
            out = orderfields(out);
        end
        
        function out = readT0(obj)
            % readT0 Reads all supported system pulse settings from hardware and returns settings structure
            
            out.run          = logical(str2double(mydo(obj,':PULS0:STAT?',1)));
            out.counter      = logical(str2double(mydo(obj,':PULS0:COUN:STAT?',1)));
            out.countTrigger = str2double(mydo(obj,':PULS0:COUN:COUN? TCNTS',1));
            out.countGate    = str2double(mydo(obj,':PULS0:COUN:COUN? GCNTS',1));
            out.period       = str2double(mydo(obj,':PULS0:PER?',1));
            tmp              = mydo(obj,':PULS0:MOD?',1);
            [~, idx]         = ismember(tmp,obj.ModeTable(:,2));
            out.mode         = obj.ModeTable{idx,1};
            out.burstCounter = round(str2double(mydo(obj,':PULS0:BCO?',1)));
            out.pulseCounter = round(str2double(mydo(obj,':PULS0:PCO?',1)));
            out.offCounter   = round(str2double(mydo(obj,':PULS0:OCO?',1)));
            tmp              = mydo(obj,':PULS0:ICL?',1);
            if strcmp(tmp,'SYS'), out.clockIN = 0;
            else,                 out.clockIN = str2double(tmp(4:end));
            end
            tmp              = mydo(obj,':PULS0:OCL?',1);
            if strcmp(tmp,'TO'), out.clockOUT = 0;
            else,                out.clockOUT = str2double(tmp);
            end
            tmp              = mydo(obj,':PULS0:GAT:MOD?',1);
            [~, idx]         = ismember(tmp,obj.GateModeTable(:,2));
            out.gateMode     = obj.GateModeTable{idx,1};
            tmp              = mydo(obj,':PULS0:GAT:LOG?',1);
            [~, idx]         = ismember(tmp,obj.GateLogicTable(:,2));
            out.gateLogic    = obj.GateLogicTable{idx,1};
            out.gateLevel    = str2double(mydo(obj,':PULS0:GAT:LEV?',1));
            tmp              = mydo(obj,':PULS0:TRIG:MOD?',1);
            [~, idx]         = ismember(tmp,obj.TriggerModeTable(:,2));
            out.triggerMode  = obj.TriggerModeTable{idx,1};
            tmp              = mydo(obj,':PULS0:TRIG:EDG?',1);
            [~, idx]         = ismember(tmp,obj.TriggerEdgeTable(:,2));
            out.triggerEdge  = obj.TriggerEdgeTable{idx,1};
            out.triggerLevel = str2double(mydo(obj,':PULS0:TRIG:LEV?',1));
            out.cycle        = round(str2double(mydo(obj,':PULS0:CYCL?',1)));
            out              = orderfields(out);
        end
        
        function out = readChannel(obj,idxCh)
            % readChannel Reads all supported channel settings from hardware and returns settings structure
            
            if nargin < 2, idxCh = 1:numel(obj.p_Channel); end
            out = struct;
            for iCH = 1:numel(idxCh)
                out(iCH).burstCounter    = round(str2double(mydo(obj,sprintf(':PULS%d:BCO?',idxCh(iCH)),1)));
                out(iCH).delay           = str2double(mydo(obj,sprintf(':PULS%d:DEL?',idxCh(iCH)),1));
                out(iCH).waitCounter     = round(str2double(mydo(obj,sprintf(':PULS%d:WCO?',idxCh(iCH)),1)));
                out(iCH).enabled         = logical(str2double(mydo(obj,sprintf(':PULS%d:STAT?',idxCh(iCH)),1)));
                tmp                      = mydo(obj,sprintf(':PULS%d:CLOG?',idxCh(iCH)),1);
                [~, idx]                 = ismember(tmp,obj.GateLogicTable(:,2));
                out(iCH).gateLogic       = obj.GateLogicTable{idx,1};
                tmp                      = mydo(obj,sprintf(':PULS%d:CGAT?',idxCh(iCH)),1);
                [~, idx]                 = ismember(tmp,obj.ChannelGateMode(:,2));
                out(iCH).gateMode        = obj.ChannelGateMode{idx,1};
                tmp                      = mydo(obj,sprintf(':PULS%d:CMOD?',idxCh(iCH)),1);
                [~, idx]                 = ismember(tmp,obj.ChannelModeTable(:,2));
                out(iCH).mode            = obj.ChannelModeTable{idx,1};
                out(iCH).mux             = round(str2double(mydo(obj,sprintf(':PULS%d:MUX?',idxCh(iCH)),1)));
                out(iCH).offCounter      = round(str2double(mydo(obj,sprintf(':PULS%d:OCO?',idxCh(iCH)),1)));
                out(iCH).outputAmplitude = str2double(mydo(obj,sprintf(':PULS%d:OUTP:AMPL?',idxCh(iCH)),1));
                tmp                      = mydo(obj,sprintf(':PULS%d:OUTP:MOD?',idxCh(iCH)),1);
                [~, idx]                 = ismember(tmp,obj.ChannelOutputMode(:,2));
                out(iCH).outputMode      = obj.ChannelOutputMode{idx,1};
                tmp                      = mydo(obj,sprintf(':PULS%d:POL?',idxCh(iCH)),1);
                [~, idx]                 = ismember(tmp,obj.ChannelPolarity(:,2));
                out(iCH).polarity        = obj.ChannelPolarity{idx,1};
                out(iCH).pulseCounter    = round(str2double(mydo(obj,sprintf(':PULS%d:PCO?',idxCh(iCH)),1)));
                tmp                      = mydo(obj,sprintf(':PULS%d:SYNC?',idxCh(iCH)),1);
                [~, idx]                 = ismember(tmp,obj.ChannelTable(:,2));
                out(iCH).sync            = obj.ChannelTable{idx,1};
                out(iCH).width           = str2double(mydo(obj,sprintf(':PULS%d:WIDT?',idxCh(iCH)),1));
                if obj.supportDT
                    tmp                   = mydo(obj,sprintf(':PULS%d:CTRIG?',idxCh(iCH)),1);
                    [~, idx]              = ismember(tmp,obj.TriggerInputTable(:,2));
                    out(iCH).triggerInput = obj.TriggerInputTable{idx,1};
                end
                if obj.supportIM
                    out(iCH).incDelay     = str2double(mydo(obj,sprintf(':PULS%d:IDEL?',idxCh(iCH)),1));
                    out(iCH).incWidth     = str2double(mydo(obj,sprintf(':PULS%d:IWID?',idxCh(iCH)),1));
                end
            end
            out = orderfields(out);
        end
        
        function out = mydo(obj,cmd,len)
            % mydo Sends char command cmd to serial device and expects len number of output lines in
            % char representation, returns a cellstr if len is greater than 1, otherwise a char.
            
            if nargin < 3, len = 0; end
            %
            % check if input buffer is empty
            [isData, data] = flushData(obj);
            if isData, warning(sprintf('%s:Run',mfilename),['Bytes available for device ''%s'', ',...
                    'which is not expected. Cleared bytes (including line feed and carriage return):\n%s'],...
                    obj.Name,char(reshape(data,1,[])));
            end
            %
            % run command, note: the BNC575 always answers
            out = '';
            fprintf(obj.sobj,cmd);
            nBytes = mywait(obj,2);
            if nBytes < 1
                error(sprintf('%s:Run',mfilename),...
                    'No data available from device ''%s'', please check!',obj.Name);
            end
            if len > 0
                % caller expects a return from device
                out = cell(len,1);
                for i = 1:len
                    nBytes = mywait(obj,2);
                    if nBytes < 1
                        warning(sprintf('%s:Run',mfilename),['No data available from device ''%s'' ',...
                            'although an appropriate command ''%s'' was send, returning empty char'],...
                            obj.Name,cmd)
                        out{i} = '';
                    else
                        tmp = fgetl(obj.sobj);
                        if numel(tmp) == 2 && strcmp(tmp(1),'?') && ~isnan(str2double(tmp(2))) && ...
                                str2double(tmp(2)) >= 1 && str2double(tmp(2)) <= 8
                            % return was an error code
                            idx = str2double(tmp(2));
                            idx = find(cell2num(obj.ErrorTable(:,1)) == idx,1,'first');
                            error(sprintf('%s:Run',mfilename),['Device ''%s'' responded with error ''%s'' ',...
                                'to command ''%s'', please check!'],obj.Name,obj.ErrorTable{idx,2},cmd);
                        else
                            out{i} = tmp;
                        end
                    end
                end
                if len == 1, out = out{1}; end
            else
                % caller does not expect a return, available should be the single line response of
                % the device with either 'ok' or the error code '?n', where n is actual code
                tmp = fgetl(obj.sobj);
                if ~strcmp(tmp,'ok')
                    if numel(tmp) == 2 && strcmp(tmp(1),'?') && ~isnan(str2double(tmp(2))) && ...
                            str2double(tmp(2)) >= 1 && str2double(tmp(2)) <= 8
                        idx = str2double(tmp(2));
                        idx = find(cell2num(obj.ErrorTable(:,1)) == idx,1,'first');
                        error(sprintf('%s:Run',mfilename),['Device ''%s'' responded with error ''%s'' ',...
                            'to command ''%s'', please check!'],obj.Name,obj.ErrorTable{idx,2},cmd);
                    else
                        error(sprintf('%s:Run',mfilename),...
                            'Respond ''%s'' of device ''%s'' is unexpected',tmp,obj.Name);
                    end
                end
            end
            %
            % check if input buffer is empty
            [isData, data] = flushData(obj);
            if isData, warning(sprintf('%s:Run',mfilename),...
                    'Bytes available for device ''%s'', which is not expected. Cleared bytes: %s',obj.Name,num2str(data));
            end
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
        
        function gui_closeFigure(obj,src,dat)
            % gui_closeFigure Function to call when closing the gui
            
            selection = questdlg(sprintf('%s: Close figure (object remains valid)?',obj.Name),...
                'Close Request Function',...
                'Yes','No','Just hide figure', 'No');
            switch selection
                case 'Yes'
                    delete(obj.p_gui.fig);
                    obj.p_gui = struct;
                case 'No'
                    return;
                case 'Just hide figure'
                    idx = find(isvalid(obj.p_gui.fig));
                    for i = reshape(idx,1,[])
                        obj.p_gui.fig(i).Visible = 'off';
                    end
                    return;
            end
        end
        
        function callbackMain(obj,hObject,hData)
            % callbackMain %callbackMain Runs callbacks for some uicontrols in main figure or run code snippet by
            % name, i.e there is no need to create a uicontrol for each code part
            
            if ischar(hObject)
                strTag = hObject;
                if isfield(obj.p_gui,strTag), hObject = obj.p_gui.(strTag);
                else,                         hObject = [];
                end
            else
                strTag = hObject.Tag;
            end
            switch strTag
                case {'eDelay' 'eWidth'}
                    value = str2double(hObject.String);
                    iCh   = hObject.UserData;
                    if ~isnan(value) && isnumeric(value) && isscalar(value)
                        obj.p_gui.tabChannel(iCh).(strTag).String = num2str(value);
                        if value < obj.p_gui.tabChannel(iCh).(['s' strTag(2:end)]).Min
                            obj.p_gui.tabChannel(iCh).(['s' strTag(2:end)]).Min = value;
                        elseif value > obj.p_gui.tabChannel(iCh).(['s' strTag(2:end)]).Max
                            obj.p_gui.tabChannel(iCh).(['s' strTag(2:end)]).Max = value;
                        end
                        obj.p_gui.tabChannel(iCh).(['s' strTag(2:end)]).Value = value;
                    else
                        value = obj.p_gui.tabChannel(iCh).(['s' strTag(2:end)]).Value;
                        obj.p_gui.tabChannel(iCh).(strTag).String = num2str(obj.p_gui.tabChannel(iCh).(['s' strTag(2:end)]).Value);
                    end
                    obj.Channel(iCh).(lower(strTag(2:end))) = value;
                case {'sDelay' 'sWidth'}
                    iCh   = hObject.UserData;
                    if hObject.Value < hObject.Min
                        hObject.Value = hObject.Min;
                    elseif hObject.Value > hObject.Max
                        hObject.Value = hObject.Max;
                    end
                    obj.p_gui.tabChannel(iCh).(['e' strTag(2:end)]).String = num2str(hObject.Value);
                    obj.Channel(iCh).(lower(strTag(2:end))) = hObject.Value;
                case {'bDelayMin' 'bWidthMin'}
                    iCh = hObject.UserData;
                    obj.p_gui.tabChannel(iCh).(['s' strTag(2:6)]).Min = obj.p_gui.tabChannel(iCh).(['s' strTag(2:6)]).Value;
                case {'bDelayMax' 'bWidthMax'}
                    iCh = hObject.UserData;
                    obj.p_gui.tabChannel(iCh).(['s' strTag(2:6)]).Max = obj.p_gui.tabChannel(iCh).(['s' strTag(2:6)]).Value;
                otherwise
                    error(sprintf('%s:Input',mfilename),'Unknown tag ''%s''',strTag);
            end
        end
    end
    
    %% Static Methods
    methods (Static = true, Access = public, Hidden = false, Sealed = true)
        function obj = loadobj(S)
            %loadobj Loads object and tries to re-connect to hardware
            
            try
                % try to connect and set channel settings (the ones that can be changed)
                for n = 1:numel(S)
                    S(n).Device.showInfoOnConstruction = false;
                    obj(n)         = BNC575(S(n).Device); %#ok<AGROW>
                    obj(n).Name    = S(n).Name; %#ok<AGROW>
                    obj(n).System  = S(n).System; %#ok<AGROW>
                    obj(n).T0      = S(n).T0; %#ok<AGROW>
                    obj(n).Channel = S(n).Channel; %#ok<AGROW>
                    showInfo(obj(n));
                end
            catch err
                warning(sprintf('%s:Input',mfilename),...
                    'Device could not be re-connected during load process: %s',err.getReport);
            end
        end
    end
end
