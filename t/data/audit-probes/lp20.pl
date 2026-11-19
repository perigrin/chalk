my @a = (1,2,3); my $n = 0; for my $x (@a) { push @a, 9 if $n++ < 2 } print "$n @a\n";
