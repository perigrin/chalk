my @c; for (1..3) { push @c, sub { $_ } } my @o; for my $c (@c) { $_ = "z"; push @o, $c->() } print "@o\n";
