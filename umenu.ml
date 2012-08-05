open Core.Std;;
module Shell = Core_extended.Shell;;

type history_entry = { count: int; command: string };;

exception ParseError of string;;

let history_path = "~/.local/umenu";;
let history_lines = 200;;

let space_regexp = Str.regexp " ";;
let home_path_regexp = Str.regexp "~";;
let home_directory = Option.value (Sys.getenv "HOME") ~default:"~";;

let expand_path s =
  Str.global_replace home_path_regexp home_directory s;;

let try_read_lines path =
  if Sys.file_exists_exn path then
    In_channel.read_lines path
  else [];;

let exec_command command =
  Unix.execvp ~prog:"/bin/sh" ~args:[|"/bin/sh"; "-c"; "exec " ^ command|];;

let parse_entry s =
  match Str.bounded_split space_regexp s 2 with
    | [count; command] -> { count = int_of_string count; command = command }
    | _ -> raise (ParseError s);;

let format_entry e =
  Printf.sprintf "%d %s" e.count e.command;;

let compare_history_entries a b = compare b a;;

let read_history path line_count = 
  let lines = try_read_lines path in
  let entries = List.map lines parse_entry in
  let sorted_entries = List.sort ~cmp:compare_history_entries entries in
  List.take sorted_entries line_count;;

let read_command dmenu_params entries = 
  let options = List.map entries (fun e -> e.command) in
  let option_string = String.concat ~sep:"\n" options in
  try
    let command = Shell.run_full "dmenu" ~input:option_string dmenu_params in
    Some (String.rstrip command)
  with Shell.Process.Failed _ ->
    None;;

let update_history entries command =
  let update_entry e = 
    if (e.command = command) then { e with count = e.count + 1 } else e
  in
  match List.findi entries ~f:(fun _ e -> e.command = command) with
    | Some _ -> List.map entries update_entry
    | None -> { count = 1; command = command } :: entries;;

let save_history path entries =
  let lines = List.map entries format_entry in
  let temppath = Filename.temp_file "umenu" "" in
  Out_channel.write_lines temppath lines;
  Shell.mv temppath path;;

let main () =
  let dmenu_params = Array.to_list (Array.slice Sys.argv 1 0) in
  let history_path = expand_path history_path in
  let entries = read_history history_path history_lines in
  match read_command dmenu_params entries with
    | Some command ->
        let updated_entries = update_history entries command in
        save_history history_path updated_entries;
        exec_command command
    | None -> ();;

if !Sys.interactive then () else main ();;
