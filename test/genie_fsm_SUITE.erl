%%
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
-module(genie_fsm_SUITE).

-include_lib("test_server/include/test_server.hrl").

%% Test cases
-export([all/0, groups/0,init_per_suite/1, end_per_suite/1,
	 init_per_group/2,end_per_group/2, init_per_testcase/2]).

-export([start1/1, start2/1, start3/1, start4/1, start5/1, start6/1,
	 start7/1, start8/1, start9/1, start10/1, start11/1, start12/1,
	 start13/1]).

-export([ abnormal1/1, abnormal2/1]).

-export([shutdown/1]).

-export([send_list/1]).

-export([ sys1/1, call_format_status/1, error_format_status/1, get_state/1, replace_state/1]).

-export([hibernate/1,hiber_idle/3,hiber_wakeup/3,hiber_idle/2,hiber_wakeup/2]).

-export([enter_loop/1]).

-export([async_start1/1, async_start2/1, async_start3/1, async_start4/1,
	 async_start5/1, async_start6/1, async_start7/1, async_start8/1,
	 async_start9/1, async_start10/1, async_start11/1, async_start12/1,
	 async_start13/1, async_exit/1, async_timer_timeout/1]).

%% Exports for apply
-export([do_msg/1, do_sync_msg/1]).
-export([enter_loop/2]).

% The genie_fsm behaviour
-export([init/1, handle_event/3, handle_sync_event/4, terminate/3,
	 handle_info/3, format_status/2]).
-export([idle/2,	idle/3,
	 timeout/2,
	 wfor_conf/2,	wfor_conf/3,
	 connected/2,	connected/3]).
-export([state0/3]).
	 

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%


all() ->
    [{group, start}, {group, abnormal}, shutdown, send_list,
     {group, sys}, hibernate, enter_loop, {group, async}].

groups() ->
    [{start, [],
      [start1, start2, start3, start4, start5, start6, start7,
       start8, start9, start10, start11, start12, start13]},
     {abnormal, [], [abnormal1, abnormal2]},
     {sys, [],
      [sys1, call_format_status, error_format_status, get_state, replace_state]},
    {async, [],
      [async_start1, async_start2, async_start3, async_start4, async_start5,
       async_start6, async_start7, async_start8, async_start9, async_start10,
       async_start11, async_start12, async_start13, async_exit,
       async_timer_timeout]}].

init_per_suite(Config) ->
    Config.

end_per_suite(_Config) ->
    ok.

init_per_group(_GroupName, Config) ->
    Config.

end_per_group(_GroupName, Config) ->
    Config.

init_per_testcase(get_state, Config) ->
    case erlang:function_exported(sys, get_state, 2) of
        false ->
            {skip, {not_exported, {sys, get_state, 2}}};
        true ->
            Config
    end;
init_per_testcase(replace_state, Config) ->
    case erlang:function_exported(sys, replace_state, 3) of
        false ->
            {skip, {not_exported, {sys, replace_state, 3}}};
        true ->
            Config
    end;
init_per_testcase(_Testcase, Config) ->
    Config.

%% anonymous
start1(Config) when is_list(Config) ->
    %%OldFl = process_flag(trap_exit, true),

    ?line {ok, Pid0} = genie_fsm:start_link(genie_fsm_SUITE, [], []),
    ?line ok = do_func_test(Pid0),
    ?line ok = do_sync_func_test(Pid0),
    stop_it(Pid0),
%%    ?line stopped = genie_fsm:sync_send_all_state_event(Pid0, stop),
%%    ?line {'EXIT', {timeout,_}} = 
%%	(catch genie_fsm:sync_send_event(Pid0, hej)),

    ?line test_server:messages_get(),
    %%process_flag(trap_exit, OldFl),
   ok.

%% anonymous w. shutdown
start2(Config) when is_list(Config) ->
    %% Dont link when shutdown
    ?line {ok, Pid0} = genie_fsm:start(genie_fsm_SUITE, [], []),
    ?line ok = do_func_test(Pid0),
    ?line ok = do_sync_func_test(Pid0),
    ?line shutdown_stopped = 
	genie_fsm:sync_send_all_state_event(Pid0, stop_shutdown),
    ?line {'EXIT', {noproc,_}} = 
	(catch genie_fsm:sync_send_event(Pid0, hej)),

    ?line test_server:messages_get(),
    ok.

%% anonymous with timeout
start3(Config) when is_list(Config) ->
    %%OldFl = process_flag(trap_exit, true),

    ?line {ok, Pid0} = genie_fsm:start(genie_fsm_SUITE, [], [{timeout,5}]),
    ?line ok = do_func_test(Pid0),
    ?line ok = do_sync_func_test(Pid0),
    ?line stop_it(Pid0),
    
    ?line {error, timeout} = genie_fsm:start(genie_fsm_SUITE, sleep,
					   [{timeout,5}]),

    test_server:messages_get(),
    %%process_flag(trap_exit, OldFl),
    ok.

%% anonymous with ignore
start4(suite) -> [];
start4(Config) when is_list(Config) ->
    OldFl = process_flag(trap_exit, true),

    ?line ignore = genie_fsm:start(genie_fsm_SUITE, ignore, []),

    test_server:messages_get(),
    process_flag(trap_exit, OldFl),
    ok.

%% anonymous with stop
start5(suite) -> [];
start5(Config) when is_list(Config) ->
    OldFl = process_flag(trap_exit, true),

    ?line {error, stopped} = genie_fsm:start(genie_fsm_SUITE, stop, []),

    test_server:messages_get(),
    process_flag(trap_exit, OldFl),
    ok.

%% anonymous linked
start6(Config) when is_list(Config) ->
    ?line {ok, Pid} = genie_fsm:start_link(genie_fsm_SUITE, [], []),
    ?line ok = do_func_test(Pid),
    ?line ok = do_sync_func_test(Pid),
    ?line stop_it(Pid),

    test_server:messages_get(),

    ok.

%% global register linked
start7(Config) when is_list(Config) ->
    ?line {ok, Pid} = 
	genie_fsm:start_link({global, my_fsm}, genie_fsm_SUITE, [], []),
    ?line {error, {already_started, Pid}} =
	genie_fsm:start_link({global, my_fsm}, genie_fsm_SUITE, [], []),
    ?line {error, {already_started, Pid}} =
	genie_fsm:start({global, my_fsm}, genie_fsm_SUITE, [], []),
    
    ?line ok = do_func_test(Pid),
    ?line ok = do_sync_func_test(Pid),
    ?line ok = do_func_test({global, my_fsm}),
    ?line ok = do_sync_func_test({global, my_fsm}),
    ?line stop_it({global, my_fsm}),
    
    test_server:messages_get(),
    ok.


%% local register
start8(Config) when is_list(Config) ->
    %%OldFl = process_flag(trap_exit, true),

    ?line {ok, Pid} = 
	genie_fsm:start({local, my_fsm}, genie_fsm_SUITE, [], []),
    ?line {error, {already_started, Pid}} =
	genie_fsm:start({local, my_fsm}, genie_fsm_SUITE, [], []),

    ?line ok = do_func_test(Pid),
    ?line ok = do_sync_func_test(Pid),
    ?line ok = do_func_test(my_fsm),
    ?line ok = do_sync_func_test(my_fsm),
    ?line stop_it(Pid),
    
    test_server:messages_get(),
    %%process_flag(trap_exit, OldFl),
    ok.

%% local register linked
start9(Config) when is_list(Config) ->
    %%OldFl = process_flag(trap_exit, true),

    ?line {ok, Pid} = 
	genie_fsm:start_link({local, my_fsm}, genie_fsm_SUITE, [], []),
    ?line {error, {already_started, Pid}} =
	genie_fsm:start({local, my_fsm}, genie_fsm_SUITE, [], []),

    ?line ok = do_func_test(Pid),
    ?line ok = do_sync_func_test(Pid),
    ?line ok = do_func_test(my_fsm),
    ?line ok = do_sync_func_test(my_fsm),
    ?line stop_it(Pid),
    
    test_server:messages_get(),
    %%process_flag(trap_exit, OldFl),
    ok.

%% global register
start10(Config) when is_list(Config) ->
    ?line {ok, Pid} = 
	genie_fsm:start({global, my_fsm}, genie_fsm_SUITE, [], []),
    ?line {error, {already_started, Pid}} =
	genie_fsm:start({global, my_fsm}, genie_fsm_SUITE, [], []),
    ?line {error, {already_started, Pid}} =
	genie_fsm:start_link({global, my_fsm}, genie_fsm_SUITE, [], []),
    
    ?line ok = do_func_test(Pid),
    ?line ok = do_sync_func_test(Pid),
    ?line ok = do_func_test({global, my_fsm}),
    ?line ok = do_sync_func_test({global, my_fsm}),
    ?line stop_it({global, my_fsm}),
    
    test_server:messages_get(),
    ok.


%% Stop registered processes
start11(Config) when is_list(Config) ->
    ?line {ok, Pid} = 
	genie_fsm:start_link({local, my_fsm}, genie_fsm_SUITE, [], []),
    ?line stop_it(Pid),

    ?line {ok, _Pid1} = 
	genie_fsm:start_link({local, my_fsm}, genie_fsm_SUITE, [], []),
    ?line stop_it(my_fsm),
    
    ?line {ok, Pid2} = 
	genie_fsm:start({global, my_fsm}, genie_fsm_SUITE, [], []),
    ?line stop_it(Pid2),
    receive after 1 -> true end,
    ?line Result = 
	genie_fsm:start({global, my_fsm}, genie_fsm_SUITE, [], []),
    io:format("Result = ~p~n",[Result]),
    ?line {ok, _Pid3} = Result, 
    ?line stop_it({global, my_fsm}),

    test_server:messages_get(),
    ok.

%% Via register linked
start12(Config) when is_list(Config) ->
    ?line dummy_via:reset(),
    ?line {ok, Pid} =
	genie_fsm:start_link({via, dummy_via, my_fsm}, genie_fsm_SUITE, [], []),
    ?line {error, {already_started, Pid}} =
	genie_fsm:start_link({via, dummy_via, my_fsm}, genie_fsm_SUITE, [], []),
    ?line {error, {already_started, Pid}} =
	genie_fsm:start({via, dummy_via, my_fsm}, genie_fsm_SUITE, [], []),

    ?line ok = do_func_test(Pid),
    ?line ok = do_sync_func_test(Pid),
    ?line ok = do_func_test({via, dummy_via, my_fsm}),
    ?line ok = do_sync_func_test({via, dummy_via, my_fsm}),
    ?line stop_it({via, dummy_via, my_fsm}),

    test_server:messages_get(),
    ok.

%% anonymous with ignore
start13(suite) -> [];
start13(Config) when is_list(Config) ->
    OldFl = process_flag(trap_exit, true),

    ?line {ok, Pid, extra} = genie_fsm:start_link(genie_fsm_SUITE, extra, []),
    ?line stop_it(Pid),

    test_server:messages_get(),
    process_flag(trap_exit, OldFl),
    ok.

%% Check that time outs in calls work
abnormal1(suite) -> [];
abnormal1(Config) when is_list(Config) ->
    {ok, Pid} = genie_fsm:start({local, my_fsm}, genie_fsm_SUITE, [], []),

    %% timeout call.
    delayed = genie_fsm:sync_send_event(my_fsm, {delayed_answer,1}, 100),
    {'EXIT',{timeout,_}} =
    (catch genie_fsm:sync_send_event(my_fsm, {delayed_answer,10}, 1)),
    ?line stop_it(Pid),
    test_server:messages_get(),
    ok.

%% Check that bad return values makes the fsm crash. Note that we must
%% trap exit since we must link to get the real bad_return_ error
abnormal2(suite) -> [];
abnormal2(Config) when is_list(Config) ->
    OldFl = process_flag(trap_exit, true),
    ?line {ok, Pid} = 
	genie_fsm:start_link(genie_fsm_SUITE, [], []),

    %% bad return value in the genie_fsm loop
    ?line {'EXIT',{{bad_return_value, badreturn},_}} =
	(catch genie_fsm:sync_send_event(Pid, badreturn)),
    
    test_server:messages_get(),
    process_flag(trap_exit, OldFl),
    ok.

shutdown(Config) when is_list(Config) ->
    ?line error_logger_forwarder:register(),

    process_flag(trap_exit, true),

    ?line {ok,Pid0} = genie_fsm:start_link(genie_fsm_SUITE, [], []),
    ?line ok = do_func_test(Pid0),
    ?line ok = do_sync_func_test(Pid0),
    ?line {shutdown,reason} = 
	genie_fsm:sync_send_all_state_event(Pid0, stop_shutdown_reason),
    receive {'EXIT',Pid0,{shutdown,reason}} -> ok end,
    process_flag(trap_exit, false),

    ?line {'EXIT', {noproc,_}} = 
	(catch genie_fsm:sync_send_event(Pid0, hej)),

    receive
	Any ->
	    ?line io:format("Unexpected: ~p", [Any]),
	    ?line ?t:fail()
    after 500 ->
	    ok
    end,

    ok.

send_list(Config) when is_list(Config) ->
    ?line dummy_via:reset(),

    ?line {ok, Pid} =
	genie_fsm:start({local, my_test_name},
			genie_fsm_SUITE, [], []),
    ?line {ok, Pid2} = genie_fsm:start(genie_fsm_SUITE, [], []),
    ?line {ok, Pid3} = genie_fsm:start(genie_fsm_SUITE, [], []),
    ?line {ok, Pid4} =
	genie_fsm:start({global, my_test_name}, genie_fsm_SUITE, [], []),
    ?line {ok, Pid5} =
	genie_fsm:start({via, dummy_via, my_test_name},
			genie_fsm_SUITE, [], []),

    ?line ok = genie_fsm:send_list_event([my_test_name, Pid2, {Pid3, pidref},
					  {global, my_test_name},
					  {via, dummy_via, my_test_name}],
					 {connect, self()}),
    ?line ok = rec_accepts(5),
    ?line ok = genie_fsm:send_list_all_state_event([my_test_name, Pid2,
						    {Pid3, pidref},
						    {global, my_test_name},
						    {via, dummy_via,
						     my_test_name}],
						   {stop, self()}),
    ?line receive
	      {Pid, stopped} ->
		  ok
	  after 1000 ->
		    test_server:fail(stop)
	  end,
    ?line receive
	      {Pid2, stopped} ->
		  ok
	  after 1000 ->
		    test_server:fail(stop)
	  end,
    ?line receive
	      {Pid3, stopped} ->
		  ok
	  after 1000 ->
		    test_server:fail(stop)
	  end,
    ?line receive
	      {Pid4, stopped} ->
		  ok
	  after 1000 ->
		    test_server:fail(stop)
	  end,
    ?line receive
	      {Pid5, stopped} ->
		  ok
	  after 1000 ->
		    test_server:fail(stop)
	  end,

    ok.

rec_accepts(0) ->
    ok;
rec_accepts(N) ->
	receive
	    accept ->
		rec_accepts(N-1)
	after
	    1000 ->
		error
	end.

sys1(Config) when is_list(Config) ->
    ?line {ok, Pid} = 
	genie_fsm:start(genie_fsm_SUITE, [], []),
    ?line {status, Pid, {module,genie_fsm}, _} = sys:get_status(Pid),
    ?line sys:suspend(Pid),
    ?line {'EXIT', {timeout,_}} = 
	(catch genie_fsm:sync_send_event(Pid, hej)),
    ?line sys:resume(Pid),
    ?line stop_it(Pid).

call_format_status(Config) when is_list(Config) ->
    ?line {ok, Pid} = genie_fsm:start(genie_fsm_SUITE, [], []),
    ?line Status = sys:get_status(Pid),
    ?line {status, Pid, _Mod, [_PDict, running, _, _, Data]} = Status,
    ?line [format_status_called | _] = lists:reverse(Data),
    ?line stop_it(Pid),

    %% check that format_status can handle a name being an atom (pid is
    %% already checked by the previous test)
    ?line {ok, Pid2} = genie_fsm:start({local, gfsm}, genie_fsm_SUITE, [], []),
    ?line Status2 = sys:get_status(gfsm),
    ?line {status, Pid2, _Mod, [_PDict2, running, _, _, Data2]} = Status2,
    ?line [format_status_called | _] = lists:reverse(Data2),
    ?line stop_it(Pid2),

    %% check that format_status can handle a name being a term other than a
    %% pid or atom
    GlobalName1 = {global, "CallFormatStatus"},
    ?line {ok, Pid3} = genie_fsm:start(GlobalName1, genie_fsm_SUITE, [], []),
    ?line Status3 = sys:get_status(GlobalName1),
    ?line {status, Pid3, _Mod, [_PDict3, running, _, _, Data3]} = Status3,
    ?line [format_status_called | _] = lists:reverse(Data3),
    ?line stop_it(Pid3),
    GlobalName2 = {global, {name, "term"}},
    ?line {ok, Pid4} = genie_fsm:start(GlobalName2, genie_fsm_SUITE, [], []),
    ?line Status4 = sys:get_status(GlobalName2),
    ?line {status, Pid4, _Mod, [_PDict4, running, _, _, Data4]} = Status4,
    ?line [format_status_called | _] = lists:reverse(Data4),
    ?line stop_it(Pid4),

    %% check that format_status can handle a name being a term other than a
    %% pid or atom
    ?line dummy_via:reset(),
    %% Prior to and including R15B gen did not have via support via, and sys
    %% uses gen.
    case catch gen:call({via, global, via_test}, '$via_test', test, 1) of
        {'EXIT', {function_clause, _}} ->
            {skip, via_not_supported};
        _ ->
            ViaName1 = {via, dummy_via, "CallFormatStatus"},
            ?line {ok, Pid5} = genie_fsm:start(ViaName1, genie_fsm_SUITE, [],
                                               []),
            ?line Status5 = sys:get_status(ViaName1),
            ?line {status, Pid5, _Mod,
                   [_PDict5, running, _, _, Data5]} = Status5,
            ?line [format_status_called | _] = lists:reverse(Data5),
            ?line stop_it(Pid5),
            ViaName2 = {via, dummy_via, {name, "term"}},
            ?line {ok, Pid6} = genie_fsm:start(ViaName2, genie_fsm_SUITE, [],
                                               []),
            ?line Status6 = sys:get_status(ViaName2),
            ?line {status, Pid6, _Mod,
                   [_PDict6, running, _, _, Data6]} = Status6,
            ?line [format_status_called | _] = lists:reverse(Data6),
            ?line stop_it(Pid6)
    end.



error_format_status(Config) when is_list(Config) ->
    ?line error_logger_forwarder:register(),
    OldFl = process_flag(trap_exit, true),
    StateData = "called format_status",
    ?line {ok, Pid} = genie_fsm:start(genie_fsm_SUITE, {state_data, StateData}, []),
    %% bad return value in the genie_fsm loop
    ?line {'EXIT',{{bad_return_value, badreturn},_}} =
	(catch genie_fsm:sync_send_event(Pid, badreturn)),
    receive
	{error,_GroupLeader,{Pid,
			     "** State machine"++_,
			     [Pid,{_,_,badreturn},idle,StateData,_]}} ->
	    ok;
	Other ->
	    ?line io:format("Unexpected: ~p", [Other]),
	    ?line ?t:fail()
    end,
    ?t:messages_get(),
    process_flag(trap_exit, OldFl),
    ok.

get_state(Config) when is_list(Config) ->
    State = self(),
    {ok, Pid} = genie_fsm:start(?MODULE, {state_data, State}, []),
    {idle, State} = sys:get_state(Pid),
    {idle, State} = sys:get_state(Pid, 5000),
    stop_it(Pid),

    %% check that get_state can handle a name being an atom (pid is
    %% already checked by the previous test)
    {ok, Pid2} = genie_fsm:start({local, gfsm}, genie_fsm_SUITE, {state_data, State}, []),
    {idle, State} = sys:get_state(gfsm),
    {idle, State} = sys:get_state(gfsm, 5000),
    stop_it(Pid2),
    ok.

replace_state(Config) when is_list(Config) ->
    State = self(),
    {ok, Pid} = genie_fsm:start(?MODULE, {state_data, State}, []),
    {idle, State} = sys:get_state(Pid),
    NState1 = "replaced",
    Replace1 = fun({StateName, _}) -> {StateName, NState1} end,
    {idle, NState1} = sys:replace_state(Pid, Replace1),
    {idle, NState1} = sys:get_state(Pid),
    NState2 = "replaced again",
    Replace2 = fun({idle, _}) -> {state0, NState2} end,
    {state0, NState2} = sys:replace_state(Pid, Replace2, 5000),
    {state0, NState2} = sys:get_state(Pid),
    %% verify no change in state if replace function crashes
    Replace3 = fun(_) -> error(fail) end,
    {state0, NState2} = sys:replace_state(Pid, Replace3),
    {state0, NState2} = sys:get_state(Pid),
    stop_it(Pid),
    ok.

%% Hibernation
hibernate(suite) -> [];
hibernate(Config) when is_list(Config) ->
    OldFl = process_flag(trap_exit, true),

    ?line {ok, Pid0} = genie_fsm:start_link(?MODULE, hiber_now, []),
    ?line receive after 1000 -> ok end,
    ?line {current_function,{erlang,hibernate,3}} = 
	erlang:process_info(Pid0,current_function),
    ?line stop_it(Pid0),
    test_server:messages_get(),


    ?line {ok, Pid} = genie_fsm:start_link(?MODULE, hiber, []),
    ?line true = ({current_function,{erlang,hibernate,3}} =/= erlang:process_info(Pid,current_function)),
    ?line hibernating = genie_fsm:sync_send_event(Pid,hibernate_sync),
    ?line receive after 1000 -> ok end,
    ?line {current_function,{erlang,hibernate,3}} = 
	erlang:process_info(Pid,current_function),
    ?line good_morning  = genie_fsm:sync_send_event(Pid,wakeup_sync),
    ?line receive after 1000 -> ok end,
    ?line true = ({current_function,{erlang,hibernate,3}} =/= erlang:process_info(Pid,current_function)),
    ?line hibernating = genie_fsm:sync_send_event(Pid,hibernate_sync),
    ?line receive after 1000 -> ok end,
    ?line {current_function,{erlang,hibernate,3}} = 
	erlang:process_info(Pid,current_function),
    ?line five_more  = genie_fsm:sync_send_event(Pid,snooze_sync),
    ?line receive after 1000 -> ok end,
    ?line {current_function,{erlang,hibernate,3}} = 
	erlang:process_info(Pid,current_function),
    ?line good_morning  = genie_fsm:sync_send_event(Pid,wakeup_sync),
    ?line receive after 1000 -> ok end,
    ?line true = ({current_function,{erlang,hibernate,3}} =/= erlang:process_info(Pid,current_function)),
    ?line ok = genie_fsm:send_event(Pid,hibernate_async),
    ?line receive after 1000 -> ok end,
    ?line {current_function,{erlang,hibernate,3}} = 
	erlang:process_info(Pid,current_function),
    ?line ok  = genie_fsm:send_event(Pid,wakeup_async),
    ?line receive after 1000 -> ok end,
    ?line true = ({current_function,{erlang,hibernate,3}} =/= erlang:process_info(Pid,current_function)),
    ?line ok = genie_fsm:send_event(Pid,hibernate_async),
    ?line receive after 1000 -> ok end,
    ?line {current_function,{erlang,hibernate,3}} = 
	erlang:process_info(Pid,current_function),
    ?line ok  = genie_fsm:send_event(Pid,snooze_async),
    ?line receive after 1000 -> ok end,
    ?line {current_function,{erlang,hibernate,3}} = 
	erlang:process_info(Pid,current_function),
    ?line ok = genie_fsm:send_event(Pid,wakeup_async),
    ?line receive after 1000 -> ok end,
    ?line true = ({current_function,{erlang,hibernate,3}} =/= erlang:process_info(Pid,current_function)),
    ?line Pid ! hibernate_later,
    ?line true = ({current_function,{erlang,hibernate,3}} =/= erlang:process_info(Pid,current_function)),
    ?line receive after 2000 -> ok end,
    ?line ({current_function,{erlang,hibernate,3}} = erlang:process_info(Pid,current_function)),
    ?line 'alive!' = genie_fsm:sync_send_event(Pid,'alive?'),
    ?line true = ({current_function,{erlang,hibernate,3}} =/= erlang:process_info(Pid,current_function)),
    ?line Pid ! hibernate_now,
    ?line receive after 1000 -> ok end,
    ?line ({current_function,{erlang,hibernate,3}} = erlang:process_info(Pid,current_function)),
    ?line 'alive!' = genie_fsm:sync_send_event(Pid,'alive?'),
    ?line true = ({current_function,{erlang,hibernate,3}} =/= erlang:process_info(Pid,current_function)),
    

    ?line hibernating = genie_fsm:sync_send_all_state_event(Pid,hibernate_sync),
    ?line receive after 1000 -> ok end,
    ?line {current_function,{erlang,hibernate,3}} = 
	erlang:process_info(Pid,current_function),
    ?line good_morning  = genie_fsm:sync_send_all_state_event(Pid,wakeup_sync),
    ?line receive after 1000 -> ok end,
    ?line true = ({current_function,{erlang,hibernate,3}} =/= erlang:process_info(Pid,current_function)),
    ?line hibernating = genie_fsm:sync_send_all_state_event(Pid,hibernate_sync),
    ?line receive after 1000 -> ok end,
    ?line {current_function,{erlang,hibernate,3}} = 
	erlang:process_info(Pid,current_function),
    ?line five_more  = genie_fsm:sync_send_all_state_event(Pid,snooze_sync),
    ?line receive after 1000 -> ok end,
    ?line {current_function,{erlang,hibernate,3}} = 
	erlang:process_info(Pid,current_function),
    ?line good_morning  = genie_fsm:sync_send_all_state_event(Pid,wakeup_sync),
    ?line receive after 1000 -> ok end,
    ?line true = ({current_function,{erlang,hibernate,3}} =/= erlang:process_info(Pid,current_function)),
    ?line ok = genie_fsm:send_all_state_event(Pid,hibernate_async),
    ?line receive after 1000 -> ok end,
    ?line {current_function,{erlang,hibernate,3}} = 
	erlang:process_info(Pid,current_function),
    ?line ok  = genie_fsm:send_all_state_event(Pid,wakeup_async),
    ?line receive after 1000 -> ok end,
    ?line true = ({current_function,{erlang,hibernate,3}} =/= erlang:process_info(Pid,current_function)),
    ?line ok = genie_fsm:send_all_state_event(Pid,hibernate_async),
    ?line receive after 1000 -> ok end,
    ?line {current_function,{erlang,hibernate,3}} = 
	erlang:process_info(Pid,current_function),
    ?line ok  = genie_fsm:send_all_state_event(Pid,snooze_async),
    ?line receive after 1000 -> ok end,
    ?line {current_function,{erlang,hibernate,3}} = 
	erlang:process_info(Pid,current_function),
    ?line ok = genie_fsm:send_all_state_event(Pid,wakeup_async),
    ?line receive after 1000 -> ok end,
    ?line true = ({current_function,{erlang,hibernate,3}} =/= erlang:process_info(Pid,current_function)),

    ?line hibernating = genie_fsm:sync_send_all_state_event(Pid,hibernate_sync),
    ?line receive after 1000 -> ok end,
    ?line {current_function,{erlang,hibernate,3}} = 
	erlang:process_info(Pid,current_function),
    ?line sys:suspend(Pid),
    ?line receive after 1000 -> ok end,
    ?line {current_function,{erlang,hibernate,3}} = erlang:process_info(Pid,current_function),
    ?line sys:resume(Pid),
    ?line receive after 1000 -> ok end,
    ?line {current_function,{erlang,hibernate,3}} = erlang:process_info(Pid,current_function),

    ?line receive after 1000 -> ok end,
    ?line {current_function,{erlang,hibernate,3}} = 
	erlang:process_info(Pid,current_function),
    ?line good_morning  = genie_fsm:sync_send_all_state_event(Pid,wakeup_sync),
    ?line receive after 1000 -> ok end,
    ?line true = ({current_function,{erlang,hibernate,3}} =/= erlang:process_info(Pid,current_function)),
    ?line stop_it(Pid),
    test_server:messages_get(),
    process_flag(trap_exit, OldFl),
    ok.



%%sys1(suite) -> [];
%%sys1(_) ->

enter_loop(suite) ->
    [];
enter_loop(doc) ->
    ["Test genie_fsm:enter_loop/4,5,6"];
enter_loop(Config) when is_list(Config) ->
    OldFlag = process_flag(trap_exit, true),

    ?line dummy_via:reset(),

    %% Locally registered process + {local, Name}
    ?line {ok, Pid1a} =
	proc_lib:start_link(?MODULE, enter_loop, [local, local]),
    ?line yes = genie_fsm:sync_send_event(Pid1a, 'alive?'),
    ?line stopped = genie_fsm:sync_send_event(Pid1a, stop),
    receive
	{'EXIT', Pid1a, normal} ->
	    ok
    after 5000 ->
	    ?line test_server:fail(genie_fsm_did_not_die)
    end,

    %% Unregistered process + {local, Name}
    ?line {ok, Pid1b} =
	proc_lib:start_link(?MODULE, enter_loop, [anon, local]),
    receive
	{'EXIT', Pid1b, process_not_registered} ->
	    ok
    after 5000 ->
	    ?line test_server:fail(genie_fsm_did_not_die)
    end,

    %% Globally registered process + {global, Name}
    ?line {ok, Pid2a} =
	proc_lib:start_link(?MODULE, enter_loop, [global, global]),
    ?line yes = genie_fsm:sync_send_event(Pid2a, 'alive?'),
    ?line stopped = genie_fsm:sync_send_event(Pid2a, stop),
    receive
	{'EXIT', Pid2a, normal} ->
	    ok
    after 5000 ->
	    ?line test_server:fail(genie_fsm_did_not_die)
    end,

    %% Unregistered process + {global, Name}
    ?line {ok, Pid2b} =
	proc_lib:start_link(?MODULE, enter_loop, [anon, global]),
    receive
	{'EXIT', Pid2b, process_not_registered_globally} ->
	    ok
    after 5000 ->
	    ?line test_server:fail(genie_fsm_did_not_die)
    end,

    %% Unregistered process + no name
    ?line {ok, Pid3} =
	proc_lib:start_link(?MODULE, enter_loop, [anon, anon]),
    ?line yes = genie_fsm:sync_send_event(Pid3, 'alive?'),
    ?line stopped = genie_fsm:sync_send_event(Pid3, stop),
    receive
	{'EXIT', Pid3, normal} ->
	    ok
    after 5000 ->
	    ?line test_server:fail(genie_fsm_did_not_die)
    end,

    %% Process not started using proc_lib
    ?line Pid4 =
	spawn_link(genie_fsm, enter_loop, [?MODULE, [], state0, []]),
    receive
	{'EXIT', Pid4, process_was_not_started_by_proc_lib} ->
	    ok
    after 5000 ->
	    ?line test_server:fail(genie_fsm_did_not_die)
    end,

    %% Make sure I am the parent, ie that ordering a shutdown will
    %% result in the process terminating with Reason==shutdown
    ?line {ok, Pid5} =
	proc_lib:start_link(?MODULE, enter_loop, [anon, anon]),
    ?line yes = genie_fsm:sync_send_event(Pid5, 'alive?'),
    ?line exit(Pid5, shutdown),
    receive
	{'EXIT', Pid5, shutdown} ->
	    ok
    after 5000 ->
	    ?line test_server:fail(genie_fsm_did_not_die)
    end,

    %% Make sure genie_fsm:enter_loop does not accept {local,Name}
    %% when it's another process than the calling one which is
    %% registered under that name
    register(armitage, self()),
    ?line {ok, Pid6a} =
	proc_lib:start_link(?MODULE, enter_loop, [anon, local]),
    receive
	{'EXIT', Pid6a, process_not_registered} ->
	    ok
    after 1000 ->
	    ?line test_server:fail(genie_fsm_started)
    end,
    unregister(armitage),

    %% Make sure genie_fsm:enter_loop does not accept {global,Name}
    %% when it's another process than the calling one which is
    %% registered under that name
    global:register_name(armitage, self()),
    ?line {ok, Pid6b} =
	proc_lib:start_link(?MODULE, enter_loop, [anon, global]),
    receive
	{'EXIT', Pid6b, process_not_registered_globally} ->
	    ok
    after 1000 ->
	    ?line test_server:fail(genie_fsm_started)
    end,
    global:unregister_name(armitage),

    dummy_via:register_name(armitage, self()),
    ?line {ok, Pid6c} =
	proc_lib:start_link(?MODULE, enter_loop, [anon, via]),
    receive
	{'EXIT', Pid6c, {process_not_registered_via, dummy_via}} ->
	    ok
    after 1000 ->
	    ?line test_server:fail({genie_fsm_started, process_info(self(),
								 messages)})
    end,
    dummy_via:unregister_name(armitage),

    process_flag(trap_exit, OldFlag),
    ok.

enter_loop(Reg1, Reg2) ->
    process_flag(trap_exit, true),
    case Reg1 of
	local -> register(armitage, self());
	global -> global:register_name(armitage, self());
	via -> dummy_via:register_name(armitage, self());
	anon -> ignore
    end,
    proc_lib:init_ack({ok, self()}),
    case Reg2 of
	local ->
	    genie_fsm:enter_loop(?MODULE, [], state0, [], {local,armitage});
	global ->
	    genie_fsm:enter_loop(?MODULE, [], state0, [], {global,armitage});
	via ->
	    genie_fsm:enter_loop(?MODULE, [], state0, [],
			       {via, dummy_via, armitage});
	anon ->
	    genie_fsm:enter_loop(?MODULE, [], state0, [])
    end.

%% async tests

%% anonymous
async_start1(Config) when is_list(Config) ->
    %%OldFl = process_flag(trap_exit, true),

    ?line {ok, Pid0} = genie_fsm:start_link(genie_fsm_SUITE, [],
					    [{async, infinity}]),
    ?line ok = do_func_test(Pid0),
    ?line ok = do_sync_func_test(Pid0),
    stop_it(Pid0),
%%    ?line stopped = genie_fsm:sync_send_all_state_event(Pid0, stop),
%%    ?line {'EXIT', {timeout,_}} = 
%%	(catch genie_fsm:sync_send_event(Pid0, hej)),

    ?line test_server:messages_get(),
    %%process_flag(trap_exit, OldFl),
   ok.

%% anonymous w. shutdown
async_start2(Config) when is_list(Config) ->
    %% Dont link when shutdown
    ?line {ok, Pid0} = genie_fsm:start(genie_fsm_SUITE, [],
				       [{async, infinity}]),
    ?line ok = do_func_test(Pid0),
    ?line ok = do_sync_func_test(Pid0),
    ?line shutdown_stopped = 
	genie_fsm:sync_send_all_state_event(Pid0, stop_shutdown),
    ?line {'EXIT', {noproc,_}} = 
	(catch genie_fsm:sync_send_event(Pid0, hej)),

    ?line test_server:messages_get(),
    ok.

%% anonymous with timeout
async_start3(Config) when is_list(Config) ->
    %%OldFl = process_flag(trap_exit, true),

    ?line {ok, Pid0} = genie_fsm:start(genie_fsm_SUITE, [], [{async, infinity},
							     {timeout, 5}]),
    ?line ok = do_func_test(Pid0),
    ?line ok = do_sync_func_test(Pid0),
    ?line stop_it(Pid0),
    
    ?line {ok, Pid1} = genie_fsm:start(genie_fsm_SUITE, sleep,
					   [{async, infinity}, {timeout,5}]),
    ?line stop_it(Pid1),

    test_server:messages_get(),
    %%process_flag(trap_exit, OldFl),
    ok.

%% anonymous with ignore
async_start4(suite) -> [];
async_start4(Config) when is_list(Config) ->
    OldFl = process_flag(trap_exit, true),

    ?line {ok, Pid} = genie_fsm:start_link(genie_fsm_SUITE, ignore,
					   [{async, infinity}]),
    receive
	{'EXIT', Pid, normal} ->
	    ok
    after 5000 ->
	      test_server:fail(not_stopped)
    end,

    test_server:messages_get(),
    process_flag(trap_exit, OldFl),
    ok.

%% anonymous with stop
async_start5(suite) -> [];
async_start5(Config) when is_list(Config) ->
    OldFl = process_flag(trap_exit, true),

    ?line error_logger_forwarder:register(),

    ?line {ok, Pid1} =
    genie_fsm:start_link(genie_fsm_SUITE, {stop, normal},
			    [{async, infinity}]),
    ?line receive
	      {'EXIT', Pid1, normal} ->
		  ok;
	      {'EXIT', Pid1, Reason} ->
		  ct:print("~p",[Reason])
	  after 5000 ->
		    test_server:fail(not_stopped)
	  end,
    ?line {ok, Pid2} =
    genie_fsm:start_link(genie_fsm_SUITE, {stop, shutdown},
			    [{async, infinity}]),
    ?line receive
	      {'EXIT', Pid2, shutdown} ->
		  ok
	  after 5000 ->
		    test_server:fail(not_stopped)
	  end,
    ?line {ok, Pid3} =
    genie_fsm:start_link(genie_fsm_SUITE, {stop, {shutdown, stopped}},
			    [{async, infinity}]),
    ?line receive
	      {'EXIT', Pid3, {shutdown, stopped}} ->
		  ok
	  after 5000 ->
		    test_server:fail(not_stopped)
	  end,
    ?line {ok, Pid4} =
    genie_fsm:start_link(genie_fsm_SUITE, stop, [{async, infinity}]),
    ?line receive
	      {'EXIT', Pid4, stopped} ->
		  ok
	  after 5000 ->
		    test_server:fail(not_stopped)
	  end,
    ?line receive
	      {error,_GroupLeader4,{Pid4,
				    "** State machine"++_,
				    [Pid4,stop,stopped]}} ->
		  ok;
	      Other4a ->
		  ?line io:format("Unexpected: ~p", [Other4a]),
		  ?line test_server:fail()
	  after 5000 ->
		    test_server:fail(not_logged)
	  end,
    process_flag(trap_exit, OldFl),
    ok.

%% anonymous linked
async_start6(Config) when is_list(Config) ->
    ?line {ok, Pid} = genie_fsm:start_link(genie_fsm_SUITE, [],
					   [{async, infinity}]),
    ?line ok = do_func_test(Pid),
    ?line ok = do_sync_func_test(Pid),
    ?line stop_it(Pid),

    test_server:messages_get(),

    ok.

%% global register linked
async_start7(Config) when is_list(Config) ->
    ?line {ok, Pid} = 
	genie_fsm:start_link({global, my_fsm}, genie_fsm_SUITE, [],
			     [{async, infinity}]),
    ?line {error, {already_started, Pid}} =
	genie_fsm:start_link({global, my_fsm}, genie_fsm_SUITE, [],
			     [{async, infinity}]),
    ?line {error, {already_started, Pid}} =
	genie_fsm:start({global, my_fsm}, genie_fsm_SUITE, [],
			[{async, infinity}]),
    
    ?line ok = do_func_test(Pid),
    ?line ok = do_sync_func_test(Pid),
    ?line ok = do_func_test({global, my_fsm}),
    ?line ok = do_sync_func_test({global, my_fsm}),
    ?line stop_it({global, my_fsm}),
    
    test_server:messages_get(),
    ok.


%% local register
async_start8(Config) when is_list(Config) ->
    %%OldFl = process_flag(trap_exit, true),

    ?line {ok, Pid} = 
	genie_fsm:start({local, my_fsm}, genie_fsm_SUITE, [],
			[{async, infinity}]),
    ?line {error, {already_started, Pid}} =
	genie_fsm:start({local, my_fsm}, genie_fsm_SUITE, [],
			[{async, infinity}]),

    ?line ok = do_func_test(Pid),
    ?line ok = do_sync_func_test(Pid),
    ?line ok = do_func_test(my_fsm),
    ?line ok = do_sync_func_test(my_fsm),
    ?line stop_it(Pid),
    
    test_server:messages_get(),
    %%process_flag(trap_exit, OldFl),
    ok.

%% local register linked
async_start9(Config) when is_list(Config) ->
    %%OldFl = process_flag(trap_exit, true),

    ?line {ok, Pid} = 
	genie_fsm:start_link({local, my_fsm}, genie_fsm_SUITE, [],
			     [{async, infinity}]),
    ?line {error, {already_started, Pid}} =
	genie_fsm:start({local, my_fsm}, genie_fsm_SUITE, [],
			[{async, infinity}]),

    ?line ok = do_func_test(Pid),
    ?line ok = do_sync_func_test(Pid),
    ?line ok = do_func_test(my_fsm),
    ?line ok = do_sync_func_test(my_fsm),
    ?line stop_it(Pid),
    
    test_server:messages_get(),
    %%process_flag(trap_exit, OldFl),
    ok.

%% global register
async_start10(Config) when is_list(Config) ->
    ?line {ok, Pid} = 
	genie_fsm:start({global, my_fsm}, genie_fsm_SUITE, [],
			[{async, infinity}]),
    ?line {error, {already_started, Pid}} =
	genie_fsm:start({global, my_fsm}, genie_fsm_SUITE, [],
			[{async, infinity}]),
    ?line {error, {already_started, Pid}} =
	genie_fsm:start_link({global, my_fsm}, genie_fsm_SUITE, [],
			     [{async, infinity}]),
    
    ?line ok = do_func_test(Pid),
    ?line ok = do_sync_func_test(Pid),
    ?line ok = do_func_test({global, my_fsm}),
    ?line ok = do_sync_func_test({global, my_fsm}),
    ?line stop_it({global, my_fsm}),
    
    test_server:messages_get(),
    ok.


%% Stop registered processes
async_start11(Config) when is_list(Config) ->
    ?line {ok, Pid} = 
	genie_fsm:start_link({local, my_fsm}, genie_fsm_SUITE, [],
			     [{async, infinity}]),
    ?line stop_it(Pid),

    ?line {ok, _Pid1} = 
	genie_fsm:start_link({local, my_fsm}, genie_fsm_SUITE, [],
			     [{async, infinity}]),
    ?line stop_it(my_fsm),
    
    ?line {ok, Pid2} = 
	genie_fsm:start({global, my_fsm}, genie_fsm_SUITE, [],
			[{async, infinity}]),
    ?line stop_it(Pid2),
    receive after 1 -> true end,
    ?line Result = 
	genie_fsm:start({global, my_fsm}, genie_fsm_SUITE, [],
			[{async, infinity}]),
    io:format("Result = ~p~n",[Result]),
    ?line {ok, _Pid3} = Result, 
    ?line stop_it({global, my_fsm}),

    test_server:messages_get(),
    ok.

%% Via register linked
async_start12(Config) when is_list(Config) ->
    ?line dummy_via:reset(),
    ?line {ok, Pid} =
	genie_fsm:start_link({via, dummy_via, my_fsm}, genie_fsm_SUITE, [],
			     [{async, infinity}]),
    ?line {error, {already_started, Pid}} =
	genie_fsm:start_link({via, dummy_via, my_fsm}, genie_fsm_SUITE, [],
			     [{async, infinity}]),
    ?line {error, {already_started, Pid}} =
	genie_fsm:start({via, dummy_via, my_fsm}, genie_fsm_SUITE, [],
			[{async, infinity}]),

    ?line ok = do_func_test(Pid),
    ?line ok = do_sync_func_test(Pid),
    ?line ok = do_func_test({via, dummy_via, my_fsm}),
    ?line ok = do_sync_func_test({via, dummy_via, my_fsm}),
    ?line stop_it({via, dummy_via, my_fsm}),

    test_server:messages_get(),
    ok.

%% anonymous with ignore
async_start13(suite) -> [];
async_start13(Config) when is_list(Config) ->
    OldFl = process_flag(trap_exit, true),

    ?line {ok, Pid} = genie_fsm:start_link(genie_fsm_SUITE, extra,
					   [{async, infinity}]),
    ?line stop_it(Pid),
    test_server:messages_get(),
    process_flag(trap_exit, OldFl),
    ok.

async_exit(_) ->
    OldFl = process_flag(trap_exit, true),

    ?line error_logger_forwarder:register(),

    ?line {ok, Pid1} =
	genie_fsm:start_link(genie_fsm_SUITE, {exit, normal},
				[{async, infinity}]),
    ?line receive
	{'EXIT', Pid1, normal} ->
	    ok
    after 5000 ->
	      test_server:fail(not_stopped)
    end,
     ?line {ok, Pid2} =
	genie_fsm:start_link(genie_fsm_SUITE, {exit, shutdown},
				[{async, infinity}]),
    ?line receive
	{'EXIT', Pid2, shutdown} ->
	    ok
    after 5000 ->
	      test_server:fail(not_stopped)
    end,
    ?line {ok, Pid3} =
	genie_fsm:start_link(genie_fsm_SUITE, {exit, {shutdown, stopped}},
				[{async, infinity}]),
    ?line receive
	{'EXIT', Pid3, {shutdown, stopped}} ->
	    ok
    after 5000 ->
	      test_server:fail(not_stopped)
    end,
    ?line {ok, Pid4} =
	genie_fsm:start_link(genie_fsm_SUITE, {exit, stopped},
				[{async, infinity}]),
    ?line receive
	{'EXIT', Pid4, stopped} ->
	    ok
    after 5000 ->
	      test_server:fail(not_stopped)
    end,
    ?line receive
	{error,_GroupLeader4,{Pid4,
			      "** State machine"++_,
			      [Pid4,{exit, stopped},stopped]}} ->
	    ok;
	Other4a ->
	    ?line io:format("Unexpected: ~p", [Other4a]),
	    ?line test_server:fail()
    after 5000 ->
	      test_server:fail(not_logged)
    end,
    process_flag(trap_exit, OldFl),
    ok.

async_timer_timeout(_) ->
    OldFl = process_flag(trap_exit, true),

    ?line error_logger_forwarder:register(),

    ?line {ok, Pid} = genie_fsm:start_link(genie_fsm_SUITE, sleep,
					      [{async, 100}]),
    receive
	{'EXIT', Pid, killed} ->
	    ok
    after
	5000 ->
	    test_server:fail(not_killed)
    end,
    receive
	{error,_GroupLeader,{_Timer,
			      "** State machine"++_,
			      [Pid,sleep,killed]}} ->
	    ok;
	Other ->
	    ?line io:format("Unexpected: ~p", [Other]),
	    ?line test_server:fail()
    after 5000 ->
	      test_server:fail(not_logged)
    end,
    process_flag(trap_exit, OldFl),
    ok.




%%
%% Functionality check
%%

wfor(Msg) ->
    receive 
	Msg -> ok
    after 5000 -> 
	    throw(timeout)
    end.


stop_it(FSM) ->
    ?line stopped = genie_fsm:sync_send_all_state_event(FSM, stop),
    ?line {'EXIT',_} = 	(catch genie_fsm:sync_send_event(FSM, hej)),
    ok.



do_func_test(FSM) ->
    ok = genie_fsm:send_all_state_event(FSM, {'alive?', self()}),
    wfor(yes),
    ok = do_connect(FSM),
    ok = genie_fsm:send_all_state_event(FSM, {'alive?', self()}),
    wfor(yes),
    test_server:do_times(3, ?MODULE, do_msg, [FSM]),
    ok = genie_fsm:send_all_state_event(FSM, {'alive?', self()}),
    wfor(yes),
    ok = do_disconnect(FSM),
    ok = genie_fsm:send_all_state_event(FSM, {'alive?', self()}),
    wfor(yes),
    ok.


do_connect(FSM) ->
    check_state(FSM, idle),
    genie_fsm:send_event(FSM, {connect, self()}),
    wfor(accept),
    check_state(FSM, wfor_conf),
    genie_fsm:send_event(FSM, confirmation),
    check_state(FSM, connected),
    ok.

do_msg(FSM) ->
    check_state(FSM, connected),
    R = make_ref(),
    ok = genie_fsm:send_event(FSM, {msg, R, self(), hej_pa_dig_quasimodo}),
    wfor({ak, R}).


do_disconnect(FSM) ->
    ok = genie_fsm:send_event(FSM, disconnect),
    check_state(FSM, idle).

check_state(FSM, State) ->
    case genie_fsm:sync_send_all_state_event(FSM, {get, self()}) of
	{state, State, _} -> ok
    end.

do_sync_func_test(FSM) ->
    yes = genie_fsm:sync_send_all_state_event(FSM, 'alive?'),
    ok = do_sync_connect(FSM),
    yes = genie_fsm:sync_send_all_state_event(FSM, 'alive?'),
    test_server:do_times(3, ?MODULE, do_sync_msg, [FSM]),
    yes = genie_fsm:sync_send_all_state_event(FSM, 'alive?'),
    ok = do_sync_disconnect(FSM),
    yes = genie_fsm:sync_send_all_state_event(FSM, 'alive?'),
    check_state(FSM, idle),
    ok = genie_fsm:sync_send_event(FSM, {timeout,200}),
    yes = genie_fsm:sync_send_all_state_event(FSM, 'alive?'),
    check_state(FSM, idle),
    ok.


do_sync_connect(FSM) ->
    check_state(FSM, idle),
    accept = genie_fsm:sync_send_event(FSM, {connect, self()}),
    check_state(FSM, wfor_conf),
    yes = genie_fsm:sync_send_event(FSM, confirmation),
    check_state(FSM, connected),
    ok.

do_sync_msg(FSM) ->
    check_state(FSM, connected),
    R = make_ref(),
    Res = genie_fsm:sync_send_event(FSM, {msg, R, self(), hej_pa_dig_quasimodo}),
    if  Res == {ak, R} ->
	    ok
    end.

do_sync_disconnect(FSM) ->
    yes = genie_fsm:sync_send_event(FSM, disconnect),
    check_state(FSM, idle).

    

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%
%% The Finite State Machine
%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

init(ignore) ->
    ignore;
init(stop) ->
    {stop, stopped};
init(stop_shutdown) ->
    {stop, shutdown};
init({stop, _Reason} = Result) ->
    Result;
init({exit, Reason}) ->
    exit(Reason);
init(sleep) ->
    test_server:sleep(1000),
    {ok, idle, data};
init({timeout, T}) ->
    {ok, idle, state, T};
init(extra) ->
    {info, idle, state, extra};
init({extra, T}) ->
    {ok, idle, state, T};
init(hiber) ->
    {ok, hiber_idle, []};
init(hiber_now) ->
    {ok, hiber_idle, [], hibernate};
init({state_data, StateData}) ->
    {ok, idle, StateData};
init(_) ->
    {ok, idle, state_data}.


terminate({From, stopped}, State, _Data) ->
    From ! {self(), {stopped, State}},
    ok;
terminate(_Reason, _State, _Data) ->
    ok.


idle({connect, Pid}, Data) ->
    Pid ! accept,
    {next_state, wfor_conf, Data};
idle(badreturn, _Data) ->
    badreturn;
idle(_, Data) ->
    {next_state, idle, Data}.

idle({connect, _Pid}, _From, Data) ->
    {reply, accept, wfor_conf, Data};
idle({delayed_answer, T}, _From, Data) ->
    test_server:sleep(T),
    {reply, delayed, idle, Data};
idle(badreturn, _From, _Data) ->
    badreturn;
idle({timeout,Time}, From, _Data) ->
    genie_fsm:send_event_after(Time, {timeout,Time}),
    {next_state, timeout, From};
idle(_, _From, Data) ->
    {reply, 'eh?', idle, Data}.

timeout({timeout,Time}, From) ->
    Ref = genie_fsm:start_timer(Time, {timeout,Time}),
    {next_state, timeout, {From,Ref}};
timeout({timeout,Ref,{timeout,Time}}, {From,Ref}) ->
    Ref2 = genie_fsm:start_timer(Time, ok),
    Cref = genie_fsm:start_timer(Time, cancel),
    Time4 = Time*4,
    receive after Time4 -> ok end,
    genie_fsm:cancel_timer(Cref),
    {next_state, timeout, {From,Ref2}};
timeout({timeout,Ref2,ok},{From,Ref2}) ->
    genie_fsm:reply(From, ok),
    {next_state, idle, state}.

wfor_conf(confirmation, Data) ->
    {next_state, connected, Data};
wfor_conf(_, Data) ->
    {next_state, idle, Data}.

wfor_conf(confirmation, _From, Data) ->
    {reply, yes, connected, Data};
wfor_conf(_, _From, Data) ->
    {reply, 'eh?', idle, Data}.

connected({msg, Ref, From, _Msg}, Data) ->
    From ! {ak, Ref},
    {next_state, connected, Data};
connected(disconnect, Data) ->
    {next_state, idle, Data};
connected(_, Data) ->
    {next_state, connected, Data}.

connected({msg, Ref, _From, _Msg}, _, Data) ->
    {reply, {ak, Ref}, connected, Data};
connected(disconnect, _From, Data) ->
    {reply, yes, idle, Data};
connected(_, _, Data) ->
    {reply, 'eh?', connected, Data}.

state0('alive?', _From, Data) ->
    {reply, yes, state0, Data};
state0(stop, _From, Data) ->
    {stop, normal, stopped, Data}.

hiber_idle('alive?', _From, Data) ->
    {reply, 'alive!', hiber_idle, Data};
hiber_idle(hibernate_sync, _From, Data) ->
    {reply, hibernating, hiber_wakeup, Data,hibernate}.
hiber_idle(timeout, hibernate_me) ->  % Arrive here from 
				              % handle_info(hibernate_later,...)
    {next_state, hiber_idle, [], hibernate};
hiber_idle(hibernate_async, Data) ->
    {next_state,hiber_wakeup, Data, hibernate}.

hiber_wakeup(wakeup_sync,_From,Data) ->
    {reply,good_morning,hiber_idle,Data};
hiber_wakeup(snooze_sync,_From,Data) ->
    {reply,five_more,hiber_wakeup,Data,hibernate}.
hiber_wakeup(wakeup_async,Data) ->
    {next_state,hiber_idle,Data};
hiber_wakeup(snooze_async,Data) ->
    {next_state,hiber_wakeup,Data,hibernate}.
    

handle_info(hibernate_now, _SName, _State) ->  % Arrive here from by direct ! from testcase
    {next_state, hiber_idle, [], hibernate};
handle_info(hibernate_later, _SName, _State) ->
    {next_state, hiber_idle, hibernate_me, 1000};

handle_info(Info, _State, Data) ->
    {stop, {unexpected,Info}, Data}.

handle_event(hibernate_async, hiber_idle, Data) ->
    {next_state,hiber_wakeup, Data, hibernate};
handle_event(wakeup_async,hiber_wakeup,Data) ->
    {next_state,hiber_idle,Data};
handle_event(snooze_async,hiber_wakeup,Data) ->
    {next_state,hiber_wakeup,Data,hibernate};
handle_event({get, Pid}, State, Data) ->
    Pid ! {state, State, Data},
    {next_state, State, Data};
handle_event(stop, _State, Data) ->
    {stop, normal, Data};
handle_event(stop_shutdown, _State, Data) ->
    {stop, shutdown, Data};
handle_event(stop_shutdown_reason, _State, Data) ->
    {stop, shutdown, Data};
handle_event({stop, Pid}, _State, Data) ->
    Pid ! {self(), stopped},
    {stop, normal, Data};
handle_event({'alive?', Pid}, State, Data) ->
    Pid ! yes,
    {next_state, State, Data}.

handle_sync_event(hibernate_sync, _From, hiber_idle, Data) ->
    {reply, hibernating, hiber_wakeup, Data, hibernate};
handle_sync_event(wakeup_sync,_From,hiber_wakeup, Data) ->
    {reply,good_morning,hiber_idle,Data};
handle_sync_event(snooze_sync,_From,hiber_wakeup,Data) ->
    {reply,five_more,hiber_wakeup,Data,hibernate};
handle_sync_event('alive?', _From, State, Data) ->
    {reply, yes, State, Data};
handle_sync_event(stop, _From, _State, Data) ->
    {stop, normal, stopped, Data};
handle_sync_event(stop_shutdown, _From, _State, Data) ->
    {stop, shutdown, shutdown_stopped, Data};
handle_sync_event(stop_shutdown_reason, _From, _State, Data) ->
    {stop, {shutdown,reason}, {shutdown,reason}, Data};
handle_sync_event({get, _Pid}, _From, State, Data) ->
    {reply, {state, State, Data}, State, Data}.

format_status(terminate, [_Pdict, StateData]) ->
    StateData;
format_status(normal, [_Pdict, _StateData]) ->
    [format_status_called].
