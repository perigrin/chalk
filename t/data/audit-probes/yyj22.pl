package P; our $v = 1; package main; { no strict; print $v, $P::v, defined $main::v ? "d" : "u", "\n"; }
