package P; our $x = 1; package main; { local $P::x = 2; print $P::x } print "$P::x\n";
