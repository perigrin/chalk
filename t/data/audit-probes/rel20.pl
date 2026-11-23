my @m=([1,2],[3,4]); my $t=0; for my $r (@m) { for my $c (@$r) { $t+=$c; $c=0 } } print "$t $m[1][1]\n";
