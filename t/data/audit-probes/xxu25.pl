our $x = 1; sub c { $x = 3; 2 } sub f1 { my $p = shift; "$p" } print f1($x, c()), "\n";
