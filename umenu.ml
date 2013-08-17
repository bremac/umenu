(* TODO: Handle closing file descriptors cleanly on errors *)

type history_entry = { count: int; command: string }

exception Parse_error of string

let history_path = "~/.umenu_history"
let history_lines = 200

let space_regexp = Str.regexp " "

let parse_entry s =
  match Str.bounded_split space_regexp s 2 with
    | [count; command] -> { count = int_of_string count; command = command }
    | _ -> raise (Parse_error s)

let format_entry e =
  Printf.sprintf "%d %s" e.count e.command

let compare_history_entries e1 e2 =
  compare (-e1.count, e1.command) (-e2.count, e2.command)

let read_history path line_count =
  let lines = Uutils.try_read_lines path in
  let entries = List.map parse_entry lines in
  let sorted_entries = List.sort compare_history_entries entries in
  Uutils.take line_count sorted_entries

let read_command dmenu_params entries =
  let options = List.map (fun e -> e.command) entries in
  let option_string = Uutils.join_lines options in
  match Uutils.exec_filter "dmenu" dmenu_params option_string with
    | Some command -> Some (String.trim command)
    | None -> None

let exec_command command =
  Unix.execvp "/bin/sh" [|"/bin/sh"; "-c"; "exec " ^ command|]

let update_history entries command =
  let update_entry e =
    if (e.command = command) then { e with count = e.count + 1 } else e
  in
  match List.filter (fun e -> e.command = command) entries with
    | [] -> { count = 1; command = command } :: entries
    | _ -> List.map update_entry entries

let save_history path entries =
  let lines = List.map format_entry entries in
  let basename = Filename.basename path in
  let dirname = Filename.dirname path in
  let temppath = Filename.temp_file ~temp_dir:dirname basename "" in
  Uutils.write_lines temppath lines;
  Unix.rename temppath path

let main () =
  let dmenu_params = List.tl (Array.to_list Sys.argv) in
  let history_path = Uutils.expand_path history_path in
  let entries = read_history history_path history_lines in
  match read_command dmenu_params entries with
    | Some command ->
        let updated_entries = update_history entries command in
        save_history history_path updated_entries;
        exec_command command
    | None -> ()

;; if !Sys.interactive then () else main ()
