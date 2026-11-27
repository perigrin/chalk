my %h; my @o; for my $w (qw(a b a)) { push @o, $w unless $h{$w}++ } print "@o$h{a}\n";
