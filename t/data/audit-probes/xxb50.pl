my @a=(1,2,3); my @b = map { my $v = $_; map { $v * $_ } @a } @a; print "@b\n";
