my %h; for my $k (qw(a b c)) { $h{$k} = sub { $k } } print join(",", map { $h{$_}->() } sort keys %h), "\n";
