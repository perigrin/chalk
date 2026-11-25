my ($a1,$b1)=(1,2); my $c=0; my $r=\($c ? $a1 : $b1); $$r=5; print "$a1$b1\n";
