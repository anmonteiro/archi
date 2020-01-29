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

  module Component = struct
    type (_, _, _) deps =
      | [] : ('ctx, 'a, 'a) deps
      | ( :: ) : ('ctx, 'a) t * ('ctx, 'b, 'c) deps -> ('ctx, 'b, 'a -> 'c) deps

    and (_, _) t =
      | Component :
          { dependencies : ('ctx, ('a, string) result Io.t, 'args) deps
          ; start : 'ctx -> 'args
          ; stop : 'a -> unit Io.t
          ; hkey : 'a Hmap.key
          ; name : string option
          }
          -> ('ctx, 'a) t

    type _ any_component = AnyComponent : ('ctx, _) t -> 'ctx any_component

    module type COMPONENT = sig
      type t

      type ctx

      type args

      val name : string

      val start : ctx -> args

      val stop : t -> unit Io.t
    end

    module type SIMPLE_COMPONENT = sig
      type t

      include
        COMPONENT with type t := t and type args := (t, string) result Io.t
    end

    let fold_left ~f ~init dependencies =
      let rec loop
          : type a args.
            f:('res -> 'ctx any_component -> 'res)
            -> init:'res
            -> ('ctx, a, args) deps
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
        : type a b c. ('ctx, c) t -> ('ctx, a, b) deps -> ('ctx, a, c -> b) deps
      =
     fun c deps -> match deps with [] -> [ c ] | xs -> c :: xs

    let rec concat
        : type a b c.
          ('ctx, b, c) deps -> ('ctx, a, b) deps -> ('ctx, a, c) deps
      =
     fun d1 d2 -> match d1 with [] -> d2 | x :: xs -> x :: concat xs d2

    let make ?name ~start ~stop =
      Component
        { start; stop; hkey = Hmap.Key.create (); name; dependencies = [] }

    let make_m
        : type ctx a.
          (module SIMPLE_COMPONENT with type t = a and type ctx = ctx)
          -> (ctx, a) t
      =
     fun (module C) ->
      Component
        { start = C.start
        ; stop = C.stop
        ; name = Some C.name
        ; hkey = Hmap.Key.create ()
        ; dependencies = []
        }

    let using ?name ~start ~stop ~dependencies =
      Component { start; stop; name; hkey = Hmap.Key.create (); dependencies }

    let using_m
        : type ctx a args.
          (module COMPONENT
             with type t = a
              and type args = args
              and type ctx = ctx)
          -> dependencies:(ctx, (a, string) result Io.t, args) deps
          -> (ctx, a) t
      =
     fun (module C) ~dependencies ->
      Component
        { start = C.start
        ; stop = C.stop
        ; name = Some C.name
        ; hkey = Hmap.Key.create ()
        ; dependencies
        }
  end

  (** System *)

  module System = struct
    type (_, _, _) components =
      | [] : ('ctx, 'a, 'a) components
      | ( :: ) :
          (string * ('ctx, 'a) Component.t) * ('ctx, 'b, 'c) components
          -> ('ctx, 'b, 'a -> 'c) components

    type (_, _) t =
      | System :
          { components : ('ctx, 'a, 'args) components
          ; mutable values : Hmap.t
          }
          -> ('ctx, 'state) t

    let fold_left ~f ~init (System { components; _ }) =
      let rec loop
          : type a args.
            f:('res -> string * 'ctx Component.any_component -> 'res)
            -> init:'res
            -> ('ctx, a, args) components
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

    (* Only here for switching the `started` / `stopped` phantom types. *)
    let cast (System { components; values }) = System { components; values }

    let make components = System { components; values = Hmap.empty }

    let rec start_component
        : type a args.
          ('ctx, [ `stopped ]) t
          -> dependencies:('ctx, (a, string) result Io.t, args) Component.deps
          -> f:args
          -> (a, string) result Io.t
      =
     fun (System { values; _ } as system) ~dependencies ~f ->
      let open Component in
      match dependencies with
      | [] ->
        f
      | Component { hkey; _ } :: xs ->
        let started_dep = Hmap.get hkey values in
        start_component system ~dependencies:xs ~f:(f started_dep)

    let rec safe_fold
        ~f ~init (sorted_components : 'ctx Component.any_component list)
      =
      match sorted_components with
      | [] ->
        Io.Result.return init
      | x :: xs ->
        let open Io.Result.Infix in
        f init x >>= fun acc -> safe_fold ~init:acc ~f xs

    let update_system ~order system ~f =
      let all_components =
        fold_left
          ~f:(fun (acc : 'ctx Component.any_component list) (_lbl, itm) ->
            itm :: acc)
          ~init:[]
          system
      in
      let ordered =
        Toposort.toposort
          ~order
          ~edges:
            (fun _graph
                 (Component.AnyComponent
                   (Component.Component { dependencies; _ })) ->
            Component.fold_left
              ~f:(fun (acc : 'ctx Component.any_component list) itm ->
                itm :: acc)
              ~init:[]
              dependencies)
          all_components
      in
      safe_fold ~init:system ~f ordered

    let start ctx system =
      let open Io.Result.Infix in
      update_system
        ~order:`Dependency
        ~f:
          (fun (System { values; components; _ } as system)
               (Component.AnyComponent
                 (Component.Component { start; dependencies; hkey; _ })) ->
          let f = start ctx in
          start_component system ~dependencies ~f >|= fun started_component ->
          let values = Hmap.add hkey started_component values in
          System { values; components })
        system
      >|= cast

    let stop system =
      let open Io.Result.Infix in
      update_system
        ~order:`Reverse
        ~f:
          (fun (System { values; components; _ })
               (Component.AnyComponent (Component.Component { stop; hkey; _ })) ->
          let open Io.Infix in
          let v = Hmap.get hkey values in
          stop v >|= fun () ->
          let values = Hmap.rem hkey values in
          Ok (System { values; components }))
        system
      >|= cast
  end
end

module Sync : IO with type +'a t = 'a = struct
  type +'a t = 'a

  let return x = x

  let map f x = f x

  let bind x f = f x
end

include Make (Sync)
