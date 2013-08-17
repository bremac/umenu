(* Utilties for list manipulation and I/O *)

let rec take n xs =
  match n, xs with
    | 0, xs -> []
    | n, [] -> []
    | n, x::xs -> x :: take (n-1) xs

let home_path_regexp = Str.regexp "~"
let home_directory = try Sys.getenv "HOME" with _ -> "~"

let expand_path s =
  Str.global_replace home_path_regexp home_directory s

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
