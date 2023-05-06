open Lwt.Infix
open Archi_lwt

let src = Logs.Src.create "example" ~doc:"logs from program entrypoint"

module Log = (val Logs.src_log src : Logs.LOG)

type config =
  { db_host : string
  ; db_port : int
  ; webserver_port : int
  }

(* Reading a config file doesn't need to be started or stopped, for this we use
   'Component.identity'. Imagine these arguments being read in by use of
   'Cmdliner.Cmd.eval_value' or equivalent. *)
let config =
  Component.identity
  @@ { db_host = "127.0.0.1"; db_port = 5432; webserver_port = 3000 }

module Database = struct
  let start () conf =
    let connection_url =
      Printf.sprintf
        "postgresql://user:password@%s:%d/db_name?sslmode=allow&connect_timeout=15"
        conf.db_host
        conf.db_port
    in
    Log.info (fun m ->
        m "Connecting to database: %s:%d" conf.db_host conf.db_port);
    let pool =
      match
        Caqti_lwt.connect_pool ~max_size:4 (Uri.of_string connection_url)
      with
      | Ok pool -> pool
      | Error err ->
        Log.err (fun m -> m "%s" (Caqti_error.show err));
        failwith (Caqti_error.show err)
    in
    Lwt_result.return
      (pool : (Caqti_lwt.connection, Caqti_error.connect) Caqti_lwt.Pool.t)

  (* The 'stop' function takes a single argument of the type returned by
     'start' *)
  let stop pool =
    Log.info (fun m -> m "Draining database connection pool");
    Caqti_lwt.Pool.drain pool

  (* Each dependency adds an additional positional argument to the 'start'
     function *)
  let component = Component.using ~start ~stop ~dependencies:[ config ]
end

module WebServer = struct
  type t = Lwt_io.server

  (* 'start' takes dependencies as positional arguments. The type is whatever
     the depencency 'start' function returns. *)
  let start () _db conf : (t, [ `Msg of string ]) Lwt_result.t =
    let listen_address =
      Unix.(ADDR_INET (inet_addr_loopback, conf.webserver_port))
    in
    Lwt_io.establish_server_with_client_address listen_address (fun _ _ ->
        Lwt_io.printlf "Client connected.%!")
    >>= fun server ->
    Format.eprintf "Started server.@.";
    Lwt_result.return server

  let stop server =
    Lwt_io.shutdown_server server >>= fun () ->
    Lwt_io.eprintlf "Stopped server.%!"

  let component =
    Component.using ~start ~stop ~dependencies:[ Database.component; config ]
end

let system =
  System.make_imperative
    [ "db", Database.component; "server", WebServer.component ]

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
    Format.eprintf
      "ERROR: %s@."
      (match error with `Msg s -> s | `Cycle_found -> "cycle found");
    exit 1

let () = Lwt_main.run (main ())
