unit Core;
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

{$mode Delphi}
{$interfaces corba}

interface

uses
	Classes, Windows, SysUtils, Utils, RegExpr, fgl;

type

	{ TSettings }

	TSettings = interface
		function GetRegistryPaths() : TVStringList;
		function GetEnvironmentVariables() : TVStringList;
		function GetFilePaths() : TVStringList;
		function GetFilteredPaths() : TVStringList;
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
		function CalcScore() : Integer;
		constructor Create();
		destructor Destroy(); override;
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
		function ResolveJavawPath(const Path : VString) : VString;
		function ParseAdoptiumSemeru(hk : HKEY; const samDesired : REGSAM) : Integer;
		function ParseJavaSoft(hk : HKEY; const samDesired : REGSAM) : Integer;
		function ParseZuluLiberica(hk : HKEY; const samDesired : REGSAM) : Integer;
		procedure ProcessEnvironmentVariables();
		procedure ProcessFilePaths();
		procedure ProcessFilteredPaths();
		procedure ProcessOSPath();
		procedure ProcessRegistry(const Is64 : Boolean);
	public
		procedure Process();
		constructor Create(const Settings : TSettings; const Logger : TLogger);
		destructor Destroy(); override;
	published
		property Installations : TFPGObjectList<TJavaInstallation> read GetInstallations;
	end;

function GetJavawInfo(Path : VString) : TJavaInstallation;
{
	TFGObjectList "helper" methods
	Since TFGObjectLIst isn't made to be subclassed, these methods are a "quick and dirty" way to ensure item uniqueness.
}
function GetInstallationWithPathIdx(
	const Path : VString;
	const Installations : TFPGObjectList<TJavaInstallation>
) : Integer;
function AddInstallationIfUnique(
	const Installation : TJavaInstallation;
	const Installations : TFPGObjectList<TJavaInstallation>
) : Boolean;
function InstallationPathExists(
	const Path : VString;
	const Installations : TFPGObjectList<TJavaInstallation>
) : Boolean;

implementation

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
function TJavaInstallation.CalcScore() : Integer;
begin
	Result := 0;
	if Path <> '' then Inc(Result, 5);
	if Version > 0 then Inc(Result);
	if Build > -1 then Inc(Result);
	if InstallationType <> TInstallationType.UNKNOWN then Inc(Result);
	if Architecture <> TArchitecture.UNKNOWN then Inc(Result);
end;

constructor TJavaInstallation.Create();
begin
	Version := -1;
	Build := -1;
	Path := '';
	InstallationType := TInstallationType.UNKNOWN;
end;

destructor TJavaInstallation.Destroy();
begin
	inherited Destroy;
end;

{ TParser }

function TParser.GetInstallations() : TFPGObjectList<TJavaInstallation>;
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

function TParser.ResolveJavawPath(const Path : VString) : VString;

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

procedure TParser.ProcessEnvironmentVariables();

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

procedure TParser.ProcessFilePaths();

var
	Installation : TJavaInstallation;
	InstallationType : TInstallationType;
	FilePath, s : VString;

begin
	for FilePath in FSettings.GetFilePaths do begin
		InstallationType := InferTypeFromPath(FilePath);
		s := ResolveJavawPath(FilePath);
		Installation := GetJavawInfo(s);
		if Installation <> Nil then begin
			Installation.InstallationType := InstallationType;
			AddInstallationIfUnique(Installation, FInstallations);
		end;
	end;
end;

procedure TParser.ProcessFilteredPaths();

var
	FilteredPaths : TVStringList;
	i : Integer;
	s, curPath : VString;

begin
	FilteredPaths := FSettings.GetFilteredPaths;
	if (FilteredPaths = Nil) or (FilteredPaths.Count = 0) then Exit;

	i := 0;
	while i < FInstallations.Count do begin
		curPath := FInstallations[i].Path;
		for s in FilteredPaths do begin
			if StartsWith(s, curPath, False) then begin
				if FLogger.IsDebug() then FLogger.Log('Filtered out installation: ' + curPath, TLogLevel.DEBUG);
				FInstallations.Delete(i);
				Dec(i);
				Break;
			end;
		end;
		Inc(i);
	end;
end;

procedure TParser.ProcessOSPath();

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
	ProcessOSPath();
	ProcessFilePaths();
	ProcessFilteredPaths();

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
	TFGObjectList "helper" methods
	Since TFGObjectLIst isn't made to be subclassed, these methods are a "quick and dirty" way to ensure item uniqueness.
}

function GetInstallationWithPathIdx(
	const Path : VString;
	const Installations : TFPGObjectList<TJavaInstallation>
) : Integer;

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
function AddInstallationIfUnique(
	const Installation : TJavaInstallation;
	const Installations : TFPGObjectList<TJavaInstallation>
) : Boolean;

begin
	Result := False;
	if (Installation = Nil) or (Installations = Nil) or (Installation.Path = '') then Exit;

	if GetInstallationWithPathIdx(Installation.Path, Installations) >= 0 then Exit;
	Installations.Add(Installation);
	Result := True;
end;

function InstallationPathExists(
	const Path : VString;
	const Installations : TFPGObjectList<TJavaInstallation>
) : Boolean;

begin
	Result := GetInstallationWithPathIdx(Path, Installations) >= 0;
end;


end.
