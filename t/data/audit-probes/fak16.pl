my %seen; sub once { return $seen{$_[0]}++ ? 0 : 1 } my @r=map { once($_) } qw(a b a); print "@r\n";
