-module(genie_basic).

-behaviour(genie).

%% api

-export([start_link/3]).
-export([start_link/4]).
-export([call/2]).
-export([call/3]).

%% genie callbacks

-export([init_it/6]).
-export([async_timeout_info/4]).

%% sys callbacks

-export([system_continue/3]).
-export([system_terminate/4]).
-export([system_code_change/4]).

-callback init(Args) -> {ok, State} | {stop, Reason} | ignore when
      Args :: term(),
      State :: term(),
      Reason :: term().

-callback handle_call(Request, From, State) ->
    {reply, Reply, NState} |
    {noreply, NState} |
    {stop, Reason, Reply, NState} |
    {stop, Reason, NState} when
      Request :: term(),
      From :: {(Pid ::pid()), (Tag :: genie:tag() | term())},
      State :: term(),
      Reply :: term(),
      NState :: term(),
      Reason :: term().

-callback handle_info(Msg, State) ->
    {noreply, NState} |
    {stop, Reason, NState} when
      Msg :: term(),
      State :: term(),
      NState :: term(),
      Reason :: term().

-callback code_change(OldVsn, State, Extra) -> {ok, NState} when
      OldVsn :: undefined | term(),
      State :: term(),
      Extra :: term(),
      NState :: term().

-callback terminate(Reason, State) -> any() when
      Reason :: term(),
      State :: term().

%% api

-spec start_link(Mod, Args, Opts) ->
    {ok, Pid} |
    ignore |
    {error, Reason} when
      Mod :: module(),
      Args :: term(),
      Opts :: genie:options(),
      Pid :: pid(),
      Reason :: term().
start_link(Mod, Args, Opts) ->
    genie:start(?MODULE, link, Mod, Args, Opts).

-spec start_link(Name, Mod, Args, Opts) ->
    {ok, Pid} |
    ignore |
    {error, {already_started, Pid}} |
    {error, Reason} when
      Name :: genie:emgr_name(),
      Mod :: module(),
      Args :: term(),
      Opts :: genie:options(),
      Pid :: pid(),
      Reason :: term().
start_link(Name, Mod, Args, Opts) ->
    genie:start(?MODULE, link, Name, Mod, Args, Opts).

-spec call(Process, Request) -> Response when
      Process :: (Pid :: pid()) |
		 (Name :: genie:emgr_name()),
      Request :: term(),
      Response :: term().
call(Process, Request) ->
    genie:call(Process, '$gen_call', Request).

-spec call(Process, Request, Timeout) -> Response when
      Process :: (Pid :: pid()) |
		 (Name :: genie:emgr_name()),
      Request :: term(),
      Timeout :: timeout(),
      Response :: term().
call(Process, Request, Timeout) ->
    genie:call(Process, '$gen_call', Request, Timeout).

%% genie callbacks

%% @private
%%
%% Called by the process spawned by `genie:start/5,6' once registration has
%% taken place.
%%
%% `Starter' is an opaque term contains the pid that called `genie:start/5,6'.
%%
%% `Parent' is the process that called `genie:start/5,6' or the atom `self' if
%% there is no link.
%%
%% `Name' is the current pid (`self()') or a `genie:emgr_name()' used to
%% register the process.
%%
%% `Mod' is the callback module to be used with genie_basic.
%%
%% `Args' are the arguments to be passed to `Mod:init/1'.
%%
%% `Options' are `genie:options()'.
init_it(Starter, self, Name, Mod, Args, Options) ->
    init_it(Starter, self(), Name, Mod, Args, Options);
init_it(Starter, Parent, Name, Mod, Args, Options) ->
    %% Get a format friendly version of `Name'. `Name2' will be an atom, term or
    %% pid. For example if `Name' is `{local, LocalName}', `Name2' will be
    %% `LocalName'. The name should be formatted using `~p':
    %% `io:format("~p", [Name2])'. This is useful when formatting information
    %% about a process for logging.
    Name2 = genie:proc_name(Name),
    %% Get the sys debug structure to use `sys:handle_debug/4'. Note that genie
    %% debug options have an extra flag that `sys:debug_options/1' does not
    %% have, so `genie:debug_options/1,2' should always be used.
    Debug = genie:debug_options(Options),
    %% `case catch' allows `Mod:init/1' to use `throw/1' to return a value, such
    %% as `{stop, Reason}'. `try [... of] ... catch' can also be used. A generic
    %% behaviour will usually catch any errors from its callback module, take
    %% some action - in this case send an acknowledgment to its starter - then
    %% exit with the same reason.
    %%
    %% Callback functions should not do a lot of long running tail recursive
    %% work - as it will not be tail recursive due to the `catch'. If this is
    %% required control should temporarily be passed back to the generic
    %% behaviour. This can be done using timeouts, see `genie_server' for an
    %% example of timeouts. This is not usually a problem as most receives will
    %% be carried out in the generic behaviour before calling the relevant
    %% callback.
    case catch Mod:init(Args) of
	{ok, State} ->
	    %% `genie:init_ack/2' should always be called once initialisation
	    %% has finished - even in the case of failure. The process that
	    %% called `start_link/3,4' blocks until it receives the
	    %% acknowledgement. `start_link/3,4' returns the second argument, in
	    %% this case `{ok, self()}'.
	    genie:init_ack(Starter, {ok, self()}),
	    loop(Parent, Name2, Mod, State, Debug);
	%% A user defined behaviour or callback module may wish to provide
	%% additional information, `Info', to its starter. This can be done by
	%% calling `genie:init_ack(Starter, {ok, self(), Info})'. `Info' can be
	%% any term. `supervisor:start_child/2' and `supervisor:restart_child/2'
	%% will pass on this information to the caller. `Info' is "lost" if
	%% the process is started using the `supervisor' callback `init/1'.
	{ok, State, Info} ->
	    genie:init_ack(Starter, {ok, self(), Info}),
	    loop(Parent, Name2, Mod, State, Debug);
	%% The standard return value when an expected error has occured. Note
	%% that there is no need for the callbacks to employ defensive
	%% programming as errors will be caught and dealt with by the generic
	%% behaviour.
	{stop, Reason} ->
	    %% It is important to unregister the process before calling
	    %% `genie:init_ack/2' because a supervisor may try to restart a
	    %% process on receiving the acknowledgment and fail with
	    %% `{error, {already_started, Pid}}'.
	    genie:unregister_name(Name),
	    genie:init_ack(Starter, {error, Reason}),
	    exit(Reason);
	%% Sometimes there is no error but the process should not continue, in
	%% in this case `ignore' is used. Note that the process exits with
	%% reason `normal'.
	ignore ->
	    genie:unregister_name(Name),
	    genie:init_ack(Starter, ignore),
	    exit(normal);
	%% An error occured in `Mod:init/1'.
	{'EXIT', Reason} ->
	    genie:unregister_name(Name),
	    genie:init_ack(Starter, {error, Reason}),
	    exit(Reason);
	%% Some went wrong. A generic behaviour should handle invalid return
	%% values from its callback by exiting with `{bad_return_value, Other}'.
	Other ->
	    Reason = {bad_return_value, Other},
	    genie:init_ack(Starter, {error, Reason}),
	    exit(Reason)
    end.

%% @private
%% This function is used by `genie' to log an error when an asynchronous
%% initialisation times out.
%%
%% `Name' is the process' register name or if not registered the pid of the
%% process.
%%
%% `Mod' and `Args' are the callback module and argument used to initialise the
%% process.
%%
%% `Debug' is result of `genie:debug_options(Name, Options)', where `Options'
%% is final argument to `genie:start/5,6'.
%%
%% In this case no logging is done but check `genie_server' or `genie_fsm' for
%% an example.
async_timeout_info(_Name, _Mod, _Args, _Debug) ->
    ok.

%% sys callbacks

%% @private
%% Called by `sys:handle_system_msg' to re-enter the loop. The third argument
%% should represent the state of the generic module, including information
%% about its callback module. This argument is used repeatedly throughout
%% handling of system messages.
system_continue(Parent, Debug, [Name, Mod, State]) ->
    loop(Parent, Name, Mod, State, Debug).

%% @private
%% Called by `sys:handle_system_msg' to terminate the loop. The process should
%% handle termination and exit with `Reason'. If termination throws an error
%% then the process may exit with that reason instead.
system_terminate(Reason, Parent, Debug, [Name, Mod, State]) ->
    terminate(Reason, Parent, Name, Mod, State, Debug).

%% @private
%% Called by `sys:handle_system_msg' to upgrade the code of the callback module.
%% Returns {ok, `GenModState'}, where `GenModState' is the last argument passed
%% to `system_continue/3'. Any other return, `Other', will cause
%% `sys:change_code/4,5' to return `{error, Other}' and a failed code upgrade.
%%
%% @see sys:change_code/5
system_code_change([Name, Mod, State], _Module, OldVsn, Extra) ->
    case catch Mod:code_change(OldVsn, State, Extra) of
	{ok, NState} ->
	    {ok, [Name, Mod, NState]};
	Other ->
	    Other
    end.

%% internal

%% Main loop functions.

%% Some generic behaviours may allow a custom initalisation before entering the
%% loop. For an example of this see `genie_server:enter_loop/5'.
loop(Parent, Name, Mod, State, Debug) ->
    %% Doing `receive' in the generic behaviour has two main benefits. It hides
    %% behaviour state and system messages from callback module and allows the
    %% callback module to be reloaded with with `code:load_file(Mod)'.
    %%
    %% However the standard OTP behaviours do not allow for selective receives.
    %% A user define behaviour could use multiple labels (e.g. `$gen_call') and
    %% use pattern matching in the receive clause to keep a subset of labelled
    %% messages in the message queue until after a state change, possibly
    %% temporarily ignoring `system' messages.
    receive
	{system, From, Request} ->
	    handle_system_msg(Request, From, Parent, Name, Mod, State, Debug);
	%% `From' is always a 2-tuple where the first element is the pid of the
	%% process that sent the call, `Caller'. The second element, `_Tag', is
	%% a unique, opaque term used to identify the respone by the caller.
	{'$gen_call', {Caller, _Tag} = From, Request} ->
	    %% In this module `sys:handle_debug/4' is always called even when no
	    %% debugging is done. This can be made more efficient by matching on
	    %% `Debug =:= []' and skipping the calls to `sys:handle_debug/4'.
	    %%
	    %% `sys:handle_debug/4' takes in a debug structure, `Debug', and
	    %% retuens a new one, `Debug2'. The second argument is a format
	    %% fun, that should print the event. The third argument is
	    %% miscellaneous data used to print the argument, in this case we
	    %% use the `Name' and `State'. The last argument is the event. `in'
	    %% and `out' events have special forms, though an event can be any
	    %% term.
	    %%
	    %% `in' events should take the form `{in, Event}' or
	    %% `{in, Event, Caller}'. `Event' can be any term. `Caller' can also
	    %% be any term but should be used to identify the process who sent
	    %% the message. In this case `From' could be used instead.
	    Debug2 = sys:handle_debug(Debug, fun print_event/3, [Name, State],
				      {in, Request, Caller}),
	    handle_call(Request, From, Parent, Name, Mod, State, Debug2);
	Msg ->
	    Debug2 = sys:handle_debug(Debug, fun print_event/3, [Name, State],
				      {in, Msg}),
	    handle_msg(Msg, Parent, Name, Mod, State, Debug2)
    end.

%% `get_state' is a special case, as state must be passed to handle_system_msg
%% as the first element in a 2-tuple. The `State' value can take any form but
%% should match that used in a replace_state fun, usually - as in this case - it
%% will be the state of the callback module.
handle_system_msg(get_state = Req, From, Parent, Name, Mod, State, Debug) ->
    sys:handle_system_msg(Req, From, Parent, ?MODULE, Debug,
			  {State, [Name, Mod, State]});
%% `{replace_state, StateFun}' is a special case, like `get_state' the state
%% must be passed as the first element in a 2-tuple. `StateFun' should be
%% applied to `State' with any exceptions caught. In the case of an exception
%% `State' is used.
handle_system_msg({replace_state, StateFun} = Req, From, Parent, Name, Mod,
		  State, Debug) ->
    NState = try StateFun(State) catch _:_ -> State end,
    sys:handle_system_msg(Req, From, Parent, ?MODULE, Debug,
			  {NState, [Name, Mod, NState]});
%% Handling of other system messages is done by the `sys' module. Once `sys' has
%% finished it will call `system_continue/3' with arguments `Parent', `Debug'
%% and final argument matching that passed to `sys:handle_system_msg/6'. If the
%% process should exit `system_terminate/4' will be called instead. This has
%% first argument `Reason', which is reason to exit with, and the remaining
%% arguments are the same as `system_continue/3'.
handle_system_msg(Req, From, Parent, Name, Mod, State, Debug) ->
    sys:handle_system_msg(Req, From, Parent, ?MODULE, Debug,
			  [Name, Mod, State]).

%% Calls sent by `genie:call/3,4' should be used as the main interface to the
%% callback module. If an invalid call arrives a callback module should reply
%% with a suitable error and may exit (depending on the importance of its
%% state).
handle_call(Request, {To, _Tag} = From, Parent, Name, Mod, State, Debug) ->
    case catch Mod:handle_call(Request, From, State) of
	{reply, Reply, NState} ->
	    %% `out' messages should take the form `{out, Event, To}' where
	    %% `Event' is any term and `To' is the target pid.
	    Debug2 = sys:handle_debug(Debug, fun print_event/3, [Name, NState],
				      {out, {reply, Reply}, To}),
	    genie:reply(From, Reply),
	    loop(Parent, Name, Mod, State, Debug2);
	{noreply, NState} ->
	    Debug2 = sys:handle_debug(Debug, fun print_event/3, [Name, NState],
				      {out, noreply, To}),
	    loop(Parent, Name, Mod, State, Debug2);
	{stop, Reason, Reply, NState} ->
	    Debug2 = sys:handle_debug(Debug, fun print_event/3, [Name, NState],
				      {out, {reply, Reply}, To}),
	    genie:reply(From, Reply),
	    %% Process shoud exit with same reason as returned even if
	    %% `Mod:terminate/2' throws an exception.
	    _ = (catch terminate(Reason, Parent, Name, Mod, State, Debug2)),
	    exit(Reason);
	{stop, Reason, NState} ->
	    Debug2 = sys:handle_debug(Debug, fun print_event/3, [Name, NState],
				      {out, noreply, To}),
	    _ = (catch terminate(Reason, Parent, Name, Mod, State, Debug2)),
	    exit(Reason);
	{'EXIT', Reason} ->
	    terminate(Reason, Parent, Name, Mod, State, Debug);
	Other ->
	    Reason = {bad_return_value, Other},
	    terminate(Reason, Parent, Name, Mod, State, Debug)
    end.

%% A generic behaviour should provide a callback to handle miscellaneous or
%% unexpected messages. The callback module will usually ignore (and perhaps
%% log) an unexpected message.
handle_msg(Msg, Parent, Name, Mod, State, Debug) ->
    case catch Mod:handle_info(Msg, State) of
	{noreply, NState} ->
	    loop(Parent, Name, Mod, NState, Debug);
	{stop, Reason, NState} ->
	    _ = (catch terminate(Reason, Parent, Name, Mod, NState, Debug)),
	    exit(Reason);
	{'EXIT', Reason} ->
	    terminate(Reason, Parent, Name, Mod, State, Debug);
	Other ->
	    Reason = {bad_return_value, Other},
	    terminate(Reason, Parent, Name, Mod, State, Debug)
    end.

%% Function used to print events by `sys:handle_debug/4', it is the second
%% argument in `sys:hande_debug/4' calls.
%% `IoDevice' is the default device to log to, `Event' is an event logged using
%% `sys:handle_debug/4'. The third argument is any extra data, passed as the
%% third argument to `sys:handle_debug/4', required to format the debug message,
%% `genie_server' uses this term to provided a format friendly name of the
%% process.
print_event(IoDevice, Event, [Name, State]) ->
    io:format(IoDevice, "*DBG* ~p event ~p while state ~p",
	      [Name, Event, State]).

terminate(Reason, _Parent, _Name, Mod, State, Debug) ->
    %% Usually a generic behaviour will log an error after it calls
    %% `Mod:terminate/1' when it terminates with an abnormal reason (i.e. not
    %% `normal', `shutdown' or `{shutdown, Term}'). See `genie_server' for an
    %% example. Note that `proc_lib' is used to spawn the process so a crash
    %% report will also be sent in these cases, which can be logged by sasl or a
    %% custom error_logger handler.
    Result = (catch Mod:terminate(State)),
    %% A generic behaviour should print the logged events stored in the `Debug'
    %% structure before exiting.
    sys:print_log(Debug),
    case Result of
	%% `Mod:terminate/1' raised an exception (not a throw), exit with that
	%% reason instead of `Reason'. Note that the exit reason of
	%% `terminate/6' is caught when `{stop, Reason, ...}' is returned from a
	%% callback function, and then `exit(Reason)' is called.
	{'EXIT', Reason2} ->
	    exit(Reason2);
	_Other ->
	    exit(Reason)
    end.
