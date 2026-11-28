my @a = (1,2,3); my @b; for (@a) { push @b, $_ * 2 } $_++ for @b; print "@a|@b\n";
