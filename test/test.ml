(*----------------------------------------------------------------------------
 * Copyright (c) 2020, António Nuno Monteiro
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are met:
 *
 * 1. Redistributions of source code must retain the above copyright notice,
 *    this list of conditions and the following disclaimer.
 *
 * 2. Redistributions in binary form must reproduce the above copyright notice,
 *    this list of conditions and the following disclaimer in the documentation
 *    and/or other materials provided with the distribution.
 *
 * 3. Neither the name of the copyright holder nor the names of its
 *    contributors may be used to endorse or promote products derived from
 *    this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
 * AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE
 * LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
 * CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
 * SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
 * INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
 * CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
 * ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
 * POSSIBILITY OF SUCH DAMAGE.
 *---------------------------------------------------------------------------*)

open Archi

module Database = struct
  type t = int

  type ctx = unit

  let name = "db"

  let db_ref = ref None

  let start () =
    let res = 42 in
    db_ref := Some res;
    Ok res

  let stop _db = db_ref := None

  let component = Component.make ~start ~stop
end

module WebServer = struct
  type t = int

  type ctx = unit

  type args = Database.t -> (t, [ `Msg of string ]) result

  let name = "webserver"

  let server_ref = ref None

  let start () db : (t, [ `Msg of string ]) result =
    let res = 3000 in
    server_ref := Some (db, res);
    Ok res

  let stop _server = server_ref := None

  let component =
    Component.using ~start ~stop ~dependencies:[ Database.component ]
end

let system =
  System.make [ "db", Database.component; "server", WebServer.component ]

let module_system =
  let db = Component.make_m (module Database) in
  System.make
    [ "db", db
    ; "server", Component.using_m (module WebServer) ~dependencies:[ db ]
    ]

let test_start_stop_order system () =
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
  | Error `Cycle_found ->
    Alcotest.fail "cycle"
  | Error (`Msg error) ->
    Alcotest.fail error

let test_duplicates_start_once () =
  let starts = ref 0 in
  let db =
    Component.make
      ~start:(fun () ->
        incr starts;
        Ok ())
      ~stop:ignore
  in
  let mk_server () =
    Component.using
      ~start:(fun () (() as _db) ->
        incr starts;
        Ok ())
      ~stop:ignore
      ~dependencies:[ db ]
  in
  let system =
    (* 3 dbs which should start only once. 2 servers which start once.
     * `!starts` should be 3. *)
    System.make
      [ "db", db
      ; "server", mk_server ()
      ; "same db", db
      ; "depends on db again", mk_server ()
      ]
  in
  let started = System.start () system in
  match started with
  | Ok _started_system ->
    Alcotest.(check int) "3 components started" 3 !starts
  | Error `Cycle_found ->
    Alcotest.fail "cycle"
  | Error (`Msg error) ->
    Alcotest.fail error

let module_system_reusable =
  let db = Component.make_m (module Database) in
  System.make_reusable
    ~lift:(fun db server -> db, server)
    [ "db", db
    ; "server", Component.using_m (module WebServer) ~dependencies:[ db ]
    ]

let using_system_ref, system_using_reusable_system =
  let ref = ref None in
  ( ref
  , System.make
      [ ( "server"
        , Component.using
            ~start:(fun () (db, server) ->
              let res = server + db in
              ref := Some res;
              Ok res)
            ~stop:ignore
            ~dependencies:[ Component.of_system module_system_reusable ] )
      ] )

let test_start_stop_order_system_deps () =
  let started = System.start () system_using_reusable_system in
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
  | Error `Cycle_found ->
    Alcotest.fail "cycle"
  | Error (`Msg error) ->
    Alcotest.fail error

let test_get () =
  let started = System.start () module_system_reusable in
  match started with
  | Ok system ->
    let db, server = System.get system in
    Alcotest.(check int "DB" 42 db);
    Alcotest.(check int "Server" 3000 server)
  | Error `Cycle_found ->
    Alcotest.fail "cycle"
  | Error (`Msg error) ->
    Alcotest.fail error

let test_identity () =
  let identity_component = Component.identity "I'm the component" in
  let system =
    System.make_reusable
      ~lift:(fun id -> id)
      [ "identity component", identity_component ]
  in
  let started = System.start () system in
  (match started with
  | Ok system ->
    let id = System.get system in
    Alcotest.(check string "expected value" "I'm the component" id)
  | Error `Cycle_found ->
    Alcotest.fail "cycle"
  | Error (`Msg error) ->
    Alcotest.fail error);
  let v = ref "" in
  let server =
    Component.using
      ~dependencies:[ identity_component ]
      ~start:(fun () id ->
        v := id;
        Ok ())
      ~stop:ignore
  in
  let system =
    System.make [ "identity component", identity_component; "server", server ]
  in
  let started = System.start () system in
  match started with
  | Ok _system ->
    Alcotest.(check string "expected value" "I'm the component" !v)
  | Error `Cycle_found ->
    Alcotest.fail "cycle"
  | Error (`Msg error) ->
    Alcotest.fail error

let suite =
  [ "start / stop order", `Quick, test_start_stop_order system
  ; ( "start / stop order, module system"
    , `Quick
    , test_start_stop_order module_system )
  ; "duplicates", `Quick, test_duplicates_start_once
  ; "system depending on system", `Quick, test_start_stop_order_system_deps
  ; "get resulting value", `Quick, test_get
  ; "test identity component", `Quick, test_identity
  ]

let () = Alcotest.run "archi unit tests" [ "archi", suite ]
