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

%% @doc `genie_fsm' is a drop in replacement for `gen_fsm'. A few features have
%% been added but nothing has been taken away.
%%
%% The `genie_fsm' behaviour has exactly the same callbacks as `gen_fsm',
%% except that `init/1' has two extra return values. `Mod:init/1' can also
%% return `{info, StateName, StateData Info}' or
%% `{info, StateName, StateData, Info, Timeout}'. This will cause
%% `start_link/3,4' (or `start/3,4') to return `{ok, Pid, Info}' and the state
%% machine will continue as if `{ok, StateName, StateData}' or
%% `{ok, StateName, StateData, Timeout}' had been returned. `Info' can be any
%% term. If `start_link/3,4' is called using `supervisor:start_child/2' or
%% `supervisor:restart_child/2' then `{ok, Pid, Info}' will be returned instead
%% of `{ok, Pid}'.
%%
%% @end

-module(genie_fsm).

%%%-----------------------------------------------------------------
%%%   
%%% This state machine is somewhat more pure than state_lib.  It is
%%% still based on State dispatching (one function per state), but
%%% allows a function handle_event to take care of events in all states.
%%% It's not that pure anymore :(  We also allow synchronized event sending.
%%%
%%% If the Parent process terminates the Module:terminate/2
%%% function is called.
%%%
%%% The user module should export:
%%%
%%%   init(Args)
%%%     ==> {ok, StateName, StateData}
%%%         {ok, StateName, StateData, Timeout}
%%%         ignore
%%%         {stop, Reason}
%%%
%%%   StateName(Msg, StateData)
%%%
%%%    ==> {next_state, NewStateName, NewStateData}
%%%        {next_state, NewStateName, NewStateData, Timeout}
%%%        {stop, Reason, NewStateData}
%%%              Reason = normal | shutdown | Term terminate(State) is called
%%%
%%%   StateName(Msg, From, StateData)
%%%
%%%    ==> {next_state, NewStateName, NewStateData}
%%%        {next_state, NewStateName, NewStateData, Timeout}
%%%        {reply, Reply, NewStateName, NewStateData}
%%%        {reply, Reply, NewStateName, NewStateData, Timeout}
%%%        {stop, Reason, NewStateData}
%%%              Reason = normal | shutdown | Term terminate(State) is called
%%%
%%%   handle_event(Msg, StateName, StateData)
%%%
%%%    ==> {next_state, NewStateName, NewStateData}
%%%        {next_state, NewStateName, NewStateData, Timeout}
%%%        {stop, Reason, Reply, NewStateData}
%%%        {stop, Reason, NewStateData}
%%%              Reason = normal | shutdown | Term terminate(State) is called
%%%
%%%   handle_sync_event(Msg, From, StateName, StateData)
%%%
%%%    ==> {next_state, NewStateName, NewStateData}
%%%        {next_state, NewStateName, NewStateData, Timeout}
%%%        {reply, Reply, NewStateName, NewStateData}
%%%        {reply, Reply, NewStateName, NewStateData, Timeout}
%%%        {stop, Reason, Reply, NewStateData}
%%%        {stop, Reason, NewStateData}
%%%              Reason = normal | shutdown | Term terminate(State) is called
%%%
%%%   handle_info(Info, StateName) (e.g. {'EXIT', P, R}, {nodedown, N}, ...
%%%
%%%    ==> {next_state, NewStateName, NewStateData}
%%%        {next_state, NewStateName, NewStateData, Timeout}
%%%        {stop, Reason, NewStateData}
%%%              Reason = normal | shutdown | Term terminate(State) is called
%%%
%%%   terminate(Reason, StateName, StateData) Let the user module clean up
%%%        always called when server terminates
%%%
%%%    ==> the return value is ignored
%%%
%%%
%%% The work flow (of the fsm) can be described as follows:
%%%
%%%   User module                           fsm
%%%   -----------                          -------
%%%     start              ----->             start
%%%     init               <-----              .
%%%
%%%                                           loop
%%%     StateName          <-----              .
%%%
%%%     handle_event       <-----              .
%%%
%%     handle__sunc_event <-----              .
%%%
%%%     handle_info        <-----              .
%%%
%%%     terminate          <-----              .
%%%
%%%
%%% ---------------------------------------------------

-export([start/3, start/4,
	 start_link/3, start_link/4,
	 send_event/2, send_list_event/2, sync_send_event/2, sync_send_event/3,
	 send_all_state_event/2, send_list_all_state_event/2,
	 sync_send_all_state_event/2, sync_send_all_state_event/3,
	 reply/2,
	 start_timer/2,send_event_after/2,cancel_timer/1,
	 enter_loop/4, enter_loop/5, enter_loop/6, wake_hib/6]).

%% Internal exports
-export([init_it/6,
	 system_continue/3,
	 system_terminate/4,
	 system_code_change/4,
	 async_timeout_info/4,
	 format_status/2]).

-import(error_logger, [format/2]).

%%% ---------------------------------------------------
%%% Interface functions.
%%% ---------------------------------------------------

-callback init(Args :: term()) ->
    {ok, StateName :: atom(), StateData :: term()} |
    {ok, StateName :: atom(), StateData :: term(), timeout() | hibernate} |
    {stop, Reason :: term()} | ignore.
-callback handle_event(Event :: term(), StateName :: atom(),
                       StateData :: term()) ->
    {next_state, NextStateName :: atom(), NewStateData :: term()} |
    {next_state, NextStateName :: atom(), NewStateData :: term(),
     timeout() | hibernate} |
    {stop, Reason :: term(), NewStateData :: term()}.
-callback handle_sync_event(Event :: term(), From :: {pid(), Tag :: term()},
                            StateName :: atom(), StateData :: term()) ->
    {reply, Reply :: term(), NextStateName :: atom(), NewStateData :: term()} |
    {reply, Reply :: term(), NextStateName :: atom(), NewStateData :: term(),
     timeout() | hibernate} |
    {next_state, NextStateName :: atom(), NewStateData :: term()} |
    {next_state, NextStateName :: atom(), NewStateData :: term(),
     timeout() | hibernate} |
    {stop, Reason :: term(), Reply :: term(), NewStateData :: term()} |
    {stop, Reason :: term(), NewStateData :: term()}.
-callback handle_info(Info :: term(), StateName :: atom(),
                      StateData :: term()) ->
    {next_state, NextStateName :: atom(), NewStateData :: term()} |
    {next_state, NextStateName :: atom(), NewStateData :: term(),
     timeout() | hibernate} |
    {stop, Reason :: normal | term(), NewStateData :: term()}.
-callback terminate(Reason :: normal | shutdown | {shutdown, term()}
		    | term(), StateName :: atom(), StateData :: term()) ->
    term().
-callback code_change(OldVsn :: term() | {down, term()}, StateName :: atom(),
		      StateData :: term(), Extra :: term()) ->
    {ok, NextStateName :: atom(), NewStateData :: term()}.

%%% ---------------------------------------------------
%%% Starts a generic state machine.
%%% start(Mod, Args, Options)
%%% start(Name, Mod, Args, Options)
%%% start_link(Mod, Args, Options)
%%% start_link(Name, Mod, Args, Options) where:
%%%    Name ::= {local, atom()} | {global, atom()} | {via, atom(), term()}
%%%    Mod  ::= atom(), callback module implementing the 'real' fsm
%%%    Args ::= term(), init arguments (to Mod:init/1)
%%%    Options ::= [{debug, [Flag]}]
%%%      Flag ::= trace | log | {logfile, File} | statistics | debug
%%%          (debug == log && statistics)
%%% Returns: {ok, Pid} |
%%%          {error, {already_started, Pid}} |
%%%          {error, Reason}
%%% ---------------------------------------------------

%% @doc Starts a generic state machine.
%%
%% @see start_link/4
%% @see gen_fsm:start/3
start(Mod, Args, Options) ->
    genie:start(?MODULE, nolink, Mod, Args, Options).

%% @doc Starts a generic state machine.
%%
%% @see start_link/4
%% @see gen_fsm:start/4
start(Name, Mod, Args, Options) ->
    genie:start(?MODULE, nolink, Name, Mod, Args, Options).

%% @doc Starts a generic state machine.
%%
%% @see start_link/4
%% @see gen_fsm:start_link/3
start_link(Mod, Args, Options) ->
    genie:start(?MODULE, link, Mod, Args, Options).

%% @doc Starts a generic state machine.
%%
%% The `Options' argument can take a new option, `{async, AsyncTimeout}'. If
%% `AsyncTimeout' is false the process is spawned synchronously - the same as
%% always occurs with `gen_fsm'. If `AsyncTimeout' is a `timeout()' value, then
%% the `start_link/3,4' or `start/3,4' function will return immediately, before
%% `Mod:init/1' is called. This means that if `Mod:init/1' returns
%% `{info, StateName, StateData, Info}' or
%% `{info, StateName, StateData, Info, Timeout}' the information will be ignored
%% and `{ok, Pid}' returned. In the case of `start_link/4' and `start/4' the
%% spawned process will be registered before the function returns. If this fails
%% the usual `already_started' error will be returned. If `Mod:init/1' does not
%% return with the timeout, `AsyncTimeout', the spawned state machine will be
%% killed.
%%
%% @see genie:start/6
%% @see gen_fsm:start_link/4
start_link(Name, Mod, Args, Options) ->
    genie:start(?MODULE, link, Name, Mod, Args, Options).

%% @doc Send an event to a state machine.
%%
%% @see gen_fsm:send_event/2
send_event(Name, Event) ->
    genie:send(Name, '$gen_event', Event).

%% @doc Sends an event to a list state machines.
%%
%% @see gen_fsm:send_event/2
send_list_event(Names, Event) ->
    genie:send_list(Names, '$gen_event', Event).

%% @doc Send a synchronous event to a state machine.
%%
%% @see gen_fsm:sync_send_event/2
sync_send_event(Name, Event) ->
    case catch genie:call(Name, '$gen_sync_event', Event) of
	{ok,Res} ->
	    Res;
	{'EXIT',Reason} ->
	    exit({Reason, {?MODULE, sync_send_event, [Name, Event]}})
    end.

%% @doc Send a synchronous event to a state machine.
%%
%% @see gen_fsm:sync_send_event/3
sync_send_event(Name, Event, Timeout) ->
    case catch genie:call(Name, '$gen_sync_event', Event, Timeout) of
	{ok,Res} ->
	    Res;
	{'EXIT',Reason} ->
	    exit({Reason, {?MODULE, sync_send_event, [Name, Event, Timeout]}})
    end.

%% @doc Send an all state event to a state machine.
%%
%% @see gen_fsm:send_all_state_event/2
send_all_state_event(Name, Event) ->
    genie:send(Name, '$gen_all_state_event', Event).

%% @doc Send an all state event to a list of state machines.
%%
%% @see send_all_state_event/2
%% @see genie:send_list/3
send_list_all_state_event(Names, Event) ->
    genie:send_list(Names, '$gen_all_state_event', Event).

%% @doc Send a synchronous all state event to a state machine.
%%
%% @see gen_fsm:sync_send_all_state_event/2
sync_send_all_state_event(Name, Event) ->
    case catch genie:call(Name, '$gen_sync_all_state_event', Event) of
	{ok,Res} ->
	    Res;
	{'EXIT',Reason} ->
	    exit({Reason, {?MODULE, sync_send_all_state_event, [Name, Event]}})
    end.

%% @doc Send a synchronous all state event to a state machine.
%%
%% @see gen_fsm:sync_send_all_state_event/3
sync_send_all_state_event(Name, Event, Timeout) ->
    case catch genie:call(Name, '$gen_sync_all_state_event', Event, Timeout) of
	{ok,Res} ->
	    Res;
	{'EXIT',Reason} ->
	    exit({Reason, {?MODULE, sync_send_all_state_event,
			   [Name, Event, Timeout]}})
    end.

%% Designed to be only callable within one of the callbacks
%% hence using the self() of this instance of the process.
%% This is to ensure that timers don't go astray in global
%% e.g. when straddling a failover, or turn up in a restarted
%% instance of the process.

%% Returns Ref, sends event {timeout,Ref,Msg} after Time 
%% to the (then) current state.

%% @doc Start a timer.
%%
%% @see gen_fsm:start_timer/2
start_timer(Time, Msg) ->
    erlang:start_timer(Time, self(), {'$gen_timer', Msg}).

%% Returns Ref, sends Event after Time to the (then) current state.

%% @doc Send an event to the current state machine after a time.
%%
%% @see gen_fsm:send_event_after/2
send_event_after(Time, Event) ->
    erlang:start_timer(Time, self(), {'$gen_event', Event}).

%% Returns the remaing time for the timer if Ref referred to 
%% an active timer/send_event_after, false otherwise.

%% @doc Cancel a timer.
%%
%% @see gen_fsm:cancel_timer/1
cancel_timer(Ref) ->
    case erlang:cancel_timer(Ref) of
	false ->
	    receive {timeout, Ref, _} -> 0
	    after 0 -> false 
	    end;
	RemainingTime ->
	    RemainingTime
    end.

%% enter_loop/4,5,6
%% Makes an existing process into a genie_fsm.
%% The calling process will enter the genie_fsm receive loop and become a
%% genie_fsm process.
%% The process *must* have been started using one of the start functions
%% in proc_lib, see proc_lib(3).
%% The user is responsible for any initialization of the process,
%% including registering a name for it.

%% @doc Enter a state machine loop.
%%
%% @see gen_fsm:enter_loop/4
enter_loop(Mod, Options, StateName, StateData) ->
    enter_loop(Mod, Options, StateName, StateData, self(), infinity).

%% @doc Enter a state machine loop.
%%
%% @see gen_fsm:enter_loop/5
enter_loop(Mod, Options, StateName, StateData, {Scope,_} = ServerName)
  when Scope == local; Scope == global ->
    enter_loop(Mod, Options, StateName, StateData, ServerName,infinity);
enter_loop(Mod, Options, StateName, StateData, {via,_,_} = ServerName) ->
    enter_loop(Mod, Options, StateName, StateData, ServerName,infinity);
enter_loop(Mod, Options, StateName, StateData, Timeout) ->
    enter_loop(Mod, Options, StateName, StateData, self(), Timeout).

%% @doc Enter a state machine loop.
%%
%% @see gen_fsm:enter_loop/6
enter_loop(Mod, Options, StateName, StateData, ServerName, Timeout) ->
    Name = genie:proc_name(ServerName, [verify]),
    Parent = genie:parent(),
    Debug = genie:debug_options(Name, Options),
    loop(Parent, Name, StateName, StateData, Mod, Timeout, Debug).

%%% ---------------------------------------------------
%%% Initiate the new process.
%%% Register the name using the Rfunc function
%%% Calls the Mod:init/Args function.
%%% Finally an acknowledge is sent to Parent and the main
%%% loop is entered.
%%% ---------------------------------------------------

%% @private
init_it(Starter, self, Name, Mod, Args, Options) ->
    init_it(Starter, self(), Name, Mod, Args, Options);
init_it(Starter, Parent, Name0, Mod, Args, Options) ->
    Name = genie:proc_name(Name0),
    Debug = genie:debug_options(Name, Options),
    case catch Mod:init(Args) of
	{ok, StateName, StateData} ->
	    genie:init_ack(Starter, {ok, self()}), 	    
	    loop(Parent, Name, StateName, StateData, Mod, infinity, Debug);
	{ok, StateName, StateData, Timeout} ->
	    genie:init_ack(Starter, {ok, self()}), 	    
	    loop(Parent, Name, StateName, StateData, Mod, Timeout, Debug);
	{info, StateName, StateData, Info} ->
	    genie:init_ack(Starter, {ok, self(), Info}), 	    
	    loop(Parent, Name, StateName, StateData, Mod, infinity, Debug);
	{info, StateName, StateData, Info, Timeout} ->
	    genie:init_ack(Starter, {ok, self(), Info}), 	    
	    loop(Parent, Name, StateName, StateData, Mod, Timeout, Debug);
	{stop, Reason} ->
	    genie:unregister_name(Name0),
	    genie:init_ack(Starter, {error, Reason}),
	    %% Async init error reported after genie:init_ack/2 as process could
	    %% be killed inside genie:init_ack/2.
	    async_error_info(Reason, Starter, Name, Args, Debug),
	    exit(Reason);
	ignore ->
	    genie:unregister_name(Name0),
	    genie:init_ack(Starter, ignore),
	    exit(normal);
	{'EXIT', Reason} ->
	    genie:unregister_name(Name0),
	    genie:init_ack(Starter, {error, Reason}),
	    async_error_info(Reason, Starter, Name, Args, Debug),
	    exit(Reason);
	Else ->
	    Error = {bad_return_value, Else},
	    genie:init_ack(Starter, {error, Error}),
	    async_error_info(Error, Starter, Name, Args, Debug),
	    exit(Error)
    end.

%%-----------------------------------------------------------------
%% The MAIN loop
%%-----------------------------------------------------------------
loop(Parent, Name, StateName, StateData, Mod, hibernate, Debug) ->
    proc_lib:hibernate(?MODULE,wake_hib,
		       [Parent, Name, StateName, StateData, Mod, 
			Debug]);
loop(Parent, Name, StateName, StateData, Mod, Time, Debug) ->
    Msg = receive
	      Input ->
		    Input
	  after Time ->
		  {'$gen_event', timeout}
	  end,
    decode_msg(Msg,Parent, Name, StateName, StateData, Mod, Time, Debug, false).

%% @private
wake_hib(Parent, Name, StateName, StateData, Mod, Debug) ->
    Msg = receive
	      Input ->
		  Input
	  end,
    decode_msg(Msg, Parent, Name, StateName, StateData, Mod, hibernate, Debug, true).

decode_msg(Msg,Parent, Name, StateName, StateData, Mod, Time, Debug, Hib) ->
    case Msg of
	{system, From, get_state} ->
	    Misc = [Name, StateName, StateData, Mod, Time],
	    sys:handle_system_msg(get_state, From, Parent, ?MODULE, Debug,
				  {{StateName, StateData}, Misc}, Hib);
	{system, From, {replace_state, StateFun}} ->
	    State = {StateName, StateData},
	    NState = {NStateName, NStateData} = try StateFun(State)
						catch _:_ -> State end,
	    NMisc = [Name, NStateName, NStateData, Mod, Time],
	    sys:handle_system_msg(replace_state, From, Parent, ?MODULE, Debug,
				  {NState, NMisc}, Hib);
        {system, From, Req} ->
	    sys:handle_system_msg(Req, From, Parent, ?MODULE, Debug,
				  [Name, StateName, StateData, Mod, Time], Hib);
	{'EXIT', Parent, Reason} ->
	    terminate(Reason, Name, Msg, Mod, StateName, StateData, Debug);
	_Msg when Debug =:= [] ->
	    handle_msg(Msg, Parent, Name, StateName, StateData, Mod, Time);
	_Msg ->
	    Debug1 = sys:handle_debug(Debug, fun print_event/3,
				      {Name, StateName}, {in, Msg}),
	    handle_msg(Msg, Parent, Name, StateName, StateData,
		       Mod, Time, Debug1)
    end.

%%-----------------------------------------------------------------
%% Callback functions for system messages handling.
%%-----------------------------------------------------------------

%% @private
system_continue(Parent, Debug, [Name, StateName, StateData, Mod, Time]) ->
    loop(Parent, Name, StateName, StateData, Mod, Time, Debug).

%% @private

-spec system_terminate(term(), _, _, [term(),...]) -> no_return().

system_terminate(Reason, _Parent, Debug,
		 [Name, StateName, StateData, Mod, _Time]) ->
    terminate(Reason, Name, [], Mod, StateName, StateData, Debug).

%% @private
system_code_change([Name, StateName, StateData, Mod, Time],
		   _Module, OldVsn, Extra) ->
    case catch Mod:code_change(OldVsn, StateName, StateData, Extra) of
	{ok, NewStateName, NewStateData} ->
	    {ok, [Name, NewStateName, NewStateData, Mod, Time]};
	Else -> Else
    end.

%%-----------------------------------------------------------------
%% Format debug messages.  Print them as the call-back module sees
%% them, not as the real erlang messages.  Use trace for that.
%%-----------------------------------------------------------------
print_event(Dev, {in, Msg}, {Name, StateName}) ->
    case Msg of
	{'$gen_event', Event} ->
	    io:format(Dev, "*DBG* ~p got event ~p in state ~w~n",
		      [Name, Event, StateName]);
	{'$gen_all_state_event', Event} ->
	    io:format(Dev,
		      "*DBG* ~p got all_state_event ~p in state ~w~n",
		      [Name, Event, StateName]);
	{timeout, Ref, {'$gen_timer', Message}} ->
	    io:format(Dev,
		      "*DBG* ~p got timer ~p in state ~w~n",
		      [Name, {timeout, Ref, Message}, StateName]);
	{timeout, _Ref, {'$gen_event', Event}} ->
	    io:format(Dev,
		      "*DBG* ~p got timer ~p in state ~w~n",
		      [Name, Event, StateName]);
	_ ->
	    io:format(Dev, "*DBG* ~p got ~p in state ~w~n",
		      [Name, Msg, StateName])
    end;
print_event(Dev, {out, Msg, To, StateName}, Name) ->
    io:format(Dev, "*DBG* ~p sent ~p to ~w~n"
	           "      and switched to state ~w~n",
	      [Name, Msg, To, StateName]);
print_event(Dev, return, {Name, StateName}) ->
    io:format(Dev, "*DBG* ~p switched to state ~w~n",
	      [Name, StateName]).

handle_msg(Msg, Parent, Name, StateName, StateData, Mod, _Time) -> %No debug here
    From = from(Msg),
    case catch dispatch(Msg, Mod, StateName, StateData) of
	{next_state, NStateName, NStateData} ->	    
	    loop(Parent, Name, NStateName, NStateData, Mod, infinity, []);
	{next_state, NStateName, NStateData, Time1} ->
	    loop(Parent, Name, NStateName, NStateData, Mod, Time1, []);
        {reply, Reply, NStateName, NStateData} when From =/= undefined ->
	    reply(From, Reply),
	    loop(Parent, Name, NStateName, NStateData, Mod, infinity, []);
        {reply, Reply, NStateName, NStateData, Time1} when From =/= undefined ->
	    reply(From, Reply),
	    loop(Parent, Name, NStateName, NStateData, Mod, Time1, []);
	{stop, Reason, NStateData} ->
	    terminate(Reason, Name, Msg, Mod, StateName, NStateData, []);
	{stop, Reason, Reply, NStateData} when From =/= undefined ->
	    {'EXIT', R} = (catch terminate(Reason, Name, Msg, Mod,
					   StateName, NStateData, [])),
	    reply(From, Reply),
	    exit(R);
	{'EXIT', What} ->
	    terminate(What, Name, Msg, Mod, StateName, StateData, []);
	Reply ->
	    terminate({bad_return_value, Reply},
		      Name, Msg, Mod, StateName, StateData, [])
    end.

handle_msg(Msg, Parent, Name, StateName, StateData, Mod, _Time, Debug) ->
    From = from(Msg),
    case catch dispatch(Msg, Mod, StateName, StateData) of
	{next_state, NStateName, NStateData} ->
	    Debug1 = sys:handle_debug(Debug, fun print_event/3,
				      {Name, NStateName}, return),
	    loop(Parent, Name, NStateName, NStateData, Mod, infinity, Debug1);
	{next_state, NStateName, NStateData, Time1} ->
	    Debug1 = sys:handle_debug(Debug, fun print_event/3,
				      {Name, NStateName}, return),
	    loop(Parent, Name, NStateName, NStateData, Mod, Time1, Debug1);
        {reply, Reply, NStateName, NStateData} when From =/= undefined ->
	    Debug1 = reply(Name, From, Reply, Debug, NStateName),
	    loop(Parent, Name, NStateName, NStateData, Mod, infinity, Debug1);
        {reply, Reply, NStateName, NStateData, Time1} when From =/= undefined ->
	    Debug1 = reply(Name, From, Reply, Debug, NStateName),
	    loop(Parent, Name, NStateName, NStateData, Mod, Time1, Debug1);
	{stop, Reason, NStateData} ->
	    terminate(Reason, Name, Msg, Mod, StateName, NStateData, Debug);
	{stop, Reason, Reply, NStateData} when From =/= undefined ->
	    {'EXIT', R} = (catch terminate(Reason, Name, Msg, Mod,
					   StateName, NStateData, Debug)),
	    _ = reply(Name, From, Reply, Debug, StateName),
	    exit(R);
	{'EXIT', What} ->
	    terminate(What, Name, Msg, Mod, StateName, StateData, Debug);
	Reply ->
	    terminate({bad_return_value, Reply},
		      Name, Msg, Mod, StateName, StateData, Debug)
    end.

dispatch({'$gen_event', Event}, Mod, StateName, StateData) ->
    Mod:StateName(Event, StateData);
dispatch({'$gen_all_state_event', Event}, Mod, StateName, StateData) ->
    Mod:handle_event(Event, StateName, StateData);
dispatch({'$gen_sync_event', From, Event}, Mod, StateName, StateData) ->
    Mod:StateName(Event, From, StateData);
dispatch({'$gen_sync_all_state_event', From, Event},
	 Mod, StateName, StateData) ->
    Mod:handle_sync_event(Event, From, StateName, StateData);
dispatch({timeout, Ref, {'$gen_timer', Msg}}, Mod, StateName, StateData) ->
    Mod:StateName({timeout, Ref, Msg}, StateData);
dispatch({timeout, _Ref, {'$gen_event', Event}}, Mod, StateName, StateData) ->
    Mod:StateName(Event, StateData);
dispatch(Info, Mod, StateName, StateData) ->
    Mod:handle_info(Info, StateName, StateData).

from({'$gen_sync_event', From, _Event}) -> From;
from({'$gen_sync_all_state_event', From, _Event}) -> From;
from(_) -> undefined.

%% Send a reply to the client.

%% @doc Send a reply to synchronous event.
%%
%% @see gen_fsm:reply/2
reply(From, Reply) ->
    genie:reply(From, Reply).

reply(Name, {To, _Tag} = From, Reply, Debug, StateName) ->
    genie:reply(From, Reply),
    sys:handle_debug(Debug, fun print_event/3, Name,
		     {out, Reply, To, StateName}).

%%% ---------------------------------------------------
%%% Terminate the server.
%%% ---------------------------------------------------

-spec terminate(term(), _, _, atom(), _, _, _) -> no_return().

terminate(Reason, Name, Msg, Mod, StateName, StateData, Debug) ->
    case catch Mod:terminate(Reason, StateName, StateData) of
	{'EXIT', R} ->
	    error_info(R, Name, Msg, StateName, StateData, Debug),
	    exit(R);
	_ ->
	    case Reason of
		normal ->
		    exit(normal);
		shutdown ->
		    exit(shutdown);
 		{shutdown,_}=Shutdown ->
 		    exit(Shutdown);
		_ ->
                    FmtStateData =
                        case erlang:function_exported(Mod, format_status, 2) of
                            true ->
                                Args = [get(), StateData],
                                case catch Mod:format_status(terminate, Args) of
                                    {'EXIT', _} -> StateData;
                                    Else -> Else
                                end;
                            _ ->
                                StateData
                        end,
		    error_info(Reason,Name,Msg,StateName,FmtStateData,Debug),
		    exit(Reason)
	    end
    end.

error_info(Reason, Name, Msg, StateName, StateData, Debug) ->
    Reason1 = reason(Reason),
    Str = "** State machine ~p terminating \n" ++
	get_msg_str(Msg) ++
	"** When State == ~p~n"
        "**      Data  == ~p~n"
        "** Reason for termination = ~n** ~p~n",
    format(Str, [Name, get_msg(Msg), StateName, StateData, Reason1]),
    sys:print_log(Debug),
    ok.

async_error_info(Reason, Starter, Name, Args, Debug) ->
    case genie:starter_mode(Starter) of
	async when Reason =/= normal andalso
		   Reason =/= shutdown andalso
		   not (is_tuple(Reason) andalso
			tuple_size(Reason) =:= 2 andalso
			element(1, Reason) =:= shutdown) ->
	    Reason1 = reason(Reason),
	    format("** State machine ~p terminating \n"
		   "** When in ~p ~p ~n"
		   "** When Arguments == ~p~n"
		   "** Reason for termination == ~n** ~p~n",
		   [Name, asynchronous, init, Args, Reason1]),
	    sys:print_log(Debug),
	    ok;
	_ ->
	    ok
    end.

%% @private
async_timeout_info(Name, _Mod, Args, Debug) ->
    format("** State machine ~p timed out ~n"
	   "** When in ~p ~p ~n"
	   "** When Arguments == ~p~n"
	   "** Reason for termination == ~n** ~p~n",
	   [Name, asynchronous, init, Args, killed]),
    sys:print_log(Debug),
    ok.

reason({undef,[{M,F,A,L}|MFAs]} = Reason) ->
    case code:is_loaded(M) of
	false ->
	    {'module could not be loaded',[{M,F,A,L}|MFAs]};
	_ ->
	    case erlang:function_exported(M, F, length(A)) of
		true ->
		    Reason;
		false ->
		    {'function not exported',[{M,F,A,L}|MFAs]}
	    end
    end;
reason(Reason) ->
    Reason.

get_msg_str({'$gen_event', _Event}) ->
    "** Last event in was ~p~n";
get_msg_str({'$gen_sync_event', _Event}) ->
    "** Last sync event in was ~p~n";
get_msg_str({'$gen_all_state_event', _Event}) ->
    "** Last event in was ~p (for all states)~n";
get_msg_str({'$gen_sync_all_state_event', _Event}) ->
    "** Last sync event in was ~p (for all states)~n";
get_msg_str({timeout, _Ref, {'$gen_timer', _Msg}}) ->
    "** Last timer event in was ~p~n";
get_msg_str({timeout, _Ref, {'$gen_event', _Msg}}) ->
    "** Last timer event in was ~p~n";
get_msg_str(_Msg) ->
    "** Last message in was ~p~n".

get_msg({'$gen_event', Event}) -> Event;
get_msg({'$gen_sync_event', Event}) -> Event;
get_msg({'$gen_all_state_event', Event}) -> Event;
get_msg({'$gen_sync_all_state_event', Event}) -> Event;
get_msg({timeout, Ref, {'$gen_timer', Msg}}) -> {timeout, Ref, Msg};
get_msg({timeout, _Ref, {'$gen_event', Event}}) -> Event;
get_msg(Msg) -> Msg.

%%-----------------------------------------------------------------
%% Status information
%%-----------------------------------------------------------------

%% @private
format_status(Opt, StatusData) ->
    [PDict, SysState, Parent, Debug, [Name, StateName, StateData, Mod, _Time]] =
	StatusData,
    Header = genie:format_status_header("Status for state machine",
                                      Name),
    Log = sys:get_debug(log, Debug, []),
    DefaultStatus = [{data, [{"StateData", StateData}]}],
    Specfic =
	case erlang:function_exported(Mod, format_status, 2) of
	    true ->
		case catch Mod:format_status(Opt,[PDict,StateData]) of
		    {'EXIT', _} -> DefaultStatus;
                    StatusList when is_list(StatusList) -> StatusList;
		    Else -> [Else]
		end;
	    _ ->
		DefaultStatus
	end,
    [{header, Header},
     {data, [{"Status", SysState},
	     {"Parent", Parent},
	     {"Logged events", Log},
	     {"StateName", StateName}]} |
     Specfic].
