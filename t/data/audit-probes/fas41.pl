my @q=(1,2,3); sub take { shift @q } my $s=""; while (defined(my $v=take())) { $s.=$v; push @q, 9 if $v==1 } print "$s\n";
