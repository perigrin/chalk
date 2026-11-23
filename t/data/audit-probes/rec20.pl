our $g=1; sub f { local $g=2; my $z=shift; int(1/$z) + 1 } my @r = map { eval { f($_) } // "e" } 0,1; print "@r $g\n";
