umenu
=====

`umenu` is a history-driven dmenu wrapper script. Instead of prompting the user
to select from all of the binaries installed on their system, it lets users select
from the list of all commands they have executed previously through umenu. Commands
may have arguments, and are sorted based on how many times they have been used.


Compiling
---------

To compile umenu, you will need a recent version of ocaml, along with
[findlib](http://projects.camlcity.org/projects/findlib.html). To build a native
binary, execute `./build.sh`.
