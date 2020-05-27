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

exception CycleFound

type order =
  [ `Dependency
  | `Reverse
  ]

(* Adapted from:
 * https://stackoverflow.com/questions/4653914/topological-sort-in-ocaml *)
let dfs ~equal graph ~edges visited start_node =
  let rec explore path visited node =
    if List.exists (fun node' -> equal node node') path then
      raise CycleFound
    else if List.exists (fun node' -> equal node node') visited then
      visited
    else
      let new_path = node :: path in
      let edges = edges graph node in
      let visited = List.fold_left (explore new_path) visited edges in
      node :: visited
  in
  explore [] visited start_node

let toposort ?(order = `Dependency) ~equal ~edges graph =
  let sorted =
    List.fold_left
      (fun visited node -> dfs ~equal ~edges graph visited node)
      []
      graph
  in
  (* `dfs` sorts in reverse by default (easier with `::`) *)
  match order with `Dependency -> List.rev sorted | `Reverse -> sorted
