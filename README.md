# MATLAB-Devices
A collection of classes to control lab instruments such as a pulse delay generator or a syringe pump within MATLAB

## Installation
Add the parent directory that holds all @-folders to you local MATLAB path. This task can easily be done
	with MATLAB's `addpath` and `genpath` functions. The devices itself must be installed as described by the
	manufacturer, such that a connection is possible, e.g. via a serial port (see `PHDUltra` for an example),
	a SDK (see `PCO` for an example), an ActiveX object (see `ThorlabsRM` for an example), a VISA object (see `KeysightWG` for an example) or similar.

## Usage
A class design is chosen to create a (virtual) handle object within MATLAB that represents the actual 
hardware. Have a look at each class implementation, i.e. by opening the help for a certain device, e.g. call 
`doc BNC575` do get information on the class to control the pulse delay generator `BNC575`. To create the object
call the class constructor (see the source code for options that can be passed to the constructor), a short example is given here for the `BNC575`:
```
% connect BNC575 available at COM port 19
mydev = BNC575('Port', 'COM19');
% enable channel 1 and start generating pulses
mydev.Channel(1).enable  = true;
mydev.start;
```