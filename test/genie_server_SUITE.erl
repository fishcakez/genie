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
-module(genie_server_SUITE).

-include_lib("test_server/include/test_server.hrl").
-include_lib("kernel/include/inet.hrl").

-export([init_per_testcase/2, end_per_testcase/2]).

-export([all/0, groups/0,init_per_suite/1, end_per_suite/1, 
	 init_per_group/2,end_per_group/2]).
-export([start/1, crash/1, call/1, cast/1, cast_fast/1,
	 cast_list/1, cast_list_fast/1,
	 info/1, abcast/1, multicall/1, multicall_down/1,
	 call_remote1/1, call_remote2/1, call_remote3/1,
	 call_remote_n1/1, call_remote_n2/1, call_remote_n3/1,
	 call_list/1,
	 call_list_remote1/1, call_list_remote2/1, call_list_remote3/1,
	 call_list_remote_n1/1, call_list_remote_n2/1, call_list_remote_n3/1,
	 spec_init/1,
	 spec_init_local_registered_parent/1, 
	 spec_init_global_registered_parent/1,
	 otp_5854/1, hibernate/1, otp_7669/1, call_format_status/1,
	 error_format_status/1, get_state/1, replace_state/1, call_with_huge_message_queue/1,
	 call_list_with_huge_message_queue/1
	]).

%% async tests
-export([async_start/1, async_stop/1, async_exit/1, async_timer_timeout/1]).

% spawn export
-export([spec_init_local/2, spec_init_global/2, spec_init_via/2,
	 spec_init_default_timeout/2, spec_init_global_default_timeout/2,
         spec_init_anonymous/1,
	 spec_init_anonymous_default_timeout/1,
	 spec_init_not_proc_lib/1, cast_fast_messup/0]).


% The genie_server behaviour
-export([init/1, handle_call/3, handle_cast/2,
	 handle_info/2, terminate/2, format_status/2]).

all() -> 
    [start, crash, call, cast, cast_fast, cast_list, cast_list_fast,
     info, abcast, multicall, multicall_down, call_remote1, call_remote2,
     call_remote3, call_remote_n1, call_remote_n2,
     call_remote_n3, call_list, call_list_remote1,
     call_list_remote2, call_list_remote3, call_list_remote_n1,
     call_list_remote_n2, call_list_remote_n3, spec_init,
     spec_init_local_registered_parent,
     spec_init_global_registered_parent, otp_5854, hibernate,
     otp_7669, call_format_status, error_format_status,
     get_state, replace_state,
     call_with_huge_message_queue, call_list_with_huge_message_queue,
     {group, async}].

groups() -> 
    [{async, [], [async_start, async_stop, async_exit, async_timer_timeout]}].

init_per_suite(Config) ->
    Config.

end_per_suite(_Config) ->
    ok.

init_per_group(_GroupName, Config) ->
    Config.

end_per_group(_GroupName, Config) ->
    Config.


-define(default_timeout, ?t:minutes(1)).
 
init_per_testcase(Case, Config) when Case == call_remote1;
				     Case == call_remote2;
				     Case == call_remote3;
				     Case == call_remote_n1;
				     Case == call_remote_n2;
				     Case == call_remote_n3;
				     Case == call_list_remote1;
				     Case == call_list_remote2;
				     Case == call_list_remote3;
				     Case == call_list_remote_n1;
				     Case == call_list_remote_n2;
				     Case == call_list_remote_n3 ->
    {ok,N} = start_node(hubba),
    ?line Dog = ?t:timetrap(?default_timeout),
    [{node,N},{watchdog, Dog} | Config];
init_per_testcase(get_state, Config) ->
    case erlang:function_exported(sys, get_state, 2) of
        false ->
            {skip, {not_exported, {sys, get_state, 2}}};
        true ->
            ?line Dog = ?t:timetrap(?default_timeout),
            [{watchdog, Dog} | Config]
    end;
init_per_testcase(replace_state, Config) ->
    case erlang:function_exported(sys, replace_state, 3) of
        false ->
            {skip, {not_exported, {sys, replace_state, 3}}};
        true ->
            ?line Dog = ?t:timetrap(?default_timeout),
            [{watchdog, Dog} | Config]
   end;
init_per_testcase(_Case, Config) ->
    ?line Dog = ?t:timetrap(?default_timeout),
    [{watchdog, Dog} | Config].
end_per_testcase(_Case, Config) ->
    case proplists:get_value(node, Config) of
	undefined ->
	    ok;
	N ->
	    test_server:stop_node(N)
    end,
    Dog = ?config(watchdog, Config),
    test_server:timetrap_cancel(Dog),
    ok.


%% --------------------------------------
%% Start and stop a genie_server.
%% --------------------------------------

start(suite) -> [];
start(Config) when is_list(Config) ->
    OldFl = process_flag(trap_exit, true),

    %% anonymous
    ?line {ok, Pid0} = genie_server:start(genie_server_SUITE, [], []),
    ?line ok = genie_server:call(Pid0, started_p),
    ?line ok = genie_server:call(Pid0, stop),
    ?line busy_wait_for_process(Pid0,600),
    ?line {'EXIT', {noproc,_}} = (catch genie_server:call(Pid0, started_p, 1)),

    %% anonymous with timeout
    ?line {ok, Pid00} = genie_server:start(genie_server_SUITE, [],
					 [{timeout,1000}]),
    ?line ok = genie_server:call(Pid00, started_p),
    ?line ok = genie_server:call(Pid00, stop),
    ?line {error, timeout} = genie_server:start(genie_server_SUITE, sleep,
					      [{timeout,100}]),

    %% anonymous with ignore
    ?line ignore = genie_server:start(genie_server_SUITE, ignore, []),

    %% anonymous with info
    ?line {ok, Pid01, extra} = genie_server:start(genie_server_SUITE, extra,
						  []),
    ?line ok = genie_server:call(Pid01, started_p),
    ?line ok = genie_server:call(Pid01, stop),

    %% anonymous with stop
    ?line {error, stopped} = genie_server:start(genie_server_SUITE, stop, []),

    %% anonymous linked
    ?line {ok, Pid1} =
	genie_server:start_link(genie_server_SUITE, [], []),
    ?line ok = genie_server:call(Pid1, started_p),
    ?line ok = genie_server:call(Pid1, stop),
    ?line receive
	      {'EXIT', Pid1, stopped} ->
		  ok
	  after 5000 ->
		  test_server:fail(not_stopped)
	  end,

    %% local register
    ?line {ok, Pid2} =
	genie_server:start({local, my_test_name},
			 genie_server_SUITE, [], []),
    ?line ok = genie_server:call(my_test_name, started_p),
    ?line {error, {already_started, Pid2}} =
	genie_server:start({local, my_test_name},
			 genie_server_SUITE, [], []),
    ?line ok = genie_server:call(my_test_name, stop),

    ?line busy_wait_for_process(Pid2,600),

    ?line {'EXIT', {noproc,_}} = (catch genie_server:call(Pid2, started_p, 10)),

    %% local register linked
    ?line {ok, Pid3} =
	genie_server:start_link({local, my_test_name},
			      genie_server_SUITE, [], []), 
    ?line ok = genie_server:call(my_test_name, started_p),
    ?line {error, {already_started, Pid3}} =
	genie_server:start({local, my_test_name},
			 genie_server_SUITE, [], []),
    ?line ok = genie_server:call(my_test_name, stop),
    ?line receive
	      {'EXIT', Pid3, stopped} ->
		  ok
	  after 5000 ->
		  test_server:fail(not_stopped)
	  end,

    %% global register
    ?line {ok, Pid4} =
	genie_server:start({global, my_test_name},
			 genie_server_SUITE, [], []),
    ?line ok = genie_server:call({global, my_test_name}, started_p),
    ?line {error, {already_started, Pid4}} =
	genie_server:start({global, my_test_name},
			 genie_server_SUITE, [], []),
    ?line ok = genie_server:call({global, my_test_name}, stop),
    test_server:sleep(1),
    ?line {'EXIT', {noproc,_}} = (catch genie_server:call(Pid4, started_p, 10)),

    %% global register linked
    ?line {ok, Pid5} =
	genie_server:start_link({global, my_test_name},
			      genie_server_SUITE, [], []), 
    ?line ok = genie_server:call({global, my_test_name}, started_p),
    ?line {error, {already_started, Pid5}} =
	genie_server:start({global, my_test_name},
			 genie_server_SUITE, [], []),
    ?line ok = genie_server:call({global, my_test_name}, stop),
    ?line receive
	      {'EXIT', Pid5, stopped} ->
		  ok
	  after 5000 ->
		  test_server:fail(not_stopped)
	  end,

    %% via register
    ?line dummy_via:reset(),
    ?line {ok, Pid6} =
	genie_server:start({via, dummy_via, my_test_name},
			 genie_server_SUITE, [], []),
    ?line ok = genie_server:call({via, dummy_via, my_test_name}, started_p),
    ?line {error, {already_started, Pid6}} =
	genie_server:start({via, dummy_via, my_test_name},
			 genie_server_SUITE, [], []),
    ?line ok = genie_server:call({via, dummy_via, my_test_name}, stop),
    test_server:sleep(1),
    ?line {'EXIT', {noproc,_}} = (catch genie_server:call(Pid6, started_p, 10)),

    %% via register linked
    ?line dummy_via:reset(),
    ?line {ok, Pid7} =
	genie_server:start_link({via, dummy_via, my_test_name},
			      genie_server_SUITE, [], []),
    ?line ok = genie_server:call({via, dummy_via, my_test_name}, started_p),
    ?line {error, {already_started, Pid7}} =
	genie_server:start({via, dummy_via, my_test_name},
			 genie_server_SUITE, [], []),
    ?line ok = genie_server:call({via, dummy_via, my_test_name}, stop),
    ?line receive
	      {'EXIT', Pid7, stopped} ->
		  ok
	  after 5000 ->
		  test_server:fail(not_stopped)
	  end,
    test_server:messages_get(),

    process_flag(trap_exit, OldFl),
    ok.

crash(Config) when is_list(Config) ->
    ?line error_logger_forwarder:register(),

    process_flag(trap_exit, true),

    %% This crash should not generate a crash report.
    ?line {ok,Pid0} = genie_server:start_link(?MODULE, [], []),
    ?line {'EXIT',{{shutdown,reason},_}} =
 	(catch genie_server:call(Pid0, shutdown_reason)),
    receive {'EXIT',Pid0,{shutdown,reason}} -> ok end,

    %% This crash should not generate a crash report.
    ?line {ok,Pid1} = genie_server:start_link(?MODULE, {state,state1}, []),
    ?line {'EXIT',{{shutdown,stop_reason},_}} =
	(catch genie_server:call(Pid1, stop_shutdown_reason)),
    receive {'EXIT',Pid1,{shutdown,stop_reason}} -> ok end,

    %% This crash should not generate a crash report.
    ?line {ok,Pid2} = genie_server:start_link(?MODULE, [], []),
    ?line {'EXIT',{shutdown,_}} =
 	(catch genie_server:call(Pid2, exit_shutdown)),
    receive {'EXIT',Pid2,shutdown} -> ok end,

    %% This crash should not generate a crash report.
    ?line {ok,Pid3} = genie_server:start_link(?MODULE, {state,state3}, []),
    ?line {'EXIT',{shutdown,_}} =
	(catch genie_server:call(Pid3, stop_shutdown)),
    receive {'EXIT',Pid3,shutdown} -> ok end,

    process_flag(trap_exit, false),

    %% This crash should generate a crash report and a report
    %% from genie_server.
    ?line {ok,Pid4} = genie_server:start(?MODULE, {state,state4}, []),
    ?line {'EXIT',{crashed,_}} = (catch genie_server:call(Pid4, crash)),
    receive
	{error,_GroupLeader4,{Pid4,
			      "** Generic server"++_,
			      [Pid4,crash,state4,crashed]}} ->
	    ok;
	Other4a ->
 	    ?line io:format("Unexpected: ~p", [Other4a]),
 	    ?line ?t:fail()
    end,
    receive
	{error_report,_,{Pid4,crash_report,[List4|_]}} ->
	    {exit,crashed,_} = proplists:get_value(error_info, List4),
	    Pid4 = proplists:get_value(pid, List4);
	Other4 ->
	    ?line io:format("Unexpected: ~p", [Other4]),
	    ?line ?t:fail()
    end,

    receive
	Any ->
	    ?line io:format("Unexpected: ~p", [Any]),
	    ?line ?t:fail()
    after 500 ->
	    ok
    end,

    ok.

%% --------------------------------------
%% Test genie_server:call and handle_call.
%% Test all different return values from
%% handle_call.
%% --------------------------------------

call(suite) -> [];
call(Config) when is_list(Config) ->
    OldFl = process_flag(trap_exit, true),

    ?line {ok, _Pid} =
	genie_server:start_link({local, my_test_name},
			      genie_server_SUITE, [], []),

    ?line ok = genie_server:call(my_test_name, started_p),
    ?line delayed = genie_server:call(my_test_name, {delayed_answer,1}),

    %% two requests within a specified time.
    ?line ok = genie_server:call(my_test_name, {call_within, 1000}),
    test_server:sleep(500),
    ?line ok = genie_server:call(my_test_name, next_call),
    ?line ok = genie_server:call(my_test_name, {call_within, 1000}),
    test_server:sleep(1500),
    ?line false = genie_server:call(my_test_name, next_call),
    
    %% timeout call.
    ?line delayed = genie_server:call(my_test_name, {delayed_answer,1}, 30),
    ?line {'EXIT',{timeout,_}} =
	(catch genie_server:call(my_test_name, {delayed_answer,30}, 1)),

    %% bad return value in the genie_server loop from handle_call.
    ?line {'EXIT',{{bad_return_value, badreturn},_}} =
	(catch genie_server:call(my_test_name, badreturn)),

    process_flag(trap_exit, OldFl),
    ok.

%% --------------------------------------
%% Test call to nonexisting processes on remote nodes
%% --------------------------------------

start_node(Name) ->
    ?line Pa = filename:dirname(code:which(?MODULE)),
    ?line Pa2 = filename:dirname(code:which(genie_server)),
    ?line N = test_server:start_node(Name, slave, [{args, " -pa " ++ Pa ++ " "
							  ++ " -pa " ++ Pa2}]),
    %% After starting a slave, it takes a little while until global knows
    %% about it, even if nodes() includes it, so we make sure that global
    %% knows about it before registering something on all nodes.
    global:sync(),
    N.

call_remote1(suite) -> [];
call_remote1(Config) when is_list(Config) ->
    N = hubba,
    ?line Node = proplists:get_value(node,Config),
    ?line {ok, Pid} = rpc:call(Node, genie_server, start,
			       [{global, N}, ?MODULE, [], []]),    
    ?line ok = (catch genie_server:call({global, N}, started_p, infinity)),
    ?line exit(Pid, boom),
    ?line {'EXIT', {Reason, _}} = (catch genie_server:call({global, N},
							 started_p, infinity)),
    ?line true = (Reason == noproc) orelse (Reason == boom),
    ok.

call_remote2(suite) -> [];
call_remote2(Config) when is_list(Config) ->
    ?line N = hubba,
    ?line Node = proplists:get_value(node,Config),

    ?line {ok, Pid} = rpc:call(Node, genie_server, start,
			       [{global, N}, ?MODULE, [], []]),
    ?line ok = (catch genie_server:call(Pid, started_p, infinity)),
    ?line exit(Pid, boom),
    ?line {'EXIT', {Reason, _}} = (catch genie_server:call(Pid,
							 started_p, infinity)),
    ?line true = (Reason == noproc) orelse (Reason == boom),
    ok.

call_remote3(suite) -> [];
call_remote3(Config) when is_list(Config) ->
    ?line Node = proplists:get_value(node,Config),

    ?line {ok, Pid} = rpc:call(Node, genie_server, start,
			       [{local, piller}, ?MODULE, [], []]),
    ?line ok = (catch genie_server:call({piller, Node}, started_p, infinity)),
    ?line exit(Pid, boom),
    ?line {'EXIT', {Reason, _}} = (catch genie_server:call({piller, Node},
							 started_p, infinity)),
    ?line true = (Reason == noproc) orelse (Reason == boom),
    ok.

%% --------------------------------------
%% Test call to nonexisting node
%% --------------------------------------

call_remote_n1(suite) -> [];
call_remote_n1(Config) when is_list(Config) ->
    ?line N = hubba,
    ?line Node = proplists:get_value(node,Config),    
    ?line {ok, _Pid} = rpc:call(Node, genie_server, start,
			       [{global, N}, ?MODULE, [], []]),
    ?line _ = test_server:stop_node(Node),
    ?line {'EXIT', {noproc, _}} =
	(catch genie_server:call({global, N}, started_p, infinity)),

    ok.

call_remote_n2(suite) -> [];
call_remote_n2(Config) when is_list(Config) ->
    ?line N = hubba,
    ?line Node = proplists:get_value(node,Config),

    ?line {ok, Pid} = rpc:call(Node, genie_server, start,
			       [{global, N}, ?MODULE, [], []]),
    ?line _ = test_server:stop_node(Node),
    ?line {'EXIT', {{nodedown, Node}, _}} = (catch genie_server:call(Pid,
							 started_p, infinity)),

    ok.

call_remote_n3(suite) -> [];
call_remote_n3(Config) when is_list(Config) ->
    ?line Node = proplists:get_value(node,Config),

    ?line {ok, _Pid} = rpc:call(Node, genie_server, start,
			       [{local, piller}, ?MODULE, [], []]),
    ?line _ = test_server:stop_node(Node),
    ?line {'EXIT', {{nodedown, Node}, _}} = (catch genie_server:call({piller, Node},
							 started_p, infinity)),

    ok.

%% --------------------------------------
%% Test genie_server:cast and handle_cast.
%% Test all different return values from
%% handle_cast.
%% --------------------------------------

cast(suite) -> [];
cast(Config) when is_list(Config) ->
    ?line {ok, Pid} =
	genie_server:start({local, my_test_name},
			 genie_server_SUITE, [], []),

    ?line ok = genie_server:call(my_test_name, started_p),

    ?line ok = genie_server:cast(my_test_name, {self(),handle_cast}),
    ?line receive
	      {Pid, handled_cast} ->
		  ok
	  after 1000 ->
		  test_server:fail(handle_cast)
	  end,
    
    ?line ok = genie_server:cast(my_test_name, {self(),delayed_cast,1}),
    ?line receive
	      {Pid, delayed} ->
		  ok
	  after 1000 ->
		  test_server:fail(delayed_cast)
	  end,
    
    ?line ok = genie_server:cast(my_test_name, {self(),stop}),
    ?line receive
	      {Pid, stopped} ->
		  ok
	  after 1000 ->
		  test_server:fail(stop)
	  end,
    ok.

cast_fast(suite) -> [];
cast_fast(doc) -> ["Test that cast really return immediately"];
cast_fast(Config) when is_list(Config) ->
    ?line {ok,Node} = start_node(hubba),
    ?line {_,"@"++Host} = lists:splitwith(fun ($@) -> false; (_) -> true end,
					   atom_to_list(Node)),
    ?line FalseNode = list_to_atom("hopp@"++Host),
    ?line true = rpc:cast(Node, ?MODULE, cast_fast_messup, []),
%    ?line io:format("Nodes ~p~n", [rpc:call(N, ?MODULE, cast_fast_messup, [])]),
    ?line test_server:sleep(1000),
    ?line [Node] = nodes(),
    ?line {Time,ok} = test_server:timecall(genie_server, cast, 
					   [{hopp,FalseNode},hopp]),
    ?line true = test_server:stop_node(Node),
    ?line if Time > 1.0 -> % Default listen timeout is about 7.0 s
		  test_server:fail(hanging_cast);
	     true -> 
		  ok
	  end.

cast_list(suite) -> [];
cast_list(Config) when is_list(Config) ->
    ?line dummy_via:reset(),

    ?line {ok, Pid} =
	genie_server:start({local, my_test_name},
			 genie_server_SUITE, [], []),
    ?line {ok, Pid2} = genie_server:start(genie_server_SUITE, [], []),
    ?line {ok, Pid3} = genie_server:start(genie_server_SUITE, [], []),
    ?line {ok, Pid4} =
	genie_server:start({global, my_test_name}, genie_server_SUITE, [], []),
    ?line {ok, Pid5} =
	genie_server:start({via, dummy_via, my_test_name},
			   genie_server_SUITE, [], []),
    ?line ok = genie_server:call(my_test_name, started_p),
    ?line ok = genie_server:call(Pid2, started_p),
    ?line ok = genie_server:call(Pid3, started_p),
    ?line ok = genie_server:call({global, my_test_name}, started_p),
    ?line ok = genie_server:call({via, dummy_via, my_test_name}, started_p),

    ?line ok = genie_server:cast_list([my_test_name, Pid2, {pidref, Pid3},
				       {global, my_test_name},
				       {via, dummy_via, my_test_name}],
				      {self(),handle_cast}),
    ?line receive
	      {Pid, handled_cast} ->
		  ok
	  after 1000 ->
		  test_server:fail(handle_cast)
	  end,
    ?line receive
	      {Pid2, handled_cast} ->
		  ok
	  after 1000 ->
		    test_server:fail(handle_cast)
	  end,
   ?line receive
	      {Pid3, handled_cast} ->
		  ok
	  after 1000 ->
		    test_server:fail(handle_cast)
	  end,
    ?line receive
	      {Pid4, handled_cast} ->
		  ok
	  after 1000 ->
		  test_server:fail(handle_cast)
	  end,
    ?line receive
	      {Pid5, handled_cast} ->
		  ok
	  after 1000 ->
		    test_server:fail(handle_cast)
	  end,

    ?line ok = genie_server:cast_list([my_test_name, Pid2, {pidref, Pid3},
				       {global, my_test_name},
				       {via, dummy_via, my_test_name}],
				      {self(),delayed_cast,1}),
    ?line receive
	      {Pid, delayed} ->
		  ok
	  after 1000 ->
		  test_server:fail(delayed_cast)
	  end,
     ?line receive
	      {Pid2, delayed} ->
		  ok
	  after 1000 ->
		  test_server:fail(delayed_cast)
	  end,
    ?line receive
	      {Pid3, delayed} ->
		  ok
	  after 1000 ->
		  test_server:fail(delayed_cast)
	  end,
     ?line receive
	      {Pid4, delayed} ->
		  ok
	  after 1000 ->
		  test_server:fail(delayed_cast)
	  end,
    ?line receive
	      {Pid5, delayed} ->
		  ok
	  after 1000 ->
		  test_server:fail(delayed_cast)
	  end,
    ?line ok = genie_server:cast_list([my_test_name, Pid2, {pidref, Pid3},
				       {global, my_test_name},
				       {via, dummy_via, my_test_name}],
				       {self(),stop}),
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

cast_list_fast(suite) -> [];
cast_list_fast(doc) -> ["Test that cast really return immediately"];
cast_list_fast(Config) when is_list(Config) ->
    ?line {ok,Node} = start_node(hubba),
    ?line {_,"@"++Host} = lists:splitwith(fun ($@) -> false; (_) -> true end,
					   atom_to_list(Node)),
    ?line FalseNode = list_to_atom("hopp@"++Host),
    ?line true = rpc:cast(Node, ?MODULE, cast_fast_messup, []),
%    ?line io:format("Nodes ~p~n", [rpc:call(N, ?MODULE, cast_fast_messup, [])]),
    ?line test_server:sleep(1000),
    ?line [Node] = nodes(),
    ?line {Time,ok} = test_server:timecall(genie_server, cast_list, 
					   [[{hopp,FalseNode}],hopp]),
    ?line true = test_server:stop_node(Node),
    ?line if Time > 1.0 -> % Default listen timeout is about 7.0 s
		  test_server:fail(hanging_cast);
	     true -> 
		  ok
	  end.

cast_fast_messup() ->
    %% Register a false node: hopp@hostname
    unregister(erl_epmd),
    erl_epmd:start_link(),
    {ok,S} = gen_tcp:listen(0, []),
    {ok,P} = inet:port(S),
    {ok,_Creation} = erl_epmd:register_node(hopp, P),
    receive after infinity -> ok end.

%% --------------------------------------
%% Test handle_info.
%% --------------------------------------

info(suite) -> [];
info(Config) when is_list(Config) ->
    ?line {ok, Pid} =
	genie_server:start({local, my_test_name},
			 genie_server_SUITE, [], []),

    ?line ok = genie_server:call(my_test_name, started_p),

    ?line Pid ! {self(),handle_info},
    ?line receive
	      {Pid, handled_info} ->
		  ok
	  after 1000 ->
		  test_server:fail(handle_info)
	  end,
    
    ?line Pid ! {self(),delayed_info,1},
    ?line receive
	      {Pid, delayed_info} ->
		  ok
	  after 1000 ->
		  test_server:fail(delayed_info)
	  end,
    
    ?line Pid ! {self(),stop},
    ?line receive
	      {Pid, stopped_info} ->
		  ok
	  after 1000 ->
		  test_server:fail(stop_info)
	  end,
    ok.

hibernate(suite) -> [];
hibernate(Config) when is_list(Config) ->
    OldFl = process_flag(trap_exit, true),
    ?line {ok, Pid0} =
	genie_server:start_link({local, my_test_name_hibernate0},
			 genie_server_SUITE, hibernate, []),
    ?line receive after 1000 -> ok end,
    ?line {current_function,{erlang,hibernate,3}} = erlang:process_info(Pid0,current_function),
    ?line ok = genie_server:call(my_test_name_hibernate0, stop),
    receive 
	{'EXIT', Pid0, stopped} ->
 	    ok
    after 5000 ->
	    test_server:fail(genie_server_did_not_die)
    end,

    ?line {ok, Pid} =
	genie_server:start_link({local, my_test_name_hibernate},
			 genie_server_SUITE, [], []),

    ?line ok = genie_server:call(my_test_name_hibernate, started_p),
    ?line true = genie_server:call(my_test_name_hibernate, hibernate),
    ?line receive after 1000 -> ok end,
    ?line {current_function,{erlang,hibernate,3}} = erlang:process_info(Pid,current_function),
    ?line Parent = self(),
    Fun = fun() ->
 		  receive
 		      go ->
 			  ok
 		  end,
 		  receive 
 		  after 1000 ->
 			  ok 
 		  end,
 		  X = erlang:process_info(Pid,current_function),
 		  Pid ! continue,
 		  Parent ! {result,X}
 	  end,
    ?line Pid2 = spawn_link(Fun),
    ?line true = genie_server:call(my_test_name_hibernate, {hibernate_noreply,Pid2}),

    ?line genie_server:cast(my_test_name_hibernate, hibernate_later),
    ?line true = ({current_function,{erlang,hibernate,3}} =/= erlang:process_info(Pid,current_function)),
    ?line receive after 2000 -> ok end,
    ?line ({current_function,{erlang,hibernate,3}} = erlang:process_info(Pid,current_function)),
    ?line ok = genie_server:call(my_test_name_hibernate, started_p),
    ?line true = ({current_function,{erlang,hibernate,3}} =/= erlang:process_info(Pid,current_function)),
    ?line genie_server:cast(my_test_name_hibernate, hibernate_now),
    ?line receive after 1000 -> ok end,
    ?line ({current_function,{erlang,hibernate,3}} = erlang:process_info(Pid,current_function)),
    ?line ok = genie_server:call(my_test_name_hibernate, started_p),
    ?line true = ({current_function,{erlang,hibernate,3}} =/= erlang:process_info(Pid,current_function)),
    ?line Pid ! hibernate_later,
    ?line true = ({current_function,{erlang,hibernate,3}} =/= erlang:process_info(Pid,current_function)),
    ?line receive after 2000 -> ok end,
    ?line ({current_function,{erlang,hibernate,3}} = erlang:process_info(Pid,current_function)),
    ?line ok = genie_server:call(my_test_name_hibernate, started_p),
    ?line true = ({current_function,{erlang,hibernate,3}} =/= erlang:process_info(Pid,current_function)),
    ?line Pid ! hibernate_now,
    ?line receive after 1000 -> ok end,
    ?line ({current_function,{erlang,hibernate,3}} = erlang:process_info(Pid,current_function)),
    ?line ok = genie_server:call(my_test_name_hibernate, started_p),
    ?line true = ({current_function,{erlang,hibernate,3}} =/= erlang:process_info(Pid,current_function)),
    ?line receive
 	      {result,R} ->
 		  ?line  {current_function,{erlang,hibernate,3}} = R
 	  end,
    ?line true = genie_server:call(my_test_name_hibernate, hibernate),
    ?line receive after 1000 -> ok end,
    ?line {current_function,{erlang,hibernate,3}} = erlang:process_info(Pid,current_function),
    ?line sys:suspend(my_test_name_hibernate),
    ?line receive after 1000 -> ok end,
    ?line {current_function,{erlang,hibernate,3}} = erlang:process_info(Pid,current_function),
    ?line sys:resume(my_test_name_hibernate),
    ?line receive after 1000 -> ok end,
    ?line {current_function,{erlang,hibernate,3}} = erlang:process_info(Pid,current_function),
    ?line ok = genie_server:call(my_test_name_hibernate, started_p),
    ?line true = ({current_function,{erlang,hibernate,3}} =/= erlang:process_info(Pid,current_function)),
    
    ?line ok = genie_server:call(my_test_name_hibernate, stop),
    receive 
	{'EXIT', Pid, stopped} ->
 	    ok
    after 5000 ->
	    test_server:fail(genie_server_did_not_die)
    end,
    process_flag(trap_exit, OldFl),
    ok.

%% --------------------------------------
%% Test genie_server:abcast and handle_cast.
%% Test all different return values from
%% handle_cast.
%% --------------------------------------

abcast(suite) -> [];
abcast(Config) when is_list(Config) ->
    ?line {ok, Pid} =
	genie_server:start({local, my_test_name},
			 genie_server_SUITE, [], []),

    ?line ok = genie_server:call(my_test_name, started_p),

    ?line abcast = genie_server:abcast(my_test_name, {self(),handle_cast}),
    ?line receive
	      {Pid, handled_cast} ->
		  ok
	  after 1000 ->
		  test_server:fail(abcast)
	  end,
    
    ?line abcast = genie_server:abcast([node()], my_test_name,
				     {self(),delayed_cast,1}),
    ?line receive
	      {Pid, delayed} ->
		  ok
	  after 1000 ->
		  test_server:fail(delayed_abcast)
	  end,
    
    ?line abcast = genie_server:abcast(my_test_name, {self(),stop}),
    ?line receive
	      {Pid, stopped} ->
		  ok
	  after 1000 ->
		  test_server:fail(abcast_stop)
	  end,
    ok.

%% --------------------------------------
%% Test genie_server:multicall and handle_call.
%% Test all different return values from
%% handle_call.
%% --------------------------------------

multicall(suite) -> [];
multicall(Config) when is_list(Config) ->
    OldFl = process_flag(trap_exit, true),

    ?line {ok, Pid} =
	genie_server:start_link({local, my_test_name},
			      genie_server_SUITE, [], []),

    ?line ok = genie_server:call(my_test_name, started_p),
    Nodes = nodes(),
    Node = node(),
    ?line {[{Node,delayed}],Nodes} =
	   genie_server:multi_call(my_test_name, {delayed_answer,1}),

    %% two requests within a specified time.
    ?line {[{Node,ok}],[]} =
	   genie_server:multi_call([Node], my_test_name, {call_within, 1000}),
    test_server:sleep(500),
    ?line {[{Node,ok}],[]} =
	   genie_server:multi_call([Node], my_test_name, next_call),
    ?line  {[{Node,ok}],[]} =
	    genie_server:multi_call([Node], my_test_name, {call_within, 1000}),
    test_server:sleep(1500),
    ?line {[{Node,false}],[]} =
	   genie_server:multi_call([Node],my_test_name, next_call),

    %% Stop the server.
    ?line {[{Node,ok}],[]} =
	   genie_server:multi_call([Node],my_test_name, stop),
    receive
	{'EXIT', Pid, stopped} -> ok
    after 1000 ->
	    test_server:fail(multicall_stop)
    end,
    
    process_flag(trap_exit, OldFl),

    ok.

%% OTP-3587
multicall_down(suite) -> [];
multicall_down(Config) when is_list(Config) ->
    %% We need a named host which is inaccessible.
    ?line Name = node@test01,

    %% We use 'global' as a genie_server to call.
    ?line {Good, Bad} = genie_server:multi_call([Name, node()],
					      global_name_server,
					      info,
					      3000),
    io:format("good = ~p, bad = ~p~n", [Good, Bad]),
    ?line [Name] = Bad,
    ok.

call_list(suite) -> [];
call_list(Config) when is_list(Config) ->
    OldFl = process_flag(trap_exit, true),

    ?line dummy_via:reset(),

    ?line {ok, _Pid} =
	genie_server:start_link({local, my_test_name},
			      genie_server_SUITE, [], []),

    ?line ok = genie_server:call(my_test_name, started_p),
    ?line {[{my_test_name, delayed}], []} =
	    genie_server:call_list([my_test_name],
				   {delayed_answer, 1}),

    %% two requests within a specified time.
    ?line {[{my_test_name, ok}], []} =
	genie_server:call_list([my_test_name], {call_within, 1000}),
    test_server:sleep(500),
    ?line {[{my_test_name, ok}], []} =
	genie_server:call_list([my_test_name], next_call),
    ?line {[{my_test_name, ok}], []} =
	genie_server:call_list([my_test_name], {call_within, 1000}),
    test_server:sleep(1500),
    ?line {[{my_test_name, false}], []} =
	genie_server:call_list([my_test_name],  next_call),
    
    %% timeout call.
    ?line {[{my_test_name, delayed}], []} =
	genie_server:call_list([my_test_name], {delayed_answer,1}, 30),
    ?line {[], [{my_test_name, timeout}]} =
	(catch genie_server:call_list([my_test_name], {delayed_answer,30}, 1)),

    %% bad return value in the genie_server loop from handle_call.
    ?line {[],[{my_test_name, {bad_return_value, badreturn}}]} =
	(catch genie_server:call_list([my_test_name], badreturn)),

    ?line BadPid1 = spawn(fun() -> ok end),
    ?line BadPid2 = spawn(fun() -> ok end),
    ?line busy_wait_for_process(BadPid1, 5),
    ?line busy_wait_for_process(BadPid2, 5),

    ?line {ok, Pid1} = genie_server:start_link(genie_server_SUITE, [], []),
    ?line {ok, Pid2} = genie_server:start_link(genie_server_SUITE, [], []),
    ?line {ok, Pid3} = genie_server:start_link({via, dummy_via, my_test_name},
					       genie_server_SUITE, [], []),

    %% parellel calls.
    ?line {Replies, Bad} = genie_server:call_list([BadPid1, {bad, BadPid2},
						   Pid1,
						   {good, Pid2},
						   {via, dummy_via,
						    my_test_name}],
						  {delayed_answer, 1000},
						  1500),

    ?line [{good, delayed}, {Pid1, delayed},
	   {{via, dummy_via, my_test_name}, delayed}] = lists:sort(Replies),
    ?line [{bad, noproc}, {BadPid1, noproc}] = lists:sort(Bad),

    %% call same pid several times.
    ?line {[{Pid1, ok}, {Pid1, ok}], [{BadPid1, noproc}, {BadPid1, noproc}]} =
	(catch genie_server:call_list([Pid1, BadPid1, Pid1, BadPid1],
				     started_p)),

    %% Stop the servers.
    ?line {Replies2, []} =
	   genie_server:call_list([Pid1, Pid2, Pid3], stop),
    ?line true = (lists:sort([{Pid1, ok}, {Pid2, ok}, {Pid3, ok}]) ==
		    lists:sort(Replies2)),
    receive
	{'EXIT', Pid1, stopped} -> ok
    after 1000 ->
	    test_server:fail(call_list_stop)
    end,
    receive
	{'EXIT', Pid2, stopped} -> ok
    after 1000 ->
	    test_server:fail(call_list_stop)
    end,
    receive
	{'EXIT', Pid3, stopped} -> ok
    after 1000 ->
	    test_server:fail(call_list_stop)
    end,
    process_flag(trap_exit, OldFl),
    ok.

call_list_remote1(suite) -> [];
call_list_remote1(Config) when is_list(Config) ->
    N = hubba,
    ?line Node = proplists:get_value(node,Config),
    ?line {ok, Pid} = rpc:call(Node, genie_server, start,
			       [{global, N}, ?MODULE, [], []]),    
    ?line {[{{global, N}, ok}], []} =
	(catch genie_server:call_list([{global, N}], started_p, infinity)),
    ?line exit(Pid, boom),
    ?line {[], [{{global, N}, Reason}]} =
	(catch genie_server:call_list([{global, N}], started_p, infinity)),
    ?line true = (Reason == noproc) orelse (Reason == boom),
    ok.

call_list_remote2(suite) -> [];
call_list_remote2(Config) when is_list(Config) ->
    ?line N = hubba,
    ?line Node = proplists:get_value(node,Config),

    ?line {ok, Pid} = rpc:call(Node, genie_server, start,
			       [{global, N}, ?MODULE, [], []]),
    ?line {[{Pid,ok}], []} =
	(catch genie_server:call_list([Pid], started_p, infinity)),
    ?line exit(Pid, boom),
    ?line {[], [{Pid, Reason}]} =
	(catch genie_server:call_list([Pid], started_p, infinity)),
    ?line true = (Reason == noproc) orelse (Reason == boom),
    ok.

call_list_remote3(suite) -> [];
call_list_remote3(Config) when is_list(Config) ->
    ?line Node = proplists:get_value(node,Config),

    ?line {ok, Pid} = rpc:call(Node, genie_server, start,
			       [{local, piller}, ?MODULE, [], []]),
    ?line {[{{piller, Node}, ok}], []} =
	(catch genie_server:call_list([{piller, Node}], started_p, infinity)),
    ?line exit(Pid, boom),
    ?line {[], [{{piller, Node}, Reason}]} =
	(catch genie_server:call_list([{piller, Node}], started_p, infinity)),
    ?line true = (Reason == noproc) orelse (Reason == boom),
    ok.

%% --------------------------------------
%% Test call to nonexisting node
%% --------------------------------------

call_list_remote_n1(suite) -> [];
call_list_remote_n1(Config) when is_list(Config) ->
    ?line N = hubba,
    ?line Node = proplists:get_value(node,Config),    
    ?line {ok, _Pid} = rpc:call(Node, genie_server, start,
			       [{global, N}, ?MODULE, [], []]),
    ?line _ = test_server:stop_node(Node),
    ?line {[], [{{global, N}, noproc}]} =
	(catch genie_server:call_list([{global, N}], started_p, infinity)),

    ok.

call_list_remote_n2(suite) -> [];
call_list_remote_n2(Config) when is_list(Config) ->
    ?line N = hubba,
    ?line Node = proplists:get_value(node,Config),

    ?line {ok, Pid} = rpc:call(Node, genie_server, start,
			       [{global, N}, ?MODULE, [], []]),
    ?line _ = test_server:stop_node(Node),
    ?line {[], [{Pid, {nodedown, Node}}]} =
	(catch genie_server:call_list([Pid], started_p, infinity)),

    ok.

call_list_remote_n3(suite) -> [];
call_list_remote_n3(Config) when is_list(Config) ->
    ?line Node = proplists:get_value(node,Config),

    ?line {ok, _Pid} = rpc:call(Node, genie_server, start,
			       [{local, piller}, ?MODULE, [], []]),
    ?line _ = test_server:stop_node(Node),
    ?line {[], [{{piller, Node}, {nodedown, Node}}]} =
	(catch genie_server:call_list([{piller, Node}], started_p, infinity)),

    ok.


busy_wait_for_process(Pid,N) ->
    case erlang:is_process_alive(Pid) of
	true ->
	    receive
	    after 100 ->
		    ok
	    end,
	    busy_wait_for_process(Pid,N-1);
	_ ->
	    ok
    end.
%%--------------------------------------------------------------
spec_init(doc) ->
    ["Test genie_server:enter_loop/[3,4,5]. Used when you want to write " 
     "your own special init-phase."];
spec_init(suite) ->
    [];
spec_init(Config) when is_list(Config) ->
    
    OldFlag = process_flag(trap_exit, true),

    ?line {ok, Pid0} = start_link(spec_init_local, [{ok, my_server}, []]),
    ?line ok = genie_server:call(Pid0, started_p),
    ?line ok = genie_server:call(Pid0, stop),
    receive 
	{'EXIT', Pid0, stopped} ->
 	    ok
    after 5000 ->
	    test_server:fail(genie_server_did_not_die)
    end,
    
    ?line {ok, Pid01} = start_link(spec_init_local, [{not_ok, my_server}, []]),
    receive 
 	{'EXIT', Pid01, process_not_registered} ->
 	    ok
    after 5000 ->
	    test_server:fail(genie_server_did_not_die)
    end,
    
    ?line {ok, Pid1} = start_link(spec_init_global, [{ok, my_server}, []]),
    ?line ok = genie_server:call(Pid1, started_p),
    ?line ok = genie_server:call(Pid1, stop),
    receive 
	{'EXIT', Pid1, stopped} ->
 	    ok
    after 5000 ->
	    test_server:fail(genie_server_did_not_die)
    end,
    
    ?line {ok, Pid11} = 
	start_link(spec_init_global, [{not_ok, my_server}, []]),

    receive 
	{'EXIT', Pid11, process_not_registered_globally} ->
 	    ok
    after 5000 ->
	    test_server:fail(genie_server_did_not_die)
    end,
    
    ?line {ok, Pid2} = start_link(spec_init_anonymous, [[]]),
    ?line ok = genie_server:call(Pid2, started_p),
    ?line ok = genie_server:call(Pid2, stop),
    receive 
	{'EXIT', Pid2, stopped} ->
 	    ok
    after 5000 ->
	    test_server:fail(genie_server_did_not_die)
    end,
    
    ?line {ok, Pid3} = start_link(spec_init_anonymous_default_timeout, [[]]),
    ?line ok = genie_server:call(Pid3, started_p),
    ?line ok = genie_server:call(Pid3, stop),
    receive 
	{'EXIT', Pid3, stopped} ->
 	    ok
    after 5000 ->
	    test_server:fail(genie_server_did_not_die)
    end,
    
    ?line {ok, Pid4} = 
	start_link(spec_init_default_timeout, [{ok, my_server}, []]),
    ?line ok = genie_server:call(Pid4, started_p),
    ?line ok = genie_server:call(Pid4, stop),
    receive 
	{'EXIT', Pid4, stopped} ->
 	    ok
    after 5000 ->
	    test_server:fail(genie_server_did_not_die)
    end,

    %% Before the OTP-10130 fix this failed because a timeout message
    %% was generated as the spawned process crashed because a {global, Name}
    %% was matched as a timeout value instead of matching on scope.
    {ok, _PidHurra} =
	start_link(spec_init_global_default_timeout, [{ok, hurra}, []]),
    timer:sleep(1000),
    ok = genie_server:call(_PidHurra, started_p),
    
    ?line Pid5 = 
	erlang:spawn_link(?MODULE, spec_init_not_proc_lib, [[]]),
    receive 
	{'EXIT', Pid5, process_was_not_started_by_proc_lib} ->
 	    ok
    after 5000 ->
	    test_server:fail(genie_server_did_not_die)
    end,
    process_flag(trap_exit, OldFlag),
    ok.

%%--------------------------------------------------------------
spec_init_local_registered_parent(doc) ->
    ["Test that terminate is run when the parent is a locally registered "
     "process OTP-4820"];
spec_init_local_registered_parent(suite) -> [];
spec_init_local_registered_parent(Config) when is_list(Config) ->

    register(foobar, self()),
    process_flag(trap_exit, true),
    
    ?line {ok, Pid} = start_link(spec_init_local, [{ok, my_server}, []]),
    
    ?line ok = genie_server:cast(my_server, {self(),stop}),
    ?line receive
	      {Pid, stopped} ->
		  ok
	  after 1000 ->
		  test_server:fail(stop)
	  end,
    unregister(foobar),
    ok.
%%--------------------------------------------------------------
spec_init_global_registered_parent(doc) ->
    ["Test that terminate is run when the parent is a global registered "
     "process OTP-4820"];
spec_init_global_registered_parent(suite) -> [];
spec_init_global_registered_parent(Config) when is_list(Config) ->

    global:register_name(foobar, self()),
    process_flag(trap_exit, true),
    
    ?line {ok, Pid} = start_link(spec_init_global, [{ok, my_server}, []]),
    
    ?line ok = genie_server:call(Pid, started_p),
    ?line ok = genie_server:cast(Pid, {self(),stop}),  

    ?line receive
	      {Pid, stopped} ->
		  ok
	  after 1000 ->
		  test_server:fail(stop)
	  end,
    global:unregister_name(foobar),
    ok.
%%--------------------------------------------------------------
otp_5854(suite) ->
    [];
otp_5854(doc) ->
    ["Test check for registered name in enter_loop/3,4,5"];
otp_5854(Config) when is_list(Config) ->
    OldFlag = process_flag(trap_exit, true),

    ?line dummy_via:reset(),

    %% Make sure genie_server:enter_loop does not accept {local,Name}
    %% when it's another process than the calling one which is
    %% registered under that name
    register(armitage, self()),
    ?line {ok, Pid1} =
	start_link(spec_init_local, [{not_ok, armitage}, []]),
    receive
	{'EXIT', Pid1, process_not_registered} ->
	    ok
    after 1000 ->
	    ?line test_server:fail(genie_server_started)
    end,
    unregister(armitage),

    %% Make sure genie_server:enter_loop does not accept {global,Name}
    %% when it's another process than the calling one which is
    %% registered under that name
    global:register_name(armitage, self()),
    ?line {ok, Pid2} =
	start_link(spec_init_global, [{not_ok, armitage}, []]),
    receive
	{'EXIT', Pid2, process_not_registered_globally} ->
	    ok
    after 1000 ->
	    ?line test_server:fail(genie_server_started)
    end,
    global:unregister_name(armitage),

    %% (same for {via, Mod, Name})
    dummy_via:register_name(armitage, self()),
    ?line {ok, Pid3} =
	start_link(spec_init_via, [{not_ok, armitage}, []]),
    receive
	{'EXIT', Pid3, {process_not_registered_via, dummy_via}} ->
	    ok
    after 1000 ->
	    ?line test_server:fail(genie_server_started)
    end,
    dummy_via:unregister_name(armitage),

    process_flag(trap_exit, OldFlag),
    ok.

%% If initialization fails (with ignore or {stop,Reason}),
%% make sure that the process is not registered when genie_server:start()
%% returns.

otp_7669(Config) when is_list(Config) ->
    ?line ?t:do_times(100, fun do_otp_7669_local_ignore/0),
    ?line ?t:do_times(100, fun do_otp_7669_global_ignore/0),
    ?line ?t:do_times(10, fun do_otp_7669_stop/0),
    ok.    

do_otp_7669_local_ignore() ->
    %% The name should never be registered after the return
    %% from genie_server:start/3.
    ?line ignore = genie_server:start({local,?MODULE}, ?MODULE, ignore, []),
    ?line undefined = whereis(?MODULE),
    ?line ignore = genie_server:start({local,?MODULE}, ?MODULE, ignore, []),
    ?line undefined = whereis(?MODULE),
    ?line ignore = genie_server:start_link({local,?MODULE}, ?MODULE, ignore, []),
    ?line undefined = whereis(?MODULE).

do_otp_7669_global_ignore() ->
    ?line ignore = genie_server:start({global,?MODULE}, ?MODULE, ignore, []),
    ?line undefined = global:whereis_name(?MODULE),
    ?line ignore = genie_server:start_link({global,?MODULE}, ?MODULE, ignore, []),
    ?line undefined = global:whereis_name(?MODULE).

do_otp_7669_stop() ->
    %% The name should never be registered after the return
    %% from genie_server:start/3.
    ?line {error,stopped} = genie_server:start({local,?MODULE},
					     ?MODULE, stop, []),
    ?line undefined = whereis(?MODULE),

    ?line {error,stopped} = genie_server:start({global,?MODULE},
					     ?MODULE, stop, []),
    ?line undefined = global:whereis_name(?MODULE).

%% Verify that sys:get_status correctly calls our format_status/2 fun
%%
call_format_status(suite) ->
    [];
call_format_status(doc) ->
    ["Test that sys:get_status/1,2 calls format_status/2"];
call_format_status(Config) when is_list(Config) ->
    ?line {ok, Pid} = genie_server:start_link({local, call_format_status},
					    ?MODULE, [], []),
    ?line Status1 = sys:get_status(call_format_status),
    ?line {status, Pid, _Mod, [_PDict, running, _Parent, _, Data1]} = Status1,
    ?line [format_status_called | _] = lists:reverse(Data1),
    ?line Status2 = sys:get_status(call_format_status, 5000),
    ?line {status, Pid, _Mod, [_PDict, running, _Parent, _, Data2]} = Status2,
    ?line [format_status_called | _] = lists:reverse(Data2),

    %% check that format_status can handle a name being a pid (atom is
    %% already checked by the previous test)
    ?line {ok, Pid3} = genie_server:start_link(genie_server_SUITE, [], []),
    ?line Status3 = sys:get_status(Pid3),
    ?line {status, Pid3, _Mod, [_PDict3, running, _Parent, _, Data3]} = Status3,
    ?line [format_status_called | _] = lists:reverse(Data3),

    %% check that format_status can handle a name being a term other than a
    %% pid or atom
    GlobalName1 = {global, "CallFormatStatus"},
    ?line {ok, Pid4} = genie_server:start_link(GlobalName1,
					     genie_server_SUITE, [], []),
    ?line Status4 = sys:get_status(Pid4),
    ?line {status, Pid4, _Mod, [_PDict4, running, _Parent, _, Data4]} = Status4,
    ?line [format_status_called | _] = lists:reverse(Data4),
    GlobalName2 = {global, {name, "term"}},
    ?line {ok, Pid5} = genie_server:start_link(GlobalName2,
					     genie_server_SUITE, [], []),
    ?line Status5 = sys:get_status(GlobalName2),
    ?line {status, Pid5, _Mod, [_PDict5, running, _Parent, _, Data5]} = Status5,
    ?line [format_status_called | _] = lists:reverse(Data5),
    ok.

%% Verify that error termination correctly calls our format_status/2 fun
%%
error_format_status(suite) ->
    [];
error_format_status(doc) ->
    ["Test that an error termination calls format_status/2"];
error_format_status(Config) when is_list(Config) ->
    ?line error_logger_forwarder:register(),
    OldFl = process_flag(trap_exit, true),
    State = "called format_status",
    ?line {ok, Pid} = genie_server:start_link(?MODULE, {state, State}, []),
    ?line {'EXIT',{crashed,_}} = (catch genie_server:call(Pid, crash)),
    receive
	{'EXIT', Pid, crashed} ->
	    ok
    end,
    receive
	{error,_GroupLeader,{Pid,
			     "** Generic server"++_,
			     [Pid,crash,State,crashed]}} ->
	    ok;
	Other ->
	    ?line io:format("Unexpected: ~p", [Other]),
	    ?line ?t:fail()
    end,
    ?t:messages_get(),
    process_flag(trap_exit, OldFl),
    ok.

%% Verify that sys:get_state correctly returns genie_server state
%%
get_state(suite) ->
    [];
get_state(doc) ->
    ["Test that sys:get_state/1,2 return the genie_server state"];
get_state(Config) when is_list(Config) ->
    State = self(),
    {ok, _Pid} = genie_server:start_link({local, get_state},
                                             ?MODULE, {state,State}, []),
    State = sys:get_state(get_state),
    State = sys:get_state(get_state, 5000),
    {ok, Pid} = genie_server:start_link(?MODULE, {state,State}, []),
    State = sys:get_state(Pid),
    State = sys:get_state(Pid, 5000),
    ok.

%% Verify that sys:replace_state correctly replaces genie_server state
%%
replace_state(suite) ->
    [];
replace_state(doc) ->
    ["Test that sys:replace_state/1,2 replace the genie_server state"];
replace_state(Config) when is_list(Config) ->
    State = self(),
    {ok, _Pid} = genie_server:start_link({local, replace_state},
                                             ?MODULE, {state,State}, []),
    State = sys:get_state(replace_state),
    NState1 = "replaced",
    Replace1 = fun(_) -> NState1 end,
    NState1 = sys:replace_state(replace_state, Replace1),
    NState1 = sys:get_state(replace_state),
    {ok, Pid} = genie_server:start_link(?MODULE, {state,NState1}, []),
    NState1 = sys:get_state(Pid),
    Suffix = " again",
    NState2 = NState1 ++ Suffix,
    Replace2 = fun(S) -> S ++ Suffix end,
    NState2 = sys:replace_state(Pid, Replace2, 5000),
    NState2 = sys:get_state(Pid, 5000),
    %% verify no change in state if replace function crashes
    Replace3 = fun(_) -> throw(fail) end,
    NState2 = sys:replace_state(Pid, Replace3),
    NState2 = sys:get_state(Pid, 5000),
    ok.

%% Test that the time for a huge message queue is not
%% significantly slower than with an empty message queue.
call_with_huge_message_queue(Config) when is_list(Config) ->
    case test_server:is_native(gen) of
	true ->
	    {skip,
	     "gen is native - huge message queue optimization "
	     "is not implemented"};
	false ->
	    do_call_with_huge_message_queue()
		end.

do_call_with_huge_message_queue() ->
    ?line Pid = spawn_link(fun echo_loop/0),

    ?line {Time,ok} = tc(fun() -> calls(10000, Pid) end),

    ?line [self() ! {msg,N} || N <- lists:seq(1, 500000)],
    erlang:garbage_collect(),
    ?line {NewTime,ok} = tc(fun() -> calls(10000, Pid) end),
    io:format("Time for empty message queue: ~p", [Time]),
    io:format("Time for huge message queue: ~p", [NewTime]),

    IsCover = test_server:is_cover(),
    case (NewTime+1) / (Time+1) of
	Q when Q < 10; IsCover ->
	    ok;
	Q ->
	    io:format("Q = ~p", [Q]),
	    ?line ?t:fail()
    end,
    ok.

%% Same as previous test but for call_list/2,3.
call_list_with_huge_message_queue(Config) when is_list(Config) ->
    ?line Pid = spawn_link(fun echo_loop/0),

    ?line {Time,ok} = tc(fun() -> call_lists(10000, Pid) end),

    ?line [self() ! {msg,N} || N <- lists:seq(1, 500000)],
    erlang:garbage_collect(),
    ?line {NewTime,ok} = tc(fun() -> call_lists(10000, Pid) end),
    io:format("Time for empty message queue: ~p", [Time]),
    io:format("Time for huge message queue: ~p", [NewTime]),

    IsCover = test_server:is_cover(),
    case (NewTime+1) / (Time+1) of
	Q when Q < 10; IsCover ->
	    ok;
	Q ->
	    io:format("Q = ~p", [Q]),
	    ?line ?t:fail()
    end,
    ok.

calls(0, _) -> ok;
calls(N, Pid) ->
    {ultimate_answer,42} = call(Pid, {ultimate_answer,42}),
    calls(N-1, Pid).

call(Pid, Msg) ->
    genie_server:call(Pid, Msg, infinity).

call_lists(0, _) -> ok;
call_lists(N, Pid) ->
    {[{Pid, {ultimate_answer,42}}], []} = call_list([Pid],
						    {ultimate_answer,42}),
    call_lists(N-1, Pid).

call_list(Pids, Msg) ->
    genie_server:call_list(Pids, Msg, infinity).

tc(Fun) ->
    timer:tc(erlang, apply, [Fun,[]]).

echo_loop() ->
    receive
	{'$gen_call',{Pid,Ref},Msg} ->
	    Pid ! {Ref,Msg},
	    echo_loop()
    end.

%% async tests

async_start(_) ->
    OldFl = process_flag(trap_exit, true),

    %% anonymous
    ?line {ok, Pid0} = genie_server:start(genie_server_SUITE, [],
					  [{async, infinity}]),
    ?line ok = genie_server:call(Pid0, started_p),
    ?line ok = genie_server:call(Pid0, stop),
    ?line busy_wait_for_process(Pid0,600),
    ?line {'EXIT', {noproc,_}} = (catch genie_server:call(Pid0, started_p, 1)),

    %% anonymous with timeout
    ?line {ok, Pid00} = genie_server:start(genie_server_SUITE, [],
					 [{timeout,1000}, {async, infinity}]),
    ?line ok = genie_server:call(Pid00, started_p),
    ?line ok = genie_server:call(Pid00, stop),
    ?line {ok, Pid01} = genie_server:start(genie_server_SUITE, sleep,
					      [{timeout,0}, {async, infinity}]),
    ?line ok = genie_server:call(Pid01, started_p),
    ?line ok = genie_server:call(Pid01, stop),

    %% anonymous with ignore
    ?line {ok, Pid02} = genie_server:start_link(genie_server_SUITE, ignore,
					   [{async, infinity}]),
    ?line receive
	      {'EXIT', Pid02, normal} ->
		  ok
	  after 5000 ->
		    test_server:fail(not_stopped)
	  end,

    %% anonymous with stop
    ?line {ok, Pid03} = genie_server:start(genie_server_SUITE, stop,
					   [{async, infinity}]),
    ?line ok = busy_wait_for_process(Pid03, 600),

    %% anonymous with timer
    ?line {ok, Pid04} = genie_server:start(genie_server_SUITE, [],
					  [{async, 1000}]),
    ?line ok = genie_server:call(Pid04, started_p),
    ?line ok = genie_server:call(Pid04, stop),

    %% anonymous with info
    ?line {ok, Pid05} = genie_server:start(genie_server_SUITE, extra,
					  [{async, infinity}]),
    ?line ok = genie_server:call(Pid05, started_p),
    ?line ok = genie_server:call(Pid05, stop),

    %% anonymous linked
    ?line {ok, Pid1} =
	genie_server:start_link(genie_server_SUITE, [], [{async, infinity}]),
    ?line ok = genie_server:call(Pid1, started_p),
    ?line ok = genie_server:call(Pid1, stop),
    ?line receive
	      {'EXIT', Pid1, stopped} ->
		  ok
	  after 5000 ->
		  test_server:fail(not_stopped)
	  end,

    %% local register
    ?line {ok, Pid2} =
	genie_server:start({local, my_test_name},
			 genie_server_SUITE, [], [{async, infinity}]),
    ?line ok = genie_server:call(my_test_name, started_p),
    ?line {error, {already_started, Pid2}} =
	genie_server:start({local, my_test_name},
			 genie_server_SUITE, [], [{async, infinity}]),
    ?line ok = genie_server:call(my_test_name, stop),

    ?line busy_wait_for_process(Pid2,600),

    ?line {'EXIT', {noproc,_}} = (catch genie_server:call(Pid2, started_p, 10)),

    %% local register linked
    ?line {ok, Pid3} =
	genie_server:start_link({local, my_test_name},
			      genie_server_SUITE, [], [{async, infinity}]), 
    ?line ok = genie_server:call(my_test_name, started_p),
    ?line {error, {already_started, Pid3}} =
	genie_server:start({local, my_test_name},
			 genie_server_SUITE, [], [{async, infinity}]),
    ?line ok = genie_server:call(my_test_name, stop),
    ?line receive
	      {'EXIT', Pid3, stopped} ->
		  ok
	  after 5000 ->
		  test_server:fail(not_stopped)
	  end,

    %% global register
    ?line {ok, Pid4} =
	genie_server:start({global, my_test_name},
			 genie_server_SUITE, [], [{async, infinity}]),
    ?line ok = genie_server:call({global, my_test_name}, started_p),
    ?line {error, {already_started, Pid4}} =
	genie_server:start({global, my_test_name},
			 genie_server_SUITE, [], [{async, infinity}]),
    ?line ok = genie_server:call({global, my_test_name}, stop),
    test_server:sleep(1),
    ?line {'EXIT', {noproc,_}} = (catch genie_server:call(Pid4, started_p, 10)),

    %% global register linked
    ?line {ok, Pid5} =
	genie_server:start_link({global, my_test_name},
			      genie_server_SUITE, [], [{async, infinity}]), 
    ?line ok = genie_server:call({global, my_test_name}, started_p),
    ?line {error, {already_started, Pid5}} =
	genie_server:start({global, my_test_name},
			 genie_server_SUITE, [], [{async, infinity}]),
    ?line ok = genie_server:call({global, my_test_name}, stop),
    ?line receive
	      {'EXIT', Pid5, stopped} ->
		  ok
	  after 5000 ->
		  test_server:fail(not_stopped)
	  end,

    %% via register
    ?line dummy_via:reset(),
    ?line {ok, Pid6} =
	genie_server:start({via, dummy_via, my_test_name},
			 genie_server_SUITE, [], [{async, infinity}]),
    ?line ok = genie_server:call({via, dummy_via, my_test_name}, started_p),
    ?line {error, {already_started, Pid6}} =
	genie_server:start({via, dummy_via, my_test_name},
			 genie_server_SUITE, [], [{async, infinity}]),
    ?line ok = genie_server:call({via, dummy_via, my_test_name}, stop),
    test_server:sleep(1),
    ?line {'EXIT', {noproc,_}} = (catch genie_server:call(Pid6, started_p, 10)),

    %% via register linked
    ?line dummy_via:reset(),
    ?line {ok, Pid7} =
	genie_server:start_link({via, dummy_via, my_test_name},
			      genie_server_SUITE, [], [{async, infinity}]),
    ?line ok = genie_server:call({via, dummy_via, my_test_name}, started_p),
    ?line {error, {already_started, Pid7}} =
	genie_server:start({via, dummy_via, my_test_name},
			 genie_server_SUITE, [], [{async, infinity}]),
    ?line ok = genie_server:call({via, dummy_via, my_test_name}, stop),
    ?line receive
	      {'EXIT', Pid7, stopped} ->
		  ok
	  after 5000 ->
		  test_server:fail(not_stopped)
	  end,
    test_server:messages_get(),

    process_flag(trap_exit, OldFl),
    ok.

async_stop(_) ->
    OldFl = process_flag(trap_exit, true),

    ?line error_logger_forwarder:register(),

    ?line {ok, Pid1} =
	genie_server:start_link(genie_server_SUITE, {stop, normal},
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
	genie_server:start_link(genie_server_SUITE, {stop, shutdown},
				[{async, infinity}]),
    ?line receive
	{'EXIT', Pid2, shutdown} ->
	    ok
    after 5000 ->
	      test_server:fail(not_stopped)
    end,
    ?line {ok, Pid3} =
	genie_server:start_link(genie_server_SUITE, {stop, {shutdown, stopped}},
				[{async, infinity}]),
    ?line receive
	{'EXIT', Pid3, {shutdown, stopped}} ->
	    ok
    after 5000 ->
	      test_server:fail(not_stopped)
    end,
    ?line {ok, Pid4} =
	genie_server:start_link(genie_server_SUITE, stop, [{async, infinity}]),
    ?line receive
	{'EXIT', Pid4, stopped} ->
	    ok
    after 5000 ->
	      test_server:fail(not_stopped)
    end,
    ?line receive
	{error,_GroupLeader4,{Pid4,
			      "** Generic server"++_,
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

async_exit(_) ->
    OldFl = process_flag(trap_exit, true),

    ?line error_logger_forwarder:register(),

    ?line {ok, Pid1} =
	genie_server:start_link(genie_server_SUITE, {exit, normal},
				[{async, infinity}]),
    ?line receive
	{'EXIT', Pid1, normal} ->
	    ok
    after 5000 ->
	      test_server:fail(not_stopped)
    end,
     ?line {ok, Pid2} =
	genie_server:start_link(genie_server_SUITE, {exit, shutdown},
				[{async, infinity}]),
    ?line receive
	{'EXIT', Pid2, shutdown} ->
	    ok
    after 5000 ->
	      test_server:fail(not_stopped)
    end,
    ?line {ok, Pid3} =
	genie_server:start_link(genie_server_SUITE, {exit, {shutdown, stopped}},
				[{async, infinity}]),
    ?line receive
	{'EXIT', Pid3, {shutdown, stopped}} ->
	    ok
    after 5000 ->
	      test_server:fail(not_stopped)
    end,
    ?line {ok, Pid4} =
	genie_server:start_link(genie_server_SUITE, {exit, stopped},
				[{async, infinity}]),
    ?line receive
	{'EXIT', Pid4, stopped} ->
	    ok
    after 5000 ->
	      test_server:fail(not_stopped)
    end,
    ?line receive
	{error,_GroupLeader4,{Pid4,
			      "** Generic server"++_,
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

    ?line {ok, Pid} = genie_server:start_link(genie_server_SUITE, sleep,
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
			      "** Generic server"++_,
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

%%--------------------------------------------------------------
%% Help functions to spec_init_*
start_link(Init, Options) ->
    proc_lib:start_link(?MODULE, Init, Options).

spec_init_local({ok, Name}, Options) ->
    process_flag(trap_exit, true),
    register(Name, self()),
    proc_lib:init_ack({ok, self()}),
    %% Supervised init can occur here  ...
    genie_server:enter_loop(?MODULE, Options, {}, {local, Name}, infinity);

spec_init_local({not_ok, Name}, Options) ->
    process_flag(trap_exit, true),
    proc_lib:init_ack({ok, self()}),
    %% Supervised init can occur here  ...
    genie_server:enter_loop(?MODULE, Options, {}, {local, Name}, infinity).

spec_init_global({ok, Name}, Options) ->
    process_flag(trap_exit, true),
    global:register_name(Name, self()),
    proc_lib:init_ack({ok, self()}),
    %% Supervised init can occur here  ...
    genie_server:enter_loop(?MODULE, Options, {}, {global, Name}, infinity);

spec_init_global({not_ok, Name}, Options) ->
    process_flag(trap_exit, true),
    proc_lib:init_ack({ok, self()}),
    %% Supervised init can occur here  ...
    genie_server:enter_loop(?MODULE, Options, {}, {global, Name}, infinity).

spec_init_via({ok, Name}, Options) ->
    process_flag(trap_exit, true),
    dummy_via:register_name(Name, self()),
    proc_lib:init_ack({ok, self()}),
    %% Supervised init can occur here  ...
    genie_server:enter_loop(?MODULE, Options, {},
			  {via, dummy_via, Name}, infinity);

spec_init_via({not_ok, Name}, Options) ->
    process_flag(trap_exit, true),
    proc_lib:init_ack({ok, self()}),
    %% Supervised init can occur here  ...
    genie_server:enter_loop(?MODULE, Options, {},
			  {via, dummy_via, Name}, infinity).

spec_init_default_timeout({ok, Name}, Options) ->
    process_flag(trap_exit, true),
    register(Name, self()),
    proc_lib:init_ack({ok, self()}),
    %% Supervised init can occur here  ...
    genie_server:enter_loop(?MODULE, Options, {}, {local, Name}).

%% OTP-10130, A bug was introduced where global scope was not matched when
%% enter_loop/4 was called (no timeout).
spec_init_global_default_timeout({ok, Name}, Options) ->
    process_flag(trap_exit, true),
    global:register_name(Name, self()),
    proc_lib:init_ack({ok, self()}),
    %% Supervised init can occur here  ...
    genie_server:enter_loop(?MODULE, Options, {}, {global, Name}).

spec_init_anonymous(Options) ->
    process_flag(trap_exit, true),
    proc_lib:init_ack({ok, self()}),
    %% Supervised init can occur here  ...
    genie_server:enter_loop(?MODULE, Options, {}, infinity).

spec_init_anonymous_default_timeout(Options) ->
    process_flag(trap_exit, true),
    proc_lib:init_ack({ok, self()}),
    %% Supervised init can occur here  ...
    genie_server:enter_loop(?MODULE, Options, {}).

spec_init_not_proc_lib(Options) ->
    genie_server:enter_loop(?MODULE, Options, {}, infinity).

%%% --------------------------------------------------------
%%% Here is the tested genie_server behaviour.
%%% --------------------------------------------------------

init([]) ->
    {ok, []};
init(ignore) ->
    ignore;
init(stop) ->
    {stop, stopped};
init({stop, _Reason} = Result) ->
    Result;
init({exit, Reason}) ->
    exit(Reason);
init(extra) ->
    {info,[],extra};
init(hibernate) ->
    {ok,[],hibernate};
init(sleep) ->
    test_server:sleep(1000),
    {ok, []};
init({state,State}) ->
    {ok, State}.

handle_call(started_p, _From, State) ->
    io:format("FROZ"),
    {reply,ok,State};
handle_call({delayed_answer, T}, From, _State) ->
    {noreply,{reply_to,From},T};
handle_call({call_within, T}, _From, _) ->
    {reply,ok,call_within,T};
handle_call(next_call, _From, call_within) ->
    {reply,ok,[]};
handle_call(next_call, _From, State) ->
    {reply,false,State};
handle_call(badreturn, _From, _State) ->
    badreturn;
handle_call(hibernate, _From, _State) ->
    {reply,true,[],hibernate};
handle_call({hibernate_noreply,Pid}, From, _State) ->
    Pid ! go,
    {noreply,From,hibernate};
handle_call(stop, _From, State) ->
    {stop,stopped,ok,State};
handle_call(crash, _From, _State) ->
    exit(crashed);
handle_call(exit_shutdown, _From, _State) ->
    exit(shutdown);
handle_call(stop_shutdown, _From, State) ->
    {stop,shutdown,State};
handle_call(shutdown_reason, _From, _State) ->
    exit({shutdown,reason});
handle_call(stop_shutdown_reason, _From, State) ->
    {stop,{shutdown,stop_reason},State}.

handle_cast({From,handle_cast}, State) ->
    From ! {self(), handled_cast},
    {noreply, State};
handle_cast({From,delayed_cast,T}, _State) ->
    {noreply, {delayed_cast,From}, T};
handle_cast(hibernate_now, _State) ->
    {noreply, [], hibernate};
handle_cast(hibernate_later, _State) ->
    timer:send_after(1000,self(),hibernate_now),
    {noreply, []};
handle_cast({From, stop}, State) ->
    io:format("BAZ"),
    {stop, {From,stopped}, State}.

handle_info(timeout, {reply_to, From}) ->
    genie_server:reply(From, delayed),
    {noreply, []};
handle_info(timeout, hibernate_me) -> % Arrive here from 
				      % handle_info(hibernate_later,...)
    {noreply, [], hibernate};
handle_info(hibernate_now, _State) ->  % Arrive here from 
				       % handle_cast({_,hibernate_later},...)
				       % and by direct ! from testcase
    {noreply, [], hibernate};
handle_info(hibernate_later, _State) ->
    {noreply, hibernate_me, 1000};
handle_info(timeout, call_within) ->
    {noreply, []};
handle_info(timeout, {delayed_cast, From}) ->
    From ! {self(), delayed},
    {noreply, []};
handle_info(timeout, {delayed_info, From}) ->
    From ! {self(), delayed_info},
    {noreply, []};
handle_info({From, handle_info}, _State) ->
    From ! {self(), handled_info},
    {noreply, []};
handle_info({From, delayed_info, T}, _State) ->
    {noreply, {delayed_info, From}, T};
handle_info(continue, From) ->
    genie_server:reply(From,true),
    {noreply, []};
handle_info({From, stop}, State) ->
    {stop, {From,stopped_info}, State};
handle_info(_Info, State) ->
    {noreply, State}.

terminate({From, stopped}, _State) ->
    io:format("FOOBAR"),
    From ! {self(), stopped},
    ok;
terminate({From, stopped_info}, _State) ->
    From ! {self(), stopped_info},
    ok;
terminate(_Reason, _State) ->
    ok.

format_status(terminate, [_PDict, State]) ->
    State;
format_status(normal, [_PDict, _State]) ->
    format_status_called.
