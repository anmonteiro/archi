open Archi

module Database = struct
  type db = int

  let db_ref = ref None

  let start () =
    let res = 42 in
    db_ref := Some res;
    Ok res

  let stop _db = db_ref := None

  let component = Component.component ~name:"db" ~start ~stop
end

module WebServer = struct
  type t = int

  let server_ref = ref None

  let start () db : (t, string) result =
    let res = 3000 in
    server_ref := Some (db, res);
    Ok res

  let stop _server = server_ref := None

  let component =
    Component.using
      ~name:"webserver"
      ~start
      ~stop
      ~dependencies:[ Database.component ]
end

let system =
  System.make [ "db", Database.component; "server", WebServer.component ]

let test_start_stop_order () =
  let started = System.start () system in
  match started with
  | Ok system ->
    Alcotest.(check (option int) "DB started" (Some 42) !Database.db_ref);
    (match !WebServer.server_ref with
    | Some (db, server) ->
      Alcotest.(check int "Server started" 3000 server);
      Alcotest.(check int "DB started first" 42 db)
    | None ->
      Alcotest.fail "Server should have started");
    ignore @@ System.stop system;
    (match !WebServer.server_ref with
    | Some _ ->
      Alcotest.fail "Server should have stopped"
    | None ->
      Alcotest.(check pass "Server stopped" true true));
    Alcotest.(check (option int) "DB stopped" None !Database.db_ref)
  | Error error ->
    Alcotest.fail error

let suite = [ "start / stop order", `Quick, test_start_stop_order ]

let () = Alcotest.run "archi unit tests" [ "archi", suite ]
