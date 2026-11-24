my @r; for my $s (qw(a1 b c3)) { $s=~/(\d)/; push @r, $1 // "u" } print "@r\n";
