sub ap { push @{$_[0]}, $_[1]; $_[0] } my @a; ap(ap(\@a, 1), 2); print "@a\n";
