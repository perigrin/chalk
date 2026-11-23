our $x=0; my @l; for my $k (1..3) { $x=$k; push @l, \$x } print join(",",map{$$_}@l),"\n";
