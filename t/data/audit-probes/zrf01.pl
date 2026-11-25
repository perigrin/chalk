my @a=(1,2); my @refs; for my $x (@a) { push @refs,\$x } $$_++ for @refs; print "@a\n";
