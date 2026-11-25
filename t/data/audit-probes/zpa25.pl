my ($a1,$b1)=(1,2); my $c=1; sub inc { $_[0]++ } inc($c ? $a1 : $b1); print "$a1$b1\n";
