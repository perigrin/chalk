sub add { push @{$_[0]}, "n" } my @a = (1); my @r; for my $i (1..2) { push @r, join(",", @a); add(\@a) } print "@r\n";
