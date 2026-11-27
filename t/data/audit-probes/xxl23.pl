my %h; for my $w (qw(a b a)) { push @{ $h{$w} }, scalar keys %h } print join("|", map { "@{$h{$_}}" } sort keys %h), "\n";
