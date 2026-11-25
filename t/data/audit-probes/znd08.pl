my @q=([1]); my $n=0; while (my $x=shift @q) { $n+=$x->[0]; push @q,[$x->[0]+1] if $x->[0]<3 } print "$n\n";
