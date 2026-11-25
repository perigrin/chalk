my $x=1; sub rec { return if $_[1]>2; $_[0]++; rec($_[0],$_[1]+1) } rec($x,0); print "$x\n";
