my @a = (1, 2); my @l = map { my $o = $_; grep { $_ != $o } @a } @a; print "@l\n";
