my @st; for my $i (1..3) { my %rec = (id => $i); $rec{sq} = $i * $i; push @st, \%rec } print join(",", map { "$_->{id}:$_->{sq}" } @st), "\n";
