my @a=(1); my $w=sub { push @a,7 }; for (1..2) { print "@a|"; $w->() } print "\n";
