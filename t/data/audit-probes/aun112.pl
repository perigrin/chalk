my @a=(1,2); my ($x) = grep { $_ == 1 } @a; $a[0]=7; print "$x\n";
