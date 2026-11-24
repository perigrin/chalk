our %c; my $m=0; for my $w (qw(a b a c a)) { $c{$w}++; $m=$c{$w} if $c{$w}>$m } print "$m\n";
