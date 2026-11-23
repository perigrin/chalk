my @a=(1,2,3); for my $x (@a) { push @a, 4 if $x==1; $x.="!" } print "@a\n";
