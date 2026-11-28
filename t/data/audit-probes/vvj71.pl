my @a = ([1,2],[3,4]); for my $r (@a) { for my $e (@$r) { $e *= 2 } } print join(",", map { @$_ } @a), "\n";
