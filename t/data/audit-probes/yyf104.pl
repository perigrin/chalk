my @a=(1,2,3,4); my $n=0; for (my $i=0; $i<@a; $i++) { pop @a if $i == 0; $n++ } print "$n\n";
