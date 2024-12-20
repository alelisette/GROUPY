-module(gms3).
-export([start/1, start/2]).
-define(timeout, 1000).
-define(arghh, 100).

start(Name) ->
    Self = self(),
    spawn_link(fun() -> init(Name, Self) end).

init(Name, Master) ->
    {A1, A2, A3} = now(),
    random:seed(A1, A2, A3),
    leader(Name, Master, 1, []).

start(Name, Grp) ->
    Self = self(),
    spawn_link(fun() -> init(Name, Grp, Self) end).

init(Name, Grp, Master) ->
    Self = self(),
    Grp ! {join, Self},
    receive
        {view, N, Leader, Slaves} ->
            Master ! joined,
            Ref = erlang:monitor(process, Leader),
            slave(Name, Master, Leader, N, 0, Slaves, Ref)
    after ?timeout ->
        Master ! {error, "no reply from leader"}
    end.

leader(Name, Master, N, Slaves) ->
    receive
        {mcast, Msg} ->
            bcast(Name, {msg, N, Msg}, Slaves),
            Master ! {deliver, Msg},
            leader(Name, Master, N+1, Slaves);
        {join, Peer} ->
            NewSlaves = lists:append(Slaves, [Peer]),
            bcast(Name, {view, N, self(), NewSlaves}, NewSlaves),
            leader(Name, Master, N + 1, NewSlaves);
        stop ->
            ok;
        Error ->
            io:format("leader ~s: strange message ~w~n", [Name, Error])
    end.

bcast(Name, Msg, Nodes) ->
    lists:foreach(fun(Node) -> Node ! Msg, crash(Name, Msg) end, Nodes).

crash(Name, Msg) ->
    case rand:uniform(?arghh) of
        ?arghh ->
            io:format("leader ~s CRASHED: msg ~w~n", [Name, Msg]),
            exit(no_luck);
        _ ->
            ok
    end.

slave(Name, Master, Leader, N, Last, Slaves, Ref) ->
    receive
        {mcast, Msg} ->
            Leader ! {mcast, Msg},
            slave(Name, Master, Leader, N, Last, Slaves, Ref);
        {join, Peer} ->
            Leader ! {join, Peer},
            slave(Name, Master, Leader, N, Last, Slaves, Ref);
        {msg, I, _} when I < N ->
            slave(Name, Master, Leader, N, Last, Slaves, Ref);
        {msg, I, Msg} ->
            Master ! {deliver, Msg},
            slave(Name, Master, Leader, I + 1, {msg, I, Msg}, Slaves, Ref);
        {view, I, NewLeader, NewSlaves} ->
            erlang:demonitor(Ref, [flush]),
            NewRef = erlang:monitor(process, NewLeader),
            slave(Name, Master, NewLeader, I+1, {view, I, Leader, NewSlaves}, NewSlaves, NewRef);
        {'DOWN', _Ref, process, Leader, _Reason} ->
            election(Name, Master, N, Last, Slaves);
        stop ->
            ok;
        Error ->
            io:format("slave ~s: strange message ~w~n", [Name, Error])
    end.

election(Name, Master, N, Last, Slaves) ->
    Self = self(),
    case Slaves of
        [Self | Rest] ->
            bcast(Name, {view, N, self(), Rest}, Rest),
            leader(Name, Master, N, Rest);
        [NewLeader | Rest] ->
            Ref = erlang:monitor(process, NewLeader),
            slave(Name, Master, NewLeader, N, Last, Rest, Ref)
    end.



