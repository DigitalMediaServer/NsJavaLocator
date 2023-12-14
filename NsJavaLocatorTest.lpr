program NsJavaLocatorTest;

{$mode objfpc}{$H+}

uses
  Interfaces, Forms, GuiTestRunner, CoreTest;

{$R *.res}

begin
  Application.Initialize;
  Application.CreateForm(TGuiTestRunner, TestRunner);
  Application.Run;
end.

