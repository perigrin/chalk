my %h; for my $w (qw(a b a c a)) { $h{$w}++ } my $s = ""; for my $k (sort keys %h) { $s .= "$k$h{$k}" } print "$s\n";
