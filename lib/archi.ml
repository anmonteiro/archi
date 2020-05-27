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

include Archi_intf

module Make (Io : IO) = struct
  module Io = struct
    include Io

    module Infix = struct
      let ( >|= ) x f = map f x
    end

    module Result = struct
      let return x = Io.return (Ok x)

      let bind x f =
        bind x (function Ok x -> f x | Error _ as err -> Io.return err)

      let map f x = map (function Ok x -> Ok (f x) | Error _ as err -> err) x

      module Infix = struct
        let ( >|= ) x f = map f x

        let ( >>= ) = bind
      end
    end
  end

  module Types = struct
    module rec Component : sig
      type (_, _, _) deps =
        | [] : ('ctx, 'ty, 'ty) deps
        | ( :: ) :
            ('ctx, 'a) t * ('ctx, 'b, 'ty) deps
            -> ('ctx, 'a -> 'b, 'ty) deps

      and (_, _) t =
        | Component :
            { dependencies :
                ('ctx, 'args, ('ty, [ `Msg of string ]) result Io.t) deps
            ; start : 'ctx -> 'args
            ; stop : 'ty -> unit Io.t
            ; hkey : 'ty Hmap.key
            }
            -> ('ctx, 'ty) t
        | System : ('ctx, 'args, 'ty) System.system -> ('ctx, 'ty) t

      type _ any_component = AnyComponent : ('ctx, _) t -> 'ctx any_component
    end =
      Component

    and System : sig
      type (_, _, _) components =
        | [] : ('ctx, 'ty, 'ty) components
        | ( :: ) :
            (string * ('ctx, 'a) Component.t) * ('ctx, 'b, 'ty) components
            -> ('ctx, 'a -> 'b, 'ty) components

      type ('ctx, 'args, 'ty) system =
        { components : ('ctx, 'args, 'ty) components
        ; hkey : 'ty Hmap.key
        ; lift : 'args
        }

      type (_, _, _) t =
        | System :
            { system : ('ctx, 'args, 'ty) system
            ; values : Hmap.t
            }
            -> ('ctx, 'ty, _) t

      val to_any_component_list
        :  ('ctx, 'args, 'ty) system
        -> 'ctx Component.any_component list
    end = struct
      type (_, _, _) components =
        | [] : ('ctx, 'ty, 'ty) components
        | ( :: ) :
            (string * ('ctx, 'a) Component.t) * ('ctx, 'b, 'ty) components
            -> ('ctx, 'a -> 'b, 'ty) components

      type ('ctx, 'args, 'ty) system =
        { components : ('ctx, 'args, 'ty) components
        ; hkey : 'ty Hmap.key
        ; lift : 'args
        }

      type (_, _, _) t =
        | System :
            { system : ('ctx, 'args, 'ty) system
            ; values : Hmap.t
            }
            -> ('ctx, 'ty, _) t

      let fold_left ~f ~init { components; _ } =
        let rec loop
            : type ty args.
              f:('res -> string * 'ctx Component.any_component -> 'res)
              -> init:'res
              -> ('ctx, args, ty) components
              -> 'res
          =
         fun ~f ~init deps ->
          match deps with
          | [] ->
            init
          | (lbl, x) :: xs ->
            loop ~f ~init:(f init (lbl, AnyComponent x)) xs
        in
        loop ~f ~init components

      let to_any_component_list system =
        fold_left
          ~f:(fun (acc : 'ctx Component.any_component list) (_lbl, itm) ->
            itm :: acc)
          ~init:[]
          system
    end
  end

  module Component = struct
    include Types.Component
    module System = Types.System

    module type COMPONENT = sig
      type t

      type ctx

      type args

      val start : ctx -> args

      val stop : t -> unit Io.t
    end

    module type SIMPLE_COMPONENT = sig
      type t

      include
        COMPONENT
          with type t := t
           and type args := (t, [ `Msg of string ]) result Io.t
    end

    let fold_left ~f ~init dependencies =
      let rec loop
          : type ty args.
            f:('res -> 'ctx any_component -> 'res)
            -> init:'res
            -> ('ctx, args, ty) deps
            -> 'res
        =
       fun ~f ~init deps ->
        match deps with
        | [] ->
          init
        | x :: xs ->
          loop ~f ~init:(f init (AnyComponent x)) xs
      in
      loop ~f ~init dependencies

    let append
        : type ty a b.
          ('ctx, a) t -> ('ctx, b, ty) deps -> ('ctx, a -> b, ty) deps
      =
     fun c deps -> match deps with [] -> [ c ] | xs -> c :: xs

    let rec concat
        : type ty a b.
          ('ctx, a, ty) deps -> ('ctx, ty, b) deps -> ('ctx, a, b) deps
      =
     fun d1 d2 -> match d1 with [] -> d2 | x :: xs -> x :: concat xs d2

    let make
        : type ctx ty.
          start:(ctx -> (ty, [ `Msg of string ]) result Io.t)
          -> stop:(ty -> unit Io.t)
          -> (ctx, ty) t
      =
     fun ~start ~stop ->
      Component { start; stop; hkey = Hmap.Key.create (); dependencies = [] }

    let identity : type ctx ty. ty -> (ctx, ty) t =
     fun c ->
      let start _ctx = Io.Result.return c in
      let stop _c = Io.return () in
      make ~start ~stop

    let make_m
        : type ctx a.
          (module SIMPLE_COMPONENT with type t = a and type ctx = ctx)
          -> (ctx, a) t
      =
     fun (module C) ->
      Component
        { start = C.start
        ; stop = C.stop
        ; hkey = Hmap.Key.create ()
        ; dependencies = []
        }

    let using
        : type ctx ty args.
          start:(ctx -> args)
          -> stop:(ty -> unit Io.t)
          -> dependencies:(ctx, args, (ty, [ `Msg of string ]) result Io.t) deps
          -> (ctx, ty) t
      =
     fun ~start ~stop ~dependencies ->
      Component { start; stop; hkey = Hmap.Key.create (); dependencies }

    let using_m
        : type ctx ty args.
          (module COMPONENT
             with type t = ty
              and type args = args
              and type ctx = ctx)
          -> dependencies:(ctx, args, (ty, [ `Msg of string ]) result Io.t) deps
          -> (ctx, ty) t
      =
     fun (module C) ~dependencies ->
      Component
        { start = C.start
        ; stop = C.stop
        ; hkey = Hmap.Key.create ()
        ; dependencies
        }

    let of_system (System.System { system; _ }) = System system

    let rec equal : 'ctx any_component -> 'ctx any_component -> bool =
     fun (AnyComponent c1) (AnyComponent c2) ->
      match c1, c2 with
      | System _, Component _ | Component _, System _ ->
        false
      | Component { hkey = k1; _ }, Component { hkey = k2; _ } ->
        Hmap.Key.equal (Hmap.Key.hide_type k1) (Hmap.Key.hide_type k2)
      | System s1, System s2 ->
        List.for_all2
          (fun x y -> equal x y)
          (System.to_any_component_list s1)
          (System.to_any_component_list s2)
  end

  (** System *)

  module System = struct
    include Types.System

    (* Only here for switching the `started` / `stopped` phantom types. *)
    external cast : ('ctx, 'ty, _) t -> ('ctx, 'ty, _) t = "%identity"

    let rec lift_ignore : type ctx args. (ctx, args, unit) components -> args =
     fun components ->
      match components with _ :: xs -> fun _ -> lift_ignore xs | [] -> ()

    let make_reusable
        : type args ty.
          lift:args -> ('ctx, args, ty) components -> ('ctx, ty, [ `stopped ]) t
      =
     fun ~lift components ->
      System
        { system = { components; hkey = Hmap.Key.create (); lift }
        ; values = Hmap.empty
        }

    let make components =
      make_reusable ~lift:(lift_ignore components) components

    let rec safe_fold
        ~f ~init (sorted_components : 'ctx Component.any_component list)
      =
      match sorted_components with
      | [] ->
        Io.Result.return init
      | x :: xs ->
        let open Io.Result.Infix in
        f init x >>= fun acc -> safe_fold ~init:acc ~f xs

    (* This function assumes dependencies have been started. The usage of
     * `Hmap.get`, even though it throws, is considered safe given that we have
     * topologically sorted the component's dependencies. *)
    let rec start_component
        : type ty args.
          ('ctx, _, [ `stopped ]) t
          -> dependencies:
               ('ctx, args, (ty, [ `Msg of string ]) result Io.t) Component.deps
          -> f:args
          -> (ty, [ `Msg of string ]) result Io.t
      =
     fun (System { values; _ } as system) ~dependencies ~f ->
      let open Component in
      match dependencies with
      | [] ->
        f
      | Component { hkey; _ } :: xs ->
        let started_dep = Hmap.get hkey values in
        start_component system ~dependencies:xs ~f:(f started_dep)
      | System { hkey; _ } :: xs ->
        let lifted_system = Hmap.get hkey values in
        start_component system ~dependencies:xs ~f:(f lifted_system)

    let update_system ~f ~order (System { system; _ } as t) =
      let all_components = to_any_component_list system in
      try
        let ordered =
          Toposort.toposort
            ~order
            ~equal:Component.equal
            ~edges:(fun _graph (Component.AnyComponent c) ->
              match c with
              | Component.Component { dependencies; _ } ->
                Component.fold_left
                  ~f:(fun (acc : 'ctx Component.any_component list) itm ->
                    itm :: acc)
                  ~init:[]
                  dependencies
              | Component.System system' ->
                let components = to_any_component_list system' in
                List.fold_left
                  (fun (acc : 'ctx Component.any_component list) itm ->
                    itm :: acc)
                  []
                  components)
            all_components
        in
        safe_fold ~init:t ~f ordered
      with
      | Toposort.CycleFound ->
        Io.return (Error `Cycle_found)

    let rec lift_system
        : type ty args.
          ('ctx, _, _) t
          -> components:('ctx, args, ty) components
          -> f:args
          -> ty
      =
     fun (System { values; _ } as system) ~components ~f ->
      let open Component in
      match components with
      | [] ->
        f
      | (_lbl, Component { hkey; _ }) :: xs ->
        let lifted_arg = Hmap.get hkey values in
        lift_system system ~components:xs ~f:(f lifted_arg)
      | (_lbl, System { hkey; _ }) :: xs ->
        let lifted_arg = Hmap.get hkey values in
        lift_system system ~components:xs ~f:(f lifted_arg)

    let start ctx system =
      let open Io.Infix in
      let f (System ({ values; _ } as s) as system) (Component.AnyComponent c) =
        match c with
        | Component.Component { start; dependencies; hkey; _ } ->
          let f = start ctx in
          start_component system ~dependencies ~f >|= ( function
          | Ok started_component ->
            let values = Hmap.add hkey started_component values in
            Ok (System { s with values })
          | Error e ->
            Error (e :> [ `Cycle_found | `Msg of string ]) )
        | Component.System { components; hkey; lift; _ } ->
          (* A system is assumed to have all its components already started
           * because of topological sorting.
           *
           * For systems we need to do 2 things:
           *   1. Lift the system to a value;
           *   2. Pass that value to `f`, the component `resolver`. *)
          let f = lift in
          let lifted_system = lift_system system ~components ~f in
          let values = Hmap.add hkey lifted_system values in
          Io.Result.return (System { s with values })
      in
      Io.Result.map cast (update_system ~order:`Dependency ~f system)

    let stop system =
      let open Io.Result.Infix in
      update_system
        ~order:`Reverse
        ~f:(fun (System ({ values; _ } as s)) (Component.AnyComponent c) ->
          match c with
          | Component.Component { stop; hkey; _ } ->
            let open Io.Infix in
            let v = Hmap.get hkey values in
            stop v >|= fun () ->
            let values = Hmap.rem hkey values in
            Ok (System { s with values })
          | Component.System _ ->
            Io.Result.return (System s))
        system
      >|= cast

    let get (System { system = { components; lift; _ }; _ } as t) =
      lift_system t ~components ~f:lift
  end
end

module Sync : IO with type +'a t = 'a = struct
  type +'a t = 'a

  let return x = x

  let map f x = f x

  let bind x f = f x
end

include Make (Sync)
