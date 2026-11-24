our $g=1; sub f { local $g=2; sprintf("%d", 1/$_[0]) } my @r; for my $z (1,0,2) { push @r, eval { f($z) } // "E$g" } print "@r $g\n";
