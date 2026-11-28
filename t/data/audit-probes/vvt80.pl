sub f { $_[0]{n}++ } my $t = 0; for my $i (1..3) { my %y; f(\%y); f(\%y) if $i > 1; $t += $y{n} } print "$t\n";
