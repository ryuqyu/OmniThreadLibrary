///<summary>Thread pool. Part of the OmniThreadLibrary project.</summary>
///<author>Primoz Gabrijelcic</author>
///<license>
///This software is distributed under the BSD license.
///
///Copyright (c) 2016, Primoz Gabrijelcic
///All rights reserved.
///
///Redistribution and use in source and binary forms, with or without modification,
///are permitted provided that the following conditions are met:
///- Redistributions of source code must retain the above copyright notice, this
///  list of conditions and the following disclaimer.
///- Redistributions in binary form must reproduce the above copyright notice,
///  this list of conditions and the following disclaimer in the documentation
///  and/or other materials provided with the distribution.
///- The name of the Primoz Gabrijelcic may not be used to endorse or promote
///  products derived from this software without specific prior written permission.
///
///THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
///ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
///WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
///DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR
///ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
///(INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
///LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON
///ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
///(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
///SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
///</license>
///<remarks><para>
///   Home              : http://www.omnithreadlibrary.com
///   Support           : https://plus.google.com/communities/112307748950248514961
///   Author            : Primoz Gabrijelcic
///     E-Mail          : primoz@gabrijelcic.org
///     Blog            : http://thedelphigeek.com
///   Contributors      : GJ, Lee_Nover, Sean B. Durkin
///   Creation date     : 2008-06-12
///   Last modification : 2016-07-14
///   Version           : 2.14
/// </para><para>
///   History:
///     2.14: 2016-07-14
///       - Any change to Affinity, ProcessorGroups, or NUMANodes properties will reset
///         the MaxExecuting count.
///     2.13: 2016-07-13
///       - Implemented NUMA and Processor group support.
///     2.12: 2015-10-04
///       - Imported mobile support by [Sean].
///     2.11: 2015-09-07
///       - Setting MinWorkers property will start up idle worker threads if total number
///         of threads managed by the thread pool is lower than the new value.
///     2.10: 2015-09-03
///       - Removed limitation on max 60 threads in a pool (faciliated by changes in
///         OtlTaskControl).
///     2.09a: 2012-01-31
///       - More accurate CountQueued.
///     2.09: 2011-11-08
///       - Adapted to OtlCommon 1.24.
///     2.08: 2011-11-06
///       - Sets thread name to 'Idle thread worker' when a thread is idle.
///     2.07: 2011-07-14
///       - Exceptions are no longer reported through the OnPoolWorkItemCompleted event.
///     2.06: 2011-07-04
///       - Fixed task exception handling. Exceptions are now reported through the
///         OnPoolWorkItemCompleted event.
///     2.05b: 2010-11-25
///       - Bug fixed: Thread pool was immediately closing unused threads if MaxExecuting
///         was set to -1.
///     2.05a: 2010-07-19
///       - Works correctly if MaxExecuting is set to 0. Set MaxExecuting to -1 to allow
///         "infinite" number of execution threads.
///       - When MaxExecuting is changed, the code checks immediately if tasks from the
///         idle queue can now be activated.
///     2.05: 2010-07-01
///       - Includes OTLOptions.inc.
///     2.04a: 2010-06-06
///       - Modified patch from 2.04 so that it's actually working.
///     2.04: 2010-05-30
///       - ThreadDataFactory can now accept either a function or a method.
///     2.03c: 2010-01-09
///       - Fixed CancelAll.
///       - Can be compiled with /dLogThreadPool.
///     2.03b: 2009-12-12
///       - Fixed exception handling for silent exceptions.
///     2.03a: 2009-11-17
///       - Task worker must not depend on monitor to be assigned.
///       - SetMonitor must be synchronous.
///     2.02: 2009-11-13
///       - D2010 compatibility changes.
///     2.01b: 2009-03-03
///       - Bug fixed: TOTPWorkerThread.Create was not waiting on the worker object to
///         initialize.
///     2.01a: 2009-02-09
///       - Removed critical section added in 2.0b - it is not needed as the
///         IOmniTaskControl.Invoke is thread-safe.
///     2.01: 2009-02-08
///       - Added support for per-thread data storage.
///     2.0b: 2009-02-06
///       - Protect communication between TOmniThreadPool and TOTPWorker with a critical
///         section. That should allow multiple threads to Schedule tasks into one
///         thread pool. 
///     2.0a: 2009-02-06
///       - Removed OnWorkerThreadCreated_Asy/OnWorkerThreadDestroyed_Asy
///         notification mechanism which was pretty much useless.
///     2.0: 2009-01-26
///       - Reimplemented using OmniThreadLibrary :)
///     1.0: 2008-08-26
///       - First official release. 
/// </para></remarks>

unit OtlThreadPool;

{$I OtlOptions.inc}

interface

// TODO 1 -oPrimoz Gabrijelcic : Should be monitorable by the OmniTaskEventDispatch
// TODO 3 -oPrimoz Gabrijelcic : Needs an async event reporting unexpected states (kill threads, for example)
// TODO 5 -oPrimoz Gabrijelcic : Loggers should (maybe) send log info to the event monitor 

uses
  {$IFDEF MSWINDOWS}
  Windows,
  {$ELSE}
  Diagnostics,
  {$ENDIF ~MSWINDOWS}
  Contnrs,
  SysUtils,
  OtlCommon,
  OtlTask;

const
  CDefaultIdleWorkerThreadTimeout_sec = 10;
  CDefaultWaitOnTerminate_sec = 30;

type
  IOmniThreadPool = interface;

  IOmniThreadPoolMonitor = interface
    ['{09EFADE8-3F14-4184-87CA-131100EC57E4}']
    function  Detach(const task: IOmniThreadPool): IOmniThreadPool;
    {$IFDEF MSWINDOWS}
    function  Monitor(const task: IOmniThreadPool): IOmniThreadPool;
    {$ENDIF MSWINDOWS}
  end; { IOmniThreadPoolMonitor }

  TThreadPoolOperation = (tpoCreateThread, tpoDestroyThread, tpoKillThread,
    tpoWorkItemCompleted);

  TOmniThreadPoolMonitorInfo = class
  strict private
    otpmiTaskID             : int64;
    otpmiThreadID           : integer;
    otpmiThreadPoolOperation: TThreadPoolOperation;
    otpmiUniqueID           : int64;
  public
    constructor Create(uniqueID: int64; threadPoolOperation: TThreadPoolOperation;
      threadID: integer); overload;
    constructor Create(uniqueID, taskID: int64); overload;
    property TaskID: int64 read otpmiTaskID;
    property ThreadPoolOperation: TThreadPoolOperation read
      otpmiThreadPoolOperation;
    property ThreadID: integer read otpmiThreadID;
    property UniqueID: int64 read otpmiUniqueID;
  end; { TOmniThreadPoolMonitorInfo }

  TOTPThreadDataFactoryFunction = function: IInterface;
  TOTPThreadDataFactoryMethod = function: IInterface of object;

  /// <summary>Worker thread lifetime reporting handler.</summary>
  TOTPWorkerThreadEvent = procedure(Sender: TObject; threadID: TThreadID) of object;

  IOmniThreadPool = interface
    ['{1FA74554-1866-46DD-AC50-F0403E378682}']
    function  GetIdleWorkerThreadTimeout_sec: integer;
    function  GetMaxExecuting: integer;
    function  GetMaxQueued: integer;
    function  GetMaxQueuedTime_sec: integer;
    function  GetMinWorkers: integer;
    function  GetName: string;
    function  GetUniqueID: int64;
    function  GetWaitOnTerminate_sec: integer;
    procedure SetIdleWorkerThreadTimeout_sec(value: integer);
    procedure SetMaxExecuting(value: integer);
    procedure SetMaxQueued(value: integer); overload;
    procedure SetMaxQueuedTime_sec(value: integer);
    procedure SetMinWorkers(value: integer);
    procedure SetName(const value: string);
    procedure SetWaitOnTerminate_sec(value: integer);
    //
    function  Cancel(taskID: int64): boolean;
    procedure CancelAll;
    function  CountExecuting: integer;
    function  CountQueued: integer;
    function  GetAffinity: IOmniIntegerSet;
    function  IsIdle: boolean;
    function  MonitorWith(const monitor: IOmniThreadPoolMonitor): IOmniThreadPool;
    function  RemoveMonitor: IOmniThreadPool;
    function  SetMonitor(hWindow: THandle): IOmniThreadPool;
    procedure SetThreadDataFactory(const value: TOTPThreadDataFactoryMethod); overload;
    procedure SetThreadDataFactory(const value: TOTPThreadDataFactoryFunction); overload;
  {$IFDEF OTL_NUMASupport}
    function  GetNUMANodes: IOmniIntegerSet;
    function  GetProcessorGroups: IOmniIntegerSet;
    procedure SetNUMANodes(const value: IOmniIntegerSet);
    procedure SetProcessorGroups(const value: IOmniIntegerSet);
  {$ENDIF OTL_NUMASupport}
    property IdleWorkerThreadTimeout_sec: integer read GetIdleWorkerThreadTimeout_sec
      write SetIdleWorkerThreadTimeout_sec;
    property Affinity: IOmniIntegerSet read GetAffinity;
    property MaxExecuting: integer read GetMaxExecuting write SetMaxExecuting;
    property MaxQueued: integer read GetMaxQueued write SetMaxQueued;
    property MaxQueuedTime_sec: integer read GetMaxQueuedTime_sec write
      SetMaxQueuedTime_sec;
    property MinWorkers: integer read GetMinWorkers write SetMinWorkers;
    property Name: string read GetName write SetName;
    property UniqueID: int64 read GetUniqueID;
    property WaitOnTerminate_sec: integer read GetWaitOnTerminate_sec
      write SetWaitOnTerminate_sec;
    {$IFDEF OTL_NUMASupport}
    property ProcessorGroups: IOmniIntegerSet read GetProcessorGroups write
      SetProcessorGroups;
    property NUMANodes: IOmniIntegerSet read GetNUMANodes write SetNUMANodes;
    {$ENDIF OTL_NUMASupport}
  end; { IOmniThreadPool }

  IOmniThreadPoolScheduler = interface
    ['{B7F5FFEF-2704-4CE0-ABF1-B20493E73650}']
    procedure Schedule(const task: IOmniTask);
  end; { IOmniThreadPoolScheduler }

function CreateThreadPool(const threadPoolName: string): IOmniThreadPool;

function GlobalOmniThreadPool: IOmniThreadPool;

implementation

uses
  {$IFDEF MSWINDOWS}
  Messages,
  DSiWin32,
  GpStuff,
  {$ENDIF}
  Math,
  SyncObjs,
  Classes,
  TypInfo,
  {$IFDEF OTL_HasSystemTypes}
  System.Types,
  {$ENDIF}
  {$IFNDEF Unicode} // D2009+ provides own TStringBuilder class
  HVStringBuilder,
  {$ENDIF}
  OtlHooks,
  OtlSync,
  OtlComm,
  OtlContainerObserver,
  OtlTaskControl,
  OtlEventMonitor;

const
  WM_REQUEST_COMPLETED = {$IFDEF MSWINDOWS}WM_USER{$ELSE}1000{$ENDIF};

  MSG_RUN               = 1;
  MSG_THREAD_CREATED    = 2;
  MSG_THREAD_DESTROYING = 3;
  MSG_COMPLETED         = 4;
  MSG_STOP              = 5;
  MSG_CANCEL_RESULT     = 6;

type
{$IFNDEF Unicode}
  TStringBuilder = HVStringBuilder.StringBuilder;
{$ENDIF}
  TOTPWorkerThread = class;
  TOmniThreadPool = class;

  TOTPWorkItem = class
  strict private
    owiGroupAffinity: TOmniGroupAffinity;
    owiScheduled_ms : int64;
    owiScheduledAt  : TDateTime;
    owiStartedAt    : TDateTime;
    owiTask         : IOmniTask;
    owiThread       : TOTPWorkerThread;
    owiUniqueID     : int64;
  public
    constructor Create(const task: IOmniTask);
    function  Description: string;
    procedure TerminateTask(exitCode: integer; const exitMessage: string);
    property GroupAffinity: TOmniGroupAffinity read owiGroupAffinity write owiGroupAffinity;
    property Scheduled_ms: int64 read owiScheduled_ms;
    property ScheduledAt: TDateTime read owiScheduledAt;
    property StartedAt: TDateTime read owiStartedAt write owiStartedAt;
    property Task: IOmniTask read owiTask;
    property Thread: TOTPWorkerThread read owiThread write owiThread;
    property UniqueID: int64 read owiUniqueID;
  end; { TOTPWorkItem }

  TOTPThreadDataFactory = record
  private
    tdfExecutable: TOmniExecutable;
  public
    constructor Create(const a: TOTPThreadDataFactoryFunction); overload;
    constructor Create(const a: TOTPThreadDataFactoryMethod); overload;
    function  Execute: IInterface; inline;
    function  IsEmpty: boolean; inline;
  end; { TOTPThreadDataFactory }

  TOTPWorkerThread = class(TThread)
  strict private
    owtCommChannel      : IOmniTwoWayChannel;
    owtNewWorkEvent     : TOmniTransitionEvent;
    owtRemoveFromPool   : boolean;
    owtStartIdle_ms     : int64;
    owtStartStopping_ms : int64;
    owtStopped          : boolean;
    owtTerminateEvent   : TOmniTransitionEvent;
    owtThreadData       : IInterface;
    owtThreadDataFactory: TOTPThreadDataFactory;
    owtWorkItemLock     : IOmniCriticalSection;
    owtWorkItem_ref     : TOTPWorkItem;
  strict protected
    function  Comm: IOmniCommunicationEndpoint;
    procedure ExecuteWorkItem(workItem: TOTPWorkItem);
    function  GetOwnerCommEndpoint: IOmniCommunicationEndpoint;
    procedure Log(const msg: string; const params: array of const);
  public
    constructor Create(const ThreadDataFactory: TOTPThreadDataFactory);
    destructor  Destroy; override;
    procedure Asy_Stop;
    function  Asy_TerminateWorkItem(var workItem: TOTPWorkItem): boolean;
    function  Description: string;
    procedure Execute; override;
    function  GetWorkItemInfo(var scheduledAt, startedAt: TDateTime;
      var description: string): boolean;
    function  IsExecuting(taskID: int64): boolean;
    procedure Start;
    function  WorkItemDescription: string;
    property NewWorkEvent: TOmniTransitionEvent read owtNewWorkEvent;
    property OwnerCommEndpoint: IOmniCommunicationEndpoint read GetOwnerCommEndpoint;
    property RemoveFromPool: boolean read owtRemoveFromPool;
    property StartIdle_ms: int64 read owtStartIdle_ms write owtStartIdle_ms;
    property StartStopping_ms: int64 read owtStartStopping_ms
      write owtStartStopping_ms; // always modified from the owner thread
    property Stopped: boolean read owtStopped
      write owtStopped; // always modified from the owner thread
    property TerminateEvent: TOmniTransitionEvent read owtTerminateEvent;
    property WorkItem_ref: TOTPWorkItem read owtWorkItem_ref
      write owtWorkItem_ref; // address of the work item this thread is working on
  end; { TOTPWorkerThread }

  TOTPGroupAffinity = class
  private
    FAffinity: int64;
    FError    : integer;
    FGroup    : integer;
    FProcCount: integer;
  strict protected
    procedure SetAffinity(const value: int64);
  public
    constructor Create(group: integer; affinity: int64);
    property Affinity: int64 read FAffinity write SetAffinity;
    property Group: integer read FGroup;
    property ProcessorCount: integer read FProcCount;
    property Error: integer read FError write FError;
  end; { TOTPGroupAffinity }

  TOTPWorkerScheduler = class
  strict private
    owsClusters   : TObjectList {of TOTPGroupAffinity};
    owsNextCluster: integer;
    owsRoundRobin : array of integer;
  strict protected
    procedure ApplyAffinityMask(const affinity: IOmniIntegerSet);
    procedure CreateInitialClusters(const processorGroups, numaNodes: IOmniIntegerSet);
    procedure CreateRoundRobin;
    function  FindHighestError: integer;
    function  GetCluster(idx: integer): TOTPGroupAffinity; inline;
    function  IsSame(value1, value2: TOTPGroupAffinity): boolean; inline;
    procedure RemoveDuplicateClusters;
  public
    constructor Create;
    destructor  Destroy; override;
    function  Count: integer; inline;
    function  Next: TOmniGroupAffinity;
    procedure Update(affinity, processorGroups, numaNodes: IOmniIntegerSet);
    property Cluster[idx: integer]: TOTPGroupAffinity read GetCluster;
  end; { TOTPWorkerScheduler }

  TOTPWorker = class(TOmniWorker)
  strict private
    owAffinity         : IOmniIntegerSet;
    owDestroying       : boolean;
    owIdleWorkers      : TObjectList;
    {$IFDEF MSWINDOWS}
    owMonitorObserver  : TOmniContainerWindowsMessageObserver;
    {$ENDIF MSWINDOWS}
    owName             : string;
    owNUMANodes        : IOmniIntegerSet;
    owProcessorGroups  : IOmniIntegerSet;
    owRunningWorkers   : TObjectList;
    owScheduler        : TOTPWorkerScheduler;
    owStoppingWorkers  : TObjectList;
    owThreadDataFactory: TOTPThreadDataFactory;
    owUniqueID         : int64;
    owWorkItemQueue    : TObjectList;
  strict protected
    function  ActiveWorkItemDescriptions: string;
    function  CreateWorker: TOTPWorkerThread;
    procedure ForwardThreadCreated(threadID: TThreadID);
    procedure ForwardThreadDestroying(threadID: TThreadID;
      threadPoolOperation: TThreadPoolOperation; worker: TOTPWorkerThread = nil);
    procedure InternalStop;
    function  LocateThread(threadID: DWORD): TOTPWorkerThread;
    procedure Log(const msg: string; const params: array of const);
    function  NumRunningStoppedThreads: integer;
    procedure ProcessCompletedWorkItem(workItem: TOTPWorkItem);
    procedure RequestCompleted(workItem: TOTPWorkItem; worker: TOTPWorkerThread);
    procedure ScheduleNext(workItem: TOTPWorkItem);
    procedure StopThread(worker: TOTPWorkerThread);
    procedure UpdateScheduler;
  protected
    procedure Cleanup; override;
    function  Initialize: boolean; override;
  public
    CountQueued                : TOmniAlignedInt32;
    CountQueuedLock            : TOmniCS;
    CountRunning               : TOmniAlignedInt32;
    IdleWorkerThreadTimeout_sec: TOmniAlignedInt32;
    MaxExecuting               : TOmniAlignedInt32;
    MaxQueued                  : TOmniAlignedInt32;
    MaxQueuedTime_sec          : TOmniAlignedInt32;
    MinWorkers                 : TOmniAlignedInt32;
    WaitOnTerminate_sec        : TOmniAlignedInt32;
    constructor Create(const name: string; uniqueID: int64);
  published
    // invoked from TOmniThreadPool
    procedure Cancel(const params: TOmniValue);
    procedure CancelAll(var doneSignal: TOmniWaitableValue);
    procedure MaintainanceTimer;
    // invoked from TOTPWorkerThreads
    procedure CheckIdleQueue;
    procedure MsgCompleted(var msg: TOmniMessage); {$IFDEF MSWINDOWS}message MSG_COMPLETED;{$ENDIF}
    procedure MsgThreadCreated(var msg: TOmniMessage); {$IFDEF MSWINDOWS}message MSG_THREAD_CREATED;{$ENDIF}
    procedure MsgThreadDestroying(var msg: TOmniMessage); {$IFDEF MSWINDOWS}message MSG_THREAD_DESTROYING;{$ENDIF}
    procedure PruneWorkingQueue;
    procedure RemoveMonitor;
    procedure Schedule(var workItem: TOTPWorkItem);
    procedure SetAffinity(const value: TOmniValue);
    procedure SetMonitor(const params: TOmniValue);
    procedure SetNUMANodes(const value: TOmniValue);
    procedure SetProcessorGroups(const value: TOmniValue);
    procedure SetName(const name: TOmniValue);
    procedure SetThreadDataFactory(const threadDataFactory: TOmniValue);
  end; { TOTPWorker }

  TOTPThreadDataFactoryData = class
  strict private
    tdfdExecutable: TOTPThreadDataFactory;
  public
    constructor Create(const executable: TOTPThreadDataFactoryMethod); overload;
    constructor Create(const executable: TOTPThreadDataFactoryFunction); overload;
    property Executable: TOTPThreadDataFactory read tdfdExecutable;
  end; { TOTPThreadDataFactoryData }

  TOmniThreadPool = class(TInterfacedObject, IOmniThreadPool, IOmniThreadPoolScheduler)
  strict private
    otpAffinity         : IOmniIntegerSet;
    otpPoolName         : string;
    otpThreadDataFactory: TOTPThreadDataFactory;
    otpUniqueID         : int64;
    otpWorker           : IOmniWorker;
    otpWorkerTask       : IOmniTaskControl;
  {$IFDEF OTL_NUMASupport}
    otpNUMANodes        : IOmniIntegerSet;
    otpProcessorGroups  : IOmniIntegerSet;
  {$ENDIF OTL_NUMASupport}
  strict protected
    procedure Log(const msg: string; const params: array of const);
  protected
    function  GetAffinity: IOmniIntegerSet;
    function  GetIdleWorkerThreadTimeout_sec: integer;
    function  GetMaxExecuting: integer;
    function  GetMaxQueued: integer;
    function  GetMaxQueuedTime_sec: integer;
    function  GetMinWorkers: integer;
    function  GetName: string;
    function  GetUniqueID: int64;
    function  GetWaitOnTerminate_sec: integer;
    function  MakeIntegerSetCopy(const value: IOmniIntegerSet): TOmniValue;
    procedure NotifyAffinityChanged(const value: IOmniIntegerSet);
    procedure SetIdleWorkerThreadTimeout_sec(value: integer);
    procedure SetMaxExecuting(value: integer);
    procedure SetMaxQueued(value: integer);
    procedure SetMaxQueuedTime_sec(value: integer);
    procedure SetMinWorkers(value: integer);
    procedure SetName(const value: string);
    procedure SetWaitOnTerminate_sec(value: integer);
    function  WorkerObj: TOTPWorker;
  {$IFDEF OTL_NUMASupport}
    function  GetNUMANodes: IOmniIntegerSet;
    function  GetProcessorGroups: IOmniIntegerSet;
    procedure NotifyNUMANodesChanged(const value: IOmniIntegerSet);
    procedure NotifyProcessorGroupsChanged(const value: IOmniIntegerSet);
    procedure SetNUMANodes(const value: IOmniIntegerSet);
    procedure SetProcessorGroups(const value: IOmniIntegerSet);
  {$ENDIF OTL_NUMASupport}
  public
    constructor Create(const name: string);
    destructor  Destroy; override;
    function  Cancel(taskID: int64): boolean;
    procedure CancelAll;
    function  CountExecuting: integer;
    function  CountQueued: integer;
    function  IsIdle: boolean;
    function  MonitorWith(const monitor: IOmniThreadPoolMonitor): IOmniThreadPool;
    function  RemoveMonitor: IOmniThreadPool;
    procedure Schedule(const task: IOmniTask);
    function  SetMonitor(hWindow: THandle): IOmniThreadPool;
    procedure SetThreadDataFactory(const value: TOTPThreadDataFactoryMethod); overload;
    procedure SetThreadDataFactory(const value: TOTPThreadDataFactoryFunction); overload;
    property Affinity: IOmniIntegerSet read GetAffinity;
    property IdleWorkerThreadTimeout_sec: integer
      read GetIdleWorkerThreadTimeout_sec write SetIdleWorkerThreadTimeout_sec;
    property MaxExecuting: integer read GetMaxExecuting write SetMaxExecuting;
    property MaxQueued: integer read GetMaxQueued write SetMaxQueued;
    property MaxQueuedTime_sec: integer read GetMaxQueuedTime_sec
      write SetMaxQueuedTime_sec;
    property MinWorkers: integer read GetMinWorkers write SetMinWorkers;
    property Name: string read GetName write SetName;
    property UniqueID: int64 read GetUniqueID;
    property WaitOnTerminate_sec: integer read GetWaitOnTerminate_sec write
      SetWaitOnTerminate_sec;
  {$IFDEF OTL_NUMASupport}
    property ProcessorGroups: IOmniIntegerSet read GetProcessorGroups write
      SetProcessorGroups;
    property NUMANodes: IOmniIntegerSet read GetNUMANodes write SetNUMANodes;
  {$ENDIF OTL_NUMASupport}
  end; { TOmniThreadPool }

const
  CGlobalOmniThreadPoolName = 'GlobalOmniThreadPool';

var
  GOmniThreadPool: IOmniThreadPool = nil;

{ exports }

function GlobalOmniThreadPool: IOmniThreadPool;
begin
  if not assigned(GOmniThreadPool) then
    GOmniThreadPool := CreateThreadPool(CGlobalOmniThreadPoolName);
  Result := GOmniThreadPool;
end; { GlobalOmniThreadPool }

function CreateThreadPool(const threadPoolName: string): IOmniThreadPool;
begin
  Result := TOmniThreadPool.Create(threadPoolName);
end; { CreateThreadPool }

{ TOmniThreadPoolMonitorInfo }

constructor TOmniThreadPoolMonitorInfo.Create(uniqueID: int64;
  threadPoolOperation: TThreadPoolOperation; threadID: integer);
begin
  otpmiUniqueID := uniqueID;
  otpmiThreadPoolOperation := threadPoolOperation;
  otpmiThreadID := threadID;
end; { TOmniThreadPoolMonitorInfo.Create }

constructor TOmniThreadPoolMonitorInfo.Create(uniqueID, taskID: int64);
begin
  otpmiUniqueID := uniqueID;
  otpmiThreadPoolOperation := tpoWorkItemCompleted;
  otpmiTaskID := taskID;
end; { TOmniThreadPoolMonitorInfo.Create }

{ TOTPThreadDataFactory }

constructor TOTPThreadDataFactory.Create(const a: TOTPThreadDataFactoryFunction);
begin
  tdfExecutable.Proc := TProcedure(a);
end; { TOTPThreadDataFactory.Create }

constructor TOTPThreadDataFactory.Create(const a: TOTPThreadDataFactoryMethod);
begin
  tdfExecutable.Method := TMethod(a);
end; { TOTPThreadDataFactory.Create }

function TOTPThreadDataFactory.Execute: IInterface;
begin
  case tdfExecutable.Kind of
    oekProcedure:
      Result := TOTPThreadDataFactoryFunction(tdfExecutable.Proc)();
    oekMethod:
      Result := TOTPThreadDataFactoryMethod(tdfExecutable.Method)();
    else raise Exception.Create('TOTPThreadDataFactory.Execute: Not supported!');
  end;
end; { TOTPThreadDataFactory.Execute }

function TOTPThreadDataFactory.IsEmpty: boolean;
begin
  Result := tdfExecutable.IsNull;
end; { TOTPThreadDataFactory.IsEmpty }

{ TOTPWorkItem }

constructor TOTPWorkItem.Create(const task: IOmniTask);
begin
  inherited Create;
  owiTask := task;
  owiScheduledAt := Now;
  owiScheduled_ms := {$IFDEF MSWINDOWS} DSiTimeGetTime64 {$ELSE} TStopWatch.GetTimeStamp {$ENDIF};
  owiUniqueID := owiTask.UniqueID;
end; { TOTPWorkItem.Create }

function TOTPWorkItem.Description: string;
begin
  if assigned(Task) then
    Result := Format('%s:%d', [Task.Name, UniqueID])
  else
    Result := Format(':%d', [UniqueID]);
end; { TOTPWorkItem.Description }

procedure TOTPWorkItem.TerminateTask(exitCode: integer; const exitMessage: string);
begin
  if assigned(owiTask) then begin
    owiTask.Enforced(false);
    owiTask.SetExitStatus(exitCode, exitMessage);
    owiTask.Terminate;
    owiTask := nil;
  end;
end; { TOTPWorkItem.TerminateTask }

{ TOTPWorkerThread }

constructor TOTPWorkerThread.Create(const ThreadDataFactory: TOTPThreadDataFactory);
begin
  inherited Create(true);
  {$IFDEF LogThreadPool}Log('Creating thread %s', [Description]);{$ENDIF LogThreadPool}
  owtThreadDataFactory := ThreadDataFactory;
  {$IFDEF MSWINDOWS}
  owtNewWorkEvent := CreateEvent(nil, false, false, nil);
  owtTerminateEvent := CreateEvent(nil, false, false, nil);
  {$ELSE}
  owtNewWorkEvent := CreateOmniEvent(false, false);
  owtTerminateEvent := CreateOmniEvent(false, false);
  {$ENDIF ~MSWINDOWS}
  owtWorkItemLock := CreateOmniCriticalSection;
  owtCommChannel := CreateTwoWayChannel(100, owtTerminateEvent);
end; { TOTPWorkerThread.Create }

destructor TOTPWorkerThread.Destroy;
begin
  {$IFDEF LogThreadPool}Log('Destroying thread %s', [Description]);{$ENDIF LogThreadPool}
  owtWorkItemLock := nil;
  {$IFDEF MSWINDOWS}
  DSiCloseHandleAndNull(owtTerminateEvent);
  DSiCloseHandleAndNull(owtNewWorkEvent);
  {$ELSE}
  owtTerminateEvent := nil;
  owtNewWorkEvent := nil;
  {$ENDIF ~MSWINDOWS}
  inherited Destroy;
end; { TOTPWorkerThread.Destroy }

/// <summary>Gently stop the worker thread.
procedure TOTPWorkerThread.Asy_Stop;
var
  task: IOmniTask;
begin
  {$IFDEF LogThreadPool}Log('Stop thread %s', [Description]);{$ENDIF LogThreadPool}
  if assigned(owtWorkItemLock) then begin // Stop may be called during Cancel[All] and owtWorkItemLock may already be destroyed
    owtWorkItemLock.Acquire;
    try
      if assigned(WorkItem_ref) then begin
        task := WorkItem_ref.task;
        if assigned(task) then
          task.Terminate;
      end;
    finally owtWorkItemLock.Release end;
  end;
end; { TOTPWorkerThread.Asy_Stop }

/// <summary>Take the work item ownership from the thread. Called asynchronously from the thread pool.</summary>
/// <returns>True if thread should be killed.</returns>
/// <since>2008-07-26</since>
function TOTPWorkerThread.Asy_TerminateWorkItem(var workItem: TOTPWorkItem): boolean;
begin
  {$IFDEF LogThreadPool}Log('Asy_TerminateWorkItem thread %s', [Description]);{$ENDIF LogThreadPool}
  Result := false;
  owtWorkItemLock.Acquire;
  try
    if assigned(WorkItem_ref) then begin
      {$IFDEF LogThreadPool}Log('Thread %s has work item', [Description]);{$ENDIF LogThreadPool}
      workItem := WorkItem_ref;
      WorkItem_ref := nil;
      if assigned(workItem) and assigned(workItem.task) and
        (not workItem.task.Stopped) then
      begin
        workItem.TerminateTask(EXIT_THREADPOOL_CANCELLED, 'Cancelled');
        Result := true;
      end
      else if assigned(workItem) then
        Result := false;
    end;
  finally owtWorkItemLock.Release; end;
end; { TOTPWorkerThread.Asy_TerminateWorkItem }

function TOTPWorkerThread.Comm: IOmniCommunicationEndpoint;
begin
  Result := owtCommChannel.Endpoint1;
end; { TOTPWorkerThread.Comm }

function TOTPWorkerThread.Description: string;
begin
  if not assigned(Self) then
    Result := '<none>'
  else
    Result := Format('%p:%d', [pointer(Self), ThreadID]);
end; { TOTPWorkerThread.Description }

procedure TOTPWorkerThread.Execute;
var
  msg: TOmniMessage;
begin
  {$IFDEF LogThreadPool}Log('>>>Execute thread %s', [Description]);{$ENDIF LogThreadPool}
  SendThreadNotifications(tntCreate, 'OtlThreadPool worker');
  try
    Comm.Send(MSG_THREAD_CREATED, threadID);
    try
      if owtThreadDataFactory.IsEmpty then
        owtThreadData := nil
      else
        owtThreadData := owtThreadDataFactory.Execute;
      while true do begin
        if Comm.ReceiveWait(msg, INFINITE) then begin
          case msg.MsgID of
            MSG_RUN:
              ExecuteWorkItem(TOTPWorkItem(msg.MsgData.AsObject));
            MSG_STOP:
              break; // while
          else
            raise Exception.CreateFmt(
              'TOTPWorkerThread.Execute: Unexpected message %d', [msg.MsgID]);
          end; // case
        end; // if Comm.ReceiveWait
      end; // while Comm.ReceiveWait()
    finally Comm.Send(MSG_THREAD_DESTROYING, threadID); end;
  finally SendThreadNotifications(tntDestroy, 'OtlThreadPool worker'); end;
  {$IFDEF LogThreadPool}Log('<<<Execute thread %s', [Description]);{$ENDIF LogThreadPool}
end; { TOTPWorkerThread.Execute }

procedure TOTPWorkerThread.ExecuteWorkItem(workItem: TOTPWorkItem);
{$IFDEF LogThreadPool}
var
  creationTime   : TDateTime;
  startKernelTime: int64;
  startUserTime  : int64;
  stopKernelTime : int64;
  stopUserTime   : int64;
{$ENDIF LogThreadPool}
var
  task: IOmniTask;
begin
  WorkItem_ref := workItem;
  task := WorkItem_ref.task;
  try
    Environment.Thread.GroupAffinity := workItem.GroupAffinity;
    {$IFDEF LogThreadPool}Log('Thread %s starting execution of %s', [Description, WorkItem_ref.Description]);
    DSiGetThreadTimes(creationTime, startUserTime, startKernelTime); {$ENDIF LogThreadPool}
    if assigned(task) then
      with (task as IOmniTaskExecutor) do begin
        SetThreadData(owtThreadData);
        Execute;
      end;
    {$IFDEF LogThreadPool}DSiGetThreadTimes(creationTime, stopUserTime, stopKernelTime);
    Log(
      'Thread %s completed execution of %s; user time = %d ms, kernel time = %d ms',
      [Description, WorkItem_ref.Description, Round
        ((stopUserTime - startUserTime) / 10000), Round
        ((stopKernelTime - startKernelTime) / 10000)]); {$ENDIF LogThreadPool}
  finally task := nil; end;
  if assigned(owtWorkItemLock) then owtWorkItemLock.Acquire;
  try
    workItem := WorkItem_ref;
    WorkItem_ref := nil;
    if assigned(workItem) then begin // not already canceled
      {$IFDEF LogThreadPool}Log(
        'Thread %s sending notification of completed work item %s',
        [Description, workItem.Description]); {$ENDIF LogThreadPool}
      Comm.Send(MSG_COMPLETED, workItem);
    end;
  finally if assigned(owtWorkItemLock) then owtWorkItemLock.Release; end;
  SetThreadName('Idle thread worker');
end; { TOTPWorkerThread.ExecuteWorkItem }

function TOTPWorkerThread.GetOwnerCommEndpoint: IOmniCommunicationEndpoint;
begin
  Result := owtCommChannel.Endpoint2;
end; { TOTPWorkerThread.GetOwnerCommEndpoint }

function TOTPWorkerThread.GetWorkItemInfo(var scheduledAt, startedAt: TDateTime;
  var description: string): boolean;
begin
  owtWorkItemLock.Acquire;
  try
    if not assigned(WorkItem_ref) then
      Result := false
    else begin
      scheduledAt := WorkItem_ref.scheduledAt;
      startedAt := WorkItem_ref.startedAt;
      description := WorkItem_ref.description;
      UniqueString(description);
      Result := true;
    end;
  finally owtWorkItemLock.Release; end;
end; { TOTPWorkerThread.GetWorkItemInfo }

function TOTPWorkerThread.IsExecuting(taskID: int64): boolean;
begin
  owtWorkItemLock.Acquire;
  try
    Result := assigned(WorkItem_ref) and (WorkItem_ref.UniqueID = taskID);
  finally owtWorkItemLock.Release; end;
end; { TOTPWorkerThread.IsExecuting }

procedure TOTPWorkerThread.Log(const msg: string; const params: array of const);
begin
  {$IFDEF LogThreadPool}
  OutputDebugString(PChar(Format(msg, params)));
  {$ENDIF LogThreadPool}
end; { TOTPWorkerThread.Log }

procedure TOTPWorkerThread.Start;
begin
  {$IFDEF OTL_DeprecatedResume}
  inherited Start;
  {$ELSE}
  inherited Resume;
  {$ENDIF OTL_DeprecatedResume}
end; { TOTPWorkerThread.Start }

function TOTPWorkerThread.WorkItemDescription: string;
begin
  owtWorkItemLock.Acquire;
  try
    if assigned(WorkItem_ref) then
      Result := WorkItem_ref.Description
    else
      Result := '';
  finally owtWorkItemLock.Release; end;
end; { TOTPWorkerThread.WorkItemDescription }

{ TOTPWorker }

constructor TOTPWorker.Create(const name: string; uniqueID: int64);
begin
  inherited Create;
  owName := name;
  owUniqueID := uniqueID;
end; { TOTPWorker.Create }

function TOTPWorker.ActiveWorkItemDescriptions: string;
var
  description   : string;
  iWorker       : integer;
  sbDescriptions: TStringBuilder;
  ScheduledAt   : TDateTime;
  StartedAt     : TDateTime;
  worker        : TOTPWorkerThread;
begin
  sbDescriptions := TStringBuilder.Create;
  try
    for iWorker := 0 to owRunningWorkers.Count - 1 do begin
      worker := TOTPWorkerThread(owRunningWorkers[iWorker]);
      if worker.GetWorkItemInfo(ScheduledAt, StartedAt, description)
      then
        sbDescriptions.Append('[').Append(iWorker + 1).Append('] ').Append
          (FormatDateTime('hh:nn:ss', ScheduledAt)).Append(' / ').Append
          (FormatDateTime('hh:nn:ss', StartedAt)).Append(' ').Append
          (description);
    end;
    Result := sbDescriptions.ToString;
  finally FreeAndNil(sbDescriptions); end;
end; { TGpThreadPool.ActiveWorkItemDescriptions }

/// <returns>True: Normal exit, False: Thread was killed.</returns> 
procedure TOTPWorker.Cancel(const params: TOmniValue);
var
  endWait_ms   : int64;
  iWorker      : integer;
  taskID       : int64;
  waitParam    : TOmniValue;
  wasTerminated: boolean;
  worker       : TOTPWorkerThread;
  workItem     : TOTPWorkItem;
begin
  taskID := params[0];
  wasTerminated := true;
  for iWorker := 0 to owRunningWorkers.Count - 1 do begin
    worker := TOTPWorkerThread(owRunningWorkers[iWorker]);
    if worker.IsExecuting(taskID) then begin
      {$IFDEF LogThreadPool}Log('Cancel request %d on thread %p:%d', [taskID, pointer(worker), worker.threadID]); {$ENDIF LogThreadPool}
      owRunningWorkers.Delete(iWorker);
      worker.Asy_Stop;
      endWait_ms := {$IFDEF MSWINDOWS} DSiTimeGetTime64 {$ELSE} TStopWatch.GetTimeStamp {$ENDIF} + int64(WaitOnTerminate_sec.Value) * 1000;
      while ({$IFDEF MSWINDOWS} DSiTimeGetTime64 {$ELSE} TStopWatch.GetTimeStamp {$ENDIF} < endWait_ms) and (not worker.Stopped) do begin
        ProcessMessages;
        Sleep(10);
      end;
      {$IFDEF MSWINDOWS}
      SuspendThread(worker.Handle);
      {$ELSE}
      worker.Suspended := true;
      {$ENDIF ~MSWINDOWS}
      if worker.Asy_TerminateWorkItem(workItem) then begin
        ProcessCompletedWorkItem(workItem);
        {$IFDEF LogThreadPool}Log(
          'Terminating unstoppable thread %s, num idle = %d, num running = %d[%d]',
          [worker.Description, owIdleWorkers.Count, owRunningWorkers.Count,
          MaxExecuting.Value]); {$ENDIF LogThreadPool}
        {$IFDEF MSWINDOWS}
        TerminateThread(worker.Handle, cardinal(-1));
        {$ELSE}
        worker.Terminate;
        {$ENDIF ~MSWINDOWS}
        ForwardThreadDestroying(worker.threadID, tpoKillThread, worker);
        FreeAndNil(worker);
        wasTerminated := false;
      end
      else begin
        {$IFDEF MSWINDOWS}
        ResumeThread(worker.Handle);
        {$ELSE}
        worker.Suspended := false;
        {$ENDIF ~MSWINDOWS}
        owIdleWorkers.Add(worker);
        {$IFDEF LogThreadPool}Log(
          'Thread %s moved to the idle list, num idle = %d, num running = %d[%d]',
          [worker.Description, owIdleWorkers.Count, owRunningWorkers.Count,
          MaxExecuting.Value]); {$ENDIF LogThreadPool}
      end;
      break; // for 
    end;
  end; // for iWorker
  waitParam := params[1];
  (waitParam.AsObject as TOmniWaitableValue).Signal(wasTerminated);
end; { TOTPWorker.Cancel }

procedure TOTPWorker.CancelAll(var doneSignal: TOmniWaitableValue);
begin
  InternalStop;
  doneSignal.Signal;
end; { TOTPWorker.CancelAll }

procedure TOTPWorker.Cleanup;
begin
  owDestroying := true;
  InternalStop;
  FreeAndNil(owStoppingWorkers);
  FreeAndNil(owRunningWorkers);
  FreeAndNil(owIdleWorkers);
  FreeAndNil(owWorkItemQueue);
  FreeAndNil(owScheduler);
end; { TOTPWorker.Cleanup }

procedure TOTPWorker.ForwardThreadCreated(threadID: TThreadID);
begin
  {$IFDEF MSWINDOWS}
  if assigned(owMonitorObserver) then
    owMonitorObserver.Send(COmniPoolMsg, 0, cardinal
        (TOmniThreadPoolMonitorInfo.Create(owUniqueID, tpoCreateThread, threadID))
      );
  {$ENDIF MSWINDOWS}
end; { TOTPWorker.ForwardThreadCreated }

procedure TOTPWorker.ForwardThreadDestroying(threadID: TThreadID;
  threadPoolOperation: TThreadPoolOperation; worker: TOTPWorkerThread);
begin
  if not assigned(worker) then
    worker := LocateThread(threadID);
  if assigned(worker) then begin
    task.UnregisterComm(worker.OwnerCommEndpoint);
    worker.Stopped := true;
  end;
  {$IFDEF MSWINDOWS}
  if assigned(owMonitorObserver) then
    owMonitorObserver.Send(COmniPoolMsg, 0, cardinal
      (TOmniThreadPoolMonitorInfo.Create(owUniqueID, threadPoolOperation,
        threadID)));
  {$ENDIF MSWINDOWS}
end; { TOTPWorker.ForwardThreadDestroying }

function TOTPWorker.Initialize: boolean;
begin
  owAffinity := TOmniIntegerSet.Create;
  owNUMANodes := TOmniIntegerSet.Create;
  owProcessorGroups := TOmniIntegerSet.Create;
  owScheduler := TOTPWorkerScheduler.Create;
  owIdleWorkers := TObjectList.Create(false);
  owRunningWorkers := TObjectList.Create(false);
  CountRunning.Value := 0;
  owStoppingWorkers := TObjectList.Create(false);
  owWorkItemQueue := TObjectList.Create(false);
  CountQueued.Value := 0;
  IdleWorkerThreadTimeout_sec.Value := CDefaultIdleWorkerThreadTimeout_sec;
  WaitOnTerminate_sec.Value := CDefaultWaitOnTerminate_sec;
  Task.SetTimer(1, 1000, @TOTPWorker.MaintainanceTimer);
  UpdateScheduler;
  Result := true;
end; { TOTPWorker.Initialize }

procedure TOTPWorker.InternalStop;
var
  endWait_ms: int64;
  iWorker: integer;
  iWorkItem: integer;
  queuedItems: TObjectList { of TOTPWorkItem } ;
  worker: TOTPWorkerThread;
  workItem: TOTPWorkItem;
begin
  {$IFDEF LogThreadPool}Log('Terminating queued tasks', []);{$ENDIF LogThreadPool}
  queuedItems := TObjectList.Create(false);
  try
    for iWorkItem := 0 to owWorkItemQueue.Count - 1 do
      queuedItems.Add(owWorkItemQueue[iWorkItem]);
    owWorkItemQueue.Clear;
    CountQueued.Value := 0;
    for iWorkItem := 0 to queuedItems.Count - 1 do begin
      workItem := TOTPWorkItem(queuedItems[iWorkItem]);
      workItem.TerminateTask(EXIT_THREADPOOL_CANCELLED, 'Cancelled');
      RequestCompleted(workItem, nil);
    end; // for iWorkItem
  finally FreeAndNil(queuedItems); end;
  {$IFDEF LogThreadPool}Log('Stopping all threads', []); {$ENDIF LogThreadPool}
  for iWorker := 0 to owIdleWorkers.Count - 1 do
    StopThread(TOTPWorkerThread(owIdleWorkers[iWorker]));
  owIdleWorkers.Clear;
  for iWorker := 0 to owRunningWorkers.Count - 1 do
    StopThread(TOTPWorkerThread(owRunningWorkers[iWorker]));
  owRunningWorkers.Clear;
  CountRunning.Value := 0;
  endWait_ms := {$IFDEF MSWINDOWS} DSiTimeGetTime64 {$ELSE} TStopWatch.GetTimeStamp {$ENDIF} + int64(WaitOnTerminate_sec.Value) * 1000;
  while (endWait_ms > {$IFDEF MSWINDOWS} DSiTimeGetTime64 {$ELSE} TStopWatch.GetTimeStamp {$ENDIF}) and (NumRunningStoppedThreads > 0) do
  begin
    ProcessMessages;
    // TODO 1 -oPrimoz Gabrijelcic : ! what happens here during CancelAll? can the task die? !
    Sleep(10);
  end;
  for iWorker := 0 to owStoppingWorkers.Count - 1 do begin
    worker := TOTPWorkerThread(owStoppingWorkers[iWorker]);
    worker.Asy_TerminateWorkItem(workItem);
    FreeAndNil(worker);
  end;
  owStoppingWorkers.Clear;
end; { TOTPWorker.InternalStop }

function TOTPWorker.LocateThread(threadID: DWORD): TOTPWorkerThread;
var
  oThread: pointer;
begin
  for oThread in owRunningWorkers do begin
    Result := TOTPWorkerThread(oThread);
    if Result.threadID = threadID then
      Exit;
  end;
  for oThread in owIdleWorkers do begin
    Result := TOTPWorkerThread(oThread);
    if Result.threadID = threadID then
      Exit;
  end;
  for oThread in owStoppingWorkers do begin
    Result := TOTPWorkerThread(oThread);
    if Result.threadID = threadID then
      Exit;
  end;
  Result := nil;
end; { TOTPWorker.LocateThread }

procedure TOTPWorker.Log(const msg: string; const params: array of const );
begin
  {$IFDEF LogThreadPool}
  OutputDebugString(PChar(Format(msg, params)));
  {$ENDIF LogThreadPool}
end; { TOTPWorker.Log }

procedure TOTPWorker.MaintainanceTimer;
var
  iWorker: integer;
  worker : TOTPWorkerThread;
begin
  PruneWorkingQueue;
  if IdleWorkerThreadTimeout_sec > 0 then begin
    iWorker := 0;
    while (owIdleWorkers.Count > MinWorkers.Value) and
          (iWorker < owIdleWorkers.Count) do
    begin
      worker := TOTPWorkerThread(owIdleWorkers[iWorker]);
      if (worker.StartStopping_ms = 0) and
        ((worker.StartIdle_ms + int64(IdleWorkerThreadTimeout_sec.Value) * 1000)
         < {$IFDEF MSWINDOWS} DSiTimeGetTime64 {$ELSE} TStopWatch.GetTimeStamp {$ENDIF}) then
      begin
        {$IFDEF LogThreadPool}Log(
          'Destroying idle thread %s because it was idle for more than %d seconds',
          [worker.Description, IdleWorkerThreadTimeout_sec.Value]);
        {$ENDIF LogThreadPool}
        owIdleWorkers.Delete(iWorker);
        StopThread(worker);
      end
      else
        Inc(iWorker);
    end; // while
  end;
  iWorker := 0;
  while iWorker < owStoppingWorkers.Count do begin
    worker := TOTPWorkerThread(owStoppingWorkers[iWorker]);
    if worker.Stopped or ((worker.StartStopping_ms + int64(WaitOnTerminate_sec.Value) * 1000) <
                         {$IFDEF MSWINDOWS} DSiTimeGetTime64 {$ELSE} TStopWatch.GetTimeStamp {$ENDIF}) then
    begin
      if not worker.Stopped then begin
        {$IFDEF MSWINDOWS}
        SuspendThread(worker.Handle);
        {$ELSE}
        worker.Suspended := True;
        {$ENDIF}
        if worker.Stopped then begin
          {$IFDEF MSWINDOWS}
          ResumeThread(worker.Handle);
          {$ELSE}
          worker.Suspended := False;
          {$ENDIF}
          break; // while
        end;
        {$IFDEF MSWINDOWS}
        TerminateThread(worker.Handle, cardinal(-1));
        {$ELSE}
        worker.Terminate;
        {$ENDIF}
        ForwardThreadDestroying(worker.threadID, tpoKillThread, worker);
      end
      else begin
        {$IFDEF LogThreadPool}Log('Removing stopped thread %s', [worker.Description]);{$ENDIF LogThreadPool}
      end;
      owStoppingWorkers.Delete(iWorker);
      FreeAndNil(worker);
    end
    else
      Inc(iWorker);
  end;
end; { TOTPWorker.MaintainanceTimer }

procedure TOTPWorker.CheckIdleQueue;
var
  worker: TOTPWorkerThread;
  workItem: TOTPWorkItem;
begin
  if owDestroying then
    Exit;

  if (owWorkItemQueue.Count > 0) and
     ((owIdleWorkers.Count > 0) or (owRunningWorkers.Count < MaxExecuting.Value)) then
  begin
    workItem := TOTPWorkItem(owWorkItemQueue[0]);
    owWorkItemQueue.Delete(0);
    CountQueued.Decrement;
    {$IFDEF LogThreadPool}Log('Dequeueing %s ', [workItem.Description]);{$ENDIF LogThreadPool}
    ScheduleNext(workItem);
  end;

  // spin up threads
  while ((owIdleWorkers.Count + CountRunning.Value) < MinWorkers.Value) do begin
    worker := CreateWorker;
    owIdleWorkers.Add(worker);
  end;
end; { TOTPWorker.CheckIdleQueue }

function TOTPWorker.CreateWorker: TOTPWorkerThread;
begin
  Result := TOTPWorkerThread.Create(owThreadDataFactory);
  Task.RegisterComm(Result.OwnerCommEndpoint);
  Result.Start;
end; { TOTPWorker.CreateWorker }

procedure TOTPWorker.MsgCompleted(var msg: TOmniMessage);
begin
  ProcessCompletedWorkItem(TOTPWorkItem(msg.MsgData.AsObject));
end; { TOTPWorker.MsgCompleted }

procedure TOTPWorker.MsgThreadCreated(var msg: TOmniMessage);
begin
  ForwardThreadCreated(msg.MsgData);
end; { TOTPWorker.MsgThreadCreated }

procedure TOTPWorker.MsgThreadDestroying(var msg: TOmniMessage);
begin
  ForwardThreadDestroying(msg.MsgData, tpoDestroyThread);
end; { TOTPWorker.MsgThreadDestroying }

/// <summary>Counts number of threads in the 'stopping' queue that are still doing work.</summary> 
/// <since>2007-07-10</since> 
function TOTPWorker.NumRunningStoppedThreads: integer;
var
  iThread: integer;
  worker : TOTPWorkerThread;
begin
  Result := 0;
  for iThread := 0 to owStoppingWorkers.Count - 1 do begin
    worker := TOTPWorkerThread(owStoppingWorkers[iThread]);
    if not worker.Stopped then
      Inc(Result);
  end; // for iThread 
end; { TOTPWorker.NumRunningStoppedThreads }

procedure TOTPWorker.ProcessCompletedWorkItem(workItem: TOTPWorkItem);
var
  worker: TOTPWorkerThread;
begin
  worker := workItem.Thread;
  {$IFDEF LogThreadPool}Log('Thread %s completed request %s',
    [worker.Description, workItem.Description]); {$ENDIF LogThreadPool}
  if owDestroying then begin
    FreeAndNil(workItem);
    Exit;
  end;
  {$IFDEF LogThreadPool}
  Log('Thread %s completed request %s', [worker.Description, workItem.Description]);
  Log('Destroying %s', [workItem.Description]);
  {$ENDIF LogThreadPool}
  {$IFDEF MSWINDOWS}
  if assigned(owMonitorObserver) then
    owMonitorObserver.Send(COmniPoolMsg, 0, cardinal
      (TOmniThreadPoolMonitorInfo.Create(owUniqueID, workItem.UniqueID)));
  {$ENDIF MSWINDOWS}
  FreeAndNil(workItem);
  if owRunningWorkers.IndexOf(worker) < 0 then
    worker := nil;
  if assigned(worker) then begin // move it back to the idle queue 
    owRunningWorkers.Extract(worker);
    CountRunning.Decrement;
    if (not worker.RemoveFromPool) and
      ((MaxExecuting.Value < 0) or (owRunningWorkers.Count < MaxExecuting.Value)) then
    begin
      worker.StartIdle_ms := {$IFDEF MSWINDOWS} DSiTimeGetTime64 {$ELSE} TStopWatch.GetTimeStamp {$ENDIF};
      owIdleWorkers.Add(worker);
      {$IFDEF LogThreadPool}Log(
        'Thread %s moved back to the idle list, num idle = %d, num running = %d[%d]'
          , [worker.Description, owIdleWorkers.Count, owRunningWorkers.Count,
        MaxExecuting.Value]); {$ENDIF LogThreadPool}
    end
    else begin
      {$IFDEF LogThreadPool}Log(
        'Destroying thread %s, num idle = %d, num running = %d[%d]',
        [worker.Description, owIdleWorkers.Count, owRunningWorkers.Count,
        MaxExecuting.Value]); {$ENDIF LogThreadPool}
      StopThread(worker);
    end;
  end;
  CheckIdleQueue;
end; { TOTPWorker.ProcessCompletedWorkItem }

procedure TOTPWorker.PruneWorkingQueue;
var
  errorMsg      : string;
  iWorkItem     : integer;
  maxWaitTime_ms: int64;
  workItem      : TOTPWorkItem;
begin
  if MaxQueued.Value > 0 then begin
    while owWorkItemQueue.Count > MaxQueued.Value do begin
      workItem := TOTPWorkItem(owWorkItemQueue[owWorkItemQueue.Count - 1]);
      {$IFDEF LogThreadPool}Log(
        'Removing request %s from work item queue because queue length > %d',
        [workItem.Description, MaxQueued.Value]); {$ENDIF LogThreadPool}
      owWorkItemQueue.Delete(owWorkItemQueue.Count - 1);
      CountQueued.Decrement;
      errorMsg := Format('Execution queue is too long (%d work items)',
        [owWorkItemQueue.Count]);
      workItem.TerminateTask(EXIT_THREADPOOL_QUEUE_TOO_LONG, errorMsg);
      RequestCompleted(workItem, nil);
    end; // while
  end;
  if MaxQueuedTime_sec.Value > 0 then begin
    iWorkItem := 0;
    while iWorkItem < owWorkItemQueue.Count do begin
      workItem := TOTPWorkItem(owWorkItemQueue[iWorkItem]);
      maxWaitTime_ms := workItem.Scheduled_ms + int64(MaxQueuedTime_sec.Value) * 1000;
      if maxWaitTime_ms > {$IFDEF MSWINDOWS} DSiTimeGetTime64 {$ELSE} TStopWatch.GetTimeStamp {$ENDIF} then
        Inc(iWorkItem)
      else begin
        {$IFDEF LogThreadPool}Log(
          'Removing request %s from work item queue because it is older than %d seconds',
          [workItem.Description, MaxQueuedTime_sec.Value]); {$ENDIF LogThreadPool}
        owWorkItemQueue.Delete(iWorkItem);
        CountQueued.Decrement;
        errorMsg := Format('Maximum queued time exceeded.' +
            ' Pool = %0:s, Now = %1:s, Max executing = %2:d,' +
            ' Removed entry queue time = %3:s, Removed entry description = %4:s.'
            + ' Active entries: %5:s', [ { 0 } owName,
          { 1 } FormatDateTime('hh:nn:ss', Now), { 2 } MaxExecuting.Value,
          { 3 } FormatDateTime('hh:nn:ss', workItem.ScheduledAt),
          { 4 } workItem.Description, { 5 } ActiveWorkItemDescriptions]);
        workItem.TerminateTask(EXIT_THREADPOOL_STALE_TASK, errorMsg);
        RequestCompleted(workItem, nil);
      end;
    end; // while
  end;
end; { TOTPWorker.PruneWorkingQueue }

procedure TOTPWorker.RemoveMonitor;
begin
  {$IFDEF MSWINDOWS}
  FreeAndNil(owMonitorObserver);
  {$ENDIF MSWINDOWS}
end; { TOTPWorker.RemoveMonitor }

procedure TOTPWorker.RequestCompleted(workItem: TOTPWorkItem;
  worker: TOTPWorkerThread);
begin
  workItem.Thread := worker;
  ProcessCompletedWorkItem(workItem);
end; { TOTPWorker.RequestCompleted }

procedure TOTPWorker.Schedule(var workItem: TOTPWorkItem);
begin
  CountQueuedLock.Acquire;
  try
    CountQueued.Decrement;
    ScheduleNext(workItem);
  finally CountQueuedLock.Release; end;
  PruneWorkingQueue;
end; { TOTPWorker.Schedule }

procedure TOTPWorker.ScheduleNext(workItem: TOTPWorkItem);
var
  groupAffinity: TOTPGroupAffinity;
  worker       : TOTPWorkerThread;
begin
  worker := nil;
  if (MaxExecuting = -1) or (owRunningWorkers.Count < MaxExecuting.Value) then begin
    if owIdleWorkers.Count > 0 then begin
      worker := TOTPWorkerThread(owIdleWorkers[owIdleWorkers.Count - 1]);
      owIdleWorkers.Delete(owIdleWorkers.Count - 1);
      owRunningWorkers.Add(worker);
      CountRunning.Increment;
      {$IFDEF LogThreadPool}Log(
        'Allocated thread from idle pool, num idle = %d, num running = %d[%d]',
        [owIdleWorkers.Count, owRunningWorkers.Count, MaxExecuting.Value]);
      {$ENDIF LogThreadPool}
    end
    else begin
      worker := CreateWorker;
      owRunningWorkers.Add(worker);
      CountRunning.Increment;
      {$IFDEF LogThreadPool}Log(
        'Created new thread %s, num idle = %d, num running = %d[%d]',
        [worker.Description, owIdleWorkers.Count, owRunningWorkers.Count,
        MaxExecuting.Value]); {$ENDIF LogThreadPool}
    end;
  end;
  if assigned(worker) then begin
    {$IFDEF LogThreadPool}Log('Started %s', [workItem.Description]);{$ENDIF LogThreadPool}
    workItem.StartedAt := Now;
    workItem.Thread := worker;
    workItem.GroupAffinity := owScheduler.Next;
    worker.OwnerCommEndpoint.Send(MSG_RUN, workItem);
  end
  else begin
    {$IFDEF LogThreadPool}Log('Queued %s ', [workItem.Description]);{$ENDIF LogThreadPool}
    owWorkItemQueue.Add(workItem);
    CountQueued.Increment;
    if (MaxQueued > 0) and (owWorkItemQueue.Count >= MaxQueued.Value) then
      PruneWorkingQueue;
  end;
end; { TOTPWorker.ScheduleNext }

procedure TOTPWorker.SetAffinity(const value: TOmniValue);
begin
  owAffinity.Assign(value.AsInterface as IOmniIntegerSet);
  UpdateScheduler;
end; { TOTPWorker.SetAffinity }

procedure TOTPWorker.SetMonitor(const params: TOmniValue);
var
  {$IFDEF MSWINDOWS}
  hWindow  : THandle;
  {$ENDIF MSWINDOWS}
  waitParam: TOmniValue;
begin
  {$IFDEF MSWINDOWS}
  hWindow := params[0];
  if not assigned(owMonitorObserver) then
    owMonitorObserver :=
      CreateContainerWindowsMessageObserver(hWindow, COmniPoolMsg, 0, 0)
  else if owMonitorObserver.Handle <> hWindow then
    raise Exception.Create(
      'TOTPWorker.SetMonitor: Task can be only monitored with a single monitor'
      );
  {$ENDIF MSWINDOWS}
  waitParam := params[1];
  (waitParam.AsObject as TOmniWaitableValue).Signal;
end; { TOTPWorker.SetMonitor }

procedure TOTPWorker.SetName(const name: TOmniValue);
begin
  owName := name;
end; { TOTPWorker.SetName }

procedure TOTPWorker.SetNUMANodes(const value: TOmniValue);
begin
  owNUMANodes.Assign(value.AsInterface as IOmniIntegerSet);
  UpdateScheduler;
end; { TOTPWorker.SetNUMANodes }

procedure TOTPWorker.SetProcessorGroups(const value: TOmniValue);
begin
  owProcessorGroups.Assign(value.AsInterface as IOmniIntegerSet);
  UpdateScheduler;
end; { TOTPWorker.SetProcessorGroups }

procedure TOTPWorker.SetThreadDataFactory(const threadDataFactory: TOmniValue);
var
  factoryData: TOTPThreadDataFactoryData;
begin
  factoryData := threadDataFactory.AsObject as TOTPThreadDataFactoryData;
  owThreadDataFactory := factoryData.Executable;
  FreeAndNil(factoryData);
end; { TOTPWorker.SetThreadDataFactory }

/// <summary>Move the thread to the 'stopping' list and tell it to CancelAll.<para> 
/// Thread is guaranted not to be in 'idle' or 'working' list when StopThread is called.</para></summary> 
/// <since>2007-07-10</since>
procedure TOTPWorker.StopThread(worker: TOTPWorkerThread);
begin
  {$IFDEF LogThreadPool}Log('Stopping worker thread %s', [worker.Description]);{$ENDIF LogThreadPool}
  owStoppingWorkers.Add(worker);
  worker.StartStopping_ms := {$IFDEF MSWINDOWS} DSiTimeGetTime64 {$ELSE} TStopWatch.GetTimeStamp {$ENDIF};
  worker.Asy_Stop; // have to force asynchronous stop as the worker thread may be stuck in the ExecuteWorkItem
  worker.OwnerCommEndpoint.Send(MSG_STOP);
  {$IFDEF LogThreadPool}Log('num stopped = %d', [owStoppingWorkers.Count]);{$ENDIF LogThreadPool}
end; { TOTPWorker.StopThread }

procedure TOTPWorker.UpdateScheduler;
begin
  owScheduler.Update(owAffinity, owProcessorGroups, owNUMANodes);
  MaxExecuting.Value := owScheduler.Count;
end; { TOTPWorker.UpdateScheduler }

{ TOTPThreadDataFactoryData }

constructor TOTPThreadDataFactoryData.Create(const executable:
  TOTPThreadDataFactoryFunction);
begin
  inherited Create;
  tdfdExecutable := TOTPThreadDataFactory.Create(executable);
end; { TOTPThreadDataFactoryData.Create }

constructor TOTPThreadDataFactoryData.Create(const executable:
  TOTPThreadDataFactoryMethod);
begin
  inherited Create;
  tdfdExecutable := TOTPThreadDataFactory.Create(executable);
end; { TOTPThreadDataFactoryData.Create }

{ TOmniThreadPool }

constructor TOmniThreadPool.Create(const name: string);
begin
  inherited Create;
  {$IFDEF LogThreadPool}Log('Creating thread pool %p [%s]', [pointer(Self), name]);{$ENDIF LogThreadPool}
  otpPoolName := name;
  otpUniqueID := OtlUID.Increment;
  otpWorker := TOTPWorker.Create(name, otpUniqueID);
  otpWorkerTask := CreateTask
    (otpWorker, Format('OmniThreadPool manager %s', [name])).Run;
  otpWorkerTask.WaitForInit;
  otpAffinity := TOmniIntegerSet.Create;
  otpAffinity.OnChange := NotifyAffinityChanged;
  {$IFDEF OTL_NUMASupport}
  otpNUMANodes := TOmniIntegerSet.Create;
  otpNUMANodes.OnChange := NotifyNUMANodesChanged;
  otpProcessorGroups := TOmniIntegerSet.Create;
  otpProcessorGroups.OnChange := NotifyProcessorGroupsChanged;
  {$ENDIF OTL_NUMASupport}
end; { TOmniThreadPool.Create }

destructor TOmniThreadPool.Destroy;
begin
  {$IFDEF LogThreadPool}Log('Destroying thread pool %p', [pointer(Self), otpPoolName]);{$ENDIF LogThreadPool}
  otpWorkerTask.Terminate;
  inherited;
end; { TOmniThreadPool.Destroy }

/// <returns>True: Normal exit, False: Thread was killed.</returns>
{$WARN NO_RETVAL OFF}
// starting with XE, Delphi complains that result is not always assigned
function TOmniThreadPool.Cancel(taskID: int64): boolean;
var
  res: TOmniWaitableValue;
begin
  res := TOmniWaitableValue.Create;
  try
    otpWorkerTask.Invoke(@TOTPWorker.Cancel, [taskID, res]);
    res.WaitFor(INFINITE);
    Result := res.Value;
  finally FreeAndNil(res); end;
end; { TOmniThreadPool.Cancel }
{$WARN NO_RETVAL ON}

procedure TOmniThreadPool.CancelAll;
var
  res: TOmniWaitableValue;
begin
  res := TOmniWaitableValue.Create;
  try
    otpWorkerTask.Invoke(@TOTPWorker.CancelAll, res);
    res.WaitFor(INFINITE);
  finally FreeAndNil(res); end;
end; { TOmniThreadPool.CancelAll }

function TOmniThreadPool.CountExecuting: integer;
begin
  Result := WorkerObj.CountRunning.Value;
end; { TOmniThreadPool.CountExecuting }

function TOmniThreadPool.CountQueued: integer;
begin
  WorkerObj.CountQueuedLock.Acquire;
  try
    Result := WorkerObj.CountQueued.Value;
  finally WorkerObj.CountQueuedLock.Release; end;
end; { TOmniThreadPool.CountQueued }

function TOmniThreadPool.GetAffinity: IOmniIntegerSet;
begin
  Result := otpAffinity;
end; { TOmniThreadPool.GetAffinity }

function TOmniThreadPool.GetIdleWorkerThreadTimeout_sec: integer;
begin
  Result := WorkerObj.IdleWorkerThreadTimeout_sec.Value;
end; { TOmniThreadPool.GetIdleWorkerThreadTimeout_sec }

function TOmniThreadPool.GetMaxExecuting: integer;
begin
  Result := WorkerObj.MaxExecuting.Value;
end; { TOmniThreadPool.GetMaxExecuting }

function TOmniThreadPool.GetMaxQueued: integer;
begin
  Result := WorkerObj.MaxQueued.Value;
end; { TOmniThreadPool.GetMaxQueued }

function TOmniThreadPool.GetMaxQueuedTime_sec: integer;
begin
  Result := WorkerObj.MaxQueuedTime_sec.Value;
end; { TOmniThreadPool.GetMaxQueuedTime_sec }

function TOmniThreadPool.GetMinWorkers: integer;
begin
  Result := WorkerObj.MinWorkers.Value;
end; { TOmniThreadPool.GetMinWorkers }

function TOmniThreadPool.GetName: string;
begin
  Result := otpPoolName;
end; { TOmniThreadPool.GetName }

{$IFDEF OTL_NUMASupport}
function TOmniThreadPool.GetNUMANodes: IOmniIntegerSet;
begin
  Result := otpNUMANodes;
end; { TOmniThreadPool.GetNUMANodes }

function TOmniThreadPool.GetProcessorGroups: IOmniIntegerSet;
begin
  Result := otpProcessorGroups;
end; { TOmniThreadPool.GetProcessorGroups }
{$ENDIF OTL_NUMASupport}

function TOmniThreadPool.GetUniqueID: int64;
begin
  Result := otpUniqueID;
end; { TOmniThreadPool.GetUniqueID }

function TOmniThreadPool.GetWaitOnTerminate_sec: integer;
begin
  Result := WorkerObj.WaitOnTerminate_sec.Value;
end; { TOmniThreadPool.GetWaitOnTerminate_sec }

function TOmniThreadPool.IsIdle: boolean;
begin
  if CountQueued <> 0 then
    Result := false
  else if CountExecuting <> 0 then
    Result := false
  else
    Result := true;
end; { TOmniThreadPool.IsIdle }

procedure TOmniThreadPool.Log(const msg: string; const params: array of const);
begin
  {$IFDEF LogThreadPool}
  OutputDebugString(PChar(Format(msg, params)));
  {$ENDIF LogThreadPool}
end; { TGpThreadPool.Log }

function TOmniThreadPool.MakeIntegerSetCopy(const value: IOmniIntegerSet): TOmniValue;
var
  copy: IOmniIntegerSet;
begin
  copy := TOmniIntegerSet.Create;
  copy.Assign(value);
  Result.AsInterface := copy;
end; { TOmniThreadPool.MakeIntegerSetCopy }

function TOmniThreadPool.MonitorWith(const monitor: IOmniThreadPoolMonitor):
  IOmniThreadPool;
begin
  {$IFDEF MSWINDOWS}
  monitor.Monitor(Self);
  {$ENDIF MSWINDOWS}
  Result := Self;
end; { TOmniThreadPool.MonitorWith }

procedure TOmniThreadPool.NotifyAffinityChanged(const value: IOmniIntegerSet);
begin
  otpWorkerTask.Invoke(@TOTPWorker.SetAffinity, MakeIntegerSetCopy(value));
end; { TOmniThreadPool.NotifyAffinityChanged }

{$IFDEF OTL_NUMASupport}
procedure TOmniThreadPool.NotifyNUMANodesChanged(const value: IOmniIntegerSet);
begin
  otpWorkerTask.Invoke(@TOTPWorker.SetNUMANodes, MakeIntegerSetCopy(value));
end; { TOmniThreadPool.NotifyNUMANodesChanged }

procedure TOmniThreadPool.NotifyProcessorGroupsChanged(const value: IOmniIntegerSet);
begin
  otpWorkerTask.Invoke(@TOTPWorker.SetProcessorGroups, MakeIntegerSetCopy(value));
end; { TOmniThreadPool.NotifyProcessorGroupsChanged }
{$ENDIF OTL_NUMASupport}

function TOmniThreadPool.RemoveMonitor: IOmniThreadPool;
begin
  otpWorkerTask.Invoke(@TOTPWorker.RemoveMonitor);
  Result := Self;
end; { TOmniThreadPool.RemoveMonitor }

procedure TOmniThreadPool.Schedule(const task: IOmniTask);
begin
  WorkerObj.CountQueued.Increment;
  otpWorkerTask.Invoke(@TOTPWorker.Schedule, TOTPWorkItem.Create(task));
end; { TOmniThreadPool.Schedule }

procedure TOmniThreadPool.SetIdleWorkerThreadTimeout_sec(value: integer);
begin
  WorkerObj.IdleWorkerThreadTimeout_sec.Value := value;
end; { TOmniThreadPool.SetIdleWorkerThreadTimeout_sec }

procedure TOmniThreadPool.SetMaxExecuting(value: integer);
begin
  WorkerObj.MaxExecuting.Value := value;
  otpWorkerTask.Invoke(@TOTPWorker.CheckIdleQueue);
end; { TOmniThreadPool.SetMaxExecuting }

procedure TOmniThreadPool.SetMaxQueued(value: integer);
begin
  WorkerObj.MaxQueued.Value := value;
  otpWorkerTask.Invoke(@TOTPWorker.PruneWorkingQueue);
end; { TOmniThreadPool.SetMaxQueued }

procedure TOmniThreadPool.SetMaxQueuedTime_sec(value: integer);
begin
  WorkerObj.MaxQueuedTime_sec.Value := value;
  otpWorkerTask.Invoke(@TOTPWorker.PruneWorkingQueue);
end; { TOmniThreadPool.SetMaxQueuedTime_sec }

procedure TOmniThreadPool.SetMinWorkers(value: integer);
begin
  WorkerObj.MinWorkers.Value := value;
  otpWorkerTask.Invoke(@TOTPWorker.CheckIdleQueue);
end; { TOmniThreadPool.SetMinWorkers }

function TOmniThreadPool.SetMonitor(hWindow: THandle): IOmniThreadPool;
var
  res: TOmniWaitableValue;
begin
  res := TOmniWaitableValue.Create;
  try
    otpWorkerTask.Invoke(@TOTPWorker.SetMonitor, [hWindow, res]);
    res.WaitFor(INFINITE);
  finally FreeAndNil(res); end;
  Result := Self;
end; { TOmniThreadPool.SetMonitor }

procedure TOmniThreadPool.SetName(const value: string);
begin
  otpPoolName := value;
  otpWorkerTask.Invoke(@TOTPWorker.SetName, value);
end; { TOmniThreadPool.SetName }

procedure TOmniThreadPool.SetNUMANodes(const value: IOmniIntegerSet);
begin
  otpNUMANodes.Assign(value);
end; { TOmniThreadPool.SetNUMANodes }

procedure TOmniThreadPool.SetProcessorGroups(const value: IOmniIntegerSet);
begin
  otpProcessorGroups.Assign(value);
end; { TOmniThreadPool.SetProcessorGroups }

procedure TOmniThreadPool.SetThreadDataFactory(const value: TOTPThreadDataFactoryMethod);
begin
  otpThreadDataFactory := TOTPThreadDataFactory.Create(value);
  otpWorkerTask.Invoke(@TOTPWorker.SetThreadDataFactory,
    TOTPThreadDataFactoryData.Create(value));
end; { TOmniThreadPool.SetThreadDataFactory }

procedure TOmniThreadPool.SetThreadDataFactory(const value:
  TOTPThreadDataFactoryFunction);
begin
  otpThreadDataFactory := TOTPThreadDataFactory.Create(value);
  otpWorkerTask.Invoke(@TOTPWorker.SetThreadDataFactory,
    TOTPThreadDataFactoryData.Create(value));
end; { TOmniThreadPool.SetThreadDataFactory }

procedure TOmniThreadPool.SetWaitOnTerminate_sec(value: integer);
begin
  WorkerObj.WaitOnTerminate_sec.Value := value;
end; { TOmniThreadPool.SetWaitOnTerminate_sec }

function TOmniThreadPool.WorkerObj: TOTPWorker;
begin
  Result := (otpWorker.Implementor as TOTPWorker);
end; { TOmniThreadPool.WorkerObj }

{ TOTPGroupAffinity }

constructor TOTPGroupAffinity.Create(group: integer; affinity: int64);
begin
  inherited Create;
  FGroup := group;
  Self.Affinity := affinity;
end; { TOTPGroupAffinity.Create }

procedure TOTPGroupAffinity.SetAffinity(const value: int64);
var
  affSet: IOmniIntegerSet;
begin
  FAffinity := value;
  affSet := TOmniIntegerSet.Create;
  affSet.AsMask := affinity;
  FProcCount := affSet.Count;
end; { TOTPGroupAffinity.SetAffinity }

{ TOTPWorkerScheduler }

constructor TOTPWorkerScheduler.Create;
begin
  inherited Create;
  owsClusters := TObjectList.Create;
end; { TOTPWorkerScheduler.Create }

destructor TOTPWorkerScheduler.Destroy;
begin
  FreeAndNil(owsClusters);
  inherited;
end; { TOTPWorkerScheduler.Destroy }

function CompareGroupAffinity(item1, item2: pointer): integer;
var
  aff1: TOTPGroupAffinity absolute item1;
  aff2: TOTPGroupAffinity absolute item2;
begin
  Result := CompareValue(aff1.Group, aff2.Group);
  if Result = 0 then
    Result := CompareValue(aff1.Affinity, aff2.Affinity);
end; { CompareGroupAffinity }

procedure TOTPWorkerScheduler.ApplyAffinityMask(const affinity: IOmniIntegerSet);
var
  affinityMask: int64;
  i           : integer;
begin
  if affinity.Count > 0 then begin
    affinityMask := affinity.AsMask;
    for i := 0 to owsClusters.Count - 1 do
      Cluster[i].Affinity := Cluster[i].Affinity AND affinityMask;
  end;
end; { TOTPWorkerScheduler.ApplyAffinityMask }

function TOTPWorkerScheduler.Count: integer;
begin
  Result := Length(owsRoundRobin);
end; { TOTPWorkerScheduler.Count }

procedure TOTPWorkerScheduler.CreateInitialClusters(const processorGroups, numaNodes:
  IOmniIntegerSet);
{$IFDEF OTL_NUMASupport}
var
  envGroups   : IOmniProcessorGroups;
  envNodes    : IOmniNUMANodes;
  i           : integer;
  nodeInfo    : IOmniNUMANode;
{$ENDIF OTL_NUMASupport}
begin
  {$IFDEF OTL_NUMASupport}
  envGroups := Environment.ProcessorGroups;
  envNodes := Environment.NUMANodes;
  if numaNodes.Count > 0 then begin
    for i := 0 to numaNodes.Count - 1 do begin
      nodeInfo := envNodes.FindNode(numaNodes[i]);
      if not assigned(nodeInfo) then
        raise Exception.CreateFmt('TOTPWorkerScheduler.Update: Unknown NUMA node: %d', [numaNodes[i]]);
      if (processorGroups.Count = 0) or processorGroups.Contains(nodeInfo.GroupNumber) then
        owsClusters.Add(TOTPGroupAffinity.Create(nodeInfo.GroupNumber, nodeInfo.Affinity.AsMask));
    end;
  end
  else if processorGroups.Count > 0 then begin
    for i := 0 to processorGroups.Count - 1 do
      owsClusters.Add(TOTPGroupAffinity.Create(processorGroups[i], envGroups[processorGroups[i]].Affinity.AsMask));
  end
  else
    owsClusters.Add(TOTPGroupAffinity.Create(0, envGroups[0].Affinity.AsMask));
  {$ELSE}
  owsClusters.Add(TOTPGroupAffinity.Create(0, Environment.Process.Affinity.Mask));
  {$ENDIF OTL_NUMASupport}

  if owsClusters.Count = 0 then
    raise Exception.Create('TOTPWorkerScheduler.Update: All cores were filtered out');
end; { TOTPWorkerScheduler.CreateInitialClusters }

procedure TOTPWorkerScheduler.CreateRoundRobin;
var
  i         : integer;
  idx       : integer;
  j         : integer;
  totalCores: integer;
begin
  // Distribute load across cores as much as possible.
  owsNextCluster := 0;

  //n-dimensional Bresenham
  totalCores := 0;
  for i := 0 to owsClusters.Count - 1 do begin
    Cluster[i].Error := Cluster[i].ProcessorCount;
    Inc(totalCores, Cluster[i].ProcessorCount);
  end;
  SetLength(owsRoundRobin, totalCores);
  for i := 1 to totalCores do begin
    idx := FindHighestError;
    owsRoundRobin[i-1] := idx;
    Cluster[idx].Error := Cluster[idx].Error - totalCores;
    for j := 0 to owsClusters.Count - 1 do
      Cluster[j].Error := Cluster[j].Error + Cluster[j].ProcessorCount;
  end;
end; { TOTPWorkerScheduler.CreateRoundRobin }

function TOTPWorkerScheduler.FindHighestError: integer;
var
  i: integer;
begin
  Result := 0;
  for i := 1 to owsClusters.Count - 1 do
    if Cluster[i].Error > Cluster[Result].Error then
      Result := i;
end; { TOTPWorkerScheduler.FindHighestError }

function TOTPWorkerScheduler.GetCluster(idx: integer): TOTPGroupAffinity;
begin
  Result := TOTPGroupAffinity(owsClusters[idx]);
end; { TOTPWorkerScheduler.GetCluster }

function TOTPWorkerScheduler.IsSame(value1, value2: TOTPGroupAffinity): boolean;
begin
  Result := (value1.Group = value2.Group) and (value1.Affinity = value2.Affinity);
end; { TOTPWorkerScheduler.IsSame }

function TOTPWorkerScheduler.Next: TOmniGroupAffinity;
begin
  with Cluster[owsRoundRobin[owsNextCluster]] do
    Result := TOmniGroupAffinity.Create(Group, Affinity);
  Inc(owsNextCluster);
  if owsNextCluster > High(owsRoundRobin) then
    owsNextCluster := Low(owsRoundRobin);
end; { TOTPWorkerScheduler.Next }

procedure TOTPWorkerScheduler.RemoveDuplicateClusters;
var
  i: integer;
begin
  for i := owsClusters.Count - 2 downto 0 do
    if IsSame(Cluster[i], Cluster[i+1]) then
      owsClusters.Delete(i+1);
end; { TOTPWorkerScheduler.RemoveDuplicateClusters }

procedure TOTPWorkerScheduler.Update(affinity, processorGroups, numaNodes:
  IOmniIntegerSet);
begin
  owsClusters.Clear;
  CreateInitialClusters(processorGroups, numaNodes);
  ApplyAffinityMask(affinity);
  owsClusters.Sort(CompareGroupAffinity);
  RemoveDuplicateClusters;
  CreateRoundRobin;
end; { TOTPWorkerScheduler.Update }

initialization
finalization
  GOmniThreadPool := nil;
end.
