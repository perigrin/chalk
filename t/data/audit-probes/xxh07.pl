sub f { my $q = pop; $q->(); my ($p) = @_; "$p" } my $x = 1; print f($x, sub { $x = 5 }), "\n";
