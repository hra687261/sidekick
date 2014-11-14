
module S = Smt.Make(struct end)

exception Out_of_time
exception Out_of_space

(* IO wrappers *)
(* Types for input/output languages *)
type sat_input =
  | Auto
  | Smtlib

type sat_output =
  | Standard (* Only output problem status *)
  | Dot

let input = ref Auto
let output = ref Standard

let input_list = [
  "auto", Auto;
  "smtlib", Smtlib;
]
let output_list = [
  "dot", Dot;
]

let error_msg opt arg l =
  Format.fprintf Format.str_formatter "'%s' is not a valid argument for '%s', valid arguments are : %a"
    arg opt (fun fmt -> List.iter (fun (s, _) -> Format.fprintf fmt "%s, " s)) l;
  Format.flush_str_formatter ()

let set_io opt arg flag l =
  try
    flag := List.assoc arg l
  with Not_found ->
    invalid_arg (error_msg opt arg l)

let set_input s = set_io "Input" s input input_list
let set_output s = set_io "Output" s output output_list

(* Input Parsing *)
let rec rev_flat_map f acc = function
  | [] -> acc
  | a :: r -> rev_flat_map f (List.rev_append (f a) acc) r

let format_of_filename s =
  let last n =
    try String.sub s (String.length s - n) n
    with Invalid_argument _ -> ""
  in
  if last 5 = ".smt2" then
    Smtlib
  else (* Default choice *)
    Smtlib

let parse_with_input file = function
  | Auto -> assert false
  | Smtlib -> rev_flat_map Smt.Tseitin.make_cnf [] (Smtlib.parse file)

let parse_input file =
  parse_with_input file (match !input with
      | Auto -> format_of_filename file
      | f -> f)

(* Printing wrappers *)
let std = Format.std_formatter

let print format = match !output with
  | Standard -> Format.fprintf std "%( fmt %)@." format
  | Dot -> Format.fprintf std "/* %( fmt %) */@." format

let print_proof proof = match !output with
  | Standard -> ()
  | Dot -> S.print_proof std proof

let rec print_cl fmt = function
  | [] -> Format.fprintf fmt "[]"
  | [a] -> Smt.Fsmt.print fmt a
  | a :: ((_ :: _) as r) -> Format.fprintf fmt "%a ∨ %a" Smt.Fsmt.print a print_cl r

let print_lcl l =
  List.iter (fun c -> Format.fprintf std "%a@\n" print_cl c) l

let print_lclause l =
  List.iter (fun c -> Format.fprintf std "%a@\n" S.print_clause c) l

(* Arguments parsing *)
let file = ref ""
let p_cnf = ref false
let p_proof_check = ref false
let p_proof_print = ref false
let p_unsat_core = ref false
let time_limit = ref 300.
let size_limit = ref 1000_000_000.

let int_arg r arg =
  let l = String.length arg in
  let multiplier m =
    let arg1 = String.sub arg 0 (l-1) in
    r := m *. (float_of_string arg1)
  in
  if l = 0 then raise (Arg.Bad "bad numeric argument")
  else
    try
      match arg.[l-1] with
      | 'k' -> multiplier 1e3
      | 'M' -> multiplier 1e6
      | 'G' -> multiplier 1e9
      | 'T' -> multiplier 1e12
      | 's' -> multiplier 1.
      | 'm' -> multiplier 60.
      | 'h' -> multiplier 3600.
      | 'd' -> multiplier 86400.
      | '0'..'9' -> r := float_of_string arg
      | _ -> raise (Arg.Bad "bad numeric argument")
    with Failure "float_of_string" -> raise (Arg.Bad "bad numeric argument")

let setup_gc_stat () =
  at_exit (fun () ->
      Gc.print_stat stdout;
    )

let input_file = fun s -> file := s

let usage = "Usage : main [options] <file>"
let argspec = Arg.align [
    "-bt", Arg.Unit (fun () -> Printexc.record_backtrace true),
    " Enable stack traces";
    "-cnf", Arg.Set p_cnf,
    " Prints the cnf used.";
    "-check", Arg.Set p_proof_check,
    " Build, check and print the proof (if output is set), if unsat";
    "-gc", Arg.Unit setup_gc_stat,
    " Outputs statistics about the GC";
    "-i", Arg.String set_input,
    " Sets the input format (default auto)";
    "-o", Arg.String set_output,
    " Sets the output format (default none)";
    "-size", Arg.String (int_arg size_limit),
    "<s>[kMGT] Sets the size limit for the sat solver";
    "-time", Arg.String (int_arg time_limit),
    "<t>[smhd] Sets the time limit for the sat solver";
    "-u", Arg.Set p_unsat_core,
    " Prints the unsat-core explanation of the unsat proof (if used with -check)";
    "-v", Arg.Int (fun i -> Log.set_debug i),
    "<lvl> Sets the debug verbose level";
  ]

(* Limits alarm *)
let check () =
  let t = Sys.time () in
  let heap_size = (Gc.quick_stat ()).Gc.heap_words in
  let s = float heap_size *. float Sys.word_size /. 8. in
  if t > !time_limit then
    raise Out_of_time
  else if s > !size_limit then
    raise Out_of_space

(* Entry file parsing *)
let get_cnf () = parse_input !file

let main () =
  (* Administrative duties *)
  Arg.parse argspec input_file usage;
  if !file = "" then begin
    Arg.usage argspec usage;
    exit 2
  end;
  ignore(Gc.create_alarm check);

  (* Interesting stuff happening *)
  let cnf = get_cnf () in
  if !p_cnf then
    print_lcl cnf;
  S.assume cnf;
  match S.solve () with
  | S.Sat ->
    print "Sat";
  | S.Unsat ->
    print "Unsat";
    if !p_proof_check then begin
      let p = S.get_proof () in
      print_proof p;
      if !p_unsat_core then
        print_lclause (S.unsat_core p)
    end

let () =
  try
    main ()
  with
  | Out_of_time ->
    print "Time limit exceeded";
    exit 2
  | Out_of_space ->
    print "Size limit exceeded";
    exit 3