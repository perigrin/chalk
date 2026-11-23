my @o; for my $i (1..3) { my %t; $t{$i}=1; $t{x}=1 if $i==2; push @o, scalar(keys %t) } print "@o\n";
