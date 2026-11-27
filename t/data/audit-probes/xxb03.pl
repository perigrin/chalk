my @a=(1,2,3); for (@a) { $a[2] = 0 if $_ == 1; $_ += 10 } print "@a\n";
