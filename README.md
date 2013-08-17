umenu
=====

`umenu` is a history-driven dmenu wrapper script. It is intended to be used as an
alternative to `dmenu_run`. Instead of asking the user to select from all of the
binaries installed on their system, it lets users select from the list of all
commands they have executed previously through umenu. Commands are sorted so
that the most frequently-used commands come first in the list &ndash; the more
frequently you run a command, the fewer characters you need to type to select it
from the menu. Commands are executed by `/bin/sh`, so you can use shell features
like `~` or variable interpolation.


Compiling
---------

To compile umenu, you will need a recent version of ocaml, along with
[findlib](http://projects.camlcity.org/projects/findlib.html). Execute `./build.sh`.
to build a native binary in `_build/umenu.native`.


Running
-------

Like `dmenu_run`, umenu passes all command-line arguments through to dmenu verbatim.
See the dmenu man page for more information.


History file format
-------------------

From time to time, you may want to edit the umenu history file. The history file
lives in `~/.local/umenu` by default. The file format is line-oriented: each line
represents a command that has been executed. Each line contains a number, followed
by a space and then the command. The order of commands in the file is not important
&ndash; commands will be sorted before they are presented to the user.

In the following example, `chromium` has been run 864 times, while `~/bin/pharo`
has only been run 19 times:

    864 chromium
    404 wicd-client -n
    199 emacs
    55 idea.sh
    19 ~/bin/pharo
