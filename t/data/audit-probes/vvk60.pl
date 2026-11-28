my @a = (1, 2); for (@a) { my @t = map { $_ * 2 } @a; $_ = $t[0] } print "@a\n";
