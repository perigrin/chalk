my @l = (1,2); my $c = sub { $_++ }; for (@l) { $c->() } print "@l\n";
