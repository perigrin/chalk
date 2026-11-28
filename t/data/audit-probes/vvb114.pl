my %h = (a=>1, b=>2); my @c; for my $k (sort keys %h) { my $v = $h{$k}; push @c, sub { "$k$v" } } print join(",", map { $_->() } @c), "\n";
