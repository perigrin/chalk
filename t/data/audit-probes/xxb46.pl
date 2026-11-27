my @a=([1],[2]); for my $r (@a) { push @$r, 0 } print join("|", map {"@$_"} @a), "\n";
