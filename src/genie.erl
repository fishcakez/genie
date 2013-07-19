%%
%% %CopyrightBegin%
%%
%% Copyright Ericsson AB 1996-2013. All Rights Reserved.
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
%% The genie behaviour requires one export `init_it/6', after spawning and
%% successfuly registring a process using `start/5,6' it will be called as
%% `GenMod:init_it(Starter, Parent, Name, Mod, Args, Options)'. This
%% function carries out the initialising of the generic module `GenMod' and its
%% callback module `Mod'.
%%
%% As part of its initialising `GenMod' calls `Mod:init(Args)' to setup a state
%% for the callback module. Based on the returned value of `Mod:init/1'
%% `GenMod' must call `proc_lib:init_ack(Starter, Return)' to acknowledge the
%% result. A success will have Return as `{ok, self()}'. In the case of
%% failure `Return' is of the form `{error, Reason}' where `Reason' can be any
%% term, the process then exits with the same reason by calling `exit(Reason)'.
%% If no error occured but the process is going to exit immediately
%% (with reason `normal'), `Return' is the atom `ignore'. Note that the caller
%% of `start/5,6' blocks until it receives the acknowledgment sent by
%% `proc_lib:init_ack/2'.
%%
%% `Starter' is the pid of the process that called `start/5,6'.
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
%% debug options to be used with the `sys' module `debug_options(Options)' is
%% used.
%%
%% An example with detailed inline comments, called `genie_basic', can be found
%% in the `examples' directory. It shows how to deal with system messages and
%% the other features of the `sys' module.
%% @end

-module(genie).
-compile({inline,[get_node/1]}).

%% API
-export([start/5, start/6,
	 call/3, call/4, reply/2,
	 debug_options/1, format_status_header/2]).

%% Internal exports
-export([init_it/6, init_it/7]).

-define(default_timeout, 5000).

-type linkage()     :: 'link' | 'nolink'.
-type local_name()  :: atom().
-type global_name() :: term().
-type via_name()    :: term().
-type emgr_name()   :: {'local', local_name()}
		     | {'global', global_name()}
		     | {via, module(), via_name()}.

-type parent()      :: pid() | self.

-type start_ret()   :: {'ok', pid()} | 'ignore' | {'error', term()}.

-type debug_flag()  :: 'trace' | 'log' | 'statistics' | 'debug'
                     | {'logfile', string()}.
-type option()      :: {'timeout', timeout()}
		     | {'debug', [debug_flag()]}
		     | {'spawn_opt', [proc_lib:spawn_option()]}.
-type options()     :: [option()].

-opaque tag()      :: reference().

-export_type([emgr_name/0, options/0, tag/0]).

%%%=========================================================================
%%%  API
%%%=========================================================================

-callback init_it(Starter :: pid(), Parent :: parent(), Name :: emgr_name(),
		  Mod :: module(), Args :: term(), Options :: options()) ->
    no_return().

%% @doc Starts a generic process.
%%
%% The process is started in the same way as `start/6' except that it is not
%% registered.
%%
%% @see start/6

-spec start(module(), linkage(), module(), term(), options()) -> start_ret().

start(GenMod, LinkP, Mod, Args, Options) ->
    do_spawn(GenMod, LinkP, Mod, Args, Options).

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
%% `sys:handle_debug/4'. `DebugFlags' is a list of terms to be passed to
%% `debug_options/1', which creates the `sys' debug options to be used with
%% `sys:handle_debug/4'.
%%
%% The option `{spawn_opts, SpawnOpts}' will cause `SpawnOpts' to be passed as
%% the spawn options to the relevant `proc_lib' spawn function.
%%
%% @see sys:handle_system_msg/6
%% @see proc_lib:start_link/5
%% @see proc_lib:init_ack/2
%% @see debug_options/1
%% @see sys:handle_debug/4

-spec start(GenMod :: module(), LinkP :: linkage(), Name :: emgr_name(),
	    Mod :: module(), Args :: term(), Options :: options()) ->
	start_ret().
start(GenMod, LinkP, Name, Mod, Args, Options) ->
    case where(Name) of
	undefined ->
	    do_spawn(GenMod, LinkP, Name, Mod, Args, Options);
	Pid ->
	    {error, {already_started, Pid}}
    end.

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
      Label :: term(),
      Request :: term(),
      Result :: term().

%%% New call function which uses the new monitor BIF
%%% call(ServerId, Label, Request)
call(Process, Label, Request) -> 
    call(Process, Label, Request, ?default_timeout).

%% @doc Makes a synchronous call to a generic process.
%%
%% `Process', the target of the call, can take many forms beyond the pid.
%% It can be the name of a locally registered process, or if the it is
%% registered locally on a different node `{LocalName, Node}'. Note that
%% `{local, LocalName}' can not be used to call a process registered locally as
%% `LocalName'. If the process is registered globally `Process' is
%% `{global, GlobalName}'. If registered via an alternative module using
%% `Module:register_name/2', `Process' is `{via, Module, ViaName}'.
%%
%% `Label' is an term used by the generic process to identify that the message
%% is a call, and possibly a particular type of call.
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
      Label :: term(),
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
    case where(Name) of
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

%% @doc Sends a reply to a client.
%%
%% `From' is from in the call message tuple `{Label, From, Request}'. `From'
%% takes the form `{To, Tag}', where `To' is the pid that sent the call, and the
%% target of the reply. `Tag' is a unique term used to identify the message.
%%
%% @see call/4

-spec reply(From, Reply) -> Reply when
      From :: {To :: pid(), (Tag :: tag() | term())},
      Reply :: term().

reply({To, Tag}, Reply) when is_pid(To) ->
    Msg = {Tag, Reply},
    try To ! Msg catch _:_ -> Msg end.

%% @doc Get the sys debug structure from genie options.
%%
%% The returned list is
%% ready too use with `sys:handle_debug/4'. Note that an empty list means no
%% debugging and calls to `sys:handle_debug' can be skipped, otherwise the term
%% is opaque.
%%
%% @see sys:debug_options/1
%% @see sys:handle_debug/4
%% @see start/6

-spec debug_options(Options) -> [sys:dbg_opt()] when
      Options :: options().

debug_options(Opts) ->
    case opt(debug, Opts) of
	{ok, Options} -> sys:debug_options(Options);
	_ -> []
    end.

%% @doc Format the header for the `format_status/2' callback used by the `sys'
%% module.
%%
%% `TagLine' should be a string declaring that it is the status for that
%% particular generic module. `ProcName' should be the pid or registered name of
%% the process. If the generic process was started using `start/6' with `Name'
%% as `{local, LocalName}', `ProcName' would be `LocalName';
%% `{global, GlobalName}', `GlobalName'; `{via, Module, ViaName}', `ViaName'.
%%
%% @see sys:get_status/2

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
init_it(GenMod, Starter, Parent, Mod, Args, Options) ->
    init_it2(GenMod, Starter, Parent, self(), Mod, Args, Options).

%% @private
init_it(GenMod, Starter, Parent, Name, Mod, Args, Options) ->
    case name_register(Name) of
	true ->
	    init_it2(GenMod, Starter, Parent, Name, Mod, Args, Options);
	{false, Pid} ->
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
do_spawn(GenMod, link, Mod, Args, Options) ->
    Time = timeout(Options),
    proc_lib:start_link(?MODULE, init_it,
			[GenMod, self(), self(), Mod, Args, Options], 
			Time,
			spawn_opts(Options));
do_spawn(GenMod, _, Mod, Args, Options) ->
    Time = timeout(Options),
    proc_lib:start(?MODULE, init_it,
		   [GenMod, self(), self, Mod, Args, Options], 
		   Time,
		   spawn_opts(Options)).

do_spawn(GenMod, link, Name, Mod, Args, Options) ->
    Time = timeout(Options),
    proc_lib:start_link(?MODULE, init_it,
			[GenMod, self(), self(), Name, Mod, Args, Options],
			Time,
			spawn_opts(Options));
do_spawn(GenMod, _, Name, Mod, Args, Options) ->
    Time = timeout(Options),
    proc_lib:start(?MODULE, init_it,
		   [GenMod, self(), self, Name, Mod, Args, Options], 
		   Time,
		   spawn_opts(Options)).

init_it2(GenMod, Starter, Parent, Name, Mod, Args, Options) ->
    GenMod:init_it(Starter, Parent, Name, Mod, Args, Options).

%%% ---------------------------------------------------
%%% Send/receive functions
%%% ---------------------------------------------------

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

%%%-----------------------------------------------------------------
%%%  Misc. functions.
%%%-----------------------------------------------------------------
where({global, Name}) -> global:whereis_name(Name);
where({via, Module, Name}) -> Module:whereis_name(Name);
where({local, Name})  -> whereis(Name).

name_register({local, Name} = LN) ->
    try register(Name, self()) of
	true -> true
    catch
	error:_ ->
	    {false, where(LN)}
    end;
name_register({global, Name} = GN) ->
    case global:register_name(Name, self()) of
	yes -> true;
	no -> {false, where(GN)}
    end;
name_register({via, Module, Name} = GN) ->
    case Module:register_name(Name, self()) of
	yes ->
	    true;
	no ->
	    {false, where(GN)}
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

opt(Op, [{Op, Value}|_]) ->
    {ok, Value};
opt(Op, [_|Options]) ->
    opt(Op, Options);
opt(_, []) ->
    false.
