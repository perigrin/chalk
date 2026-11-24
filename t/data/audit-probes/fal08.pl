my @a=(3,1,2); my @b; while (@a) { my $x=shift @a; push @b,$x; push @a,0 if $x==3 } print "@b\n";
