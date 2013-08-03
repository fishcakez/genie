%%
%% %CopyrightBegin%
%%
%% Copyright Ericsson AB 1996-2013. All Rights Reserved.
%% Copyright 2013, James Fish <james@fishcakez.com>
%%
%% The contents of this file are subject to the Erlang Public License,
%% Version 1.1, (the "License"); you may not use this file except in
%% compliance with the License. You should have received a copy of the
%% Erlang Public License along with this software. If not, it can be
%% retrieved online at http://www.erlang.org/.
%%
%% Software distributed under the License is distributed on an "AS IS"
%% basis, WITHOUT WARRANTY OF ANY KIND, either express or implied. See
%% the License for the specific language governing rights and limitations
%% under the License.
%%
%% %CopyrightEnd%
%%

%% @doc This module implements the really generic stuff for generic or
%% user defined behaviours that adhere to OTP design principles.
%%
%% The genie behaviour requires two callbacks. The first, `init_it/6', is called
%% after spawning and successfuly registring a process using `start/5,6' it will
%% be called as
%% `GenMod:init_it(Starter, Parent, Name, Mod, Args, Options)'. This
%% function carries out the initialising of the generic module `GenMod' and its
%% callback module `Mod'.
%%
%% As part of its initialising `GenMod' calls `Mod:init(Args)' to setup a state
%% for the callback module. Based on the returned value of `Mod:init/1'
%% `GenMod' must call `init_ack(Starter, Return)' to acknowledge the
%% result.
%%
%% `Starter' is an opaque term that contains the pid of the process that called
%% `start/5,6'. The pid can be retrieved using `starter_process/1'.
%%
%% `Parent' is also the pid of the process that called `start/5,6' if
%% the spawned process is linked (the second argument, `LinkP', is `link'). If
%% the processes are not linked (`LinkP' is `nolink'), `Parent' is the atom
%% `self', which means that the spawned process is not part of the supervision
%% tree.
%%
%% `Name' is the name the process was registered with in `start/6' or if no
%% registration took place (the process was spawned using `start/5') it is the
%% pid of the spawned process.
%%
%% `Mod' is the callback module that exports the functions required to exhibit
%% the generic behaviour (`GenMod').
%%
%% `Args' are the arguments to be passed to `Mod:init/1' to initialise the
%% process and so all generic behaviours require such a callback.
%%
%% `Options' are the options passed as the final argument to `start/5,6'. These
%% determine how the process should be spawned, how long to wait for
%% initialising to complete and the debug options for the process. To get the
%% debug options to be used with the `sys' module `debug_options/1,2' is used.
%%
%% The second callback is `async_timeout_info/4', which is called by a timer
%% process when the main process takes too long initialising. It is called as
%% `GenMod:async_timeout_info(Name, Mod, Args, Debug)'. The first three terms
%% are the same as above. The final term, `Debug', is the result of calling
%% `debug_options/2' on the `Options' passed to `start/5,6'. This `Debug' value
%% may be different to one used by the behaviour process if it is altered
%% during initialisation.
%%
%% An example with detailed inline comments, called `genie_basic', can be found
%% in the `examples' directory. It shows how to deal with system messages and
%% the other features of the `sys' module.
%% @end

-module(genie).
-compile({inline,[get_node/1]}).

%% API
-export([start/5, start/6, init_ack/2,
	 cast/3, cast_list/3,
	 send/3, send_list/3,
	 call/3, call/4,
	 call_list/3, call_list/4,
	 reply/2,
	 starter_mode/1, starter_process/1,
	 debug_options/1, debug_options/2,
	 format_status_header/2,
	 register_name/2, unregister_name/1,
	 whereis_name/1,
	 proc_name/1, proc_name/2, parent/0]).

%% Internal exports
-export([init_it/7, init_it/8]).

-define(default_timeout, 5000).

-type linkage() :: 'link' | 'nolink'.
-type local_name() :: atom().
-type global_name() :: term().
-type via_name() :: term().
-type emgr_name() :: {'local', local_name()}
		   | {'global', global_name()}
		   | {via, module(), via_name()}.

-type parent() :: pid() | self.

-opaque starter() :: pid() | {async, pid(), undefined | pid()}.

-type start_ret() :: {'ok', pid()}
		   | {ok, pid(), term()}
		   | 'ignore'
		   | {'error', term()}.

-type system_event() :: {'in', Msg :: term()}
		      | {'in', Msg :: term(), From :: term()}
		      | {'out', Msg :: term(), To :: term()}
		      | term().
-type debug_flag() :: 'trace' | 'log' | 'statistics' | 'debug'
		    | {'log', pos_integer()} | {'logfile', string()}
		    | {install, {fun((DbgFunState :: term(),
				      Event :: system_event(),
				      Misc :: term()) ->
					done | (DbgFunState2 :: term()))}}.
-type option() :: {'timeout', timeout()}
		| {'debug', [debug_flag()]}
		| {'spawn_opt', [proc_lib:spawn_option()]}
		| {'async', timeout()}.
-type options() :: [option()].

-type label() :: atom().
-opaque tag() :: reference().

-export_type([emgr_name/0, starter/0, options/0, tag/0]).

%%%=========================================================================
%%%  API
%%%=========================================================================

-callback init_it(Starter :: starter(), Parent :: parent(),
		  Name :: emgr_name(), Mod :: module(), Args :: term(),
		  Options :: options()) ->
    no_return().
-callback async_timeout_info(Name :: emgr_name() | pid(), Mod :: module(),
			     Args :: term(), Debug :: [sys:dbg_opt()]) ->
    term().

%% @doc Starts a generic process.
%%
%% The process is started in the same way as `start/6' except that it is not
%% registered.
%%
%% @see start/6

-spec start(GenMod, LinkP, Mod, Args, Options) -> Result when
      GenMod :: module(),
      LinkP :: linkage(),
      Mod :: module(),
      Args :: term(),
      Options :: options(),
      Result :: start_ret().

start(GenMod, LinkP, Mod, Args, Options) ->
    AsyncTimeout = async_timeout(Options),
    do_spawn(GenMod, LinkP, Mod, Args, Options, AsyncTimeout).

%% @doc Starts a generic process.
%%
%% `GenMod' is a module which adheres to OTP design principles and implements a
%% generic or user defined behaviour, with callback module `Mod'. While this
%% function will spawn (using `proc_lib') and register a process in accordance
%% with the OTP design principles the `GenMod' is responsible for providing the
%% required `sys' functionality such as `sys:handle_system_msg/6'.
%%
%% `LinkP' determines whether the process is linked to or not, `link' results in
%% a link begin created and `nolink' does not. In nearly all cases `start/6'
%% will be called by a supervisor and `LinkP' will be `link' so that the process
%% is part of the supervision tree. Otherwise the process will not be part of
%% the supervision tree and won't fully adhere to the OTP principles.
%%
%% The spawned process will attempt to registered itself according to `Name'.
%% `{local, LocalName}' will register the process locally with the atom
%% LocalName. `{global, GlobalName}' will register the process globally with the
%% term GlobalName. `{via, Module, ViaName}' will register the process by
%% calling `Module:register_name(ViaName, self())'. If registration fails
%% `{error, {already_started, Pid}}', where `Pid' is the currently registered
%% process (or possibly undefined), will be returned by `start/6' and the
%% process will exit with reason `normal' - never calling `GenMod:init_it/6'.
%%
%% `Options' is a list containing options for spawning and debugging the
%% process, it will be passed to `GenMod:init_it/6'. If `Options' contains
%% `{timeout, Timeout}' the spawned process will be killed if it does not
%% initialise within `Timeout' and `{error, timeout}' will be returned.
%%
%% The option `{debug, DebugFlags}' should be used by the GenMod to make use of
%% `sys:handle_debug/4'. `DebugFlags' is a list of options that can be passed
%% to `sys:debug_options', with an extra flag `debug' that represents both `log'
%% and `statistics'. `Options' should be passed to `debug_options/1,2', which
%% creates the `sys' debug options to be used with `sys:handle_debug/4'.
%%
%% The option `{spawn_opts, SpawnOpts}' will cause `SpawnOpts' to be passed as
%% the spawn options to the relevant `proc_lib' spawn function.
%%
%% @see sys:handle_system_msg/6
%% @see proc_lib:start_link/5
%% @see init_ack/2
%% @see debug_options/2
%% @see sys:handle_debug/4

-spec start(GenMod, LinkP, Name, Mod, Args, Options) -> Result when
      GenMod :: module(),
      LinkP :: linkage(),
      Name :: emgr_name(),
      Mod :: module(),
      Args :: term(),
      Options :: options(),
      Result :: start_ret().

start(GenMod, LinkP, Name, Mod, Args, Options) ->
    case whereis_name(Name) of
	undefined ->
	    AsyncTimeout = async_timeout(Options),
	    do_spawn(GenMod, LinkP, Name, Mod, Args, Options, AsyncTimeout);
	Pid ->
	    {error, {already_started, Pid}}
    end.

%% @doc Informs the caller of `start/5,6' that the spawned process has finished
%% its initialisation.
%%
%% `Starter' is the first argument passed to `GenMod:init_it/6'.
%%
%% A success will have `Return' as `{ok, self()}' or `{ok, self(), Info}, where
%% `Info' can be any term. In the case of failure `Return' is of the form
%% `{error, Reason}' where `Reason' can be any term, the process then exits with
%% the same reason by calling `exit(Reason)'. If no error occured but the
%% process is going to exit immediately (with reason `normal'), `Return' is the
%% atom `ignore'.
%%
%% Note that the caller of `start/5,6' blocks until it receives the
%% acknowledgment sent by `init_ack/2'.
%%
%% @see proc_lib:init_ack/2

-spec init_ack(Starter, Return) -> ok when
      Starter :: starter(),
      Return :: start_ret().

init_ack(Starter, Return) when is_pid(Starter) ->
    proc_lib:init_ack(Starter, Return);
init_ack({async, _Starter, AsyncTimer}, _Return) when is_pid(AsyncTimer) ->
    MonRef = erlang:monitor(process, AsyncTimer),
    AsyncTimer ! {ack, self()},
    unlink(AsyncTimer),
    Reason2 = receive
		  {'EXIT', AsyncTimer, Reason} ->
		      Reason
	      after
		  0 ->
		      noproc
	      end,
    receive
	{'DOWN', MonRef, _, _, normal} ->
	    ok;
	%% AsyncTimer died before monitor/2 call.
	{'DOWN', MonRef, _, _, noproc} ->
	    exit(Reason2);
	%% AsyncTimer's code failed or it was killed.
	{'DOWN', MonRef, _, _, Reason3} ->
	    exit(Reason3)
    end;
%% async with infinity timeout.
init_ack(_Starter, _Return) ->
    ok.

%% @doc Get the mode of initialisation a starter used.

-spec starter_mode(Starter) -> StarterMode when
      Starter :: starter(),
      StarterMode :: sync | async.

starter_mode(Pid) when is_pid(Pid) ->
    sync;
starter_mode({async, _, _}) ->
    async.

%% @doc Get the starter's pid from the opaque starter term.

-spec starter_process(Starter) -> Pid when
      Starter :: starter(),
      Pid :: pid().

starter_process(Pid) when is_pid(Pid) ->
    Pid;
starter_process({async, Pid, _}) when is_pid(Pid) ->
    Pid.

%% @doc Sends an asynchronous request to `Process' and returns ok immediately,
%% regardless of whether or not `Process' exists.
%%
%% `Process', the target of the cast, can take many forms apart from a pid.
%% It can be the name of a locally registered process, or if the it is
%% registered locally on a different node `{LocalName, Node}'. If the process is
%% registered globally `Process' is `{global, GlobalName}'. If registered via an
%% alternative module using `Module:register_name/2', `Process' is
%% `{via, Module, ViaName}'.
%%
%% `Label' is an atom used by the generic process to identify that the message
%% is a call, and possibly a particular type of call.
%%
%% `Request' is a term which communicates the meaning of the request in the cast
%% message.
%%
%% A message sent by `cast/3' takes the form `{Label, Request}' and may arrive
%% in a different to order to they are sent.

-spec cast(Process, Label, Request) -> ok when
      Process :: (Pid :: pid())
	       | LocalName
	       | ({LocalName, Node :: node()})
	       | ({global, GlobalName :: global_name()})
	       | ({via, Module :: module(), ViaName :: via_name()}),
      LocalName :: local_name(),
      Label :: label(),
      Request :: term().

cast({global, GlobalName}, Label, Request) ->
    Pid = global:whereis_name(GlobalName),
    do_cast(Pid, {Label, Request});
cast({via, Module, ViaName}, Label, Request) ->
    Pid = Module:whereis_name(ViaName, Request),
    do_cast(Pid, {Label, Request});
cast(LocalName, Label, Request) when is_atom(LocalName) ->
    do_cast(LocalName, {Label, Request});
cast({LocalName, Node} = Process, Label, Request)
  when is_atom(LocalName) andalso is_atom(Node) ->
    do_cast(Process, {Label, Request});
cast(Pid, Label, Request) when is_pid(Pid) ->
    do_cast(Pid, {Label, Request}).

%% @doc Sends asynchronous requests to a list of generic processes and
%% returns ok immediatly, regardless of whether or not any of the processes
%% exist.
%%
%% This function efficiently carries out a cast for each process in `Processes'.
%% It is equivalent to making several `cast/3' calls and collecting the results.
%%
%% `Processes' is a list of targets for the call. The elements of `Processes'
%% take the same form as the `Process' argument for `cast/3' with an additional
%% type: `{ProcessRef, Pid}'. This special case will make a call to `Pid' but
%% associate the result of the call with `ProcessRef'. `ProcessRef' can not be
%% the atom `global'.
%%
%% `Label' and `Request' are identical to their arguments in `cast/3'.
%%
%% There is no guarantee of message ordering when `cast_list/3' is called
%% multiple times.
%%
%% @see cast/3

-spec cast_list(Processes, Label, Request) -> ok when
      Processes :: [(Process | {ProcessRef, pid()})],
      Process :: (Pid :: pid())
	       | LocalName
	       | ({LocalName, Node :: node()})
	       | ({global, GlobalName :: global_name()})
	       | ({via, Module :: module(), ViaName :: via_name()}),
      ProcessRef :: term(),
      LocalName :: local_name(),
      Label :: label(),
      Request :: term().

cast_list(Processes, Label, Request) ->
    Msg = {Label, Request},
    _ = [do_cast_list(Process, Msg) || Process <- Processes],
    ok.

%% @doc Sends an asynchronous request to `Process' and returns ok.
%%
%% `Process', the target of the send, can take many forms apart from a pid.
%% It can be the name of a locally registered process, if no process is
%% associated with the name, a `badarg' error will be thrown. However if the
%% it is the name of a process registered locally on a different node,
%% `{LocalName, Node}', and the node does not exist or no process is associated
%% with `LocalName' no error will be thrown. If the process is registered
%% globally as `Globalname', `Process' is `{global, GlobalName}'. If no process
%% is assoicated globally with `GlobalName' a `badarg' error will be thrown. If
%% registered via an alternative module using `Module:register_name/2' as
%% `ViaName', `Process' is `{via, Module, ViaName}' and similarly if there is no
%% associated process a `badarg' error will be thrown.
%%
%% `Label' is an atom used by the generic process to identify that the message
%% is a send or cast, and possibly a particular type of send or cast.
%%
%% `Request' is a term which communicates the meaning of the request in the cast
%% message.
%%
%% `send/3' is different to `cast/3'. `send/3' will fail with reason `badarg' if
%% it is passed a name that is not associated with a process - and the name is
%% not of the form `{LocalName, Node}', whereas `cast/3' will always return ok.
%% Also `send/3' will block while trying to connect to another node, whereas
%% `cast/3' will not. This means that `send/3' messages will arrive in the order
%% they are sent - though there is no guarantee that all messages will be
%% delivered.
%%
%% `send/3' messages takes the same form as `cast/3' messages:
%% `{Label, Request}'.

-spec send(Process, Label, Request) -> ok when
      Process :: (Pid :: pid())
	       | LocalName
	       | ({LocalName, Node :: node()})
	       | ({global, GlobalName :: global_name()})
	       | ({via, Module :: module(), ViaName :: via_name()}),
      LocalName :: local_name(),
      Label :: label(),
      Request :: term().

send({global, GlobalName}, Label, Request) ->
    _ = global:send(GlobalName, {Label, Request}),
    ok;
send({via, Module, ViaName}, Label, Request) ->
    _ = Module:send(ViaName, {Label, Request}),
    ok;
send(LocalName, Label, Request) when is_atom(LocalName) ->
    erlang:send(LocalName, {Label, Request}),
    ok;
send({LocalName, Node} = Process, Label, Request)
  when is_atom(LocalName) andalso is_atom(Node) ->
    erlang:send(Process, {Label, Request}),
    ok;
send(Pid, Label, Request) when is_pid(Pid) ->
    erlang:send(Pid, {Label, Request}),
    ok.

%% @doc Sends asynchronous requests to a list of generic processes and
%% returns ok.
%%
%% This function efficiently carries out a cast for each process in `Processes'.
%% It is equivalent to making several `send/3' calls.
%%
%% `Processes' is a list of targets for the call. The elements of `Processes'
%% take the same form as the `Process' argument for `send/3' with an additional
%% type: `{ProcessRef, Pid}'. This special case will make a call to `Pid' but
%% associate the result of the call with `ProcessRef'. `ProcessRef' can not be
%% the atom `global'.
%%
%% `Label' and `Request' are identical to their arguments in `send/3'.
%%
%% If `send_list/3' is called twice, the messages in the first call will arrive
%% before those in the second - assuming they are delivered successfully.
%%
%% @see send/3

-spec send_list(Processes, Label, Request) -> ok when
      Processes :: [(Process | {ProcessRef, pid()})],
      Process :: (Pid :: pid())
	       | LocalName
	       | ({LocalName, Node :: node()})
	       | ({global, GlobalName :: global_name()})
	       | ({via, Module :: module(), ViaName :: via_name()}),
      ProcessRef :: term(),
      LocalName :: local_name(),
      Label :: label(),
      Request :: term().

send_list(Processes, Label, Request) ->
    Msg = {Label, Request},
    _ = [do_send_list(Process, Msg) || Process <- Processes],
    ok.

%% @doc Makes a synchronous call to a generic process.
%%
%% @equiv call(Process, Label, Request, 5000)

-spec call(Process, Label, Request) -> Result when
      Process :: (Pid :: pid())
	       | LocalName
	       | ({LocalName, Node :: node()})
	       | ({global, GlobalName :: global_name()})
	       | ({via, Module :: module(), ViaName :: via_name()}),
      LocalName :: local_name(),
      Label :: label(),
      Request :: term(),
      Result :: term().

%%% New call function which uses the new monitor BIF
%%% call(ServerId, Label, Request)
call(Process, Label, Request) -> 
    call(Process, Label, Request, ?default_timeout).

%% @doc Makes a synchronous call to a generic process.
%%
%% `Process', the target of the call, can take many forms apart form a pid. It
%% can be the name of a locally registered process, or if the it is registered
%% locally on a different node `{LocalName, Node}'. Note that
%% `{local, LocalName}' can not be used to call a process registered locally as
%% `LocalName'. If the process is registered globally `Process' is
%% `{global, GlobalName}'. If registered via an alternative module using
%% `Module:register_name/2', `Process' is `{via, Module, ViaName}'.
%%
%% `Label' is an atom used by the generic process to identify that the message
%% is a call, and possibly a particular type of call. For example `genie_server'
%% uses the atom `$gen_call' to identify calls.
%%
%% `Request' is a term which communicates the meaning of the request in the call
%% message.
%%
%% `Timeout' is the time a calling process will wait before exiting with reason
%% `timeout'.
%%
%% A message sent by `call/4' is of the form
%% `{Label, {self(), Tag} = From, Request}', where `self()' is the pid of the
%% calling process. `Tag' is a term that uniquely idenities the call. The
%% generic process receiving the call should reply using `reply(From, Reply)'.
%%
%% `call/4' will monitor the target process while waiting for a reply. If the
%% target process exits or does not exist `exit/1' will be called with a
%% suitable reason.
%%
%% If an exception raised by `call/4' is caught a reply could be in the calling
%% process' message queue, could arrive later or not at all.
%%
%% `call/4' takes advantage of an optimisation so that the whole message queue
%% does not need to be scanned for the reply.
%%
%% @see reply/2

-spec call(Process, Label, Request, Timeout) -> Result when
      Process :: (Pid :: pid())
	       | LocalName
	       | ({LocalName, Node :: node()})
	       | ({global, GlobalName :: global_name()})
	       | ({via, Module :: module(), ViaName :: via_name()}),
      LocalName :: atom(),
      Label :: label(),
      Request :: term(),
      Timeout :: timeout(),
      Result :: term().

%% Local or remote by pid
call(Pid, Label, Request, Timeout) 
  when is_pid(Pid), Timeout =:= infinity;
       is_pid(Pid), is_integer(Timeout), Timeout >= 0 ->
    do_call(Pid, Label, Request, Timeout);
%% Local by name
call(LocalName, Label, Request, Timeout) 
  when is_atom(LocalName), Timeout =:= infinity;
       is_atom(LocalName), is_integer(Timeout), Timeout >= 0 ->
    case whereis(LocalName) of
	Pid when is_pid(Pid) ->
	    do_call(Pid, Label, Request, Timeout);
	undefined ->
	    exit(noproc)
    end;
%% Global or via by name
call(Name, Label, Request, Timeout)
  when ((tuple_size(Name) == 2 andalso element(1, Name) == global)
	orelse
	  (tuple_size(Name) == 3 andalso element(1, Name) == via))
       andalso
       (Timeout =:= infinity orelse (is_integer(Timeout) andalso Timeout >= 0)) ->
    case whereis_name(Name) of
	Pid when is_pid(Pid) ->
	    Node = node(Pid),
 	    try do_call(Pid, Label, Request, Timeout)
 	    catch
 		exit:{nodedown, Node} ->
 		    %% A nodedown not yet detected by global,
 		    %% pretend that it was.
 		    exit(noproc)
	    end;
	undefined ->
	    exit(noproc)
    end;
%% Local by name in disguise
call({LocalName, Node}, Label, Request, Timeout)
  when Node =:= node(), Timeout =:= infinity;
       Node =:= node(), is_integer(Timeout), Timeout >= 0 ->
    call(LocalName, Label, Request, Timeout);
%% Remote by name
call({_LocalName, Node}=Process, Label, Request, Timeout)
  when is_atom(Node), Timeout =:= infinity;
       is_atom(Node), is_integer(Timeout), Timeout >= 0 ->
    if
 	node() =:= nonode@nohost ->
 	    exit({nodedown, Node});
 	true ->
 	    do_call(Process, Label, Request, Timeout)
    end.

%% @doc Makes simultaneous synchronous calls to a list of generic processes.
%%
%% @equiv call_list(Process, Label, Request, 5000)

-spec call_list(Processes, Label, Request) -> Result when
      Processes :: [(Process | {ProcessRef, pid()})],
      Process :: (Pid :: pid())
	       | LocalName
	       | ({LocalName, Node :: node()})
	       | ({global, GlobalName :: global_name()})
	       | ({via, Module :: module(), ViaName :: via_name()}),
      ProcessRef :: term(),
      LocalName :: local_name(),
      Label :: label(),
      Request :: term(),
      Result :: {(Replies :: [{(Process | ProcessRef), term()}]),
		 (BadProcess :: [(Process | ProcessRef)])}.

call_list(Processes, Label, Request) ->
    call_list(Processes, Label, Request, ?default_timeout).

%% @doc Makes simultaneous synchronous calls to a list of generic processes.
%%
%% This function efficiently carries out a call for each process in `Processes'.
%% It is equivalent to making parallel `call/4' calls and collecting the
%% results, except more efficient. A middleman process is used to make the
%% calls, which means that the process in call message will belong to the
%% middleman rather than the calling process.
%%
%% `Processes' is a list of targets for the call. The elements of `Processes'
%% take the same form as the `Process' argument for `call/4' with an additional
%% type: `{ProcessRef, Pid}'. This special case will make a call to `Pid' but
%% associate the result of the call with `ProcessRef'. `ProcessRef' can not be
%% the atom `global'.
%%
%% `Label' and `Request' are identical to their arguments in `call/4'.
%%
%% `Timeout' is the time a calling process will wait before assigning a
%% bad result with reason `timeout' to each unanswered call.
%%
%% Unlike `call/4' if a process exits before a response is received, or a
%% process does not exist, `call_list/4' will not exit with the same reason.
%% Instead results are split into a list of replies, `Replies' and error
%% reasons, `BadProcesses'. `Replies' is a list of tuple pairs where the first
%% element is the target process from `Processes', the second element is the
%% result of the call from that process. `BadProcesses' takes the same form
%% except the second element is the error reason. As noted above if the process
%% took the form `{ProcessRef, Pid}' then first element of its tuple will be
%% `ProcessRef'.
%%
%% @see call/4
%% @see reply/2

-spec call_list(Processes, Label, Request, Timeout) -> Result when
      Processes :: [(Process | {ProcessRef, pid()})],
      Process :: (Pid :: pid())
	       | LocalName
	       | ({LocalName, Node :: node()})
	       | ({global, GlobalName :: global_name()})
	       | ({via, Module :: module(), ViaName :: via_name()}),
      ProcessRef :: term(),
      LocalName :: local_name(),
      Label :: label(),
      Request :: term(),
      Timeout :: timeout(),
      Result :: {(Replies :: [{(Process | ProcessRef), term()}]),
		 (BadProcess :: [(Process | ProcessRef)])}.

call_list(Processes, Label, Request, Timeout)
  when is_list(Processes) andalso is_integer(Timeout) andalso Timeout >= 0 ->
    do_call_list(Processes, Label, Request, Timeout);
call_list(Processes, Label, Request, infinity) when is_list(Processes) ->
    do_call_list(Processes, Label, Request, infinity).

%% @doc Sends a reply to a client.
%%
%% `From' is taken from the call message tuple `{Label, From, Request}'. `From'
%% takes the form `{To, Tag}', where `To' is the pid that sent the call, and the
%% target of the reply. `Tag' is a unique term used to identify the message.
%%
%% It is possible that `To' is a middleman process (see `call_list/4') and so
%% `self()' should be included in the `Request' of a `call/4' or `call_list/4'
%% if the calling pid is required.
%%
%% @see call/4
%% @see call_list/4

-spec reply(From, Reply) -> Reply when
      From :: {To :: pid(), (Tag :: tag() | term())},
      Reply :: term().

reply({To, Tag}, Reply) when is_pid(To) ->
    Msg = {Tag, Reply},
    try To ! Msg catch _:_ -> Msg end.

%% @doc Get the sys debug structure from genie options.
%%
%% @equiv debug_options(self(), Options)

-spec debug_options(Options) -> [sys:dbg_opt()] when
      Options :: options().

debug_options(Options) ->
    debug_options(self(), Options).

%% @doc Get the sys debug structure from genie options.
%%
%% The returned list is ready to use with `sys:handle_debug/4'. Note that an
%% empty list means no debugging and calls to `sys:handle_debug' can be skipped,
%% otherwise the term is opaque.
%%
%% `Name' is the name used to identify a process when formatting an error.
%%
%% `Options' should be the last argument passed to `GenMod:init_it/6'.
%%
%% @see sys:debug_options/1
%% @see sys:handle_debug/4
%% @see start/6

-spec debug_options(Name , Options) -> [sys:dbg_opt()] when
      Name :: term(),
      Options :: options().

debug_options(Name, Options) ->
    case opt(debug, Options) of
	{ok, DebugFlags} ->
	    debug_flags(Name, DebugFlags, format);
	_Other ->
	    debug_flags(Name, [], format)
    end.

%% @doc Format the header for the `format_status/2' callback used by the `sys'
%% module.
%%
%% `TagLine' should be a string declaring that it is the status for that
%% particular generic module. `ProcName' should be the pid or registered name of
%% the process. If the generic process was started using `start/6' with `Name'
%% as `{local, LocalName}', `ProcName' would be `LocalName';
%% `{global, GlobalName}', `GlobalName'; `{via, Module, ViaName}', `ViaName'.
%% The utility function `proc_name/1' can be used to convert `Name' to
%% `ProcName'.
%%
%% @see sys:get_status/2
%% @see proc_name/1

-spec format_status_header(TagLine, ProcName) -> Result when
      TagLine :: string(),
      ProcName :: (Pid :: pid())
		| (LocalName :: local_name())
		| (RegName :: global_name() | via_name()),
      Result :: string()
	      | {TagLine, ProcName}.

format_status_header(TagLine, Pid) when is_pid(Pid) ->
    lists:concat([TagLine, " ", pid_to_list(Pid)]);
format_status_header(TagLine, LocalName) when is_atom(LocalName) ->
    lists:concat([TagLine, " ", LocalName]);
format_status_header(TagLine, RegName) ->
    {TagLine, RegName}.

%% @doc Associate the `Name' with the process `Pid'.
%%
%% `Name' can be of the form `{local, LocalName}', in which case the process,
%% `Pid', will be registered locally as `Localname'. If `Name' is
%% `{global, GlobalName}' `Pid' is registered globally as `GlobalName'. If
%% `Name' is `{via, Module, ViaName}' `Pid' is registered by calling
%% `Module:register_name(ViaName, Pid)'. A successful registration will
%% return `yes' and a failure `no'.
%%
%% For convenience `Name' can also be a pid. In this case no action occurs, if
%% `Name' is equal to `Pid' `yes' is returned otherwise `no'.
%%
%% @see unregister_name/1
%% @see whereis_name/1

-spec register_name(Name, Pid) -> yes | no when
      Name :: emgr_name(),
      Pid :: pid().

register_name({local, LocalName}, Pid) ->
    try register(LocalName, Pid) of
	true ->
	    yes
    catch
	error:badarg ->
	    no
    end;
register_name({global, GlobalName}, Pid) ->
    global:register_name(GlobalName, Pid);
register_name({via, Module, ViaName}, Pid) ->
    Module:register_name(ViaName, Pid);
register_name(Pid, Pid) when is_pid(Pid) ->
    yes;
register_name(Pid, Pid2) when is_pid(Pid) andalso is_pid(Pid2) ->
    no.

%% @doc Removes the association, if it exists, between `Name' and a process.
%%
%% `Name' can be of the form `{local, LocalName}', in which case `LocalName'
%% will be unregistered locally.If `Name' is
%% `{global, GlobalName}' `GlobalName' will be unregistered globally. If `Name'
%% is `{via, Module, ViaName}' `ViaName' will be unregistered by calling
%% `Module:unregister_name(ViaName)'. The function always returns `true'.
%%
%% For convenience `Name' can also be a pid. In this case no action occurs and
%% `true' is returned.
%%
%% @see register_name/2
%% @see whereis_name/1

-spec unregister_name(Name) -> true when
      Name :: emgr_name() | pid().

unregister_name({local, LocalName}) ->
    _ = (catch unregister(LocalName)),
    true;
unregister_name({global, GlobalName}) ->
    _ = global:unregister_name(GlobalName),
    true;
unregister_name({via, Module, ViaName}) ->
    _ = Module:unregister_name(ViaName),
    true;
unregister_name(Pid) when is_pid(Pid) ->
    true.

%% @doc Returns the pid associated with `Name'.
%%
%% `Name' can be of the form `{local, LocalName}', in which case the local
%% pid of the process locally registered as `LocalName' will be returned. If
%% `Name' is `{global, GlobalName}', the pid of process globally registered as
%% `GlobalName'. If `Name' is `{via, Module, ViaName}', the pid of the process
%% associated with `ViaName' will be returned by calling
%% `Module:whereis_name(ViaName)'. If no process is associate with a `Name' then
%% `undefined' is returned.
%%
%% For convenience `Name' can also be a pid. In this case no action occurs and
%% the pid is returned.
%%
%% @see register_name/2
%% @see unregister_name/1

-spec whereis_name(Name) -> undefined | pid() when
      Name :: emgr_name() | pid().

whereis_name({local, LocalName}) ->
    whereis(LocalName);
whereis_name({global, GlobalName}) ->
    global:whereis_name(GlobalName);
whereis_name({via, Module, ViaName}) ->
    Module:whereis_name(ViaName);
whereis_name(Pid) when is_pid(Pid) ->
    Pid.

%% @doc Returns a version of the process' name suitable for formatting.
%%
%% @equiv proc_name(Name, [])

-spec proc_name({local, LocalName}) ->
    LocalName when
      LocalName :: local_name();
      ({global, GlobalName}) ->
    GlobalName when
      GlobalName :: global_name();
      ({via, Module, ViaName}) ->
    ViaName when
      Module :: module(),
      ViaName :: via_name();
      (Pid) ->
    Pid when
      Pid :: pid().

proc_name({local, LocalName}) ->
    LocalName;
proc_name({global, GlobalName}) ->
    GlobalName;
proc_name({via, _Module, ViaName}) ->
    ViaName;
proc_name(Pid) when is_pid(Pid) ->
    Pid.

%% @doc Returns a version of the process' name suitable for formatting.
%%
%% `Name' is the `Name' argument passed in `GenMod:init_it/6'. It can
%% `{local, LocalName}', `{global, GlobalName}', `{via, Module, ViaName}' or a
%% pid.
%%
%% `Opts' is a list of options. The only option is `verify', if it is present in
%% the list then the calling process must also be registered as `Name' otherwise
%% the function will exit with a suitable reason. The verification passes if a
%% call to `whereis_name(Name)' returns the calling process. This means that if
%% `Name' is a pid, then that must be the pid of the calling process.

-spec proc_name({local, LocalName}, [verify]) ->
    LocalName when
      LocalName :: local_name();
      ({global, GlobalName}, [verify]) ->
    GlobalName when
      GlobalName :: global_name();
      ({via, Module, ViaName}, [verify]) ->
    ViaName when
      Module :: module(),
      ViaName :: via_name();
      (Pid, [verify]) ->
    Pid when
      Pid :: pid().

proc_name(Name, Opts) ->
    case lists:member(verify, Opts) of
	true ->
	    get_proc_name(Name);
	false ->
	    proc_name(Name)
    end.

%% @doc Returns the parent of the calling process.
%%
%% If the process was spawned using `proc_lib' the parent process is returned,
%% otherwise the function exits.

-spec parent() -> pid().

parent() ->
    case get('$ancestors') of
	[Parent | _] when is_pid(Parent)->
            Parent;
        [Parent | _] when is_atom(Parent)->
            name_to_pid(Parent);
	_ ->
	    exit(process_was_not_started_by_proc_lib)
    end.

%%%========================================================================
%%% Proc lib-callback functions
%%%========================================================================

%%-----------------------------------------------------------------
%% Initiate the new process.
%% Register the name using the Rfunc function
%% Calls the Mod:init/Args function.
%% Finally an acknowledge is sent to Parent and the main
%% loop is entered.
%%-----------------------------------------------------------------
%% @private
init_it(GenMod, Starter, Parent, Mod, Args, Options, AsyncTimeout) ->
    init_it2(GenMod, Starter, Parent, self(), Mod, Args, Options, AsyncTimeout).

%% @private
init_it(GenMod, Starter, Parent, Name, Mod, Args, Options, AsyncTimeout) ->
    case register_name(Name, self()) of
	yes when AsyncTimeout =:= false ->
	    init_it2(GenMod, Starter, Parent, Name, Mod, Args, Options,
		     AsyncTimeout);
	yes ->
	    proc_lib:init_ack(Starter, {ok, self()}),
	    init_it2(GenMod, Starter, Parent, Name, Mod, Args, Options,
		     AsyncTimeout);
	no ->
	    Pid = whereis_name(Name),
	    proc_lib:init_ack(Starter, {error, {already_started, Pid}})
    end.

%%%========================================================================
%%% Internal functions
%%%========================================================================

%%% ---------------------------------------------------
%%% Spawn/init functions
%%% ---------------------------------------------------

%%-----------------------------------------------------------------
%% Spawn the process (and link) maybe at another node.
%% If spawn without link, set parent to ourselves 'self'!!!
%%-----------------------------------------------------------------
do_spawn(GenMod, link, Mod, Args, Options, false) ->
    Time = timeout(Options),
    proc_lib:start_link(?MODULE, init_it,
			[GenMod, self(), self(), Mod, Args, Options, false], 
			Time,
			spawn_opts(Options));
do_spawn(GenMod, link, Mod, Args, Options, AsyncTimeout) ->
    Pid = proc_lib:spawn_opt(?MODULE, init_it,
			     [GenMod, self(), self, Mod, Args, Options,
			      AsyncTimeout], 
			     [link | spawn_opts(Options)]),
    {ok, Pid};
do_spawn(GenMod, _, Mod, Args, Options, false) ->
    Time = timeout(Options),
    proc_lib:start(?MODULE, init_it,
		   [GenMod, self(), self, Mod, Args, Options, false], 
		   Time,
		   spawn_opts(Options));
do_spawn(GenMod, _, Mod, Args, Options, AsyncTimeout) ->
    Pid = proc_lib:spawn_opt(?MODULE, init_it,
			  [GenMod, self(), self, Mod, Args, Options,
			   AsyncTimeout], 
			  spawn_opts(Options)),
    {ok, Pid}.

do_spawn(GenMod, link, Name, Mod, Args, Options, AsyncTimeout) ->
    Time = timeout(Options),
    proc_lib:start_link(?MODULE, init_it,
			[GenMod, self(), self(), Name, Mod, Args, Options,
			 AsyncTimeout],
			Time,
			spawn_opts(Options));
do_spawn(GenMod, _, Name, Mod, Args, Options, AsyncTimeout) ->
    Time = timeout(Options),
    proc_lib:start(?MODULE, init_it,
		   [GenMod, self(), self, Name, Mod, Args, Options,
		    AsyncTimeout], 
		   Time,
		   spawn_opts(Options)).

init_it2(GenMod, Starter, Parent, Name, Mod, Args, Options, false) ->
    GenMod:init_it(Starter, Parent, Name, Mod, Args, Options);
init_it2(GenMod, Starter, Parent, Name, Mod, Args, Options, infinity) ->
    NStarter = {async, Starter, undefined},
    GenMod:init_it(NStarter, Parent, Name, Mod, Args, Options);
init_it2(GenMod, Starter, Parent, Name, Mod, Args, Options, AsyncTimeout) ->
    GenPid = self(),
    AsyncTimer = spawn_link(
		     fun() ->
			     process_flag(trap_exit, true),
			     receive
				 {ack, GenPid} ->
				     exit(normal);
				 {'EXIT', GenPid, Reason} ->
				     exit(Reason)
			     after
				 AsyncTimeout ->
				     Debug = async_debug(Name, Options),
				     async_timeout_info(GenMod, Name, Mod, Args,
							Debug),
				     exit(GenPid, kill),
				     exit(timeout)
			     end
		     end),
    NStarter = {async, Starter, AsyncTimer},
    GenMod:init_it(NStarter, Parent, Name, Mod, Args, Options).

%%% ---------------------------------------------------
%%% Send/receive functions
%%% ---------------------------------------------------

do_cast(Process, Msg) ->
    case catch erlang:send(Process, Msg, [noconnect]) of
	noconnect ->
	    spawn(erlang, send, [Process, Msg]),
	    ok;
	_Other ->
	    ok
    end.

do_cast_list(Pid, Msg) when is_pid(Pid) ->
    do_cast(Pid, Msg);
do_cast_list({global, GlobalName}, Msg) ->
    case global:whereis_name(GlobalName) of
	Pid when is_pid(Pid) ->
	    do_cast(Pid, Msg);
	undefined ->
	    ok
    end;
do_cast_list({via, Module, ViaName}, Msg) ->
    case Module:whereis_name(ViaName) of
	Pid when is_pid(Pid) ->
	    do_cast(Pid, Msg);
	undefined ->
	    ok
    end;
do_cast_list(LocalName, Msg) when is_atom(LocalName) ->
    do_cast(LocalName, Msg);
do_cast_list({LocalName, Node} = Process, Msg)
  when is_atom(LocalName) andalso is_atom(Node) ->
    do_cast(Process, Msg);
do_cast_list({_ProcessRef, Pid}, Msg) when is_pid(Pid) ->
    do_cast(Pid, Msg).

do_send_list(Pid, Msg) when is_pid(Pid) ->
    erlang:send(Pid, Msg),
    ok;
do_send_list({global, GlobalName}, Msg) ->
    global:send(GlobalName, Msg),
    ok;
do_send_list({via, Module, ViaName}, Msg) ->
    Module:send(ViaName, Msg),
    ok;
do_send_list(LocalName, Msg) when is_atom(LocalName) ->
    erlang:send(LocalName, Msg),
    ok;
do_send_list({LocalName, Node} = Process, Msg)
  when is_atom(LocalName) andalso is_atom(Node) ->
    erlang:send(Process, Msg),
    ok;
do_send_list({_ProcessRef, Pid}, Msg) when is_pid(Pid) ->
    erlang:send(Pid, Msg),
    ok.

do_call(Process, Label, Request, Timeout) ->
    try erlang:monitor(process, Process) of
	Mref ->
	    %% If the monitor/2 call failed to set up a connection to a
	    %% remote node, we don't want the '!' operator to attempt
	    %% to set up the connection again. (If the monitor/2 call
	    %% failed due to an expired timeout, '!' too would probably
	    %% have to wait for the timeout to expire.) Therefore,
	    %% use erlang:send/3 with the 'noconnect' option so that it
	    %% will fail immediately if there is no connection to the
	    %% remote node.

	    catch erlang:send(Process, {Label, {self(), Mref}, Request},
		  [noconnect]),
	    receive
		{Mref, Reply} ->
		    erlang:demonitor(Mref, [flush]),
		    {ok, Reply};
		{'DOWN', Mref, _, _, noconnection} ->
		    Node = get_node(Process),
		    exit({nodedown, Node});
		{'DOWN', Mref, _, _, Reason} ->
		    exit(Reason)
	    after Timeout ->
		    erlang:demonitor(Mref, [flush]),
		    exit(timeout)
	    end
    catch
	error:_ ->
	    %% Node (C/Java?) is not supporting the monitor.
	    %% The other possible case -- this node is not distributed
	    %% -- should have been handled earlier.
	    %% Do the best possible with monitor_node/2.
	    %% This code may hang indefinitely if the Process 
	    %% does not exist. It is only used for featureweak remote nodes.
	    Node = get_node(Process),
	    monitor_node(Node, true),
	    receive
		{nodedown, Node} -> 
		    monitor_node(Node, false),
		    exit({nodedown, Node})
	    after 0 -> 
		    Tag = make_ref(),
		    Process ! {Label, {self(), Tag}, Request},
		    wait_resp(Node, Tag, Timeout)
	    end
    end.

get_node(Process) ->
    %% We trust the arguments to be correct, i.e
    %% Process is either a local or remote pid,
    %% or a {Name, Node} tuple (of atoms) and in this
    %% case this node (node()) _is_ distributed and Node =/= node().
    case Process of
	{_S, N} when is_atom(N) ->
	    N;
	_ when is_pid(Process) ->
	    node(Process)
    end.

wait_resp(Node, Tag, Timeout) ->
    receive
	{Tag, Reply} ->
	    monitor_node(Node, false),
	    {ok, Reply};
	{nodedown, Node} ->
	    monitor_node(Node, false),
	    exit({nodedown, Node})
    after Timeout ->
	    monitor_node(Node, false),
	    exit(timeout)
    end.

do_call_list(Processes, Label, Request, Timeout) ->
    Tag = make_ref(),
    Caller = self(),
    Receiver = spawn(
		 fun() ->
			 %% Middleman process. Should be unsensitive to regular
			 %% exit signals. The sychronization is needed in case
			 %% the receiver would exit before the caller started
			 %% the monitor.
			 process_flag(trap_exit, true),
			 Ref = erlang:monitor(process, Caller),
			 receive
			     {Caller, Tag} ->
				 {Monitors, Bad} = send_processes(Processes,
								  Label, Request),
				 TRef = start_timer(Timeout),
				 Result = rec_processes(Monitors, Bad, TRef),
				 exit({self(), Tag, Result});
			     {'DOWN', Ref, _, _, _} ->
				 %% Caller died before sending us the go-ahead.
				 %% Give up silently.

				 exit(normal)
			 end
		 end),
    Ref = erlang:monitor(process, Receiver),
    Receiver ! {self(), Tag},
    receive
	{'DOWN', Ref, _, _, {Receiver, Tag, Result}} ->
	    Result;
	{'DOWN', Ref, _, _, Reason} ->
	    %% The middleman code failed. Or someone did
	    %% exit(_, kill) on the middleman process => Reason==killed
	    exit(Reason)
    end.

send_processes(Processes, Label, Request) ->
    send_processes(Processes, Label, Request, [], []).

send_processes([Pid | Processes], Label, Request, Monitors, Bad)
  when is_pid(Pid) ->
    Ref = monitor_and_send(Pid, Label, Request),
    send_processes(Processes, Label, Request, [{Pid, Ref, Pid} | Monitors],
		   Bad);
send_processes([{global, GlobalName} = Process | Processes], Label, Request,
	       Monitors, Bad) ->
    case global:whereis_name(GlobalName) of
	Pid when is_pid(Pid) ->
	    Ref = monitor_and_send(Pid, Label, Request),
	    send_processes(Processes, Label, Request,
			   [{Process, Ref, Pid} | Monitors], Bad);
	undefined ->
	    send_processes(Processes, Label, Request, Monitors,
			   [{Process, noproc} | Bad])
    end;
send_processes([{via, Module, ViaName} = Process | Processes], Label, Request,
	       Monitors, Bad) ->
    case Module:whereis_name(ViaName) of
	Pid when is_pid(Pid) ->
	    Ref = monitor_and_send(Pid, Label, Request),
	    send_processes(Processes, Label, Request,
			   [{Process, Ref, Pid} | Monitors], Bad);
	undefined ->
	    send_processes(Processes, Label, Request, Monitors,
			   [{Process, noproc} | Bad])
    end;
send_processes([LocalName | Processes], Label, Request, Monitors, Bad)
  when is_atom(LocalName) ->
    case erlang:whereis(LocalName) of
	Pid when is_pid(Pid) ->
	    Ref = monitor_and_send(Pid, Label, Request),
	    send_processes(Processes, Label, Request,
			   [{LocalName, Ref, Pid} | Monitors], Bad);
	undefined ->
	    send_processes(Processes, Label, Request, Monitors,
			   [{LocalName, noproc} | Bad])
    end;
send_processes([{LocalName, Node} | Processes], Label, Request,
	       Monitors, Bad) when is_atom(LocalName) andalso Node =:= node() ->
   send_processes([LocalName | Processes], Label, Request, Monitors, Bad);
send_processes([{LocalName, Node} = Process | Processes], Label, Request,
	       Monitors, Bad) when is_atom(LocalName) andalso is_atom(Node) ->
    Ref = monitor_and_send(Process, Label, Request),
    send_processes(Processes, Label, Request,
		   [{Process, Ref, Process} | Monitors], Bad);
send_processes([{ProcessRef, Pid} | Processes], Label, Request, Monitors, Bad)
  when is_pid(Pid) ->
    Ref = monitor_and_send(Pid, Label, Request),
    send_processes(Processes, Label, Request,
		   [{ProcessRef, Ref, Pid} | Monitors], Bad);
%% Ignore invalid - same behaviour as multi_call/5.
send_processes([_Invalid | Processes], Label, Request, Monitors, Bad) ->
    send_processes(Processes, Label, Request, Monitors, Bad);
send_processes([], _Label, _Request, Monitors, Bad) ->
    {Monitors, Bad}.

rec_processes(Monitors, Bad, TRef) ->
    rec_processes(Monitors, Bad, [], TRef).

rec_processes([{Process, Ref, Pid} | Monitors], Bad, Replies, TRef)
  when is_reference(Ref) ->
    receive
	{'DOWN', Ref, _, _, noconnection} ->
	    Reason = rec_noconnection(Process, Pid),
	    rec_processes(Monitors, [{Process, Reason} | Bad],
			  Replies, TRef);
	{'DOWN', Ref, _, _, Reason} ->
	    rec_processes(Monitors, [{Process, Reason} | Bad], Replies, TRef);
	{Ref, Reply} ->
	    erlang:demonitor(Ref, [flush]),
	    rec_processes(Monitors, Bad, [{Process, Reply} | Replies], TRef);
	{timeout, TRef, _} ->
	    erlang:demonitor(Ref, [flush]),
	    rec_processes_rest(Monitors, [{Process, timeout} | Bad], Replies)
    end;
rec_processes([{Process, {Node, Ref}, Pid} | Monitors], Bad, Replies, TRef) ->
    receive
	{nodedown, Node} ->
	    Reason = rec_noconnection(Process, Pid),
	    rec_processes(Monitors, [{Process, Reason} | Bad],
			  Replies, TRef);
	{Ref, Reply} ->
	    monitor_node(Node, false),
	    rec_processes(Monitors, Bad, [{Process, Reply} | Replies], TRef);
	{timeout, TRef, _} ->
	    monitor_node(Node, false),
	    rec_processes_rest(Monitors, [{Process, timeout} | Bad], Replies)
    end;
rec_processes([], Bad, Replies, TRef) when is_reference(TRef) ->
    case erlang:cancel_timer(TRef) of
	false ->
	    receive {timeout, TRef, _} -> ok after 0 -> ok end;
	_ ->
	    ok
    end,
    {Replies, Bad};
rec_processes([], Bad, Replies, undefined) ->
    {Replies, Bad}.

rec_processes_rest([{Process, Ref, Pid} | Monitors], Bad, Replies)
  when is_reference(Ref) ->
    receive
	{'DOWN', Ref, _, _, noconnection} ->
	    Reason = rec_noconnection(Process, Pid),
	    rec_processes_rest(Monitors, [{Process, Reason} | Bad],
			       Replies);
	{'DOWN', Ref, _, _, Reason} ->
	    rec_processes_rest(Monitors, [{Process, Reason} | Bad], Replies);
	{Ref, Reply} ->
	    erlang:demonitor(Ref, [flush]),
	    rec_processes_rest(Monitors, Bad, [{Process, Reply} | Replies])
    after
	0 ->
	    erlang:demonitor(Ref, [flush]),
	    rec_processes_rest(Monitors, [{Process, timeout} | Bad], Replies)
    end;
rec_processes_rest([{Process, {Node, Ref}, Pid} | Monitors], Bad, Replies) ->
    receive
	{nodedown, Node} ->
	    Reason = rec_noconnection(Process, Pid),
	    rec_processes_rest(Monitors, [{Process, Reason} | Bad],
			       Replies);
	{Ref, Reply} ->
	    monitor_node(Node, false),
	    rec_processes_rest(Monitors, Bad, [{Process, Reply} | Replies])
    after
	0 ->
	    monitor_node(Node, false),
	    rec_processes_rest(Monitors, [{Process, timeout} | Bad], Replies)
    end;
rec_processes_rest([], Bad, Replies) ->
    {Replies, Bad}.

%% `nodedown' not yet detected by global (or via module) `noproc' is reason is
%% used instead to copy call/4 behaviour.
rec_noconnection({global, _GlobalName}, _Pid) ->
    noproc;
rec_noconnection({via, _Module, _ViaName}, _Pid) ->
    noproc;
rec_noconnection(_Process, Pid) ->
    {nodedown, get_node(Pid)}.

monitor_and_send(Process, Label, Request) ->
    try erlang:monitor(process, Process) of
	Ref ->
	    catch erlang:send(Process, {Label, {self(), Ref}, Request},
			      [noconnect]),
	    Ref
    catch
	error:_ ->
	    Node = get_node(Process),
	    monitor_node(Node, true),
	    Ref = make_ref(),
	    catch erlang:send(Process, {Label, {self(), Ref}, Request},
			      [noconnect]),
	    {Node, Ref}
    end.

start_timer(infinity) ->
    undefined;
start_timer(Timeout) ->
    erlang:start_timer(Timeout, self(), ok).

%%%-----------------------------------------------------------------
%%%  Misc. functions.
%%%-----------------------------------------------------------------
async_timeout(Options) ->
    case opt(async, Options) of
	{ok, infinity} ->
	    infinity;
	{ok, AsyncTimeout}
	  when is_integer(AsyncTimeout) andalso AsyncTimeout >= 0 ->
	    AsyncTimeout;
	{ok, false} ->
	    false;
	_ ->
	    false
    end.

timeout(Options) ->
    case opt(timeout, Options) of
	{ok, Time} ->
	    Time;
	_ ->
	    infinity
    end.

spawn_opts(Options) ->
    case opt(spawn_opt, Options) of
	{ok, Opts} ->
	    Opts;
	_ ->
	    []
    end.

debug_flags(Name, [], Format) ->
    DebugOpts =
	case init:get_argument(generic_debug) of
	    error ->
		[];
	    _ ->
		[log, statistics]
	end,
    sys_debug_options(Name, DebugOpts, Format);
debug_flags(Name, DebugFlags, Format) ->
    Fun = fun(debug, Acc) ->
		  [statistics, log | Acc];
	     (Other, Acc) ->
		  [Other | Acc]
	  end,
    DebugOpts = lists:reverse(lists:foldl(Fun, [], DebugFlags)),
    sys_debug_options(Name, DebugOpts, Format).

sys_debug_options(Name, DebugOpts, Format) ->
    case catch sys:debug_options(DebugOpts) of
	{'EXIT',_}  when Format =:= format ->
	    error_logger:format("~p: ignoring erroneous debug options - ~p~n",
		   [Name, DebugOpts]),
	    [];
	{'EXIT',_} when Format =:= noformat ->
	    [];
	Debug ->
	    Debug
    end.

opt(Op, [{Op, Value}|_]) ->
    {ok, Value};
opt(Op, [_|Options]) ->
    opt(Op, Options);
opt(_, []) ->
    false.

async_debug(Name, Options) ->
    case opt(debug, Options) of
	{ok, DebugFlags} ->
	    debug_flags(Name, DebugFlags, noformat);
	_Other ->
	    debug_flags(Name, [], noformat)
    end.

async_timeout_info(GenMod, Name, Mod, Args, Debug) ->
    _ = (catch GenMod:async_timeout_info(Name, Mod, Args, Debug)),
    ok.

get_proc_name({local, LocalName}) ->
    case process_info(self(), registered_name) of
	{registered_name, LocalName} ->
	    LocalName;
	{registered_name, _LocalName} ->
	    exit(process_not_registered);
	[] ->
	    exit(process_not_registered)
    end;    
get_proc_name({global, GlobalName}) ->
    case global:whereis_name(GlobalName) of
	undefined ->
	    exit(process_not_registered_globally);
	Pid when Pid =:= self() ->
	    GlobalName;
	_Pid ->
	    exit(process_not_registered_globally)
    end;
get_proc_name({via, Module, ViaName}) ->
    case Module:whereis_name(ViaName) of
	undefined ->
	    exit({process_not_registered_via, Module});
	Pid when Pid =:= self() ->
	    ViaName;
	_Pid ->
	    exit({process_not_registered_via, Module})
    end;
get_proc_name(Pid) when Pid =:= self() ->
    Pid;
get_proc_name(Pid) when is_pid(Pid) ->
    exit({process_not, Pid}).

name_to_pid(Name) ->
    case whereis(Name) of
	undefined ->
	    case global:whereis_name(Name) of
		undefined ->
		    exit(could_not_find_registered_name);
		Pid ->
		    Pid
	    end;
	Pid ->
	    Pid
    end.
