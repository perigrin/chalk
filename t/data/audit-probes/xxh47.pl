sub f { my ($n) = @_; return 1 if $n < 2; my $l = f($n - 1); my $r = f($n - 2); $l + $r } print f(10), "\n";
