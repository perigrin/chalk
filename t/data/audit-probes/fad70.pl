our $g=1; sub f { local $g=2; my $s = "a" x $_[0]; substr($s, 5, 1) = "z"; } eval { f(2) }; print "$g ", $@?1:0, "\n";
