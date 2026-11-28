my @a = (1,2,3); my @b = (0, @a)[1, 2]; my $l = (0, @a)[-1]; print "@b$l\n";
