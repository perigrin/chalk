our $g = 1; sub f { local $g = 2; die "d\n" if $_[0]; $g } my $v = eval { f(0) } . (eval { f(1) } // "U"); print "$v$g\n";
