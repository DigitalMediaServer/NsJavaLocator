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
	Utils;

type

	{ TParameters }

	TParameters = class(TObject)
	private
		FRegistryPaths : TVStringList;
		FEnvironmentVariables : TVStringList;
		FFilePaths : TVStringList;
		FIsLogging : Boolean;
		FIsDialogDebug : Boolean;
		function ReadParams() : TVStringList;
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
		property IsLogging : Boolean read GetLogging;
		property IsDialogDebug : Boolean read GetDialogDebug;
	end;

	{ TJavaInstallation }

	TJavaInstallation = class(TObject)
	public
		Version : Integer;
		Build : Integer;
		Path : VString;
		InstallationType : TInstallationType;
		Architecture : TArchitecture;
		Optimal : Boolean;
		function Equals(Obj : TJavaInstallation) : boolean; overload;
		function CalcScore : Integer;
		constructor Create;
		destructor Destroy; override;
	end;

const
	ModernJavaVersionRE = '^\s*(\d+)\.(\d+)\.(\d+).*';
	LegacyJavaVersionRE = '^\s*1\.(\d+)(?:\.(\d+)_(\d+))?\s*$';
	ZuluRE = '(?i)^\s*zulu-(\d+)(?:-(jre))?\s*$';
	LibericaRE = '(?i)^\s*(jre|jdk)-(\d+)\s*$';

{ TJavaInstallation }

function TJavaInstallation.Equals(Obj : TJavaInstallation) : boolean;
begin
	Result := (Obj <> Nil) and (Version = Obj.Version) and (Build = Obj.Build) and
		(InstallationType = Obj.InstallationType) and (Architecture = Obj.Architecture) and
		(Optimal = Obj.Optimal) and EqualStr(Path, Obj.Path, False);
end;

{
	Calculates a "score" that indicates how "good" information this instance has.
}
function TJavaInstallation.CalcScore : Integer;
begin
	Result := 0;
	if Path <> '' then Inc(Result, 5);
	if Version > 0 then Inc(Result);
	if Build > -1 then Inc(Result);
	if InstallationType <> TInstallationType.UNKNOWN then Inc(Result);
	if Architecture <> TArchitecture.UNKNOWN then Inc(Result);
end;

constructor TJavaInstallation.Create;
begin
	Version := -1;
	Build := -1;
	Path := '';
	InstallationType := TInstallationType.UNKNOWN;
end;

destructor TJavaInstallation.Destroy;
begin
	inherited Destroy;
end;

{
	Since TFGObjectLIst isn't made to be subclassed, these methods are a "quick and dirty" way to ensure item uniqueness.
}
function GetInstallationWithPathIdx(const Path : VString; const Installations : TFPGObjectList<TJavaInstallation>) : Integer;

var
	i : Integer;

begin
	Result := -1;
	if (Path = '') or (Installations = Nil) then Exit;

	for i := 0 to Installations.Count - 1 do begin
		if EqualStr(Installations[i].Path, Path, False) then begin
			Result := i;
			Exit;
		end;
	end;
end;

{
	Returns True if actually added.
}
function AddInstallationIfUnique(const Installation : TJavaInstallation; const Installations : TFPGObjectList<TJavaInstallation>) : Boolean;

begin
	Result := False;
	if (Installation = Nil) or (Installations = Nil) or (Installation.Path = '') then Exit;

	if GetInstallationWithPathIdx(Installation.Path, Installations) >= 0 then Exit;
	Installations.Add(Installation);
	Result := True;
end;

function InstallationPathExists(const Path : VString; const Installations : TFPGObjectList<TJavaInstallation>) : Boolean;

begin
	Result := GetInstallationWithPathIdx(Path, Installations) >= 0;
end;

function InferTypeFromPath(const Path : VString) : TInstallationType;

var
	parts : TVStringArray;
	i, first, last : Integer;
	regEx : TRegExpr;

begin
	Result := TInstallationType.UNKNOWN;
	if Path = '' then Exit;
	parts := SplitPath(Path);
	if Length(parts) < 1 then Exit;
	regEx := TRegExpr.Create('(?i)(JDK|JRE)');
	try
		first := Length(parts) - 1;
		if EqualStr('bin', parts[first], False) then Dec(first);
		if first < 0 then Exit;
		if first > 0 then last := first - 1
		else last := first;

		for i:= first downto last do begin
			if regEx.Exec(parts[i]) then begin
				if EqualStr(regEx.Match[1], 'JDK', False) then Result := TInstallationType.JDK
				else Result := TInstallationType.JRE;
				Exit;
			end;
		end;
	finally
		regEx.Free;
	end;
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

{
	Returns the number of added installations
}
function ParseAdoptiumSemeru(
	hk : HKEY;
	const samDesired : REGSAM;
	const Installations : TFPGObjectList<TJavaInstallation>;
	const Debug, DialogDebug : Boolean
) : Integer ;

var
	Installation : TJavaInstallation;
	SubKeys, SubKeys2, SubKeys3, SubKeys4 : TVStringList;
	regEx : TRegExpr;
	i, j, k, l, Version, Build : Integer;
	hk2, hk3, hk4, hk5 : HKEY;
	installationType : TInstallationType;
	s : VString;

begin
	Result := 0;
	SubKeys := EnumerateRegSubKeys(hk, Debug, DialogDebug);
	regEx := TRegExpr.Create(ModernJavaVersionRE);
	try
		for i := 0 to SubKeys.Count - 1 do begin
			if EqualStr(SubKeys[i], 'JDK', False) then installationType := TInstallationType.JDK
			else if EqualStr(SubKeys[i], 'JRE', False) then installationType := TInstallationType.JRE
			else installationType := TInstallationType.UNKNOWN;
			if installationType <> TInstallationType.UNKNOWN then begin
				hk2 := OpenRegKey(hk, SubKeys[i], samDesired, Debug, DialogDebug);
				SubKeys2 := EnumerateRegSubKeys(hk2, Debug, DialogDebug);
				try
					for j := 0 to SubKeys2.Count - 1 do begin
						regEx.InputString := SubKeys2[j];
						if (regEx.Exec) and (regEx.Match[1] <> '1') then begin
							Version := VStrToIntDef(regEx.Match[1], -1);
							Build := VStrToIntDef(regEx.Match[3], -1);
							hk3 := OpenRegKey(hk2, SubKeys2[j], samDesired, Debug, DialogDebug);
							if hk3 <> 0 then begin
								SubKeys3 := EnumerateRegSubKeys(hk3, Debug, DialogDebug);
								try
									for k := 0 to SubKeys3.Count - 1 do begin
										if EqualStr(SubKeys3[k], 'hotspot', False) or EqualStr(SubKeys3[k], 'openj9', False) then begin
											hk4 := OpenRegKey(hk3, SubKeys3[k], samDesired, Debug, DialogDebug);
											if hk4 <> 0 then begin
												SubKeys4 := EnumerateRegSubKeys(hk4, Debug, DialogDebug);
												try
													l := SubKeys4.IndexOf('MSI');
													if l >= 0 then begin
														hk5 := OpenRegKey(hk4, SubKeys4[l], samDesired, Debug, DialogDebug);
														if hk5 <> 0 then begin
															try
																s := GetRegString(hk5, 'Path', Debug, DialogDebug);
															finally
																RegCloseKey(hk5);
															end;
															if s <> '' then begin
																s := ResolveJavawPath(s);
																Installation := GetJavawInfo(s);
																if Installation <> Nil then begin
																	if (Version > 0) and (Version <> Installation.Version) then begin
																		if Debug then LogMessage(
																			'Parsed version (' + IntToVStr(Version) + ') and file version (' +
																			IntToVStr(Installation.Version) + ') differs - using parsed version'
																		);
																		if DialogDebug then NSISDialog(
																			'Parsed version (' + IntToVStr(Version) + ') and file version (' +
																			IntToVStr(Installation.Version) + ') differs - using parsed version',
																			'Warning',
																			MB_OK,
																			Warning
																		);
																		Installation.Version := Version;
																	end;
																	if (Build > -1) and (Build <> Installation.Build) then begin
																		if Debug then LogMessage(
																			'Parsed build (' + IntToVStr(Build) + ') and file build (' +
																			IntToVStr(Installation.Build) + ') differs - using parsed build'
																		);
																		if DialogDebug then NSISDialog(
																			'Parsed build (' + IntToVStr(Build) + ') and file build (' +
																			IntToVStr(Installation.Build) + ') differs - using parsed build',
																			'Warning',
																			MB_OK,
																			Warning
																		);
																		Installation.Build := Build;
																	end;
																	Installation.InstallationType := installationType;
																	Installation.Architecture := GetPEArchitecture(s);
																	if AddInstallationIfUnique(Installation, Installations) then Inc(Result)
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
		regEx.Free;
		SubKeys.Free;
	end;
end;

{
	Returns the number of added installations
}
function ParseZuluLiberica(
	hk : HKEY;
	const samDesired : REGSAM;
	const Installations : TFPGObjectList<TJavaInstallation>;
	const Debug, DialogDebug : Boolean
) : Integer;

var
	Installation : TJavaInstallation;
	SubKeys : TVStringList;
	regExZulu, regExLiberica : TRegExpr;
	i, Version : Integer;
	InstallationType : TInstallationType;
	hk2 : HKEY;
	found : Boolean;
	nQWord : TNullableQWord;
	s : VString;

begin
	Result := 0;
	SubKeys := EnumerateRegSubKeys(hk, Debug, DialogDebug);
	try
		if SubKeys.Count > 0 then begin
			regExZulu := TRegExpr.Create(ZuluRE);
			regExLiberica := TRegExpr.Create(LibericaRE);
			try
				for i := 0 to SubKeys.Count - 1 do begin
					InstallationType := TInstallationType.UNKNOWN;
					found := False;
					regExZulu.InputString := SubKeys[i];
					if regExZulu.Exec then begin
						Version := VStrToIntDef(regExZulu.Match[1], -1);
						if regExZulu.Match[2] <> '' then InstallationType := TInstallationType.JRE
						else InstallationType := TInstallationType.JDK;
						found := True;
					end
					else begin
						regExLiberica.InputString := SubKeys[i];
						if regExLiberica.Exec then begin
							Version := VStrToIntDef(regExZulu.Match[2], -1);
							if EqualStr('jre', regExLiberica.Match[1], False) then InstallationType := TInstallationType.JRE
							else if EqualStr('jdk', regExLiberica.Match[1], False) then InstallationType := TInstallationType.JDK;
							found := True;
						end;
					end;

					if found then begin
						hk2 := OpenRegKey(hk, SubKeys[i], samDesired, Debug, DialogDebug);
						if hk2 <> 0 then begin
							try
								s := GetRegString(hk2, 'InstallationPath', Debug, DialogDebug);
								if s <> '' then begin
									s := ResolveJavawPath(s);
									Installation := GetJavawInfo(s);
									if Installation <> Nil then begin
										Installation.InstallationType := InstallationType;
										nQWord := GetRegInt(hk2, 'MajorVersion', Debug, DialogDebug);
										if nQWord.Valid and (nQWord.Value > 0) then begin
											if (Version > 0) and (nQWord.Value <> Version) then begin
												if Debug then LogMessage(
													'Parsed version (' + IntToVStr(Version) + ') and registry version (' +
													IntToVStr(nQWord.Value) + ') differs - using registry version'
												);
												if DialogDebug then NSISDialog(
													'Parsed version (' + IntToVStr(Version) + ') and registry version (' +
													IntToVStr(nQWord.Value) + ') differs - using registry version',
													'Warning',
													MB_OK,
													Warning
												);
												Version := nQWord.Value;
											end;
										end;
										if (Version > 0) and (Version <> Installation.Version) then begin
											if Debug then LogMessage(
												'Parsed/registry version (' + IntToVStr(Version) + ') and file version (' +
												IntToVStr(Installation.Version) + ') differs - using parsed/registry version'
											);
											if DialogDebug then NSISDialog(
												'Parsed/registry version (' + IntToVStr(Version) + ') and file version (' +
												IntToVStr(Installation.Version) + ') differs - using parsed/registry version',
												'Warning',
												MB_OK,
												Warning
											);
											Installation.Version := Version;
										end;

										nQWord := GetRegInt(hk2, 'MinorVersion', Debug, DialogDebug);
										if nQWord.Valid and (nQWord.Value > 0) and (nQWord.Value <> Installation.Build) then begin
											if Debug then LogMessage(
												'Registry build (' + IntToVStr(nQWord.Value) + ') and file build (' +
												IntToVStr(Installation.Version) + ') differs - using registry build'
											);
											if DialogDebug then NSISDialog(
												'Registry build (' + IntToVStr(nQWord.Value) + ') and file build (' +
												IntToVStr(Installation.Version) + ') differs - using registry build',
												'Warning',
												MB_OK,
												Warning
											);
											Installation.Build := nQWord.Value;
										end;
										Installation.Architecture := GetPEArchitecture(s);
										if AddInstallationIfUnique(Installation, Installations) then Inc(Result)
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
				regExZulu.Free;
				regExLiberica.Free;
			end;
		end;
	finally
		SubKeys.Free;
	end;
end;

{
	Returns the number of added installations
}
function ParseJavaSoft(
	hk : HKEY;
	const samDesired : REGSAM;
	const Installations : TFPGObjectList<TJavaInstallation>;
	const Debug, DialogDebug : Boolean
) : Integer;

var
	Installation : TJavaInstallation;
	SubKeys, SubKeys2 : TVStringList;
	regExModern, regExLegacy, regEx : TRegExpr;
	i, j, Version, Build, idx : Integer;
	hk2, hk3 : HKEY;
	installationType : TInstallationType;
	s : VString;

begin
	Result := 0;
	SubKeys := EnumerateRegSubKeys(hk, Debug, DialogDebug);
	regExModern := TRegExpr.Create(ModernJavaVersionRE);
	regExLegacy := TRegExpr.Create(LegacyJavaVersionRE);
	try
		for i := 0 to SubKeys.Count - 1 do begin
			if EqualStr(SubKeys[i], 'JDK', False) then begin
				installationType := TInstallationType.JDK;
				regEx := regExModern;
			end
			else if EqualStr(SubKeys[i], 'JRE', False) then begin
				installationType := TInstallationType.JRE;
				regEx := regExModern;
			end
			else if EqualStr(SubKeys[i], 'Java Development Kit', False) then begin
				installationType := TInstallationType.JDK;
				regEx := regExLegacy;
			end
			else if EqualStr(SubKeys[i], 'Java Runtime Environment', False) then begin
				installationType := TInstallationType.JRE;
				regEx := regExLegacy;
			end
			else installationType := TInstallationType.UNKNOWN;
			if installationType <> TInstallationType.UNKNOWN then begin
				hk2 := OpenRegKey(hk, SubKeys[i], samDesired, Debug, DialogDebug);
				SubKeys2 := EnumerateRegSubKeys(hk2, Debug, DialogDebug);
				try
					for j := 0 to SubKeys2.Count - 1 do begin
						regEx.InputString := SubKeys2[j];
						if regEx.Exec then begin
							Version := VStrToIntDef(regEx.Match[1], -1);
							if regEx.Match[3] <> '' then Build := VStrToIntDef(regEx.Match[3], -1)
							else Build := -1;
							hk3 := OpenRegKey(hk2, SubKeys2[j], samDesired, Debug, DialogDebug);
							if hk3 <> 0 then begin
								try
									s := GetRegString(hk3, 'JavaHome', Debug, DialogDebug);
									if s <> '' then begin
										s := ResolveJavawPath(s);
										Installation := GetJavawInfo(s);
										if Installation <> Nil then begin
											if (Version > 0) and (Version <> Installation.Version) then begin
												if Debug then LogMessage(
													'Parsed version (' + IntToVStr(Version) + ') and file version (' +
													IntToVStr(Installation.Version) + ') differs - using parsed version'
												);
												if DialogDebug then NSISDialog(
													'Parsed version (' + IntToVStr(Version) + ') and file version (' +
													IntToVStr(Installation.Version) + ') differs - using parsed version',
													'Warning',
													MB_OK,
													Warning
												);
												Installation.Version := Version;
											end;
											if (Build > -1) and (Build <> Installation.Build) then begin
												if Debug then LogMessage(
													'Parsed build (' + IntToVStr(Build) + ') and file build (' +
													IntToVStr(Installation.Build) + ') differs - using parsed build'
												);
												if DialogDebug then NSISDialog(
													'Parsed build (' + IntToVStr(Build) + ') and file build (' +
													IntToVStr(Installation.Build) + ') differs - using parsed build',
													'Warning',
													MB_OK,
													Warning
												);
												Installation.Build := Build;
											end;
											Installation.InstallationType := installationType;
											Installation.Architecture := GetPEArchitecture(s);
											idx := GetInstallationWithPathIdx(s, Installations);
											if idx > -1 then begin
												if Installation.CalcScore > Installations[idx].CalcScore then begin
													Installations.Delete(idx);
													Installations.Add(Installation);
													Inc(Result);
												end
												else Installation.Free;
											end
											else begin
												Installations.Add(Installation);
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
		regExModern.Free;
		regExLegacy.Free;
		SubKeys.Free;
	end;
end;

procedure ProcessRegistry(const Is64 : Boolean; const Params : TParameters);

const
	baseSamDesired = KEY_READ or KEY_QUERY_VALUE or KEY_ENUMERATE_SUB_KEYS;

var
	h, rootKey : HKEY;
	run : Integer = 0;
	samDesired : REGSAM = baseSamDesired;
	subKey : VString;
	Installations : TFPGObjectList<TJavaInstallation>;

begin
	Installations := TFPGObjectList<TJavaInstallation>.Create(True);
	repeat
		if (run = 0) or (run = 2) then rootKey :=  HKEY_LOCAL_MACHINE
		else rootKey := HKEY_CURRENT_USER;
		if is64 then begin
			if run > 1 then samDesired := baseSamDesired or KEY_WOW64_32KEY
			else samDesired := baseSamDesired or KEY_WOW64_64KEY;
		end;

		for subKey in Params.RegistryPaths do begin
			h := OpenRegKey(rootKey, subKey, samDesired, Params.IsLogging, Params.IsDialogDebug);
			if h <> 0 then begin
				try
					if ParseAdoptiumSemeru(h, samDesired, Installations, Params.IsLogging, Params.IsDialogDebug) < 1 then begin
						if ParseZuluLiberica(h, samDesired, Installations, Params.IsLogging, Params.IsDialogDebug) < 1 then begin
							ParseJavaSoft(h, samDesired, Installations, Params.IsLogging, Params.IsDialogDebug);
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

procedure ProcessEnvironmentVariables(const Params : TParameters);

var
	Installation : TJavaInstallation;
	Installations : TFPGObjectList<TJavaInstallation>;
	InstallationType : TInstallationType;
	envVar, s : VString;

begin
	Installations := TFPGObjectList<TJavaInstallation>.Create(True);
	for envVar in Params.EnvironmentVariables do begin
		s := ExpandEnvStrings(envVar);
		if s <> envVar then begin
			InstallationType := InferTypeFromPath(s);
			s := ResolveJavawPath(s);
			Installation := GetJavawInfo(s);
			if Installation <> Nil then begin
				Installation.InstallationType := InstallationType;
				AddInstallationIfUnique(Installation, Installations);
			end;
		end;
	end;
end;

procedure ProcessOSPath;

var
	Installation : TJavaInstallation;
	PathElements : TVStringArray;
	Installations : TFPGObjectList<TJavaInstallation>;
	Element, s : VString;

begin
	Installations := TFPGObjectList<TJavaInstallation>.Create(True);
	s := ExpandEnvStrings('%PATH%');
	if s = '%PATH%' then Exit;
	PathElements := SplitStr(s, [';']);
	if PathElements = Nil then Exit;
	for Element in PathElements do begin
		s := ResolveJavawPath(Element);
		Installation := GetJavawInfo(s);
		if Installation <> Nil then begin
			Installation.InstallationType := InferTypeFromPath(Element);
			if not AddInstallationIfUnique(Installation, Installations) then Installation.Free;
		end;
	end;
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

var
	parameterList : TVStringList;
	i : Integer;

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

begin
	Init(hwndParent, string_size, variables, stacktop);
	parameters := TParameters.Create();
	parameters.ParseParams();
	ProcessRegistry(IsWOW64, parameters);
	ProcessEnvironmentVariables(parameters);
	ProcessOSPath();
end;

exports Locate;

end.
