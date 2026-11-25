my $n=0; my @l=(1,2,3); my @g = grep { $n++; $_ > 1 } @l; print "$n @g\n";
