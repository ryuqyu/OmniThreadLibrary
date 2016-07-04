unit test_64_ProcessorGroups_NUMA;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants, System.Classes, Vcl.Graphics,
  Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.StdCtrls, Vcl.Samples.Spin,
  OtlComm;

const
  MSG_LOG = WM_USER;

type
  TfrmProcessorGroupsNUMA = class(TForm)
    lbLog: TListBox;
    btnStartProcGroup: TButton;
    inpProcGroup: TSpinEdit;
    btnStartInNumaNode: TButton;
    inpNUMANode: TSpinEdit;
    procedure btnStartInNumaNodeClick(Sender: TObject);
    procedure btnStartProcGroupClick(Sender: TObject);
    procedure FormShow(Sender: TObject);
  private
    procedure DisplayInfo;
    procedure Log(const msg: string); overload;
    procedure Log(const msg: string; const params: array of const); overload;
    procedure WMMsgLog(var msg: TOmniMessage); message MSG_LOG;
  public
  end;

var
  frmProcessorGroupsNUMA: TfrmProcessorGroupsNUMA;

implementation

uses
  DSiWin32,
  OtlTask,
  OtlTaskControl,
  OtlCommon;

{$R *.dfm}

procedure TestWorker(const task: IOmniTask);
var
  groupAffinity: TGroupAffinity;
begin
  if DSiGetThreadGroupAffinity(GetCurrentThread, groupAffinity) then
    task.Comm.Send(MSG_LOG, Format('Thread affinity: group %d, mask %.16x',
      [groupAffinity.Group, groupAffinity.Mask]))
  else
    task.Comm.Send(MSG_LOG, 'Cannot read thread group affinity');
end;

{ TfrmProcessorGroupsNUMA }

procedure TfrmProcessorGroupsNUMA.btnStartInNumaNodeClick(Sender: TObject);
begin
  CreateTask(TestWorker, 'NUMANode task')
    .NUMANode(inpNUMANode.Value)
    .OnMessage(Self)
    .Unobserved
    .Run;
end;

procedure TfrmProcessorGroupsNUMA.btnStartProcGroupClick(Sender: TObject);
begin
  CreateTask(TestWorker, 'ProcessorGroup task')
    .ProcessorGroup(inpProcGroup.Value)
    .OnMessage(Self)
    .Unobserved
    .Run;
end;

procedure TfrmProcessorGroupsNUMA.DisplayInfo;
var
  i: integer;
begin
  Log('Processor groups');
  for i := 0 to Environment.ProcessorGroups.Count - 1 do
    Log(Format('%d: Mask: %.16x', [
      Environment.ProcessorGroups[i].GroupNumber,
      Environment.ProcessorGroups[i].Affinity]));
  Log('');

  Log('NUMA nodes');
  for i := 0 to Environment.NUMANodes.Count - 1 do
    Log(Format('%d: Group: %d, Mask: %.16x', [
      Environment.NUMANodes[i].NodeNumber,
      Environment.NUMANodes[i].GroupNumber,
      Environment.NUMANodes[i].Affinity]));
end;

procedure TfrmProcessorGroupsNUMA.FormShow(Sender: TObject);
begin
  OnShow := nil;
  DisplayInfo;
end;

procedure TfrmProcessorGroupsNUMA.Log(const msg: string);
begin
  lbLog.Items.Add(msg);
end;

procedure TfrmProcessorGroupsNUMA.Log(const msg: string; const params: array of const);
begin
  Log(Format(msg, params));
end;

procedure TfrmProcessorGroupsNUMA.WMMsgLog(var msg: TOmniMessage);
begin
  Log(msg.MsgData);
end;

end.
