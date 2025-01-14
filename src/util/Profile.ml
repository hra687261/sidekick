module type BACKEND = sig
  val get_ts : unit -> float

  val emit_duration_event :
    name:string ->
    start:float ->
    end_:float ->
    args:(string * string) list ->
    unit ->
    unit

  val emit_instant_event :
    name:string -> ts:float -> args:(string * string) list -> unit -> unit

  val emit_count_event : name:string -> ts:float -> (string * int) list -> unit
  val teardown : unit -> unit
end

type backend = (module BACKEND)
type probe = No_probe | Probe of { name: string; start: float }

let null_probe = No_probe

(* where to print events *)
let out_ : backend option ref = ref None

let[@inline] enabled () =
  match !out_ with
  | Some _ -> true
  | None -> false

let[@inline never] begin_with_ (module B : BACKEND) name : probe =
  Probe { name; start = B.get_ts () }

let[@inline] begin_ name : probe =
  match !out_ with
  | None -> No_probe
  | Some b -> begin_with_ b name

let[@inline] instant ?(args = []) name =
  match !out_ with
  | None -> ()
  | Some (module B) ->
    let now = B.get_ts () in
    B.emit_instant_event ~name ~ts:now ~args ()

let[@inline] count name cs =
  if cs <> [] then (
    match !out_ with
    | None -> ()
    | Some (module B) ->
      let now = B.get_ts () in
      B.emit_count_event ~name ~ts:now cs
  )

(* slow path *)
let[@inline never] exit_full_ (module B : BACKEND) ~args name start =
  let now = B.get_ts () in
  B.emit_duration_event ~name ~start ~end_:now ~args ()

let[@inline] exit_with_ ~args b pb =
  match pb with
  | No_probe -> ()
  | Probe { name; start } -> exit_full_ ~args b name start

let[@inline] exit ?(args = []) pb =
  match pb, !out_ with
  | Probe { name; start }, Some b -> exit_full_ ~args b name start
  | _ -> ()

let[@inline] with_ ?(args = []) name f =
  match !out_ with
  | None -> f ()
  | Some b ->
    let pb = begin_with_ b name in
    (try
       let x = f () in
       exit_with_ ~args b pb;
       x
     with e ->
       exit_with_ ~args b pb;
       raise e)

let[@inline] with1 ?(args = []) name f x =
  match !out_ with
  | None -> f x
  | Some b ->
    let pb = begin_with_ b name in
    (try
       let res = f x in
       exit_with_ ~args b pb;
       res
     with e ->
       exit_with_ ~args b pb;
       raise e)

let[@inline] with2 ?args name f x y = with_ ?args name (fun () -> f x y)

module Control = struct
  let setup b =
    assert (!out_ = None);
    out_ := b

  let teardown () =
    match !out_ with
    | None -> ()
    | Some (module B) ->
      out_ := None;
      B.teardown ()
end
