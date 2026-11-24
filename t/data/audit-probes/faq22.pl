my @o; for my $s (qw(a1 b2)) { if ($s=~/([a-z])(\d)/) { push @o, "$2$1" } } print "@o\n";
