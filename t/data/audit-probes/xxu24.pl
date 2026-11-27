our $x = 1; sub c { $x = 3; 2 } sub f1 { my ($p, $q) = @_; "$p$q" } print f1($x, c()), "\n";
