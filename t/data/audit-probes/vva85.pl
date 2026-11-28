our $x = 1; { local $main::x = 2; print $x } print "$x\n";
