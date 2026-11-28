our $x = 1; sub al { $_[0] = 5 } { local $x = 2; al($x); print $x } print "$x\n";
