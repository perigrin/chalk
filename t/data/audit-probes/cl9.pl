my @subs; for my $i (1..3) { my $j = $i; push @subs, sub { $j++ } } $subs[0]->(); print join(",", map { $_->() } @subs), "\n";
