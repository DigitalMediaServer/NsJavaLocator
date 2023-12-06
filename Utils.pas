unit Utils;
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
{$SCOPEDENUMS ON}

interface

uses
	Classes, Windows, fgl;

type
{$IFDEF UNICODE}
	VString = UnicodeString;
	VChar = WideChar;
	PVChar = PWideChar;
{$ELSE}
	VString = AnsiString;
	VChar = AnsiChar;
	PVChar = PAnsiChar;
{$ENDIF}
	TVStringArray = Array of VString;

	TInstallationType = (JDK, JRE, UNKNOWN);
	TArchitecture = (UNKNOWN, x86, x64, ia64);
	TLogLevel = (INVALID, ERROR, WARN, INFO, DEBUG);

	{ TLogger }

	TLogger = Interface
		procedure Log(const Message : VString; const LogLevel : TLogLevel);
		function IsWarn() : Boolean;
		function IsInfo() : Boolean;
		function IsDebug() : Boolean;
	end;

	{ TVStringList }

	TVStringList = class(TFPGList<VString>)
		function AddUnique(const Str : VString; const CaseSensitive : Boolean = True) : Integer;
		function RemoveMatching(const Str : VString; const CaseSensitive : Boolean = True) : Integer;
		function IndexOf(const Item : VString) : Integer;
		function IndexOfCaseInsensitive(const Item : VString) : Integer;
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

function IntToVStr(Value : QWord) : VString; overload;
function IntToVStr(Value : Int64) : VString; overload;
function IntToVStr(Value : LongInt) : VString; overload;
function UIntToVStr(Value : QWord) : VString; overload;
function UIntToVStr(Value : Cardinal) : VString; overload;
function VStrToIntDef(const ns : VString; Default : LongInt) : LongInt;
function BoolToVStr(Value : Boolean) : VString;
function EqualStr(str1, str2 : VString; CaseSensitive : Boolean = true) : Boolean;
function EndsWith(subStr : VString; const str : VString; CaseSensitive : Boolean = true) : Boolean;
function InstallationTypeToStr(const InstallationType : TInstallationType) : VString;
function ArchitectureToStr(const Architecture : TArchitecture; const BitsOnly : Boolean) : VString;
function LogLevelToVStr(const LogLevel : TLogLevel) : VString;
function VStrToLogLevel(const LogLevelStr : VString) : TLogLevel;
function SplitStr(const Path : VString; const separators : array of VChar) : TVStringArray;
function SplitPath(const Path : VString): TVStringArray;
function SystemErrorToStr(MessageId : DWORD) : VString;
function IsWOW64(const Logger : TLogger) : Boolean;
function ExpandEnvStrings(const str : VString) : VString;
function OpenRegKey(const rootKey : HKEY; const subKey : VString; samDesired : REGSAM; const Logger : TLogger) : HKEY;
function GetRegInt(const key : HKEY; const valueName : VString; const Logger : TLogger) : TNullableQWord;
function GetRegString(const key : HKEY; const valueName : VString; const Logger : TLogger) : VString;
function EnumerateRegSubKeys(const key : HKEY; const Logger : TLogger) : TVStringList;
function GetFileInfo(Path : VString) : TFileInfo;
function GetPEArchitecture(Path: VString) : TArchitecture;

implementation

uses
	SysUtils;

{ String handling routines }

function IntToVStr(Value : QWord) : VString; overload;
begin
	Result := VString(IntToStr(Value));
end;

function IntToVStr(Value : Int64) : VString; overload;
begin
	Result := VString(IntToStr(Value));
end;

function IntToVStr(Value : LongInt) : VString; overload;
begin
	Result := VString(IntToStr(Value));
end;

function UIntToVStr(Value : QWord) : VString; overload;
begin
	Result := VString(UIntToStr(Value));
end;

function UIntToVStr(Value : Cardinal) : VString; overload;
begin
	Result := VString(UIntToStr(Value));
end;

function VStrToIntDef(const ns : VString; Default : LongInt) : LongInt;

var
	Error : word;

begin
	Val(ns, Result, Error);
	if Error <> 0 then Result := Default;
end;

function BoolToVStr(Value : Boolean) : VString;
begin
	if Value then Result := 'True'
	else Result := 'False';
end;

function EqualStr(str1, str2 : VString; CaseSensitive : Boolean = true) : Boolean;

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

function EndsWith(subStr : VString; const str : VString; CaseSensitive : Boolean = true) : Boolean;

var
	subLen, len, offset, i : Integer;
	endStr : VString;

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

{ Utility routines }

function InstallationTypeToStr(const InstallationType : TInstallationType) : VString;
begin
	case InstallationType of
		TInstallationType.JDK : Result := VString('JDK');
		TInstallationType.JRE : Result := VString('JRE');
	else Result := VString('Unknown');
	end;
end;

function ArchitectureToStr(const Architecture : TArchitecture; const BitsOnly : Boolean) : VString;
begin
	if BitsOnly then begin
		case Architecture of
			TArchitecture.ia64 : Result := VString('64');
			TArchitecture.x64 : Result := VString('64');
			TArchitecture.x86 : Result := VString('32');
		else Result := VString('');
		end;
	end
	else begin
		case Architecture of
			TArchitecture.ia64 : Result := VString('ia64');
			TArchitecture.x64 : Result := VString('x64');
			TArchitecture.x86 : Result := VString('x86');
		else Result := VString('Unknown');
		end;
	end;
end;

function LogLevelToVStr(const LogLevel : TLogLevel) : VString;
begin
	case LogLevel of
		TLogLevel.ERROR : Result := VString('Error');
		TLogLevel.WARN : Result := VString('Warning');
		TLogLevel.INFO : Result := VString('Information');
		TLogLevel.DEBUG : Result := VString('Debug');
	else Result := VString('Invalid');
	end;
end;

function VStrToLogLevel(const LogLevelStr : VString) : TLogLevel;
begin
	Result := TLogLevel.INVALID;
	if LogLevelStr = '' then Exit;
	if EqualStr('ERROR', LogLevelStr, False) then Result := TLogLevel.ERROR
	else if EqualStr('WARN', LogLevelStr, False) or EqualStr('WARNING', LogLevelStr, False) then Result := TLogLevel.WARN
	else if EqualStr('INFO', LogLevelStr, False) or EqualStr('INFORMATION', LogLevelStr, False) then Result := TLogLevel.INFO
	else if EqualStr('DEBUG', LogLevelStr, False) then Result := TLogLevel.DEBUG;
end;

function SplitStr(const Path : VString; const separators : array of VChar) : TVStringArray;

const
	BlockSize = 10;

	procedure MaybeGrow(Curlen : SizeInt);
	begin
		if Length(Result) <= CurLen then SetLength(Result, Length(Result) + BlockSize);
	end;

	function IsSeparator(c : VChar) : Boolean;

	var
		ch : VChar;

	begin
		Result := False;
		for ch in separators do begin
			if ch = c then begin
				Result := True;
				Exit;
			end;
		end;
	end;

var
	LastSep, Len, StrLen, i : SizeInt;

begin
	StrLen := Length(Path);
	if (StrLen = 0) or (Length(separators) = 0) then begin
		SetLength(Result, 0);
		Exit;
	end;

	SetLength(Result, BlockSize);
	Len := 0;
	LastSep := 0;
	for i := 1 to StrLen do begin
		if IsSeparator(Path[i]) then begin
			if i > lastSep + 1 then begin
				MaybeGrow(Len);
				Result[Len] := Copy(Path, lastSep + 1, i - lastSep - 1);
				Inc(Len);
			end;
			lastSep := i;
		end;
	end;
	if lastSep < StrLen then begin
		MaybeGrow(Len);
		Result[Len] := Copy(Path, lastSep + 1, StrLen - lastSep);
		Inc(Len);
	end;
	SetLength(Result, Len);
end;

function SplitPath(const Path : VString): TVStringArray;

const
	PathSeparators : array[0..1] of VChar = ('\', '/');

begin
	Result := SplitStr(Path, PathSeparators);
end;

{ Windows API routines }

function SystemErrorToStr(MessageId : DWORD) : VString;

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

function IsWOW64(const Logger : TLogger) : Boolean;

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
		else if Logger <> Nil then Logger.Log('Failed to query isWow64Process', TLogLevel.ERROR);
	end;
end;

function ExpandEnvStrings(const str : VString) : VString;

var
	retVal : DWORD;

begin
	Result := '';
	if str = '' then Exit;

{$IFDEF UNICODE}
	retVal := ExpandEnvironmentStringsW(LPCWSTR(str), Nil, 0);
{$ELSE}
	retVal := ExpandEnvironmentStringsA(LPCSTR(str), Nil, 0);
{$ENDIF}
	if retVal = 0 then Exit;
	SetLength(Result, retVal);

{$IFDEF UNICODE}
	retVal := ExpandEnvironmentStringsW(LPCWSTR(str), @result[1], retVal);
{$ELSE}
	retVal := ExpandEnvironmentStringsA(LPCSTR(str), LPCSTR(result), retVal);
{$ENDIF}
	SetLength(Result, retVal - 1);
end;

function OpenRegKey(const rootKey : HKEY; const subKey : VString; samDesired : REGSAM; const Logger : TLogger) : HKEY;

var
	retVal : LongInt;

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
		if (retVal <> ERROR_FILE_NOT_FOUND) and (Logger <> Nil) then begin
			Logger.Log('Failed to open registry key "' + subkey + '" because: ' + SystemErrorToStr(retVal), TLogLevel.ERROR);
		end;
	end;
end;

{$WARN 5058 off : Variable "$1" does not seem to be initialized}
{$WARN 5060 off : Function result variable does not seem to be initialized}
function GetRegInt(const key : HKEY; const valueName : VString; const Logger : TLogger) : TNullableQWord;

var
	retVal : LONG;
	dataType : DWORD;
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
		if (retVal <> ERROR_FILE_NOT_FOUND) and (Logger <> Nil) then begin
			Logger.Log(
				'Failed to get registry value "' + valueName + '" because: ' + SystemErrorToStr(retVal),
				TLogLevel.ERROR
			);
		end;
	end;
end;
{$WARN 5058 on : Variable "$1" does not seem to be initialized}
{$WARN 5060 on : Function result variable does not seem to be initialized}

function GetRegString(const key : HKEY; const valueName : VString; const Logger : TLogger) : VString;
var
	retVal : LONG;
	dataType : DWORD;
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
		if (retVal <> ERROR_FILE_NOT_FOUND) and (Logger <> Nil) then begin
			Logger.Log(
				'Failed to get registry value "' + valueName + '" because: ' + SystemErrorToStr(retVal),
				TLogLevel.ERROR
			);
		end;
	end;
end;

function EnumerateRegSubKeys(const key : HKEY; const Logger : TLogger) : TVStringList;

var
	subKeys : DWORD = 0;
	lpcchName : DWORD;
	retVal : LONG;
	i : Integer;
{$IFDEF UNICODE}
	lpName : PWideChar;
{$ELSE}
	lpName : PChar;
{$ENDIF}

begin
	Result := TVStringList.Create;
	if key = 0 then Exit;
	retVal := RegQueryInfoKeyA(key, Nil, Nil, Nil, @subKeys, Nil, Nil, Nil, Nil, Nil, Nil, Nil);
	if retVal <> ERROR_SUCCESS then begin
		if Logger <> Nil then
			Logger.Log(
				'Failed to enumerate registry sub keys: ' + SystemErrorToStr(retVal),
				TLogLevel.ERROR
			);
	end
	else if (subKeys > 0) then begin
{$IFDEF UNICODE}
		lpName :=  WideStrAlloc(255);
{$ELSE}
		lpName := StrAlloc(255);
{$ENDIF}
		try
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
				else if (Logger <> Nil) then begin
					Logger.Log(
						'Failed to retrieve registry sub key name: ' + SystemErrorToStr(retVal),
						TLogLevel.ERROR
					);
				end;
			end;
		finally
			StrDispose(lpName);
		end;
	end;
end;

function GetFileInfo(Path : VString) : TFileInfo;

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
		if GetFileVersionInfoW(PWideChar(Path), dwHandle, size, buffer) then begin
{$ELSE}
		if GetFileVersionInfoA(PChar(Path), dwHandle, size, buffer) then begin
{$ENDIF}
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

function GetPEArchitecture(Path: VString) : TArchitecture;

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

{ TVStringList }

function TVStringList.AddUnique(const Str : VString; const CaseSensitive : Boolean) : Integer;

var
	idx : Integer;

begin
	if CaseSensitive then idx := IndexOf(Str)
	else idx := IndexOfCaseInsensitive(Str);
	if idx = -1 then Result := Add(Str)
	else Result := -1;
end;

function TVStringList.RemoveMatching(const Str : VString; const CaseSensitive : Boolean) : Integer;

var
	idx : Integer;

begin
	Result := 0;
	repeat
		if CaseSensitive then idx := IndexOf(Str)
		else idx := IndexOfCaseInsensitive(Str);
		if idx > -1 then begin
			Delete(idx);
			Inc(Result);
		end;
	until idx = -1;
end;

function TVStringList.IndexOf(const Item : VString) : Integer;
begin
	Result := 0;
	while (Result < FCount) and (not EqualStr(Items[Result], Item)) do Inc(Result);
	if Result = FCount then Result := -1;
end;

function TVStringList.IndexOfCaseInsensitive(const Item : VString) : Integer;
begin
	Result := 0;
	while (Result < FCount) and (not EqualStr(Items[Result], Item, False)) do Inc(Result);
	if Result = FCount then Result := -1;
end;


end.

