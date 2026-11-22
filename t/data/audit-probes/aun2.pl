our $g=0; sub bump{$g+=10} for my $i (1..3) { $g .= ""; bump() } print "$g\n";
