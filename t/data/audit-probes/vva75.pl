our $x = 1; { local $x = 2; goto_end() } sub goto_end { print $x } print "$x\n";
