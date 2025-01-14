(*
MSAT is free software, using the Apache license, see file LICENSE
Copyright 2014 Guillaume Bury
Copyright 2014 Simon Cruanes
*)

module E = CCResult
module Fmt = CCFormat
module Term = Sidekick_base.Term
module Config = Sidekick_base.Config
module Solver = Sidekick_smtlib.Solver
module Driver = Sidekick_smtlib.Driver
module Proof = Sidekick_proof
open E.Infix

type 'a or_error = ('a, string) E.t

exception Out_of_time
exception Out_of_space

let file = ref ""
let p_cnf = ref false
let p_proof = ref false
let p_model = ref false
let check = ref false
let time_limit = ref 300.
let mem_limit = ref 1_000_000_000.
let p_stat = ref false
let p_gc_stat = ref false
let p_progress = ref false
let enable_trace = ref false
let proof_file = ref ""
let trace_file = ref ""

(* Arguments parsing *)
let int_arg r arg =
  let l = String.length arg in
  let multiplier m =
    let arg1 = String.sub arg 0 (l - 1) in
    r := m *. float_of_string arg1
  in
  if l = 0 then
    raise (Arg.Bad "bad numeric argument")
  else (
    try
      match arg.[l - 1] with
      | 'k' -> multiplier 1e3
      | 'M' -> multiplier 1e6
      | 'G' -> multiplier 1e9
      | 'T' -> multiplier 1e12
      | 's' -> multiplier 1.
      | 'm' -> multiplier 60.
      | 'h' -> multiplier 3600.
      | 'd' -> multiplier 86400.
      | '0' .. '9' -> r := float_of_string arg
      | _ -> raise (Arg.Bad "bad numeric argument")
    with Failure _ -> raise (Arg.Bad "bad numeric argument")
  )

let input_file s = file := s
let usage = "Usage : main [options] <file>"
let version = "%%version%%"
let config = ref Config.empty

let argspec =
  Arg.align
    [
      ( "--bt",
        Arg.Unit (fun () -> Printexc.record_backtrace true),
        " enable stack traces" );
      "--cnf", Arg.Set p_cnf, " prints the cnf used.";
      ( "--check",
        Arg.Set check,
        " build, check and print the proof (if output is set), if unsat" );
      "--no-check", Arg.Clear check, " inverse of -check";
      "--stat", Arg.Set p_stat, " print statistics";
      "--proof", Arg.Set p_proof, " print proof";
      "--no-proof", Arg.Clear p_proof, " do not print proof";
      "-o", Arg.Set_string proof_file, " file into which to output a proof";
      "--model", Arg.Set p_model, " print model";
      "--trace", Arg.Set enable_trace, " enable tracing";
      "--no-trace", Arg.Clear enable_trace, " disable tracing";
      ( "--trace-file",
        Arg.Set_string trace_file,
        " store trace in given file (no cleanup)" );
      "--no-model", Arg.Clear p_model, " do not print model";
      ( "--bool",
        Arg.Symbol
          ( [ "dyn"; "static" ],
            function
            | "dyn" ->
              config := Config.add Sidekick_base.k_th_bool_config `Dyn !config
            | "static" ->
              config :=
                Config.add Sidekick_base.k_th_bool_config `Static !config
            | _s -> failwith "unknown" ),
        " configure bool theory" );
      "--gc-stat", Arg.Set p_gc_stat, " outputs statistics about the GC";
      "-p", Arg.Set p_progress, " print progress bar";
      "--no-p", Arg.Clear p_progress, " no progress bar";
      ( "--memory",
        Arg.String (int_arg mem_limit),
        " <s>[kMGT] sets the memory limit for the sat solver" );
      ( "--time",
        Arg.String (int_arg time_limit),
        " <t>[smhd] sets the time limit for the sat solver" );
      "-t", Arg.String (int_arg time_limit), " short for --time";
      ( "--version",
        Arg.Unit
          (fun () ->
            Printf.printf "version: %s\n%!" version;
            exit 0),
        " show version and exit" );
      "-d", Arg.Int Log.set_debug, "<lvl> sets the debug verbose level";
      "--debug", Arg.Int Log.set_debug, "<lvl> sets the debug verbose level";
    ]
  |> List.sort compare

(* Limits alarm *)
let check_limits () =
  let t = Sys.time () in
  let heap_size = (Gc.quick_stat ()).Gc.heap_words in
  let s = float heap_size *. float Sys.word_size /. 8. in
  if t > !time_limit then
    raise Out_of_time
  else if s > !mem_limit then
    raise Out_of_space

(* call [k] with the name of a temporary proof file, and cleanup if necessary *)
let run_with_tmp_file ~enable_proof k =
  (* TODO: use memory writer if [!proof_store_memory] *)
  if enable_proof then
    if !trace_file <> "" then (
      let file = !trace_file in
      k file
    ) else
      CCIO.File.with_temp ~temp_dir:"." ~prefix:".sidekick-proof" ~suffix:".dat"
        k
  else
    k ""

let mk_smt_tracer ~trace_file () =
  if !enable_trace || trace_file <> "" then (
    Log.debugf 1 (fun k -> k "(@[emit-trace-into@ %S@])" trace_file);
    let oc = open_out_bin trace_file in
    Sidekick_smt_solver.Tracer.make
      ~sink:(Sidekick_trace.Sink.of_out_channel_using_bencode oc)
      ()
  ) else
    Sidekick_smt_solver.Tracer.dummy

let mk_sat_tracer () : Sidekick_sat.Tracer.t =
  if !trace_file = "" then
    Sidekick_sat.Tracer.dummy
  else (
    let oc = open_out_bin !trace_file in
    let sink = Sidekick_trace.Sink.of_out_channel_using_bencode oc in
    Pure_sat_solver.tracer ~sink ()
  )

let main_smt ~config () : _ result =
  let tst = Term.Store.create ~size:4_096 () in

  let enable_proof = !check || !p_proof || !proof_file <> "" in
  Log.debugf 1 (fun k -> k "(@[proof-enable@ %B@])" enable_proof);

  run_with_tmp_file ~enable_proof @@ fun trace_file ->
  Log.debugf 1 (fun k -> k "(@[trace_file@ %S@])" trace_file);

  (* FIXME
     let config =
       if enable_proof_ then
         Proof.Config.default |> Proof.Config.enable true
         |> Proof.Config.store_on_disk_at temp_proof_file
       else
         Proof.Config.empty
     in

     (* main proof object *)
     let proof = Proof.create ~config () in
  *)
  let tracer = mk_smt_tracer ~trace_file () in
  Proof.Tracer.enable tracer enable_proof;

  let solver =
    (* TODO: probes, to load only required theories *)
    let theories =
      let th_bool = Driver.th_bool config in
      Log.debugf 1 (fun k ->
          k "(@[main.th-bool.pick@ %S@])"
            (Sidekick_smt_solver.Theory.name th_bool));
      [ th_bool; Driver.th_ty_unin; Driver.th_data; Driver.th_lra ]
    in
    Solver.Smt_solver.Solver.create_default ~tracer ~theories tst ()
  in

  let finally () =
    if !p_stat then
      Format.printf "%a@." Solver.Smt_solver.Solver.pp_stats solver
  in
  CCFun.protect ~finally @@ fun () ->
  (* FIXME: emit an actual proof *)
  let proof_file =
    if !proof_file = "" then
      None
    else
      Some !proof_file
  in
  if !check then
    (* might have to check conflicts *)
    Solver.Smt_solver.Solver.add_theory solver Sidekick_smtlib.Check_cc.theory;

  let parse_res =
    let@ () = Profile.with_ "parse" ~args:[ "file", !file ] in
    Sidekick_smtlib.parse tst !file
  in

  parse_res >>= fun input ->
  let driver =
    let asolver = Solver.Smt_solver.Solver.as_asolver solver in
    Driver.create ~pp_cnf:!p_cnf ~time:!time_limit ~memory:!mem_limit
      ~pp_model:!p_model ?proof_file ~check:!check ~progress:!p_progress asolver
  in

  (* process statements *)
  let res =
    try E.fold_l (fun () stmt -> Driver.process_stmt driver stmt) () input
    with Exit -> E.return ()
  in
  res

let main_cnf () : _ result =
  let module S = Pure_sat_solver in
  let stat = Stat.create () in

  let finally () = if !p_stat then Fmt.printf "%a@." Stat.pp stat in
  CCFun.protect ~finally @@ fun () ->
  let enable_proof_ = !check || !p_proof || !proof_file <> "" in

  let tst = Term.Store.create () in
  let tracer = mk_sat_tracer () in
  Proof.Tracer.enable tracer enable_proof_;
  let solver = S.SAT.create_pure_sat ~size:`Big ~tracer ~stat () in

  S.Dimacs.parse_file solver tst !file >>= fun () ->
  let r = S.solve ~check:!check solver in
  (* FIXME: if in memory proof and !proof_file<>"",
     then dump proof into file now *)
  r

let main () =
  Sys.catch_break true;

  (* instrumentation and tracing *)
  Sidekick_tef.with_setup @@ fun () ->
  Sidekick_memtrace.trace_if_requested ~context:"sidekick" ();

  CCFormat.set_color_default true;
  (* Administrative duties *)
  Arg.parse argspec input_file usage;
  if !file = "" then (
    Arg.usage argspec usage;
    exit 2
  );
  let al = Gc.create_alarm check_limits in
  Util.setup_gc ();
  let is_cnf = Filename.check_suffix !file ".cnf" in

  let finally () =
    if !p_gc_stat then Printf.printf "(gc_stats\n%t)\n" Gc.print_stat
  in
  CCFun.protect ~finally @@ fun () ->
  let res =
    if is_cnf then
      main_cnf ()
    else
      main_smt ~config:!config ()
  in
  Gc.delete_alarm al;
  res

let () =
  match main () with
  | E.Ok () -> ()
  | E.Error msg ->
    Format.printf "@{<Red>Error@}: %s@." msg;
    exit 1
  | exception e ->
    let b = Printexc.get_backtrace () in
    let exit_ n =
      if Printexc.backtrace_status () then
        Format.fprintf Format.std_formatter "%s@." b;
      CCShims_.Stdlib.exit n
    in
    (match e with
    | Error.Error msg ->
      Format.printf "@{<Red>Error@}: %s@." msg;
      ignore @@ exit_ 1
    | Out_of_time ->
      Format.printf "Timeout@.";
      exit_ 2
    | Out_of_space ->
      Format.printf "Spaceout@.";
      exit_ 3
    | Invalid_argument e ->
      Format.printf "invalid argument:\n%s@." e;
      exit_ 127
    | Sys.Break ->
      Printf.printf "interrupted.\n%!";
      exit_ 1
    | _ -> raise e)
