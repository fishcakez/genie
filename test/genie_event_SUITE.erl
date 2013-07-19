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
-module(genie_event_SUITE).

-include_lib("test_server/include/test_server.hrl").

-export([all/0, suite/0,groups/0,init_per_suite/1, end_per_suite/1, 
	 init_per_group/2,end_per_group/2]).
-export([start/1, add_handler/1, add_sup_handler/1,
	 delete_handler/1, swap_handler/1, swap_sup_handler/1,
	 notify/1, sync_notify/1, call/1, info/1, hibernate/1,
	 call_format_status/1, call_format_status_anon/1,
         error_format_status/1, get_state/1, replace_state/1]).

suite() -> [{ct_hooks,[ts_install_cth]}].

all() -> 
    [start, {group, test_all}, hibernate,
     call_format_status, call_format_status_anon, error_format_status,
     get_state, replace_state].

groups() -> 
    [{test_all, [],
      [add_handler, add_sup_handler, delete_handler,
       swap_handler, swap_sup_handler, notify, sync_notify,
       call, info]}].

init_per_suite(Config) ->
    Config.

end_per_suite(_Config) ->
    ok.

init_per_group(_GroupName, Config) ->
    Config.

end_per_group(_GroupName, Config) ->
    Config.


%% --------------------------------------
%% Start an event manager.
%% --------------------------------------

start(doc) -> [];
start(suite) -> [];
start(Config) when is_list(Config) ->
    OldFl = process_flag(trap_exit, true),

    ?line dummy_via:reset(),

    ?line {ok, Pid0} = genie_event:start(), %anonymous
    ?line [] = genie_event:which_handlers(Pid0),
    ?line ok = genie_event:stop(Pid0),

    ?line {ok, Pid1} = genie_event:start_link(), %anonymous
    ?line [] = genie_event:which_handlers(Pid1),
    ?line ok = genie_event:stop(Pid1),

    ?line {ok, Pid2} = genie_event:start({local, my_dummy_name}),
    ?line [] = genie_event:which_handlers(my_dummy_name),
    ?line [] = genie_event:which_handlers(Pid2),
    ?line ok = genie_event:stop(my_dummy_name),

    ?line {ok, Pid3} = genie_event:start_link({local, my_dummy_name}),
    ?line [] = genie_event:which_handlers(my_dummy_name),
    ?line [] = genie_event:which_handlers(Pid3),
    ?line ok = genie_event:stop(my_dummy_name),

    ?line {ok, Pid4} = genie_event:start_link({global, my_dummy_name}),
    ?line [] = genie_event:which_handlers({global, my_dummy_name}),
    ?line [] = genie_event:which_handlers(Pid4),
    ?line ok = genie_event:stop({global, my_dummy_name}),

    ?line {ok, Pid5} = genie_event:start_link({via, dummy_via, my_dummy_name}),
    ?line [] = genie_event:which_handlers({via, dummy_via, my_dummy_name}),
    ?line [] = genie_event:which_handlers(Pid5),
    ?line ok = genie_event:stop({via, dummy_via, my_dummy_name}),

    ?line {ok, _} = genie_event:start_link({local, my_dummy_name}),
    ?line {error, {already_started, _}} =
	genie_event:start_link({local, my_dummy_name}),
    ?line {error, {already_started, _}} =
	genie_event:start({local, my_dummy_name}),
    ?line ok = genie_event:stop(my_dummy_name),

    ?line {ok, Pid6} = genie_event:start_link({global, my_dummy_name}),
    ?line {error, {already_started, _}} =
	genie_event:start_link({global, my_dummy_name}),
    ?line {error, {already_started, _}} =
	genie_event:start({global, my_dummy_name}),

    exit(Pid6, shutdown),
    receive
	{'EXIT', Pid6, shutdown} -> ok
    after 10000 ->
	    ?t:fail(exit_genie_event)
    end,

    ?line {ok, Pid7} = genie_event:start_link({via, dummy_via, my_dummy_name}),
    ?line {error, {already_started, _}} =
	genie_event:start_link({via, dummy_via, my_dummy_name}),
    ?line {error, {already_started, _}} =
	genie_event:start({via, dummy_via, my_dummy_name}),

    exit(Pid7, shutdown),
    receive
	{'EXIT', Pid7, shutdown} -> ok
    after 10000 ->
	    ?t:fail(exit_genie_event)
    end,

    ?t:messages_get(),
    process_flag(trap_exit, OldFl),
    ok.


hibernate(suite) -> [];
hibernate(Config) when is_list(Config) ->
    ?line {ok,Pid} = genie_event:start({local, my_dummy_handler}),
    ?line ok = genie_event:add_handler(my_dummy_handler, dummy_h, [self()]),
    ?line [dummy_h] = genie_event:which_handlers(my_dummy_handler),
    ?line true = genie_event:call(my_dummy_handler, dummy_h, hibernate),
    ?line receive after 1000 -> ok end,
    ?line {current_function,{erlang,hibernate,3}} = erlang:process_info(Pid,current_function),
    ?line Pid ! wake,
    ?line receive after 1000 -> ok end,
    ?line true = ({current_function,{erlang,hibernate,3}} =/= 
		  erlang:process_info(Pid,current_function)),    
    ?line later = genie_event:call(my_dummy_handler, dummy_h, hibernate_later),
    ?line true = ({current_function,{erlang,hibernate,3}} =/= 
		  erlang:process_info(Pid,current_function)),    
    ?line receive after 2000 -> ok end,
    ?line {current_function,{erlang,hibernate,3}} = erlang:process_info(Pid,current_function),
    ?line Pid ! wake,
    ?line receive after 1000 -> ok end,
    ?line true = ({current_function,{erlang,hibernate,3}} =/= 
		  erlang:process_info(Pid,current_function)),    
    ?line genie_event:notify(my_dummy_handler,hibernate),
    ?line receive after 1000 -> ok end,
    ?line {current_function,{erlang,hibernate,3}} = erlang:process_info(Pid,current_function),
    ?line genie_event:notify(my_dummy_handler,wakeup),
    ?line receive after 1000 -> ok end,
    ?line true = ({current_function,{erlang,hibernate,3}} =/= 
		  erlang:process_info(Pid,current_function)),    
    ?line genie_event:notify(my_dummy_handler,hibernate),
    ?line receive after 1000 -> ok end,
    ?line {current_function,{erlang,hibernate,3}} = erlang:process_info(Pid,current_function),
    ?line genie_event:sync_notify(my_dummy_handler,wakeup),
    ?line true = ({current_function,{erlang,hibernate,3}} =/= 
		  erlang:process_info(Pid,current_function)),    
    ?line ok = genie_event:sync_notify(my_dummy_handler,hibernate),
    ?line receive after 1000 -> ok end,
    ?line {current_function,{erlang,hibernate,3}} = erlang:process_info(Pid,current_function),
    ?line Pid ! wake,
    ?line receive after 1000 -> ok end,
    ?line true = ({current_function,{erlang,hibernate,3}} =/= 
		  erlang:process_info(Pid,current_function)),
    ?line ok = genie_event:add_handler(my_dummy_handler, dummy1_h, [self()]),
    ?line [_,_] = genie_event:which_handlers(my_dummy_handler),
    ?line genie_event:notify(my_dummy_handler,hibernate),
    ?line receive after 1000 -> ok end,
    ?line {current_function,{erlang,hibernate,3}} = erlang:process_info(Pid,current_function),
    ?line genie_event:notify(my_dummy_handler,wakeup),
    ?line receive after 1000 -> ok end,
    ?line {current_function,{erlang,hibernate,3}} = erlang:process_info(Pid,current_function),
    ?line Pid ! wake,
    ?line receive after 1000 -> ok end,
    ?line true = ({current_function,{erlang,hibernate,3}} =/= 
		  erlang:process_info(Pid,current_function)),
    ?line Pid ! gnurf,
    ?line receive after 1000 -> ok end,
    ?line {current_function,{erlang,hibernate,3}} = erlang:process_info(Pid,current_function),
    ?line Pid ! sleep,
    ?line receive after 1000 -> ok end,
    ?line {current_function,{erlang,hibernate,3}} = erlang:process_info(Pid,current_function),
    ?line Pid ! wake,
    ?line receive after 1000 -> ok end,
    ?line true = ({current_function,{erlang,hibernate,3}} =/= 
		  erlang:process_info(Pid,current_function)),
    ?line ok = genie_event:stop(my_dummy_handler),
    ?line {ok,Pid2} = genie_event:start({local, my_dummy_handler}),
    ?line ok = genie_event:add_handler(my_dummy_handler, dummy_h, [self(),hibernate]),
    ?line receive after 1000 -> ok end,
    ?line {current_function,{erlang,hibernate,3}} = erlang:process_info(Pid2,current_function),
    ?line sys:suspend(my_dummy_handler),
    ?line receive after 1000 -> ok end,
    ?line {current_function,{erlang,hibernate,3}} = erlang:process_info(Pid2,current_function),
    ?line sys:resume(my_dummy_handler),
    ?line receive after 1000 -> ok end,
    ?line {current_function,{erlang,hibernate,3}} = erlang:process_info(Pid2,current_function),
    ?line Pid2 ! wake,
    ?line receive after 1000 -> ok end,
    ?line true = ({current_function,{erlang,hibernate,3}} =/= 
		  erlang:process_info(Pid2,current_function)),
   

    ?line ok = genie_event:stop(my_dummy_handler),

    ok.



add_handler(doc) -> [];
add_handler(suite) -> [];
add_handler(Config) when is_list(Config) ->
    ?line {ok,_} = genie_event:start({local, my_dummy_handler}),
    ?line {error, my_error} =
	genie_event:add_handler(my_dummy_handler, dummy_h, make_error),
    ?line [] = genie_event:which_handlers(my_dummy_handler),
    ?line ok = genie_event:add_handler(my_dummy_handler, dummy_h, [self()]),
    ?line [dummy_h] = genie_event:which_handlers(my_dummy_handler),

    ?line {error, my_error} =
	genie_event:add_handler(my_dummy_handler, {dummy_h, self()}, make_error),
    ?line [dummy_h] = genie_event:which_handlers(my_dummy_handler),
    ?line ok = genie_event:add_handler(my_dummy_handler, {dummy_h,self()},
				     [self()]),
    Self = self(),
    ?line [{dummy_h, Self}, dummy_h] =
	genie_event:which_handlers(my_dummy_handler),
    ?line ok = genie_event:stop(my_dummy_handler),
    ok.

add_sup_handler(doc) -> [];
add_sup_handler(suite) -> [];
add_sup_handler(Config) when is_list(Config) ->
    ?line {ok,Pid} = genie_event:start({local, my_dummy_handler}),
    ?line {error, my_error} =
	genie_event:add_sup_handler(my_dummy_handler, dummy_h, make_error),
    ?line [] = genie_event:which_handlers(my_dummy_handler),
    ?line ok = genie_event:add_sup_handler(my_dummy_handler, dummy_h, [self()]),
    ?line [dummy_h] = genie_event:which_handlers(my_dummy_handler),
    ?line exit(Pid, sup_died),
    ?t:sleep(1000),
    ?line [] = genie_event:which_handlers(my_dummy_handler),

    ?line ok = genie_event:add_sup_handler(my_dummy_handler, dummy_h, [self()]),
    ?line [dummy_h] = genie_event:which_handlers(my_dummy_handler),

    ?line {error, my_error} =
	genie_event:add_handler(my_dummy_handler, {dummy_h, self()}, make_error),
    ?line [dummy_h] = genie_event:which_handlers(my_dummy_handler),
    ?line ok = genie_event:add_sup_handler(my_dummy_handler, {dummy_h,self()},
					 [self()]),
    Self = self(),
    ?line [{dummy_h, Self}, dummy_h] =
	genie_event:which_handlers(my_dummy_handler),
    ?line ok = genie_event:stop(my_dummy_handler),

    ?line receive
	      {genie_event_EXIT, dummy_h, shutdown} ->
		  ok
	  after 1000 ->
		  ?t:fail({no,{genie_event_EXIT, dummy_h, shutdown}})
	  end,

    ?line receive
	      {genie_event_EXIT, {dummy_h,Self}, shutdown} ->
		  ok
	  after 1000 ->
		  ?t:fail({no,{genie_event_EXIT, {dummy_h,Self},
					shutdown}})
	  end,
    ok.

delete_handler(doc) -> [];
delete_handler(suite) -> [];
delete_handler(Config) when is_list(Config) ->
    ?line {ok,_} = genie_event:start({local, my_dummy_handler}),
    ?line ok = genie_event:add_handler(my_dummy_handler, dummy_h, [self()]),
    ?line {error, module_not_found} =
	genie_event:delete_handler(my_dummy_handler, duuuuuuuuumy, []),
    ?line return_hej =
	genie_event:delete_handler(my_dummy_handler, dummy_h, return_hej),
    ?line [] = genie_event:which_handlers(my_dummy_handler),
    ?line ok = genie_event:add_handler(my_dummy_handler, dummy_h, [self()]),
    ?line ok =
	genie_event:delete_handler(my_dummy_handler, dummy_h, []),
    ?line [] = genie_event:which_handlers(my_dummy_handler),

    ?line ok = genie_event:add_handler(my_dummy_handler, {dummy_h,1}, [self()]),
    ?line ok = genie_event:add_handler(my_dummy_handler, {dummy_h,2}, [self()]),
    ?line {error, module_not_found} =
	genie_event:delete_handler(my_dummy_handler, {duuuuuuuuumy,1}, []),
    ?line return_hej =
	genie_event:delete_handler(my_dummy_handler, {dummy_h,1}, return_hej),
    ?line return_hej =
	genie_event:delete_handler(my_dummy_handler, {dummy_h,2}, return_hej),
    ?line [] = genie_event:which_handlers(my_dummy_handler),
    ?line ok = genie_event:add_handler(my_dummy_handler, {dummy_h,2}, [self()]),
    ?line ok =
	genie_event:delete_handler(my_dummy_handler, {dummy_h,2}, []),
    ?line [] = genie_event:which_handlers(my_dummy_handler),

    ?line ok = genie_event:stop(my_dummy_handler),
    ok.

swap_handler(doc) -> [];
swap_handler(suite) -> [];
swap_handler(Config) when is_list(Config) ->
    ?line {ok,_} = genie_event:start({local, my_dummy_handler}),
    ?line ok = genie_event:add_handler(my_dummy_handler, dummy_h, [self()]),
    ?line {error, non_existing} =
	genie_event:swap_handler(my_dummy_handler, {faulty_h, swap},
			       {dummy1_h, []}),
    ?line ok =
	genie_event:swap_handler(my_dummy_handler, {dummy_h, swap},
			       {dummy1_h, swap}),
    ?line [dummy1_h] = genie_event:which_handlers(my_dummy_handler),

    ?line ok = genie_event:delete_handler(my_dummy_handler, dummy1_h, []),

    ?line ok = genie_event:add_handler(my_dummy_handler, {dummy_h,3}, [self()]),
    ?line {error, non_existing} =
	genie_event:swap_handler(my_dummy_handler, {faulty_h, swap},
			       {dummy1_h, []}),
    ?line ok =
	genie_event:swap_handler(my_dummy_handler, {{dummy_h,3}, swap},
			       {{dummy1_h,4}, swap}),
    ?line [{dummy1_h,4}] = genie_event:which_handlers(my_dummy_handler),

    ?line ok = genie_event:delete_handler(my_dummy_handler, {dummy1_h,4}, []),

    ?line ok = genie_event:stop(my_dummy_handler),
    ok.
	
swap_sup_handler(doc) -> [];
swap_sup_handler(suite) -> [];
swap_sup_handler(Config) when is_list(Config) ->
    ?line {ok,_} = genie_event:start({local, my_dummy_handler}),
    ?line ok = genie_event:add_sup_handler(my_dummy_handler, dummy_h, [self()]),
    ?line {error, non_existing} =
	genie_event:swap_handler(my_dummy_handler, {faulty_h, swap},
			       {dummy1_h, []}),
    ?line ok =
	genie_event:swap_handler(my_dummy_handler, {dummy_h, swap},
			       {dummy1_h, swap}),
    ?line [dummy1_h] = genie_event:which_handlers(my_dummy_handler),

    ?line ok = genie_event:delete_handler(my_dummy_handler, dummy1_h, []),
    ?line receive
	      {genie_event_EXIT, dummy1_h, normal} ->
		  ok
	  after 1000 ->
		  ?t:fail({no,{genie_event_EXIT, dummy1_h, normal}})
	  end,

    ?line ok = genie_event:add_sup_handler(my_dummy_handler, {dummy_h,3},
					 [self()]),
    ?line {error, non_existing} =
	genie_event:swap_sup_handler(my_dummy_handler, {faulty_h, swap},
				   {dummy1_h, []}),
    ?line ok =
	genie_event:swap_sup_handler(my_dummy_handler, {{dummy_h,3}, swap},
				   {{dummy1_h,4}, swap}),
    ?line [{dummy1_h,4}] = genie_event:which_handlers(my_dummy_handler),

    ?line ok = genie_event:delete_handler(my_dummy_handler, {dummy1_h,4}, []),
    ?line receive
	      {genie_event_EXIT, {dummy1_h,4}, normal} ->
		  ok
	  after 1000 ->
		  ?t:fail({no,{genie_event_EXIT, {dummy1_h,4}, normal}})
	  end,

    ?line ok = genie_event:stop(my_dummy_handler),
    ok.
	
notify(doc) -> [];
notify(suite) -> [];
notify(Config) when is_list(Config) ->
    ?line {ok,_} = genie_event:start({local, my_dummy_handler}),
    ?line ok = genie_event:add_handler(my_dummy_handler, dummy_h, [self()]),
    Event = {event, self()},
    ?line [dummy_h] = genie_event:which_handlers(my_dummy_handler),
    ?line ok = genie_event:notify(my_dummy_handler, Event),
    ?line receive
	      {dummy_h, Event} ->
		  ok
	  end,
    ?line ok = genie_event:notify(my_dummy_handler, {swap_event,dummy1_h,swap}),
    ?t:sleep(1000),
    ?line [dummy1_h] = genie_event:which_handlers(my_dummy_handler),
    ?line ok = genie_event:notify(my_dummy_handler, Event),
    ?line receive
	      {dummy1_h, Event} ->
		  ok
	  end,
    ?line ok = genie_event:notify(my_dummy_handler, delete_event),
    ?line receive
	      {dummy1_h, removed} ->
		  ok
	  end,
    ?line [] = genie_event:which_handlers(my_dummy_handler),
    ?line ok = genie_event:add_handler(my_dummy_handler, dummy_h, [self()]),

    ?line ok = genie_event:notify(my_dummy_handler, error_event),
    ?line receive
	      {dummy_h, returned_error} ->
		  ok
	  end,
    ?line [] = genie_event:which_handlers(my_dummy_handler),

    %% Handler with id, {Mod,Id}

    ?line ok = genie_event:add_handler(my_dummy_handler, {dummy_h,5}, [self()]),
    ?line [{dummy_h,5}] = genie_event:which_handlers(my_dummy_handler),
    ?line ok = genie_event:notify(my_dummy_handler, Event),
    ?line receive
	      {dummy_h, Event} ->
		  ok
	  end,
    ?line ok = genie_event:notify(my_dummy_handler,
				{swap_event, {dummy1_h, 9}, swap}),
    ?t:sleep(1000),
    ?line [{dummy1_h,9}] = genie_event:which_handlers(my_dummy_handler),
    ?line ok = genie_event:notify(my_dummy_handler, Event),
    ?line receive
	      {dummy1_h, Event} ->
		  ok
	  end,
    ?line ok = genie_event:notify(my_dummy_handler, delete_event),
    ?line receive
	      {dummy1_h, removed} ->
		  ok
	  end,
    ?line [] = genie_event:which_handlers(my_dummy_handler),
    ?line ok = genie_event:add_handler(my_dummy_handler, {dummy_h,a}, [self()]),

    ?line ok = genie_event:notify(my_dummy_handler, error_event),
    ?line receive
	      {dummy_h, returned_error} ->
		  ok
	  end,
    ?line [] = genie_event:which_handlers(my_dummy_handler),

    %% Supervised handler.

    ?line ok = genie_event:add_sup_handler(my_dummy_handler, dummy_h, [self()]),
    ?line [dummy_h] = genie_event:which_handlers(my_dummy_handler),
    ?line ok = genie_event:notify(my_dummy_handler, Event),
    ?line receive
	      {dummy_h, Event} ->
		  ok
	  end,

    ?line ok = genie_event:notify(my_dummy_handler, do_crash),
    ?line receive
	      {genie_event_EXIT, dummy_h, {'EXIT',_}} ->
		  ok
	  end,

    ?line ok = genie_event:add_sup_handler(my_dummy_handler, dummy_h, [self()]),
    ?line ok = genie_event:notify(my_dummy_handler, {swap_event,dummy1_h,swap}),
    ?t:sleep(1000),
    ?line [dummy1_h] = genie_event:which_handlers(my_dummy_handler),

    ?line ok = genie_event:notify(my_dummy_handler, do_crash),
    ?line receive
	      {genie_event_EXIT, dummy1_h, {'EXIT',_}} ->
		  ok
	  end,

    ?line ok = genie_event:add_sup_handler(my_dummy_handler, dummy_h, [self()]),
    ?line ok = genie_event:notify(my_dummy_handler, {swap_event,dummy1_h,swap}),
    ?t:sleep(1000),
    ?line [dummy1_h] = genie_event:which_handlers(my_dummy_handler),

    ?line ok = genie_event:notify(my_dummy_handler, delete_event),
    ?line receive
	      {dummy1_h, removed} ->
		  ok
	  end,

    ?line receive
	      {genie_event_EXIT, dummy1_h, normal} ->
		  ok
	  end,

    ?line [] = genie_event:which_handlers(my_dummy_handler),

    ?line ok = genie_event:stop(my_dummy_handler),
    ok.

sync_notify(doc) -> [];
sync_notify(suite) -> [];
sync_notify(Config) when is_list(Config) ->
    ?line {ok,_} = genie_event:start({local, my_dummy_handler}),
    ?line ok = genie_event:add_handler(my_dummy_handler, dummy_h, [self()]),
    Event = {event, self()},
    ?line [dummy_h] = genie_event:which_handlers(my_dummy_handler),
    ?line ok = genie_event:sync_notify(my_dummy_handler, Event),
    ?line receive
	      {dummy_h, Event} ->
		  ok
	  end,
    ?line ok = genie_event:sync_notify(my_dummy_handler,
				     {swap_event, dummy1_h, swap}),
    ?t:sleep(1000),
    ?line [dummy1_h] = genie_event:which_handlers(my_dummy_handler),
    ?line ok = genie_event:sync_notify(my_dummy_handler, Event),
    ?line receive
	      {dummy1_h, Event} ->
		  ok
	  end,
    ?line ok = genie_event:sync_notify(my_dummy_handler, delete_event),
    ?line receive
	      {dummy1_h, removed} ->
		  ok
	  end,
    ?line [] = genie_event:which_handlers(my_dummy_handler),
    ?line ok = genie_event:add_handler(my_dummy_handler, dummy_h, [self()]),

    ?line ok = genie_event:sync_notify(my_dummy_handler, error_event),
    ?line receive
	      {dummy_h, returned_error} ->
		  ok
	  end,
    ?line [] = genie_event:which_handlers(my_dummy_handler),

    %% Handler with id, {Mod,Id}

    ?line ok = genie_event:add_handler(my_dummy_handler, {dummy_h,5}, [self()]),
    ?line [{dummy_h,5}] = genie_event:which_handlers(my_dummy_handler),
    ?line ok = genie_event:sync_notify(my_dummy_handler, Event),
    ?line receive
	      {dummy_h, Event} ->
		  ok
	  end,
    ?line ok = genie_event:sync_notify(my_dummy_handler,
				     {swap_event, {dummy1_h, 9}, swap}),
    ?t:sleep(1000),
    ?line [{dummy1_h,9}] = genie_event:which_handlers(my_dummy_handler),
    ?line ok = genie_event:sync_notify(my_dummy_handler, Event),
    ?line receive
	      {dummy1_h, Event} ->
		  ok
	  end,
    ?line ok = genie_event:sync_notify(my_dummy_handler, delete_event),
    ?line receive
	      {dummy1_h, removed} ->
		  ok
	  end,
    ?line [] = genie_event:which_handlers(my_dummy_handler),
    ?line ok = genie_event:add_handler(my_dummy_handler, {dummy_h,a}, [self()]),

    ?line ok = genie_event:sync_notify(my_dummy_handler, error_event),
    ?line receive
	      {dummy_h, returned_error} ->
		  ok
	  end,
    ?line [] = genie_event:which_handlers(my_dummy_handler),

    %% Supervised handler.

    ?line ok = genie_event:add_sup_handler(my_dummy_handler, dummy_h, [self()]),
    ?line [dummy_h] = genie_event:which_handlers(my_dummy_handler),
    ?line ok = genie_event:sync_notify(my_dummy_handler, Event),
    ?line receive
	      {dummy_h, Event} ->
		  ok
	  end,

    ?line ok = genie_event:sync_notify(my_dummy_handler, do_crash),
    ?line receive
	      {genie_event_EXIT, dummy_h, {'EXIT',_}} ->
		  ok
	  end,

    ?line ok = genie_event:add_sup_handler(my_dummy_handler, dummy_h, [self()]),
    ?line ok = genie_event:sync_notify(my_dummy_handler,
				     {swap_event,dummy1_h,swap}),
    ?t:sleep(1000),
    ?line [dummy1_h] = genie_event:which_handlers(my_dummy_handler),

    ?line ok = genie_event:sync_notify(my_dummy_handler, do_crash),
    ?line receive
	      {genie_event_EXIT, dummy1_h, {'EXIT',_}} ->
		  ok
	  end,

    ?line ok = genie_event:add_sup_handler(my_dummy_handler, dummy_h, [self()]),
    ?line ok = genie_event:sync_notify(my_dummy_handler,
				     {swap_event,dummy1_h,swap}),
    ?t:sleep(1000),
    ?line [dummy1_h] = genie_event:which_handlers(my_dummy_handler),

    ?line ok = genie_event:sync_notify(my_dummy_handler, delete_event),
    ?line receive
	      {dummy1_h, removed} ->
		  ok
	  end,

    ?line receive
	      {genie_event_EXIT, dummy1_h, normal} ->
		  ok
	  end,

    ?line [] = genie_event:which_handlers(my_dummy_handler),

    ?line ok = genie_event:stop(my_dummy_handler),
    ok.

call(doc) -> [];
call(suite) -> [];
call(Config) when is_list(Config) ->
    ?line {ok,_} = genie_event:start({local, my_dummy_handler}),
    ?line ok = genie_event:add_handler(my_dummy_handler, dummy_h, [self()]),
    ?line ok = genie_event:add_handler(my_dummy_handler, {dummy_h, 1}, [self()]),
    ?line [{dummy_h, 1}, dummy_h] = genie_event:which_handlers(my_dummy_handler),
    ?line {'EXIT',_} = (catch genie_event:call(non_exist, dummy_h, hejsan)),
    ?line {error, bad_module} =
	genie_event:call(my_dummy_handler, bad_h, hejsan),
    ?line {ok, hejhopp} = genie_event:call(my_dummy_handler, dummy_h, hejsan),
    ?line {ok, hejhopp} = genie_event:call(my_dummy_handler, {dummy_h, 1},
					 hejsan),
    ?line {ok, hejhopp} = genie_event:call(my_dummy_handler, dummy_h, hejsan,
					 10000),
    ?line {'EXIT', {timeout, _}} =
	(catch genie_event:call(my_dummy_handler, dummy_h, hejsan, 0)),
    flush(),
    ?line ok = genie_event:delete_handler(my_dummy_handler, {dummy_h, 1}, []),
    ?line {ok, swapped} = genie_event:call(my_dummy_handler, dummy_h,
					 {swap_call,dummy1_h,swap}),
    ?line [dummy1_h] = genie_event:which_handlers(my_dummy_handler),
    ?line {error, bad_module} =
	genie_event:call(my_dummy_handler, dummy_h, hejsan),
    ?line ok = genie_event:call(my_dummy_handler, dummy1_h, delete_call),
    ?line receive
	      {dummy1_h, removed} ->
		  ok
	  end,
    ?line [] = genie_event:which_handlers(my_dummy_handler),
    ?line ok = genie_event:add_handler(my_dummy_handler, dummy_h, [self()]),

    ?line {error, {return, faulty}} =
	genie_event:call(my_dummy_handler, dummy_h, error_call),
    ?line receive
	      {dummy_h, returned_error} ->
		  ok
	  end,
    ?line [] = genie_event:which_handlers(my_dummy_handler),
    ?line ok = genie_event:add_handler(my_dummy_handler, dummy_h, [self()]),

    ?line {error, {'EXIT', _}} =
	genie_event:call(my_dummy_handler, dummy_h, exit_call),

    ?line [] = genie_event:which_handlers(my_dummy_handler),

    %% Handler with id, {Mod,Id}

    ?line ok = genie_event:add_handler(my_dummy_handler, {dummy_h,1}, [self()]),
    ?line [{dummy_h,1}] = genie_event:which_handlers(my_dummy_handler),
    ?line {error, bad_module} =
	genie_event:call(my_dummy_handler, bad_h, hejsan),
    ?line {ok, hejhopp} = genie_event:call(my_dummy_handler, {dummy_h,1},
					 hejsan),
    ?line {ok, swapped} = genie_event:call(my_dummy_handler, {dummy_h,1},
					 {swap_call,{dummy1_h,2},swap}),
    ?line [{dummy1_h,2}] = genie_event:which_handlers(my_dummy_handler),
    ?line {error, bad_module} =
	genie_event:call(my_dummy_handler, dummy_h, hejsan),
    ?line ok = genie_event:call(my_dummy_handler, {dummy1_h,2}, delete_call),
    ?line receive
	      {dummy1_h, removed} ->
		  ok
	  end,
    ?line [] = genie_event:which_handlers(my_dummy_handler),
    ?line ok = genie_event:add_handler(my_dummy_handler, {dummy_h,3}, [self()]),

    ?line {error, {return, faulty}} =
	genie_event:call(my_dummy_handler, {dummy_h,3}, error_call),
    ?line receive
	      {dummy_h, returned_error} ->
		  ok
	  end,
    ?line [] = genie_event:which_handlers(my_dummy_handler),
    ?line ok = genie_event:add_handler(my_dummy_handler, {dummy_h,4}, [self()]),

    ?line {error, {'EXIT', _}} =
	genie_event:call(my_dummy_handler, {dummy_h,4}, exit_call),

    ?line [] = genie_event:which_handlers(my_dummy_handler),

    %% Supervised handler.

    ?line ok = genie_event:add_sup_handler(my_dummy_handler, dummy_h, [self()]),
    ?line [dummy_h] = genie_event:which_handlers(my_dummy_handler),
    ?line {error, bad_module} =
	genie_event:call(my_dummy_handler, bad_h, hejsan),
    ?line {ok, hejhopp} = genie_event:call(my_dummy_handler, dummy_h, hejsan),
    ?line {ok, swapped} = genie_event:call(my_dummy_handler, dummy_h,
					 {swap_call,dummy1_h,swap}),
    ?line [dummy1_h] = genie_event:which_handlers(my_dummy_handler),
    ?line {error, bad_module} =
	genie_event:call(my_dummy_handler, dummy_h, hejsan),
    ?line ok = genie_event:call(my_dummy_handler, dummy1_h, delete_call),
    ?line receive
	      {dummy1_h, removed} ->
		  ok
	  end,

    ?line receive
	      {genie_event_EXIT, dummy1_h, normal} ->
		  ok
	  end,

    ?line [] = genie_event:which_handlers(my_dummy_handler),
    ?line ok = genie_event:add_sup_handler(my_dummy_handler, dummy_h, [self()]),

    ?line {error, {return, faulty}} =
	genie_event:call(my_dummy_handler, dummy_h, error_call),
    ?line receive
	      {dummy_h, returned_error} ->
		  ok
	  end,

    ?line receive
	      {genie_event_EXIT, dummy_h, {return,faulty}} ->
		  ok
	  after 1000 ->
		  ?t:fail({no, {genie_event_EXIT, dummy_h, {return,faulty}}})
	  end,

    ?line [] = genie_event:which_handlers(my_dummy_handler),
    ?line ok = genie_event:add_sup_handler(my_dummy_handler, dummy_h, [self()]),

    ?line {error, {'EXIT', _}} =
	genie_event:call(my_dummy_handler, dummy_h, exit_call),

    ?line receive
	      {genie_event_EXIT, dummy_h, {'EXIT',_}} ->
		  ok
	  after 1000 ->
		  ?t:fail({no, {genie_event_EXIT, dummy_h, {'EXIT','_'}}})
	  end,

    ?line [] = genie_event:which_handlers(my_dummy_handler),

    ?line ok = genie_event:stop(my_dummy_handler),
    ok.

flush() ->
    receive _ -> flush() after 0 -> ok end.

info(doc) -> [];
info(suite) -> [];
info(Config) when is_list(Config) ->
    ?line {ok,_} = genie_event:start({local, my_dummy_handler}),
    ?line ok = genie_event:add_handler(my_dummy_handler, dummy_h, [self()]),
    Info = {info, self()},
    ?line [dummy_h] = genie_event:which_handlers(my_dummy_handler),
    ?line my_dummy_handler ! Info,
    ?line receive
	      {dummy_h, Info} ->
		  ok
	  end,
    ?line my_dummy_handler ! {swap_info,dummy1_h,swap},
    ?t:sleep(1000),
    ?line [dummy1_h] = genie_event:which_handlers(my_dummy_handler),
    ?line my_dummy_handler ! Info,
    ?line receive
	      {dummy1_h, Info} ->
		  ok
	  end,
    ?line my_dummy_handler ! delete_info,
    ?line receive
	      {dummy1_h, removed} ->
		  ok
	  end,
    ?line [] = genie_event:which_handlers(my_dummy_handler),
    ?line ok = genie_event:add_handler(my_dummy_handler, dummy_h, [self()]),

    ?line my_dummy_handler ! error_info,
    ?line receive
	      {dummy_h, returned_error} ->
		  ok
	  end,
    ?line [] = genie_event:which_handlers(my_dummy_handler),

    %% Handler with id, {Mod,Id}

    ?line ok = genie_event:add_handler(my_dummy_handler, {dummy_h,1}, [self()]),
    ?line [{dummy_h,1}] = genie_event:which_handlers(my_dummy_handler),
    ?line my_dummy_handler ! Info,
    ?line receive
	      {dummy_h, Info} ->
		  ok
	  end,
    ?line my_dummy_handler ! {swap_info,{dummy1_h,2},swap},
    ?t:sleep(1000),
    ?line [{dummy1_h,2}] = genie_event:which_handlers(my_dummy_handler),
    ?line my_dummy_handler ! Info,
    ?line receive
	      {dummy1_h, Info} ->
		  ok
	  end,
    ?line my_dummy_handler ! delete_info,
    ?line receive
	      {dummy1_h, removed} ->
		  ok
	  end,
    ?line [] = genie_event:which_handlers(my_dummy_handler),
    ?line ok = genie_event:add_handler(my_dummy_handler, {dummy_h,3}, [self()]),

    ?line my_dummy_handler ! error_info,
    ?line receive
	      {dummy_h, returned_error} ->
		  ok
	  end,
    ?line [] = genie_event:which_handlers(my_dummy_handler),

    %% Supervised handler

    ?line ok = genie_event:add_sup_handler(my_dummy_handler, dummy_h, [self()]),
    ?line [dummy_h] = genie_event:which_handlers(my_dummy_handler),
    ?line my_dummy_handler ! Info,
    ?line receive
	      {dummy_h, Info} ->
		  ok
	  end,
    ?line my_dummy_handler ! {swap_info,dummy1_h,swap},
    ?t:sleep(1000),
    ?line [dummy1_h] = genie_event:which_handlers(my_dummy_handler),
    ?line my_dummy_handler ! Info,
    ?line receive
	      {dummy1_h, Info} ->
		  ok
	  end,
    ?line my_dummy_handler ! delete_info,
    ?line receive
	      {dummy1_h, removed} ->
		  ok
	  end,

    ?line receive
	      {genie_event_EXIT, dummy1_h, normal} ->
		  ok
	  after 1000 ->
		  ?t:fail({no, {genie_event_EXIT, dummy1_h, normal}})
	  end,

    ?line [] = genie_event:which_handlers(my_dummy_handler),

    ?line ok = genie_event:add_sup_handler(my_dummy_handler, dummy_h, [self()]),

    ?line my_dummy_handler ! error_info,
    ?line receive
	      {dummy_h, returned_error} ->
		  ok
	  end,

    ?line receive
	      {genie_event_EXIT, dummy_h, {return,faulty}} ->
		  ok
	  after 1000 ->
		  ?t:fail({no, {genie_event_EXIT, dummy_h, {return,faulty}}})
	  end,

    ?line ok = genie_event:add_sup_handler(my_dummy_handler, dummy_h, [self()]),
    ?line my_dummy_handler ! do_crash,

    ?line receive
	      {genie_event_EXIT, dummy_h, {'EXIT',_}} ->
		  ok
	  after 1000 ->
		  ?t:fail({no, {genie_event_EXIT, dummy_h, {'EXIT','_'}}})
	  end,

    ?line [] = genie_event:which_handlers(my_dummy_handler),

    ?line ok = genie_event:stop(my_dummy_handler),
    ok.

call_format_status(suite) ->
    [];
call_format_status(doc) ->
    ["Test that sys:get_status/1,2 calls format_status/2"];
call_format_status(Config) when is_list(Config) ->
    ?line {ok, Pid} = genie_event:start({local, my_dummy_handler}),
    %% State here intentionally differs from what we expect from format_status
    State = self(),
    FmtState = "dummy1_h handler state",
    ?line ok = genie_event:add_handler(my_dummy_handler, dummy1_h, [State]),
    ?line Status1 = sys:get_status(Pid),
    ?line Status2 = sys:get_status(Pid, 5000),
    ?line ok = genie_event:stop(Pid),
    ?line {status, Pid, _, [_, _, Pid, [], Data1]} = Status1,
    ?line HandlerInfo1 = proplists:get_value(items, Data1),
    ?line {"Installed handlers", [{_,dummy1_h,_,FmtState,_}]} = HandlerInfo1,
    ?line {status, Pid, _, [_, _, Pid, [], Data2]} = Status2,
    ?line HandlerInfo2 = proplists:get_value(items, Data2),
    ?line {"Installed handlers", [{_,dummy1_h,_,FmtState,_}]} = HandlerInfo2,
    ok.

call_format_status_anon(suite) ->
    [];
call_format_status_anon(doc) ->
    ["Test that sys:get_status/1,2 calls format_status/2 for anonymous genie_event processes"];
call_format_status_anon(Config) when is_list(Config) ->
    ?line {ok, Pid} = genie_event:start(),
    %% The 'Name' of the genie_event process will be a pid() here, so
    %% the next line will crash if format_status can't string-ify pids.
    ?line Status1 = sys:get_status(Pid),
    ?line ok = genie_event:stop(Pid),
    Header = "Status for event handler " ++  pid_to_list(Pid),
    ?line {status, Pid, _, [_, _, Pid, [], Data1]} = Status1,
    ?line Header = proplists:get_value(header, Data1),
    ok.


error_format_status(suite) ->
    [];
error_format_status(doc) ->
    ["Test that a handler error calls format_status/2"];
error_format_status(Config) when is_list(Config) ->
    ?line error_logger_forwarder:register(),
    OldFl = process_flag(trap_exit, true),
    State = self(),
    ?line {ok, Pid} = genie_event:start({local, my_dummy_handler}),
    ?line ok = genie_event:add_sup_handler(my_dummy_handler, dummy1_h, [State]),
    ?line ok = genie_event:notify(my_dummy_handler, do_crash),
    ?line receive
	      {genie_event_EXIT,dummy1_h,{'EXIT',_}} -> ok
	  after 5000 ->
		  ?t:fail(exit_genie_event)
	  end,
    FmtState = "dummy1_h handler state",
    receive
	{error,_GroupLeader, {Pid,
			      "** genie_event handler"++_,
			      [dummy1_h,my_dummy_handler,do_crash,
			       FmtState, _]}} ->
	    ok;
	Other ->
	    ?line io:format("Unexpected: ~p", [Other]),
	    ?line ?t:fail()
    end,
    ?t:messages_get(),
    ?line ok = genie_event:stop(Pid),
    process_flag(trap_exit, OldFl),
    ok.

get_state(suite) ->
    [];
get_state(doc) ->
    ["Test that sys:get_state/1,2 return the genie_event state"];
get_state(Config) when is_list(Config) ->
    {ok, Pid} = genie_event:start({local, my_dummy_handler}),
    State1 = self(),
    ok = genie_event:add_handler(my_dummy_handler, dummy1_h, [State1]),
    [{dummy1_h,false,State1}] = sys:get_state(Pid),
    [{dummy1_h,false,State1}] = sys:get_state(Pid, 5000),
    State2 = {?MODULE, self()},
    ok = genie_event:add_handler(my_dummy_handler, {dummy1_h,id}, [State2]),
    Result1 = sys:get_state(Pid),
    [{dummy1_h,false,State1},{dummy1_h,id,State2}] = lists:sort(Result1),
    Result2 = sys:get_state(Pid, 5000),
    [{dummy1_h,false,State1},{dummy1_h,id,State2}] = lists:sort(Result2),
    ok = genie_event:stop(Pid),
    ok.

replace_state(suite) ->
    [];
replace_state(doc) ->
    ["Test that replace_state/2,3 replace the genie_event state"];
replace_state(Config) when is_list(Config) ->
    {ok, Pid} = genie_event:start({local, my_dummy_handler}),
    State1 = self(),
    ok = genie_event:add_handler(my_dummy_handler, dummy1_h, [State1]),
    [{dummy1_h,false,State1}] = sys:get_state(Pid),
    NState1 = "replaced",
    Replace1 = fun({dummy1_h,false,_}=S) -> setelement(3,S,NState1) end,
    [{dummy1_h,false,NState1}] = sys:replace_state(Pid, Replace1),
    [{dummy1_h,false,NState1}] = sys:get_state(Pid),
    NState2 = "replaced again",
    Replace2 = fun({dummy1_h,false,_}=S) -> setelement(3,S,NState2) end,
    [{dummy1_h,false,NState2}] = sys:replace_state(Pid, Replace2, 5000),
    [{dummy1_h,false,NState2}] = sys:get_state(Pid),
    %% verify no change in state if replace function crashes
    Replace3 = fun(_) -> exit(fail) end,
    [{dummy1_h,false,NState2}] = sys:replace_state(Pid, Replace3),
    [{dummy1_h,false,NState2}] = sys:get_state(Pid),
    ok.
