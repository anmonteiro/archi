# archi

Archi is an OCaml library for managing the lifecycle of stateful components and
their dependencies.

## Installation

```shell
$ opam install archi # choose your preferred runtime: archi-lwt archi-async
```

# Usage & Examples

TODO, read the [mli](./lib/archi.mli) file for now.

### Examples

The design of this library is heavily inspired by the [`component`][clojure-component]
library for Clojure. The terminology is similar, and so is the API.

[clojure-component]: https://github.com/stuartsierra/component

```ocaml
open Lwt.Infix
open Archi_lwt

module Database = struct
  type db = { handle : int }

  let start () =
    Format.eprintf "Started DB.@.";
    Lwt_result.return { handle = 42 }

  let stop _db = Lwt_io.eprintlf "Stopped DB.%!"

  let component = Component.make ~start ~stop
end

module WebServer = struct
  type t = Lwt_io.server

  let start () _db : (t, string) Lwt_result.t =
    let listen_address = Unix.(ADDR_INET (inet_addr_loopback, 3000)) in
    Lwt_io.establish_server_with_client_address listen_address (fun _ _ ->
        Lwt_io.printlf "Client connected.%!")
    >>= fun server ->
    Format.eprintf "Started server.@.";
    Lwt_result.return server

  let stop server =
    Lwt_io.shutdown_server server >>= fun () ->
    Lwt_io.eprintlf "Stopped server.%!"

  let component =
    Component.using ~start ~stop ~dependencies:[ Database.component ]
end

let system =
  System.make [ "db", Database.component; "server", WebServer.component ]

let main () =
  System.start () system >>= fun system ->
  match system with
  | Ok system ->
    let forever, waiter = Lwt.wait () in
    Sys.(
      set_signal
        sigint
        (Signal_handle
           (fun _ ->
             Format.eprintf "SIGINT received, tearing down.@.";
             Lwt.async (fun () ->
                 System.stop system >|= fun _stopped_system ->
                 Lwt.wakeup_later waiter ()))));
    forever
  | Error error ->
    Format.eprintf "ERROR: %s@." error;
    exit 1

let () = Lwt_main.run (main ())

```

## License & Copyright

Copyright (c) 2020 António Nuno Monteiro

Archi is distributed under the 3-Clause BSD License, see [LICENSE](./LICENSE).

