my @o; for my $i (1..3) { my @t=($i); push @t,0 if $i==2; push @o, scalar(@t) } print "@o\n";
