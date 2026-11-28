my @l = sub { return (1, 2) if $_[0]; (3) }->(1); my $c = sub { return (1, 2) if $_[0]; (3) }->(1); print "@l$c\n";
