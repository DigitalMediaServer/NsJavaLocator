unit CoreTest;

{$mode objfpc}{$H+}

interface

uses
	Classes, SysUtils, Core, Utils, fpcunit, fgl, testregistry;

type

	{ NsJavaLocatorTest }

	NsJavaLocatorTest = class(TTestCase)
	published
		procedure TestEvaluator();
		procedure TestIsOptimal;
	end;

 { TSimpleSettings }

	TSimpleSettings = class(TObject, TSettings)
	public
		FRegistryPaths : TVStringList;
		FEnvironmentVariables : TVStringList;
		FFilePaths : TVStringList;
		FFilteredPaths : TVStringList;
		FSkipOSPath : Boolean;
		FMinVersion : VString;
		FMaxVersion : VString;
		FOptimalVersion : VString;

		function GetRegistryPaths() : TVStringList;
		function GetEnvironmentVariables() : TVStringList;
		function GetFilePaths() : TVStringList;
		function GetFilteredPaths() : TVStringList;
		function GetSkipOSPath() : Boolean;
		function GetMinVersion() : VString;
		function GetMaxVersion() : VString;
		function GetOptimalVersion() : VString;
 	end;

implementation

{ TSimpleSettings }

function TSimpleSettings.GetRegistryPaths : TVStringList;
begin
	Result := FRegistryPaths;
end;

function TSimpleSettings.GetEnvironmentVariables : TVStringList;
begin
	Result := FEnvironmentVariables;
end;

function TSimpleSettings.GetFilePaths : TVStringList;
begin
	Result := FFilePaths;
end;

function TSimpleSettings.GetFilteredPaths : TVStringList;
begin
	Result := FFilteredPaths;
end;

function TSimpleSettings.GetSkipOSPath : Boolean;
begin
	Result := FSkipOSPath;
end;

function TSimpleSettings.GetMinVersion : VString;
begin
	Result := FMinVersion;
end;

function TSimpleSettings.GetMaxVersion : VString;
begin
	Result := FMaxVersion;
end;

function TSimpleSettings.GetOptimalVersion : VString;
begin
	Result := FOptimalVersion;
end;

procedure NsJavaLocatorTest.TestEvaluator();

type
	TInstallations = specialize TFPGObjectList<TJavaInstallation>;

var
	eval : TEvaluator;
	Installations : TInstallations;
	Settings : TSimpleSettings;
	inst1, inst2, inst3, inst4, inst5, inst6 : TJavaInstallation;

begin
	Installations := TInstallations.Create(True);
	inst1 := TJavaInstallation.Create();
	inst1.Architecture := TArchitecture.x64;
	inst1.Version := 7;
	inst1.Build := 180;
	Installations.Add(inst1);
	inst2 := TJavaInstallation.Create();
	inst2.Architecture := TArchitecture.x64;
	inst2.Version := 8;
	inst2.Build := 380;
	Installations.Add(inst2);
	inst3 := TJavaInstallation.Create();
	inst3.Architecture := TArchitecture.x86;
	inst3.Version := 8;
	inst3.Build := 180;
	Installations.Add(inst3);
	inst4 := TJavaInstallation.Create();
	inst4.Architecture := TArchitecture.x86;
	inst4.Version := 11;
	inst4.Build := 20;
	Installations.Add(inst4);
	inst5 := TJavaInstallation.Create();
	inst5.Architecture := TArchitecture.x64;
	inst5.Version := 11;
	inst5.Build := 5;
	Installations.Add(inst5);
	inst6 := TJavaInstallation.Create();
	inst6.Architecture := TArchitecture.UNKNOWN;
	inst6.Version := 21;
	inst6.Build := 13;
	Installations.Add(inst6);

	Settings := TSimpleSettings.Create;
	eval := TEvaluator.Create(Installations, Settings, Nil);
	eval.Process();
	AssertTrue(inst5.Equals(Installations.Items[0]));
	AssertTrue(inst2.Equals(Installations.Items[1]));
	AssertTrue(inst1.Equals(Installations.Items[2]));
	AssertTrue(inst4.Equals(Installations.Items[3]));
	AssertTrue(inst3.Equals(Installations.Items[4]));
	AssertTrue(inst6.Equals(Installations.Items[5]));

	Settings.FOptimalVersion := '<9';
	inst6.Architecture := TArchitecture.ia64;
	eval.Process();
	AssertTrue(inst2.Equals(Installations.Items[0]));
	AssertTrue(inst1.Equals(Installations.Items[1]));
	AssertTrue(inst3.Equals(Installations.Items[2]));
	AssertTrue(inst6.Equals(Installations.Items[3]));
	AssertTrue(inst5.Equals(Installations.Items[4]));
	AssertTrue(inst4.Equals(Installations.Items[5]));

	Installations.Free;
	Settings.Free;
end;

procedure NsJavaLocatorTest.TestIsOptimal();

var
	opt : TVersionCondition;
	inst : TJavaInstallation;

begin
	opt.Valid := False;
	inst := TJavaInstallation.Create();
	try
		// Equal
		opt.CompareType := TCompareType.equal;
		AssertFalse(ConditionTrue(opt, inst)); // Invalid = Invalid
		inst.Version := 2;
		AssertFalse(ConditionTrue(opt, inst)); // 2 = Invalid
		inst.Build := 2;
		AssertFalse(ConditionTrue(opt, inst)); // 2.2 = Invalid
		inst.Version := -1;
		inst.Build := -1;
		opt.Version := 2;
		opt.Valid := True;
		opt.Build := -1;
		AssertFalse(ConditionTrue(opt, inst)); // Invalid = 2
		inst.Version := 1;
		AssertFalse(ConditionTrue(opt, inst)); // 1 = 2
		inst.Version := 2;
		AssertTrue(ConditionTrue(opt, inst)); // 2 = 2
		opt.Build := 4;
		AssertFalse(ConditionTrue(opt, inst)); // 2 = 2.4
		inst.Build := 3;
		AssertFalse(ConditionTrue(opt, inst)); // 2.3 = 2.4
		inst.Build := 4;
		AssertTrue(ConditionTrue(opt, inst)); // 2.4 = 2.4
		opt.Build := -1;
		AssertTrue(ConditionTrue(opt, inst)); // 2.4 = 2

		// Less
		inst.Version := 2;
		inst.Build := 4;
		opt.Version := 2;
		opt.Build := -1;
		opt.CompareType := TCompareType.less;
		AssertFalse(ConditionTrue(opt, inst)); // 2.4 < 2
		opt.Build := 3;
		AssertFalse(ConditionTrue(opt, inst)); // 2.4 < 2.3
		opt.Build := -1;
		inst.Version := 1;
		AssertTrue(ConditionTrue(opt, inst)); // 1.4 < 2
		inst.Version := 2;
		opt.Build := 4;
		AssertFalse(ConditionTrue(opt, inst)); // 2.4 < 2.4
		opt.Build := 5;
		AssertTrue(ConditionTrue(opt, inst)); // 2.4 < 2.5
		inst.Build := -1;
		AssertFalse(ConditionTrue(opt, inst)); // 2 < 2.5
		inst.Version := -1;
		AssertFalse(ConditionTrue(opt, inst)); // Invalid < 2.5
		inst.Version := 2;
		inst.Build := 6;
		AssertFalse(ConditionTrue(opt, inst)); // 2.6 < 2.5
		inst.Version := 1;
		inst.Build := 5;
		AssertTrue(ConditionTrue(opt, inst)); // 1.5 < 2.5
		inst.Build := 6;
		AssertTrue(ConditionTrue(opt, inst)); // 1.6 < 2.5
		inst.Version := 3;
		AssertFalse(ConditionTrue(opt, inst)); // 3.6 < 2.5
		opt.Build := -1;
		AssertFalse(ConditionTrue(opt, inst)); // 3.6 < 2
		inst.Build := -1;
		AssertFalse(ConditionTrue(opt, inst)); // 3 < 2
		inst.Version := 2;
		AssertFalse(ConditionTrue(opt, inst)); // 2 < 2
		inst.Version := 1;
		AssertTrue(ConditionTrue(opt, inst)); // 1 < 2

		// LessOrEqual
		inst.Version := 2;
		inst.Build := 4;
		opt.Version := 2;
		opt.Build := -1;
		opt.CompareType := TCompareType.lessOrEqual;
		AssertTrue(ConditionTrue(opt, inst)); // 2.4 <= 2
		opt.Build := 3;
		AssertFalse(ConditionTrue(opt, inst)); // 2.4 <= 2.3
		opt.Build := -1;
		inst.Version := 1;
		AssertTrue(ConditionTrue(opt, inst)); // 1.4 <= 2
		inst.Version := 2;
		opt.Build := 4;
		AssertTrue(ConditionTrue(opt, inst)); // 2.4 <= 2.4
		opt.Build := 5;
		AssertTrue(ConditionTrue(opt, inst)); // 2.4 <= 2.5
		inst.Build := -1;
		AssertFalse(ConditionTrue(opt, inst)); // 2 <= 2.5
		inst.Version := -1;
		AssertFalse(ConditionTrue(opt, inst)); // Invalid <= 2.5
		inst.Version := 2;
		inst.Build := 6;
		AssertFalse(ConditionTrue(opt, inst)); // 2.6 <= 2.5
		inst.Version := 1;
		inst.Build := 5;
		AssertTrue(ConditionTrue(opt, inst)); // 1.5 <= 2.5
		inst.Build := 6;
		AssertTrue(ConditionTrue(opt, inst)); // 1.6 <= 2.5
		inst.Version := 3;
		AssertFalse(ConditionTrue(opt, inst)); // 3.6 <= 2.5
		opt.Build := -1;
		AssertFalse(ConditionTrue(opt, inst)); // 3.6 <= 2
		inst.Build := -1;
		AssertFalse(ConditionTrue(opt, inst)); // 3 <= 2
		inst.Version := 2;
		AssertTrue(ConditionTrue(opt, inst)); // 2 <= 2
		inst.Version := 1;
		AssertTrue(ConditionTrue(opt, inst)); // 1 <= 2

		// More
		inst.Version := 2;
		inst.Build := 4;
		opt.Version := 2;
		opt.Build := -1;
		opt.CompareType := TCompareType.more;
		AssertFalse(ConditionTrue(opt, inst)); // 2.4 > 2
		opt.Build := 4;
		AssertFalse(ConditionTrue(opt, inst)); // 2.4 > 2.4
		opt.Build := -1;
		inst.Version := 3;
		AssertTrue(ConditionTrue(opt, inst)); // 3.4 > 2
		inst.Version := 2;
		opt.Build := 5;
		AssertFalse(ConditionTrue(opt, inst)); // 2.4 > 2.5
		opt.Build := 3;
		AssertTrue(ConditionTrue(opt, inst)); // 2.4 > 2.3
		inst.Build := -1;
		AssertFalse(ConditionTrue(opt, inst)); // 2 > 2.3
		inst.Version := -1;
		AssertFalse(ConditionTrue(opt, inst)); // Invalid > 2.3
		inst.Version := 2;
		inst.Build := 2;
		AssertFalse(ConditionTrue(opt, inst)); // 2.2 > 2.3
		inst.Version := 3;
		inst.Build := 1;
		AssertTrue(ConditionTrue(opt, inst)); // 3.1 > 2.3
		inst.Build := 6;
		AssertTrue(ConditionTrue(opt, inst)); // 3.6 > 2.3
		inst.Build := 2;
		AssertTrue(ConditionTrue(opt, inst)); // 3.2 > 2.3
		inst.Version := 2;
		AssertFalse(ConditionTrue(opt, inst)); // 2.2 > 2.3
		inst.Version := 1;
		AssertFalse(ConditionTrue(opt, inst)); // 1.2 > 2.3
		opt.Build := -1;
		AssertFalse(ConditionTrue(opt, inst)); // 1.2 > 2
		inst.Build := -1;
		AssertFalse(ConditionTrue(opt, inst)); // 1 > 2
		inst.Version := 2;
		AssertFalse(ConditionTrue(opt, inst)); // 2 > 2
		inst.Version := 3;
		AssertTrue(ConditionTrue(opt, inst)); // 3 > 2

		// MoreOrEqual
		inst.Version := 2;
		inst.Build := 4;
		opt.Version := 2;
		opt.Build := -1;
		opt.CompareType := TCompareType.moreOrEqual;
		AssertTrue(ConditionTrue(opt, inst)); // 2.4 >= 2
		opt.Build := 4;
		AssertTrue(ConditionTrue(opt, inst)); // 2.4 >= 2.4
		opt.Build := -1;
		inst.Version := 3;
		AssertTrue(ConditionTrue(opt, inst)); // 3.4 >= 2
		inst.Version := 2;
		opt.Build := 5;
		AssertFalse(ConditionTrue(opt, inst)); // 2.4 >= 2.5
		opt.Build := 3;
		AssertTrue(ConditionTrue(opt, inst)); // 2.4 >= 2.3
		inst.Build := -1;
		AssertFalse(ConditionTrue(opt, inst)); // 2 >= 2.3
		inst.Version := -1;
		AssertFalse(ConditionTrue(opt, inst)); // Invalid >= 2.3
		inst.Version := 2;
		inst.Build := 2;
		AssertFalse(ConditionTrue(opt, inst)); // 2.2 >= 2.3
		inst.Version := 3;
		inst.Build := 1;
		AssertTrue(ConditionTrue(opt, inst)); // 3.1 >= 2.3
		inst.Build := 6;
		AssertTrue(ConditionTrue(opt, inst)); // 3.6 >= 2.3
		inst.Build := 2;
		AssertTrue(ConditionTrue(opt, inst)); // 3.2 >= 2.3
		inst.Version := 2;
		AssertFalse(ConditionTrue(opt, inst)); // 2.2 >= 2.3
		inst.Version := 1;
		AssertFalse(ConditionTrue(opt, inst)); // 1.2 >= 2.3
		opt.Build := -1;
		AssertFalse(ConditionTrue(opt, inst)); // 1.2 >= 2
		inst.Build := -1;
		AssertFalse(ConditionTrue(opt, inst)); // 1 >= 2
		inst.Version := 2;
		AssertTrue(ConditionTrue(opt, inst)); // 2 >= 2
		inst.Version := 3;
		AssertTrue(ConditionTrue(opt, inst)); // 3 >= 2
	finally
		inst.Free;
	end;
end;

initialization

	RegisterTest(NsJavaLocatorTest);
end.

