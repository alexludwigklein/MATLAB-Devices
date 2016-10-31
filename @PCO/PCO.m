classdef PCO < handle
    %PCO Class describing the connection to a single PCO camera via the SDK by PCO
    %
    % Please note: PCO released an Image Adaptor for MATLAB's image acquisition toolbox in 2016 as
    % part of their SDK, which can be used instead of this class. However, in October 2016 the
    % double image mode was not yet supported in SDK 1.20 where this class can help.
    %
    % The class allows to connect to the device, configure it and read images. It does not make use
    % of all functions described in the SDK, for example PCO_GetFirmwareInfo. This does not lead to
    % any loss of functionality (maybe a loss of information). However, some features are not
    % supported at all:
    %   * PCO color cameras
    %   * PCO_GetImageTiming
    %   * PCO_SetTransferParametersAuto
    %   * PCO_GetModulationMode, PCO_SetModulationMode
    %   * PCO_GetRecordStopEvent, PCO_SetRecordStopEvent
    %   * PCO_GetAcquireModeEx, PCO_SetAcquireModeEx
    %   * PCO_ReadHotPixelList, PCO_WriteHotPixelList, PCO_ClearHotPixelList
    %   * PCO_GetIRSensitivity, PCO_SetIRSensitivity
    %   * PCO_GetInterfaceOutputFormat, PCO_SetInterfaceOutputFormat (dimax only)
    %   * PCO_PlayImagesFromSegmentHDSDI, PCO_GetPlayPositionHDSDI (dimax only)
    %   * PCO_GetMetaDataMode, PCO_SetMetaDataMode (dimax only)
    %   * PCO_GetCameraSetup, PCO_SetCameraSetup (pco.edge only)
    %   * PCO_GetHWIOSignalCount, PCO_GetHWIOSignalDescriptor (dimax, edge only)
    %   * PCO_GetHWIOSignal, PCO_SetHWIOSignal (dimax, edge only)
    %   * PCO_GetLookuptableInfo, PCO_GetActiveLookuptable, PCO_SetActiveLookuptable (edge only)
    %   * PCO_GetFPSExposureMode, PCO_SetFPSExposureMode (1200(h)s only)
    %   * PCO_GetFrameRate, PCO_SetFrameRate (dimax, edge only)
    %   * PCO_GetCameraSynchMode, PCO_SetCameraSynchMode (dimax only)
    %   * PCO_GetFastTimingMode, PCO_SetFastTimingMode (dimax only)
    %   * PCO_GetSensorSignalStatus (pco.edge)
    %   * PCO_GetMetaData (dimax only)
    %   * PCO_EnableSoftROI (only available for Cameralink Me4)
    %
    % Examples:
    %   Open a camera connected via ethernet (same as GIGE):
    %     cam = PCO('Interface','gige');
    %   Open a specific camera connected via ethernet (same as GIGE):
    %     cam = PCO('Interface','gige','CameraNumber',0);
    %   Open a camera connected via USB2.0 and give a custom name:
    %     cam = PCO('Interface','usb','Name','My USB camera');
    %
    % Implementation notes:
    %   * Have a look at the SDK documentation for a description of camera settings. The MATLAB
    %     class is rather a wrapper for the SDK to make changing settings, etc. more easy, error
    %     proven and automatic.
    %   * The class was tested with a PCO4000 gray scale camera. This explains why a color support
    %     was not implemented from the beginning, but it should be rather easy to add to the class.
    %   * Data types in the SDK and how they translate to data types in MATLAB
    %       DWORD: 32bit unsigned integer (uint32)
    %        WORD: 16bit unsigned integer (uint16)
    %        LONG: 32bit   signed integer (int32)
    %       SHORT: 16bit   signed integer (int16)
    %        BYTE:  8bit unsigned integer (uint8)
    %         INT: 32bit   signed integer (int32)
    %   * Todo: What could, must or should be done or tested in the future
    %       * add the connection properties of the interface to the Settings property
    %
    %----------------------------------------------------------------------------------
    %   Copyright 2016 Alexander Ludwig Klein, alexludwigklein@gmail.com
    %
    %   Physics of Fluids, University of Twente
    %----------------------------------------------------------------------------------
    
    %% Properties
    properties (GetAccess = public, SetAccess = public, Dependent = true)
        % Description Description of the camera (structure)
        %
        % The fields of the structure are a combination of the PCO structures PCO_CameraType,
        % PCO_Description1 and PCO_Description2. The first part of each fieldname in PCO format
        % indicates the data type, which is removed here since some values are converted to human
        % readable format (e.g. wCamType is converted to a CamType, a string with the camera name)
        % or other data types (e.g. all numeric values are converted to double).
        Description
        % Health Health status and temperature(s) of the camera (structure)
        %
        % The fields of the structure are as follows:
        %               Error: string with current health errors
        %             Warning: string with current health warnings
        %              Status: structure with several state fields, such as IS_IN_POWERSAVE
        %      TemperatureCCD: double with temperature of the CCD in degrees celcius
        %   TemperatureCamera: double with temperature of the electronics in degrees celcius
        %    TemperaturePower: double with temperature of the power supply in degrees celcius
        Health
        % Settings Settings of the camera (structure)
        %
        % The fields of the structure are a combination of the PCO structures and get commands. Only
        % the supported settings are listed and converted to MATLAB typical formats (mostly double
        % for numeric values) and practical units, i.e. delay and exposure is set in s. The name of
        % each setting is close to the one listed in the SDK, so have a look at it for a more
        % detailed description.
        Settings
        % LoggingDetails Settings and information related to the logging feature of the class (structure)
        %
        % The fields of the structure are as follows:
        %       AveragePeriod: information given by timer object (double)
        %           BufferFix: number of timer runs without any available buffer before the buffers are re-allocated (0 disables feature) (double)
        %           BufferNum: number of buffers to use during logging (double)
        %          BufferRuns: number of times to check the buffers during a single run of the timer function (double)
        %          BufferWait: seconds to wait for buffers in SDK, 0 disables any waiting (double)
        %          DiskLogger: a VideoWriter object or a function handle when logging to disk (VideoWriter or function_handle)
        %             Enabled: true/false whether logging is enabled (logical)
        %            ErrorFcn: function to execute when an error event occurs ('' or function_handle)
        %        FinalReadout: true/false whether images are re-read after logging stopped (logical)
        %      FramesAcquired: number of frames that have been logged, read-only (double)
        %   FramesAcquiredFcn: function to excecute each time frames are a cquired ('' or function_handle)
        %        FramesExtend: number of frames to extend data structure with once it is filled up (double)
        %         HealthCheck: seconds between health/memory checks performed when the timer is running, 0 disables the feature (double)
        %       InstantPeriod: information given by timer object (double)
        %         MemoryLimit: limit of memory usage in MiB to output a warning (double)
        %                Mode: mode of logging as char that is 'disk', 'memory' or 'disk&memory' (char)
        %          PreviewFcn: function to show a preview based on the last image read from the camera ('' or function_handle)
        %    PreviewTransform: function to transform the preview image ('' or function_handle)
        %        RunningTimer: char 'on' or 'off'  whether the timer of the object is currently running (char)
        %            StartFcn: function to execute when the timer is started ('' or function_handle)
        %             StopFcn: function to execute when the timer is stoped ('' or function_handle)
        %            TimerFcn: function to excecute each time the timer runs ('' or function_handle)
        %         TimerPeriod: period in s of the timer that checks for new frames (double)
        %           TimerRuns: maximum number of runs the timer should perform (double)
        %           Timestamp: 14 pixel for each acquired image where PCO's binary timestamp may be (uint8 or uint16)
        %        TransformFcn: empty or function handle for a transformation of the image ('' or function_handle)
        %
        % Note: each function (except TransformFcn and PreviewFcn) given in the settings is called
        % with the object as first input and the event structure of the timer as second (or empty if
        % not applicable). The TransformFcn is called with a single image as first and only input.
        % The PreviewFcn is called with the object as first input, the last acquired frame as second
        % input and the timestamp pixels as third input, for initialization of the preview the
        % function is called with the object as only input argument (that way the number of input
        % arguments determines the state, where three input arguments mean a display run and one
        % input argument means an initialization run, see obj.preview for an example)
        %
        %
        % Principle of logging: the buffer management of the driver is controlled by MATLAB via a
        % timer function that checks periodically for new images and transfers new images to MATLAB
        % for any further processing, such as logging to disk via a VideoWriter. Logging depends on
        % the camera settings:
        %   * obj.Settings.StorageMode is set to 'fifo': multiple buffers are used to read images in
        %     consecutive order into the Data property or streamed to disk. The logging stops with
        %     the recording, i.e. the obj.Running state if at least one image has been read. In case
        %     the logging is stopped first, the recording is stopped as well. Remaining images are
        %     read if this option is enabled.
        %   * obj.Settings.StorageMode is set to 'recorder' and obj.Settings.RecorderMode is set to
        %     'sequence': multiple buffers are used to read images into the Data property, but the
        %     correct order is not ensured by the hardware (images can be used for a live preview).
        %     Once the recording stops, all images in the camera memory are re-read and transfered
        %     in consecutive order to the Data property (if enabled). In case the logging is stopped
        %     first, the recording is stopped as well. In case the recorder mode is set to 'ring',
        %     the final readout from the camera memory is ommitted and the recording is NOT stopped
        %     as well.
        %   * if the logging mode is set to 'disk', the last image streamed to disk is also
        %     available in the Data property, e.g. for a live check of the recording.
        %
        % This feature does not need to be used to read images from the camera. All buffer function
        % can be accessed (are public), such that any user can take care of the buffer management
        % and image read out.
        LoggingDetails
        % Logging True/false whether the object is logging data (logical)
        Logging
        % Data The images read from the camera with fixed rotation as 4D array (uint8 or uint16)
        %
        % Initialize the Data property by setting it to an empty array or a certain number of
        % frames, during recording the Data structure is extended when needed (see LoggingDetails),
        % the data is stored as 4D array, i.e. Width X Height X Depth (1 for BW camera) X Frame
        Data
        % Armed True/false whether the camera was armed after last change of settings (logical)
        %
        % Set this property to true to arm the camera, i.e. apply settings and check camera health
        Armed
        % Running Recording state of the camera, true: camera is running, false: camera is idle (logical)
        %
        % Set this property to true to initiate a recording, set it to false to stop a recording
        Running
        % Verbose Indicates how much to output, for example during logging (double)
        %
        %  <   0: Print no output to command line
        %  >   0: Print more information to commmand line
        %  > 100: Print all information to commmand line
        Verbose
        % UnloadCamera True/false whether to unload the camera when the object is deleted (double)
        UnloadCamera
        % UnloadSDK True/false whether to unload the SDK when the object is deleted (double)
        UnloadSDK
    end
    
    properties (GetAccess = public, SetAccess = protected, Dependent = true)
        % AcquisitionSignal Get the current status of the <acq enbl> user input at the camera (logical)
        AcquisitionSignal
        % Available In case of a bus reset you can check whether the device is still valid (logical)
        Available
        % Buffer Returns the data of the current buffers (structure)
        %
        % The output is similar to obj.p_Buffer, but does not include the pointers but the actual
        % data of the buffers, mainly a short hand to obj.p_Buffer.im_ptr.Value, returns an empty
        % array if no buffer is allocated
        Buffer
        % Busy True/false whether the camera is still busy, i.e. exposure or readout (logical)
        Busy
        % COCRuntime Returns the camera operation code in s, may be used to calculate the maximum FPS of the hardware (double)
        COCRuntime
        % FramesAcquired Number of frames in data property (double)
        FramesAcquired
        % Locked True/false whether the object is locked
        %
        % The object can be locked by the logging feature te prevent any read out while images are
        % streamed form the camera to the Data property
        Locked
        % Memory Memory usage in MiB of stored data (double)
        Memory
        % NumberOfAvailableBuffer Get the total number of buffers allocated in this class (double)
        %
        % Note: it does not check the driver, but only the MATLAB class which should keep track of the buffers
        NumberOfAvailableBuffer
        % NumberOfPendingBuffer Get the number of pending buffers while the camera is recording (double)
        NumberOfPendingBuffer
        % Timestamp Timestamp pixels of the data stored in Data property (uint8 or uint16)
        %
        % 14 pixel for each image where PCO's binary timestamp might be, i.e. n x 14
        Timestamp
    end
    
    properties (GetAccess = public, SetAccess = protected, Dependent = true, Hidden = true)
        % PCO_SDK_ALIAS The alias of the SDK (char)
        PCO_SDK_ALIAS
        % PC_CameraHandle The pointer to the camera (lib.pointer)
        PCO_CameraHandle
        % PCO_CameraType Easy access to SDK library structure (see p_SDK)
        PCO_CameraType
        % PCO_Description1 Easy access to SDK library structure (see p_SDK)
        PCO_Description1
        % PCO_Description2 Easy access to SDK library structure (see p_SDK)
        PCO_Description2
        % PCO_Timing Easy access to SDK library structure (see p_SDK)
        PCO_Timing
        % PCO_Sensor Easy access to SDK library structure (see p_SDK)
        PCO_Sensor
        % PCO_Storage Easy access to SDK library structure (see p_SDK)
        PCO_Storage
        % PCO_Recording Easy access to SDK library structure (see p_SDK)
        PCO_Recording
    end
    
    properties (GetAccess = public, SetAccess = public, Transient = true)
        % Name A short name for the device (char)
        Name = 'PCO';
        % UserData Userdata linked to the device (arbitrary)
        UserData = [];
    end
    
    properties (GetAccess = protected, SetAccess = protected, Transient = true)
        % p_ActiveSegment Index of the active RAM segment
        p_ActiveSegment
        % p_Description Storage for description
        p_Description
        % p_SDK Place to store helpers for the connection to the SDK (structure)
        %
        %  The following information is stored here:
        %           alias: name of the SDK as char
        %      closeAtEnd: true/false whether to close camera when the object is deleted
        %     unloadAtEnd: true/false whether to unload the library when the object is deleted
        %       camHandle: handle to the camera as a lib.pointer object
        %       camNumber: number of camera at the interface (starts with 0)
        %   userCalledArm: true/false whether the user armed the camera after a settings change
        %
        % In addition, the library of the SDK needs C structures as input, which can be accessed via
        % class properties for easy access and their size set to the correct value (see wSize in SDK
        % manual for PCO_GetGeneral). The actual storage is in the class property p_SDK, but they
        % get set the first time in their corresponding get method:
        %            PCO_CameraType: PCO_CameraType
        %          PCO_Description1: PCO_Description1
        %          PCO_Description2: PCO_Description2
        %                PCO_Timing: PCO_Timing
        %                PCO_Sensor: PCO_Sensor
        %               PCO_Storage: PCO_Storage
        %             PCO_Recording: PCO_Recording
        p_SDK = struct(...
            'alias',          'PCO_CAM_SDK',...
            'closeAtEnd',     false,...
            'unloadAtEnd',    false,...
            'camHandle',      [],...
            'camNumber',      0,...
            'userCalledArm',  false,...
            'PCO_CameraType', [], 'PCO_Description1',[], 'PCO_Description2', [], 'PCO_Timing',  [],...
            'PCO_Storage',    [], 'PCO_Recording',   [], 'PCO_Sensor',       []);
        % p_Buffer Place to store the buffer(s) of the SDK (empty or structure)
        %
        %  In case no buffer is allocated the property is set to an empty array, otherwise the
        %  following information is stored here as structure:
        %            Image: a place to store the image of the buffer (uint8 or uint16)
        %         BufferID: the buffer number as known to the SDK (int16)
        %           im_ptr: a pointer to the actual buffer of the SDK (lib.pointer)
        %           ev_ptr: a pointer to an event of the SDK (lib.pointer)
        %     BitsPerPixel: bits per pixel of the image data (double)
        %        ImageSize: the size of the image on the camera excluding LineAdd (double
        %             Size: Size of the buffer in bytes (double)
        %   NumberOfImages: the number of images the buffer was made for (double)
        %             Free: treu/false whether freeBuffer was called for this buffer (logical)
        %          LineAdd: number of lines added to the image for FireWire connection (double)
        %         UserData: a place to store additional information, e.g. index of image (arbitrary)
        p_Buffer = [];
        % p_Log Storage for LoggingDetails and additional information (empty or structure)
        %
        % The fields of the structure in addition to LoggingDetails are as follows:
        %        BufferIdx: indices of buffer(s) created for the logging (double)
        %  BufferOnceAdded: true\false whether buffer have been added for the first time (logical)
        %       HealthLast: last time the health check was performed (output of tic)
        %     PausePreview: true false whether to not update the current preview (logical)
        %     RecorderMode: shorthand to obj.Settings.RecorderMode (char)
        %      StorageMode: shorthand to obj.Settings.StorageMode (char)
        %            Timer: timer object (timer)
        p_Log = [];
        % p_Data Storage for Data
        p_Data = uint16.empty;
        % p_DataIndex Last index in p_Data property that is an actual recorded image, any larger
        % index is initialized for a readout but not yet used
        p_DataIndex = 0;
        % p_Timestamp Storage for Timestamp
        p_Timestamp = uint16.empty;
        % p_Verbose Storage for Verbose
        p_Verbose = 1;
        % p_Locked Storage for Locked
        p_Locked = false;
    end
    
    properties (GetAccess = public, Constant = true, Hidden = true)
        % Table_CameraType Known camera types with name and HEX code according to sc2_defs.h
        Table_CameraType = {
            'PCO1200HS'             '0x0100'
            'PCO1300'               '0x0200'
            'PCO1600'               '0x0220'
            'PCO2000'               '0x0240'
            'PCO4000'               '0x0260'
            'ROCHEHTC'              '0x0800'
            '284XS'                 '0x0800'
            'KODAK1300OEM'          '0x0820'
            'PCO1400'               '0x0830'
            'NEWGEN'                '0x0840'
            'PROVEHR'               '0x0850'
            'PCO_USBPIXELFLY'       '0x0900'
            'PCO_DIMAX_STD'         '0x1000'
            'PCO_DIMAX_TV'          '0x1010'
            'PCO_DIMAX_AUTOMOTIVE'  '0x1020'
            'SC3_SONYQE'            '0x1200'
            'SC3_EMTI'              '0x1210'
            'SC3_KODAK4800'         '0x1220'
            'PCO_EDGE'              '0x1300'
            'PCO_EDGE_42'           '0x1302'
            'PCO_EDGE_GL'           '0x1310'
            'PCO_EDGE_USB3'         '0x1320'
            'PCO_EDGE_HS'           '0x1340'
            'PCO_FLIM'              '0x1400'
            'PCO_FLOW'              '0x1500'
            };
        % Table_SensorType Known sensor types with name and HEX code according to sc2_defs.h
        Table_SensorType = {
            'ICX285AL'              '0x0010'
            'ICX285AK'              '0x0011'
            'ICX263AL'              '0x0020'
            'ICX263AK'              '0x0021'
            'ICX274AL'              '0x0030'
            'ICX274AK'              '0x0031'
            'ICX407AL'              '0x0040'
            'ICX407AK'              '0x0041'
            'ICX414AL'              '0x0050'
            'ICX414AK'              '0x0051'
            'ICX407BLA'             '0x0060'
            'KAI2000M'              '0x0110'
            'KAI2000CM'             '0x0111'
            'KAI2001M'              '0x0120'
            'KAI2001CM'             '0x0121'
            'KAI2002M'              '0x0122'
            'KAI2002CM'             '0x0123'
            'KAI4010M'              '0x0130'
            'KAI4010CM'             '0x0131'
            'KAI4011M'              '0x0132'
            'KAI4011CM'             '0x0133'
            'KAI4020M'              '0x0140'
            'KAI4020CM'             '0x0141'
            'KAI4021M'              '0x0142'
            'KAI4021CM'             '0x0143'
            'KAI4022M'              '0x0144'
            'KAI4022CM'             '0x0145'
            'KAI11000M'             '0x0150'
            'KAI11000CM'            '0x0151'
            'KAI11002M'             '0x0152'
            'KAI11002CM'            '0x0153'
            'KAI16000AXA'           '0x0160'
            'KAI16000CXA'           '0x0161'
            'MV13BW'                '0x1010'
            'MV13COL'               '0x1011'
            'CIS2051_V1_FI_BW'      '0x2000'
            'CIS2051_V1_FI_COL'     '0x2001'
            'CIS1042_V1_FI_BW'      '0x2002'
            'CIS2051_V1_BI_BW'      '0x2010'
            'TC285SPD'              '0x2120'
            'CYPRESS_RR_V1_BW'      '0x3000'
            'CYPRESS_RR_V1_COL'     '0x3001'
            'CMOSIS_CMV12000_BW'    '0x3100'
            'CMOSIS_CMV12000_COL'   '0x3101'
            'QMFLIM_V2B_BW'         '0x4000'
            };
        % Table_Interface Known interfaces with name and HEX code according to sc2_defs.h
        Table_Interface = {
            'FIREWIRE'              '0x0001'
            'CAMERALINK'            '0x0002'
            'USB'                   '0x0003'
            'ETHERNET'              '0x0004'
            'SERIAL'                '0x0005'
            'USB3'                  '0x0006'
            'CAMERALINKHS'          '0x0007'
            'COAXPRESS'             '0x0008'
            };
        % Table_BufferStatus Known buffer states and HEX mask according to SDK manual
        Table_BufferStatus = {
            'ALLOCATED'             '0x80000000'
            'EVENT_INSIDE_SDK'      '0x40000000'
            'ALLOCATED_EXTERN'      '0x20000000'
            'EVENT_SET'             '0x00008000'
            };
        % Table_Warning Known warnings with cause and HEX mask according to sc2_defs.h
        Table_Warning = {
            'POWERSUPPLYVOLTAGERANGE'   '0x00000001'
            'POWERSUPPLYTEMPERATURE'    '0x00000002'
            'CAMERATEMPERATURE'         '0x00000004'
            'SENSORTEMPERATURE'         '0x00000008'
            'EXTERNAL_BATTERY_LOW'      '0x00000010'
            'OFFSET_REGULATION_RANGE'   '0x00000020'
            };
        % Table_Warning Known errors with cause and HEX mask according to sc2_defs.h
        Table_Error = {
            'POWERSUPPLYVOLTAGERANGE'   '0x00000001'
            'POWERSUPPLYTEMPERATURE'    '0x00000002'
            'CAMERATEMPERATURE'         '0x00000004'
            'SENSORTEMPERATURE'         '0x00000008'
            'EXTERNAL_BATTERY_LOW'      '0x00000010'
            'CAMERAINTERFACE'           '0x00010000'
            'CAMERARAM'                 '0x00020000'
            'CAMERAMAINBOARD'           '0x00040000'
            'CAMERAHEADBOARD'           '0x00080000'
            };
        % Table_Status Known status with cause and HEX mask according to sc2_defs.h
        Table_Status = {
            'DEFAULT_STATE'             '0x00000001'
            'SETTINGS_VALID'            '0x00000002'
            'RECORDING_ON'              '0x00000004'
            'READ_IMAGE_ON'             '0x00000008'
            'FRAMERATE_VALID'           '0x00000010'
            'SEQ_STOP_TRIGGERED'        '0x00000020'
            'LOCKED_TO_EXTSYNC'         '0x00000040'
            'EXT_BATTERY_AVAILABLE'     '0x00000080'
            'IS_IN_POWERSAVE'           '0x00000100'
            'POWERSAVE_LEFT'            '0x00000200'
            'LOCKED_TO_IRIG'            '0x00000400'
            };
        % Table_GeneralCaps1 Known general feature with description and HEX mask according to sc2_defs.h
        Table_GeneralCaps1 = {
            'NOISE_FILTER'                      '0x00000001'
            'HOTPIX_FILTER'                     '0x00000002'
            'HOTPIX_ONLY_WITH_NOISE_FILTER'     '0x00000004'
            'TIMESTAMP_ASCII_ONLY'              '0x00000008'
            'DATAFORMAT2X12'                    '0x00000010'
            'RECORD_STOP'                       '0x00000020'
            'HOT_PIXEL_CORRECTION'              '0x00000040'
            'NO_EXTEXPCTRL'                     '0x00000080'
            'NO_TIMESTAMP'                      '0x00000100'
            'NO_ACQUIREMODE'                    '0x00000200'
            'DATAFORMAT4X16'                    '0x00000400'
            'DATAFORMAT5X16'                    '0x00000800'
            'NO_RECORDER'                       '0x00001000'
            'FAST_TIMING'                       '0x00002000'
            'METADATA'                          '0x00004000'
            'SETFRAMERATE_ENABLED'              '0x00008000'
            'CDI_MODE'                          '0x00010000'
            'CCM'                               '0x00020000'
            'EXTERNAL_SYNC'                     '0x00040000'
            'NO_GLOBAL_SHUTTER'                 '0x00080000'
            'GLOBAL_RESET_MODE'                 '0x00100000'
            'EXT_ACQUIRE'                       '0x00200000'
            'FAN_CONTROL'                       '0x00400000'
            'ROI_VERT_SYMM_TO_HORZ_AXIS'        '0x00800000'
            'ROI_HORZ_SYMM_TO_VERT_AXIS'        '0x01000000'
            'HW_IO_SIGNAL_DESCRIPTOR'           '0x40000000'
            'ENHANCED_DESCRIPTOR_2'             '0x80000000'
            };
    end
    
    %% Events
    events
        % newData Notify when new data is added to the Data property
        newData
        % newSettings Notify when settings of the actual device are changed
        newSettings
        % newState Notify when the state, i.e. obj.Running, is changed by the user, the class cannot
        % notify if the state is changed by the hardware
        newState
    end
    
    %% Constructor and SET/GET
    methods
        function obj = PCO(varargin)
            % PCO Creates object that links to the device
            %
            % Optional input is required when a camera needs to be accessed that is already open. In
            % such a case the input should be:
            %   1st input: pointer to the camera, data type is a lib.pointer of data type 'voidPtr'
            %   2nd input: alias to the SDK, e.g. a char such as 'PCO_CAM_SDK'
            
            %
            % get input with input parser, where inputs are mostly related to PCO's OpenCamera
            tmp               = inputParser;
            tmp.StructExpand  = true;
            tmp.KeepUnmatched = false;
            % Interface
            tmp.addParameter('Interface', 'gige', ...
                @(x) ~isempty(x) && ischar(x) && ismember(lower(x),{'usb','usb3','ethernet','gige','firewire'}));
            % Desired camera number at the desired interface, starts with 0
            tmp.addParameter('CameraNumber', 0, ...
                @(x) ~isempty(x) && isnumeric(x) && isscalar(x) && x >= 0);
            % Alias of the SDK in MATLAB
            tmp.addParameter('SDK', 'PCO_CAM_SDK', ...
                @(x) ~isempty(x) && ischar(x));
            % Camera handle (ignores then the given interface and camera number)
            tmp.addParameter('CameraHandle', [], ...
                @(x) isempty(x) ||(isa(x,'lib.pointer') && strcmp(x.DataType,'voidPtr')));
            % A name for the device
            tmp.addParameter('Name', '', ...
                @(x) isempty(x) || ischar(x));
            tmp.addParameter('showInfoOnConstruction', true, ...
                @(x) islogical(x) && isscalar(x));
            tmp.parse(varargin{:});
            tmp                    = tmp.Results;
            showInfoOnConstruction = tmp.showInfoOnConstruction;
            obj.Name               = tmp.Name;
            obj.p_SDK.alias        = tmp.SDK;
            obj.p_SDK.camNumber    = uint16(tmp.CameraNumber);
            %
            % check/load the SDK library
            try
                isLoaded = libisloaded(obj.p_SDK.alias);
            catch exception
                error(sprintf('%s:Input',mfilename),...
                    'Could not check for PCO''s SDK library (alias is ''%s'') due to: %s',...
                    obj.p_SDK.alias, exception.getReport);
            end
            if ~isLoaded
                % library is not loaded, start from scratch
                if ~isempty(tmp.CameraHandle)
                    % the camera handle was given as input by the user, but the SDK is not
                    % loaded, something must be wrong with the camera handle
                    error(sprintf('%s:Input',mfilename),...
                        ['The SDK for a PCO camera is NOT loaded, but a camera handle was given ',...
                        'as input to the class constructor ''%s'', which is unexpected, please check!',...
                        ' To unload the library use somthing like ''unloadlibrary(''%s'')'''], class(obj),obj.p_SDK.alias);
                else
                    % load the library to access PCO's SDK and get a handle to the camera
                    loadlibrary('SC2_Cam','SC2_CamMatlab.h', ...
                        'addheader','SC2_CamExport.h', ...
                        'alias', obj.p_SDK.alias);
                    obj.p_SDK.unloadAtEnd = true;
                    obj.p_SDK.closeAtEnd  = true;
                end
            else
                obj.p_SDK.unloadAtEnd = false;
                if ~isempty(tmp.CameraHandle)
                    warning(sprintf('%s:Input',mfilename), ['A camera handle was given as input, ',...
                        'assuming camera number to be 0 and camera is not closed on object deletion'], class(obj));
                    obj.p_SDK.camHandle  = tmp.CameraHandle;
                    obj.p_SDK.closeAtEnd = false;
                else
                    obj.p_SDK.closeAtEnd = true;
                end
            end
            %
            % open camera
            if obj.p_SDK.closeAtEnd
                % extended open call with options
                ph_ptr     = libpointer('voidPtrPtr');
                structOpen = libstruct('PCO_OpenStruct');
                set(structOpen,'wSize',structOpen.structsize);
                switch lower(tmp.Interface)
                    case {'ethernet' 'gige'}
                        structOpen.wInterfaceType = uint16(5);
                    case 'firewire'
                        structOpen.wInterfaceType = uint16(1);
                    case 'usb'
                        structOpen.wInterfaceType = uint16(6);
                    case 'usb3'
                        structOpen.wInterfaceType = uint16(8);
                end
                structOpen.wCameraNumber = uint16(obj.p_SDK.camNumber);
                [err, out_ptr] = mydo(obj,false,0, 'PCO_OpenCameraEx', ...
                    ph_ptr, structOpen);
                % check for errors
                if err == 0
                    obj.p_SDK.camHandle = out_ptr;
                else
                    % an error occured, try to unload the library and throw an error
                    [errU, errH] = obj.pco_err2err(err);
                    if strcmp(errH(1:3),'0x8') && strcmp(errH(end-3:end),'2001')
                        error(sprintf('%s:Input',mfilename),...
                            ['Could not open camera, error code returned by SDK is ',...
                            '%d (%s) (which means no camera connected), to unload the SDK use something like ''unloadlibrary(''%s'')'')'], ...
                            errU, errH, obj.p_SDK.alias);
                    else
                        error(sprintf('%s:Input',mfilename),...
                            ['Could not open camera, error code returned by SDK is ',...
                            '%d (%s), to unload the SDK use something like ''unloadlibrary(''%s'')'')'], ...
                            errU, errH, obj.p_SDK.alias);
                    end
                end
            end
            %
            % set the data and time of the camera and arm
            if obj.Running
                warning(sprintf('%s:Input',mfilename),...
                    'camera is already running after opening, please check!');
            else
                obj.Settings.DateTime = datetime('now');
                obj.arm;
            end
            %
            % set name
            if isempty(obj.Name)
                obj.Name = sprintf('%s-%s-%d',obj.Description.CamType,obj.Description.InterfaceType,obj.p_SDK.camNumber);
            end
            if showInfoOnConstruction
                showInfo(obj);
            end
        end
        
        function out = get.PCO_CameraHandle(obj)
            out = obj.p_SDK.camHandle;
        end
        
        function out = get.PCO_CameraType(obj)
            % read structure only once, since it holds only constant camera properties
            if isempty(obj.p_SDK.PCO_CameraType)
                obj.p_SDK.PCO_CameraType = libstruct('PCO_CameraType');
                set(obj.p_SDK.PCO_CameraType,'wSize',obj.p_SDK.PCO_CameraType.structsize);
                [~, obj.p_SDK.camHandle, obj.p_SDK.PCO_CameraType] = mydo(obj,true,0, 'PCO_GetCameraType',...
                    obj.p_SDK.camHandle, obj.p_SDK.PCO_CameraType);
            end
            out = obj.p_SDK.PCO_CameraType;
        end
        
        function out = get.PCO_Description1(obj)
            % read structure only once, since it holds only constant camera properties
            if isempty(obj.p_SDK.PCO_Description1)
                obj.p_SDK.PCO_Description1 = libstruct('PCO_Description');
                set(obj.p_SDK.PCO_Description1,'wSize',obj.p_SDK.PCO_Description1.structsize);
                [~, obj.p_SDK.camHandle, obj.p_SDK.PCO_Description1] = mydo(obj,true,0, 'PCO_GetCameraDescription',...
                    obj.p_SDK.camHandle, obj.p_SDK.PCO_Description1);
            end
            out = obj.p_SDK.PCO_Description1;
        end
        
        function out = get.PCO_Description2(obj)
            % so far it did not work out to read out the correct structure or MATLAB crashed
            % afterwards. It turned out that the structure is also contained in the sensor structure
            % by PCO, which can be read out without problem
            % Option 1: direct readout
            % [~,idx] = ismember('ENHANCED_DESCRIPTOR_2',obj.Table_GeneralCaps1(:,1));
            % bitmask = hex2dec(obj.Table_GeneralCaps1{idx,2}(3:end));
            % if bitand(uint32(obj.PCO_Description1.dwGeneralCapsDESC1),uint32(bitmask)) > 0
            %     if isempty(obj.p_SDK.PCO_Description2)
            %         obj.p_SDK.PCO_Description2 = libstruct('PCO_DescriptionEx');
            %         tmp = libstruct('PCO_Description2');
            %         set(obj.p_SDK.PCO_Description2,'wSize',tmp.structsize);
            %     end
            %     [~, obj.p_SDK.camHandle, obj.p_SDK.PCO_Description2] = mydo(obj,true,0, 'PCO_GetCameraDescriptionEx',...
            %         obj.p_SDK.camHandle, obj.p_SDK.PCO_Description2, uint16(1));
            % else
            %     obj.p_SDK.PCO_Description2 = [];
            % end
            % Option 2: read via PCO_Sensor
            if isempty(obj.p_SDK.PCO_Description2)
                [~,idx] = ismember('ENHANCED_DESCRIPTOR_2',obj.Table_GeneralCaps1(:,1));
                bitmask = hex2dec(obj.Table_GeneralCaps1{idx,2}(3:end));
                if  bitand(uint32(obj.PCO_Description1.dwGeneralCapsDESC1),uint32(bitmask)) > 0
                    obj.p_SDK.PCO_Description2 = obj.PCO_Sensor.strDescription2;
                end
            end
            out = obj.p_SDK.PCO_Description2;
        end
        
        function out = get.PCO_Timing(obj)
            if isempty(obj.p_SDK.PCO_Timing)
                obj.p_SDK.PCO_Timing = libstruct('PCO_Timing');
                set(obj.p_SDK.PCO_Timing,'wSize',obj.p_SDK.PCO_Timing.structsize);
            end
            [~, obj.p_SDK.camHandle, obj.p_SDK.PCO_Timing] = mydo(obj,true,0, 'PCO_GetTimingStruct',...
                obj.p_SDK.camHandle, obj.p_SDK.PCO_Timing);
            out = obj.p_SDK.PCO_Timing;
        end
        
        function out = get.PCO_Storage(obj)
            [~,idx] = ismember('NO_RECORDER',obj.Table_GeneralCaps1(:,1));
            bitmask = hex2dec(obj.Table_GeneralCaps1{idx,2}(3:end));
            if bitand(uint32(obj.PCO_Description1.dwGeneralCapsDESC1),uint32(bitmask)) == 0
                if isempty(obj.p_SDK.PCO_Storage)
                    obj.p_SDK.PCO_Storage = libstruct('PCO_Storage');
                    set(obj.p_SDK.PCO_Storage,'wSize',obj.p_SDK.PCO_Storage.structsize);
                end
                [~, obj.p_SDK.camHandle, obj.p_SDK.PCO_Storage] = mydo(obj,true,0, 'PCO_GetStorageStruct',...
                    obj.p_SDK.camHandle, obj.p_SDK.PCO_Storage);
            else
                obj.p_SDK.PCO_Storage = [];
            end
            out = obj.p_SDK.PCO_Storage;
        end
        
        function out = get.PCO_Sensor(obj)
            if isempty(obj.p_SDK.PCO_Sensor)
                obj.p_SDK.PCO_Sensor = libstruct('PCO_Sensor');
                set(obj.p_SDK.PCO_Sensor,'wSize',obj.p_SDK.PCO_Sensor.structsize);
            end
            [~, obj.p_SDK.camHandle, obj.p_SDK.PCO_Sensor] = mydo(obj,true,0, 'PCO_GetSensorStruct',...
                obj.p_SDK.camHandle, obj.p_SDK.PCO_Sensor);
            out = obj.p_SDK.PCO_Sensor;
        end
        
        function out = get.PCO_Recording(obj)
            if isempty(obj.p_SDK.PCO_Recording)
                obj.p_SDK.PCO_Recording = libstruct('PCO_Recording');
                set(obj.p_SDK.PCO_Recording,'wSize',obj.p_SDK.PCO_Recording.structsize);
            end
            [~, obj.p_SDK.camHandle, obj.p_SDK.PCO_Recording] = mydo(obj,true,0, 'PCO_GetRecordingStruct',...
                obj.p_SDK.camHandle, obj.p_SDK.PCO_Recording);
            out = obj.p_SDK.PCO_Recording;
        end
        
        function out = get.PCO_SDK_ALIAS(obj)
            out = obj.p_SDK.alias;
        end
        
        function out = get.Description(obj)
            if isempty(obj.p_Description)
                %
                % combine PCO structures for camera type and description 1 and 2
                out = obj.PCO_CameraType;
                fn  = fieldnames(obj.PCO_Description1);
                for i = 1:numel(fn)
                    out.(fn{i}) = obj.PCO_Description1.(fn{i});
                end
                if ~isempty(obj.PCO_Description2)
                    fn  = fieldnames(obj.PCO_Description2);
                    for i = 1:numel(fn)
                        out.(fn{i}) = obj.PCO_Description2.(fn{i});
                    end
                end
                % remove some fields
                fnDelete = {'wSize' 'ZZwAlignDummy1' 'ZZwDummy' 'ZZdwDummy' 'ZZdwDummycv' 'ZZdwDummypr',...
                    'ZZwAlignDummy3' 'wDummy1' 'wDummy2'};
                fnDelete = fnDelete(ismember(fnDelete,fieldnames(out)));
                out      = rmfields(out,fnDelete);
                %
                % transform some values to a human readable format, this may also change the data
                % typ, which is why the data typ in the variable name is removed, e.g. 'CamType'
                % instead of 'wCamType' in order not to confuse
                bak = out;
                out = struct;
                fn  = fieldnames(bak);
                for i = 1:numel(fn)
                    if strcmp(fn{i}(1:3),'str')
                        out.(fn{i}(4:end)) = bak.(fn{i});
                    elseif strcmp(fn{i}(1:2),'dw')
                        out.(fn{i}(3:end)) = double(bak.(fn{i}));
                    elseif strcmp(fn{i}(1),'w')
                        out.(fn{i}(2:end)) = double(bak.(fn{i}));
                    elseif strcmp(fn{i}(1),'s')
                        out.(fn{i}(2:end)) = double(bak.(fn{i}));
                    elseif strcmp(fn{i}(1),'l')
                        out.(fn{i}(2:end)) = double(bak.(fn{i}));
                    else
                        % copy unknown data type
                        out.(fn{i}) = bak.(fn{i});
                    end
                end
                fn = fieldnames(out);
                for i = 1:numel(fn)
                    switch fn{i}
                        case 'CamType'
                            tmp = cellfun(@(x) hex2dec(x(3:end)),obj.Table_CameraType(:,2));
                            idx = find(out.(fn{i})==tmp,1,'first');
                            if isempty(idx), out.(fn{i}) = 'unknown';
                            else,            out.(fn{i}) = obj.Table_CameraType{idx,1};
                            end
                        case 'InterfaceType'
                            tmp = cellfun(@(x) hex2dec(x(3:end)),obj.Table_Interface(:,2));
                            idx = find(out.(fn{i})==tmp,1,'first');
                            if isempty(idx), out.(fn{i}) = 'unknown';
                            else,            out.(fn{i}) = obj.Table_Interface{idx,1};
                            end
                        case 'SensorTypeDESC'
                            tmp = cellfun(@(x) hex2dec(x(3:end)),obj.Table_SensorType(:,2));
                            idx = find(out.(fn{i})==tmp,1,'first');
                            if isempty(idx), out.(fn{i}) = 'unknown';
                            else,            out.(fn{i}) = obj.Table_SensorType{idx,1};
                            end
                        case 'GeneralCapsDESC1'
                            value       = out.(fn{i});
                            out.(fn{i}) = struct;
                            for j = 1:size(obj.Table_GeneralCaps1,1)
                                tmp = hex2dec(obj.Table_GeneralCaps1{j,2}(3:end));
                                out.(fn{i}).(obj.Table_GeneralCaps1{j,1}) = ...
                                    bitand(uint32(value),uint32(tmp)) > 0;
                            end
                    end
                end
                obj.p_Description = orderfields(out);
            end
            out = obj.p_Description;
        end
        
        function       set.Description(obj,~)
            error(sprintf('%s:Input',mfilename),...
                'The description of device ''%s'' is read-only and cannot be changed',obj.Name);
        end
        
        function out = get.Settings(obj)
            %
            % copy only supported settings from the PCO structures to the class' settings property
            out = struct;
            %
            % read PCO_Sensor structure
            ms = obj.PCO_Sensor;
            switch ms.wSensorformat
                case 0,    str = 'standard';
                case 1,    str = 'extended';
                otherwise, str = 'unknown';
            end
            out.SensorFormat     = str;
            out.ROI              = double([ms.wRoiX0, ms.wRoiY0, ms.wRoiX1-ms.wRoiX0+1, ms.wRoiY1-ms.wRoiY0+1]);
            out.Binning          = double([ms.wBinHorz ms.wBinVert]);
            out.PixelRate        = double(ms.dwPixelRate);
            out.ConversionFactor = double(ms.wConvFact)/100;
            out.DoubleImage      = logical(ms.wDoubleImage);
            out.ADCOperation     = double(ms.wADCOperation);
            out.TemperatureCCDSetpoint = double(ms.sCoolSet);
            switch ms.wOffsetRegulation
                case 0,    str = 'auto';
                case 1,    str = 'off';
                otherwise, str = 'unknown';
            end
            out.OffsetMode = str;
            if obj.Description.GeneralCapsDESC1.NOISE_FILTER
                switch ms.wNoiseFilterMode
                    case 0,    str = 'off';
                    case 1,    str = 'on';
                    case 257,  str = 'on&hp';
                    otherwise, str = 'unknown';
                end
                out.NoiseFilterMode = str;
            end
            %
            % read hot pixel mode
            if obj.Description.GeneralCapsDESC1.HOT_PIXEL_CORRECTION
                tmp = uint16(0);
                [~, obj.p_SDK.camHandle, tmp] = mydo(obj,true,0, 'PCO_GetHotPixelCorrectionMode', ...
                    obj.p_SDK.camHandle, tmp);
                switch tmp
                    case 0,    str = 'off';
                    case 1,    str = 'on';
                    otherwise, str = 'unknown';
                end
                out.HotPixelCorrectionMode = str;
            end
            %
            % read PCO_Timing structure
            ms           = obj.PCO_Timing;
            out.Delay    = double(ms.dwDelayTable) * 10^(-3*(2-ms.wTimeBaseDelay)-3);
            out.Exposure = double(ms.dwExposureTable) * 10^(-3*(2-ms.wTimeBaseExposure)-3);
            switch ms.wTriggerMode
                case 0,    str = 'auto';
                case 1,    str = 'software';
                case 2,    str = 'external start';
                case 3,    str = 'external control';
                otherwise, str = 'unknown';
            end
            out.TriggerMode = str;
            switch ms.wPowerDownMode
                case 0
                    str = 'auto';
                case 1
                    str = 'user';
                otherwise
                    str = 'unknown';
            end
            out.PowerDownMode = str;
            out.PowerDownTime = double(ms.dwPowerDownTime)*1e-3;
            %
            % read PCO_Storage structure
            ms                = obj.PCO_Storage;
            out.SegmentSize   = double(ms.dwRamSegSize);
            out.SegmentActive = double(ms.wActSeg);
            out.RamSize       = double(ms.dwRamSize);
            out.PageSize      = double(ms.wPageSize);
            %
            % read PCO_Recording structure
            ms = obj.PCO_Recording;
            switch ms.wStorageMode
                case 0
                    str = 'recorder';
                case 1
                    str = 'fifo';
                otherwise
                    str = 'unknown';
            end
            out.StorageMode = str;
            switch ms.wRecSubmode
                case 0
                    str = 'sequence';
                case 1
                    str = 'ring';
                otherwise
                    str = 'unknown';
            end
            out.RecorderMode   = str;
            out.RecordingState = logical(ms.wRecState);
            switch ms.wAcquMode
                case 0
                    str = 'auto';
                case 1
                    str = 'external';
                otherwise
                    str = 'unknown';
            end
            out.AcquireMode = str;
            out.DateTime    = datetime(double(ms.wYear),double(ms.ucMonth),double(ms.ucDay),double(ms.wHour),double(ms.ucMin),double(ms.ucSec));
            switch ms.wTimeStampMode
                case 0
                    str = 'disabled';
                case 1
                    str = 'bit';
                case 2
                    str = 'bit&ascii';
                case 3
                    str = 'ascii';
                otherwise
                    str = 'unknown';
            end
            out.TimestampMode = str;
            %
            % read additional settings
            tmp = uint16(0);
            [~, obj.p_SDK.camHandle, tmp] = mydo(obj,true,0, 'PCO_GetBitAlignment', ...
                obj.p_SDK.camHandle, tmp);
            switch tmp
                case 0
                    str = 'msb';
                case 1
                    str = 'lsb';
                otherwise
                    str = 'unknown';
            end
            out.BitAlignment = str;
            ax = uint16(0);ay = uint16(0);mx = uint16(0);my = uint16(0);
            [~, obj.p_SDK.camHandle, ax, ay, mx, my] = mydo(obj,true,0, 'PCO_GetSizes', ...
                obj.p_SDK.camHandle, ax, ay, mx, my);
            out.ImageSize = double([ax ay]); out.ImageSizeMax = double([mx my]);
            %
            % prepare output
            out = orderfields(out);
        end
        
        function       set.Settings(obj,value)
            curValue = obj.Settings;
            % check if input is given as a structure, but only allow for changing specific settings
            if ~(isstruct(value) && isscalar(value) && all(ismember(fieldnames(value),fieldnames(curValue))))
                error(sprintf('%s:Input',mfilename),...
                    'Expected a scalar structure with settings as input, please check input!');
            else
                fn     = fieldnames(value);
                anynew = false;
                for i = 1:numel(fn)
                    tmp = value.(fn{i});
                    if ~isequal(tmp,curValue.(fn{i})) % only process if it changed
                        if obj.Running && ~ismember(fn{i},{'PowerDownMode','PowerDownTime'})
                            error(sprintf('%s:Input',mfilename),...
                                '%s is currently recording and the change of setting ''%s'' cannot be performed',obj.Name,fn{i});
                        end
                        anynew = true;
                        switch fn{i}
                            %
                            % Sensor related settings
                            %
                            case 'SensorFormat'
                                if ischar(tmp) && ismember(lower(tmp),{'standard' 'extended'})
                                    if strcmpi(tmp,'standard'), tmp = uint16(0);
                                    else,                       tmp = uint16(1);
                                    end
                                    mydo(obj,true,0, 'PCO_SetSensorFormat',...
                                        obj.p_SDK.camHandle, tmp);
                                else
                                    error(sprintf('%s:Input',mfilename),...
                                        '%s is expected to be a single char (''standard'', ''extended''), please check input!',fn{i});
                                end
                            case 'ROI'
                                if isnumeric(tmp) && numel(tmp) == 4 && min(tmp) > 0
                                    warning(sprintf('%s:Input',mfilename),...
                                        ['Input for ''%s'' is not checked for compatibility with the camera, ',...
                                        'please check the SDK manual for further instruction, e.g. ',...
                                        'the ROI must be symmetric when two ADC are used and the ',...
                                        ' stepping must match, see RoiHorStepsDESC and RoiVertStepsDESC '...
                                        'in the camera description'],fn{i});
                                    % translate to PCO's definition (two opposite corners)
                                    x1  = uint16(tmp(1)); y1 = uint16(tmp(2)); x2 = uint16(x1+tmp(3)-1); y2 = uint16(y1+tmp(4)-1);
                                    mydo(obj,true,0, 'PCO_SetROI',...
                                        obj.p_SDK.camHandle, x1, y1, x2, y2);
                                else
                                    error(sprintf('%s:Input',mfilename),...
                                        '%s is expected to be a numeric input with four elements each greater than zero, please check input!',fn{i});
                                end
                            case 'Binning'
                                if isnumeric(tmp) && numel(tmp) == 2 && min(tmp) > 0
                                    warning(sprintf('%s:Input',mfilename),...
                                        ['Input for ''%s'' is not checked for compatibility with the camera, ',...
                                        'please check the SDK manual for further instruction'],fn{i});
                                    mydo(obj,true,0, 'PCO_SetBinning',...
                                        obj.p_SDK.camHandle, uint16(tmp(1)), uint16(tmp(2)));
                                else
                                    error(sprintf('%s:Input',mfilename),...
                                        '%s is expected to be a numeric input with two elements each greater than zero, please check input!',fn{i});
                                end
                            case 'PixelRate'
                                if isnumeric(tmp) && isscalar(tmp) && tmp > 0 && ...
                                        ismember(round(tmp),obj.Description.PixelRateDESC)
                                    mydo(obj,true,0, 'PCO_SetPixelRate',...
                                        obj.p_SDK.camHandle, uint32(tmp));
                                else
                                    error(sprintf('%s:Input',mfilename),...
                                        '%s is expected to be a scalar numeric input in a certain range, please check input!',fn{i});
                                end
                            case 'ConversionFactor'
                                if isnumeric(tmp) && isscalar(tmp) && tmp > 0 && ...
                                        ismember(round(tmp*100),obj.Description.ConvFactDESC)
                                    mydo(obj,true,0, 'PCO_SetConversionFactor',...
                                        obj.p_SDK.camHandle, uint16(tmp*100));
                                else
                                    error(sprintf('%s:Input',mfilename),...
                                        '%s is expected to be a scalar numeric input in a certain range, please check input!',fn{i});
                                end
                            case 'DoubleImage'
                                if islogical(tmp) && isscalar(tmp)
                                    % CDI_MODE is false for a PCO4000 although it supports it, error
                                    % is put in comment here
                                    % if tmp && ~obj.Description.GeneralCapsDESC1.CDI_MODE
                                    %     error(sprintf('%s:Input',mfilename),...
                                    %         '%s does not support double image mode, please check!',obj.Name);
                                    % end
                                    mydo(obj,true,0, 'PCO_SetDoubleImageMode',...
                                        obj.p_SDK.camHandle, uint16(tmp));
                                else
                                    error(sprintf('%s:Input',mfilename),...
                                        '%s is expected to be a scalar logical, please check input!',fn{i});
                                end
                            case 'OffsetMode'
                                if ischar(tmp) && ismember(lower(tmp),{'auto' 'off'})
                                    if strcmpi(tmp,'auto'), tmp = uint16(0);
                                    else,                   tmp = uint16(1);
                                    end
                                    mydo(obj,true,0, 'PCO_SetOffsetMode', ...
                                        obj.p_SDK.camHandle, tmp);
                                else
                                    error(sprintf('%s:Input',mfilename),...
                                        '%s is expected to be a single char (''auto'', ''off''), please check input!',fn{i});
                                end
                            case 'NoiseFilterMode'
                                if ischar(tmp) && ismember(lower(tmp),{'on' 'off' 'on&hp'})
                                    if ~obj.Description.GeneralCapsDESC1.NOISE_FILTER
                                        error(sprintf('%s:Input',mfilename),...
                                            '%s does not support a noise filter, please check!',obj.Name);
                                    end
                                    if     strcmpi(tmp,'off'), tmp = uint16(0);
                                    elseif strcmpi(tmp,'on'),  tmp = uint16(1);
                                    else,                      tmp = uint16(257);
                                    end
                                    mydo(obj,true,0, 'PCO_SetNoiseFilterMode', ...
                                        obj.p_SDK.camHandle, tmp);
                                else
                                    error(sprintf('%s:Input',mfilename),...
                                        '%s is expected to be a single char (''on'', ''off'', ''on&hp''), please check input!',fn{i});
                                end
                            case 'HotPixelCorrectionMode'
                                if ischar(tmp) && ismember(lower(tmp),{'on' 'off'})
                                    if ~obj.Description.GeneralCapsDESC1.HOT_PIXEL_CORRECTION
                                        error(sprintf('%s:Input',mfilename),...
                                            '%s does not support hot pixel correction, please check!',obj.Name);
                                    end
                                    if     strcmpi(tmp,'off'), tmp = uint16(0);
                                    elseif strcmpi(tmp,'on'),  tmp = uint16(1);
                                        if obj.Description.GeneralCapsDESC1.HOTPIX_ONLY_WITH_NOISE_FILTER
                                            warning(sprintf('%s:Input',mfilename),['%s does support ',...
                                                'hot pixel correction only with noise filter, ',...
                                                'please make sure to enable noise filter as well!'],obj.Name);
                                        end
                                    end
                                    mydo(obj,true,0, 'PCO_SetHotPixelCorrectionMode', ...
                                        obj.p_SDK.camHandle, tmp);
                                else
                                    error(sprintf('%s:Input',mfilename),...
                                        '%s is expected to be a single char (''on'', ''off''), please check input!',fn{i});
                                end
                            case 'TemperatureCCDSetpoint'
                                if isnumeric(tmp) && isscalar(tmp) && round(tmp) >= obj.Description.MinCoolSetDESC && ...
                                        round(tmp) <= obj.Description.MaxCoolSetDESC
                                    mydo(obj,true,0, 'PCO_SetCoolingSetpointTemperature',...
                                        obj.p_SDK.camHandle, int16(tmp));
                                else
                                    error(sprintf('%s:Input',mfilename),...
                                        '%s is expected to be a scalar numeric input in a certain range, please check input!',fn{i});
                                end
                            case 'ADCOperation'
                                if isnumeric(tmp) && isscalar(tmp) && round(tmp) >= 1 && ...
                                        round(tmp) <= obj.Description.NumADCsDESC
                                    mydo(obj,true,0, 'PCO_SetADCOperation',...
                                        obj.p_SDK.camHandle, uint16(tmp));
                                else
                                    error(sprintf('%s:Input',mfilename),...
                                        '%s is expected to be a scalar numeric input in a certain range, please check input!',fn{i});
                                end
                                %
                                % Timing related settings
                                %
                            case 'Delay'
                                if isnumeric(tmp) && isfloat(tmp) && numel(tmp) <= 16 && min(tmp) >= 0 &&...
                                        all(tmp<=obj.Description.MaxDelayDESC*1e-3) && all(tmp>=obj.Description.MinDelayDESC*1e-9)
                                    tmp2               = zeros(1,16);
                                    tmp2(1:numel(tmp)) = tmp(:);
                                    if obj.Description.TimeTableDESC < 1 && any(tmp(2:end) > 0)
                                        error(sprintf('%s:Input',mfilename),...
                                            '%s does not support a time table mode, please check input!',obj.Name);
                                    end
                                    % find timebase and convert values
                                    if max(tmp2) < 4.29
                                        time = uint32(tmp2 * 1e9);
                                        base = uint16(0); % ns timebase
                                    elseif max(tmp2) < 4.29e3
                                        time = uint32(tmp2 * 1e6);
                                        base = uint16(1); % us timebase
                                    else
                                        time = uint32(tmp2 * 1e3);
                                        base = uint16(2); % ms timebase
                                    end
                                    % call PCO_SetDelayExposureTimeTable if a full table was given,
                                    % otherwise, call PCO_SetDelayExposureTime
                                    ms  = obj.PCO_Timing;
                                    if any(tmp(2:end) > 0)
                                        mydo(obj,true,0, 'PCO_SetDelayExposureTimeTable',...
                                            obj.p_SDK.camHandle, time, ms.dwExposureTable, base, ms.wTimeBaseExposure, uint16(16));
                                    else
                                        mydo(obj,true,0, 'PCO_SetDelayExposureTimeTable',...
                                            obj.p_SDK.camHandle, time(1), ms.dwExposureTable(1), base, ms.wTimeBaseExposure);
                                    end
                                else
                                    error(sprintf('%s:Input',mfilename),...
                                        '%s is expected to be a double input with no more than 16 elements in a certain range, please check input!',fn{i});
                                end
                            case 'Exposure'
                                if isnumeric(tmp) && isfloat(tmp) && numel(tmp) <= 16 && min(tmp) >= 0 &&...
                                        all(tmp<=obj.Description.MaxExposureDESC*1e-3) && all(tmp>=obj.Description.MinExposureDESC*1e-9)
                                    tmp2               = zeros(1,16);
                                    tmp2(1:numel(tmp)) = tmp(:);
                                    if obj.Description.TimeTableDESC < 1 && any(tmp(2:end) > 0)
                                        error(sprintf('%s:Input',mfilename),...
                                            '%s does not support a time table mode, please check input!',obj.Name);
                                    end
                                    % find timebase and convert values
                                    if max(tmp2) < 4.29
                                        time = uint32(tmp2 * 1e9);
                                        base = uint16(0); % ns timebase
                                    elseif max(tmp2) < 4.29e3
                                        time = uint32(tmp2 * 1e6);
                                        base = uint16(1); % us timebase
                                    else
                                        time = uint32(tmp2 * 1e3);
                                        base = uint16(2); % ms timebase
                                    end
                                    % call PCO_SetDelayExposureTimeTable if a full table was given,
                                    % otherwise, call PCO_SetDelayExposureTime
                                    ms  = obj.PCO_Timing;
                                    if any(tmp(2:end) > 0)
                                        mydo(obj,true,0, 'PCO_SetDelayExposureTimeTable',...
                                            obj.p_SDK.camHandle, ms.dwDelayTable, time, ms.wTimeBaseDelay, base, uint16(16));
                                    else
                                        mydo(obj,true,0, 'PCO_SetDelayExposureTime',...
                                            obj.p_SDK.camHandle, ms.dwDelayTable(1), time(1), ms.wTimeBaseDelay, base);
                                    end
                                else
                                    error(sprintf('%s:Input',mfilename),...
                                        '%s is expected to be a double input with no more than 16 elements in a certain range, please check input!',fn{i});
                                end
                            case 'TriggerMode'
                                if ischar(tmp) && ismember(lower(tmp),{'auto' 'software' 'external start', 'external control'})
                                    switch lower(tmp)
                                        case 'auto'
                                            tmp = uint16(0);
                                        case 'software'
                                            tmp = uint16(1);
                                        case 'external start'
                                            tmp = uint16(2);
                                        case 'external control'
                                            if obj.Description.GeneralCapsDESC1.NO_EXTEXPCTRL
                                                error(sprintf('%s:Input',mfilename),...
                                                    '%s does not support external exposure control, please check!',obj.Name);
                                            end
                                            tmp = uint16(3);
                                    end
                                    mydo(obj,true,0, 'PCO_SetTriggerMode', ...
                                        obj.p_SDK.camHandle, tmp);
                                else
                                    error(sprintf('%s:Input',mfilename),...
                                        '%s is expected to be a single char (''auto'', ''software'', ''external start'', ''external control''), please check input!',fn{i});
                                end
                            case 'PowerDownMode'
                                if ischar(tmp) && ismember(lower(tmp),{'auto' 'user'})
                                    switch lower(tmp)
                                        case 'auto'
                                            tmp = uint16(0);
                                        case 'user'
                                            tmp = uint16(1);
                                    end
                                    mydo(obj,true,0, 'PCO_SetPowerDownMode', ...
                                        obj.p_SDK.camHandle, tmp);
                                else
                                    error(sprintf('%s:Input',mfilename),...
                                        '%s is expected to be a single char (''auto'', ''user''), please check input!',fn{i});
                                end
                            case 'PowerDownTime'
                                if isnumeric(tmp) && isfloat(tmp) && isscalar(tmp) && tmp >= 0
                                    tmp = uint16(tmp*1e3);
                                    mydo(obj,true,0, 'PCO_SetUserPowerDownTime', ...
                                        obj.p_SDK.camHandle, tmp);
                                else
                                    error(sprintf('%s:Input',mfilename),...
                                        '%s is expected to be a scalar double greater than zero, please check input!',fn{i});
                                end
                                %
                                % Storage related settings
                                %
                            case 'SegmentSize'
                                ms = obj.PCO_Storage;
                                if isnumeric(tmp) && numel(tmp) == 4 && min(tmp) >= 0 && sum(tmp) > 0 &&...
                                        sum(tmp) <= double(ms.dwRamSize)
                                    warning(sprintf('%s:Input',mfilename),...
                                        ['Input for ''%s'' is not fully checked for compatibility with the camera, ',...
                                        'please check the SDK manual for further instruction'],fn{i});
                                    tmp = uint32(tmp);
                                    mydo(obj,true,0, 'PCO_SetCameraRamSegmentSize',...
                                        obj.p_SDK.camHandle, tmp);
                                else
                                    error(sprintf('%s:Input',mfilename),...
                                        '%s is expected to be a numeric input with four elements in a certain range, please check input!',fn{i});
                                end
                            case 'SegmentActive'
                                if isnumeric(tmp) && isscalar(tmp) && ismember(tmp,[1 2 3 4])
                                    mydo(obj,true,0, 'PCO_SetActiveRamSegment',...
                                        obj.p_SDK.camHandle, uint16(tmp));
                                else
                                    error(sprintf('%s:Input',mfilename),...
                                        '%s is expected to be a scalar numeric input between one and four, please check input!',fn{i});
                                end
                                %
                                % Recording related settings
                                %
                            case 'StorageMode'
                                if ischar(tmp) && ismember(lower(tmp),{'recorder' 'fifo'})
                                    switch lower(tmp)
                                        case 'recorder'
                                            tmp = uint16(0);
                                        case 'fifo'
                                            tmp = uint16(1);
                                    end
                                    mydo(obj,true,0, 'PCO_SetStorageMode', ...
                                        obj.p_SDK.camHandle, tmp);
                                else
                                    error(sprintf('%s:Input',mfilename),...
                                        '%s is expected to be a single char (''recorder'', ''fifo''), please check input!',fn{i});
                                end
                            case 'RecorderMode'
                                if ischar(tmp) && ismember(lower(tmp),{'sequence' 'ring'})
                                    switch lower(tmp)
                                        case 'sequence'
                                            tmp = uint16(0);
                                        case 'ring'
                                            tmp = uint16(1);
                                    end
                                    mydo(obj,true,0, 'PCO_SetRecorderSubmode', ...
                                        obj.p_SDK.camHandle, tmp);
                                else
                                    error(sprintf('%s:Input',mfilename),...
                                        '%s is expected to be a single char (''sequence'', ''ring''), please check input!',fn{i});
                                end
                            case 'RecordingState'
                                obj.Running = tmp;
                            case 'AcquireMode'
                                if ischar(tmp) && ismember(lower(tmp),{'auto' 'external'}) % modulation mode is not supported
                                    if obj.Description.GeneralCapsDESC1.NO_ACQUIREMODE
                                        error(sprintf('%s:Input',mfilename),...
                                            '%s does not support an acquire mode, please check!',obj.Name);
                                    end
                                    switch lower(tmp)
                                        case 'auto'
                                            tmp = uint16(0);
                                        case 'external'
                                            tmp = uint16(1);
                                    end
                                    mydo(obj,true,0, 'PCO_SetAcquireMode', ...
                                        obj.p_SDK.camHandle, tmp);
                                else
                                    error(sprintf('%s:Input',mfilename),...
                                        '%s is expected to be a single char (''auto'', ''external''), please check input!',fn{i});
                                end
                            case 'DateTime'
                                if isdatetime(tmp)
                                    mydo(obj,true,0, 'PCO_SetDateTime', ...
                                        obj.p_SDK.camHandle, uint8(tmp.Day), uint8(tmp.Month), uint16(tmp.Year),...
                                        uint16(tmp.Hour), uint8(tmp.Minute), uint8(tmp.Second));
                                else
                                    error(sprintf('%s:Input',mfilename),...
                                        '%s is expected to be datetime, please check input!',fn{i});
                                end
                            case 'TimestampMode'
                                if ischar(tmp) && ismember(lower(tmp),{'disabled' 'bit' 'bit&ascii' 'ascii'})
                                    if obj.Description.GeneralCapsDESC1.NO_TIMESTAMP
                                        error(sprintf('%s:Input',mfilename),...
                                            '%s does not support time stamps, please check!',obj.Name);
                                    end
                                    switch lower(tmp)
                                        case 'disabled'
                                            tmp = uint16(0);
                                        case 'bit'
                                            tmp = uint16(1);
                                        case 'bit&ascii'
                                            tmp = uint16(2);
                                        case 'ascii'
                                            if ~obj.Description.GeneralCapsDESC1.TIMESTAMP_ASCII_ONLY
                                                error(sprintf('%s:Input',mfilename),...
                                                    '%s does not support ASCII only mode, please check input!',obj.Name);
                                            end
                                            tmp = uint16(3);
                                    end
                                    mydo(obj,true,0, 'PCO_SetTimestampMode', ...
                                        obj.p_SDK.camHandle, tmp);
                                else
                                    error(sprintf('%s:Input',mfilename),...
                                        '%s is expected to be a single char (''disabled'', ''bit'', ''bit&ascii'', ''ascii''), please check input!',fn{i});
                                end
                            case 'BitAlignment'
                                if ischar(tmp) && ismember(lower(tmp),{'msb' 'lsb'})
                                    switch lower(tmp)
                                        case 'msb'
                                            tmp = uint16(0);
                                        case 'lsb'
                                            tmp = uint16(1);
                                    end
                                    mydo(obj,true,0, 'PCO_SetBitAlignment', ...
                                        obj.p_SDK.camHandle, tmp);
                                else
                                    error(sprintf('%s:Input',mfilename),...
                                        '%s is expected to be a single char (''msb'', ''lsb''), please check input!',fn{i});
                                end
                            otherwise
                                error(sprintf('%s:Input',mfilename),...
                                    'Unknown or unchangeable camera setting ''%s'' for device of class ''%s''',fn{i},class(obj));
                        end
                    end
                end
                if anynew
                    obj.p_SDK.userCalledArm = false;
                    notify(obj,'newSettings');
                end
            end
        end
        
        function out = get.Health(obj)
            % read health status
            dwarn = uint32(0);
            derr  = uint32(0);
            dstat = uint32(0);
            [~, obj.p_SDK.camHandle, dwarn, derr, dstat] = mydo(obj,true,0, 'PCO_GetCameraHealthStatus',...
                obj.p_SDK.camHandle, dwarn, derr, dstat);
            % process errors
            if derr ~= 0
                [~, out.Error] = obj.catStatus(obj.Table_Error,derr);
                warning(sprintf('%s:Check',mfilename),...
                    ['%s seems to be in a critical state, please reset, check errors and switch off,',...
                    ' call reset method to bring the camera to default state!'],obj.Name);
            else
                out.Error = '';
            end
            % process warnings
            if dwarn > 0
                [~, out.Warning] = obj.catStatus(obj.Table_Warning,dwarn);
                warning(sprintf('%s:Check',mfilename),...
                    '%s seems to be in an abnormal state, please check warnings!',obj.Name);
            else
                out.Warning = '';
            end
            % process status: build structure with field for each status bit
            out.Status = obj.catStatus(obj.Table_Status,dstat);
            %
            % read temperature
            TCCD = int16(0);
            TCAM = int16(0);
            TPOW = int16(0);
            [~, obj.p_SDK.camHandle, TCCD, TCAM, TPOW] = mydo(obj,true,0, 'PCO_GetTemperature',...
                obj.p_SDK.camHandle, TCCD, TCAM, TPOW);
            if TCCD == 32768, TCCD = NaN; end
            if TCAM == 32768, TCAM = NaN; end
            if TPOW == 32768, TPOW = NaN; end
            out.TemperatureCCD    = double(TCCD)/10;
            out.TemperatureCamera = double(TCAM);
            out.TemperaturePower  = double(TPOW);
        end
        
        function       set.Health(obj,~)
            error(sprintf('%s:Input',mfilename),...
                'The health of device ''%s'' is read-only and cannot be changed',obj.Name);
        end
        
        function       set.Name(obj,value)
            if ischar(value)
                obj.Name = value;
            else
                error(sprintf('%s:Input',mfilename),...
                    'Name is expected to be a char, please check input!');
            end
        end
        
        function out = get.Running(obj)
            out = uint16(0);
            [~, obj.p_SDK.camHandle, out] = mydo(obj,true,0, 'PCO_GetRecordingState',...
                obj.p_SDK.camHandle, out);
            out = logical(out);
        end
        
        function       set.Running(obj,value)
            if islogical(value) && isscalar(value)
                if value == obj.Running
                    % camera is already in requested state
                elseif value
                    %
                    % user requested to run camera, check if camera is armed
                    if ~obj.p_SDK.userCalledArm
                        warning(sprintf('%s:Input',mfilename),...
                            '%s is not armed, which is done now to apply the settings on the hardware and check health',obj.Name);
                        obj.arm;
                    end
                    %
                    % put camera in run mode
                    mydo(obj,true,0, 'PCO_SetRecordingState',...
                        obj.p_SDK.camHandle, uint16(1));
                    notify(obj,'newState');
                else
                    % user requested to stop camera
                    mydo(obj,true,0, 'PCO_SetRecordingState',...
                        obj.p_SDK.camHandle, uint16(0));
                    notify(obj,'newState');
                end
                if value ~= obj.Running
                    error(sprintf('%s:Input',mfilename),...
                        'Running state is not correct, please check!');
                end
            else
                error(sprintf('%s:Input',mfilename),...
                    'Running is expected to be a scalar logical, please check input!');
            end
        end
        
        function out = get.Armed(obj)
            out = obj.p_SDK.userCalledArm;
        end
        
        function       set.Armed(obj,value)
            if islogical(value) && isscalar(value)
                if value
                    obj.arm;
                else
                    error(sprintf('%s:Input',mfilename), ['%s cannot be un-armed directly, ',...
                        'changing a setting requires a re-arm and, therefore, sets the ',...
                        'Armed state to false'],obj.Name);
                end
            else
                error(sprintf('%s:Input',mfilename),...
                    'Armed is expected to be a scalar logical, please check input!');
            end
        end
        
        function out = get.UnloadCamera(obj)
            out = obj.p_SDK.closeAtEnd;
        end
        
        function       set.UnloadCamera(obj,value)
            if islogical(value) && isscalar(value)
                if ~value && obj.p_SDK.unloadAtEnd
                    warning(sprintf('%s:Input',mfilename),...
                        'Not unloading the camera during object deletion also requires not to unload the SDK, adjusting UnloadSDK accordingly!');
                    obj.p_SDK.unloadAtEnd = false;
                end
                obj.p_SDK.closeAtEnd = value;
            else
                error(sprintf('%s:Input',mfilename),...
                    'UnloadCamera is expected to be a scalar logical, please check input!');
            end
        end
        
        function out = get.UnloadSDK(obj)
            out = obj.p_SDK.unloadAtEnd;
        end
        
        function       set.UnloadSDK(obj,value)
            if islogical(value) && isscalar(value)
                if value && ~obj.p_SDK.closeAtEnd
                    warning(sprintf('%s:Input',mfilename),...
                        'Unloading the SDK during object deletion also requires to unload the camera, adjusting UnloadCamera accordingly!');
                    obj.p_SDK.closeAtEnd = true;
                end
                obj.p_SDK.unloadAtEnd = value;
            else
                error(sprintf('%s:Input',mfilename),...
                    'UnloadSDK is expected to be a scalar logical, please check input!');
            end
        end
        
        function out = get.Buffer(obj)
            if isempty(obj.p_Buffer)
                out = [];
            else
                out = rmfield(obj.p_Buffer,{'BufferID' 'im_ptr' 'ev_ptr'});
            end
        end
        
        function out = get.Busy(obj)
            out = uint16(0);
            [~, obj.p_SDK.camHandle, out] = mydo(obj,true,0, 'PCO_GetCameraBusyStatus', ...
                obj.p_SDK.camHandle, out);
            out = logical(out);
        end
        
        function out = get.COCRuntime(obj)
            if ~obj.p_SDK.userCalledArm
                if obj.Running
                    warning(sprintf('%s:Input',mfilename),...
                        '%s is not armed but running, which means the COCRuntime might be wrong',obj.Name);
                else
                    warning(sprintf('%s:Input',mfilename),...
                        '%s is not armed, which is done now to get the COCRuntime with the actual settings',obj.Name);
                    obj.arm;
                end
            end
            tmp1 = uint32(0); tmp2 = uint32(0);
            [~, obj.p_SDK.camHandle, tmp1, tmp2] = mydo(obj,true,0, 'PCO_GetCOCRuntime', ...
                obj.p_SDK.camHandle, tmp1, tmp2);
            out = double(tmp1) + double(tmp2) * 1e-9;
        end
        
        function out = get.Available(obj)
            err = mydo(obj,true,0, 'PCO_CheckDeviceAvailability', ...
                obj.p_SDK.camHandle, uint16(obj.p_SDK.camNumber));
            out = err == 0;
        end
        
        function out = get.AcquisitionSignal(obj)
            tmp = uint16(0);
            [~, obj.p_SDK.camHandle, tmp] = mydo(obj,true,0, 'PCO_GetAcqEnblSignalStatus',...
                obj.p_SDK.camHandle, uint16(tmp));
            out = logical(tmp);
        end
        
        function out = get.p_ActiveSegment(obj)
            tmp = uint16(0);
            [~, obj.p_SDK.camHandle, tmp] = mydo(obj,true,0, 'PCO_GetActiveRamSegment',...
                obj.p_SDK.camHandle, uint16(tmp));
            out = double(tmp);
        end
        
        function out = get.NumberOfAvailableBuffer(obj)
            out = numel(obj.p_Buffer);
        end
        
        function out = get.NumberOfPendingBuffer(obj)
            if ~isempty(obj.p_Buffer)
                tmp = int32(0);
                [~, obj.p_SDK.camHandle,tmp] = mydo(obj,true,0, 'PCO_GetPendingBuffer', ...
                    obj.p_SDK.camHandle, tmp);
                out = double(tmp);
            else
                out = NaN;
            end
        end
        
        function out = get.FramesAcquired(obj)
            out = obj.p_DataIndex;
        end
        
        function out = get.Locked(obj)
            out = obj.p_Locked;
        end
        
        function out = get.Verbose(obj)
            out = obj.p_Verbose;
        end
        
        function       set.Verbose(obj,value)
            if isnumeric(value) && isscalar(value)
                obj.p_Verbose = double(value);
            else
                error(sprintf('%s:Input',mfilename),...
                    'Verbose must be scalar numeric, please check input!');
            end
        end
        
        function out = get.LoggingDetails(obj)
            if isempty(obj.p_Log)
                % populate structure with default values
                out.BufferFix         = 0;
                out.BufferIdx         = [];
                out.BufferNum         = 2;
                out.BufferOnceAdded   = false;
                out.BufferRuns        = 2;
                out.BufferWait        = 0;
                out.DiskLogger        = '';
                out.Enabled           = false;
                out.HealthCheck       = 5;
                out.HealthLast        = zeros(1,1,'uint64');
                out.Mode              = 'memory';
                out.ErrorFcn          = '';
                out.FinalReadout      = false;
                out.FramesAcquired    = 0;
                out.FramesExtend      = ceil(10*obj.COCRuntime);
                out.FramesAcquiredFcn = '';
                out.MemoryLimit       = 8192;
                out.PausePreview      = false;
                out.PreviewFcn        = '';
                out.PreviewTransform  = '';
                out.RecorderMode      = obj.Settings.RecorderMode;
                out.RunsWithoutBuffer = 0;
                out.StartFcn          = '';
                out.StopFcn           = '';
                out.StorageMode       = obj.Settings.StorageMode;
                out.Timer             = [];
                out.TimerFcn          = '';
                out.TimerPeriod       = 1;
                out.TimerRuns         = Inf;
                out.Timestamp         = zeros([0, 14], sprintf('uint%d', ceil(obj.Description.DynResDESC/8)*8));
                out.TransformFcn      = '';
                obj.p_Log             = orderfields(out);
            end
            %
            % return a part of p_Log to the user extended with information on timer
            fieldsDelete = {'Timer','BufferIdx','StorageMode','RecorderMode',...
                'HealthLast','BufferOnceAdded','PausePreview','RunsWithoutBuffer'};
            out = rmfield(obj.p_Log,fieldsDelete);
            if isempty(obj.p_Log.Timer)
                out.AveragePeriod = NaN;
                out.InstantPeriod = NaN;
                out.RunningTimer  = 'off';
            else
                out.AveragePeriod = obj.p_Log.Timer.AveragePeriod;
                out.InstantPeriod = obj.p_Log.Timer.InstantPeriod;
                out.RunningTimer  = obj.p_Log.Timer.Running;
            end
            out = orderfields(out);
        end
        
        function       set.LoggingDetails(obj,value)
            curValue = obj.LoggingDetails;
            % check if input is given as a structure, but only allow for changing specific settings
            if ~(isstruct(value) && isscalar(value) && all(ismember(fieldnames(value),fieldnames(curValue))))
                error(sprintf('%s:Input',mfilename),...
                    'Expected a scalar structure with logging settings as input, please check input!');
            else
                fn     = fieldnames(value);
                anynew = false; %#ok<NASGU>
                for i = 1:numel(fn)
                    tmp = value.(fn{i});
                    if ~isequal(tmp,curValue.(fn{i})) && ... % only process if it changed
                            ~ismember(fn{i},{'AveragePeriod','InstantPeriod'}) % exclude some settings that might be NaNs, etc.
                        if obj.Logging && ismember(fn{i},{'BufferNum' 'Mode' 'TimerPeriod' 'TimerRuns', 'TransformFcn'})
                            error(sprintf('%s:Input',mfilename),...
                                '%s is currently logging and the change of setting ''%s'' cannot be performed',obj.Name,fn{i});
                        end
                        anynew = true; %#ok<NASGU>
                        switch fn{i}
                            case 'BufferFix'
                                if isnumeric(tmp) && isscalar(tmp) && round(tmp) >= 0
                                    obj.p_Log.(fn{i}) = round(tmp);
                                else
                                    error(sprintf('%s:Input',mfilename),...
                                        '%s is expected to be a scalar numeric value greater or equal to zero, please check input!',fn{i});
                                end
                            case 'BufferNum'
                                if isnumeric(tmp) && isscalar(tmp) && round(tmp) > 0
                                    obj.p_Log.(fn{i}) = round(tmp);
                                else
                                    error(sprintf('%s:Input',mfilename),...
                                        '%s is expected to be a scalar numeric value greater zero, please check input!',fn{i});
                                end
                            case 'BufferWait'
                                if isnumeric(tmp) && isscalar(tmp) && tmp >= 0
                                    obj.p_Log.(fn{i}) = tmp;
                                else
                                    error(sprintf('%s:Input',mfilename),...
                                        '%s is expected to be a scalar numeric value greater or equal to zero, please check input!',fn{i});
                                end
                            case 'BufferRuns'
                                if isnumeric(tmp) && isscalar(tmp) && tmp >= 1
                                    obj.p_Log.(fn{i}) = tmp;
                                else
                                    error(sprintf('%s:Input',mfilename),...
                                        '%s is expected to be a scalar numeric value greater or equal to zero, please check input!',fn{i});
                                end
                            case 'DiskLogger'
                                if isempty(tmp)
                                    obj.p_Log.(fn{i}) = '';
                                elseif (isa(tmp,'VideoWriter') && isvalid(tmp)) || isa(tmp,'function_handle')
                                    obj.p_Log.(fn{i}) = tmp;
                                else
                                    error(sprintf('%s:Input',mfilename),...
                                        '%s is expected to be empty, a VideoWriter object or a function handle, please check input!',fn{i});
                                end
                            case 'Enabled'
                                obj.Logging = value;
                            case 'ErrorFcn'
                                if isempty(tmp)
                                    obj.p_Log.(fn{i}) = '';
                                elseif isa(tmp,'function_handle')
                                    obj.p_Log.(fn{i}) = tmp;
                                else
                                    error(sprintf('%s:Input',mfilename),...
                                        '%s is expected to be empty or a function handle, please check input!',fn{i});
                                end
                            case 'FinalReadout'
                                if islogical(tmp) && isscalar(tmp)
                                    obj.p_Log.(fn{i}) = tmp;
                                else
                                    error(sprintf('%s:Input',mfilename),...
                                        '%s is expected to be a scalar logical, please check input!',fn{i});
                                end
                            case 'FramesExtend'
                                if isnumeric(tmp) && isscalar(tmp) && round(tmp) > 0
                                    obj.p_Log.(fn{i}) = round(tmp);
                                else
                                    error(sprintf('%s:Input',mfilename),...
                                        '%s is expected to be a scalar numeric value greater zero, please check input!',fn{i});
                                end
                            case 'HealthCheck'
                                if isnumeric(tmp) && isscalar(tmp) && tmp >= 0
                                    obj.p_Log.(fn{i}) = tmp;
                                else
                                    error(sprintf('%s:Input',mfilename),...
                                        '%s is expected to be a scalar numeric value greater or equal to zero, please check input!',fn{i});
                                end
                            case 'MemoryLimit'
                                if isnumeric(tmp) && isscalar(tmp) && tmp >= 0
                                    obj.p_Log.(fn{i}) = tmp;
                                else
                                    error(sprintf('%s:Input',mfilename),...
                                        '%s is expected to be a scalar numeric value greater or equal to zero, please check input!',fn{i});
                                end
                            case 'Mode'
                                if ischar(tmp) && ismember(lower(tmp),{'disk' 'memory' 'disk&memory'})
                                    obj.p_Log.(fn{i}) = lower(tmp);
                                else
                                    error(sprintf('%s:Input',mfilename),...
                                        '%s is expected to be a single char (''disk'', ''memory'', ''disk&memory''), please check input!',fn{i});
                                end
                            case 'PreviewFcn'
                                if isempty(tmp)
                                    obj.p_Log.(fn{i}) = '';
                                elseif isa(tmp,'function_handle')
                                    obj.p_Log.(fn{i}) = tmp;
                                else
                                    error(sprintf('%s:Input',mfilename),...
                                        '%s is expected to be empty or a function handle, please check input!',fn{i});
                                end
                            case 'PreviewTransform'
                                if isempty(tmp)
                                    obj.p_Log.(fn{i}) = '';
                                elseif isa(tmp,'function_handle')
                                    obj.p_Log.(fn{i}) = tmp;
                                else
                                    error(sprintf('%s:Input',mfilename),...
                                        '%s is expected to be empty or a function handle, please check input!',fn{i});
                                end
                            case 'StartFcn'
                                if isempty(tmp)
                                    obj.p_Log.(fn{i}) = '';
                                elseif isa(tmp,'function_handle')
                                    obj.p_Log.(fn{i}) = tmp;
                                else
                                    error(sprintf('%s:Input',mfilename),...
                                        '%s is expected to be empty or a function handle, please check input!',fn{i});
                                end
                            case 'StopFcn'
                                if isempty(tmp)
                                    obj.p_Log.(fn{i}) = '';
                                elseif isa(tmp,'function_handle')
                                    obj.p_Log.(fn{i}) = tmp;
                                else
                                    error(sprintf('%s:Input',mfilename),...
                                        '%s is expected to be empty or a function handle, please check input!',fn{i});
                                end
                            case 'FramesAcquiredFcn'
                                if isempty(tmp)
                                    obj.p_Log.(fn{i}) = '';
                                elseif isa(tmp,'function_handle')
                                    obj.p_Log.(fn{i}) = tmp;
                                else
                                    error(sprintf('%s:Input',mfilename),...
                                        '%s is expected to be empty or a function handle, please check input!',fn{i});
                                end
                            case 'TimerFcn'
                                if isempty(tmp)
                                    obj.p_Log.(fn{i}) = '';
                                elseif isa(tmp,'function_handle')
                                    obj.p_Log.(fn{i}) = tmp;
                                else
                                    error(sprintf('%s:Input',mfilename),...
                                        '%s is expected to be empty or a function handle, please check input!',fn{i});
                                end
                            case 'TimerPeriod'
                                if isnumeric(tmp) && isscalar(tmp) && tmp >= 0.001
                                    obj.p_Log.(fn{i}) = tmp;
                                else
                                    error(sprintf('%s:Input',mfilename),...
                                        '%s is expected to be a scalar numeric value greater or equal to 0.001, please check input!',fn{i});
                                end
                            case 'TimerRuns'
                                if isnumeric(tmp) && isscalar(tmp) && round(tmp) >= 0
                                    obj.p_Log.(fn{i}) = round(tmp);
                                else
                                    error(sprintf('%s:Input',mfilename),...
                                        '%s is expected to be a scalar numeric value greater or equal to zero, please check input!',fn{i});
                                end
                            case 'TransformFcn'
                                if isempty(tmp)
                                    obj.p_Log.(fn{i}) = '';
                                elseif isa(tmp,'function_handle')
                                    obj.p_Log.(fn{i}) = tmp;
                                else
                                    error(sprintf('%s:Input',mfilename),...
                                        '%s is expected to be empty or a function handle, please check input!',fn{i});
                                end
                            otherwise
                                error(sprintf('%s:Input',mfilename),...
                                    'Unknown or unchangeable logging setting ''%s'' for device of class ''%s''',fn{i},class(obj));
                        end
                    end
                end
            end
        end
        
        function out = get.Logging(obj)
            if isempty(obj.p_Log)
                out = obj.LoggingDetails.Enabled;
            else
                out = obj.p_Log.Enabled;
            end
        end
        
        function       set.Logging(obj,value)
            if islogical(value) && isscalar(value)
                %
                % make sure the logging settings are initialized
                obj.Logging;
                %
                % set logging state
                if value == obj.Logging
                    % logging is in requested state, check for the timer
                    if value && isempty(obj.p_Log.Timer)
                        warning(sprintf('%s:Input',mfilename),['Logging is expected to be a on, but ',...
                            'it seems to be off, adjusting state, please check and try again, maybe use loggingFix!']);
                        obj.p_Log.Enabled = false;
                    elseif ~value && ~isempty(obj.p_Log.Timer)
                        warning(sprintf('%s:Input',mfilename),['Logging is expected to be a off, but ',...
                            'it seems to be on, adjusting state, please check and try again, maybe use loggingFix!']);
                        stop(obj.p_Log.Timer);
                        if ~isempty(obj.p_Log.Timer)
                            delete(obj.p_Log.Timer);
                            obj.p_Log.Timer = [];
                        end
                    end
                elseif value
                    %
                    % enable logging by creating the timer and prepare everything in the start, run
                    % and stop function, such that those function could be called manually
                    obj.p_Log.Timer = timer('BusyMode','drop','ErrorFcn',@(~,event) loggingError(obj,event),...
                        'ExecutionMode','fixedRate','Name',sprintf('timer-%s',class(obj)),...
                        'ObjectVisibility','off','Period',obj.p_Log.TimerPeriod,...
                        'StartFcn',@(~,event) loggingStart(obj,event),'StopFcn',@(~,event) loggingStop(obj,event),...
                        'Tag',sprintf('timer-%s-%s',class(obj),obj.p_SDK.camNumber),...
                        'TasksToExecute',obj.p_Log.TimerRuns,'TimerFcn',@(~,event) loggingRun(obj,event));
                    start(obj.p_Log.Timer);
                else
                    % user requested to stop logging
                    if isempty(obj.p_Log.Timer)
                        warning(sprintf('%s:Input',mfilename),['Logging is expected to be a on, but ',...
                            'it seems to be off, adjusting state, please check and try again, maybe use loggingFix!']);
                        obj.p_Log.Enabled = false;
                    else
                        stop(obj.p_Log.Timer);
                        if ~isempty(obj.p_Log.Timer)
                            warning(sprintf('%s:Input',mfilename),['Logging is expected to clean up timer object, ',...
                                'but it still seems to exist, please run loggingStop manually and check, maybe use loggingFix!']);
                        end
                    end
                end
            else
                error(sprintf('%s:Input',mfilename), 'Logging is expected to be a scalar logical, please check input!');
            end
        end
        
        function out = get.Data(obj)
            out = obj.p_Data(:,:,:,1:obj.p_DataIndex);
        end
        
        function out = get.Timestamp(obj)
            out = obj.p_Timestamp(1:obj.p_DataIndex,:);
        end
        
        function       set.Data(obj,value)
            if obj.Logging
                error(sprintf('%s:Input',mfilename),...
                    ['The object is currently logging and needs to be disabled before any change can be done, ',...
                    'reading data during logging should be possible, use the getData method to read out and ',...
                    'reset the Data property while logging to memory']);
            end
            %
            % get an example image and apply transformation
            img = getExampleImage(obj);
            if ~isempty(obj.p_Log.TransformFcn), img = obj.p_Log.TransformFcn(img); end
            if ~(isnumeric(img) && ndims(img) <= 3)
                error(sprintf('%s:Input',mfilename),'Unknown image format, please check!');
            end
            if isempty(value)
                obj.p_Data      = eval(sprintf('%s.empty',class(img)));
                obj.p_Timestamp = eval(sprintf('%s.empty',class(img)));
                obj.p_DataIndex = 0;
            elseif isnumeric(value) && isscalar(value) && round(value) > 0
                value = double(round(value));
                %
                % compute expected size for allocated image(s)
                fileInfo = whos('img','bytes');
                sizMiB   = value * fileInfo.bytes/1024^2;
                if ispc
                    tmp = memory;
                    tmp = tmp.MaxPossibleArrayBytes/1024^2;
                    if sizMiB > 0.9*tmp
                        error(sprintf('%s:Input',mfilename), ['Initializing Data property with an ',...
                            'array of %f MiB, which would be %f%% of available memory, is aborted, please check!'],...
                            sizMiB,100*sizMiB/tmp);
                    elseif sizMiB > 0.5*tmp
                        warning(sprintf('%s:Input',mfilename), ['Initializing Data property with an ',...
                            'array of %f MiB, which is %f%% of available memory, please be careful'],...
                            sizMiB,100*sizMiB/tmp);
                    elseif sizMiB > obj.LoggingDetails.MemoryLimit
                        warning(sprintf('%s:Input',mfilename),...
                            'Initializing Data property with an array of %f MiB, please be careful',sizMiB);
                    end
                else
                    if sizMiB > obj.LoggingDetails.MemoryLimit
                        warning(sprintf('%s:Input',mfilename),...
                            'Initializing Data property with an array of %f MiB, please be careful',sizMiB);
                    end
                end
                obj.p_Data      = repmat(img,[1 1 1 value]);
                obj.p_Timestamp = zeros([size(obj.p_Data,4),14], 'like', img);
                obj.p_DataIndex = 0;
            else
                error(sprintf('%s:Input',mfilename),...
                    ['Data can only be changed by a reset by supplying an empty value ',...
                    ' or by initializing for a given number of frames (i.e. a scalar value), please check input!']);
            end
        end
        
        function out = get.Memory(obj)
            nImage = size(obj.p_Data,4);
            if nImage > 0
                curval   = obj.p_Data(:,:,:,1); %#ok<NASGU>
                fileInfo = whos('curval','bytes');
                out      = nImage*fileInfo.bytes/1024^2;
            else
                out = 0;
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
        
        function             delete(obj)
            % delete Deletes object and make sure the camera is closed properly
            
            %
            % try to remove and free buffers
            try
                obj.Running = false;
                p_removeBuffer(obj);
                p_freeBuffer(obj);
            catch
                warning(sprintf('%s:Input',mfilename),...
                    ['Could not stop camera and free buffers during object deletion, ',...
                    'to unload the SDK use something like ''unloadlibrary(''%s'')'')'], ...
                    obj.p_SDK.alias);
            end
            %
            % close camera
            if obj.p_SDK.closeAtEnd
                err = mydo(obj,false,0, 'PCO_CloseCamera', obj.p_SDK.camHandle);
                if err ~= 0
                    [errU, errH] = obj.pco_err2err(err);
                    warning(sprintf('%s:Input',mfilename),...
                        ['Could not close camera, error code returned by SDK is ',...
                        '%d (%s), to unload the SDK use something like ''unloadlibrary(''%s'')'')'], ...
                        errU, errH, obj.p_SDK.alias);
                end
            end
            %
            % make sure all SDK structures and data are removed before unloading
            closepreview(obj);
            doUnload = obj.p_SDK.unloadAtEnd;
            myAlias  = obj.p_SDK.alias;
            obj.p_SDK         = [];
            obj.p_Buffer      = [];
            obj.p_Description = [];
            obj.UserData      = [];
            obj.p_Data        = [];
            obj.p_Timestamp   = [];
            if doUnload
                if libisloaded('GRABFUNC'), unloadlibrary('GRABFUNC'); end
                if libisloaded(myAlias), unloadlibrary(myAlias); end
            end
        end
        
        function S         = saveobj(obj)
            % saveobj Supposed to be called by MATLAB's save function, stores settings for SDK
            % connection and settings to allow for a recovery during the load processs
            
            % remove read-only settings and disable logging after the object is loaded
            S.Settings       = obj.Settings;
            S.LoggingDetails = rmfield(obj.LoggingDetails,{'AveragePeriod','FramesAcquired',...
                'InstantPeriod','RunningTimer','Timestamp'}); S.LoggingDetails.Enabled = false;
            S.Recover        = struct('Interface',lower(obj.Description.InterfaceType),...
                'CameraNumber',obj.p_SDK.camNumber,'SDK',obj.p_SDK.alias,'Name',obj.Name);
        end
        
        function             reboot(obj)
            % reboot Reboots the camera
            
            mydo(obj,true,0, 'PCO_ResetSettingsToDefault', obj.p_SDK.camHandle);
        end
        
        function             reset(obj)
            % reset Resets the camera
            
            mydo(obj,true,0, 'PCO_RebootCamera', obj.p_SDK.camHandle);
        end
        
        function varargout = initiateSelftest(obj)
            % initiateSelftest Initiates a self-test, which will throw an error in case it fails or
            % return true if the test is passed
            
            nargoutchk(0,1);
            err = mydo(obj,true,0, 'PCO_InitiateSelftestProcedure',...
                obj.p_SDK.camHandle);
            out = err ==0;
            if nargout > 0, varargout = {out}; end
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
            nargoutchk(0,1);
            %
            % built top information strings
            out        = cell(1);
            sep        = '  ';
            lenChar    = 22;
            out{end+1} = sprintf('%s (%s) connected as camera %d via ''%s'' ',...
                obj.Name,obj.Description.CamType,obj.p_SDK.camNumber,obj.Description.InterfaceType);
            sep2       = repmat('-',1,numel(out{end}));
            out{end+1} = sep2;
            out{1}     = sep2;
            %
            % add settings
            if ~onlyState
                mys        = obj.Settings;
                fns        = fieldnames(mys);
                out{end+1} = sprintf('%s%*s Settings',sep,lenChar,'Camera');
                out{end+1} = sprintf('%s%*s---------------',sep,lenChar,'--------------');
                for n = 1:numel(fns)
                    switch lower(fns{n})
                        case {'recordermode','storagemode','timestampmode','triggermode','sensorformat',...
                                'noisefiltermode','acquiremode','bitalignment','hotpixelcorrectionmode'}
                            out{end+1} = sprintf('%s%*s: %s',sep,lenChar,fns{n},mys.(fns{n})); %#ok<AGROW>
                        case {'temperatureccdsetpoint','segmentactive','roi','pixelrate','doubleimage',...
                                'adcoperation','binning'}
                            out{end+1} = sprintf('%s%*s: %s',sep,lenChar,fns{n},num2str(mys.(fns{n}))); %#ok<AGROW>
                        case {'exposure','delay'}
                            if all(mys.(fns{n})(2:end)==0)
                                out{end+1} = sprintf('%s%*s: %s',sep,lenChar,fns{n},num2str(mys.(fns{n})(1))); %#ok<AGROW>
                            else
                                out{end+1} = sprintf('%s%*s: %s',sep,lenChar,fns{n},num2str(mys.(fns{n}))); %#ok<AGROW>
                            end
                    end
                end
            end
            %
            % current health and state
            [nIn,nMax] = checkRamSegment(obj);
            myh        = obj.Health;
            fnh        = fieldnames(myh);
            out{end+1} = ' ';
            out{end+1} = sprintf('%s%*s State',sep,lenChar,'Camera');
            out{end+1} = sprintf('%s%*s---------------',sep,lenChar,'--------------');
            for n = 1:numel(fnh)
                switch lower(fnh{n})
                    case {'error','warning','timestampmode'}
                        out{end+1} = sprintf('%s%*s: %s',sep,lenChar,fnh{n},myh.(fnh{n})); %#ok<AGROW>
                    case {'temperatureccd','temperaturecamera','temperaturepower'}
                        out{end+1} = sprintf('%s%*s: %s',sep,lenChar,fnh{n},num2str(myh.(fnh{n}))); %#ok<AGROW>
                end
            end
            out{end+1} = sprintf('%s%*s: %s',sep,lenChar,'COCRuntime',obj.COCRuntime);
            out{end+1} = sprintf('%s%*s: %d',sep,lenChar,'FramesAcquired',obj.FramesAcquired);
            out{end+1} = sprintf('%s%*s: %d',sep,lenChar,'Armed',obj.Armed);
            out{end+1} = sprintf('%s%*s: %d',sep,lenChar,'Locked',obj.Locked);
            out{end+1} = sprintf('%s%*s: %d',sep,lenChar,'Logging',obj.Logging);
            out{end+1} = sprintf('%s%*s: %d',sep,lenChar,'Running',obj.Running);
            out{end+1} = sprintf('%s%*s: %d / %d',sep,lenChar,'CamRAM',nIn,nMax);
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
        
        function varargout = start(obj)
            % start Starts logging and runnning with current settings and returns health
            
            nargoutchk(0,1);
            obj.arm;
            obj.Logging = true;
            obj.Running = true;
            out         = obj.Health;
            if nargout > 0, varargout = {out}; end
        end
        
        function varargout = stop(obj)
            % stop Stops runnning and logging and returns health
            
            nargoutchk(0,1);
            obj.Logging = false;
            obj.Running = false;
            out         = obj.Health;
            if nargout > 0, varargout = {out}; end
        end
        
        function varargout = trig(obj)
            % trig Forces a trigger and returns if it was successful
            
            nargoutchk(0,1);
            if obj.Running
                if obj.Busy
                    error(sprintf('%s:Run',mfilename),...
                        '%s is busy and does currently not accept a trigger',obj.Name);
                else
                    tmp = uint16(0);
                    [~, obj.p_SDK.camHandle, tmp] = mydo(obj,true,0, 'PCO_ForceTrigger', ...
                        obj.p_SDK.camHandle, tmp);
                    out = logical(tmp);
                end
            else
                error(sprintf('%s:Run',mfilename),...
                    '%s must be running to accept a trigger',obj.Name);
            end
            if nargout > 0, varargout = {out}; end
        end
        
        function varargout = arm(obj)
            % arm Prepares the camera for a consecutive set recording status = run command, i.e. in
            % terms of this class: obj.Running = true, function also checks and returns the health
            % status of the camera
            
            if obj.Running
                error(sprintf('%s:Run',mfilename),...
                    '%s is already running, i.e. should have been armed before',obj.Name);
            else
                nargoutchk(0,1);
                %
                % arm camera
                mydo(obj,true,0, 'PCO_ArmCamera',...
                    obj.p_SDK.camHandle);
                obj.p_SDK.userCalledArm = true;
                %
                % read health status as suggested by SDK manual
                out = obj.Health;
                if nargout > 0, varargout = {out}; end
            end
        end
        
        function varargout = allocateBuffer(obj,nBuffer,nImage)
            % allocateBuffer Allocates or re-allocates buffer(s) for given number of images (last
            % and optional input, default is one image per buffer), returns the index of each buffer
            % as output
            %
            % Each buffer is created with a size to hold the given number of images To re-allocate
            % an existing buffer supply its index as negative number, i.e. [-1 -2] will reallocate
            % buffer 1 and 2
            
            %
            % check input
            nBuffer = round(nBuffer);
            assert(isnumeric(nBuffer) && ((isscalar(nBuffer) && nBuffer > 0 && nBuffer <= 16) || ...
                (max(nBuffer) < 0 && max(abs(nBuffer)) <= numel(obj.p_Buffer))), ...
                sprintf('%s:Input',mfilename),['Number of buffers is expected to be a scalar numeric ',...
                'between 1 and 16 to allocate a new buffer or the negative index of an ',...
                'existing buffer (or muliple buffers) to re-allocate that buffer']);
            if nargin < 3, nImage = 1; end
            newBuffer = ~(max(nBuffer) < 0);
            if newBuffer, nImageAllowed = nBuffer;        % allocate new nBUffer
            else,         nImageAllowed = numel(nBuffer); % re-allocate existing buffers
            end
            nImage = round(nImage);
            assert(isnumeric(nImage) && (isscalar(nImage) || numel(nImage) == nImageAllowed) && min(nImage) > 0, sprintf('%s:Input',mfilename),...
                'Number of images is expected to be a scalar numeric input or an array with as many elements as requested buffers');
            if isscalar(nImage) && newBuffer
                nImage = repmat(nImage,1,nBuffer);
            else
                nImage = repmat(nImage,1,numel(nBuffer));
            end
            nargoutchk(0,1);
            %
            % check if camera was armed
            if ~obj.p_SDK.userCalledArm
                warning(sprintf('%s:Input',mfilename),...
                    '%s is not armed, which is done now to get correct image size, etc.',obj.Name);
                obj.arm;
            end
            %
            % call workhorse function
            [varargout{1:nargout}] = p_allocateBuffer(obj,nBuffer,nImage);
            varargout              = varargout(1:nargout);
        end
        
        function             addBuffer(obj,idxBuffer,idxImageStart,idxImageEnd)
            % addBuffer Adds a buffer to the driver queue to read image of given index, last input
            % idxImageEnd is optional and is set to idxImageStart in case it is omitted
            
            if ~isempty(obj.p_Buffer)
                nMax = p_checkRamSegment(obj,obj.p_ActiveSegment);
                if nargin < 2 || isempty(idxBuffer),     idxBuffer = 1:numel(obj.p_Buffer); end
                if nargin < 3 || isempty(idxImageStart), idxImageStart = 0; end
                if nargin < 4 || isempty(idxImageEnd),     idxImageEnd = idxImageStart; end
                assert(isnumeric(idxBuffer) && min(idxBuffer) > 0 && max(idxBuffer) <= numel(obj.p_Buffer),...
                    sprintf('%s:Input',mfilename), 'Index of buffer(s) are out of bound, please check!');
                assert(isnumeric(idxImageStart) && min(idxImageStart) >= 0 && (numel(idxImageStart) == numel(idxBuffer) ||...
                    isscalar(idxImageStart)) && max(idxImageStart) <= nMax,...
                    sprintf('%s:Input',mfilename), 'Start index of image(s) are out of bound, please check!');
                if nargin < 4 || isempty(idxImageEnd), idxImageEnd = idxImageStart; end
                assert(isnumeric(idxImageEnd) && min(idxImageEnd) >= 0 && (numel(idxImageEnd) == numel(idxBuffer) || ...
                    isscalar(idxImageEnd)) && max(idxImageEnd) <= nMax && all((idxImageEnd-idxImageStart)>=0),...
                    sprintf('%s:Input',mfilename), 'Start index of image(s) are out of bound, please check!');
                if isscalar(idxImageStart), idxImageStart = repmat(idxImageStart,size(idxBuffer)); end
                if isscalar(idxImageEnd),     idxImageEnd = repmat(idxImageEnd,size(idxBuffer)); end
                %
                % call workhorse function
                p_addBuffer(obj,idxBuffer,idxImageStart,idxImageEnd);
            else
                error(sprintf('%s:Input',mfilename),...
                    'No buffer(s) are allocated for %s, please check!',obj.Name);
            end
        end
        
        function             getBuffer(obj,idxBuffer)
            % getBuffer Gets the data of an allocated buffer
            
            if ~isempty(obj.p_Buffer)
                if nargin < 2 || isempty(idxBuffer), idxBuffer = 1:numel(obj.p_Buffer); end
                assert(isnumeric(idxBuffer) && min(idxBuffer) > 0 && max(idxBuffer) <= numel(obj.p_Buffer), sprintf('%s:Input',mfilename),...
                    'Index of buffer(s) are out of bound, please check!');
                %
                % call workhorse function
                p_getBuffer(obj,idxBuffer);
            else
                error(sprintf('%s:Input',mfilename),...
                    'No buffer(s) are allocated for %s, please check!',obj.Name);
            end
        end
        
        function             killBuffer(obj)
            % killBuffer Deletes buffer structure in object
            
            if ~isempty(obj.p_Buffer)
                warning(sprintf('%s:Input',mfilename),...
                    'Removing buffer(s) from object, but they may persist in the driver of %s',obj.Name);
            end
            %
            % call workhorse function
            p_killBuffer(obj);
        end
        
        function             fixLock(obj)
            % fixLock Fixes a broken lock
            
            if obj.Locked
                warning(sprintf('%s:Input',mfilename),...
                    'Removing lock from object %s',obj.Name);
            end
            obj.p_Locked = false;
        end
        
        function             fixLogging(obj)
            % fixLogging Tries to fix a aborted logging run
            
            try obj.Logging = false; end %#ok<TRYNC>
            %
            % take care of the timer object
            try %#ok<TRYNC>
                if isempty(obj.p_Log.Timer) || ~isvalid(obj.p_Log.Timer)
                    obj.p_Log.Timer = [];
                elseif isvalid(obj.p_Log.Timer)
                    delete(obj.p_Log.Timer);
                    obj.p_Log.Timer = [];
                end
            end
            %
            % fix lock
            try fixLock(obj); end %#ok<TRYNC>
            %
            % free buffers
            try p_removeBuffer(obj); end %#ok<TRYNC>
            try p_freeBuffer(obj); end %#ok<TRYNC>
            if ~isempty(obj.p_Buffer)
                error(sprintf('%s:Input',mfilename),...
                    'Buffer(s) could not be removed for %s and, therefore, logging could not be fixed, please check!',obj.Name);
            end
            %
            % final tweaks
            obj.p_Log.Enabled = false;
        end
        
        function             removeBuffer(obj)
            % p_removeBuffer Removes any buffer from the driver queue
            
            %
            % call workhorse function
            p_removeBuffer(obj);
        end
        
        function varargout  = getImage(obj,idxBuffer,idxImage,idxSegment)
            % getImage Transfers images into buffers from a certain segment
            
            if ~isempty(obj.p_Buffer)
                narginchk(3,4);
                if nargin < 4, idxSegment = obj.p_ActiveSegment; end
                assert(isnumeric(idxBuffer) && min(idxBuffer) > 0 && max(idxBuffer) <= numel(obj.p_Buffer),...
                    sprintf('%s:Input',mfilename), 'Index of buffer(s) are out of bound, please check!');
                assert(isnumeric(idxSegment) && isscalar(idxSegment) && idxSegment > 0 && idxSegment <= 4,...
                    sprintf('%s:Input',mfilename), 'Index of segment is out of bound, please check!');
                assert(isnumeric(idxImage) && min(idxImage) > 0 && numel(idxImage) == numel(idxBuffer) &&...
                    max(idxImage) <= p_checkRamSegment(obj,idxSegment) && ...
                    sprintf('%s:Input',mfilename), 'Index of image(s) are out of bound, please check!');
                %
                % call workhorse function
                [varargout{1:nargout}] = p_getImage(obj,idxBuffer,idxImage,idxSegment);
                varargout              = varargout(1:nargout);
            else
                error(sprintf('%s:Input',mfilename),...
                    'No buffer(s) are allocated for %s, please check!',obj.Name);
            end
        end
        
        function varargout = freeBuffer(obj,idxBuffer)
            % freeBuffer Frees a previously allocated buffer and returns if all buffers are free
            % and, therefore, deleted from the MATALB object
            
            if ~isempty(obj.p_Buffer)
                if nargin < 2 || isempty(idxBuffer), idxBuffer = 1:numel(obj.p_Buffer); end
                assert(isnumeric(idxBuffer) && min(idxBuffer) > 0 && max(idxBuffer) <= numel(obj.p_Buffer), ...
                    sprintf('%s:Input',mfilename), 'Index of buffer(s) are out of bound, please check!');
                nargoutchk(0,1);
                %
                % call workhorse function
                [varargout{1:nargout}] = p_freeBuffer(obj,idxBuffer);
                varargout              = varargout(1:nargout);
            elseif nargout > 0
                varargout = {isempty(obj.p_Buffer)};
            end
        end
        
        function varargout = checkBuffer(obj,idxBuffer)
            % checkBuffer Get the buffer status of a previously allocated and added buffer
            %
            % This can be used to poll the status, while waiting for an image during recording.
            % After an image has been transferred it is recommended to check the buffer status
            % according to driver errors, which might occur during the image transfer. Function
            % returns the status of the DLL and the driver. The status of the DLL is returned as
            % structure as well (third output).
            
            if ~isempty(obj.p_Buffer)
                if nargin < 2 || isempty(idxBuffer), idxBuffer = 1:numel(obj.p_Buffer); end
                assert(isnumeric(idxBuffer) && min(idxBuffer) > 0 && max(idxBuffer) <= numel(obj.p_Buffer), sprintf('%s:Input',mfilename),...
                    'Index of buffer(s) are out of bound, please check!');
                nargoutchk(0,3);
                %
                % call workhorse function
                [varargout{1:nargout}] = p_checkBuffer(obj,idxBuffer);
                varargout              = varargout(1:nargout);
            else
                error(sprintf('%s:Input',mfilename),...
                    'No buffer(s) are allocated for %s, please check!',obj.Name);
            end
        end
        
        function varargout = waitForBuffer(obj,idxBuffer,timeout)
            % waitForBuffer Checks all given buffer whether one of them is triggered within timeout.
            % It returns the indices of all triggered buffers where an event is set and the status
            % of all checked buffers
            
            if ~isempty(obj.p_Buffer)
                if nargin < 2 || isempty(idxBuffer), idxBuffer = 1:numel(obj.p_Buffer); end
                if nargin < 3 || isempty(timeout),   timeout   = 1; end
                assert(isnumeric(idxBuffer) && min(idxBuffer) > 0 && max(idxBuffer) <= numel(obj.p_Buffer), ...
                    sprintf('%s:Input',mfilename), 'Index of buffer(s) are out of bound, please check!');
                assert(isnumeric(timeout) && isscalar(timeout) && timeout > 0, ...
                    sprintf('%s:Input',mfilename), 'Timeout is not valid, please check!');
                nargoutchk(0,2);
                %
                % call workhorse function
                [varargout{1:nargout}] = p_waitForBuffer(obj,idxBuffer,timeout);
                varargout              = varargout(1:nargout);
            else
                error(sprintf('%s:Input',mfilename),...
                    'No buffer(s) are allocated for %s, please check!',obj.Name);
            end
        end
        
        function [img, ts] = peekdata(obj,nImg)
            % peekdata Peeks for given number of images in case logging is not used and returns the
            % image(s) and correspnding timestamp(s). Please note: this should only be used when the
            % camera is receiving images and no other logging is used.
            
            %
            % check input
            img = [];
            ts  = [];
            narginchk(1,2);
            if nargin < 2, nImg = 1; end
            nImg = round(nImg);
            assert(isnumeric(nImg) && isscalar(nImg) && nImg >= 0,...
                'Number of images to get is out of bound, please check!');
            if obj.p_Verbose > 0, fprintf('%s: %s Trying to get %d peek images, ', obj.Name, datestr(now), nImg); end
            %
            % test if camera is running
            if ~obj.Running
                error(sprintf('%s:Input',mfilename),...
                    '%s is not running, cannot peek for images in that case!',obj.Name);
            end
            %
            % test for logging
            if obj.Logging
                error(sprintf('%s:Input',mfilename),...
                    '%s seems already to be logging, cannot peek for images in that case!',obj.Name);
            end
            %
            % check for lock
            if obj.Locked
                error(sprintf('%s:Input',mfilename),...
                    '%s is locked, which is unexpected, please check or fix state with ''obj.fixLock''!', obj.Name);
            end
            %
            % check buffers, such that buffers can be build up from scratch
            if obj.NumberOfAvailableBuffer > 0
                error(sprintf('%s:Input',mfilename),...
                    '%d buffer(s) are already available for %s, please clean up buffer(s) and try again!',...
                    obj.NumberOfAvailableBuffer,obj.Name);
            end
            %
            % check health
            tmp = obj.Health;
            if ~(isempty(tmp.Error) && isempty(tmp.Warning))
                obj.Running = false;
                obj.p_Locked = false;
                error(sprintf('%s:Input',mfilename),...
                    '%s is not healthy, please check!', obj.Name);
            end
            %
            % allocate 1 buffer
            p_allocateBuffer(obj,1);
            if ~obj.p_SDK.userCalledArm, arm(obj);end
            %
            % read images           
            for i = 1:nImg
                inTime = p_getImage(obj,1,0);
                if ~inTime
                    warning(sprintf('%s:Input',mfilename),...
                        '%s reached a timeout, %d missing images could not be read',obj.Name,nImg-1+1);
                    p_freeBuffer(obj);
                    break;
                else
                    tmp = permute(obj.p_Buffer(1).im_ptr.Value,[2 1 3 4]);
                    if i == 1
                        img = tmp;
                        ts  = tmp(1,1:14);
                    else
                        img = cat(4,img,tmp);
                        ts  = cat(1,ts,tmp(1,1:14));
                    end
                end
            end
            %
            % free buffer
            p_freeBuffer(obj);
            %
            % finish output
            if obj.p_Verbose > 0
                fprintf(' ... done with %d image(s)\n',nImg);
            end
        end
        
        function varargout = checkRamSegment(obj,idxSegment)
            % checkRamSegment Checks for current and maximum number of images in RAM segment(s)
            
            if nargin < 2 || isempty(idxSegment), idxSegment = obj.p_ActiveSegment; end
            assert(isnumeric(idxSegment) && min(idxSegment) > 0 && max(idxSegment) < 5, sprintf('%s:Input',mfilename),...
                'Index of segement(s) are out of bound, please check!');
            nargoutchk(0,2);
            %
            % call workhorse function
            [varargout{1:nargout}] = p_checkRamSegment(obj,idxSegment);
            varargout              = varargout(1:nargout);
        end
        
        function varargout = readActiveRamSegment(obj,idxDo,append)
            % readActiveRamSegment Reads active RAM segment into data property after any running and
            % logging is stopped, this function can be called if no logging is used to read data
            % while the camera is running, the function returns the number of images transferred from
            % the camera RAM, normally the data is appended to the data property but can also be
            % replaced depending on the third (optional) input argument, the second input (optional)
            % can be used to select only specific frames, an empty value leads to all frames being
            % read into computer memory
            
            %
            % check state of camera
            if obj.Logging || obj.Running
                error(sprintf('%s:Input',mfilename),...
                    ['The object is currently logging and/or running, ',...
                    'please stop camera before reading the active RAM segment']);
            end
            %
            % check input
            nargoutchk(0,1);
            nImage = p_checkRamSegment(obj);
            if nImage < 1
                % return in case no image is available
                if nargout > 0, varargout = {0}; end
                return;
            end
            if nargin < 2 || isempty(idxDo), idxDo = 1:nImage; end
            if nargin < 3, append = true; end
            assert(isnumeric(idxDo) && min(round(idxDo(:))) > 0, ...
                sprintf('%s:Input',mfilename), 'Second input is expected to be a numeric, please check');
            assert(islogical(append) && isscalar(append), ...
                sprintf('%s:Input',mfilename), 'Third input is expected to be a scalar logical, please check');
            idxDo = round(reshape(idxDo,1,[]));
            if nargout > 0, varargout = {numel(idxDo)}; end
            if nImage < 1
                warning(sprintf('%s:Input',mfilename),...
                    ['The active RAM segement is empty, ',...
                    'no images are transferred and the data propery is untouched']);
                return;
            end
            if max(idxDo) > nImage
                warning(sprintf('%s:Input',mfilename),...
                    ['Requested images are out of bound, ',...
                    'only available image(s) (maximum image index is %d) are returned'],nImage);
                idxDo(idxDo>nImage) = [];
            end
            if obj.p_Verbose > 0, fprintf('%s: Acquiring %d image(s) from CamRAM\n',obj.Name, numel(idxDo)); end
            %
            % compute indices of images to read
            if append
                if obj.p_DataIndex < 0, obj.Data = numel(idxDo); end
                idxData = (1:numel(idxDo)) + obj.p_DataIndex;
            else
                obj.Data = numel(idxDo);
                idxData  = (1:numel(idxDo));
            end
            %
            % correct size of data
            if isempty(obj.p_Data)
                obj.Data = max(idxData);
            elseif size(obj.p_Data,4) < max(idxData)
                siz             = size(obj.p_Data);
                if numel(siz) < 4, siz((end+1):4) = 1; end
                obj.p_Data      = cat(4,obj.p_Data,zeros([siz(1:3),max(idxData)-siz(4)],'like',obj.p_Data));
                obj.p_Timestamp = cat(1,obj.p_Timestamp,...
                    zeros([max(idxData)-siz(4),14],'like',obj.p_Timestamp));
            elseif size(obj.p_Data,4) > max(idxData)
                obj.p_Data      = obj.p_Data(:,:,:,1:max(idxData));
                obj.p_Timestamp = obj.p_Timestamp(1:max(idxData),:);
            end
            %
            % allocate 1 buffer
            p_allocateBuffer(obj,1);
            if ~obj.p_SDK.userCalledArm, arm(obj);end
            %
            % read images
            for i = 1:numel(idxDo)
                inTime = p_getImage(obj,1,idxDo(i));
                if ~inTime
                    warning(sprintf('%s:Input',mfilename),...
                        '%s reached a timeout, %d missing images could not be read',obj.Name,numel(idxDo)-i+1);
                    break;
                else
                    img = permute(obj.p_Buffer(1).im_ptr.Value,[2 1 3 4]);
                    obj.p_Data(:,:,:,idxData(i))  = img;
                    obj.p_Timestamp(idxData(i),:) = img(1,1:14);
                    obj.p_DataIndex               = idxData(i);
                    if obj.p_Verbose > 100
                        fprintf(' ... image %d of %d \n',i, numel(idxDo));
                    end
                end
            end
            %
            % free buffer
            p_freeBuffer(obj);
            %
            % finish output
            if obj.p_Verbose > 0
                fprintf(' ... done with %d image(s)\n',numel(idxDo));
            end
        end
        
        function             clearActiveRamSegment(obj)
            % clearActiveRamSegment Clears active camera RAM segment, delete all image info and prepare segment for new images
            
            if ~obj.Description.GeneralCapsDESC1.NO_RECORDER
                if obj.Running
                    error(sprintf('%s:Run',mfilename),...
                        '%s is running and cannot clear the RAM',obj.Name);
                end
                mydo(obj,true,0, 'PCO_ClearRamSegment', ...
                    obj.p_SDK.camHandle);
            end
        end
        
        function             loggingStart(obj,event)
            % loggingStart Should be called when timer is started to prepare actual logging or by
            % user to prepare for manual logging run
            
            if obj.p_Verbose > 0, fprintf('%s: %s Starting logging, ', obj.Name, datestr(now)); end
            if nargin < 2, event = []; end
            %
            % test logging
            if obj.Logging
                error(sprintf('%s:Input',mfilename),...
                    '%s seems already to be logging, please check!',obj.Name);
            end
            %
            % check for lock
            if obj.Locked
                error(sprintf('%s:Input',mfilename),...
                    '%s is locked, which is unexpected, please check or fix state with ''obj.fixLock''!', obj.Name);
            end
            %
            % user requested to start logging, check if camera is armed
            if ~obj.p_SDK.userCalledArm
                warning(sprintf('%s:Input',mfilename),...
                    '%s is not armed, which is done now to apply the settings on the hardware and check health',obj.Name);
                obj.arm;
            end
            %
            % check buffers, such that buffers can be build up from scratch
            if obj.NumberOfAvailableBuffer > 0
                error(sprintf('%s:Input',mfilename),...
                    '%d buffer(s) are already available for %s, please clean up buffer(s) and try again!',...
                    obj.NumberOfAvailableBuffer,obj.Name);
            end
            %
            % check for logger
            if ismember(obj.p_Log.Mode,{'disk','disk&memory'})
                if isempty(obj.p_Log.DiskLogger) || (isa(obj.p_Log.DiskLogger,'VideoWriter') && ~isvalid(obj.p_Log.DiskLogger))
                    error(sprintf('%s:Input',mfilename),...
                        '%s is missing a disk logger, please supply one or turn of logging to disk and try again!', obj.Name);
                end
            end
            %
            % check health
            obj.p_Log.HealthLast = tic;
            tmp                  = obj.Health;
            if ~(isempty(tmp.Error) && isempty(tmp.Warning))
                error(sprintf('%s:Input',mfilename),...
                    '%s is not healthy, please check!', obj.Name);
            end
            %
            % allocate buffers and add them all to the most recent image, in case of FIFO mode the
            % camera should return the next image in the camera memory. Note: buffers are only added
            % once the camera is running to avoid black images initially. Therefore, adding buffers
            % is moved to the run function
            obj.p_Log.BufferIdx = p_allocateBuffer(obj,obj.p_Log.BufferNum);
            if ~obj.p_SDK.userCalledArm, arm(obj);end
            obj.p_Log.BufferOnceAdded = false;
            %
            % reset the Data property
            if strcmpi(obj.p_Log,'disk'), myFramesExtend = 1;
            else,                         myFramesExtend = obj.p_Log.FramesExtend;
            end
            if obj.p_DataIndex == 0
                % initialize if Data property is completely empty
                if isempty(obj.p_Data), obj.Data = myFramesExtend; end
            else
                % warning(sprintf('%s:Input',mfilename),['Erasing existing data and initializing Data ',...
                %     'property of %s with %d black images'],obj.Name,obj.p_Log.FramesExtend);
                obj.Data = myFramesExtend;
            end
            obj.p_Log.RunsWithoutBuffer = 0;
            obj.p_Log.FramesAcquired    = 0;
            obj.p_Log.Timestamp         = zeros([0,14],'like',obj.p_Buffer(1).Image);
            %
            % store storage and recorder mode for fast access
            mys                    = obj.Settings;
            obj.p_Log.StorageMode  = mys.StorageMode;
            obj.p_Log.RecorderMode = mys.RecorderMode;
            %
            % run user specified function
            if ~isempty(obj.p_Log.StartFcn)
                obj.p_Log.StartFcn(obj,event);
            end
            %
            % run preview function
            obj.p_Log.PausePreview = false;
            if ~isempty(obj.p_Log.PreviewFcn)
                obj.p_Log.PreviewFcn(obj);
            end
            obj.p_Log.Enabled = true;
            %
            % output
            if obj.p_Verbose > 0
                fprintf('%s Logging is started\n',datestr(now));
            end
        end
        
        function varargout = loggingRun(obj,event)
            % loggingRun Performs an actual run to get frames from camera
            
            if obj.p_Verbose > 100, fprintf('%s: %s Logging, ', obj.Name, datestr(now)); end
            if obj.p_Locked
                % wait for the next call of the timer
                if nargout > 0, varargout = {0}; end
                if obj.p_Verbose > 0, fprintf('%s: Camera is currently locked, no frames can be acquired\n',obj.Name); end
                return;
            end
            obj.p_Locked = true;
            if nargin < 2, event = []; end
            %
            % check if logging was started correctly
            if ~obj.Logging
                obj.p_Locked = false;
                error(sprintf('%s:Input',mfilename),...
                    'Logging was not started correctly for %s, please check!',obj.Name);
            end
            %
            % check health
            if obj.p_Log.HealthCheck > 0 && toc(obj.p_Log.HealthLast) >= obj.p_Log.HealthCheck
                obj.p_Log.HealthLast = tic;
                tmp                  = obj.Health;
                if ~(isempty(tmp.Error) && isempty(tmp.Warning))
                    obj.Running = false;
                    obj.p_Locked = false;
                    error(sprintf('%s:Input',mfilename),...
                        '%s is not healthy, please check!', obj.Name);
                end
                sizMiB = obj.Memory;
                if sizMiB > obj.p_Log.MemoryLimit
                    warning(sprintf('%s:Input',mfilename),...
                        'Data property exceeds %f MiB, please be careful',sizMiB);
                end
            end
            %
            % stop logging if camera is not running, but only if at least one image has been
            % acquired, otherwise the logging might end before the camera started running. Return
            % and wait for the actual start if camera is not running and no image has been acquired
            if ~obj.Running && obj.p_Log.FramesAcquired > 0
                if obj.p_Verbose > 0, fprintf('%s Camera is not running any more, logging will be stopped\n', datestr(now)); end
                if ~isempty(obj.p_Log.Timer), stop(obj.p_Log.Timer); end
                obj.p_Locked = false;
                return;
            elseif ~obj.Running && obj.p_Log.FramesAcquired < 1
                obj.p_Locked = false;
                if obj.p_Verbose > 0, fprintf('%s Camera is not (yet?) running\n', datestr(now)); end
                return;
            end
            %
            % add buffers for the first time after camera is set to running
            if ~obj.p_Log.BufferOnceAdded
                p_addBuffer(obj);
                obj.p_Log.BufferOnceAdded = true;
            end
            %
            % perform check and read from the camera: first wait for any buffer to get ready or just
            % check the state of all buffers, second - in case an image is ready - get the image, if
            % no buffer was ready at all do not check again and return from this function
            counter = 1;
            doAgain = true;
            out     = 0;
            while counter <= obj.p_Log.BufferRuns && doAgain
                if obj.p_Log.BufferWait > 0
                    idx = obj.p_waitForBuffer(obj.p_Log.BufferIdx,obj.p_Log.BufferWait);
                else
                    [~,stDRV,stat] = p_checkBuffer(obj,obj.p_Log.BufferIdx);
                    idx            = obj.p_Log.BufferIdx([stat.EVENT_SET]);
                    if ~all(stDRV == 0)
                        % throw all errors
                        showError(obj,stDRV,'p_checkBuffer in loggingRun');
                    end
                end
                out = out + numel(idx);
                if numel(idx) > 0
                    if obj.p_Verbose > 100, fprintf('Run %d, Buffer(s): %s, ',counter,num2str(idx));end
                    %
                    % get image from available buffers
                    for n = reshape(idx,1,[])
                        % read buffer and add again
                        img = permute(obj.p_Buffer(n).im_ptr.Value,[2 1 3 4]); % todo: getBuffer first?
                        p_addBuffer(obj,n);
                        obj.p_Log.FramesAcquired = obj.p_Log.FramesAcquired + 1;
                        % store timestamp
                        ts                  = img(1,1:14);
                        obj.p_Log.Timestamp = cat(1,obj.p_Log.Timestamp,ts);
                        % apply transformation
                        if ~isempty(obj.p_Log.TransformFcn), img = obj.p_Log.TransformFcn(img); end
                        % store image in Data property
                        if ismember(obj.p_Log.Mode,{'memory','disk&memory'})
                            % extend Data property
                            if isempty(obj.p_Data)
                                obj.Data = obj.LoggingDetails.FramesExtend;
                            elseif size(obj.p_Data,4) < obj.p_DataIndex+1
                                siz             = size(obj.p_Data);
                                if numel(siz) < 4, siz((end+1):4) = 1; end
                                obj.p_Data      = cat(4,obj.p_Data,zeros([siz(1:3),obj.LoggingDetails.FramesExtend],'like',obj.p_Data));
                                obj.p_Timestamp = cat(1,obj.p_Timestamp,...
                                    zeros([obj.LoggingDetails.FramesExtend,14],'like',obj.p_Timestamp));
                            end
                            % store image in Data property
                            obj.p_Data(:,:,:,obj.p_DataIndex+1)  = img;
                            obj.p_Timestamp(obj.p_DataIndex+1,:) = ts;
                            obj.p_DataIndex                      = obj.p_DataIndex+1;
                        end
                        % stream image to disk
                        if ismember(obj.p_Log.Mode,{'disk','disk&memory'})
                            if isa(obj.p_Log.DiskLogger,'function_handle')
                                obj.p_Log.DiskLogger(img);
                            else
                                writeVideo(obj.p_Log.DiskLogger,img);
                            end
                        end
                    end
                else
                    doAgain = false;
                end
                counter = counter + 1;
            end
            if out > 0
                %
                % store last image in Data property for preview purpose in case of logging to disk
                if strcmpi(obj.p_Log.Mode,'disk')
                    obj.p_Data      = img;
                    obj.p_Timestamp = reshape(ts,1,[]);
                    obj.p_DataIndex = 1;
                end
                %
                % run user specified function
                if ~isempty(obj.p_Log.FramesAcquiredFcn)
                    obj.p_Log.FramesAcquiredFcn(obj,event);
                end
                %
                % run preview function
                if ~isempty(obj.p_Log.PreviewFcn) && ~obj.p_Log.PausePreview
                    if ~isempty(obj.p_Log.PreviewTransform)
                        img = obj.p_Log.PreviewTransform(img);
                    end
                    obj.p_Log.PreviewFcn(obj,img,ts);
                end
            else
                obj.p_Log.RunsWithoutBuffer = obj.p_Log.RunsWithoutBuffer + 1;
            end
            %
            % fix buffers if they seem to be dead (which may happen for an unknown reason)
            if obj.p_Log.BufferFix > 0 && obj.p_Log.RunsWithoutBuffer > obj.p_Log.BufferFix
                if obj.p_Verbose > 0, fprintf('Buffers seem to be dead, trying to fix by re-allocating\n'); end
                p_allocateBuffer(obj,-1*obj.p_Log.BufferIdx);
                p_addBuffer(obj);
                obj.p_Log.RunsWithoutBuffer = 0;
            end
            %
            % run user specified function
            if ~isempty(obj.p_Log.TimerFcn)
                obj.p_Log.TimerFcn(obj,event);
            end
            %
            % finish output
            if obj.p_Verbose > 100
                [nIn, nMax] = p_checkRamSegment(obj);
                fprintf('%s Logging run is finished for %d frames, CamRAM level is %d / %d\n',...
                    datestr(now),out,nIn,nMax);
            end
            obj.p_Locked = false;
            if out > 0, notify(obj,'newData'); end
            if nargout > 0, varargout = {out}; end
        end
        
        function             loggingStop(obj,event)
            % loggingStop Should be called when timer stoped
            
            if obj.p_Verbose > 0, fprintf('%s: Stopping logging, ', obj.Name, datestr(now)); end
            firstWait = true;
            while obj.p_Locked
                if obj.p_Verbose > 0 && firstWait, fprintf('%s: Camera is currently locked, waiting for release, ',obj.Name); end
                firstWait = false;
                pause(max(0.001,obj.p_Log.TimerPeriod/2));
            end
            obj.p_Locked = true;
            if nargin < 2, event = []; end
            %
            % test logging
            if ~obj.Logging
                error(sprintf('%s:Input',mfilename),...
                    '%s seems already to be NOT logging, please check!',obj.Name);
            end
            %
            % take care of the timer object
            if isempty(obj.p_Log.Timer) || ~isvalid(obj.p_Log.Timer)
                obj.p_Log.Timer = [];
            elseif isvalid(obj.p_Log.Timer)
                delete(obj.p_Log.Timer);
                obj.p_Log.Timer = [];
            end
            %
            % stop recording (depends on mode) and re-read images
            nImage = 0;
            if obj.p_Log.FinalReadout && ((strcmpi(obj.Settings.StorageMode,'recorder') && ...
                    strcmpi(obj.Settings.RecorderMode,'sequence')) || ...
                    strcmpi(obj.Settings.StorageMode,'fifo'))
                % stop recording
                obj.Running = false;
                nImage      = p_checkRamSegment(obj);
                if nImage > 0
                    if obj.p_Verbose > 0, fprintf('%s: Acquiring %d image(s) from CamRAM, ', obj.Name, nImage); end
                    % compute indices of images to read
                    idxDo = 1:nImage;
                    if strcmpi(obj.Settings.StorageMode,'fifo')
                        idxData = idxDo + obj.p_DataIndex;
                    else
                        idxData = idxDo;
                    end
                    if ismember(obj.p_Log.Mode,{'memory','disk&memory'})
                        % correct size of data
                        if isempty(obj.p_Data)
                            obj.Data = max(idxData);
                        elseif size(obj.p_Data,4) < max(idxData)
                            siz             = size(obj.p_Data);
                            if numel(siz) < 4, siz((end+1):4) = 1; end
                            obj.p_Data      = cat(4,obj.p_Data,zeros([siz(1:3),max(idxData)-siz(4)],'like',obj.p_Data));
                            obj.p_Timestamp = cat(1,obj.p_Timestamp,...
                                zeros([max(idxData)-siz(4),14],'like',obj.p_Timestamp));
                        elseif size(obj.p_Data,4) > max(idxData)
                            obj.p_Data      = obj.p_Data(:,:,:,1:max(idxData));
                            obj.p_Timestamp = obj.p_Timestamp(1:max(idxData),:);
                        end
                    end
                    % read images
                    for i = 1:numel(idxDo)
                        inTime = p_getImage(obj,1,idxDo(i));
                        if ~inTime
                            warning(sprintf('%s:Input',mfilename),...
                                '%s reached a timeout, %d images could not be read',obj.Name,numel(idxDo)-i+1);
                            break;
                        else
                            img = permute(obj.p_Buffer(1).im_ptr.Value,[2 1 3 4]);
                            if ~isempty(obj.p_Log.TransformFcn), img = obj.p_Log.TransformFcn(img); end
                            if ismember(obj.p_Log.Mode,{'memory','disk&memory'})
                                obj.p_Data(:,:,:,idxData(i))  = img;
                                obj.p_Timestamp(idxData(i),:) = img(1,1:14);
                                obj.p_DataIndex               = idxData(i);
                            end
                            if ismember(obj.p_Log.Mode,{'disk','disk&memory'})
                                if isa(obj.p_Log.DiskLogger,'function_handle')
                                    obj.p_Log.DiskLogger(img);
                                else
                                    writeVideo(obj.p_Log.DiskLogger,img);
                                end
                            end
                            obj.p_Log.FramesAcquired = obj.p_Log.FramesAcquired + 1;
                            if obj.p_Verbose > 100
                                fprintf(' ... image %d of %d \n', i, numel(idxDo));
                            end
                        end
                    end
                end
            end
            %
            % correct size of Data property and timestamp
            if ismember(obj.p_Log.Mode,{'memory','disk&memory'})
                obj.p_Data      = obj.p_Data(:,:,:,1:obj.p_DataIndex);
                obj.p_Timestamp = obj.p_Timestamp(1:obj.p_DataIndex,:);
                obj.p_DataIndex = size(obj.p_Data,4);
            end
            %
            % free buffers
            removeBuffer(obj);
            freeBuffer(obj);
            %
            % run user specified function
            if ~isempty(obj.p_Log.StopFcn)
                obj.p_Log.StopFcn(obj,event);
            end
            obj.p_Log.Enabled = false;
            %
            % output
            if obj.p_Verbose > 0
                fprintf('%s Logging is stopped\n',datestr(now));
            end
            obj.p_Locked = false;
            if nImage > 0, notify(obj,'newData'); end
        end
        
        function             loggingFix(obj)
            % loggingFix Stops logging, removes any timer and buffer
            
            obj.Logging;
            if ~isempty(obj.p_Log) && ~isempty(obj.p_Log.Timer)
                if isvalid(obj.p_Log.Timer)
                    stop(obj.p_Log.Timer);
                end
                delete(obj.p_Log.Timer);
            end
            obj.p_Log.Timer = [];
            removeBuffer(obj);
            freeBuffer(obj);
            obj.p_Locked      = false;
            obj.p_Log.Enabled = false;
        end
        
        function             loggingError(obj,event)
            % loggingError Called when an error occurred when the timer was running
            
            if nargin < 2, event = []; end
            %
            % make sure the logging settings are initialized
            obj.Logging;
            %
            % run user specified function
            if ~isempty(obj.p_Log.ErrorFcn)
                obj.p_Log.ErrorFcn(obj,event);
            end
            %
            % output
            if obj.p_Verbose > 0
                fprintf('%s: %s An error occured during logging, use ''loggingFix'' and ''freeBuffer'' to recover from an unknown state\n', obj.Name,datestr(now));
            end
        end
        
        function out       = getExampleImage(obj)
            % getExampleImage Returns an image as it would be read from the camera with the correct
            % size and class after fixing the rotation
            
            %
            % check if camera was armed
            if ~obj.p_SDK.userCalledArm
                warning(sprintf('%s:Input',mfilename),...
                    '%s is not armed, which is done now to get correct image size, etc.',obj.Name);
                obj.arm;
            end
            %
            % determine imagesize
            imageSize = obj.Settings.ImageSize;            % width and height of image
            imas      = fix((obj.Description.DynResDESC + 7)/8);
            imas      = imas*prod(imageSize);              % image size in byte
            if strcmpi(obj.Description.InterfaceType,'firewire')
                % re-compute image size for firewire, code adapted from example 'pco_1200_live.m',
                % should ensure that the buffer size is a multiple of 4096 + 8192 bytes (see SDK
                % manual for PCO_AllocateBuffer), needs testing
                i       = 4096 * (1+floor(imas/4096));
                i       = i - imas;
                xs      = fix((obj.Description.DynResDESC + 7)/8);
                xs      = xs * imageSize(1);
                i       = floor(i/xs);
                i       = i + 1;
                lineadd = i;
            else
                lineadd = 0;
            end
            imgClass = sprintf('uint%d', ceil(obj.Description.DynResDESC/8)*8);
            %
            % return example in correct orientation
            out = permute(zeros(imageSize(1),imageSize(2) + lineadd, 1, imgClass),[2 1 3 4]);
        end
        
        function [data, t] = getData(obj,idx)
            % getData Returns frames of given index (or all available frames in case the optional
            % argument is omitted) and removes those frames from the corresponding Data property in
            % case the object is logging to memory. In case the object is only logging to disk, one
            % frame should be available at most (the last one), which is returned but the Data
            % property is not altered. It returns the timestamp as well
            
            while obj.p_Locked, pause(max(0.001,obj.p_Log.TimerPeriod/2)); end
            obj.p_Locked = true;
            %
            % check input
            if nargin < 2, idx = 1:obj.p_DataIndex; end
            assert(isnumeric(idx) && min(idx>0) && max(idx) <= obj.p_DataIndex, sprintf('%s:Input',mfilename),...
                'Given index is out of bounds or wrong data type, please check!');
            %
            % return data and adjust p_DataIndex
            data                   = obj.p_Data(:,:,:,idx);
            t                      = obj.p_Timestamp(idx,:);
            obj.p_Data(:,:,:,idx)  = [];
            obj.p_Timestamp(idx,:) = [];
            obj.p_DataIndex        = obj.p_DataIndex - numel(unique(idx));
            obj.p_Locked           = false;
        end
        
        function             flushData(obj)
            % flushData Removes data from object, i.e. the Data and Timestamp property
            
            while obj.p_Locked, pause(max(0.001,obj.p_Log.TimerPeriod/2)); end
            obj.p_Locked    = true;
            obj.p_Data      = eval(sprintf('%s.empty',class(obj.p_Data)));
            obj.p_Timestamp = eval(sprintf('%s.empty',class(obj.p_Timestamp)));
            obj.p_DataIndex = 0;
            obj.p_Locked    = false;
        end
        
        function [t, i]    = convertTimestamp(obj,in)
            % convertTimestamp Converts given timestamp with current object settings to the datetime
            % and image index, if second input is empty it converts obj.Timestamp
            
            %
            % check input
            if nargin < 2, in = obj.Timestamp; end
            if isempty(in)
                i = [];
                t = datetime.empty;
                return;
            end
            assert((isa(in,'uint8') || isa(in,'uint16')) &&isnumeric(in) && ...
                ((isvector(in) && numel(in) == 14) || (ismatrix(in) && size(in,2) == 14)),...
                sprintf('%s:Input',mfilename), ['Second input should be a 14 element numeric array with a PCO time stamp ',...
                'or a matrix with size(in,2) == 14 for multiple timestamps']);
            [t, i] = obj.pco_timestamp(in, obj.Settings.BitAlignment, obj.Description.DynResDESC);
        end
        
        function             preview(obj,img,ts)
            % preview Function that can be used to show a preview during logging
            %
            % Depending on the input arguments the function reacts differently
            %  * Three inputs (object, numeric image, numeric timestamp): the function updates the
            %    preview graphics if all information is available, i.e. due to an initialization,
            %    otherwise the preview is disabled
            %  * Two inputs (object, image): the second input is expected to be an image object,
            %    which will be updated during consecutive calls of this function with three inputs,
            %    the title of the parent axes of the image object will also be updated
            %  * One input (object): a new figure, axes and image object are created for a live
            %    preview
            
            %
            if nargin == 3 && isnumeric(img) && isnumeric(ts) && numel(ts) == 14 && ...
                    isfield(obj.UserData,'Preview') && isvalid(obj.UserData.Preview.hImg)
                %
                % should be an update run, no further error checking
                %
                [nIn, nMax] = checkRamSegment(obj);
                [time, idx] = obj.pco_timestamp(reshape(ts,1,[]), obj.UserData.Preview.BitAlignment, ...
                    obj.UserData.Preview.BitsPerPixel);
                obj.UserData.Preview.hImg.CData    = img;
                obj.UserData.Preview.hTitle.String = {obj.Name, sprintf('%s Image %d',datestr(time),idx),...
                    sprintf('Memory usage %.2f MiB, CamRAM level %d / %d',obj.Memory,nIn,nMax)};
                drawnow;
            elseif nargin <= 2
                %
                % initialization of graphics
                %
                imgPix = getExampleImage(obj);
                if ~isempty(obj.p_Log.PreviewTransform)
                    imgPix = obj.p_Log.PreviewTransform(imgPix);
                end
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
                % prepare preview with an example image of the object, store some information for
                % quick and easy access
                obj.UserData.Preview.BitAlignment = obj.Settings.BitAlignment;
                obj.UserData.Preview.BitsPerPixel = obj.Description.DynResDESC;
                [nIn, nMax] = checkRamSegment(obj);
                [time, idx] = obj.pco_timestamp(zeros(1,14,'uint16'), obj.UserData.Preview.BitAlignment, ...
                    obj.UserData.Preview.BitsPerPixel);
                obj.UserData.Preview.hImg.CData    = imgPix;
                obj.UserData.Preview.hTitle.String = {obj.Name, sprintf('%s Image %d',datestr(time),idx),...
                    sprintf('Memory usage %.2f MiB, CamRAM level %d / %d',obj.Memory,nIn,nMax)};
                drawnow;
                %
                % enable preview function for object
                %
                obj.p_Log.PausePreview = false;
                obj.p_Log.PreviewFcn   = @preview;
            else
                %
                % unexpected input, close preview
                %
                closepreview(obj);
            end
        end
        
        function             stoppreview(obj)
            % stoppreview Stops the previewing during logging
            
            obj.p_Log.PreviewFcn = '';
        end
        
        function             pausepreview(obj)
            % pausepreview Makes sure the preview function is not called during a logging run until
            % resumepreview is called or the logging is restarted
            
            obj.p_Log.PausePreview = true;
            if isfield(obj.UserData,'Preview') && isvalid(obj.UserData.Preview.hImg)
                obj.UserData.Preview.hTitle.String = {obj.Name, 'Preview is paused',...
                    sprintf('Memory usage %.2f MiB, CamRAM level %d / %d',obj.Memory,nIn,nMax)};
            end
        end
        
        function             resumepreview(obj)
            % resumepreview Makes sure the preview function is called during a logging run until
            % pausepreview is called
            
            obj.p_Log.PausePreview = false;
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
        function idx                     = p_allocateBuffer(obj,nBuffer,nImage)
            % p_allocateBuffer Allocates or re-allocates buffer(s) for given number of images (last
            % and optional input, default is one image per buffer), returns the index of each buffer
            % as output
            %
            % Each buffer is created with a size to hold the given number of images To re-allocate
            % an existing buffer supply its index as negative number, i.e. [-1 -2] will reallocate
            % buffer 1 and 2
            %
            % This is the workhorse function without much error checking for class internal use
            
            %
            % check input
            if nargin < 3, nImage = 1; end
            nBuffer   = round(nBuffer);
            nImage    = round(nImage);
            newBuffer = ~(max(nBuffer) < 0);
            if isscalar(nImage) && newBuffer, nImage = repmat(nImage,1,nBuffer);
            else,                             nImage = repmat(nImage,1,numel(nBuffer));
            end
            %
            % check if camera was armed
            if ~obj.p_SDK.userCalledArm, obj.arm; end
            %
            % determine imagesize
            imageSize = obj.Settings.ImageSize;            % width and height of image
            imas      = fix((obj.Description.DynResDESC + 7)/8);
            imas      = imas*prod(imageSize);              % image size in byte
            imasize   = imas;                              % image size aligned in byte
            if strcmpi(obj.Description.InterfaceType,'firewire')
                % re-compute image size for firewire, code adapted from example 'pco_1200_live.m',
                % should ensure that the buffer size is a multiple of 4096 + 8192 bytes (see SDK
                % manual for PCO_AllocateBuffer), needs testing
                i       = 4096 * (1+floor(imas/4096));
                imasize = i;
                i       = i - imas;
                xs      = fix((obj.Description.DynResDESC + 7)/8);
                xs      = xs * imageSize(1);
                i       = floor(i/xs);
                i       = i + 1;
                lineadd = i;
            else
                lineadd = 0;
            end
            imgClass = sprintf('uint%d', ceil(obj.Description.DynResDESC/8)*8);
            %
            % initialise structure for buffers with an image stack to hold content of each buffer
            if newBuffer, idx = numel(obj.p_Buffer) + (1:nBuffer);
            else,         idx = reshape(abs(nBuffer),1,[]);
            end
            k = 1;
            for n = idx
                % buffer number will be filled by library for new buffers and set to -1 here, any
                % existing buffer is not changed unless the size changed
                if newBuffer
                    obj.p_Buffer(n).Image      = zeros(imageSize(1),imageSize(2) + lineadd, nImage(k), imgClass);
                    obj.p_Buffer(n).BufferID   = int16(-1);
                    obj.p_Buffer(n).im_ptr     = libpointer(sprintf('%sPtr',imgClass),obj.p_Buffer(n).Image);
                    obj.p_Buffer(n).ev_ptr     = libpointer('voidPtr');
                    obj.p_Buffer(n).UserData   = [];
                else
                    if obj.p_Buffer(n).Size ~= imasize*nImage(k)
                        obj.p_Buffer(n).im_ptr = [];
                        obj.p_Buffer(n).Image  = [];
                        obj.p_Buffer(n).Image  = zeros(imageSize(1),imageSize(2) + lineadd, nImage(k), imgClass);
                        obj.p_Buffer(n).im_ptr = libpointer(sprintf('%sPtr',imgClass),obj.p_Buffer(n).Image);
                    end
                end
                obj.p_Buffer(n).Size           = imasize*nImage(k);
                obj.p_Buffer(n).BitsPerPixel   = obj.Description.DynResDESC;
                obj.p_Buffer(n).ImageSize      = imageSize;
                obj.p_Buffer(n).NumberOfImages = nImage(k);
                obj.p_Buffer(n).Free           = false;
                obj.p_Buffer(n).LineAdd        = lineadd;
                % allocate SDK buffer and set address of buffer
                [~, obj.p_SDK.camHandle, obj.p_Buffer(n).BufferID] = mydo(obj,true,0, 'PCO_AllocateBuffer', ...
                    obj.p_SDK.camHandle, obj.p_Buffer(n).BufferID, uint32(obj.p_Buffer(n).Size), ...
                    obj.p_Buffer(n).im_ptr, obj.p_Buffer(n).ev_ptr);
                k = k + 1;
            end
            %
            % set the image parameters for the image buffer transfer inside the CamLink and GigE
            % interface, with all other interfaces this is a dummy call
            mydo(obj,true,0, 'PCO_CamLinkSetImageParameters', ...
                obj.p_SDK.camHandle, uint16(imageSize(1)), uint16(imageSize(2)));
        end
        
        function                           p_addBuffer(obj,idxBuffer,idxImageStart,idxImageEnd)
            % p_addBuffer Adds a buffer to the driver queue to read image of given index, last input
            % idxImageEnd is optional and is set to idxImageStart in case it is omitted
            %
            % This is the workhorse function without much error checking for class internal use
            
            if ~isempty(obj.p_Buffer)
                if nargin < 2 || isempty(idxBuffer),     idxBuffer = 1:numel(obj.p_Buffer); end
                if nargin < 3 || isempty(idxImageStart), idxImageStart = 0; end
                if nargin < 4 || isempty(idxImageEnd),   idxImageEnd = idxImageStart; end
                if isscalar(idxImageStart), idxImageStart = repmat(idxImageStart,size(idxBuffer)); end
                if isscalar(idxImageEnd),     idxImageEnd = repmat(idxImageEnd,size(idxBuffer)); end
                for n = 1:numel(idxBuffer)
                    mydo(obj,true,0, 'PCO_AddBufferEx', ...
                        obj.p_SDK.camHandle, uint32(idxImageStart(n)), uint32(idxImageEnd(n)), obj.p_Buffer(idxBuffer(n)).BufferID,...
                        uint16(obj.p_Buffer(idxBuffer(n)).ImageSize(1)),uint16(obj.p_Buffer(idxBuffer(n)).ImageSize(2)),...
                        uint16(obj.p_Buffer(n).BitsPerPixel));
                end
            else
                error(sprintf('%s:Input',mfilename),...
                    'No buffer(s) are allocated for %s, please check!',obj.Name);
            end
        end
        
        function                           p_getBuffer(obj,idxBuffer)
            % p_getBuffer Gets the data of an allocated buffer
            %
            % This is the workhorse function without much error checking for class internal use
            
            if ~isempty(obj.p_Buffer)
                if nargin < 2 || isempty(idxBuffer), idxBuffer = 1:numel(obj.p_Buffer); end
                for n = reshape(idxBuffer,1,[])
                    [~, obj.p_SDK.camHandle, obj.p_Buffer(n).Image] = mydo(obj,true,0, 'PCO_GetBuffer', ...
                        obj.p_SDK.camHandle, obj.p_Buffer(n).BufferID,obj.p_Buffer(n).im_ptr,obj.p_Buffer(n).ev_ptr);
                end
            else
                error(sprintf('%s:Input',mfilename),...
                    'No buffer(s) are allocated for %s, please check!',obj.Name);
            end
        end
        
        function                           p_killBuffer(obj)
            % p_killBuffer Deletes buffer structure in object
            %
            % This is the workhorse function without much error checking for class internal use
            
            obj.p_Buffer = [];
        end
        
        function                           p_removeBuffer(obj)
            % p_removeBuffer Removes any buffer from the driver queue
            %
            % This is the workhorse function without much error checking for class internal use
            
            mydo(obj,true,0, 'PCO_RemoveBuffer', ...
                obj.p_SDK.camHandle);
        end
        
        function inTime                  = p_getImage(obj,idxBuffer,idxImage,idxSegment)
            % p_getImage Transfers images into buffers from a certain segment and returns if no
            % timeout was triggered as true/false
            %
            % This is the workhorse function without much error checking for class internal use
            
            if ~isempty(obj.p_Buffer)
                if nargin < 4, idxSegment = obj.p_ActiveSegment; end
                inTime = true;
                for n = 1:numel(idxBuffer)
                    err = mydo(obj,false,0, 'PCO_GetImageEx', ...
                        obj.p_SDK.camHandle, uint16(idxSegment), uint32(idxImage(n)), uint32(idxImage(n)), obj.p_Buffer(idxBuffer(n)).BufferID,...
                        uint16(obj.p_Buffer(idxBuffer(n)).ImageSize(1)),uint16(obj.p_Buffer(idxBuffer(n)).ImageSize(2)),...
                        uint16(obj.p_Buffer(idxBuffer(n)).BitsPerPixel));
                    if err ~= 0
                        [~, errH] = obj.pco_err2err(err);
                        if strcmp(errH(1:3),'0xA') && strcmp(errH(end-2:end),'005')
                            % this should be a timeout error, so no image available
                            inTime = false;
                            return;
                        else
                            % throw error
                            showError(obj,err,'PCO_GetImageEx in p_getImage');
                        end
                    end
                end
            else
                error(sprintf('%s:Input',mfilename),...
                    'No buffer(s) are allocated for %s, please check!',obj.Name);
            end
        end
        
        function out                     = p_freeBuffer(obj,idxBuffer)
            % p_freeBuffer Frees a previously allocated buffer and returns if all buffers are free
            % and, therefore, deleted from the MATALB object
            %
            % This is the workhorse function without much error checking for class internal use
            
            if ~isempty(obj.p_Buffer)
                if nargin < 2 || isempty(idxBuffer), idxBuffer = 1:numel(obj.p_Buffer); end
                for n = reshape(idxBuffer,1,[])
                    err = mydo(obj,false,0, 'PCO_FreeBuffer', ...
                        obj.p_SDK.camHandle, obj.p_Buffer(n).BufferID);
                    if err ~= 0
                        [~, errH] = obj.pco_err2err(err);
                        if ~(strcmp(errH(1:3),'0x8') && strcmp(errH(end-3:end),'300B'))
                            % ignore error that buffer is not available but throw anything else
                            showError(obj,err,'PCO_FreeBuffer in p_freeBuffer');
                        end
                    end
                    obj.p_Buffer(n).Free = true;
                end
                % check if all buffers can be removed
                if all([obj.p_Buffer.Free])
                    [~,stDRV,stBuff] = p_checkBuffer(obj);
                    if ~all(stDRV == 0)
                        [~, errH] = obj.pco_err2err(stDRV);
                        for i = 1:numel(stDRV)
                            if (strcmp(errH(i,1:3),'0x8') && strcmp(errH(i,end-3:end),'2007')) ||...
                                    (strcmp(errH(i,1:3),'0x8') && strcmp(errH(i,end-3:end),'300B'))  || ...
                                    (strcmp(errH(i,1:3),'0x8') && strcmp(errH(i,end-3:end),'2010')) || ...
                                    (strcmp(errH(i,1:3),'0x8') && strcmp(errH(i,end-3:end),'101F'))
                                % ignore the following errors:
                                % * I/O did not work
                                % * a requested buffer is not available
                                % * buffer was cancelled
                                % * image read not possible
                            else
                                % throw any other error
                                showError(obj,stDRV(i),sprintf('p_checkBuffer for buffer %d in p_freeBuffer',i));
                            end
                        end
                    end
                    if ~any([stBuff.ALLOCATED])
                        obj.p_Buffer = [];
                    else
                        error(sprintf('%s:Input',mfilename),...
                            'Buffer(s) of %s could not be free, please check!',obj.Name);
                    end
                end
            end
            out = isempty(obj.p_Buffer);
        end
        
        function [stDLL,stDRV,structDLL] = p_checkBuffer(obj,idxBuffer)
            % p_checkBuffer Get the buffer status of a previously allocated and added buffer
            %
            % This can be used to poll the status, while waiting for an image during recording.
            % After an image has been transferred it is recommended to check the buffer status
            % according to driver errors, which might occur during the image transfer. Function
            % returns the status of the DLL and the driver.
            %
            % This is the workhorse function without much error checking for class internal use
            
            if ~isempty(obj.p_Buffer)
                if nargin < 2 || isempty(idxBuffer), idxBuffer = 1:numel(obj.p_Buffer); end
                stDLL = NaN(size(idxBuffer));
                stDRV = NaN(size(idxBuffer));
                for n = 1:numel(idxBuffer)
                    sdll = uint32(0);
                    sdrv = uint32(0);
                    [~, obj.p_SDK.camHandle, sdll, sdrv] = mydo(obj,true,0, 'PCO_GetBufferStatus', ...
                        obj.p_SDK.camHandle, obj.p_Buffer(idxBuffer(n)).BufferID, sdll, sdrv);
                    stDLL(n) = sdll; stDRV(n) = sdrv;
                    if n == 1
                        structDLL    = obj.catStatus(obj.Table_BufferStatus,sdll);
                    else
                        structDLL(n) = obj.catStatus(obj.Table_BufferStatus,sdll);
                    end
                end
            else
                error(sprintf('%s:Input',mfilename),...
                    'No buffer(s) are allocated for %s, please check!',obj.Name);
            end
        end
        
        function [inTime, stat]          = p_waitForBuffer(obj,idxBuffer,timeout)
            % p_waitForBuffer Checks all given buffer whether one of them is triggered within timeout.
            % It returns the indices of all triggered buffers where an event is set and the status
            % of all checked buffers
            %
            % This is the workhorse function without much error checking for class internal use
            
            if ~isempty(obj.p_Buffer)
                if nargin < 2 || isempty(idxBuffer), idxBuffer = 1:numel(obj.p_Buffer); end
                if nargin < 3 || isempty(timeout),   timeout   = 1; end
                % wait for buffer(s) and capture timeout error
                tmp = struct;
                for n = 1:numel(idxBuffer)
                    tmp(n).sBufNr        = obj.p_Buffer(idxBuffer(n)).BufferID;
                    tmp(n).ZZwAlignDummy = uint16(0);
                    tmp(n).dwStatusDll   = uint32(0);
                    tmp(n).dwStatusDrv   = uint32(0);
                end
                tmp1 = libstruct('PCO_Buflist',tmp);
                err  = mydo(obj,false,0, 'PCO_WaitforBuffer', ...
                    obj.p_SDK.camHandle, int32(numel(idxBuffer)), tmp1, int32(timeout * 1e3));
                if err ~= 0
                    [~, errH] = obj.pco_err2err(err);
                    if strcmp(errH(1:3),'0xA') && strcmp(errH(end-2:end),'005')
                        % this should be a timeout error, so no buffer at all was triggered
                        inTime     = [];
                        [~,stDRV,stat] = p_checkBuffer(obj,idxBuffer);
                    else
                        % throw error
                        showError(obj,err,'PCO_WaitforBuffer in p_waitBuffer');
                    end
                else
                    [~,stDRV,stat] = p_checkBuffer(obj,idxBuffer);
                    inTime     = idxBuffer([stat.EVENT_SET]);
                end
                % check driver error from checkBuffer
                if ~all(stDRV == 0)
                    for i = 1:numel(stDRV)
                        % throw any other error
                        showError(obj,stDRV(i),sprintf('p_checkBuffer for buffer %d in p_waitForBuffer',idxBuffer(i)));
                    end
                end
            else
                error(sprintf('%s:Input',mfilename),...
                    'No buffer(s) are allocated for %s, please check!',obj.Name);
            end
        end
        
        function [nImage, nImageMax]     = p_checkRamSegment(obj,idxSegment)
            % p_checkRamSegment Checks for current and maximum number of images in RAM segment(s)
            %
            % This is the workhorse function without much error checking for class internal use
            
            if nargin < 2 || isempty(idxSegment), idxSegment = obj.p_ActiveSegment; end
            nImage    = NaN(size(idxSegment));
            nImageMax = NaN(size(idxSegment));
            if ~obj.Description.GeneralCapsDESC1.NO_RECORDER
                for n = 1:numel(idxSegment)
                    ni = uint32(0);
                    nm = uint32(0);
                    [~, obj.p_SDK.camHandle,ni,nm] = mydo(obj,true,0, 'PCO_GetNumberOfImagesInSegment', ...
                        obj.p_SDK.camHandle,uint16(idxSegment(n)),ni,nm);
                    nImage(n) = double(ni); nImageMax(n) = double(nm);
                end
            end
        end
        
        function varargout = mydo(obj,doErr,doWait,varargin)
            % mydo Runs command in SDK library, checks for errors (second input (logical) can be
            % used to disable this) and can be configured by the third input (double for the time to
            % wait) to try another time in case of a timeout, the actual command and input arguments
            % for the SDK start from the fourth input argument, first output argument is the error
            % code returned by the SDK library followed by any other return value of the specific
            % command that was run in the SDK.
            
            [varargout{1:nargout}] = calllib(obj.p_SDK.alias, varargin{:});
            if doWait > 0
                [~, errH] = obj.pco_err2err(varargout{1});
                if strcmp(errH(1:3),'0xA') && strcmp(errH(end-2:end),'005')
                    % this should be a timeout error, wait and try again
                    pause(doWait);
                    [varargout{1:nargout}] = mydo(obj,doErr,0,varargin{:});
                    varargout              = varargout(1:nargout);
                    return;
                end
            end
            if doErr && varargout{1} ~= 0
                showError(obj,varargout{1},varargin{1});
            end
            varargout = varargout(1:nargout);
        end
        
        function                           showError(obj,err,cmd)
            % showError Processes the error code returned by calllib and the SDK library
            
            if ~all(err == 0)
                idx          = find(err ~= 0,1,'first');
                [errU, errH] = obj.pco_err2err(err(idx));
                if numel(err) > 1
                    str = sprintf(' (first bad error code is number %d out of %d)',idx,numel(err));
                else
                    str = '';
                end
                if nargin < 3
                    error(sprintf('%s:Input',mfilename),...
                        '%s returned %d (%s) as error code%s, please check PCO_err.h for further details!',...
                        obj.Name, errU(idx), errH(idx,:),str);
                else
                    error(sprintf('%s:Input',mfilename),['%s returned %d (%s) as error code%s during ',...
                        'execution of command ''%s'', please check PCO_err.h for further details!'],...
                        obj.Name, errU(idx), errH(idx,:),str,cmd);
                end
            end
        end
    end
    
    %% Static Methods
    methods (Static = true, Access = public, Hidden = false, Sealed = true)
        function obj                 = loadobj(S)
            %loadobj Loads object and tries to re-connect to hardware
            
            try
                % try to connect and set channel settings (the ones that can be changed)
                for n = 1:numel(S)
                    S(n).Recover.showInfoOnConstruction = false;
                    obj(n)                = PCO(S(n).Recover); %#ok<AGROW>
                    obj(n).Settings       = S(n).Settings; %#ok<AGROW>
                    obj(n).LoggingDetails = S(n).LoggingDetails; %#ok<AGROW>
                    showInfo(obj(n));
                end
            catch err
                warning(sprintf('%s:Input',mfilename),...
                    'Device could not be re-connected during load process: %s',err.getReport);
            end
        end
        
        function [st1, st2]          = catStatus(table,code)
            % catStatus Check which state in a given table (state and hex code as cell) is set in
            % the given code, the function returns a structure and string with the results
            
            st1 = struct; st2 = '';
            for i = 1:size(table,1)
                tmp   = cast(hex2dec(table{i,2}(3:end)),'like',code);
                isSet = bitand(code,tmp) > 0;
                st1.(table{i,1}) = isSet;
                if isSet, st2 = [st2 table{i,1} ', ' ]; end %#ok<AGROW>
            end
            if numel(st2) > 0, st2 = st2(1:end-2); end
        end
        
        function [errUINT32, errHEX] = pco_err2err(err)
            % pco_err2err Converts error code returned by library to a uint32 and HEX number, where
            % the HEX number is returned as a string
            
            if err < 0
                errUINT32 = uint32(-1*err) - 1;
                errUINT32 = bitcmp(errUINT32,'uint32');
            else
                errUINT32 = uint32(err);
            end
            errHEX = repmat(['0x' num2str(errUINT32(1),'%08X')],numel(err),1);
            for i = 2:numel(errUINT32)
                errHEX(i,:) = ['0x' num2str(errUINT32(i),'%08X')];
            end
        end
        
        function [time, idx]         = pco_timestamp(in, bitAlign, bitPix)
            % pco_timestamp Reads the timestamp information from 14 pixels and returns image counter
            % as double and time as as datetime, give matrix of size n x 14 to get the timestamp of
            % multiple images
            
            %
            % check input
            assert((isa(in,'uint8') || isa(in,'uint16')) &&isnumeric(in) && ...
                ((isvector(in) && numel(in) == 14) || (ismatrix(in) && size(in,2) == 14)),...
                sprintf('%s:Input',mfilename), ['First input should be a 14 element numeric array with a PCO time stamp ',...
                'or a matrix with size(in,2) == 14 for multiple timestamps']);
            assert((ischar(bitAlign) && ismember(lower(bitAlign),{'msb' 'lsb'})) || ...
                ((isnumeric(bitAlign) || islogical(bitAlign)) && isscalar(bitAlign)),...
                sprintf('%s:Input',mfilename), ['Second input should be a scalar indicating the bit alignment ',...
                'or a char (''msb'' or ''lsb'')']);
            assert(isnumeric(bitPix) && isscalar(bitPix),...
                sprintf('%s:Input',mfilename), 'Third input should be a scalar indicating the bits per pixel');
            %
            % prepare input
            if isvector(in), in = reshape(in,1,[]); end
            if ischar(bitAlign)
                if strcmpi(bitAlign,'msb'), bitAlign = 0; else, bitAlign = 1; end
            end
            if bitAlign == 0
                in = fix(double(in)/(2^(16-bitPix)));
            else
                in = double(in);
            end
            %
            % compute data
            nCodes = size(in,1);
            idx    = sum((bitshift(in(:,1:4),-4)*10+bitand(15,in(:,1:4))) .* repmat(10.^[6 4 2 0],nCodes,1),2);
            YYYY   = sum((bitshift(in(:,5:6),-4)*10+bitand(15,in(:,5:6))) .* repmat(10.^[2 0],nCodes,1),2);
            MM     = bitshift(in(:,7),-4)*10+bitand(15,in(:,7));
            DD     = bitshift(in(:,8),-4)*10+bitand(15,in(:,8));
            HH     = bitshift(in(:,9),-4)*10+bitand(15,in(:,9));
            mm     = bitshift(in(:,10),-4)*10+bitand(15,in(:,10));
            SS     = bitshift(in(:,11),-4)*10+bitand(15,in(:,11)) + ...
                sum((bitshift(in(:,12:14),-4)*10+bitand(15,in(:,12:14))) .* repmat(10.^[-2 -4 -6],nCodes,1),2);
            time   = datetime(YYYY,MM,DD,HH,mm,SS);
        end
    end
end
