our %c; for my $w (qw(a b a c a)) { $c{$w}++ } print join(",",map{"$_$c{$w=$_}"} sort keys %c),"\n";
