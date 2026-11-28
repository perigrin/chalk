our $x = 1; sub c { $x = 5; 2 } sub f { my ($p, $q) = @_; "$p$q" } print f($x, c()), "\n";
