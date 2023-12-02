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
{$SCOPEDENUMS ON}
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
	NSIS in 'NSIS.pas';

type
	TNSISTStringList = class(TFPGList<NSISTString>);
	TInstallationType = (JDK, JRE, UNKNOWN);
	TArchitecture = (UNKNOWN, x86, x64, ia64);

	{ TParameters }

	TParameters = class(TObject)
	private
		FRegistryPaths : TNSISTStringList;
		FFilePaths : TNSISTStringList;
		FIsLogging : Boolean;
		FIsDialogDebug : Boolean;
		function ReadParams() : TNSISTStringList;
		function GetLogging() : Boolean;
		function GetDialogDebug() : Boolean;
	public
		function GetRegistryPaths() : TNSISTStringList;
		function GetFilePaths() : TNSISTStringList;
		procedure ParseParams();
		constructor Create();
		destructor Destroy(); override;
	published
		property RegistryPaths : TNSISTStringList read GetRegistryPaths;
		property Filepaths : TNSISTStringList read GetFilePaths;
		property IsLogging : Boolean read GetLogging;
		property IsDialogDebug : Boolean read GetDialogDebug;
	end;

	{ TJavaInstallation }

	TJavaInstallation = class(TObject)
	public
		Version : Integer;
		Build : Integer;
		Path : NSISTString;
		InstallationType : TInstallationType;
		Architecture : TArchitecture;
		Optimal : Boolean;
		function Equals(Obj : TJavaInstallation) : boolean; overload;
		function CalcScore : Integer;
		constructor Create;
		destructor Destroy; override;
	end;

	TFileInfo = record
		Valid : Boolean;
		FileVersionMajor : Word;
		FileVersionMinor : Word;
		FileVersionRevision : Word;
		FileVersionBuild : Word;
		ProductVersionMajor : Word;
		ProductVersionMinor : Word;
		ProductVersionRevision : Word;
		ProductVersionBuild : Word;
	end;

	TNullableQWord = record
		Valid : Boolean;
		Value : QWord;
	end;

function IntToNStr(Value : QWord) : NSISTString; overload;
begin
	Result := NSISTString(IntToStr(Value));
end;

function IntToNStr(Value : Int64) : NSISTString; overload;
begin
	Result := NSISTString(IntToStr(Value));
end;

function IntToNStr(Value : LongInt) : NSISTString; overload;
begin
	Result := NSISTString(IntToStr(Value));
end;

function UIntToNStr(Value : QWord) : NSISTString; overload;
begin
	Result := NSISTString(UIntToStr(Value));
end;

function UIntToNStr(Value : Cardinal) : NSISTString; overload;
begin
	Result := NSISTString(UIntToStr(Value));
end;

function NStrToIntDef(const ns : NSISTString; Default : LongInt) : LongInt;

var
	Error : word;

begin
	Val(ns, Result, Error);
	if Error <> 0 then Result := Default;
end;

function EqualStr(str1, str2 : NSISTString; CaseSensitive : Boolean = true) : Boolean;

var
	len, i : Integer;

begin
	Result := False;
	len := Length(str2);
	if len <> Length(str1) then Exit;
	if len = 0 then begin
		Result := True;
		Exit;
	end;
	if CaseSensitive then begin
		for i := 1 to len do if str2[i] <> str1[i] then Exit;
		Result := true;
	end
	else begin
		UniqueString(str1);
		UniqueString(str2);
{$IFDEF UNICODE}
		Result := lstrcmpiW(LPCWSTR(str2), LPCWSTR(str1)) = 0;
{$ELSE}
		Result := lstrcmpiA(LPCSTR(str2), LPCSTR(str1)) = 0;
{$ENDIF}
	end;
end;

function EndsWith(subStr : NSISTString; Const str : NSISTString; CaseSensitive : Boolean = true) : Boolean;

var
	subLen, len, offset, i : Integer;
	endStr : NSISTString;

begin
	Result := False;
	subLen := Length(subStr);
	len := Length(str);
	if (subLen = 0) or (len = 0) or (len < subLen) then Exit;
	if CaseSensitive then begin
		offset := len - subLen;
		for i := 1 to subLen do if str[offset + i] <> subStr[i] then Exit;
		Result := true;
	end
	else begin
		UniqueString(subStr);
		endStr := Copy(str, len - subLen + 1, subLen);
{$IFDEF UNICODE}
		Result := lstrcmpiW(LPCWSTR(endStr), LPCWSTR(subStr)) = 0;
{$ELSE}
		Result := lstrcmpiA(LPCSTR(endStr), LPCSTR(subStr)) = 0;
{$ENDIF}
	end;
end;

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

function InstallationTypeToStr(Const installationType : TInstallationType) : NSISTString;
begin
	case installationType of
		TInstallationType.JDK : Result := NSISTString('JDK');
		TInstallationType.JRE : Result := NSISTString('JRE');
	else Result := NSISTString('Unknown');
	end;
end;

function ArchitectureToStr(Const Architecture : TArchitecture; const BitsOnly : Boolean) : NSISTString;
begin
	if BitsOnly then begin
		case Architecture of
			TArchitecture.ia64 : Result := NSISTString('64');
			TArchitecture.x64 : Result := NSISTString('64');
			TArchitecture.x86 : Result := NSISTString('32');
		else Result := NSISTString('');
		end;
	end
	else begin
		case Architecture of
			TArchitecture.ia64 : Result := NSISTString('ia64');
			TArchitecture.x64 : Result := NSISTString('x64');
			TArchitecture.x86 : Result := NSISTString('x86');
		else Result := NSISTString('Unknown');
		end;
	end;
end;

function SystemErrorToStr(MessageId : DWORD) : NSISTString;

var
	len, newLen : DWORD;
{$IFDEF UNICODE}
	lpBuffer : LPWSTR;
{$ELSE}
	lpBuffer : LPSTR;
{$ENDIF}

begin
	Result := '';
{$IFDEF UNICODE}
	len := FormatMessageW(
		FORMAT_MESSAGE_ALLOCATE_BUFFER or FORMAT_MESSAGE_FROM_SYSTEM or FORMAT_MESSAGE_IGNORE_INSERTS,
		Nil,
		MessageId,
		MAKELANGID(LANG_NEUTRAL, SUBLANG_DEFAULT),
		PWideChar(@lpBuffer),
		0,
		Nil
	);
{$ELSE}
	len := FormatMessageA(
		FORMAT_MESSAGE_ALLOCATE_BUFFER or FORMAT_MESSAGE_FROM_SYSTEM or FORMAT_MESSAGE_IGNORE_INSERTS,
		Nil,
		MessageId,
		MAKELANGID(LANG_NEUTRAL, SUBLANG_DEFAULT),
		PChar(@lpBuffer),
		0,
		Nil
	);
{$ENDIF}
	if len > 0 then begin
		Result := lpBuffer;

		// Remove trailing newlines
		newLen := len;
		if (newLen > 1) and (Result[newLen - 1] = #13) and (Result[len] = #10) then
			Dec(newLen, 2);
		SetLength(Result, newLen);
	end;
	LocalFree(HLOCAL(lpBuffer));
end;

function IsWOW64 : Boolean;

var
	module : HModule;
	s : RawByteString;
	ptr : FARPROC;
	res : BOOL;

begin
	Result := False;
	s := 'kernel32';
	module := GetModuleHandleA(PChar(s));
	s := 'IsWow64Process';
	ptr := GetProcAddress(module, PChar(s));
	if @ptr <> Nil then begin
		// IsWow64Process exists, so we're potentially running on 64-bit
		if IsWow64Process(GetCurrentProcess, @res) then Result := res
		else NSISDialog('Failed to query IsWow64Process', 'Error', MB_OK);
	end;
end;

function OpenRegKey(Const rootKey : HKEY; Const subKey : NSISTString; samDesired : REGSAM; Const Debug, DialogDebug : Boolean) : HKEY;

var
	retVal : LongInt;
	ErrorMsg : NSISTString;

begin
	if rootKey = 0 then begin
		Result := 0;
		Exit;
	end;
{$IFDEF UNICODE}
	retVal := RegOpenKeyExW(rootKey, LPWSTR(subKey), 0, samDesired, @Result);
{$ELSE}
	retVal := RegOpenKeyExA(rootKey, LPCSTR(subKey), 0, samDesired, @Result);
{$ENDIF}

	if retVal <> ERROR_SUCCESS then begin
		Result := 0;
		if (retVal <> ERROR_FILE_NOT_FOUND) and (Debug or DialogDebug) then begin
			ErrorMsg := SystemErrorToStr(retVal);
			if Debug then LogMessage('Failed to open registry key "' + subkey + '" because: ' + ErrorMsg);
			if DialogDebug then NSISDialog(
				'Failed to open registry key "' + subkey + '" because: ' + ErrorMsg,
				'Error',
				MB_OK,
				Error
			);
		end;
	end;
end;

{$WARN 5058 off : Variable "$1" does not seem to be initialized}
{$WARN 5060 off : Function result variable does not seem to be initialized}
function GetRegInt(Const key : HKEY; Const valueName : NSISTString; Const Debug, DialogDebug : Boolean) : TNullableQWord;

var
	retVal : LONG;
	dataType : DWORD;
	ErrorMsg : NSISTString;
	cbData : DWORD = 8;
	data : array[0..7] of Byte;

begin
	FillChar(Result, SizeOf(Result), 0);
	if key = 0 then Exit;
{$IFDEF UNICODE}
	retVal := RegQueryValueExW(key, LPWSTR(valueName), Nil, @dataType, @data, @cbData);
{$ELSE}
	retVal := RegQueryValueExA(key, LPCSTR(valueName), Nil, @dataType, @data, @cbData);
{$ENDIF}
	if retVal = ERROR_SUCCESS then begin
		if (cbData > 0) and ((dataType = REG_DWORD) or (dataType = REG_DWORD_BIG_ENDIAN) or (dataType = REG_QWORD)) then begin
			if (dataType = REG_QWORD) and (cbData = 8) then begin
				Result.Value := PQWord(@data)^;
				Result.Valid := True;
			end
			else if cbData = 4 then begin
				if dataType = REG_DWORD_BIG_ENDIAN then Result.Value := SwapEndian(PDWORD(@data)^)
				else Result.Value := PDWORD(@data)^;
				Result.Valid := True;
			end;
		end;
	end
	else begin
		if (retVal <> ERROR_FILE_NOT_FOUND) and (Debug or DialogDebug) then begin
			ErrorMsg := SystemErrorToStr(retVal);
			if Debug then LogMessage('Failed to get registry value "' + valueName + '" because: ' + ErrorMsg);
			if DialogDebug then NSISDialog(
				'Failed to get registry value "' + valueName + '" because: ' + ErrorMsg,
				'Error',
				MB_OK,
				Error
			);
		end;
	end;
end;
{$WARN 5058 on : Variable "$1" does not seem to be initialized}
{$WARN 5060 on : Function result variable does not seem to be initialized}

function GetRegString(const key : HKEY; const valueName : NSISTString; const Debug, DialogDebug : Boolean) : NSISTString;
var
	retVal : LONG;
	dataType : DWORD;
	ErrorMsg : NSISTString;
{$IFDEF UNICODE}
	cbData : DWORD = 2050;
	data : array[0..1024] of WideChar;
{$ELSE}
	cbData : DWORD = 1025;
	data : array[0..1024] of Char;
{$ENDIF}

begin
	Result := '';
	if key = 0 then Exit;
{$IFDEF UNICODE}
	retVal := RegQueryValueExW(key, LPWSTR(valueName), Nil, @dataType, @data, @cbData);
{$ELSE}
	retVal := RegQueryValueExA(key, LPCSTR(valueName), Nil, @dataType, @data, @cbData);
{$ENDIF}
	if retVal = ERROR_SUCCESS then begin
		if (dataType = REG_SZ) and (cbData > 0) then begin
{$IFDEF UNICODE}
			if (cbData > 1) and (data[(cbData div 2) - 1] <> WideChar(#0)) then begin
				if cbData > 2048 then begin
					data[1024] := WideChar(#0);
					cbData := 2050;
				end
				else data[cbData div 2] := WideChar(#0);
			end;
			Result := PWideChar(data);
{$ELSE}
			if data[cbData - 1] <> #0 then begin
				if cbData > 1024 then begin
					data[1024] := #0;
					cbData := 1025;
				end
				else data[cbData] := #0;
				Result := PChar(data);
			end;
{$ENDIF}
		end;
	end
	else begin
		if (retVal <> ERROR_FILE_NOT_FOUND) and (Debug or DialogDebug) then begin
			ErrorMsg := SystemErrorToStr(retVal);
			if Debug then LogMessage('Failed to get registry value "' + valueName + '" because: ' + ErrorMsg);
			if DialogDebug then NSISDialog(
				'Failed to get registry value "' + valueName + '" because: ' + ErrorMsg,
				'Error',
				MB_OK,
				Error
			);
		end;
	end;
end;

function EnumerateRegSubKeys(const key : HKEY; Const Debug, DialogDebug : Boolean) : TNSISTStringList;

var
	subKeys : DWORD = 0;
	lpcchName : DWORD;
	retVal : LONG;
	ErrorMsg : NSISTString;
	i : Integer;
{$IFDEF UNICODE}
	lpName : PWideChar;
{$ELSE}
	lpName : PChar;
{$ENDIF}

begin
	Result := TNSISTStringList.Create;
	if key = 0 then Exit;
	retVal := RegQueryInfoKeyA(key, Nil, Nil, Nil, @subKeys, Nil, Nil, Nil, Nil, Nil, Nil, Nil);
	if retVal <> ERROR_SUCCESS then begin
		if Debug or DialogDebug then begin
			ErrorMsg := SystemErrorToStr(retVal);
			if Debug then LogMessage('Failed to enumerate registry sub keys: ' + ErrorMsg);
			if DialogDebug then NSISDialog('Failed to enumerate registry sub keys: ' + ErrorMsg, 'Error', MB_OK, Error);
		end;
	end
	else if (subKeys > 0) then begin
{$IFDEF UNICODE}
		lpName :=  WideStrAlloc(255);
{$ELSE}
		lpName := StrAlloc(255);
{$ENDIF}
		for i := 0 to subKeys - 1 do begin
			lpcchName := 255;
{$IFDEF UNICODE}
			retVal := RegEnumKeyExW(key, i, PUnicodeChar(lpName), lpcchName, Nil, Nil, Nil, Nil);
			if retVal = ERROR_SUCCESS then begin
				Result.Add(lpName);
			end
{$ELSE}
			retVal := RegEnumKeyExA(key, i, PChar(lpName), lpcchName, Nil, Nil, Nil, Nil);
			if retVal = ERROR_SUCCESS then begin
				Result.Add(lpName);
			end
{$ENDIF}
			else if retVal = ERROR_NO_MORE_ITEMS then break
			else begin
				if Debug or DialogDebug then begin
					ErrorMsg := SystemErrorToStr(retVal);
					if Debug then LogMessage('Failed to retrieve registry sub key name: ' + ErrorMsg);
					if DialogDebug then NSISDialog('Failed to retrieve registry sub key name: ' + ErrorMsg, 'Error', MB_OK, Error);
				end;
			end;
		end;
		StrDispose(lpName);
	end;
end;

function GetFileInfo(Path : NSISTString) : TFileInfo;

var
	size, dwHandle, valueSize : DWORD;
	buffer : Pointer;
	value : PVSFixedFileInfo;

begin
{$WARN 5060 off : Function result variable does not seem to be initialized}
	FillChar(Result, sizeof(Result), 0);
{$WARN 5060 on : Function result variable does not seem to be initialized}
	UniqueString(Path);
{$IFDEF UNICODE}
	size := GetFileVersionInfoSizeW(LPWSTR(Path), @dwHandle);
{$ELSE}
	size := GetFileVersionInfoSizeA(LPCSTR(Path), @dwHandle);
{$ENDIF}
	if size = 0 then Exit;
	GetMem(buffer, size);
	try
{$IFDEF UNICODE}
		if GetFileVersionInfoW(PWideChar(Path), dwHandle, size, buffer) then
{$ELSE}
		if GetFileVersionInfoA(PChar(Path), dwHandle, size, buffer) then
{$ENDIF}
		begin
{$WARN 5057 off : Local variable "$1" does not seem to be initialized}
			if VerQueryValueA(buffer, '\', value, valueSize) then begin
{$WARN 5057 on : Local variable "$1" does not seem to be initialized}
				Result.FileVersionMajor := (value^.dwFileVersionMS and $ffff0000) shr 16;
				Result.FileVersionMinor := value^.dwFileVersionMS and $ffff;
				Result.FileVersionRevision := (value^.dwFileVersionLS and $ffff0000) shr 16;
				Result.FileVersionBuild := value^.dwFileVersionLS and $ffff;
				Result.ProductVersionMajor := (value^.dwProductVersionMS and $ffff0000) shr 16;
				Result.ProductVersionMinor := value^.dwProductVersionMS and $ffff;
				Result.ProductVersionRevision := (value^.dwProductVersionLS and $ffff0000) shr 16;
				Result.ProductVersionBuild := value^.dwProductVersionLS and $ffff;
				Result.Valid := True;
			end;
		end;
	finally
		Freemem(buffer);
	end;
end;

function ResolveJavawPath(Const Path : NSISTString) : NSISTString;

begin
	Result := Path;
	if Path = '' then Exit;

	if not EndsWith(NSISTString('javaw.exe'), Result, False) then begin
		if EndsWith('bin', Result, False) then Result := Result + '\'
		else if not EndsWith('bin\', Result, False) then begin
			if EndsWith('\', Result, True) then Result := Result + 'bin\'
			else Result := Result + '\bin\';
		end;
		Result := Result + 'javaw.exe';
	end;
end;

function GetPEArchitecture(Path: NSISTString) : TArchitecture;

var
	h : HANDLE;
	buffer : array[0..63] of Byte;
	read : DWORD;
	offset : PDWORD;
	machineType : PWORD;

begin
	Result := TArchitecture.UNKNOWN;
	if Path = '' then Exit;
	UniqueString(Path);
{$IFDEF UNICODE}
	h := CreateFileW(PWideChar(Path), DWORD(GENERIC_READ), FILE_SHARE_READ, Nil, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, 0);
{$ELSE}
	h := CreateFileA(PChar(Path), DWORD(GENERIC_READ), FILE_SHARE_READ, Nil, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, 0);
{$ENDIF}
	if h = INVALID_HANDLE_VALUE then Exit;
	try
{$WARN 5057 off : Local variable "$1" does not seem to be initialized}
		if not ReadFile(h, buffer, 64, read, Nil) then Exit; // Read error
{$WARN 5057 on : Local variable "$1" does not seem to be initialized}
		if read < 64 then Exit; // To small file
		if (buffer[0] <> $4D) or (buffer[1] <> $5A) then Exit; // Missing the "MZ" magic bytes
		offset := Pointer(@buffer) + $3C;
		if offset^ < $40 then Exit; // Not the offset we're expecting
		read := SetFilePointer(h, offset^, Nil, FILE_BEGIN);
		if read = INVALID_SET_FILE_POINTER then Exit; // Seek failed
		if not ReadFile(h, buffer, 6, read, Nil) then Exit; // Read error
		if (buffer[0] <> 80) or (buffer[1] <> 69) or (buffer[2] <> 0) or (buffer[3] <> 0) then Exit; // Not a PE file
		machineType := Pointer(@buffer) + 4;
		case machineType^ of
			$014C: Result := TArchitecture.x86; //x86 (32-bit)
			$200: Result := TArchitecture.ia64; //Intel Itanium (64-bit)
			$8664: Result := TArchitecture.x64; //x64 (64-bit)
		end;
	finally
		CloseHandle(h);
	end;
end;

{
	Creates a TJavaInstallation instance if a valid result is found.
	IE, Result must be Free'd if it's non-nil upon return.
}
function GetJavawInfo(Path : NSISTString) : TJavaInstallation;

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

function ParseAdoptiumSemeru(hk : HKEY; Const samDesired : REGSAM; Const Debug, DialogDebug : Boolean) : TJavaInstallation;

const
	ModernJavaVersionRE = '\s*(\d+)\.(\d+)\.(\d+).*';

var
	SubKeys, SubKeys2, SubKeys3, SubKeys4 : TNSISTStringList;
	regEx : TRegExpr;
	i, j, k, l, Version, Build : Integer;
	hk2, hk3, hk4, hk5 : HKEY;
	installationType : TInstallationType;
	s : NSISTString;

begin
	Result := Nil;
	SubKeys := EnumerateRegSubKeys(hk, Debug, DialogDebug);
	regEx := TRegExpr.Create;
	try
		regEx.Expression := ModernJavaVersionRE;
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
							Version := NStrToIntDef(regEx.Match[1], -1);
							Build := NStrToIntDef(regEx.Match[3], -1);
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
																Result := GetJavawInfo(s);
															end;
															if Result <> Nil then begin
																if (Version > 0) and (Version <> Result.Version) then begin
																	if Debug then LogMessage(
																		'Parsed version (' + IntToNStr(Version) + ') and file version (' +
																		IntToNStr(Result.Version) + ') differs - using parsed version'
																	);
																	if DialogDebug then NSISDialog(
																		'Parsed version (' + IntToNStr(Version) + ') and file version (' +
																		IntToNStr(Result.Version) + ') differs - using parsed version',
																		'Warning',
																		MB_OK,
																		Warning
																	);
																	Result.Version := Version;
																end;
																if (Build > -1) and (Build <> Result.Build) then begin
																	if Debug then LogMessage(
																		'Parsed build (' + IntToNStr(Version) + ') and file build (' +
																		IntToNStr(Result.Version) + ') differs - using parsed build'
																	);
																	if DialogDebug then NSISDialog(
																		'Parsed build (' + IntToNStr(Version) + ') and file build (' +
																		IntToNStr(Result.Version) + ') differs - using parsed build',
																		'Warning',
																		MB_OK,
																		Warning
																	);
																	Result.Build := Build;
																end;
																Result.InstallationType := installationType;
																Result.Architecture := GetPEArchitecture(s);
																Exit;
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

function ParseZuluLiberica(hk : HKEY; Const samDesired : REGSAM; Const Debug, DialogDebug : Boolean) : TJavaInstallation;

const
	ZuluRE = '(?i)\s*zulu-(\d+)(?:-(jre))\s*';
	LibericaRE = '(?i)\s*(jre|jdk)-(\d+)\s*';

var
	SubKeys : TNSISTStringList;
	regExZulu, regExLiberica : TRegExpr;
	i, Version : Integer;
	InstallationType : TInstallationType;
	hk2 : HKEY;
	found : Boolean;
	nQWord : TNullableQWord;
	s : NSISTString;

begin
	Result := Nil;
	SubKeys := EnumerateRegSubKeys(hk, Debug, DialogDebug);
	try
		if SubKeys.Count > 0 then begin
			regExZulu := TRegExpr.Create;
			regExLiberica := TRegExpr.Create;
			try
				regExZulu.Expression := ZuluRE;
				regExLiberica.Expression := LibericaRE;
				for i := 0 to SubKeys.Count - 1 do begin
					InstallationType := TInstallationType.UNKNOWN;
					found := False;
					regExZulu.InputString := SubKeys[i];
					if regExZulu.Exec then begin
						Version := NStrToIntDef(regExZulu.Match[1], -1);
						if regExZulu.Match[2] <> '' then InstallationType := TInstallationType.JRE
						else InstallationType := TInstallationType.JDK;
						found := True;
					end
					else begin
						regExLiberica.InputString := SubKeys[i];
						if regExLiberica.Exec then begin
							Version := NStrToIntDef(regExZulu.Match[2], -1);
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
									Result := GetJavawInfo(s);
								end;
								if Result <> Nil then begin
									Result.InstallationType := InstallationType;
									nQWord := GetRegInt(hk2, 'MajorVersion', Debug, DialogDebug);
									if nQWord.Valid and (nQWord.Value > 0) then begin
										if (Version > 0) and (nQWord.Value <> Version) then begin
											if Debug then LogMessage(
												'Parsed version (' + IntToNStr(Version) + ') and registry version (' +
												IntToNStr(nQWord.Value) + ') differs - using registry version'
											);
											if DialogDebug then NSISDialog(
												'Parsed version (' + IntToNStr(Version) + ') and registry version (' +
												IntToNStr(nQWord.Value) + ') differs - using registry version',
												'Warning',
												MB_OK,
												Warning
											);
											Version := nQWord.Value;
										end;
									end;
									if (Version > 0) and (Version <> Result.Version) then begin
										if Debug then LogMessage(
											'Parsed/registry version (' + IntToNStr(Version) + ') and file version (' +
											IntToNStr(Result.Version) + ') differs - using parsed/registry version'
										);
										if DialogDebug then NSISDialog(
											'Parsed/registry version (' + IntToNStr(Version) + ') and file version (' +
											IntToNStr(Result.Version) + ') differs - using parsed/registry version',
											'Warning',
											MB_OK,
											Warning
										);
										Result.Version := Version;
									end;

									nQWord := GetRegInt(hk2, 'MinorVersion', Debug, DialogDebug);
									if nQWord.Valid and (nQWord.Value > 0) and (nQWord.Value <> Result.Build) then begin
										if Debug then LogMessage(
											'Registry build (' + IntToNStr(nQWord.Value) + ') and file build (' +
											IntToNStr(Result.Version) + ') differs - using registry build'
										);
										if DialogDebug then NSISDialog(
											'Registry build (' + IntToNStr(nQWord.Value) + ') and file build (' +
											IntToNStr(Result.Version) + ') differs - using registry build',
											'Warning',
											MB_OK,
											Warning
										);
										Result.Build := nQWord.Value;
									end;
									Result.Architecture := GetPEArchitecture(s);
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

procedure ProcessRegistry(const Is64 : Boolean; const Params : TParameters);

const
	baseSamDesired = KEY_READ or KEY_QUERY_VALUE or KEY_ENUMERATE_SUB_KEYS;

var
	h, rootKey : HKEY;
	run : Integer = 0;
	samDesired : REGSAM = baseSamDesired;
	subKey : NSISTString;
	Installation : TJavaInstallation;

begin
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
					Installation := ParseAdoptiumSemeru(h, samDesired, Params.IsLogging, Params.IsDialogDebug);
					if Installation = Nil then Installation := ParseZuluLiberica(h, samDesired, Params.IsLogging, Params.IsDialogDebug);
					RegCloseKey(h);
					if Installation <> Nil then
					begin
					end;
				finally
				end;
			end;
		end;
		Inc(run);
	until ((not Is64) and (run > 1)) or (run > 3);
end;

function TParameters.GetRegistryPaths() : TNSISTStringList;
begin
	Result := FRegistryPaths;
end;

function TParameters.GetFilePaths() : TNSISTStringList;
begin
	Result := FFilePaths;
end;

function TParameters.ReadParams() : TNSISTStringList;
var
	parameter : NSISTString;
begin
	Result := TNSISTStringList.Create;
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
	poLog = '/LOG';
	poDialogDebug = '/DIALOGDEBUG';

var
	parameterList : TNSISTStringList;
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
				FRegistryPaths.Add(parameterList[i + 1]);
				Inc(i);
			end
			else begin
				NSISDialog('Invalid option "' + parameterList[i] + '"', 'Error', MB_OK, TDialaogIcon.Error);
			end;
		end
		else begin
			FFilePaths.Add(parameterList[i]);
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
	StandardRegPaths : array [0..5] of NSISTString = (
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
	FRegistryPaths := TNSISTStringList.Create();
	for i := 0 to high(StandardRegPaths) do begin
		FRegistryPaths.Add(StandardRegPaths[i]);
	end;
	FFilePaths := TNSISTStringList.Create();
	FIsLogging := False;
	FIsDialogDebug := False;
end;

destructor TParameters.Destroy();
begin
	FFilePaths.Free();
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
end;

exports Locate;

end.
