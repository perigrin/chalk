my @f; my $i=0; while ($i<3) { my $v=$i++; push @f, sub { $v } } print join("", map { $_->() } @f), "\n";
