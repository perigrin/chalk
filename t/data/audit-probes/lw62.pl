sub f { my @a = @_; my @r; for my $i (1..2) { push @r, "@a"; $_ .= "x" for @a } "@r" } print f(1,2), "\n";
