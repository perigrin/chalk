my %seen; my @u = grep { !$seen{$_}{x}++ } qw(a a b); print "@u ", scalar(keys %seen), "\n";
