my @a = (1,2,3); my @b = (4,5,6); my @z = map { $a[$_] * $b[$_] } 0..$#a; my $dot = 0; $dot += $_ for @z; my @il = map { ($a[$_], $b[$_]) } 0..$#a; my %hz; @hz{@a} = @b; print "@z|$dot|@il|$hz{2}\n";
