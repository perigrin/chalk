sub f { my ($p,$q) = @_; $q->(); $p } my $x = 1; print f($x, sub { $x = 5 }), $x, "\n";
