my ($a1,$b1)=(1,2); sub t { my $c=shift; ($c ? $a1 : $b1) = 9 } t(1); t(0); print "$a1 $b1\n";
