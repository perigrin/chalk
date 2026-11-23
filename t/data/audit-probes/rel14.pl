my @a=(1,2,3); my $c=0; while (my $x=shift @a) { $c+=$x; push @a,10 if $x==1 } print "$c\n";
