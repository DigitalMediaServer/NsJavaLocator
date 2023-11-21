{
    Original Code from
    (C) 2001 - Peter Windridge

    Code in separate unit and some changes
    2003 by Bernhard Mayer

    Fixed and formatted by Brett Dever
    http://editor.nfscheats.com/

    Further fixes and additions by Nadahar

    simply include this unit in your plugin project and export
    functions as needed
}

unit NSIS;

{$MODE Delphi}

interface

uses
	windows, SysUtils
{$IFNDEF FPC}
	,CommCtrl
{$ENDIF}
{$IF FPC_FULLVERSION < 30000} ; This is probably wrong
	,CommCtrl
{$ENDIF}
	;

type
{$IFDEF UNICODE}
	NSISTString = UnicodeString;
	NSISPTChar = PWideChar;
{$ELSE}
	NSISTString = AnsiString;
	NSISPTChar = PAnsiChar;
{$ENDIF}
	VarConstants = (
		INST_0,       // $0
		INST_1,       // $1
		INST_2,       // $2
		INST_3,       // $3
		INST_4,       // $4
		INST_5,       // $5
		INST_6,       // $6
		INST_7,       // $7
		INST_8,       // $8
		INST_9,       // $9
		INST_R0,      // $R0
		INST_R1,      // $R1
		INST_R2,      // $R2
		INST_R3,      // $R3
		INST_R4,      // $R4
		INST_R5,      // $R5
		INST_R6,      // $R6
		INST_R7,      // $R7
		INST_R8,      // $R8
		INST_R9,      // $R9
		INST_CMDLINE, // $CMDLINE
		INST_INSTDIR, // $INSTDIR
		INST_OUTDIR,  // $OUTDIR
		INST_EXEDIR,  // $EXEDIR
		INST_LANG,    // $LANGUAGE
		__INST_LAST
		);
	TVariableList = INST_0..__INST_LAST;

type
	PluginCallbackMessages = (
		NSPIM_UNLOAD,   // This is the last message a plugin gets, do final cleanup
		NSPIM_GUIUNLOAD // Called after .onGUIEnd
	);
	TNSPIM = NSPIM_UNLOAD..NSPIM_GUIUNLOAD;

	//TPluginCallback = function (const NSPIM: Integer): Pointer; cdecl;

	TExecuteCodeSegment = function (const funct_id: Integer; const parent: HWND): Integer;  stdcall;
	Tvalidate_filename = procedure (const filename: NSISPTChar); stdcall;
	TRegisterPluginCallback = function (const DllInstance: HMODULE; const CallbackFunction: Pointer): Integer; stdcall;

	pexec_flags_t = ^exec_flags_t;
	exec_flags_t = record
		autoclose: Integer;
		all_user_var: Integer;
		exec_error: Integer;
		abort: Integer;
		exec_reboot: Integer;
		reboot_called: Integer;
		XXX_cur_insttype: Integer;
		plugin_api_version: Integer;
		silent: Integer;
		instdir_error: Integer;
		rtl: Integer;
		errlvl: Integer;
		alter_reg_view: Integer;
		status_update: Integer;
	end;

	pextrap_t = ^extrap_t;
	extrap_t = record
		exec_flags: Pointer; // exec_flags_t;
		exec_code_segment: TExecuteCodeSegment; // TFarProc;
		validate_filename: Pointer; // Tvalidate_filename;
		RegisterPluginCallback: Pointer; //TRegisterPluginCallback;
	end;

	pstack_t = ^stack_t;
	stack_t = record
		next: pstack_t;
		text: NSISPTChar;
	end;
	TDialaogIcon = (Info, Warning, Error, Question, None);

var
	g_stringsize: integer;
	g_stacktop: ^pstack_t;
	g_variables: NSISPTChar;
	g_hwndParent: HWND;
	g_hwndList: HWND;
	g_extraparameters: pextrap_t;

procedure Init(const hwndParent: HWND; const string_size: integer; const variables: NSISPTChar; const stacktop: pointer; const extraparameters: pointer = nil);
procedure LogMessage(Msg : NSISTString);
function Call(NSIS_func : NSISTString) : Integer;
function PopString(): NSISTString;
procedure PushString(const str: NSISTString='');
function GetUserVariable(const varnum: TVariableList): NSISTString;
procedure SetUserVariable(const varnum: TVariableList; const value: NSISTString);
procedure NSISDebugDialog(const variable: Pointer; const bytesLen : Integer; const caption: NSISTString);
procedure NSISDialog(const text, caption: NSISTString; const buttons: UINT = MB_OK; const icon : TDialaogIcon = Info); overload;

implementation

type
	TLV_ITEM = record
		mask : UINT;
		iItem : longint;
		iSubItem : longint;
		state : UINT;
		stateMask : UINT;
		pszText : NSISPTChar;
		cchTextMax : longint;
		iImage : longint;
		lParam : LPARAM;
	end;

function ListView_InsertItem(hwnd:HWND;var item : TLV_ITEM) : LRESULT;
begin
{$IFDEF UNICODE}
	ListView_InsertItem:=SendMessageW(hwnd,LVM_INSERTITEMW,0,LPARAM(@item));
{$ELSE}
	ListView_InsertItem:=SendMessageA(hwnd,LVM_INSERTITEMA,0,LPARAM(@item));
{$ENDIF}
end;

procedure Init(const hwndParent: HWND; const string_size: integer; const variables: NSISPTChar; const stacktop: pointer; const extraparameters: pointer = nil);
begin
	g_stringsize := string_size;
	g_hwndParent := hwndParent;
	g_stacktop   := stacktop;
	g_variables  := variables;
	if g_hwndParent = 0 then g_hwndList := 0
	else
{$IFDEF UNICODE}
		g_hwndList   := FindWindowExW(FindWindowExW(g_hwndParent, 0, '#32770', nil), 0,'SysListView32', nil);
{$ELSE}
		g_hwndList   := FindWindowExA(FindWindowExA(g_hwndParent, 0, '#32770', nil), 0,'SysListView32', nil);
{$ENDIF}
	g_extraparameters := extraparameters;
end;


function Call(NSIS_func : NSISTString) : Integer;

var
	codeoffset: Integer; //The ID of nsis function

{$WARN 4105 off : Implicit string type conversion with potential data loss from "$1" to "$2"}
begin
	Result := 0;
	codeoffset := StrToIntDef(NSIS_func, 0);
	if (codeoffset <> 0) and (g_extraparameters <> nil) then begin
		codeoffset := codeoffset - 1;
		Result := g_extraparameters.exec_code_segment(codeoffset, g_hwndParent);
	end;
end;
{$WARN 4105 on : Implicit string type conversion with potential data loss from "$1" to "$2"}

procedure LogMessage(Msg : NSISTString);
var
	ItemCount : Integer;
	item: TLV_ITEM;
{$WARN 5057 off : Local variable "$1" does not seem to be initialized}
begin
	if g_hwndList = 0 then exit;
	FillChar(item, sizeof(item), 0);
{$IFDEF UNICODE}
	ItemCount := SendMessageW(g_hwndList, LVM_GETITEMCOUNT, 0, 0);
{$ELSE}
	ItemCount := SendMessageA(g_hwndList, LVM_GETITEMCOUNT, 0, 0);
{$ENDIF}
	item.iItem := ItemCount;
	item.mask := LVIF_TEXT;
	item.pszText := NSISPTChar(Msg);
	ListView_InsertItem(g_hwndList, item);
	ListView_EnsureVisible(g_hwndList, ItemCount, not 0);
end;
{$WARN 5057 on : Local variable "$1" does not seem to be initialized}

function PopString(): NSISTString;
var
	th: pstack_t;
begin
	if NativeUInt(g_stacktop^) <> 0 then begin
		th := g_stacktop^;
		Result := NSISPTChar(@th.text);
		g_stacktop^ := th.next;
		GlobalFree(HGLOBAL(th));
	end
	else begin
		Result := '';
	end;
end;

procedure PushString(const str: NSISTString='');
var
	th: pstack_t;
begin
	if NativeUInt(g_stacktop) <> 0 then begin
{$IFDEF UNICODE}
		th := pstack_t(GlobalAlloc(GPTR, SizeOf(stack_t) + (g_stringsize * 2)));
		lstrcpynW(@th.text, PWideChar(str), g_stringsize);
{$ELSE}
		th := pstack_t(GlobalAlloc(GPTR, SizeOf(stack_t) + (g_stringsize    )));
		lstrcpynA(@th.text, PAnsiChar(str), g_stringsize);
{$ENDIF}
		th.next := g_stacktop^;
		g_stacktop^ := th;
	end;
end;

function GetUserVariable(const varnum: TVariableList): NSISTString;
begin
	if (integer(varnum) >= 0) and (integer(varnum) < integer(__INST_LAST)) then
		Result := g_variables + integer(varnum) * g_stringsize
	else
		Result := '';
end;

procedure SetUserVariable(const varnum: TVariableList; const value: NSISTString);
begin
	if (integer(varnum) >= 0) and (integer(varnum) < integer(__INST_LAST)) then
{$IFDEF UNICODE}
		lstrcpyW(g_variables + integer(varnum) * (g_stringsize), PWideChar(value))
{$ELSE}
		lstrcpyA(g_variables + integer(varnum) * (g_stringsize), PAnsiChar(value))
{$ENDIF}
end;

{
    Debugging NSIS plugins can be hard - this method can be used to output the byte data
    of memory as a hex string to a dialog. You must give the method the address/pointer
    and the number of bytes/the length to display.

    Parameters:
    variable    - The pointer to the variable to show. Show show the contents of a string
                  for example, use Pointer(string identifier) here.
    bytesLen    - The number of bytes to display from the address specified in "variable".
    caption     - The caption for the dialog box.
}
procedure NSISDebugDialog(const variable: Pointer; const bytesLen : Integer; const caption: NSISTString);

var
	pBytes : PByteArray;
	i : Integer;
	s : string = '';

begin
	pBytes := variable;
	for i := 0 to bytesLen - 1 do begin
		s := s + IntToHex(pBytes^[i]) + ' ';
	end;
	NSISDialog(NSISTString(s), caption, MB_OK);
end;

procedure NSISDialog(const text, caption: NSISTString; const buttons: UINT = MB_OK; const icon : TDialaogIcon = Info); overload;
var
	hwndOwner: HWND;
	iconVal : UINT = 0;

begin
	hwndOwner := g_hwndParent;
	if not IsWindow(g_hwndParent) then hwndOwner := 0; // g_hwndParent is not valid in NSPIM_[GUI]UNLOAD
	case icon of
		Info: iconVal := MB_ICONINFORMATION;
		Warning: iconVal := MB_ICONWARNING;
		Error: iconVal := MB_ICONERROR;
		Question: iconVal := MB_ICONQUESTION;
	end;

{$IFDEF UNICODE}
	MessageBoxW(hwndOwner, PWideChar(text), PWideChar(caption), buttons or iconVal);
{$ELSE}
	MessageBoxA(hwndOwner, PAnsiChar(text), PAnsiChar(caption), buttons or iconVal);
{$ENDIF}
end;

begin

end.

