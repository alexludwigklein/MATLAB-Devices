classdef ThorlabsRM < handle
    %ThorlabsRM Class describing the ActiveX connection to the rotational mount K10CR1 by Thorlabs,
    %   but in principle it should work for many other motion controllers by Thorlabs.
    %
    %   The class allows to connect to the device via an ActiveX control and perform very basic
    %   operation, such as setting the position. All settings can be configured via a GUI, i.e. the
    %   actual ActiveX object.
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
        % Visible True/false whether to show the parent figure with the ActivX control (logical)
        Visible
        % HardwarePosition Absolute positon of the rotational mount in degree (double)
        %   0 is the home position
        % < 0 device rotates counter-clockwise
        % > 0 device rotates clockwise to given position
        HardwarePosition
        % Origin Add a phase shift to the hardware position in degrees to get a new custom origin(double)
        %
        % The hardware will be set to <obj.Position + obj.Origin>, such that this can be used
        % to transform the position to somethinh easy to remember. Please note, this value is not
        % taken into account in the ActiveX control.
        Origin = 0;
        % Position Relative position of the rotational mount in degree including the custom origin (double)
        Position
        % Name A short name for the device (char)
        Name
    end
    
    properties (GetAccess = public, SetAccess = public, Transient = true)
        % UserData Userdata linked to the device (arbitrary)
        UserData = [];
    end
    
    properties (GetAccess = public, SetAccess = protected, Dependent = true)
        % Moving True/false whether the rotational mount is moving (logical)
        Moving
        % Status Status of the device (numeric value read from hardware)
        Status
    end
    
    properties (GetAccess = public, SetAccess = protected, Transient = true)
        % Parent The parent graphic object of the ActiveX object, e.g. a figure
        Parent
    end
    
    properties (GetAccess = protected, SetAccess = protected, Transient = true)
        % sobj ActiveX device, i.e. the actual connection to the hardware (serial object)
        sobj
        % Recover Settings needed when the object is loaded from disk
        Recover
        % p_Name Storage for Name
        p_Name = 'ThorlabsRM';
        % p_Origin Storage for Origin
        p_Origin = 0;
        % gui Place to store uicontrols besides the actual ActiveX control element
        gui
    end
    
    %% Events
    events
        % newSettings Notify when settings are changed
        newSettings
        % moveComplete Notify when a move is complete
        moveComplete
        % moveStopped Notify when a move is complete
        moveStopped
        % homeComplete Notify when a home is complete
        homeComplete
    end
    
    %% Constructor and SET/GET
    methods
        function obj = ThorlabsRM(varargin)
            % ThorlabsRM Creates object that links to the device
            %
            % Options are supposed to be given in <propertyname> <propertyvalue> style
            
            %
            % get input with input parser
            tmp               = inputParser;
            tmp.StructExpand  = true;
            tmp.KeepUnmatched = false;
            % figure settings
            tmp.addParameter('Parent', [], ...
                @(x) isempty(x) || (isscalar(x) && isgraphics(x,'figure')));
            tmp.addParameter('Visible', true, ...
                @(x) ~isempty(x) && islogical(x));
            % ActiveX
            tmp.addParameter('progid', 'MGMOTOR.MGMotorCtrl.1', ...
                @(x) ~isempty(x) && ischar(x));
            tmp.addParameter('serialnumber', 55000106, ...
                @(x) ~isempty(x) && isnumeric(x));
            tmp.addParameter('showInfoOnConstruction', true, ...
                @(x) islogical(x) && isscalar(x));
            % object settings
             tmp.addParameter('Name', 'ThorlabsRM', ...
                @(x) ~isempty(x) && ischar(x));
            tmp.parse(varargin{:});
            tmp = tmp.Results;
            obj.p_Name             = tmp.Name;
            showInfoOnConstruction = tmp.showInfoOnConstruction;
            tmp                    = rmfield(tmp,'showInfoOnConstruction');
            %
            % create figure
            if isempty(tmp.Parent)
                pos = get(groot,'DefaultFigurePosition');
                obj.Parent = figure('numbertitle', 'off', 'Visible','off',...
                    'name', sprintf('%s: Rotational mount control',obj.p_Name), ...
                    'menubar','figure', ...
                    'toolbar','none', ...
                    'resize', 'on', ...
                    'HandleVisibility','callback',...
                    'tag','ThorlabsRM',...
                    'SizeChangedFcn', @(src,dat) sizeChangedParent(obj,src,dat),...
                    'CloseRequestFcn', @(src,dat) closeParent(obj),...
                    'DeleteFcn', @(src,dat) delete(obj),...
                    'position',pos);
            else
                obj.Parent      = tmp.Parent;
                set(obj.Parent, 'Name', sprintf('%s: Rotational mount control',obj.p_Name),...
                    'CloseRequestFcn', @(src,dat) closeParent(obj),...
                    'DeleteFcn', @(src,dat) delete(obj),...
                    'SizeChangedFcn', @(src,dat) sizeChangedParent(obj,src,dat));
            end
            bak = obj.Parent.Units;
            obj.Parent.Units = 'pixel';
            pos = obj.Parent.Position;
            %
            % construct ActiveX object
            try
                obj.sobj = actxcontrol(tmp.progid,'position', [1 1 pos(3) pos(4) ], 'parent', obj.Parent);
                % start Control
                obj.sobj.StartCtrl;
                % set the Serial Number
                set(obj.sobj,'HWSerialNum', tmp.serialnumber);
                % register events
                obj.sobj.registerevent({'MoveComplete'    @(varargin) p_moveComplete(obj,varargin)});
                obj.sobj.registerevent({'MoveStopped'     @(varargin) p_moveStopped(obj,varargin)});
                obj.sobj.registerevent({'HomeComplete'    @(varargin) p_homeComplete(obj,varargin)});
                obj.sobj.registerevent({'SettingsChanged' @(varargin) p_settingsChanged(obj,varargin)});
            catch exception
                error(sprintf('%s:Input',mfilename),'Could not open device: %s',exception.getReport);
            end
            %
            % construct uicontrol GUI 
            obj.gui.EPosition = uicontrol(obj.Parent,'Units','pixel','style','edit','string',['Relative position: ' num2str(obj.Position)],...
                'tag','EPosition','callback', @(src,dat) callbackParent(obj,'EPosition',src,dat),...
                'ToolTipString','Enter new position taking the custom origin into account',...
                'Fontsize',16);
            obj.gui.PBShift = uicontrol(obj.Parent,'Units','pixel','style','pushbutton','string','Set origin',...
                'tag','PBShift','callback', @(src,dat) callbackParent(obj,'PBShift',src,dat),...
                'ToolTipString','Set current hardware position as new origin','Fontsize',12);
            % restore units of figure
            obj.Parent.Units = bak;
            %
            % update visibility
            obj.Parent.DockControls = 'on';
            obj.Visible = tmp.Visible;
            %
            % store some input settings for later recovery
            obj.Recover = rmfield(tmp,{'Parent'});
            %
            % identify hardware
            identify(obj);
            if showInfoOnConstruction
                showInfo(obj);
            end
        end
        
        function out = get.Visible(obj)
            
            out = strcmp(obj.Parent.Visible,'on');
        end
        
        function       set.Visible(obj,value)
            
            if islogical(value) && isscalar(value)
                if value, str = 'on'; else, str = 'off'; end
                obj.Parent.Visible = str;
                if value, figure(obj.Parent); end
            else
                error(sprintf('%s:Input',mfilename),...
                    'Visible is expected to be a scalar logical, please check input!');
            end
        end
        
        function out = get.Status(obj)
            
            out = obj.sobj.GetStatusBits_Bits(0);
        end
        
        function out = get.Moving(obj)
            
            tmp = obj.Status;
            out = bitget(abs(tmp),5) || bitget(abs(tmp),6);
        end
        
        function out = get.HardwarePosition(obj)
            
            out = obj.sobj.GetPosition_Position(0);
        end
        
        function       set.HardwarePosition(obj,value)
            
            if isnumeric(value) && isscalar(value) && abs(value) <= 180
                if value < 0, value = 360 + value; end
                if obj.Moving, stop(obj); end
                obj.sobj.SetAbsMovePos(0,value);
                obj.sobj.MoveAbsolute(0,false);
            else
                error(sprintf('%s:Input',mfilename),['HardwarePosition is expected to be a scalar double ',...
                    'between -180 and 180, please check input!']);
            end
        end
        
        function out = get.Position(obj)
            
            out = obj.sobj.GetPosition_Position(0)-obj.p_Origin;
        end
        
        function       set.Position(obj,value)
            
            if isnumeric(value) && isscalar(value) && abs(value+obj.p_Origin) <= 180
                value = value+obj.p_Origin;
                if value < 0, value = 360 + value; end
                if obj.Moving, stop(obj); end
                obj.sobj.SetAbsMovePos(0,value);
                obj.sobj.MoveAbsolute(0,false);
            else
                error(sprintf('%s:Input',mfilename),['Position is expected to be a scalar double ',...
                    'between %e and %e given the current origin of %e, please check input!'],...
                    -180-obj.p_Origin,180-obj.p_Origin,obj.p_Origin);
            end
        end
            
        function       set.Origin(obj,value)
            
            if isnumeric(value) && isscalar(value)
                obj.p_Origin = value;
            else
                error(sprintf('%s:Input',mfilename),...
                    'Origin is expected to be a scalar double, please check input!');
            end
        end

        function out = get.Origin(obj)
            
            out = obj.p_Origin;
        end
        
        function       set.Name(obj,value)
            
            if ischar(value)
                obj.p_Name      = value;
                obj.Parent.Name = sprintf('%s: Rotational mount control',obj.Name);
            else
                error(sprintf('%s:Input',mfilename),...
                    'Name is expected to be a char, please check input!');
            end
        end
        
        function out = get.Name(obj)
            
            out = obj.p_Name;
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
            % delete Deletes object and tries to stop the ActiveX object
            
            try %#ok<TRYNC>
                obj.sobj.StopCtrl;
            end
            try %#ok<TRYNC>
                obj.Parent.delete;
            end
        end
        
        function S         = saveobj(obj)
            % saveobj Supposed to be called by MATLAB's save function, stores settings for ActiveX
            % connection and position to allow for a recovery during the load processs
            
            S.Name     = obj.p_Name;
            S.Position = obj.Position;
            S.Recover  = obj.Recover;
            S.Origin   = obj.Origin;
        end
        
        function             identify(obj)
            % identify Makes LED on device blink to find it
            
            obj.sobj.Identify;
        end
        
        function             home(obj)
            % home Moves mount to home position
            
            obj.sobj.MoveHome(0,0);
        end
        
        function             stop(obj)
            % stop Stops a move in a profiled manner
            
            obj.sobj.StopProfiled(0)
        end
        
        function             stopNow(obj)
            % stopNow Stops a move immediately
            
            obj.sobj.StopImmediate(0)
        end
        
        function             waitStop(obj)
            % waitStop Waits for motion in progress to stop with a simple pause loop
            
            while obj.Moving, pause(0.1); end
        end
        
        function             wait(obj)
            % wait Wrapper for waitStop
            
            waitStop(obj);
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
            out{end+1} = sprintf('%s (motional stage, S/N: %d) connected as ActiveX control',obj.p_Name,obj.sobj.HWSerialNum);
            sep2       = repmat('-',1,numel(out{end}));
            lenChar    = 22;
            out{end+1} = sep2;
            out{1}     = sep2;
            out{end+1} = sprintf('%s%*s: %.2f',sep,lenChar,'HardwarePosition',obj.HardwarePosition);
            out{end+1} = sprintf('%s%*s: %.2f',sep,lenChar,'Origin',obj.p_Origin);
            out{end+1} = sprintf('%s%*s: %.2f',sep,lenChar,'Position',obj.Position);
            if ~obj.Moving
                out{end+1} = sprintf('%sSystem is currently NOT moving',sep);
            else
                out{end+1} = sprintf('%sSystem is currently moving',sep);
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
        
        function             closeParent(obj)
           % closeParent Closes but asks for confirmation first
           
           selection = questdlg(sprintf('%s: Close figure and give up control?',obj.p_Name),...
               'Close Request Function',...
               'Yes','No','Just hide figure', 'No');
           switch selection
               case 'Yes'
                   delete(obj)
               case 'No'
                   return;
               case 'Just hide figure'
                   obj.Visible = false;
                   return;
           end
        end
        
        function             hide(obj)
            % hide Hides parent figure
            
            obj.Visible = false;
        end
        
        function             show(obj)
            % show Show parent figure
            
            obj.Visible = true;
        end
    end
    
    methods (Access = private, Hidden = false)
         function         callbackParent(obj,type,src,dat) %#ok<INUSD>
            %callbackParent Handles callbacks from GUI elements
            
            switch type
                case 'EPosition'
                    value = str2double(obj.gui.EPosition.String);
                    if ~isnan(value) && isnumeric(value) && isscalar(value) && ...
                            value >= -180-obj.p_Origin && value <= 180-obj.p_Origin
                        obj.Position             = value;
                        obj.gui.EPosition.String = ['Relative position: ' num2str(value)];
                    else
                        obj.gui.EPosition.String = ['Relative position: ' num2str(obj.Position)];
                    end
                case 'PBShift'
                    obj.p_Origin             = obj.HardwarePosition;
                    obj.gui.EPosition.String = ['Relative position: ' num2str(obj.Position)];
            end
         end
         
        function         sizeChangedParent(obj,fig,data) %#ok<INUSD>
            %sizeChangedParent Adjusts GUI in case of a size change
            
            %
            % settings for size in pixels
            pbW  = 150;
            pbH  = 40;
            %
            % get size of figure in pixel
            bak              = obj.Parent.Units;
            obj.Parent.Units = 'pixel';
            pos              = obj.Parent.Position;
            % resize
            if pos(3) > 2*pbW && pos(4) > 4*pbH
                obj.gui.EPosition.Position = [1 pos(4)-pbH pos(3)-pbW pbH];
                obj.gui.PBShift.Position   = [pos(3)-pbW pos(4)-pbH pbW pbH];
                move(obj.sobj,[1 1 pos(3) pos(4)-pbH]);
            end
            % reset figure units
            obj.Parent.Units = bak;
        end
        
        function p_moveComplete(obj,varargin)
            % p_moveComplete Wrapper for event from ActiveX object
            
            obj.gui.EPosition.String = ['Relative position: ' num2str(obj.Position)];
            notify(obj,'moveComplete');
        end
        
        function p_moveStopped(obj,varargin)
            % p_moveStopped Wrapper for event from ActiveX object
            
            obj.gui.EPosition.String = ['Relative position: ' num2str(obj.Position)];
            notify(obj,'moveStopped');
        end
        
        function p_homeComplete (obj,varargin)
            % p_homeComplete Wrapper for event from ActiveX object
            
            obj.gui.EPosition.String = ['Relative position: ' num2str(obj.Position)];
            notify(obj,'homeComplete');
        end
        
        function p_settingsChanged(obj,varargin)
            % p_settingsChanged Wrapper for event from ActiveX object
            
            obj.gui.EPosition.String = ['Relative position: ' num2str(obj.Position)];
            notify(obj,'newSettings');
        end
    end
    
    %% Static Methods
    methods (Static = true, Access = public, Hidden = false, Sealed = true)
        function obj = loadobj(S)
            %loadobj Loads object and tries to re-connect to hardware
            
            try
                % try to connect and set name and position
                for n = 1:numel(S)
                    S(n).Recover.showInfoOnConstruction = false;
                    obj(n)          = ThorlabsRM(S(n).Recover); %#ok<AGROW>
                    obj(n).Name     = S(n).Name; %#ok<AGROW>
                    obj(n).Position = S(n).Position; %#ok<AGROW>
                    obj(n).Origin   = S(n).Origin; %#ok<AGROW>
                    showInfo(obj(n));
                end
            catch err
                warning(sprintf('%s:Input',mfilename),...
                    'Device could not be re-connected during load process: %s',err.getReport);
            end
        end
    end
end
