my %seen; my @u=grep { !$seen{$_}++ } qw(a b a c b); print "@u ", join("", map { $seen{$_} } sort keys %seen), "\n";
