our $g = 1; sub b { $g++ } for my $i (1..3) { b(); local $g = $g + 10; next if $i == 2; print "$g\n"; } print "$g\n";
