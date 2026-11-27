our $g = 1; my $i = 0; { local $g = 2; $i++; redo if $i < 3; } print "$i$g\n";
