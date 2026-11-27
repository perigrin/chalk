sub f { my ($p,$q) = @_; $q->(); $p + $_[0] } my $x = 1; print f($x, sub { $x = 5 }), "\n";
