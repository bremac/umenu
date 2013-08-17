(* TODO: Handle closing file descriptors cleanly on errors *)

type history_entry = { count: int; command: string }

exception Parse_error of string

let history_path = "~/.umenu_history"
let history_lines = 200

let space_regexp = Str.regexp " "
let home_path_regexp = Str.regexp "~"
let home_directory = try Sys.getenv "HOME" with _ -> "~"

let expand_path s =
  Str.global_replace home_path_regexp home_directory s

let rec take n xs =
  match n, xs with
    | 0, xs -> []
    | n, [] -> []
    | n, x::xs -> x :: take (n-1) xs

let read_lines path =
  let lines = ref [] in
  let chan = open_in path in
  try
    while true; do
      lines := input_line chan :: !lines
    done; []
  with End_of_file ->
    close_in chan;
    List.rev !lines

let join_lines lines =
  String.concat "\n" (lines @ [""])

let write_lines path lines =
  let chan = open_out path in
  output_string chan (join_lines lines);
  close_out chan

let try_read_lines path =
  if Sys.file_exists path then
    read_lines path
  else []

let exec_command command =
  Unix.execvp "/bin/sh" [|"/bin/sh"; "-c"; "exec " ^ command|]

let spawn prog args =
  let params = (Array.of_list (prog :: args)) in
  let child_in, parent_out = Unix.pipe () in
  let parent_in, child_out = Unix.pipe () in
  match Unix.fork () with
    | 0 ->
        Unix.close parent_in;
        Unix.close parent_out;
        Unix.dup2 child_in Unix.stdin;
        Unix.dup2 child_out Unix.stdout;
        Unix.close child_in;
        Unix.close child_out;
        Unix.execvp prog params
    | pid ->
        Unix.close child_in;
        Unix.close child_out;
        pid, parent_in, parent_out

let exec_filter prog args input =
  let pid, child_stdout, child_stdin = spawn prog args in
  let input_chan = Unix.out_channel_of_descr child_stdin in
  output_string input_chan input;
  close_out input_chan;

  let output_chan = Unix.in_channel_of_descr child_stdout in
  let output = try input_line output_chan with _ -> "" in
  let result =
    match Unix.waitpid [] pid with
      | _, Unix.WEXITED 0 -> Some output
      | _ -> None
  in
  close_in output_chan;
  result

let parse_entry s =
  match Str.bounded_split space_regexp s 2 with
    | [count; command] -> { count = int_of_string count; command = command }
    | _ -> raise (Parse_error s)

let format_entry e =
  Printf.sprintf "%d %s" e.count e.command

let compare_history_entries e1 e2 =
  compare (-e1.count, e1.command) (-e2.count, e2.command)

let read_history path line_count = 
  let lines = try_read_lines path in
  let entries = List.map parse_entry lines in
  let sorted_entries = List.sort compare_history_entries entries in
  take line_count sorted_entries

let read_command dmenu_params entries = 
  let options = List.map (fun e -> e.command) entries in
  let option_string = join_lines options in
  match exec_filter "dmenu" dmenu_params option_string with
    | Some command -> Some (String.trim command)
    | None -> None

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
  write_lines temppath lines;
  Unix.rename temppath path

let main () =
  let dmenu_params = List.tl (Array.to_list Sys.argv) in
  let history_path = expand_path history_path in
  let entries = read_history history_path history_lines in
  match read_command dmenu_params entries with
    | Some command ->
        let updated_entries = update_history entries command in
        save_history history_path updated_entries;
        exec_command command
    | None -> ()

;; if !Sys.interactive then () else main ()
