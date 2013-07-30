genie
=====
A drop-in replacement for `gen`, `gen_server` and `gen_fsm` with the following
additional features:
* Asynchronous starting of behaviours (with optional timeout)
* Return `{ok, Pid, Info}` from `start(_link)` functions
* `call_list`, `cast_list` and `send_list` functions
* Common features moved to `genie` for use in custom behaviours
* Documentation of `genie` to aid creation of custom behaviours

The majority of the code is taken directly from OTP release R16B01. Several
commits involve moving common functions to the `genie` module.

semver
------
This application follows `semver` and is at version `1.0.0`.

Incompatibility
---------------
The behaviour of `genie_server:cast/2` is slightly different to
`gen_server:cast/2`. If a `global` or `via` name is used and no process is
associated with that name a `badarg` error will nolonger be raised. This is
consistent with the handling of a locally registered name. `genie` has a
`send/3` function which behaves like `gen_fsm:send_event/2` and will raise a
`badarg` error.

Installation
------------
Clone the repo:
```
git clone https://github.com/fishcakez/genie.git
cd genie
```
Build and test with rebar:
```
rebar compile doc ct
```
Or with erlang.mk:
```
make docs tests
```

Custom Behaviours
-----------------
There is no guide for writing custom behaviours but there is a `gen_basic`
module in the `examples` directory which contains alot of inline comments about
how to implement a custom behaviour. I originally wrote `gen_basic` as notes for
myself so apologies for any typos. Inspiration may also be drawn from
`genie_server` and `genie_fsm`.

License
-------
Erlang Public License V1.1
