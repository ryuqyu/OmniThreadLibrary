object frmProcessorGroupsNUMA: TfrmProcessorGroupsNUMA
  Left = 0
  Top = 0
  Caption = 'Processor groups & NUMA tester'
  ClientHeight = 336
  ClientWidth = 635
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -11
  Font.Name = 'Tahoma'
  Font.Style = []
  OldCreateOrder = False
  OnShow = FormShow
  PixelsPerInch = 96
  TextHeight = 13
  object lbLog: TListBox
    Left = 248
    Top = 0
    Width = 387
    Height = 336
    Align = alRight
    Anchors = [akLeft, akTop, akRight, akBottom]
    ItemHeight = 13
    TabOrder = 0
  end
  object btnStartProcGroup: TButton
    Left = 8
    Top = 8
    Width = 177
    Height = 25
    Caption = 'Start task in processor group:'
    TabOrder = 1
    OnClick = btnStartProcGroupClick
  end
  object inpProcGroup: TSpinEdit
    Left = 191
    Top = 10
    Width = 49
    Height = 22
    MaxValue = 0
    MinValue = 0
    TabOrder = 2
    Value = 0
  end
  object btnStartInNumaNode: TButton
    Left = 8
    Top = 39
    Width = 177
    Height = 25
    Caption = 'Start task in NUMA node:'
    TabOrder = 3
    OnClick = btnStartInNumaNodeClick
  end
  object inpNUMANode: TSpinEdit
    Left = 191
    Top = 41
    Width = 49
    Height = 22
    MaxValue = 0
    MinValue = 0
    TabOrder = 4
    Value = 0
  end
end
