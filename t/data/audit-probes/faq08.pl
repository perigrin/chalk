my @r; for my $s (qw(a1 b c3)) { push @r, $1 if $s=~/(\d)/ } print "@r\n";
