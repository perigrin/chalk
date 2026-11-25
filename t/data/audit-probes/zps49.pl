my @a=(1); my $r=\@a; for (1..2) { print "@a|"; push @$r,$_ } print "\n";
