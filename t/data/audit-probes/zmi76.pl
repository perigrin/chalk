my $s=join "", map { chr(ord($_)+1) } split //, "HAL"; my $n=ord("a"); my $h=hex("ff"); my $o=oct("755"); my $b=oct("0b11"); print "$s$n $h $o $b\n";
