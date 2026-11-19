my @o; sub DESTROY { push @o, "d" } { my $x = bless [], "main"; } print "@o\n";
