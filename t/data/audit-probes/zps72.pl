my @a=(1,2,3); my $n=0; for my $x (@a) { $n++; push @a,9 if $n==1 } print "$n\n";
