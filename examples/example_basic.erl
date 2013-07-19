-module(example_basic).

-behaviour(genie_basic).

%% api

-export([start_link/1]).
-export([start_link/2]).
-export([call/2]).
-export([call/3]).

%% genie_basic callbacks

-export([init/1]).
-export([handle_call/3]).
-export([handle_info/2]).
-export([code_change/3]).
-export([terminate/2]).

%% api

start_link(Opts) ->
    genie_basic:start_link(?MODULE, [], Opts).

start_link(Name, Opts) ->
    genie_basic:start_link(Name, ?MODULE, [], Opts).

call(Process, Request) ->
    genie_basic:call(Process, Request).

call(Process, Request, Timeout) ->
    genie_basic:call(Process, Request, Timeout).

%% genie_basic callbacks

init([]) ->
    {ok, undefined}.

handle_call({reply, Request}, _From, State) ->
    {reply, Request, State};
handle_call(noreply, _From, State) ->
    {noreply, State};
handle_call({stop, Reason, Reply}, _From, State) ->
    {stop, Reason, Reply, State};
handle_call({stop, Reason}, _From, State) ->
    {stop, Reason, State}.

handle_info(Msg, State) ->
    ok = io:format("Received msg: ~p~n", [Msg]),
    {noreply, State}.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

terminate(_Reason, _State) ->
    ok.
