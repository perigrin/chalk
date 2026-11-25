our $x=1; package Q; sub w { $main::x=2 } package main; my $o=$x; Q::w(); print "$o$x\n";
