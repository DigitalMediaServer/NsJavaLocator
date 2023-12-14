library NsJavaLocator;
{
  NsJavaLocator, a NSIS plugin for locating Java installations.
  Copyright (C) 2023 Digital Media Server developers.

  This program is free software; you can redistribute it and/or modify it under the terms of the GNU Lesser General
  Public License as published by the Free Software Foundation; either version 3 of the License, or (at your option)
  any later version.

  This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied
  warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU Lesser General Public License for more
  details.

  You should have received a copy of the GNU Lesser General Public License along with this library; if not, write to
  the Free Software Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
}

{$MODE Delphi}
{$WARN 6058 off : Call to subroutine "$1" marked as inline is not inlined}
{$WARN 3123 off : "$1" not yet supported inside inline procedure/function}
{$WARN 3124 off : Inlining disabled}
{$WARN 4055 off : Conversion between ordinals and pointers is not portable}

{$R *.res}

uses
	Windows,
	SysUtils,
	Classes,
	fgl,
	NSIS,
	Core,
	Utils;

type

	{ TParameters }

	TParameters = class(TObject, TSettings)
	private
		FRegistryPaths : TVStringList;
		FEnvironmentVariables : TVStringList;
		FFilePaths : TVStringList;
		FFilteredPaths : TVStringList;
		FIsSkipOSPath : Boolean;
		FMinVersion : VString;
		FMaxVersion : VString;
		FOptimalVersion : VString;
		FLogLevel : TLogLevel;
		FIsLogging : Boolean;
		FIsDialogDebug : Boolean;
		function ReadParams() : TVStringList;
		function GetLogLevel() : TLogLevel;
		function GetLogging() : Boolean;
		function GetDialogDebug() : Boolean;
	public
		function GetRegistryPaths() : TVStringList;
		function GetEnvironmentVariables() : TVStringList;
		function GetFilePaths() : TVStringList;
		function GetFilteredPaths() : TVStringList;
		function GetSkipOSPath() : Boolean;
		function GetMinVersion() : VString;
		function GetMaxVersion() : VString;
		function GetOptimalVersion() : VString;
		procedure ParseParams();
		constructor Create();
		destructor Destroy(); override;
	published
		property RegistryPaths : TVStringList read GetRegistryPaths;
		property EnvironmentVariables : TVStringList read GetEnvironmentVariables;
		property FilePaths : TVStringList read GetFilePaths;
		property FilteredPaths : TVStringList read GetFilteredPaths;
		property IsSkipOSPath : Boolean read GetSkipOSPath;
		property MaxVersion : VString read GetMaxVersion;
		property MinVersion : VString read GetMinVersion;
		property OptimalVersion : VString read GetOptimalVersion;
		property LogLevel : TLogLevel read GetLogLevel;
		property IsLogging : Boolean read GetLogging;
		property IsDialogDebug : Boolean read GetDialogDebug;
	end;

	{ TRunner }

	TRunner = class(TObject, TLogger)
	private
		FParams : TParameters;
		FLogLevel : TLogLevel;
	public
		procedure Log(const Message : VString; const LogLevel : TLogLevel);
		function IsWarn() : Boolean;
		function IsInfo() : Boolean;
		function IsDebug() : Boolean;
		procedure Run();
		constructor Create();
		destructor Destroy(); override;
	end;

{ TRunner }

procedure TRunner.Log(const Message : VString; const LogLevel : TLogLevel);

var
	Icon : TDialaogIcon;

begin
	if LogLevel > FLogLevel then Exit;
	if FParams.IsLogging then begin
		if LogLevel = TLogLevel.ERROR then LogMessage('Error: ' + Message)
		else if LogLevel = TLogLevel.WARN then LogMessage('Warning: ' + Message)
		else LogMessage(Message);
	end;
	if FParams.IsDialogDebug then begin
		case LogLevel of
			TLogLevel.ERROR: Icon := TDialaogIcon.Error;
			TLogLevel.WARN: Icon := TDialaogIcon.Warning;
			TLogLevel.INFO: Icon := TDialaogIcon.Info;
			TLogLevel.DEBUG: Icon := TDialaogIcon.Info;
		else Icon := TDialaogIcon.None;
		end;
		NSISDialog(Message, LogLevelToVStr(LogLevel), MB_OK, Icon);
	end;
end;

function TRunner.IsWarn() : Boolean;
begin
	Result := FLogLevel >= TLogLevel.WARN;
end;

function TRunner.IsInfo() : Boolean;
begin
	Result := FLogLevel >= TLogLevel.INFO;
end;

function TRunner.IsDebug() : Boolean;
begin
	Result := FLogLevel >= TLogLevel.DEBUG;
end;

procedure TRunner.Run();

var
	Parser : TParser;
	Evaluator : TEvaluator;

begin
	FParams.ParseParams();
	FLogLevel := FParams.LogLevel;
	Parser := TParser.Create(FParams, Self);
	try
		Parser.Process();
		Evaluator := TEvaluator.Create(Parser.Installations, FParams, Self);
		try
			Evaluator.Process();
		finally
			Evaluator.Free();
		end;
	finally
		Parser.Free();
	end;
end;

constructor TRunner.Create();
begin
	FParams := TParameters.Create();
	FLogLevel := TLogLevel.INFO;
end;

destructor TRunner.Destroy();
begin
	FParams.Free();
	inherited Destroy;
end;

function TParameters.GetRegistryPaths() : TVStringList;
begin
	Result := FRegistryPaths;
end;

function TParameters.GetEnvironmentVariables() : TVStringList;
begin
	Result := FEnvironmentVariables;
end;

function TParameters.GetFilePaths() : TVStringList;
begin
	Result := FFilePaths;
end;

function TParameters.GetFilteredPaths() : TVStringList;
begin
	Result := FFilteredPaths;
end;

function TParameters.GetSkipOSPath() : Boolean;
begin
	Result := FIsSkipOSPath;
end;

function TParameters.GetMinVersion() : VString;
begin
	Result := FMinVersion;
end;

function TParameters.GetMaxVersion() : VString;
begin
	Result := FMaxVersion;
end;

function TParameters.GetOptimalVersion() : VString;
begin
	Result := FOptimalVersion;
end;

function TParameters.ReadParams() : TVStringList;

var
	parameter : VString;

begin
	Result := TVStringList.Create();
	parameter := PopString();
	while (not EqualStr(parameter, '/END', False)) and (not EqualStr(parameter, '/END;', False)) do begin
		Result.Add(parameter);
		parameter := PopString();
	end;
end;

function TParameters.GetLogLevel() : TLogLevel;
begin
	Result := FLogLevel;
end;

function TParameters.GetLogging() : Boolean;
begin
	Result := FIsLogging;
end;

function TParameters.GetDialogDebug() : Boolean;
begin
	Result := FIsDialogDebug;
end;

procedure TParameters.ParseParams();

const
	poReg = '/REGPATH';
	poRegDel = '/DELREGPATH';
	poEnv = '/ENVSTR';
	poEnvDel = '/DELENVSTR';
	poFilterAdd = '/ADDFILTER';
	poFilterDel = '/DELFILTER';
	poSkipOSPath = '/SKIPOSPATH';
	poMinVer = '/MINVER';
	poMaxVer = '/MAXVER';
	poOptVer = '/OPTVER';
	poLog = '/LOG';
	poDialogDebug = '/DIALOGDEBUG';
	poLogLevel = '/LOGLEVEL';

var
	parameterList : TVStringList;
	i : Integer;
	s, dialogStr : VString;
	tmpLogLevel : TLogLevel;

begin
	parameterList := readParams();
	i := 0;
	while i < parameterList.Count do begin
		if parameterList[i][1] = '/' then begin
			if EqualStr(poLog, parameterList[i], False) then FIsLogging := True
			else if EqualStr(poDialogDebug, parameterList[i], False) then FIsDialogDebug := True
			else if EqualStr(poSkipOSPath, parameterList[i], False) then FIsSkipOSPath := True

			// All value-less options must be handled before this point
			else if (i + 1 >= parameterList.Count) or (parameterList[i + 1][1] = '/') then begin
				NSISDialog('Missin option value for "' + parameterList[i] + '"', 'Error', MB_OK, TDialaogIcon.Error);
			end else if Trim(parameterList[i + 1]) = '' then begin
				NSISDialog('Empty option value for "' + parameterList[i] + '"', 'Error', MB_OK, TDialaogIcon.Error);
				Inc(i);
			end
			else if EqualStr(poReg, parameterList[i], False) then begin
				FRegistryPaths.AddUnique(parameterList[i + 1], False);
				Inc(i);
			end
			else if EqualStr(poRegDel, parameterList[i], False) then begin
				FRegistryPaths.RemoveMatching(parameterList[i + 1], False);
				Inc(i);
			end
			else if EqualStr(poEnv, parameterList[i], False) then begin
				FEnvironmentVariables.AddUnique(parameterList[i + 1], False);
				Inc(i);
			end
			else if EqualStr(poEnvDel, parameterList[i], False) then begin
				FEnvironmentVariables.RemoveMatching(parameterList[i + 1], False);
				Inc(i);
			end
			else if EqualStr(poFilterAdd, parameterList[i], False) then begin
				s := ExpandEnvStrings(parameterList[i + 1]);
				if (s <> '') and (s <> parameterList[i + 1]) then FFilteredPaths.AddUnique(s, False)
				else FFilteredPaths.AddUnique(parameterList[i + 1], False);
				Inc(i);
			end
			else if EqualStr(poFilterDel, parameterList[i], False) then begin
				FFilteredPaths.RemoveMatching(parameterList[i + 1], False);
				s := ExpandEnvStrings(parameterList[i + 1]);
				if (s <> '') and (s <> parameterList[i + 1]) then FFilteredPaths.RemoveMatching(s, False);
				Inc(i);
			end
			else if EqualStr(poMinVer, parameterList[i], False) then begin
				FMinVersion := parameterList[i + 1];
				Inc(i);
			end
			else if EqualStr(poMaxVer, parameterList[i], False) then begin
				FMaxVersion := parameterList[i + 1];
				Inc(i);
			end
			else if EqualStr(poOptVer, parameterList[i], False) then begin
				FOptimalVersion := parameterList[i + 1];
				Inc(i);
			end
			else if EqualStr(poLogLevel, parameterList[i], False) then begin
				tmpLogLevel := VStrToLogLevel(parameterList[i + 1]);
				if tmpLogLevel = TLogLevel.INVALID then
					NSISDialog('Invalid log level "' + parameterList[i + 1] + '"', 'Error', MB_OK, TDialaogIcon.Error)
				else
					FLogLevel := tmpLogLevel;
				Inc(i);
			end
			else begin
				NSISDialog('Invalid option "' + parameterList[i] + '"', 'Error', MB_OK, TDialaogIcon.Error);
			end;
		end
		else begin
			FFilePaths.AddUnique(parameterList[i], False);
		end;
		Inc(i);
	end;
	parameterList.Free;

	for i := 0 to FFilePaths.Count - 1 do begin
		s := ExpandEnvStrings(FFilePaths[i]);
		if s <> FFilePaths[i] then begin
			FFilePaths[i] := s;
		end
	end;

	if (FIsLogging or FIsDialogDebug) and (FLogLevel >= TLogLevel.DEBUG) then begin
		dialogStr := '';
		for i := 0 to FRegistryPaths.Count - 1 do begin
			if FIsLogging then LogMessage('Registry Path ' + IntToVStr(i + 1) + ': ' + FRegistryPaths[i]);
			if FIsDialogDebug then dialogStr := dialogStr + 'Registry Path ' + IntToVStr(i + 1) + ': ' + FRegistryPaths[i] + #13#10;
		end;
		if dialogStr <> '' then NSISDialog(dialogStr, 'Registry Paths');
		dialogStr := '';
		for i := 0 to FEnvironmentVariables.Count - 1 do begin
			if FIsLogging then LogMessage('Environment Variable ' + IntToVStr(i + 1) + ': ' + FEnvironmentVariables[i]);
			if FIsDialogDebug then dialogStr := dialogStr + 'Environment Variable ' + IntToVStr(i + 1) + ': ' + FEnvironmentVariables[i] + #13#10;
		end;
		if dialogStr <> '' then NSISDialog(dialogStr, 'Environment Variables');
		dialogStr := '';
		for i := 0 to FFilePaths.Count - 1 do begin
			if FIsLogging then LogMessage('File Path ' + IntToVStr(i + 1) + ': ' + FFilePaths[i]);
			if FIsDialogDebug then dialogStr := dialogStr + 'File Path ' + IntToVStr(i + 1) + ': ' + FFilePaths[i] +#13#10;
		end;
		if dialogStr <> '' then NSISDialog(dialogStr, 'File Paths');
		dialogStr := '';
		for i := 0 to FFilteredPaths.Count - 1 do begin
			if FIsLogging then LogMessage('Filtered Path ' + IntToVStr(i + 1) + ': ' + FFilteredPaths[i]);
			if FIsDialogDebug then dialogStr := dialogStr + 'Filtered Path ' + IntToVStr(i + 1) + ': ' + FFilteredPaths[i] + #13#10;
		end;
		if dialogStr <> '' then NSISDialog(dialogStr, 'Filtered Paths');
	end;
end;

constructor TParameters.Create();

{
	Observed registry paths:													Relevant value(s):

	"JavaSoft" registry entries created by various JDK/JRE packages

	HKLM\SOFTWARE\JavaSoft\Java Development Kit\1.7								JavaHome:str
	HKLM\SOFTWARE\JavaSoft\Java Development Kit\1.7.0_141						JavaHome:str
	HKLM\SOFTWARE\JavaSoft\Java Development Kit\1.8.0_201						JavaHome:str
	HKLM\SOFTWARE\JavaSoft\Java Development Kit\1.8.0_201\MSI					INSTALLDIR:str
	HKLM\SOFTWARE\JavaSoft\Java Development Kit\1.8								JavaHome:str
	HKLM\SOFTWARE\JavaSoft\Java Development Kit\1.8.0_392						JavaHome:str
	HKLM\SOFTWARE\JavaSoft\Java Development Kit\1.8.0_392\MSI					INSTALLDIR:str
	HKLM\SOFTWARE\JavaSoft\Java Development Kit\8.0								JavaHome:str
	HKLM\SOFTWARE\JavaSoft\Java Development Kit\8.0.392							JavaHome:str
	HKLM\SOFTWARE\JavaSoft\Java Runtime Environment\1.7							JavaHome:str
	HKLM\SOFTWARE\JavaSoft\Java Runtime Environment\1.7.0_141					JavaHome:str
	HKLM\SOFTWARE\JavaSoft\Java Runtime Environment\1.7.0_141\MSI				INSTALLDIR:str, PRODUCTVERSION:str, FullVersion:str
	HKLM\SOFTWARE\JavaSoft\Java Runtime Environment\1.8							JavaHome:str
	HKLM\SOFTWARE\JavaSoft\Java Runtime Environment\1.8.0_201					JavaHome:str
	HKLM\SOFTWARE\JavaSoft\Java Runtime Environment\1.8.0_201\MSI				INSTALLDIR:str, PRODUCTVERSION:str, FullVersion:str
	HKLM\SOFTWARE\JavaSoft\Java Runtime Environment\1.8.0_391					JavaHome:str
	HKLM\SOFTWARE\JavaSoft\Java Runtime Environment\1.8.0_391\MSI				INSTALLDIR:str, PRODUCTVERSION:str, FullVersion:str
	HKLM\SOFTWARE\JavaSoft\Java Runtime Environment\1.8.0_392					JavaHome:str
	HKLM\SOFTWARE\JavaSoft\Java Runtime Environment\1.8.0_392\MSI				INSTALLDIR:str
	HKLM\SOFTWARE\JavaSoft\Java Runtime Environment\8.0.382.5					JavaHome:str
	HKLM\SOFTWARE\JavaSoft\Java Runtime Environment\8.0.392						JavaHome:str
	HKLM\SOFTWARE\JavaSoft\JDK\17.0.9											JavaHome:str
	HKLM\SOFTWARE\JavaSoft\JDK\17.0.9\MSI										INSTALLDIR:str
	HKLM\SOFTWARE\JavaSoft\JDK\21.0.1											JavaHome:str
	HKLM\SOFTWARE\JavaSoft\JDK\21.0.1\MSI										INSTALLDIR:str
	HKLM\SOFTWARE\WOW6432Node\JavaSoft\Java Development Kit\1.8.0_151			JavaHome:str
	HKLM\SOFTWARE\WOW6432Node\JavaSoft\Java Development Kit\1.8.0_151\MSI		INSTALLDIR:str
	HKLM\SOFTWARE\WOW6432Node\JavaSoft\Java Development Kit\1.8.0_392			JavaHome:str
	HKLM\SOFTWARE\WOW6432Node\JavaSoft\Java Runtime Environment\1.7.0_80		JavaHome:str
	HKLM\SOFTWARE\WOW6432Node\JavaSoft\Java Runtime Environment\1.7.0_80\MSI	INSTALLDIR:str, PRODUCTVERSION:str, FullVersion:str

	Regular registry entries created by various JDK/JRE packages

	Eclipse Adoptium/Temurin:

	HKLM\SOFTWARE\Eclipse Adoptium\JRE\8.0.392.8\hotspot\MSI					Path:str
	HKLM\SOFTWARE\Eclipse Adoptium\JDK\21.0.1.12\hotspot\MSI					Path:str
	HKLM\SOFTWARE\WOW6432Node\Eclipse Adoptium\JRE\8.0.392.8\hotspot\MSI		Path:str
	HKLM\SOFTWARE\WOW6432Node\Eclipse Adoptium\JDK\8.0.392.8\hotspot\MSI		Path:str

	Azul:

	HKLM\SOFTWARE\Azul Systems\Zulu\zulu-8										InstallationPath:str, MajorVersion:int, MinorVersion:int, CurrentVersion:str
	HKLM\SOFTWARE\Azul Systems\Zulu\zulu-8-jre									InstallationPath:str, MajorVersion:int, MinorVersion:int, CurrentVersion:str
	HKLM\SOFTWARE\WOW6432Node\Azul Systems\Zulu 32-bit\zulu-8					InstallationPath:str, MajorVersion:int, MinorVersion:int, CurrentVersion:str
	HKLM\SOFTWARE\WOW6432Node\Azul Systems\Zulu 32-bit\zulu-8-jre				InstallationPath:str, MajorVersion:int, MinorVersion:int, CurrentVersion:str

	IBM Semeru/OpenJ9:

	HKLM\SOFTWARE\Semeru\JDK\8.0.382.5\openj9\MSI								Path:str
	HKLM\SOFTWARE\WOW6432Node\Semeru\JDK\8.0.382.5\openj9\MSI					Path:str
	HKLM\SOFTWARE\WOW6432Node\Semeru\JRE\8.0.382.5\openj9\MSI					Path:str
	KKLM\SOFTWARE\Semeru\JRE\8.0.382.5\openj9\MSI								Path:str

	Bellsoft Liberica:

	HKLM\SOFTWARE\WOW6432Node\BellSoft\Liberica\jdk-8 							InstallationPath:str, MajorVersion:int, MinorVersion:int, PatchVersion:int, CurrentVersion:str
	HKLM\SOFTWARE\WOW6432Node\BellSoft\Liberica\jdk-8\MSI 						InstallationPath:str
	HKLM\SOFTWARE\BellSoft\Liberica\jre-8										InstallationPath:str, MajorVersion:int, MinorVersion:int, PatchVersion:int, CurrentVersion:str
	HKLM\SOFTWARE\BellSoft\Liberica\jre-8\MSI									InstallationPath:str
	HKLM\SOFTWARE\BellSoft\Liberica\jdk-8										InstallationPath:str, MajorVersion:int, MinorVersion:int, PatchVersion:int, CurrentVersion:str
	HKLM\SOFTWARE\BellSoft\Liberica\jdk-8\MSI									InstallationPath:str
}

const
	StandardRegPaths : array [0..5] of VString = (
		'SOFTWARE\JavaSoft',
		'SOFTWARE\Eclipse Adoptium',
		'SOFTWARE\Azul Systems\Zulu',
		'SOFTWARE\Azul Systems\Zulu 32-bit',
		'SOFTWARE\Semeru',
		'SOFTWARE\BellSoft\Liberica'
	);
	StandardFilteredPaths : array [0..5] of VString = (
		'%commonprogramfiles%\Oracle\Java\javapath',
		'%commonprogramfiles(x86)%\Oracle\Java\javapath',
		'%commonprogramW6432%\Oracle\Java\javapath',
		'%ALLUSERSPROFILE%\Oracle\Java\javapath',
		'%SystemRoot%\system32',
		'%SystemRoot%\SysWOW64'
	);

var
	i : Integer;
	s : VString;

begin
	FRegistryPaths := TVStringList.Create();
	for i := 0 to high(StandardRegPaths) do begin
		FRegistryPaths.Add(StandardRegPaths[i]);
	end;
	FEnvironmentVariables := TVStringList.Create();
	FEnvironmentVariables.Add('%JAVA_HOME%');
	FFilePaths := TVStringList.Create();
	FFilteredPaths := TVStringList.Create;
	for i := 0 to high(StandardFilteredPaths) do begin
		s := ExpandEnvStrings(StandardFilteredPaths[i]);
		// Only add filters that expand - otherwise they don't exist on the system
		if s <> StandardFilteredPaths[i] then FFilteredPaths.AddUnique(s, False);
	end;
	FIsSkipOSPath := False;
	FMinVersion := '';
	FMaxVersion := '';
	FOptimalVersion := '';
	FLogLevel := TLogLevel.INFO;
	FIsLogging := False;
	FIsDialogDebug := False;
end;

destructor TParameters.Destroy();
begin
	FFilteredPaths.Free();
	FFilePaths.Free();
	FEnvironmentVariables.Free();
	FRegistryPaths.Free();
	inherited Destroy;
end;

procedure Locate(const hwndParent: HWND; const string_size: integer; const variables: NSISPTChar; const stacktop: pointer); cdecl;

var
	runner : TRunner;

begin
	Init(hwndParent, string_size, variables, stacktop);
	runner := TRunner.Create();
	try
		runner.Run();
	finally
		runner.Free();
	end;
end;

exports Locate;

end.
