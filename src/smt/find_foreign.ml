open Sidekick_core

module type ACTIONS = sig
  val declare_need_th_combination : Term.t -> unit
  (** Declare that this term is a foreign variable in some other subterm. *)

  val add_lit_for_bool_term : ?default_pol:bool -> Term.t -> unit
  (** Add the (boolean) term to the SAT solver *)
end

type actions = (module ACTIONS)
type hook = actions -> is_sub:bool -> Term.t -> unit
type t = { seen: unit Term.Tbl.t; mutable hooks: hook list }

let create () : t = { hooks = []; seen = Term.Tbl.create 8 }
let add_hook self h = self.hooks <- h :: self.hooks

let traverse_term (self : t) ((module A) as acts : actions) (t : Term.t) : unit
    =
  let rec loop ~is_sub t =
    if (not (Term.is_a_type t)) && not (Term.Tbl.mem self.seen t) then (
      Term.Tbl.add self.seen t ();
      Log.debugf 10 (fun k -> k "(@[find-foreign-in@ %a@])" Term.pp t);

      (* boolean subterm: need a literal *)
      if Term.is_bool (Term.ty t) then A.add_lit_for_bool_term t;

      (* call hooks *)
      List.iter (fun (h : hook) -> h acts ~is_sub t) self.hooks;

      match Term.open_eq t with
      | Some (_, _) when not is_sub ->
        Term.iter_shallow t ~f:(fun _ u -> loop ~is_sub:false u)
      | _ -> Term.iter_shallow t ~f:(fun _ u -> loop ~is_sub:true u)
    )
  in
  loop ~is_sub:false t
