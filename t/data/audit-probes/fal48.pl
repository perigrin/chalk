my @f; for my $i (1..2) { my @l=($i); push @f, sub { push @l,9; scalar @l } } $f[0]->(); print $f[0]->(), $f[1]->(), "\n";
