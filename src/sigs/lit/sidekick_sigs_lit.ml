(** Literals

    Literals are a pair of a boolean-sorted term, and a sign.
    Positive literals are the same as their term, and negative literals
    are the negation of their term.

    The SAT solver deals only in literals and clauses (sets of literals).
    Everything else belongs in the SMT solver. *)

module type TERM = Sidekick_sigs_term.S

module type S = sig
  module T : TERM
  (** Literals depend on terms *)

  type t
  (** A literal *)

  include Sidekick_sigs.EQ_HASH_PRINT with type t := t

  val term : t -> T.Term.t
  (** Get the (positive) term *)

  val sign : t -> bool
  (** Get the sign. A negated literal has sign [false]. *)

  val neg : t -> t
  (** Take negation of literal. [sign (neg lit) = not (sign lit)]. *)

  val abs : t -> t
  (** [abs lit] is like [lit] but always positive, i.e. [sign (abs lit) = true] *)

  val signed_term : t -> T.Term.t * bool
  (** Return the atom and the sign *)

  val atom : ?sign:bool -> T.Term.store -> T.Term.t -> t
  (** [atom store t] makes a literal out of a term, possibly normalizing
      its sign in the process.
      @param sign if provided, and [sign=false], negate the resulting lit. *)

  val norm_sign : t -> t * bool
  (** [norm_sign (+t)] is [+t, true],
      and [norm_sign (-t)] is [+t, false].
      In both cases the term is positive, and the boolean reflects the initial sign. *)
end
