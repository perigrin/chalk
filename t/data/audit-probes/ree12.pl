my @a=([1],[2]); for my $r (@a) { push @$r, 9 } print join("|", map {"@$_"} @a), "\n";
