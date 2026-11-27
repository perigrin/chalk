my @a=(1,2,3); my $s = 0; for (@a) { $s += $_; $_ = $s } print "@a $s\n";
