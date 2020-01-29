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

module type IO = sig
  type +'a t

  val return : 'a -> 'a t

  val map : ('a -> 'b) -> 'a t -> 'b t

  val bind : 'a t -> ('a -> 'b t) -> 'b t
end

module type S = sig
  module Io : IO

  module Component : sig
    type ('ctx, 'a) t

    type (_, _, _) deps =
      | [] : ('ctx, 'a, 'a) deps
      | ( :: ) : ('ctx, 'a) t * ('ctx, 'b, 'c) deps -> ('ctx, 'b, 'a -> 'c) deps

    val append
      :  ('ctx, 'c) t
      -> ('ctx, 'a, 'b) deps
      -> ('ctx, 'a, 'c -> 'b) deps

    val concat
      :  ('ctx, 'b, 'c) deps
      -> ('ctx, 'a, 'b) deps
      -> ('ctx, 'a, 'c) deps

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

    (** Creating components *)

    val make
      :  ?name:string
      -> start:('ctx -> ('a, string) result Io.t)
      -> stop:('a -> unit Io.t)
      -> ('ctx, 'a) t

    val make_m
      :  (module SIMPLE_COMPONENT with type t = 'a and type ctx = 'ctx)
      -> ('ctx, 'a) t

    val using
      :  ?name:string
      -> start:('ctx -> 'args)
      -> stop:('a -> unit Io.t)
      -> dependencies:('ctx, ('a, string) result Io.t, 'args) deps
      -> ('ctx, 'a) t

    val using_m
      :  (module COMPONENT
            with type t = 'a
             and type args = 'args
             and type ctx = 'ctx)
      -> dependencies:('ctx, ('a, string) result Io.t, 'args) deps
      -> ('ctx, 'a) t
  end

  (** Systems *)

  module System : sig
    type (_, _, _) components =
      | [] : ('ctx, 'a, 'a) components
      | ( :: ) :
          (string * ('ctx, 'a) Component.t) * ('ctx, 'b, 'c) components
          -> ('ctx, 'b, 'a -> 'c) components

    type ('ctx, _) t

    val make : ('ctx, 'a, 'args) components -> ('ctx, [ `stopped ]) t

    val start
      :  'ctx
      -> ('ctx, [ `stopped ]) t
      -> (('ctx, [ `started ]) t, string) result Io.t

    val stop
      :  ('ctx, [ `started ]) t
      -> (('ctx, [ `stopped ]) t, string) result Io.t
  end
end
