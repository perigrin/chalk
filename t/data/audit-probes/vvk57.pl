my @a = (1, 2); my @l = map { my $o = $_; map { "$o$_" } @a } @a; print "@l\n";
