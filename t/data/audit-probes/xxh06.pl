sub f { my $p = shift; my $q = shift; $q->(); "$p" } my $x = 1; print f($x, sub { $x = 5 }), "\n";
