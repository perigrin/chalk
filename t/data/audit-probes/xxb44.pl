my @a=(1,2,3); for (@a[grep { $_ != 1 } 0..2]) { $_ = 0 } print "@a\n";
