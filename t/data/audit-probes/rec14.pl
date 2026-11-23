our $g=1; sub f { local $g=2; my $s=shift; my $n = "abc" x $s; substr($n, 10, 1) = "x"; 1 } eval { f(1) }; print "$g\n";
