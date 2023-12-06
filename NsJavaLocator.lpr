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
	RegExpr,
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
		procedure ParseParams();
		constructor Create();
		destructor Destroy(); override;
	published
		property RegistryPaths : TVStringList read GetRegistryPaths;
		property EnvironmentVariables : TVStringList read GetEnvironmentVariables;
		property FilePaths : TVStringList read GetFilePaths;
		property LogLevel : TLogLevel read GetLogLevel;
		property IsLogging : Boolean read GetLogging;
		property IsDialogDebug : Boolean read GetDialogDebug;
	end;

	{ TParser }

	TParser = class(TObject)
	protected
		FLogger : TLogger;
		FSettings : TSettings;
		FInstallations : TFPGObjectList<TJavaInstallation>;
		FJdkJreRegEx : TRegExpr;
		FModernRegEx : TRegExpr;
		FLegacyRegEx : TRegExpr;
		FZuluRegEx : TRegExpr;
		FLibericaRegEx : TRegExpr;
		const JdkJreRE = '(?i)(JDK|JRE)';
		const ModernJavaVersionRE = '^\s*(\d+)\.(\d+)\.(\d+).*';
		const LegacyJavaVersionRE = '^\s*1\.(\d+)(?:\.(\d+)_(\d+))?\s*$';
		const ZuluRE = '(?i)^\s*zulu-(\d+)(?:-(jre))?\s*$';
		const LibericaRE = '(?i)^\s*(jre|jdk)-(\d+)\s*$';
		function GetInstallations() : TFPGObjectList<TJavaInstallation>;
		function InferTypeFromPath(const Path : VString) : TInstallationType;
		function ParseAdoptiumSemeru(hk : HKEY; const samDesired : REGSAM) : Integer;
		function ParseJavaSoft(hk : HKEY; const samDesired : REGSAM) : Integer;
		function ParseZuluLiberica(hk : HKEY; const samDesired : REGSAM) : Integer;
		procedure ProcessEnvironmentVariables();
		procedure ProcessOSPath();
		procedure ProcessRegistry(const Is64 : Boolean);
	public
		procedure Process();
		constructor Create(const Settings : TSettings; const Logger : TLogger);
		destructor Destroy(); override;
	published
		property Installations : TFPGObjectList<TJavaInstallation> read GetInstallations;
	end;

function ResolveJavawPath(const Path : VString) : VString;

begin
	Result := Path;
	if Path = '' then Exit;

	if not EndsWith('javaw.exe', Result, False) then begin
		if EndsWith('bin', Result, False) then Result := Result + '\'
		else if not EndsWith('bin\', Result, False) then begin
			if EndsWith('\', Result, True) then Result := Result + 'bin\'
			else Result := Result + '\bin\';
		end;
		Result := Result + 'javaw.exe';
	end;
end;

{
	Creates a TJavaInstallation instance if a valid result is found.
	IE, Result must be Free'd if it's non-nil upon return.
}
function GetJavawInfo(Path : VString) : TJavaInstallation;

var
	FileInfo : TFileInfo;

begin
	Result := Nil;
	if Path = '' then Exit;

	FileInfo := GetFileInfo(Path);
	if FileInfo.Valid then begin
		// Most Java 8 and below executables have the revision version stored at 10x. This is an attempt remedy the issue.
		if (FileInfo.FileVersionMajor <= 8) and (FileInfo.FileVersionRevision > 0) and (FileInfo.FileVersionRevision mod 10 = 0) then
			FileInfo.FileVersionRevision := FileInfo.FileVersionRevision div 10;
		if (FileInfo.ProductVersionMajor <= 8) and (FileInfo.ProductVersionRevision > 0) and (FileInfo.ProductVersionRevision mod 10 = 0) then
			FileInfo.ProductVersionRevision := FileInfo.ProductVersionRevision div 10;
		Result := TJavaInstallation.Create;
		Result.Version := FileInfo.ProductVersionMajor;
		Result.Build := FileInfo.ProductVersionRevision;
		Result.Path := Path;
	end;
end;

function TParser.GetInstallations : TFPGObjectList<TJavaInstallation>;
begin
	Result := FInstallations;
end;

function TParser.InferTypeFromPath(const Path : VString) : TInstallationType;

var
	parts : TVStringArray;
	i, first, last : Integer;

begin
	Result := TInstallationType.UNKNOWN;
	if Path = '' then Exit;
	parts := SplitPath(Path);
	if Length(parts) < 1 then Exit;
	first := Length(parts) - 1;
	if EqualStr('bin', parts[first], False) then Dec(first);
	if first < 0 then Exit;
	if first > 0 then last := first - 1
	else last := first;

	for i:= first downto last do begin
		if FJdkJreRegEx.Exec(parts[i]) then begin
			if EqualStr(FJdkJreRegEx.Match[1], 'JDK', False) then Result := TInstallationType.JDK
			else Result := TInstallationType.JRE;
			Exit;
		end;
	end;
end;

{
	Returns the number of added installations
}
function TParser.ParseAdoptiumSemeru(hk : HKEY; const samDesired : REGSAM) : Integer;

var
	Installation : TJavaInstallation;
	SubKeys, SubKeys2, SubKeys3, SubKeys4 : TVStringList;
	i, j, k, l, Version, Build : Integer;
	hk2, hk3, hk4, hk5 : HKEY;
	installationType : TInstallationType;
	s : VString;

begin
	Result := 0;
	SubKeys := EnumerateRegSubKeys(hk, FLogger);
	try
		for i := 0 to SubKeys.Count - 1 do begin
			if EqualStr(SubKeys[i], 'JDK', False) then installationType := TInstallationType.JDK
			else if EqualStr(SubKeys[i], 'JRE', False) then installationType := TInstallationType.JRE
			else installationType := TInstallationType.UNKNOWN;
			if installationType <> TInstallationType.UNKNOWN then begin
				hk2 := OpenRegKey(hk, SubKeys[i], samDesired, FLogger);
				SubKeys2 := EnumerateRegSubKeys(hk2, FLogger);
				try
					for j := 0 to SubKeys2.Count - 1 do begin
						FModernRegEx.InputString := SubKeys2[j];
						if (FModernRegEx.Exec) and (FModernRegEx.Match[1] <> '1') then begin
							Version := VStrToIntDef(FModernRegEx.Match[1], -1);
							Build := VStrToIntDef(FModernRegEx.Match[3], -1);
							hk3 := OpenRegKey(hk2, SubKeys2[j], samDesired, FLogger);
							if hk3 <> 0 then begin
								SubKeys3 := EnumerateRegSubKeys(hk3, FLogger);
								try
									for k := 0 to SubKeys3.Count - 1 do begin
										if EqualStr(SubKeys3[k], 'hotspot', False) or EqualStr(SubKeys3[k], 'openj9', False) then begin
											hk4 := OpenRegKey(hk3, SubKeys3[k], samDesired, FLogger);
											if hk4 <> 0 then begin
												SubKeys4 := EnumerateRegSubKeys(hk4, FLogger);
												try
													l := SubKeys4.IndexOf('MSI');
													if l >= 0 then begin
														hk5 := OpenRegKey(hk4, SubKeys4[l], samDesired, FLogger);
														if hk5 <> 0 then begin
															try
																s := GetRegString(hk5, 'Path', FLogger);
															finally
																RegCloseKey(hk5);
															end;
															if s <> '' then begin
																s := ResolveJavawPath(s);
																Installation := GetJavawInfo(s);
																if Installation <> Nil then begin
																	if (Version > 0) and (Version <> Installation.Version) then begin
																		if FLogger <> Nil then FLogger.Log(
																			'Parsed version (' + IntToVStr(Version) + ') and file version (' +
																			IntToVStr(Installation.Version) + ') differs - using parsed version',
																			TLogLevel.WARN
																		);
																		Installation.Version := Version;
																	end;
																	if (Build > -1) and (Build <> Installation.Build) then begin
																		if FLogger <> Nil then FLogger.Log(
																			'Parsed build (' + IntToVStr(Build) + ') and file build (' +
																			IntToVStr(Installation.Build) + ') differs - using parsed build',
																			TLogLevel.WARN
																		);
																		Installation.Build := Build;
																	end;
																	Installation.InstallationType := installationType;
																	Installation.Architecture := GetPEArchitecture(s);
																	if AddInstallationIfUnique(Installation, FInstallations) then Inc(Result)
																	else Installation.Free;
																end;
															end;
														end;
													end;
												finally
													SubKeys4.Free;
													RegCloseKey(hk4);
												end;
											end;
										end;
									end;
								finally
									SubKeys3.Free;
									RegCloseKey(hk3);
								end;
							end;
						end;
					end;
				finally
					SubKeys2.Free;
					RegCloseKey(hk2);
				end;
			end;
		end;
	finally
		SubKeys.Free;
	end;
end;

{
	Returns the number of added installations
}
function TParser.ParseJavaSoft(hk : HKEY; const samDesired : REGSAM) : Integer;

var
	Installation : TJavaInstallation;
	SubKeys, SubKeys2 : TVStringList;
	regEx : TRegExpr;
	i, j, Version, Build, idx : Integer;
	hk2, hk3 : HKEY;
	installationType : TInstallationType;
	s : VString;

begin
	Result := 0;
	SubKeys := EnumerateRegSubKeys(hk, FLogger);
	try
		for i := 0 to SubKeys.Count - 1 do begin
			if EqualStr(SubKeys[i], 'JDK', False) then begin
				installationType := TInstallationType.JDK;
				regEx := FModernRegEx;
			end
			else if EqualStr(SubKeys[i], 'JRE', False) then begin
				installationType := TInstallationType.JRE;
				regEx := FModernRegEx;
			end
			else if EqualStr(SubKeys[i], 'Java Development Kit', False) then begin
				installationType := TInstallationType.JDK;
				regEx := FLegacyRegEx;
			end
			else if EqualStr(SubKeys[i], 'Java Runtime Environment', False) then begin
				installationType := TInstallationType.JRE;
				regEx := FLegacyRegEx;
			end
			else installationType := TInstallationType.UNKNOWN;
			if installationType <> TInstallationType.UNKNOWN then begin
				hk2 := OpenRegKey(hk, SubKeys[i], samDesired, FLogger);
				SubKeys2 := EnumerateRegSubKeys(hk2, FLogger);
				try
					for j := 0 to SubKeys2.Count - 1 do begin
						regEx.InputString := SubKeys2[j];
						if regEx.Exec then begin
							Version := VStrToIntDef(regEx.Match[1], -1);
							if regEx.Match[3] <> '' then Build := VStrToIntDef(regEx.Match[3], -1)
							else Build := -1;
							hk3 := OpenRegKey(hk2, SubKeys2[j], samDesired, FLogger);
							if hk3 <> 0 then begin
								try
									s := GetRegString(hk3, 'JavaHome', FLogger);
									if s <> '' then begin
										s := ResolveJavawPath(s);
										Installation := GetJavawInfo(s);
										if Installation <> Nil then begin
											if (Version > 0) and (Version <> Installation.Version) then begin
												if FLogger <> Nil then FLogger.Log(
													'Parsed version (' + IntToVStr(Version) + ') and file version (' +
													IntToVStr(Installation.Version) + ') differs - using parsed version',
													TLogLevel.WARN
												);
												Installation.Version := Version;
											end;
											if (Build > -1) and (Build <> Installation.Build) then begin
												if FLogger <> Nil then FLogger.Log(
													'Parsed build (' + IntToVStr(Build) + ') and file build (' +
													IntToVStr(Installation.Build) + ') differs - using parsed build',
													TLogLevel.WARN
												);
												Installation.Build := Build;
											end;
											Installation.InstallationType := installationType;
											Installation.Architecture := GetPEArchitecture(s);
											idx := GetInstallationWithPathIdx(s, FInstallations);
											if idx > -1 then begin
												if Installation.CalcScore > FInstallations[idx].CalcScore then begin
													FInstallations.Delete(idx);
													FInstallations.Add(Installation);
													Inc(Result);
												end
												else Installation.Free;
											end
											else begin
												FInstallations.Add(Installation);
												Inc(Result);
											end;
										end;
									end;
								finally
									RegCloseKey(hk3);
								end;
							end;
						end;
					end;
				finally
					SubKeys2.Free;
					RegCloseKey(hk2);
				end;
			end;
		end;
	finally
		SubKeys.Free;
	end;
end;

{
	Returns the number of added installations
}
function TParser.ParseZuluLiberica(hk : HKEY; const samDesired : REGSAM) : Integer;

var
	Installation : TJavaInstallation;
	SubKeys : TVStringList;
	i, Version : Integer;
	InstallationType : TInstallationType;
	hk2 : HKEY;
	found : Boolean;
	nQWord : TNullableQWord;
	s : VString;

begin
	Result := 0;
	SubKeys := EnumerateRegSubKeys(hk, FLogger);
	try
		for i := 0 to SubKeys.Count - 1 do begin
			InstallationType := TInstallationType.UNKNOWN;
			found := False;
			if FZuluRegEx.Exec(SubKeys[i]) then begin
				Version := VStrToIntDef(FZuluRegEx.Match[1], -1);
				if FZuluRegEx.Match[2] <> '' then InstallationType := TInstallationType.JRE
				else InstallationType := TInstallationType.JDK;
				found := True;
			end
			else begin
				if FLibericaRegEx.Exec(SubKeys[i]) then begin
					Version := VStrToIntDef(FLibericaRegEx.Match[2], -1);
					if EqualStr('jre', FLibericaRegEx.Match[1], False) then InstallationType := TInstallationType.JRE
					else if EqualStr('jdk', FLibericaRegEx.Match[1], False) then InstallationType := TInstallationType.JDK;
					found := True;
				end;
			end;

			if found then begin
				hk2 := OpenRegKey(hk, SubKeys[i], samDesired, FLogger);
				if hk2 <> 0 then begin
					try
						s := GetRegString(hk2, 'InstallationPath', FLogger);
						if s <> '' then begin
							s := ResolveJavawPath(s);
							Installation := GetJavawInfo(s);
							if Installation <> Nil then begin
								Installation.InstallationType := InstallationType;
								nQWord := GetRegInt(hk2, 'MajorVersion', FLogger);
								if nQWord.Valid and (nQWord.Value > 0) then begin
									if (Version > 0) and (nQWord.Value <> Version) then begin
										if FLogger <> Nil then FLogger.Log(
											'Parsed version (' + IntToVStr(Version) + ') and registry version (' +
											IntToVStr(nQWord.Value) + ') differs - using registry version',
											TLogLevel.WARN
										);
										Version := nQWord.Value;
									end;
								end;
								if (Version > 0) and (Version <> Installation.Version) then begin
									if FLogger <> Nil then FLogger.Log(
										'Parsed/registry version (' + IntToVStr(Version) + ') and file version (' +
										IntToVStr(Installation.Version) + ') differs - using parsed/registry version',
										TLogLevel.WARN
									);
									Installation.Version := Version;
								end;

								nQWord := GetRegInt(hk2, 'MinorVersion', FLogger);
								if nQWord.Valid and (nQWord.Value > 0) and (nQWord.Value <> Installation.Build) then begin
									if FLogger <> Nil then FLogger.Log(
										'Registry build (' + IntToVStr(nQWord.Value) + ') and file build (' +
										IntToVStr(Installation.Version) + ') differs - using registry build',
										TLogLevel.WARN
									);
									Installation.Build := nQWord.Value;
								end;
								Installation.Architecture := GetPEArchitecture(s);
								if AddInstallationIfUnique(Installation, FInstallations) then Inc(Result)
								else Installation.Free;
							end;
						end;
					finally
						RegCloseKey(hk2);
					end;
				end;
			end;
		end;
	finally
		SubKeys.Free;
	end;
end;

procedure TParser.ProcessEnvironmentVariables;

var
	Installation : TJavaInstallation;
	InstallationType : TInstallationType;
	envVar, s : VString;

begin
	for envVar in FSettings.GetEnvironmentVariables do begin
		s := ExpandEnvStrings(envVar);
		if s <> envVar then begin
			InstallationType := InferTypeFromPath(s);
			s := ResolveJavawPath(s);
			Installation := GetJavawInfo(s);
			if Installation <> Nil then begin
				Installation.InstallationType := InstallationType;
				AddInstallationIfUnique(Installation, FInstallations);
			end;
		end;
	end;
end;

procedure TParser.ProcessOSPath;

var
	Installation : TJavaInstallation;
	PathElements : TVStringArray;
	Element, s : VString;

begin
	s := ExpandEnvStrings('%PATH%');
	if s = '%PATH%' then Exit;
	PathElements := SplitStr(s, [';']);
	if PathElements = Nil then Exit;
	for Element in PathElements do begin
		s := ResolveJavawPath(Element);
		Installation := GetJavawInfo(s);
		if Installation <> Nil then begin
			Installation.InstallationType := InferTypeFromPath(Element);
			if not AddInstallationIfUnique(Installation, FInstallations) then Installation.Free;
		end;
	end;
end;

procedure TParser.ProcessRegistry(const Is64 : Boolean);
const
	baseSamDesired = KEY_READ or KEY_QUERY_VALUE or KEY_ENUMERATE_SUB_KEYS;

var
	h, rootKey : HKEY;
	run : Integer = 0;
	samDesired : REGSAM = baseSamDesired;
	subKey : VString;

begin
	repeat
		if (run = 0) or (run = 2) then rootKey :=  HKEY_LOCAL_MACHINE
		else rootKey := HKEY_CURRENT_USER;
		if is64 then begin
			if run > 1 then samDesired := baseSamDesired or KEY_WOW64_32KEY
			else samDesired := baseSamDesired or KEY_WOW64_64KEY;
		end;

		for subKey in FSettings.GetRegistryPaths do begin
			h := OpenRegKey(rootKey, subKey, samDesired, FLogger);
			if h <> 0 then begin
				try
					if ParseAdoptiumSemeru(h, samDesired) < 1 then begin
						if ParseZuluLiberica(h, samDesired) < 1 then begin
							ParseJavaSoft(h, samDesired);
						end;
					end;
				finally
					RegCloseKey(h);
				end;
			end;
		end;
		Inc(run);
	until ((not Is64) and (run > 1)) or (run > 3);
end;

procedure TParser.Process();

var
	i : Integer;
begin
	ProcessRegistry(IsWOW64(FLogger));
	ProcessEnvironmentVariables();
	ProcessOSPath;

	if (FLogger <> Nil) and (FLogger.isDebug()) then begin
		for i := 0 to FInstallations.Count - 1 do begin
			FLogger.Log(
				'Found Java installation ' + IntToVStr(i + 1) +
				': Version=' + IntToVStr(FInstallations[i].Version) + ':' + IntToVStr(FInstallations[i].Build) +
				', Type=' + InstallationTypeToStr(FInstallations[i].InstallationType) +
				', Arch=' + ArchitectureToStr(FInstallations[i].Architecture, False) +
				', Path=' + FInstallations[i].Path,
				TLogLevel.DEBUG
			);
		end;
	end;
end;

constructor TParser.Create(const Settings : TSettings; const Logger : TLogger);
begin
	FSettings := Settings;
	FLogger := Logger;
	FInstallations := TFPGObjectList<TJavaInstallation>.Create(True);
	FJdkJreRegEx := TRegExpr.Create(JdkJreRE);
	FModernRegEx := TRegExpr.Create(ModernJavaVersionRE);
	FLegacyRegEx := TRegExpr.Create(LegacyJavaVersionRE);
	FZuluRegEx := TRegExpr.Create(ZuluRE);
	FLibericaRegEx := TRegExpr.Create(LibericaRE);
end;

destructor TParser.Destroy();
begin
	FLibericaRegEx.Free;
	FZuluRegEx.Free;
	FLegacyRegEx.Free;
	FModernRegEx.Free;
	FJdkJreRegEx.Free;
	FInstallations.Free;
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
	poLog = '/LOG';
	poDialogDebug = '/DIALOGDEBUG';
	poLogLevel = '/LOGLEVEL';

var
	parameterList : TVStringList;
	i : Integer;
	tmpLogLevel : TLogLevel;

begin
	parameterList := readParams();
	i := 0;
	while i < parameterList.Count do begin
		if parameterList[i][1] = '/' then begin
			if EqualStr(poLog, parameterList[i], False) then FIsLogging := True
			else if EqualStr(poDialogDebug, parameterList[i], False) then FIsDialogDebug := True

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

var
	i : Integer;

begin
	FRegistryPaths := TVStringList.Create();
	for i := 0 to high(StandardRegPaths) do begin
		FRegistryPaths.Add(StandardRegPaths[i]);
	end;
	FEnvironmentVariables := TVStringList.Create();
	FEnvironmentVariables.Add('%JAVA_HOME%');
	FFilePaths := TVStringList.Create();
	FLogLevel := TLogLevel.INFO;
	FIsLogging := False;
	FIsDialogDebug := False;
end;

destructor TParameters.Destroy();
begin
	FFilePaths.Free();
	FEnvironmentVariables.Free();
	FRegistryPaths.Free();
	inherited Destroy;
end;

procedure Locate(const hwndParent: HWND; const string_size: integer; const variables: NSISPTChar; const stacktop: pointer); cdecl;

var
	parameters : TParameters;
	parser : TParser;

begin
	Init(hwndParent, string_size, variables, stacktop);
	parameters := TParameters.Create();
	parameters.ParseParams();
	parser := TParser.Create(parameters, Nil);
	parser.Process();
end;

exports Locate;

end.
