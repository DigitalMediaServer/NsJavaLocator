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

interface

uses
	Classes, SysUtils, Utils, fgl;

type
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
