my $s=""; for my $w (qw(a1 b2)) { $s .= $1 if $w =~ /(\d)/ } print "$s\n";
