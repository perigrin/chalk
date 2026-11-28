my $x = 1; sub f { $x = 5; my $t = 0; $t += $_ for @_; $t } print f($x, $x), "\n";
